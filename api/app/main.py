"""Aplicación HTTP de la etapa inicial."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status

from app.config import Settings
from app.database import create_pool, database_is_available


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncIterator[None]:
    """Abre y cierra el pool junto con el proceso de la API."""

    settings = Settings.from_environment()
    pool = create_pool(settings)

    # No bloquea el arranque esperando a PostgreSQL. Si no está disponible,
    # el endpoint de salud responderá 503 y el pool seguirá reintentando.
    pool.open(wait=False)
    application.state.db_pool = pool
    application.state.db_pool_timeout_seconds = (
        settings.db_pool_timeout_seconds
    )

    try:
        yield
    finally:
        pool.close()


app = FastAPI(
    title="Bodegas del Atuel API",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/salud", tags=["infraestructura"])
def salud(request: Request) -> dict[str, str]:
    """Informa disponibilidad solo después de ejecutar ``SELECT 1``."""

    if not database_is_available(
        request.app.state.db_pool,
        request.app.state.db_pool_timeout_seconds,
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Base de datos no disponible.",
        )

    return {"estado": "ok", "base_de_datos": "disponible"}
