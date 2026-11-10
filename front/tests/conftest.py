"""Fixtures comunes de las pruebas de punta a punta del front (Etapa 7).

Las pruebas corren dentro de Docker (servicio front-test), contra un proyecto de
Compose aislado y cargado (ver front/tests/ejecutar.sh). El navegador abre
http://front y llama a /api por el mismo origen, a través de nginx, como en
producción. Nunca se corren contra el entorno por defecto: crean vinos, ventas
y transferencias.

La base se consulta sólo para VERIFICAR, con el rol de reportes (sólo lectura).
Toda escritura pasa por el front y la API. Los datos de prueba (un cliente, una
sala, un vino con stock, un vino sin stock en una sala) se buscan con SELECT en
la carga: nunca se escriben ids fijos, porque la carga cambia con
FECHA_REFERENCIA.
"""

import os
from collections.abc import Callable, Iterator
from typing import Any

import psycopg
import pytest
from playwright.sync_api import APIRequestContext, Playwright


@pytest.fixture(scope="session")
def base_url() -> str:
    """URL del front dentro de la red de Compose; la usa page.goto("/#/vinos")."""

    return os.environ["FRONT_URL"]


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args: dict) -> dict:
    # El front formatea con es-AR; el navegador usa el mismo idioma que el usuario.
    return {**browser_context_args, "locale": "es-AR", "viewport": {"width": 1280, "height": 900}}


@pytest.fixture(scope="session")
def _conexion() -> Iterator[psycopg.Connection]:
    conn = psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        autocommit=True,
        # Doble seguro: aunque el rol de reportes ya no puede escribir, la sesión
        # tampoco abre transacciones de escritura.
        options="-c search_path=bodegas,pg_catalog -c default_transaction_read_only=on",
    )
    yield conn
    conn.close()


@pytest.fixture(scope="session")
def consultar(_conexion: psycopg.Connection) -> Callable[..., list[tuple]]:
    """Ejecuta un SELECT parametrizado y devuelve todas las filas."""

    def ejecutar(sql: str, parametros: tuple = ()) -> list[tuple]:
        return _conexion.execute(sql, parametros).fetchall()

    return ejecutar


@pytest.fixture(scope="session")
def consultar_valor(consultar: Callable[..., list[tuple]]) -> Callable[..., Any]:
    """Como consultar, pero devuelve el primer valor de la primera fila (o None)."""

    def ejecutar(sql: str, parametros: tuple = ()) -> Any:
        filas = consultar(sql, parametros)
        return filas[0][0] if filas else None

    return ejecutar


@pytest.fixture(scope="session")
def api(playwright: Playwright, base_url: str) -> Iterator[APIRequestContext]:
    """Cliente HTTP de la API por la misma ruta pública que usa el navegador
    (/api a través de nginx). Sirve para leer lo que la API responde y compararlo
    con la pantalla, y para preparar datos por la propia API."""

    contexto = playwright.request.new_context(base_url=f"{base_url}/api/")
    yield contexto
    contexto.dispose()


@pytest.fixture(scope="session")
def id_sala(consultar_valor: Callable[..., Any]) -> int:
    """Una sala de la carga (la de menor id)."""

    return consultar_valor("SELECT min(id_sala) FROM sala_venta")


@pytest.fixture(scope="session")
def id_cliente(consultar_valor: Callable[..., Any]) -> int:
    """Un cliente de la carga (el de menor id)."""

    return consultar_valor("SELECT min(id_cliente) FROM cliente")
