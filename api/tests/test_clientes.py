"""CRUD de clientes de los tres tipos (issue #27).

La fixture ``cliente`` es el cliente HTTP (conftest.py); los clientes de la
base se llaman acá por su tipo o por su id. Los datos del dataset se buscan
con consultas como bodegas_api y ninguna prueba los escribe fijos. Cada
prueba que escribe crea sus propios clientes con la ``marca`` de la prueba:
ninguna modifica ni borra clientes de la carga.
"""

from decimal import Decimal

import pytest


TIPOS = ["socio", "distribuidor", "exportador"]
DESCUENTO_BASE = {"socio": "10.00", "distribuidor": "20.00", "exportador": "30.00"}


# --- Listado ----------------------------------------------------------------

@pytest.mark.parametrize("tipo", TIPOS)
def test_listado_por_tipo(cliente, consultar, consultar_filas, tipo) -> None:
    respuesta = cliente.get("/clientes", params={"tipo": tipo, "limite": 100})

    assert respuesta.status_code == 200, respuesta.text
    pagina = respuesta.json()
    assert pagina["total"] == consultar("SELECT count(*) FROM cliente WHERE tipo = %s", (tipo,))
    esperados = [f[0] for f in consultar_filas(
        "SELECT id_cliente FROM cliente WHERE tipo = %s ORDER BY id_cliente LIMIT 100", (tipo,))]
    assert [c["id_cliente"] for c in pagina["items"]] == esperados
    assert {c["tipo"] for c in pagina["items"]} == {tipo}
    assert set(pagina["items"][0]) == {"id_cliente", "nombre_razon_social", "tipo_documento",
                                       "nro_documento", "tipo", "id_localidad", "localidad"}


def test_listado_por_localidad_y_combinado(cliente, consultar) -> None:
    id_localidad = consultar("SELECT id_localidad FROM cliente GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1")

    solo = cliente.get("/clientes", params={"id_localidad": id_localidad}).json()
    combinado = cliente.get("/clientes", params={"id_localidad": id_localidad, "tipo": "socio"}).json()

    assert solo["total"] == consultar("SELECT count(*) FROM cliente WHERE id_localidad = %s", (id_localidad,))
    assert {c["id_localidad"] for c in solo["items"]} == {id_localidad}
    assert combinado["total"] == consultar(
        "SELECT count(*) FROM cliente WHERE id_localidad = %s AND tipo = 'socio'", (id_localidad,))
    assert {(c["id_localidad"], c["tipo"]) for c in combinado["items"]} == {(id_localidad, "socio")}


@pytest.mark.parametrize("params", [{"tipo": "mayorista"}, {"id_localidad": 0}, {"id_localidad": "abc"}])
def test_filtro_invalido_422(cliente, params) -> None:
    respuesta = cliente.get("/clientes", params=params)

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"


# --- Ficha ------------------------------------------------------------------

@pytest.mark.parametrize("tipo", TIPOS)
def test_ficha_de_un_cliente_de_la_carga(cliente, consultar, consultar_filas, tipo) -> None:
    id_cliente = consultar("SELECT min(id_cliente) FROM cliente WHERE tipo = %s", (tipo,))

    respuesta = cliente.get(f"/clientes/{id_cliente}")

    assert respuesta.status_code == 200, respuesta.text
    ficha = respuesta.json()
    assert ficha["id_cliente"] == id_cliente and ficha["tipo"] == tipo
    # El descuento lo calcula la base; la API sólo lo muestra.
    assert Decimal(ficha["descuento"]) == consultar("SELECT fn_descuento_cliente(%s)", (id_cliente,))
    assert ficha["fecha_alta"] == str(consultar("SELECT fecha_alta FROM cliente WHERE id_cliente = %s",
                                                (id_cliente,)))
    comunes = {"id_cliente", "nombre_razon_social", "tipo_documento", "nro_documento", "direccion",
               "id_localidad", "localidad", "fecha_alta", "tipo", "descuento"}
    propios = {"socio": set(), "distribuidor": {"zona_cobertura", "nro_habilitacion"},
               "exportador": {"pais_destino_principal", "permisos"}}
    assert set(ficha) == comunes | propios[tipo]
    if tipo == "distribuidor":
        assert ficha["nro_habilitacion"] == consultar(
            "SELECT nro_habilitacion FROM distribuidor WHERE id_cliente = %s", (id_cliente,))
    if tipo == "exportador":
        assert [p["codigo_permiso"] for p in ficha["permisos"]] == [f[0] for f in consultar_filas(
            "SELECT codigo_permiso FROM permiso_exportacion WHERE id_exportador = %s "
            "ORDER BY fecha_emision, codigo_permiso", (id_cliente,))]


