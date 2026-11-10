"""Configuración para la nube (Etapa 8, issue #66): DB_SSLMODE y CORS_ORIGINS.

No usan la base: arman la configuración y la aplicación con variables de
entorno propias (monkeypatch), sin tocar la app que comparte el resto de la
suite. Las preflight de CORS las responde el middleware antes de llegar a las
rutas, así que no hace falta abrir el pool.
"""

import pytest
from fastapi.testclient import TestClient

from app.config import ConfigurationError, Settings, cors_origins_desde_entorno
from app.main import crear_app

FRONT = "https://bodegas-front.onrender.com"


@pytest.fixture
def entorno_base(monkeypatch):
    for nombre, valor in {
        "DB_HOST": "db", "DB_NAME": "bodegas", "DB_USER": "bodegas_api", "DB_PASSWORD": "x",
    }.items():
        monkeypatch.setenv(nombre, valor)
    monkeypatch.delenv("DB_SSLMODE", raising=False)
    monkeypatch.delenv("CORS_ORIGINS", raising=False)
    return monkeypatch


def test_sslmode_por_omision_es_prefer(entorno_base):
    assert Settings.from_environment().connection_kwargs()["sslmode"] == "prefer"


def test_sslmode_require_llega_a_la_conexion(entorno_base):
    entorno_base.setenv("DB_SSLMODE", "require")
    assert Settings.from_environment().connection_kwargs()["sslmode"] == "require"


def test_sslmode_invalido_no_arranca(entorno_base):
    entorno_base.setenv("DB_SSLMODE", "siempre")
    with pytest.raises(ConfigurationError):
        Settings.from_environment()


@pytest.mark.parametrize("valor", ["*", "http://ejemplo.com", "https://front.com/", "https://*.onrender.com"])
def test_cors_rechaza_origenes_peligrosos(entorno_base, valor):
    entorno_base.setenv("CORS_ORIGINS", valor)
    with pytest.raises(ConfigurationError):
        cors_origins_desde_entorno()


def test_cors_acepta_lista(entorno_base):
    entorno_base.setenv("CORS_ORIGINS", f"{FRONT}, http://localhost:8080")
    assert cors_origins_desde_entorno() == (FRONT, "http://localhost:8080")


def _preflight(cliente: TestClient, origen: str):
    return cliente.options(
        "/vinos",
        headers={"Origin": origen, "Access-Control-Request-Method": "POST",
                 "Access-Control-Request-Headers": "content-type"},
    )


def test_cors_permite_el_origen_del_front(entorno_base):
    entorno_base.setenv("CORS_ORIGINS", FRONT)
    respuesta = _preflight(TestClient(crear_app()), FRONT)
    assert respuesta.status_code == 200
    assert respuesta.headers["access-control-allow-origin"] == FRONT


def test_cors_rechaza_un_origen_ajeno(entorno_base):
    entorno_base.setenv("CORS_ORIGINS", FRONT)
    respuesta = _preflight(TestClient(crear_app()), "https://ejemplo-malicioso.com")
    assert "access-control-allow-origin" not in respuesta.headers


def test_sin_cors_origins_no_hay_cors(entorno_base):
    respuesta = _preflight(TestClient(crear_app()), FRONT)
    assert "access-control-allow-origin" not in respuesta.headers
