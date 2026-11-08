"""POST, PUT y DELETE de /vinos contra la base cargada (issue #26).

Cada prueba crea sus propios vinos por la API, con un nombre único (fixture
``marca``). Ninguna modifica ni borra vinos del dataset: la única que los toca
intenta borrar uno con ventas y espera el rechazo. Los rechazos de reglas de
negocio vienen de PostgreSQL (CHECK, FK, constraint trigger diferido), no de
Python, y cada uno verifica con una consulta que no quedaron filas a medias.
"""

import os
from decimal import Decimal

import httpx
import pytest


@pytest.fixture(scope="module")
def catalogo(consultar_filas) -> dict:
    """Bodega, dos cepas y dos maridajes existentes, buscados en el dataset."""

    return {
        "cuit": consultar_filas("SELECT min(cuit) FROM bodega")[0][0],
        "cepas": [f[0] for f in consultar_filas("SELECT id_cepa FROM cepa ORDER BY id_cepa LIMIT 3")],
        "maridajes": [f[0] for f in consultar_filas(
            "SELECT id_maridaje FROM maridaje ORDER BY id_maridaje LIMIT 2")],
    }


@pytest.fixture
def cuerpo(marca: str, catalogo: dict) -> dict:
    """Un vino válido: corte 60/40 y dos maridajes."""

    return {
        "nombre": "Vino " + marca,
        "tipo": "tinto",
        "anada": 2024,
        "volumen_ml": 750,
        "graduacion": "13.50",
        "precio": "1000.00",
        "cuit_bodega": catalogo["cuit"],
        "composicion": [
            {"id_cepa": catalogo["cepas"][0], "porcentaje": "60.00"},
            {"id_cepa": catalogo["cepas"][1], "porcentaje": "40.00"},
        ],
        "maridajes": catalogo["maridajes"],
    }


def crear(cliente, cuerpo: dict) -> int:
    respuesta = cliente.post("/vinos", json=cuerpo)
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()["cod_vino"]


def vinos_con_nombre(consultar, nombre: str) -> int:
    return consultar("SELECT count(*) FROM vino WHERE nombre = %s", (nombre,))


def composicion_en_la_base(consultar_filas, cod_vino: int) -> set[tuple[int, str]]:
    # porcentaje::text: se compara como texto, sin pasar por float.
    return set(consultar_filas(
        "SELECT id_cepa, porcentaje::text FROM composicion_vino WHERE cod_vino = %s", (cod_vino,)))


# --- Alta -------------------------------------------------------------------

def test_alta_correcta(cliente, consultar_filas, cuerpo) -> None:
    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 201, respuesta.text
    ficha = respuesta.json()
    cod = ficha["cod_vino"]
    assert respuesta.headers["location"] == f"/vinos/{cod}"
    for campo in ("nombre", "tipo", "anada", "volumen_ml", "graduacion", "precio", "cuit_bodega"):
        assert ficha[campo] == cuerpo[campo], campo
    assert ficha["stock_total"] == 0
    enviada = {(c["id_cepa"], c["porcentaje"]) for c in cuerpo["composicion"]}
    assert {(c["id_cepa"], c["porcentaje"]) for c in ficha["composicion"]} == enviada
    assert {m["id_maridaje"] for m in ficha["maridajes"]} == set(cuerpo["maridajes"])
    # Y en la base, no sólo en la respuesta.
    assert composicion_en_la_base(consultar_filas, cod) == enviada
    assert {f[0] for f in consultar_filas(
        "SELECT id_maridaje FROM vino_maridaje WHERE cod_vino = %s", (cod,))} == set(cuerpo["maridajes"])
    # La ficha del alta es la misma que la del GET.
    assert cliente.get(f"/vinos/{cod}").json() == ficha


