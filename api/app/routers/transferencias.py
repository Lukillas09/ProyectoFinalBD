"""Transferencias del depósito central a una sala (issue #29).

El circuito es en_confeccion -> terminado -> procesado (RN-11). La API crea la
cabecera, agrega renglones e invoca sp_terminar_transferencia y
sp_procesar_transferencia; las transiciones, el bloqueo de renglones (RN-12) y
el movimiento de stock los decide PostgreSQL. Cada operación es una sola
sentencia, atómica en autocommit, y la transferencia se lee después de
confirmarla. Los errores de la base los traduce app/errores.py.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Request, Response, status
from psycopg import Connection

from app.database import conexion
from app.datos import documentos as datos
from app.esquemas import MAX_BIGINT, ErrorRespuesta, TransferenciaDetalle, TransferenciaEntrada


router = APIRouter(prefix="/transferencias", tags=["transferencias"])

NRO = Path(ge=1, le=MAX_BIGINT, description="Número de transferencia.")


def _error(descripcion: str) -> dict:
    return {"model": ErrorRespuesta, "description": descripcion}


def _no_existe(nro: int) -> HTTPException:
    # El mismo texto que el P0002 de los procedimientos.
    return HTTPException(status.HTTP_404_NOT_FOUND, f"La transferencia {nro} no existe.")


def _leer(conn: Connection, nro: int) -> TransferenciaDetalle:
    transferencia = datos.obtener_transferencia(conn, nro)
    if transferencia is None:
        raise _no_existe(nro)
    return TransferenciaDetalle(**transferencia)


def _ubicacion(request: Request, response: Response, nro: int) -> None:
    # Ruta relativa con el prefijo público, como en vinos: /transferencias/N
    # directo y /api/transferencias/N por nginx.
    response.headers["Location"] = request.scope.get("root_path", "") + router.url_path_for(
        "obtener_transferencia", nro=nro)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Crear una transferencia en confección",
    responses={422: _error("Forma inválida (validacion) o sala inexistente (23503).")},
)
def crear_transferencia(
    entrada: TransferenciaEntrada,
    request: Request,
    response: Response,
    conn: Connection = Depends(conexion),
) -> TransferenciaDetalle:
    """Crea la cabecera en estado `en_confeccion`, sin renglones.

    La fecha de confección la fija la base (RN-11): si el cuerpo trae `estado`
    o `fecha_confeccion`, se ignoran.
    """

    nro = datos.crear_transferencia(conn, entrada.id_sala)
    _ubicacion(request, response, nro)
    return _leer(conn, nro)


@router.get(
    "/{nro}",
    summary="Consultar una transferencia",
    responses={404: _error("La transferencia no existe.")},
)
def obtener_transferencia(nro: int = NRO, conn: Connection = Depends(conexion)) -> TransferenciaDetalle:
    """Cabecera, estado y renglones. El estado indica qué operaciones admite."""

    return _leer(conn, nro)
