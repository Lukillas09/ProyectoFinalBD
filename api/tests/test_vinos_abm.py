"""POST, PUT y DELETE de /vinos contra la base cargada (issue #26).

Cada prueba crea sus propios vinos por la API, con un nombre único (fixture
``marca``). Ninguna modifica ni borra vinos del dataset: la única que los toca
intenta borrar uno con ventas y espera el rechazo. Los rechazos de reglas de
negocio vienen de PostgreSQL (CHECK, FK, constraint trigger diferido), no de
Python, y cada uno verifica con una consulta que no quedaron filas a medias.
"""

from decimal import Decimal

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
