"""Pool y consultas SQL de infraestructura."""

import logging

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
        open=False,
        name="bodegas-api-pool",
    )


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
