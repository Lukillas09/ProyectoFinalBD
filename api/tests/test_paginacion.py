"""Paginación común: validación de parámetros y patrón de total (api/README.md)."""

import pytest


def test_valores_por_omision(cliente, consultar) -> None:
    cuerpo = cliente.get("/_prueba/localidades").json()

    assert (cuerpo["limite"], cuerpo["desplazamiento"]) == (20, 0)
    assert len(cuerpo["items"]) == 20
    assert cuerpo["total"] == consultar("SELECT count(*) FROM localidad")


def test_segunda_pagina(cliente, consultar) -> None:
    cuerpo = cliente.get("/_prueba/localidades", params={"limite": 10, "desplazamiento": 10}).json()

    esperado = consultar(
        "SELECT array_agg(id_localidad ORDER BY id_localidad) FROM "
        "(SELECT id_localidad FROM localidad ORDER BY id_localidad LIMIT 10 OFFSET 10) AS p")
    assert [fila["id_localidad"] for fila in cuerpo["items"]] == esperado


def test_desplazamiento_mayor_que_el_total(cliente, consultar) -> None:
    respuesta = cliente.get("/_prueba/localidades", params={"desplazamiento": 1000})

    assert respuesta.status_code == 200
    assert respuesta.json()["items"] == []
    assert respuesta.json()["total"] == consultar("SELECT count(*) FROM localidad")


@pytest.mark.parametrize(
    ("parametros", "campo"),
    [
        ({"limite": 0}, "query.limite"),
        ({"limite": 101}, "query.limite"),
        ({"limite": -1}, "query.limite"),
        ({"desplazamiento": -1}, "query.desplazamiento"),
        ({"limite": "veinte"}, "query.limite"),
    ],
)
def test_parametros_fuera_de_rango_422(cliente, parametros, campo) -> None:
    respuesta = cliente.get("/_prueba/localidades", params=parametros)

    assert respuesta.status_code == 422
    cuerpo = respuesta.json()
    assert (cuerpo["detail"], cuerpo["codigo"]) == ("Datos de entrada inválidos.", "validacion")
    assert [error["campo"] for error in cuerpo["errores"]] == [campo]
