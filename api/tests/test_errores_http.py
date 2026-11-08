"""HTTPException con el cuerpo ErrorRespuesta: las de Starlette y las propias.

El 503 de /salud sin base está en test_salud.py.
"""

import os

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.main import crear_app


@pytest.fixture(scope="module")
def cliente_http():
    app = crear_app()

    # Así responden los endpoints de los issues #25 a #32 cuando no hay fila.
    def vino(cod_vino: int) -> dict[str, int]:
        raise HTTPException(404, f"El vino {cod_vino} no existe.")

    app.add_api_route("/_prueba/vinos/{cod_vino}", vino)
    with TestClient(app) as cliente:
        yield cliente


def test_ruta_inexistente_404(cliente_http) -> None:
    respuesta = cliente_http.get("/no-existe")

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": "Recurso no encontrado.", "codigo": "no_encontrado"}


def test_metodo_no_permitido_405_conserva_allow(cliente_http) -> None:
    respuesta = cliente_http.post("/salud")

    assert respuesta.status_code == 405
    assert respuesta.headers["allow"] == "GET"
    assert respuesta.json() == {"detail": "Método no permitido para este recurso.",
                                "codigo": "metodo_no_permitido"}


def test_no_existe_propio_conserva_el_detalle(cliente_http) -> None:
    respuesta = cliente_http.get("/_prueba/vinos/7")

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": "El vino 7 no existe.", "codigo": "no_encontrado"}


@pytest.mark.parametrize("base", ["API_URL", "FRONT_URL"])
def test_404_por_http_real(base: str) -> None:
    # Contra la API que corre en el servicio api, directo y por nginx.
    prefijo = "/api" if base == "FRONT_URL" else ""
    respuesta = httpx.get(f"{os.environ[base]}{prefijo}/no-existe", timeout=10)

    assert respuesta.status_code == 404
    assert respuesta.json()["codigo"] == "no_encontrado"
