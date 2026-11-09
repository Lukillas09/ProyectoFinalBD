"""Ingresos de una bodega al depósito central (issue #30).

Mismo circuito que las transferencias: en_confeccion -> terminado ->
procesado (RN-10). La API crea la cabecera, agrega renglones e invoca
sp_terminar_ingreso y sp_procesar_ingreso. Las transiciones, el bloqueo de
renglones (RN-12), los vinos de la bodega de origen (RN-16) y la suma al
depósito los decide PostgreSQL. Cada operación es una sola sentencia y el
ingreso se lee después de confirmarla. Los errores los traduce app/errores.py.

`POST /ingresos/{cod}/terminar` no figura en la consigna, que sólo lista
procesar. RN-10 exige pasar por terminado y la base no lo hace sola, así que
se expone como en transferencias (docs/api.md, sección 6, pregunta 2).
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Request, Response, status
from psycopg import Connection

from app.database import conexion
from app.datos import documentos as datos
from app.esquemas import MAX_BIGINT, ErrorRespuesta, IngresoDetalle, IngresoEntrada, RenglonDocumentoEntrada


router = APIRouter(prefix="/ingresos", tags=["ingresos"])

COD = Path(ge=1, le=MAX_BIGINT, description="Código de ingreso.")


def _error(descripcion: str) -> dict:
    return {"model": ErrorRespuesta, "description": descripcion}


def _no_existe(cod: int) -> HTTPException:
    # El mismo texto que el P0002 de los procedimientos.
    return HTTPException(status.HTTP_404_NOT_FOUND, f"El ingreso {cod} no existe.")


def _leer(conn: Connection, cod: int) -> IngresoDetalle:
    ingreso = datos.obtener_ingreso(conn, cod)
    if ingreso is None:
        raise _no_existe(cod)
    return IngresoDetalle(**ingreso)


def _ubicacion(request: Request, response: Response, cod: int) -> None:
    # Ruta relativa con el prefijo público: /ingresos/N directo y
    # /api/ingresos/N por nginx.
    response.headers["Location"] = request.scope.get("root_path", "") + router.url_path_for(
        "obtener_ingreso", cod=cod)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Crear un ingreso en confección",
    responses={422: _error("Forma inválida (validacion) o transportista o bodega inexistente (23503).")},
)
def crear_ingreso(
    entrada: IngresoEntrada,
    request: Request,
    response: Response,
    conn: Connection = Depends(conexion),
) -> IngresoDetalle:
    """Crea la cabecera en estado `en_confeccion`, sin renglones.

    Estado y fecha los fija la base: si el cuerpo los trae, se ignoran.
    """

    cod = datos.crear_ingreso(conn, entrada.cod_transportista, entrada.cuit_bodega)
    _ubicacion(request, response, cod)
    return _leer(conn, cod)


@router.get(
    "/{cod}",
    summary="Consultar un ingreso",
    responses={404: _error("El ingreso no existe.")},
)
def obtener_ingreso(cod: int = COD, conn: Connection = Depends(conexion)) -> IngresoDetalle:
    """Cabecera, estado y renglones. El estado indica qué operaciones admite."""

    return _leer(conn, cod)


@router.post(
    "/{cod}/renglones",
    status_code=status.HTTP_201_CREATED,
    summary="Agregar un renglón a un ingreso en confección",
    responses={
        404: _error("El ingreso no existe."),
        409: _error("El ingreso ya no está en confección (P0001, RN-12), el vino es de otra bodega "
                    "(P0001, RN-16) o ya tiene un renglón (23505, pk_renglon_ingreso)."),
        422: _error("Forma inválida (validacion), cantidad no positiva (23514) o vino "
                    "inexistente (23503)."),
    },
)
def agregar_renglon(
    renglon: RenglonDocumentoEntrada,
    request: Request,
    response: Response,
    cod: int = COD,
    conn: Connection = Depends(conexion),
) -> IngresoDetalle:
    """Agrega un vino y su cantidad. Responde el ingreso completo.

    Sólo mientras está `en_confeccion` (RN-12), y sólo con vinos de la bodega
    de origen del ingreso (RN-16).
    """

    if not datos.agregar_renglon_ingreso(conn, cod, renglon.cod_vino, renglon.cantidad):
        raise _no_existe(cod)
    _ubicacion(request, response, cod)
    return _leer(conn, cod)


@router.post(
    "/{cod}/terminar",
    summary="Terminar un ingreso",
    responses={
        404: _error("El ingreso no existe (P0002)."),
        409: _error("Transición inválida o ingreso sin renglones (P0001, RN-10)."),
    },
)
def terminar_ingreso(cod: int = COD, conn: Connection = Depends(conexion)) -> IngresoDetalle:
    """`CALL sp_terminar_ingreso`: de `en_confeccion` a `terminado`.

    No figura en la consigna, pero RN-10 exige este paso antes de procesar.
    Necesita al menos un renglón; desde ese momento los renglones no cambian
    (RN-12). Terminar un ingreso ya terminado no cambia nada.
    """

    datos.terminar_ingreso(conn, cod)
    return _leer(conn, cod)


@router.post(
    "/{cod}/procesar",
    summary="Procesar un ingreso: sumar sus botellas al depósito central",
    responses={
        404: _error("El ingreso no existe (P0002)."),
        409: _error("No está terminado o ya fue procesado (P0001, RN-10)."),
    },
)
def procesar_ingreso(cod: int = COD, conn: Connection = Depends(conexion)) -> IngresoDetalle:
    """`CALL sp_procesar_ingreso`: de `terminado` a `procesado`.

    El procedimiento bloquea el ingreso (`FOR UPDATE`) y suma cada renglón al
    depósito, en orden de vino, todo o nada. Un ingreso procesado no vuelve a
    sumarse (impacto único). La API no toca el stock.
    """

    datos.procesar_ingreso(conn, cod)
    return _leer(conn, cod)
