"""GET /vinos y GET /vinos/{cod_vino} contra la base cargada (issue #25).

Los datos se buscan en el dataset con consultas como bodegas_api: los ids y
valores cambian con la carga, así que ninguna prueba los escribe fijos.
"""

import os
from decimal import Decimal

import httpx
import pytest


def todas_las_paginas(cliente, params: dict) -> tuple[list[dict], int]:
    """Recorre el listado completo de a 100 y devuelve los items y el total."""

    items, desplazamiento = [], 0
    while True:
        respuesta = cliente.get("/vinos", params={**params, "limite": 100, "desplazamiento": desplazamiento})
        assert respuesta.status_code == 200, respuesta.text
        pagina = respuesta.json()
        items += pagina["items"]
        desplazamiento += 100
        if desplazamiento >= pagina["total"]:
            return items, pagina["total"]


@pytest.fixture(scope="module")
def vino_de_corte(consultar_filas) -> tuple[int, list[int]]:
    """Un vino con dos o más cepas y los ids de esas cepas."""

    cod_vino = consultar_filas(
        "SELECT cod_vino FROM composicion_vino GROUP BY cod_vino HAVING count(*) >= 2 "
        "ORDER BY cod_vino LIMIT 1")[0][0]
    cepas = [fila[0] for fila in consultar_filas(
        "SELECT id_cepa FROM composicion_vino WHERE cod_vino = %s ORDER BY id_cepa", (cod_vino,))]
    return cod_vino, cepas


@pytest.fixture(scope="module")
def filtros_frecuentes(consultar, vino_de_corte) -> dict:
    """Un valor de cada filtro que tiene vinos en el dataset."""

    return {
        "tipo": "blanco",
        "cuit_bodega": consultar("SELECT cuit_bodega FROM vino GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1"),
        "anada": consultar("SELECT anada FROM vino GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1"),
        "id_cepa": vino_de_corte[1][0],
    }


# --- Listado ----------------------------------------------------------------

def test_listado_sin_filtros(cliente, consultar) -> None:
    respuesta = cliente.get("/vinos")

    assert respuesta.status_code == 200
    pagina = respuesta.json()
    assert set(pagina) == {"items", "limite", "desplazamiento", "total"}
    assert (pagina["limite"], pagina["desplazamiento"]) == (20, 0)
    assert len(pagina["items"]) == 20
    assert pagina["total"] == consultar("SELECT count(*) FROM vino")
    assert set(pagina["items"][0]) == {"cod_vino", "nombre", "tipo", "anada", "volumen_ml",
                                       "graduacion", "precio", "cuit_bodega", "bodega"}
    # Dinero como string con la escala de NUMERIC(14,2), sin pasar por float.
    precio = pagina["items"][0]["precio"]
    assert isinstance(precio, str) and Decimal(precio).as_tuple().exponent == -2


@pytest.mark.parametrize(
    ("filtro", "sql_esperados"),
    [
        ("tipo", "SELECT cod_vino FROM vino WHERE tipo = %s ORDER BY cod_vino"),
        ("cuit_bodega", "SELECT cod_vino FROM vino WHERE cuit_bodega = %s ORDER BY cod_vino"),
        ("anada", "SELECT cod_vino FROM vino WHERE anada = %s ORDER BY cod_vino"),
        ("id_cepa", "SELECT DISTINCT cod_vino FROM composicion_vino WHERE id_cepa = %s ORDER BY cod_vino"),
    ],
)
def test_cada_filtro_solo(cliente, consultar_filas, filtros_frecuentes, filtro, sql_esperados) -> None:
    valor = filtros_frecuentes[filtro]
    esperados = [fila[0] for fila in consultar_filas(sql_esperados, (valor,))]

    items, total = todas_las_paginas(cliente, {filtro: valor})

    assert total == len(esperados) > 0
    assert [item["cod_vino"] for item in items] == esperados
    if filtro != "id_cepa":
        assert all(item[filtro] == valor for item in items)


