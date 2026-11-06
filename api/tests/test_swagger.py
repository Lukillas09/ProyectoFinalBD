"""Swagger y OpenAPI, directo contra la API y a través de nginx (/api)."""

import os

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import crear_app


@pytest.fixture(scope="module")
def cliente_local():
    with TestClient(crear_app()) as cliente_http:
        yield cliente_http


def test_metadatos_y_etiqueta_de_salud(cliente_local) -> None:
    esquema = cliente_local.get("/openapi.json").json()

    assert esquema["info"]["title"] == "Bodegas del Atuel API"
    assert esquema["info"]["version"] == "0.2.0"
    assert esquema["paths"]["/salud"]["get"]["tags"] == ["infraestructura"]
    assert "ErrorRespuesta" in esquema["components"]["schemas"]


@pytest.mark.parametrize(
    ("encabezados", "servidores", "url_openapi"),
    [
        ({}, None, "/openapi.json"),
        ({"X-Forwarded-Prefix": "/api"}, [{"url": "/api"}], "/api/openapi.json"),
        ({"X-Forwarded-Prefix": "/otro"}, None, "/openapi.json"),
        # Un valor arbitrario no llega al HTML de Swagger (sería un XSS reflejado).
        ({"X-Forwarded-Prefix": "/api'</script><script>alert(1)//"}, None, "/openapi.json"),
    ],
)
def test_prefijo_del_proxy(cliente_local, encabezados, servidores, url_openapi) -> None:
    esquema = cliente_local.get("/openapi.json", headers=encabezados).json()
    html = cliente_local.get("/docs", headers=encabezados).text

    assert esquema.get("servers") == servidores
    assert f"url: '{url_openapi}'" in html
    assert "alert(1)" not in html


# --- HTTP real dentro de la red de Compose ---------------------------------

def test_openapi_directo() -> None:
    respuesta = httpx.get(f"{os.environ['API_URL']}/openapi.json", timeout=5)

    assert respuesta.status_code == 200
    assert "servers" not in respuesta.json()


def test_swagger_por_el_proxy() -> None:
    front = os.environ["FRONT_URL"]
    esquema = httpx.get(f"{front}/api/openapi.json", timeout=5)
    html = httpx.get(f"{front}/api/docs", timeout=5)
    # "Try it out" usa servers + la ruta: /api/salud por el proxy.
    salud = httpx.get(f"{front}{esquema.json()['servers'][0]['url']}/salud", timeout=5)

    assert esquema.status_code == 200
    assert esquema.json()["servers"] == [{"url": "/api"}]
    assert "url: '/api/openapi.json'" in html.text
    assert salud.status_code == 200


def test_el_proxy_no_cambia_el_esquema_del_acceso_directo() -> None:
    httpx.get(f"{os.environ['FRONT_URL']}/api/openapi.json", timeout=5)
    directo = httpx.get(f"{os.environ['API_URL']}/openapi.json", timeout=5)

    assert "servers" not in directo.json()
