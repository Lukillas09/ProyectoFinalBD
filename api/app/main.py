"""Aplicación HTTP: ciclo de vida del pool, manejo de errores y rutas."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI, HTTPException, Request, status

from app.config import Settings
from app.database import create_pool, database_is_available
from app.errores import registrar_manejadores
from app.esquemas import ErrorRespuesta
from app.routers import catalogos, clientes, comprobantes, ingresos, reportes, transferencias, vinos


DESCRIPCION = """
API REST de Bodegas del Atuel (TPI Bases de Datos 2026, UTN FRSR).

Las reglas de negocio, los importes, los descuentos y el stock los resuelve
PostgreSQL. La API invoca sus funciones y procedimientos y traduce sus errores
por SQLSTATE: todos los errores responden con el modelo `ErrorRespuesta`
(`detail`, `codigo` y, según el caso, `restriccion`, `columna` o `errores`).
"""

ETIQUETAS = [
    {"name": "infraestructura", "description": "Estado de la API y de su conexión a PostgreSQL."},
    {"name": "vinos", "description": "Catálogo de vinos (listado con filtros y paginación, y ficha "
                                     "con bodega, composición, maridajes y stock total) y su alta, "
                                     "modificación y baja."},
    {"name": "clientes", "description": "Clientes de los tres tipos (socio, distribuidor y "
                                        "exportador) con los datos de su subtipo y el descuento "
                                        "que les aplica la base."},
    {"name": "transferencias", "description": "Transferencias del depósito central a una sala: "
                                              "alta, renglones, terminar y procesar. El stock lo "
                                              "mueve la base al procesar."},
    {"name": "ingresos", "description": "Ingresos de una bodega al depósito central: alta, "
                                        "renglones (sólo vinos de esa bodega), terminar y "
                                        "procesar. El stock lo suma la base al procesar."},
    {"name": "reportes", "description": "Reportes de sólo lectura (consultas S1, S8, S6 y S7): "
                                        "vinos más vendidos, ventas por sala, vinos sin stock en "
                                        "una sala y transportista más activo."},
    {"name": "catalogos", "description": "Listas de sólo lectura para los selectores del front: "
                                         "tipos de vino, cepas, bodegas, maridajes y salas. "
                                         "Sin paginación: son tablas de referencia chicas."},
]

# Prefijo con el que nginx publica la API (front/nginx.conf, location /api/).
PREFIJO_PROXY = b"/api"


class PrefijoDelProxy:
    """Middleware ASGI: toma el prefijo público que informa nginx.

    nginx quita /api antes de reenviar y avisa con X-Forwarded-Prefix. Con ese
    valor como root_path, Swagger pide /api/openapi.json y "Try it out" llama a
    /api/...; sin el encabezado (acceso directo al puerto de la API) todo
    queda en /. Sólo se acepta exactamente /api: Swagger incrusta el prefijo
    en su HTML sin escaparlo, y un valor arbitrario enviado al puerto de la
    API sería un XSS reflejado.
    """

    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] == "http" and (b"x-forwarded-prefix", PREFIJO_PROXY) in scope["headers"]:
            scope = {**scope, "root_path": PREFIJO_PROXY.decode()}
        await self.app(scope, receive, send)


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncGenerator[None, None]:
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


router = APIRouter()


@router.get(
    "/salud",
    tags=["infraestructura"],
    responses={503: {"model": ErrorRespuesta, "description": "PostgreSQL no responde."}},
)
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


def crear_app() -> FastAPI:
    """Arma la aplicación. Las pruebas crean la suya con esta misma función."""

    application = FastAPI(
        title="Bodegas del Atuel API",
        version="0.2.0",
        description=DESCRIPCION,
        openapi_tags=ETIQUETAS,
        lifespan=lifespan,
    )
    application.add_middleware(PrefijoDelProxy)
    registrar_manejadores(application)
    application.include_router(router)
    application.include_router(vinos.router)
    application.include_router(clientes.router)
    application.include_router(comprobantes.router)
    application.include_router(transferencias.router)
    application.include_router(ingresos.router)
    application.include_router(reportes.router)
    application.include_router(catalogos.router)
    return application


app = crear_app()