def test_filtros_combinados(cliente, consultar, consultar_filas) -> None:
    tipo, cuit_bodega, anada = consultar_filas(
        "SELECT tipo, cuit_bodega, anada FROM vino GROUP BY 1, 2, 3 ORDER BY count(*) DESC, 1, 2, 3 LIMIT 1")[0]
    esperado = consultar("SELECT count(*) FROM vino WHERE tipo = %s AND cuit_bodega = %s AND anada = %s",
                         (tipo, cuit_bodega, anada))

    items, total = todas_las_paginas(cliente, {"tipo": tipo, "cuit_bodega": cuit_bodega, "anada": anada})

    assert total == len(items) == esperado > 0
    assert all((i["tipo"], i["cuit_bodega"], i["anada"]) == (tipo, cuit_bodega, anada) for i in items)
    # Menos que cada filtro por separado: se combinan con AND.
    assert total < consultar("SELECT count(*) FROM vino WHERE tipo = %s", (tipo,))


def test_vino_de_corte_aparece_una_sola_vez(cliente, consultar, vino_de_corte) -> None:
    cod_vino, cepas = vino_de_corte

    for params in ({}, {"id_cepa": cepas[0]}, {"id_cepa": cepas[1]}):
        items, total = todas_las_paginas(cliente, params)
        codigos = [item["cod_vino"] for item in items]
        assert codigos.count(cod_vino) == 1, params
        assert len(codigos) == len(set(codigos)) == total
    # Un JOIN a composicion_vino sin el filtro devolvería una fila por cepa.
    assert consultar("SELECT count(*) FROM vino JOIN composicion_vino USING (cod_vino)") > \
        consultar("SELECT count(*) FROM vino")


def test_dos_paginas_consecutivas_sin_repetir(cliente) -> None:
    primera = cliente.get("/vinos", params={"limite": 5}).json()["items"]
    segunda = cliente.get("/vinos", params={"limite": 5, "desplazamiento": 5}).json()["items"]

    codigos = [item["cod_vino"] for item in primera + segunda]
    assert len(codigos) == 10
    assert codigos == sorted(set(codigos))


def test_desplazamiento_mayor_que_el_total_con_filtro(cliente, consultar) -> None:
    esperado = consultar("SELECT count(*) FROM vino WHERE tipo = 'rosado'")

    respuesta = cliente.get("/vinos", params={"tipo": "rosado", "desplazamiento": esperado + 50})

    assert respuesta.status_code == 200
    assert respuesta.json() == {"items": [], "limite": 20, "desplazamiento": esperado + 50, "total": esperado}


@pytest.mark.parametrize(
    ("params", "campo"),
    [
        ({"tipo": "rojo"}, "query.tipo"),
        ({"anada": "abc"}, "query.anada"),
        ({"anada": 1800}, "query.anada"),
        ({"cuit_bodega": "123"}, "query.cuit_bodega"),
        ({"cuit_bodega": "3050000000a"}, "query.cuit_bodega"),
        ({"id_cepa": 0}, "query.id_cepa"),
    ],
)
def test_filtro_invalido_422(cliente, params, campo) -> None:
    respuesta = cliente.get("/vinos", params=params)

    assert respuesta.status_code == 422
    cuerpo = respuesta.json()
    assert cuerpo["codigo"] == "validacion"
    assert [error["campo"] for error in cuerpo["errores"]] == [campo]


def test_texto_malicioso_en_un_filtro_no_llega_a_la_base(cliente) -> None:
    respuesta = cliente.get("/vinos", params={"tipo": "tinto' OR '1'='1"})

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"
    assert "items" not in respuesta.json()


# --- Ficha ------------------------------------------------------------------

@pytest.fixture(scope="module")
def vino_con_stock(consultar) -> int:
    """Un vino de corte con stock en el depósito y en al menos una sala."""

    return consultar(
        "SELECT d.cod_vino FROM stock_deposito d "
        "WHERE d.cantidad > 0 "
        "  AND EXISTS (SELECT 1 FROM stock_sala s WHERE s.cod_vino = d.cod_vino AND s.cantidad > 0) "
        "  AND (SELECT count(*) FROM composicion_vino c WHERE c.cod_vino = d.cod_vino) >= 2 "
        "ORDER BY d.cod_vino LIMIT 1")


