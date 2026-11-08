"""GET /vinos y GET /vinos/{cod_vino} contra la base cargada (issue #25).

Los datos se buscan en el dataset con consultas como bodegas_api: los ids y
valores cambian con la carga, así que ninguna prueba los escribe fijos.
"""

from decimal import Decimal

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