def test_alta_sin_usage_sobre_la_secuencia(cliente, consultar, cuerpo) -> None:
    # cod_vino es IDENTITY. bodegas_api no tiene USAGE sobre su secuencia ni
    # puede llamar a nextval(), y aun así el alta funciona: el valor por
    # omisión de una columna IDENTITY no verifica ese privilegio.
    secuencia = consultar("SELECT pg_get_serial_sequence('bodegas.vino', 'cod_vino')")
    assert consultar("SELECT current_user") == "bodegas_api"
    assert consultar("SELECT has_sequence_privilege(%s, 'USAGE')", (secuencia,)) is False
    assert consultar("SELECT has_sequence_privilege(%s, 'UPDATE')", (secuencia,)) is False

    assert cliente.post("/vinos", json=cuerpo).status_code == 201


def test_composicion_que_suma_90_no_deja_el_vino(cliente, consultar, cuerpo) -> None:
    cuerpo["composicion"][1]["porcentaje"] = "30.00"

    respuesta = cliente.post("/vinos", json=cuerpo)

    # El constraint trigger diferido falla en el COMMIT: P0001 con el mensaje
    # de la base, y el ROLLBACK se lleva también el vino y sus maridajes.
    assert respuesta.status_code == 409
    error = respuesta.json()
    assert error["codigo"] == "P0001"
    assert error["detail"].startswith("RN-05: la composición del vino ")
    assert "suma 90.00 %" in error["detail"]
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


@pytest.mark.parametrize(("campo", "valor", "restriccion"), [
    ("precio", "-100.00", "ck_vino_precio_positivo"),
    ("precio", "0.00", "ck_vino_precio_positivo"),
    ("graduacion", "25.00", "ck_vino_graduacion"),
    ("volumen_ml", 0, "ck_vino_volumen_positivo"),
])
def test_check_de_la_base_422(cliente, consultar, cuerpo, campo, valor, restriccion) -> None:
    # Pydantic no valida estos rangos: los rechaza el CHECK de PostgreSQL.
    cuerpo[campo] = valor

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 422
    assert respuesta.json() == {"detail": "Un valor no cumple una regla de validación.",
                                "codigo": "23514", "restriccion": restriccion}
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


def test_porcentaje_fuera_de_rango_422(cliente, consultar, cuerpo) -> None:
    cuerpo["composicion"] = [{"id_cepa": cuerpo["composicion"][0]["id_cepa"], "porcentaje": "150.00"}]

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert (respuesta.status_code, respuesta.json()["restriccion"]) == (422, "ck_composicion_vino_porcentaje")
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


def test_bodega_inexistente_422(cliente, consultar, cuerpo) -> None:
    cuerpo["cuit_bodega"] = "99999999999"

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 422
    assert respuesta.json() == {"detail": "El dato relacionado no existe.",
                                "codigo": "23503", "restriccion": "fk_vino_bodega"}
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


@pytest.mark.parametrize(("lista", "restriccion"), [
    ("composicion", "fk_composicion_vino_cepa"),
    ("maridajes", "fk_vino_maridaje_maridaje"),
])
def test_cepa_o_maridaje_inexistente_422(cliente, consultar, cuerpo, lista, restriccion) -> None:
    # El vino ya se insertó cuando falla la segunda o la tercera sentencia: la
    # transacción lo revierte.
    if lista == "composicion":
        inexistente = consultar("SELECT max(id_cepa) + 1000 FROM cepa")
        cuerpo["composicion"][1]["id_cepa"] = inexistente
    else:
        cuerpo["maridajes"] = [consultar("SELECT max(id_maridaje) + 1000 FROM maridaje")]

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 422
    assert (respuesta.json()["codigo"], respuesta.json()["restriccion"]) == ("23503", restriccion)
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


def test_vino_repetido_409(cliente, consultar, cuerpo) -> None:
    crear(cliente, cuerpo)

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 409
    assert respuesta.json() == {"detail": "Ya existe un registro con esos datos.",
                                "codigo": "23505", "restriccion": "uq_vino_identidad_comercial"}
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 1


def _sin(campo: str):
    def quitar(cuerpo: dict) -> None:
        del cuerpo[campo]
    return quitar