def test_ficha_de_cliente_inexistente_404(cliente) -> None:
    respuesta = cliente.get("/clientes/999999999")

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": "El cliente 999999999 no existe.", "codigo": "no_encontrado"}


# --- Alta -------------------------------------------------------------------

# Una consulta completa por tipo, sin armar SQL con texto.
FILAS_DEL_SUBTIPO = {
    "socio": "SELECT count(*) FROM socio_club WHERE id_cliente = %s",
    "distribuidor": "SELECT count(*) FROM distribuidor WHERE id_cliente = %s",
    "exportador": "SELECT count(*) FROM exportador WHERE id_cliente = %s",
}
PERMISOS_EN_LA_BASE = (
    "SELECT codigo_permiso FROM permiso_exportacion WHERE id_exportador = %s ORDER BY codigo_permiso")


@pytest.fixture
def cuerpo(consultar, marca):
    """Arma el cuerpo válido de un cliente del tipo pedido, único por prueba."""

    id_localidad = consultar("SELECT min(id_localidad) FROM localidad")

    def armar(tipo: str, permisos: int = 2) -> dict:
        datos = {"tipo": tipo, "nombre_razon_social": f"Cliente {marca}",
                 "tipo_documento": "DNI" if tipo == "socio" else "CUIT", "nro_documento": marca,
                 "direccion": "Calle 1", "id_localidad": id_localidad}
        if tipo == "distribuidor":
            datos |= {"zona_cobertura": "Sur de Mendoza", "nro_habilitacion": f"HAB-{marca}"}
        if tipo == "exportador":
            datos |= {"pais_destino_principal": "Brasil", "permisos": [
                {"codigo_permiso": f"{marca}-{i}", "fecha_emision": "2025-01-01",
                 "fecha_vencimiento": "2027-01-01"} for i in range(1, permisos + 1)]}
        return datos

    return armar


def crear(cliente, datos: dict) -> int:
    respuesta = cliente.post("/clientes", json=datos)
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()["id_cliente"]


def clientes_con_documento(consultar, nro_documento: str) -> int:
    return consultar("SELECT count(*) FROM cliente WHERE nro_documento = %s", (nro_documento,))


@pytest.mark.parametrize("tipo", TIPOS)
def test_alta_de_cada_tipo(cliente, consultar, consultar_filas, cuerpo, marca, tipo) -> None:
    respuesta = cliente.post("/clientes", json=cuerpo(tipo))

    assert respuesta.status_code == 201, respuesta.text
    ficha = respuesta.json()
    id_cliente = ficha["id_cliente"]
    assert respuesta.headers["location"] == f"/clientes/{id_cliente}"
    assert ficha["tipo"] == tipo and ficha["nro_documento"] == marca
    assert ficha["descuento"] == DESCUENTO_BASE[tipo]
    assert ficha["fecha_alta"] == str(consultar("SELECT current_date"))
    assert consultar(FILAS_DEL_SUBTIPO[tipo], (id_cliente,)) == 1
    if tipo == "exportador":
        codigos = [f"{marca}-1", f"{marca}-2"]
        assert [f[0] for f in consultar_filas(PERMISOS_EN_LA_BASE, (id_cliente,))] == codigos
        assert [p["codigo_permiso"] for p in ficha["permisos"]] == codigos
    assert cliente.get(f"/clientes/{id_cliente}").json() == ficha


def test_el_descuento_enviado_se_ignora(cliente, consultar, cuerpo) -> None:
    # El descuento no viaja en el cuerpo: lo calcula fn_descuento_cliente.
    datos = cuerpo("exportador") | {"descuento": "50.00", "descuento_excepcion": "35.00"}

    respuesta = cliente.post("/clientes", json=datos)

    assert respuesta.status_code == 201, respuesta.text
    assert respuesta.json()["descuento"] == "30.00"
    assert consultar("SELECT descuento_excepcion FROM cliente WHERE id_cliente = %s",
                     (respuesta.json()["id_cliente"],)) is None


def test_documento_repetido_409(cliente, consultar, cuerpo, marca) -> None:
    crear(cliente, cuerpo("socio"))

    respuesta = cliente.post("/clientes", json=cuerpo("socio") | {"nombre_razon_social": "Otro nombre"})

    assert respuesta.status_code == 409
    assert respuesta.json() == {"detail": "Ya existe un registro con esos datos.", "codigo": "23505",
                                "restriccion": "uq_cliente_documento"}
    assert clientes_con_documento(consultar, marca) == 1


