"""Pruebas de /salud contra PostgreSQL real.

Corren dentro de Docker (servicio api-test), en la red interna donde está db y
con las mismas variables de entorno que la API. Ver api/README.md.
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app


def test_salud_responde_200_con_la_base_disponible() -> None:
    # El bloque with ejecuta el lifespan: abre y cierra el pool real.
    with TestClient(app) as cliente:
        respuesta = cliente.get("/salud")

    assert respuesta.status_code == 200
    assert respuesta.json() == {"estado": "ok", "base_de_datos": "disponible"}


def test_salud_responde_503_sin_base(monkeypatch: pytest.MonkeyPatch) -> None:
    # La configuración se lee al iniciar la aplicación: apuntarla a un puerto
    # donde no escucha nadie simula una base caída sin detener el contenedor db.
    monkeypatch.setenv("DB_HOST", "127.0.0.1")
    monkeypatch.setenv("DB_PORT", "1")

    with TestClient(app) as cliente:
        respuesta = cliente.get("/salud")

    assert respuesta.status_code == 503
    assert respuesta.json() == {"detail": "Base de datos no disponible."}