def _repetir_cepa(cuerpo: dict) -> None:
    cuerpo["composicion"][1]["id_cepa"] = cuerpo["composicion"][0]["id_cepa"]


@pytest.mark.parametrize(("cambio", "campo"), [
    (lambda c: c.update(composicion=[]), "body.composicion"),
    (_repetir_cepa, "body.composicion"),
    (lambda c: c.update(maridajes=[c["maridajes"][0]] * 2), "body.maridajes"),
    (lambda c: c.update(precio="1000.005"), "body.precio"),
    (lambda c: c.update(tipo="rojo"), "body.tipo"),
    (lambda c: c.update(cuit_bodega="123"), "body.cuit_bodega"),
    (_sin("maridajes"), "body.maridajes"),
], ids=["sin_cepas", "cepa_repetida", "maridaje_repetido", "precio_con_3_decimales",
        "tipo_invalido", "cuit_invalido", "falta_maridajes"])
def test_forma_invalida_422(cliente, consultar, cuerpo, cambio, campo) -> None:
    cambio(cuerpo)

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 422
    error = respuesta.json()
    assert error["codigo"] == "validacion"
    assert error["errores"][0]["campo"] == campo
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


def test_texto_con_caracteres_especiales_se_guarda_tal_cual(cliente, consultar, cuerpo, marca) -> None:
    # Demostración para el issue #34: el nombre viaja como parámetro, nunca
    # como texto del SQL. Se guarda tal cual y la tabla sigue existiendo.
    cuerpo["nombre"] = "Malbec '; DROP TABLE vino; -- " + marca

    respuesta = cliente.post("/vinos", json=cuerpo)

    assert respuesta.status_code == 201, respuesta.text
    cod = respuesta.json()["cod_vino"]
    assert respuesta.json()["nombre"] == cuerpo["nombre"]
    assert consultar("SELECT nombre FROM vino WHERE cod_vino = %s", (cod,)) == cuerpo["nombre"]
    assert consultar("SELECT to_regclass('bodegas.vino') IS NOT NULL") is True
    assert consultar("SELECT count(*) FROM vino") > 0


def test_decimal_como_numero_json(cliente, cuerpo) -> None:
    # También se aceptan números JSON; la respuesta los devuelve como string
    # con la escala de la columna.
    cuerpo["precio"] = 1234.5
    cuerpo["graduacion"] = 14

    ficha = cliente.post("/vinos", json=cuerpo).json()

    assert (ficha["precio"], ficha["graduacion"]) == ("1234.50", "14.00")
    assert Decimal(ficha["precio"]) == Decimal("1234.5")


# --- Modificación -----------------------------------------------------------

def auditoria(consultar_filas, cod_vino: int) -> list[tuple]:
    return consultar_filas(
        "SELECT precio_anterior::text, precio_nuevo::text, usuario_bd FROM auditoria_precio "
        "WHERE cod_vino = %s ORDER BY id_auditoria", (cod_vino,))


def test_put_que_cambia_el_precio_deja_una_auditoria(cliente, consultar, consultar_filas, cuerpo) -> None:
    cod = crear(cliente, cuerpo)
    cuerpo["precio"] = "1250.50"

    respuesta = cliente.put(f"/vinos/{cod}", json=cuerpo)

    assert respuesta.status_code == 200, respuesta.text
    assert respuesta.json()["precio"] == "1250.50"
    # La fila la escribe trg_vino_auditoria_precio, no la API. usuario_bd es
    # session_user: la cuenta con que se conecta la API, la misma de las pruebas.
    assert auditoria(consultar_filas, cod) == [("1000.00", "1250.50", consultar("SELECT session_user"))]


