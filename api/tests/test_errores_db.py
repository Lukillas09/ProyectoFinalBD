"""Traducción de errores reales de PostgreSQL, de punta a punta.

Cada caso ejecuta SQL real como bodegas_api a través de una ruta de prueba
(conftest.py), dentro de una transacción que termina en error y se revierte.
Se verifica la respuesta HTTP y, cuando la prueba escribió algo, que no quedó.
"""

import logging
import os

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient
from psycopg import Connection

from app.database import conexion
from app.errores import FK_CON_DEPENDIENTES, FK_FALTA_REFERIDO
from app.main import crear_app


@pytest.mark.parametrize(
    ("caso", "prefijo"),
    [("falta_relacionado", FK_FALTA_REFERIDO), ("con_dependientes", FK_CON_DEPENDIENTES)],
)
def test_textos_de_23503_que_reconoce_la_traduccion(error_de_la_base, consultar, marca, caso, prefijo) -> None:
    # La traducción de 23503 depende del idioma de los mensajes del servidor
    # (lc_messages, que bodegas_api no puede cambiar). No se fija su valor:
    # en_US.utf8, C y C.UTF-8 dan los mismos textos, y en la nube puede ser
    # otro. Se verifica lo que importa: los dos textos reales.
    error = error_de_la_base(caso)

    assert error.sqlstate == "23503"
    assert error.diag.message_primary.startswith(prefijo)
    assert consultar("SELECT count(*) FROM vino WHERE nombre = %s", (marca,)) == 0


@pytest.mark.parametrize(
    ("caso", "status", "codigo", "restriccion"),
    [
        ("unico", 409, "23505", "uq_vino_identidad_comercial"),
        ("falta_relacionado", 422, "23503", "fk_composicion_vino_vino"),
        ("con_dependientes", 409, "23503", "fk_auditoria_precio_vino"),
        ("check", 422, "23514", "ck_vino_precio_positivo"),
    ],
)
def test_restricciones(cliente, consultar, marca, caso, status, codigo, restriccion) -> None:
    respuesta = cliente.post(f"/_prueba/error/{caso}", params={"marca": marca})

    assert respuesta.status_code == status
    cuerpo = respuesta.json()
    assert (cuerpo["codigo"], cuerpo["restriccion"]) == (codigo, restriccion)
    assert "Key (" not in cuerpo["detail"]  # nunca el DETAIL con valores de la fila
    assert consultar("SELECT count(*) FROM vino WHERE nombre = %s", (marca,)) == 0


def test_no_nulo_informa_la_columna(cliente, marca) -> None:
    respuesta = cliente.post("/_prueba/error/no_nulo", params={"marca": marca})

    assert respuesta.status_code == 422
    assert respuesta.json() == {"detail": "Falta un dato obligatorio.", "codigo": "23502", "columna": "nombre"}


@pytest.mark.parametrize(
    ("caso", "status", "codigo"),
    [("largo", 422, "22001"), ("fuera_de_rango", 422, "22003"), ("formato", 400, "22P02")],
)
def test_datos_invalidos(cliente, marca, caso, status, codigo) -> None:
    respuesta = cliente.post(f"/_prueba/error/{caso}", params={"marca": marca})

    assert (respuesta.status_code, respuesta.json()["codigo"]) == (status, codigo)
    assert "abc" not in respuesta.json()["detail"]


def test_regla_de_negocio_devuelve_el_mensaje_de_la_base(cliente, marca) -> None:
    respuesta = cliente.post("/_prueba/error/regla", params={"marca": marca})

    assert respuesta.status_code == 409
    assert respuesta.json() == {"detail": "RN-08: una venta debe tener al menos un renglón.", "codigo": "P0001"}


def test_no_existe_404(cliente, marca) -> None:
    respuesta = cliente.post("/_prueba/error/no_existe", params={"marca": marca})

    assert respuesta.status_code == 404
    assert respuesta.json() == {"detail": "La transferencia -1 no existe.", "codigo": "P0002"}


def test_constraint_trigger_diferido_falla_en_el_commit(cliente, consultar, marca) -> None:
    respuesta = cliente.post("/_prueba/error/diferido", params={"marca": marca})

    assert respuesta.status_code == 409
    assert respuesta.json()["codigo"] == "P0001"
    assert respuesta.json()["detail"].startswith("Jerarquía de clientes: el cliente ")
    assert consultar("SELECT count(*) FROM cliente WHERE nombre_razon_social = %s", (marca,)) == 0


def test_serializacion_503_con_retry_after(cliente, marca) -> None:
    respuesta = cliente.post("/_prueba/error/serializacion", params={"marca": marca})

    assert respuesta.status_code == 503
    assert respuesta.headers["retry-after"] == "1"
    assert respuesta.json()["codigo"] == "40001"


def test_permiso_denegado_500_sin_detalles_y_al_log(cliente, marca, caplog) -> None:
    with caplog.at_level(logging.ERROR, logger="app.errores"):
        respuesta = cliente.post("/_prueba/error/permiso", params={"marca": marca})

    assert respuesta.status_code == 500
    assert respuesta.json() == {"detail": "Error interno del servidor.", "codigo": "interno"}
    registro = caplog.text
    assert "42501" in registro and "empleado" in registro
    assert os.environ["DB_PASSWORD"] not in registro
    assert os.environ["DB_HOST"] not in registro


def test_pool_sin_base_503(monkeypatch: pytest.MonkeyPatch) -> None:
    # Puerto donde no escucha nadie: el pool no entrega conexión (PoolTimeout).
    monkeypatch.setenv("DB_HOST", "127.0.0.1")
    monkeypatch.setenv("DB_PORT", "1")
    app = crear_app()

    def usa_la_base(conn: Connection = Depends(conexion)) -> dict[str, str]:
        return {"resultado": "no debería llegar"}

    app.add_api_route("/_prueba/conexion", usa_la_base)
    with TestClient(app) as cliente_sin_base:
        respuesta = cliente_sin_base.get("/_prueba/conexion")

    assert respuesta.status_code == 503
    assert respuesta.json() == {"detail": "Base de datos no disponible.", "codigo": "no_disponible"}
