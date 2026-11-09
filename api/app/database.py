"""Pool, conexión por pedido y consultas SQL de infraestructura."""

import logging
from collections.abc import Iterator

from fastapi import Request
from psycopg import Connection
from psycopg import Error as PsycopgError
from psycopg_pool import ConnectionPool, PoolClosed, PoolTimeout

from app.config import Settings


logger = logging.getLogger(__name__)


def create_pool(settings: Settings) -> ConnectionPool:
    """Crea el pool cerrado para que el ciclo de vida de FastAPI lo administre."""

    return ConnectionPool(
        conninfo="",
        kwargs=settings.connection_kwargs(),
        min_size=settings.db_pool_min_size,
        max_size=settings.db_pool_max_size,
        timeout=settings.db_pool_timeout_seconds,
        # Prueba cada conexión antes de entregarla. Sin esto, después de un
        # reinicio de PostgreSQL el primer pedido recibía una conexión muerta.
        check=ConnectionPool.check_connection,
        open=False,
        name="bodegas-api-pool",
    )


def conexion(request: Request) -> Iterator[Connection]:
    """Dependencia de FastAPI: una conexión del pool para el pedido.

    La conexión está en autocommit: cada sentencia suelta se confirma sola.
    Una operación de varias sentencias abre su transacción dentro del
    endpoint, con ``with conn.transaction():``. Así el COMMIT, y los errores
    de los constraint triggers diferidos que aparecen en él, ocurren antes de
    armar la respuesta (ver api/README.md).

    Si el pool no entrega una conexión a tiempo, PoolTimeout llega al
    manejador de app/errores.py y la respuesta es 503.
    """

    pool: ConnectionPool = request.app.state.db_pool
    with pool.connection(timeout=request.app.state.db_pool_timeout_seconds) as conn:
        yield conn


def database_is_available(
    pool: ConnectionPool, timeout_seconds: int
) -> bool:
    """Comprueba PostgreSQL sin propagar detalles internos al controlador HTTP."""

    try:
        with pool.connection(timeout=timeout_seconds) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                return cursor.fetchone() == (1,)
    except (PsycopgError, PoolClosed, PoolTimeout, OSError):
        # No se registra la excepción porque podría incluir datos de conexión.
        logger.warning("PostgreSQL no respondió al control de salud.")
        return False
