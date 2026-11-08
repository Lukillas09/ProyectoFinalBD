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
TABLA_DEL_SUBTIPO = {"socio": "socio_club", "distribuidor": "distribuidor", "exportador": "exportador"}
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
