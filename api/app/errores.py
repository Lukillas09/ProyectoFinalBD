"""Traducción central de errores a respuestas HTTP (docs/api.md, sección 3).

``traducir`` es una función pura: recibe el SQLSTATE y los campos de
diagnóstico y decide estado, cuerpo y encabezados, sin base ni FastAPI. Los
manejadores sólo extraen esos datos de la excepción, registran lo necesario y
responden.

Al cliente nunca va el DETAIL de PostgreSQL (puede traer valores de la fila)
ni el texto completo de la excepción (en errores de conexión trae servidor y
usuario). Sí va ``message_primary`` cuando el mensaje es nuestro: P0001 y
P0002 los escriben los ``RAISE`` de las funciones, triggers y procedimientos.
"""

import logging
from dataclasses import dataclass, field

import psycopg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from psycopg_pool import PoolClosed, PoolTimeout

from app.esquemas import ErrorCampo, ErrorRespuesta


logger = logging.getLogger(__name__)

NO_DISPONIBLE = "Base de datos no disponible."
INTERNO = "Error interno del servidor."

# 23503 tiene dos mensajes en PostgreSQL 16 (lc_messages en inglés; lo
# verifica tests/test_errores_db.py). diag.table_name no los distingue: en
# los dos casos informa la tabla que referencia.
FK_FALTA_REFERIDO = "insert or update on table "
FK_CON_DEPENDIENTES = "update or delete on table "


@dataclass(frozen=True)
class Traduccion:
    status: int
    cuerpo: ErrorRespuesta
    encabezados: dict[str, str] = field(default_factory=dict)
    # Nivel de log (logging.WARNING, logging.ERROR) o None si no se registra.
    nivel_log: int | None = None


def traducir(
    sqlstate: str | None,
    mensaje_primario: str | None,
    restriccion: str | None = None,
    columna: str | None = None,
) -> Traduccion:
    """Decide la respuesta HTTP para un error de PostgreSQL."""

    def error(status: int, detail: str, codigo: str | None = None, **extra) -> Traduccion:
        return Traduccion(status, ErrorRespuesta(detail=detail, codigo=codigo or sqlstate, **extra))

    if sqlstate is None or sqlstate.startswith("08"):
        # Clase 08 o conexión perdida sin SQLSTATE: la base no responde.
        return Traduccion(503, ErrorRespuesta(detail=NO_DISPONIBLE, codigo="no_disponible"),
                          nivel_log=logging.WARNING)
    if sqlstate == "P0001":
        return error(409, mensaje_primario or "Regla de negocio rechazada.")
    if sqlstate == "P0002":
        return error(404, mensaje_primario or "No existe.")
    if sqlstate == "23505":
        return error(409, "Ya existe un registro con esos datos.", restriccion=restriccion)
    if sqlstate == "23503":
        mensaje = mensaje_primario or ""
        if mensaje.startswith(FK_FALTA_REFERIDO):
            return error(422, "El dato relacionado no existe.", restriccion=restriccion)
        traduccion = error(409, "No se puede borrar ni modificar: hay datos que dependen de este registro.",
                           restriccion=restriccion)
        if not mensaje.startswith(FK_CON_DEPENDIENTES):
            # Texto no reconocido (otro idioma del servidor): se responde
            # como conflicto y se avisa en el log para revisarlo.
            return Traduccion(traduccion.status, traduccion.cuerpo, nivel_log=logging.WARNING)
        return traduccion
    if sqlstate == "23514":
        return error(422, "Un valor no cumple una regla de validación.", restriccion=restriccion)
    if sqlstate == "23502":
        return error(422, "Falta un dato obligatorio.", columna=columna)
    if sqlstate == "22001":
        return error(422, "Un texto supera el largo permitido.")
    if sqlstate == "22003":
        return error(422, "Un número está fuera del rango permitido.")
    if sqlstate == "22P02":
        return error(400, "Un valor no tiene el formato esperado.")
    if sqlstate in ("40001", "40P01"):
        return Traduccion(
            503,
            ErrorRespuesta(detail="La operación chocó con otra simultánea. Reintente.", codigo=sqlstate),
            encabezados={"Retry-After": "1"},
        )
    # 42501 (permiso denegado al rol de la API) y cualquier otro: es un error
    # de la API o de sus privilegios, no del cliente. Se registra completo y
    # se responde sin detalles.
    return Traduccion(500, ErrorRespuesta(detail=INTERNO, codigo="interno"), nivel_log=logging.ERROR)


def _responder(traduccion: Traduccion) -> JSONResponse:
    return JSONResponse(
        status_code=traduccion.status,
        content=traduccion.cuerpo.model_dump(exclude_none=True),
        headers=traduccion.encabezados or None,
    )


async def _error_postgresql(_: Request, exc: psycopg.Error) -> JSONResponse:
    if exc.sqlstate is None and not isinstance(exc, (psycopg.OperationalError, psycopg.InterfaceError)):
        # Error del lado del cliente psycopg (por ejemplo, parámetros mal
        # armados): es un error de la API.
        traduccion = Traduccion(500, ErrorRespuesta(detail=INTERNO, codigo="interno"), nivel_log=logging.ERROR)
    else:
        diag = exc.diag
        traduccion = traducir(exc.sqlstate, diag.message_primary, diag.constraint_name, diag.column_name)
    if traduccion.nivel_log is not None:
        # Sólo SQLSTATE, mensaje primario y nombres de objetos: nunca str(exc)
        # ni DETAIL, que pueden traer datos de la conexión o de la fila.
        diag = exc.diag
        logger.log(traduccion.nivel_log, "Error de PostgreSQL %s (%s): %s [tabla=%s, restricción=%s]",
                   exc.sqlstate, type(exc).__name__, diag.message_primary,
                   diag.table_name, diag.constraint_name)
    return _responder(traduccion)


async def _pool_no_disponible(_: Request, exc: Exception) -> JSONResponse:
    logger.warning("Pool de conexiones no disponible: %s", type(exc).__name__)
    return _responder(Traduccion(503, ErrorRespuesta(detail=NO_DISPONIBLE, codigo="no_disponible")))


async def _validacion(_: Request, exc: Exception) -> JSONResponse:
    # Mismo formato que los errores de la base: el front muestra "detail".
    assert isinstance(exc, RequestValidationError)
    errores = [
        ErrorCampo(campo=".".join(str(parte) for parte in error["loc"]), mensaje=error["msg"])
        for error in exc.errors()
    ]
    return _responder(Traduccion(422, ErrorRespuesta(
        detail="Datos de entrada inválidos.", codigo="validacion", errores=errores)))


def registrar_manejadores(app: FastAPI) -> None:
    """Instala la traducción de errores en la aplicación."""

    app.add_exception_handler(PoolTimeout, _pool_no_disponible)
    app.add_exception_handler(PoolClosed, _pool_no_disponible)
    app.add_exception_handler(psycopg.Error, _error_postgresql)
    app.add_exception_handler(RequestValidationError, _validacion)