@pytest.mark.parametrize("mismo_precio", ["1000.00", "1000.0", 1000])
def test_put_sin_cambiar_el_precio_no_audita(cliente, consultar_filas, cuerpo, mismo_precio) -> None:
    # 1000.0 y 1000.00 son iguales en NUMERIC: el WHEN (OLD.precio IS
    # DISTINCT FROM NEW.precio) del trigger descarta el cambio inexistente.
    cod = crear(cliente, cuerpo)
    cuerpo["precio"] = mismo_precio
    cuerpo["nombre"] += " (editado)"

    respuesta = cliente.put(f"/vinos/{cod}", json=cuerpo)

    assert respuesta.status_code == 200, respuesta.text
    assert respuesta.json()["nombre"] == cuerpo["nombre"]
    assert auditoria(consultar_filas, cod) == []


def test_put_reemplaza_composicion_y_maridajes(cliente, consultar_filas, cuerpo, catalogo) -> None:
    cod = crear(cliente, cuerpo)
    cuerpo["composicion"] = [
        {"id_cepa": catalogo["cepas"][1], "porcentaje": "50.00"},
        {"id_cepa": catalogo["cepas"][2], "porcentaje": "50.00"},
    ]
    cuerpo["maridajes"] = []

    respuesta = cliente.put(f"/vinos/{cod}", json=cuerpo)

    assert respuesta.status_code == 200, respuesta.text
    nueva = {(catalogo["cepas"][1], "50.00"), (catalogo["cepas"][2], "50.00")}
    assert {(c["id_cepa"], c["porcentaje"]) for c in respuesta.json()["composicion"]} == nueva
    assert respuesta.json()["maridajes"] == []
    assert composicion_en_la_base(consultar_filas, cod) == nueva
    assert consultar_filas("SELECT count(*) FROM vino_maridaje WHERE cod_vino = %s", (cod,)) == [(0,)]


def test_put_con_composicion_que_suma_80_no_cambia_nada(cliente, consultar, consultar_filas, cuerpo, catalogo) -> None:
    cod = crear(cliente, cuerpo)
    anterior = composicion_en_la_base(consultar_filas, cod)
    cuerpo["precio"] = "2000.00"
    cuerpo["composicion"] = [{"id_cepa": catalogo["cepas"][2], "porcentaje": "80.00"}]

    respuesta = cliente.put(f"/vinos/{cod}", json=cuerpo)

    assert respuesta.status_code == 409
    assert respuesta.json()["codigo"] == "P0001"
    assert respuesta.json()["detail"].startswith(f"RN-05: la composición del vino {cod} suma 80.00 %")
    # El ROLLBACK se lleva todo el PUT: composición, precio y su auditoría.
    assert composicion_en_la_base(consultar_filas, cod) == anterior
    assert consultar("SELECT precio::text FROM vino WHERE cod_vino = %s", (cod,)) == "1000.00"
    assert auditoria(consultar_filas, cod) == []


def test_put_que_choca_con_otro_vino_409(cliente, cuerpo) -> None:
    crear(cliente, cuerpo)
    otro = {**cuerpo, "nombre": cuerpo["nombre"] + " (otro)"}
    cod_otro = crear(cliente, otro)

    respuesta = cliente.put(f"/vinos/{cod_otro}", json=cuerpo)

    assert respuesta.status_code == 409
    assert respuesta.json()["restriccion"] == "uq_vino_identidad_comercial"


def test_put_con_bodega_inexistente_422(cliente, consultar, cuerpo) -> None:
    cod = crear(cliente, cuerpo)
    cuerpo["cuit_bodega"] = "99999999999"

    respuesta = cliente.put(f"/vinos/{cod}", json=cuerpo)

    assert (respuesta.status_code, respuesta.json()["restriccion"]) == (422, "fk_vino_bodega")
    assert consultar("SELECT cuit_bodega FROM vino WHERE cod_vino = %s", (cod,)) != "99999999999"


def test_put_de_vino_inexistente_404(cliente, consultar, cuerpo) -> None:
    inexistente = consultar("SELECT max(cod_vino) + 1000 FROM vino")

    respuesta = cliente.put(f"/vinos/{inexistente}", json=cuerpo)

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": f"El vino {inexistente} no existe.", "codigo": "no_encontrado"}
    assert vinos_con_nombre(consultar, cuerpo["nombre"]) == 0


# --- Baja -------------------------------------------------------------------