def test_distribuidor_sin_nro_habilitacion_422(cliente, consultar, cuerpo, marca) -> None:
    datos = cuerpo("distribuidor")
    del datos["nro_habilitacion"]

    respuesta = cliente.post("/clientes", json=datos)

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"
    assert [e["campo"] for e in respuesta.json()["errores"]] == ["body.distribuidor.nro_habilitacion"]
    assert clientes_con_documento(consultar, marca) == 0


def _sin(campo: str):
    return lambda datos: {k: v for k, v in datos.items() if k != campo}


def _permiso_repetido(datos: dict) -> dict:
    return datos | {"permisos": [datos["permisos"][0], datos["permisos"][0]]}


def _fecha_mal_formada(datos: dict) -> dict:
    return datos | {"permisos": [datos["permisos"][0] | {"fecha_emision": "2025-13-01"}]}


@pytest.mark.parametrize(
    ("tipo", "cambiar"),
    [
        pytest.param("socio", lambda d: d | {"tipo": "mayorista"}, id="tipo-inexistente"),
        pytest.param("socio", _sin("tipo"), id="sin-tipo"),
        pytest.param("socio", lambda d: d | {"nombre_razon_social": ""}, id="nombre-vacio"),
        pytest.param("socio", lambda d: d | {"id_localidad": 0}, id="localidad-0"),
        pytest.param("exportador", _permiso_repetido, id="permiso-repetido"),
        pytest.param("exportador", _fecha_mal_formada, id="fecha-mal-formada"),
        pytest.param("exportador", _sin("permisos"), id="sin-permisos"),
    ],
)
def test_forma_invalida_422(cliente, consultar, cuerpo, marca, tipo, cambiar) -> None:
    respuesta = cliente.post("/clientes", json=cambiar(cuerpo(tipo)))

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["codigo"] == "validacion"
    assert clientes_con_documento(consultar, marca) == 0


def _habilitacion_existente(datos: dict, consultar) -> dict:
    return datos | {"nro_habilitacion": consultar("SELECT min(nro_habilitacion) FROM distribuidor")}


def _fechas_invertidas(datos: dict, consultar) -> dict:
    return datos | {"permisos": [datos["permisos"][0] | {"fecha_vencimiento": "2024-01-01"}]}


def _permiso_de_otro(datos: dict, consultar) -> dict:
    otro = consultar("SELECT min(codigo_permiso) FROM permiso_exportacion")
    return datos | {"permisos": [datos["permisos"][0], datos["permisos"][1] | {"codigo_permiso": otro}]}


def _localidad_inexistente(datos: dict, consultar) -> dict:
    return datos | {"id_localidad": consultar("SELECT max(id_localidad) + 1000 FROM localidad")}


@pytest.mark.parametrize(
    ("tipo", "cambiar", "estado", "codigo", "restriccion"),
    [
        pytest.param("distribuidor", _habilitacion_existente, 409, "23505", "uq_distribuidor_habilitacion",
                     id="habilitacion-repetida"),
        pytest.param("exportador", _fechas_invertidas, 422, "23514", "ck_permiso_exportacion_fechas",
                     id="permiso-vence-antes"),
        pytest.param("exportador", _permiso_de_otro, 409, "23505", "pk_permiso_exportacion",
                     id="permiso-de-otro-exportador"),
        pytest.param("socio", _localidad_inexistente, 422, "23503", "fk_cliente_localidad",
                     id="localidad-inexistente"),
    ],
)
def test_alta_fallida_no_deja_el_cliente_sin_subtipo(cliente, consultar, cuerpo, marca, tipo, cambiar,
                                                     estado, codigo, restriccion) -> None:
    # El cliente se inserta antes que el subtipo y los permisos: si después
    # falla una de esas inserciones, el ROLLBACK de la transacción se lo lleva.
    respuesta = cliente.post("/clientes", json=cambiar(cuerpo(tipo), consultar))

    assert respuesta.status_code == estado, respuesta.text
    assert (respuesta.json()["codigo"], respuesta.json()["restriccion"]) == (codigo, restriccion)
    assert clientes_con_documento(consultar, marca) == 0


def test_exclusividad_por_la_fk_compuesta(error_de_la_base, consultar, marca) -> None:
    # Directo en la base, como bodegas_api: la API nunca inserta un subtipo
    # distinto del tipo del cuerpo, pero la base lo impediría igual.
    error = error_de_la_base("subtipo_ajeno")

    assert error.sqlstate == "23503"
    assert error.diag.constraint_name == "fk_distribuidor_cliente"
    assert clientes_con_documento(consultar, marca[-10:]) == 0
