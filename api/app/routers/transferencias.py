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
from app.esquemas import (
    MAX_BIGINT, ErrorRespuesta, RenglonDocumentoEntrada, TransferenciaDetalle, TransferenciaEntrada,
)


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


@router.post(
    "/{nro}/renglones",
    status_code=status.HTTP_201_CREATED,
    summary="Agregar un renglón a una transferencia en confección",
    responses={
        404: _error("La transferencia no existe."),
        409: _error("La transferencia ya no está en confección (P0001, RN-12) o el vino ya tiene "
                    "un renglón (23505, pk_renglon_transferencia)."),
        422: _error("Forma inválida (validacion), cantidad no positiva (23514) o vino "
                    "inexistente (23503)."),
    },
)
def agregar_renglon(
    renglon: RenglonDocumentoEntrada,
    request: Request,
    response: Response,
    nro: int = NRO,
    conn: Connection = Depends(conexion),
) -> TransferenciaDetalle:
    """Agrega un vino y su cantidad. Responde la transferencia completa.

    Sólo mientras está `en_confeccion`: después la base rechaza cualquier
    cambio en los renglones (RN-12). El stock no se controla acá, sino al
    procesar.
    """

    if not datos.agregar_renglon_transferencia(conn, nro, renglon.cod_vino, renglon.cantidad):
        raise _no_existe(nro)
    _ubicacion(request, response, nro)
    return _leer(conn, nro)


@router.post(
    "/{nro}/terminar",
    summary="Terminar una transferencia",
    responses={
        404: _error("La transferencia no existe (P0002)."),
        409: _error("Transición inválida o transferencia sin renglones (P0001, RN-11)."),
    },
)
def terminar_transferencia(nro: int = NRO, conn: Connection = Depends(conexion)) -> TransferenciaDetalle:
    """`CALL sp_terminar_transferencia`: de `en_confeccion` a `terminado`.

    Necesita al menos un renglón. Desde ese momento los renglones no cambian
    (RN-12). Terminar una transferencia ya terminada no es una transición y no
    cambia nada; una procesada no vuelve atrás (409).
    """

    datos.terminar_transferencia(conn, nro)
    return _leer(conn, nro)


@router.post(
    "/{nro}/procesar",
    summary="Procesar una transferencia: mover el stock del depósito a la sala",
    responses={
        404: _error("La transferencia no existe (P0002)."),
        409: _error("No está terminada, ya fue procesada o el depósito no tiene stock suficiente "
                    "(P0001, RN-11). En ese caso no queda ningún cambio."),
    },
)
def procesar_transferencia(nro: int = NRO, conn: Connection = Depends(conexion)) -> TransferenciaDetalle:
    """`CALL sp_procesar_transferencia`: de `terminado` a `procesado`.

    El procedimiento bloquea la transferencia y las filas del depósito
    (`FOR UPDATE`, en orden de vino), verifica el stock de **cada** renglón,
    descuenta del depósito, suma a la sala y cambia el estado, todo o nada.
    La API no toca el stock.
    """

    datos.procesar_transferencia(conn, nro)
    return _leer(conn, nro)