def test_delete_de_vino_sin_historia_204(cliente, consultar, cuerpo) -> None:
    cod = crear(cliente, cuerpo)

    respuesta = cliente.delete(f"/vinos/{cod}")

    assert (respuesta.status_code, respuesta.content) == (204, b"")
    # La composición y los maridajes caen por ON DELETE CASCADE.
    assert consultar("SELECT count(*) FROM vino WHERE cod_vino = %s", (cod,)) == 0
    assert consultar("SELECT count(*) FROM composicion_vino WHERE cod_vino = %s", (cod,)) == 0
    assert consultar("SELECT count(*) FROM vino_maridaje WHERE cod_vino = %s", (cod,)) == 0
    assert cliente.get(f"/vinos/{cod}").status_code == 404


def test_delete_de_vino_inexistente_404(cliente, consultar) -> None:
    inexistente = consultar("SELECT max(cod_vino) + 1000 FROM vino")

    respuesta = cliente.delete(f"/vinos/{inexistente}")

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": f"El vino {inexistente} no existe.", "codigo": "no_encontrado"}


def test_delete_de_vino_con_ventas_409(cliente, consultar) -> None:
    # Único contacto con el dataset: el borrado tiene que fallar.
    con_ventas = consultar("SELECT min(cod_vino) FROM renglon_comprobante")

    respuesta = cliente.delete(f"/vinos/{con_ventas}")

    assert respuesta.status_code == 409
    assert respuesta.json() == {
        "detail": "No se puede borrar ni modificar: hay datos que dependen de este registro.",
        "codigo": "23503", "restriccion": "fk_renglon_comprobante_vino"}
    assert consultar("SELECT count(*) FROM vino WHERE cod_vino = %s", (con_ventas,)) == 1


def test_delete_de_vino_con_cambio_de_precio_409(cliente, consultar, cuerpo) -> None:
    # RN-14: la historia de precios no se pierde al borrar el vino.
    cod = crear(cliente, cuerpo)
    assert cliente.put(f"/vinos/{cod}", json={**cuerpo, "precio": "1100.00"}).status_code == 200

    respuesta = cliente.delete(f"/vinos/{cod}")

    assert respuesta.status_code == 409
    assert (respuesta.json()["codigo"], respuesta.json()["restriccion"]) == ("23503", "fk_auditoria_precio_vino")
    assert consultar("SELECT count(*) FROM vino WHERE cod_vino = %s", (cod,)) == 1
    assert consultar("SELECT count(*) FROM composicion_vino WHERE cod_vino = %s", (cod,)) == 2


# --- Swagger y HTTP real ----------------------------------------------------

def test_abm_en_openapi(cliente) -> None:
    rutas = cliente.get("/openapi.json").json()["paths"]

    codigos = {
        ("/vinos", "post"): {"201", "409", "422"},
        ("/vinos/{cod_vino}", "put"): {"200", "404", "409", "422"},
        ("/vinos/{cod_vino}", "delete"): {"204", "404", "409"},
    }
    for (ruta, metodo), esperados in codigos.items():
        operacion = rutas[ruta][metodo]
        assert operacion["tags"] == ["vinos"]
        assert esperados <= set(operacion["responses"]), (ruta, metodo)
    assert "cambió el precio no se puede borrar" in rutas["/vinos/{cod_vino}"]["delete"]["description"]


def test_alta_y_baja_por_nginx(cuerpo) -> None:
    # Como el front: por /api. Location trae el prefijo público.
    raiz = os.environ["FRONT_URL"] + "/api"

    alta = httpx.post(raiz + "/vinos", json=cuerpo, timeout=10)
    assert alta.status_code == 201, alta.text
    cod = alta.json()["cod_vino"]
    assert alta.headers["location"] == f"/api/vinos/{cod}"

    baja = httpx.delete(raiz + "/vinos/" + str(cod), timeout=10)
    assert baja.status_code == 204
    assert httpx.get(raiz + "/vinos/" + str(cod), timeout=10).status_code == 404