def test_ficha_coincide_con_la_base(cliente, consultar, consultar_filas, vino_con_stock) -> None:
    cod_vino = vino_con_stock
    respuesta = cliente.get(f"/vinos/{cod_vino}")

    assert respuesta.status_code == 200
    ficha = respuesta.json()
    nombre, precio, razon_social = consultar_filas(
        "SELECT v.nombre, v.precio::text, b.razon_social FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega "
        "WHERE v.cod_vino = %s", (cod_vino,))[0]
    assert (ficha["cod_vino"], ficha["nombre"], ficha["precio"], ficha["bodega"]) == \
        (cod_vino, nombre, precio, razon_social)

    # Composición estructurada: igual a composicion_vino (porcentajes como texto,
    # sin floats), de mayor a menor, y suma 100.
    composicion = consultar_filas(
        "SELECT c.id_cepa, ce.nombre, ce.tipo, c.porcentaje::text FROM composicion_vino c "
        "JOIN cepa ce ON ce.id_cepa = c.id_cepa WHERE c.cod_vino = %s "
        "ORDER BY c.porcentaje DESC, ce.nombre", (cod_vino,))
    assert [(c["id_cepa"], c["cepa"], c["tipo_cepa"], c["porcentaje"]) for c in ficha["composicion"]] == \
        [tuple(fila) for fila in composicion]
    assert len(ficha["composicion"]) >= 2
    assert sum(Decimal(c["porcentaje"]) for c in ficha["composicion"]) == 100

    maridajes = consultar_filas(
        "SELECT m.id_maridaje, m.nombre, m.temperatura_servicio_c::text FROM vino_maridaje vm "
        "JOIN maridaje m ON m.id_maridaje = vm.id_maridaje WHERE vm.cod_vino = %s ORDER BY m.nombre",
        (cod_vino,))
    assert [(m["id_maridaje"], m["nombre"], m["temperatura_servicio_c"]) for m in ficha["maridajes"]] == \
        [tuple(fila) for fila in maridajes]

    # Stock calculado directo de las tablas, no de la vista que usa la API.
    stock = consultar(
        "SELECT (SELECT cantidad FROM stock_deposito WHERE cod_vino = %s) "
        "     + (SELECT sum(cantidad) FROM stock_sala WHERE cod_vino = %s)", (cod_vino, cod_vino))
    assert ficha["stock_total"] == stock > 0


def test_ficha_de_vino_inexistente_404(cliente, consultar) -> None:
    cod_vino = consultar("SELECT max(cod_vino) + 1000 FROM vino")

    respuesta = cliente.get(f"/vinos/{cod_vino}")

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": f"El vino {cod_vino} no existe.", "codigo": "no_encontrado"}


@pytest.mark.parametrize("cod_vino", ["abc", "0", "9223372036854775808"])
def test_ficha_con_codigo_invalido_422(cliente, cod_vino) -> None:
    respuesta = cliente.get(f"/vinos/{cod_vino}")

    assert respuesta.status_code == 422
    assert respuesta.json()["errores"][0]["campo"] == "path.cod_vino"


# --- OpenAPI ----------------------------------------------------------------

def test_vinos_en_openapi(cliente) -> None:
    esquema = cliente.get("/openapi.json").json()

    assert esquema["paths"]["/vinos"]["get"]["tags"] == ["vinos"]
    assert esquema["paths"]["/vinos/{cod_vino}"]["get"]["tags"] == ["vinos"]
    assert "vinos" in [etiqueta["name"] for etiqueta in esquema["tags"]]
    parametros = {p["name"]: p for p in esquema["paths"]["/vinos"]["get"]["parameters"]}
    assert set(parametros) == {"tipo", "id_cepa", "cuit_bodega", "anada", "limite", "desplazamiento"}
    # El dinero se publica como string.
    assert esquema["components"]["schemas"]["VinoResumen"]["properties"]["precio"]["type"] == "string"


@pytest.mark.parametrize("base", ["API_URL", "FRONT_URL"])
def test_vinos_por_http_real(base: str, vino_con_stock: int) -> None:
    # Contra la API del servicio api, directo y por nginx (/api), como el front.
    raiz = os.environ[base] + ("/api" if base == "FRONT_URL" else "")

    listado = httpx.get(raiz + "/vinos", params={"limite": 1}, timeout=10)
    ficha = httpx.get(raiz + "/vinos/" + str(vino_con_stock), timeout=10)

    assert (listado.status_code, len(listado.json()["items"])) == (200, 1)
    assert (ficha.status_code, ficha.json()["cod_vino"]) == (200, vino_con_stock)
