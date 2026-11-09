"""Transferencias: alta, renglones, terminar y procesar (issue #29).

Corren con api/tests/ejecutar.sh, contra un proyecto aislado y cargado, como
bodegas_api. Sala y vinos se buscan en el dataset; cada prueba crea sus
propias transferencias por la API, así no depende del estado de otras.
"""

from typing import Any, Callable

import pytest
from fastapi.testclient import TestClient


# Un número válido para BIGINT que ninguna transferencia de la carga alcanza.
INEXISTENTE = 9_000_000_000_000


def _sala(consultar: Callable[..., Any]) -> int:
    return consultar("SELECT min(id_sala) FROM sala_venta")


def _nueva(cliente: TestClient, id_sala: int) -> int:
    respuesta = cliente.post("/transferencias", json={"id_sala": id_sala})
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()["nro_transferencia"]


# --- Alta y consulta --------------------------------------------------------

def test_alta_en_confeccion_con_la_fecha_de_la_base(cliente, consultar) -> None:
    id_sala = _sala(consultar)

    # Estado y fecha enviados se ignoran: los fija la base (RN-11).
    respuesta = cliente.post("/transferencias", json={
        "id_sala": id_sala, "estado": "procesado", "fecha_confeccion": "2000-01-01"})

    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    assert datos["estado"] == "en_confeccion"
    assert datos["id_sala"] == id_sala
    assert datos["renglones"] == []
    assert datos["fecha_confeccion"] == consultar("SELECT CURRENT_DATE").isoformat()
    assert respuesta.headers["Location"] == f"/transferencias/{datos['nro_transferencia']}"

    consulta = cliente.get(respuesta.headers["Location"])
    assert consulta.status_code == 200
    assert consulta.json() == datos


def test_alta_con_sala_inexistente_422(cliente, consultar) -> None:
    antes = consultar("SELECT count(*) FROM transferencia")

    respuesta = cliente.post("/transferencias", json={"id_sala": 2_147_483_647})

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "El dato relacionado no existe.", "codigo": "23503",
                                "restriccion": "fk_transferencia_sala_venta"}
    assert consultar("SELECT count(*) FROM transferencia") == antes


def test_alta_sin_sala_422(cliente) -> None:
    respuesta = cliente.post("/transferencias", json={})

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"


@pytest.mark.parametrize(("metodo", "ruta", "cuerpo"), [
    ("GET", "", None),
])
def test_transferencia_inexistente_404(cliente, metodo, ruta, cuerpo) -> None:
    respuesta = cliente.request(metodo, f"/transferencias/{INEXISTENTE}{ruta}", json=cuerpo)

    assert respuesta.status_code == 404, respuesta.text
    # El texto viene del endpoint o del procedimiento, no del 404 de ruta inexistente.
    assert respuesta.json()["detail"] == f"La transferencia {INEXISTENTE} no existe."
