"""Vinos: catálogo (issue #25) y alta, modificación y baja (issue #26).

Los endpoints no capturan psycopg.Error: lo traduce app/errores.py. Las
operaciones de varias sentencias abren la transacción acá, con
``with conn.transaction():``, porque la composición al 100 % es un constraint
trigger diferido que falla recién en el COMMIT, al salir del bloque.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Request, Response, status
from psycopg import Connection

from app.database import conexion
from app.datos import vinos as datos
from app.esquemas import (
    MAX_BIGINT, ErrorRespuesta, FiltrosVino, Pagina, Paginacion, VinoDetalle, VinoEntrada, VinoResumen,
)


router = APIRouter(prefix="/vinos", tags=["vinos"])


def _error(descripcion: str) -> dict:
    return {"model": ErrorRespuesta, "description": descripcion}


@router.get("", summary="Listar vinos con filtros")
def listar_vinos(
    filtros: FiltrosVino = Depends(),
    pagina: Paginacion = Depends(),
    conn: Connection = Depends(conexion),
) -> Pagina[VinoResumen]:
    """Vinos ordenados por código. Los filtros son opcionales y se combinan con AND."""

    items, total = datos.listar(conn, filtros, pagina)
    return Pagina[VinoResumen](
        items=[VinoResumen(**item) for item in items],
        limite=pagina.limite,
        desplazamiento=pagina.desplazamiento,
        total=total,
    )


@router.get(
    "/{cod_vino}",
    summary="Ficha de un vino",
    responses={404: _error("El vino no existe.")},
)
def obtener_vino(
    cod_vino: int = Path(ge=1, le=MAX_BIGINT, description="Código del vino."),
    conn: Connection = Depends(conexion),
) -> VinoDetalle:
    """Bodega, composición (cepas y porcentajes), maridajes y stock total."""

    vino = datos.detalle(conn, cod_vino)
    if vino is None:
        raise HTTPException(404, f"El vino {cod_vino} no existe.")
    return VinoDetalle(**vino)


def _ficha_confirmada(conn: Connection, cod_vino: int) -> VinoDetalle:
    # Se lee después del COMMIT, en la misma conexión: la respuesta muestra lo
    # que quedó confirmado, ya validado por los triggers diferidos.
    vino = datos.detalle(conn, cod_vino)
    if vino is None:  # otro pedido lo borró justo después del COMMIT
        raise HTTPException(404, f"El vino {cod_vino} no existe.")
    return VinoDetalle(**vino)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Dar de alta un vino con su composición y maridajes",
    responses={
        409: _error("Vino repetido (23505, uq_vino_identidad_comercial) o composición que no suma "
                    "100 % (P0001, RN-05)."),
        422: _error("Forma inválida (validacion), una regla CHECK (23514: precio ≤ 0, graduación "
                    "fuera de 5-20, ...) o bodega, cepa o maridaje inexistente (23503)."),
    },
)
def crear_vino(
    vino: VinoEntrada,
    request: Request,
    response: Response,
    conn: Connection = Depends(conexion),
) -> VinoDetalle:
    """Inserta el vino, su composición y sus maridajes en **una transacción**.

    La suma de la composición al 100 % la verifica PostgreSQL al confirmar
    (constraint trigger diferido): si falla, no queda nada guardado. Responde
    la ficha completa, igual a la de `GET /vinos/{cod_vino}`.
    """

    with conn.transaction():
        cod_vino = datos.insertar(conn, vino)
        datos.insertar_composicion(conn, cod_vino, vino.composicion)
        datos.insertar_maridajes(conn, cod_vino, vino.maridajes)
    # Ruta relativa con el prefijo público: /vinos/N directo y /api/vinos/N
    # por nginx. request.url_for armaría una URL absoluta con el Host que
    # reenvía nginx, sin su puerto.
    response.headers["Location"] = request.scope.get("root_path", "") + router.url_path_for(
        "obtener_vino", cod_vino=cod_vino)
    return _ficha_confirmada(conn, cod_vino)


@router.put(
    "/{cod_vino}",
    summary="Modificar un vino (reemplazo completo)",
    responses={
        404: _error("El vino no existe."),
        409: _error("Choca con otro vino (23505, uq_vino_identidad_comercial) o la composición "
                    "nueva no suma 100 % (P0001, RN-05)."),
        422: _error("Forma inválida (validacion), una regla CHECK (23514) o bodega, cepa o "
                    "maridaje inexistente (23503)."),
    },
)
def modificar_vino(
    vino: VinoEntrada,
    cod_vino: int = Path(ge=1, le=MAX_BIGINT, description="Código del vino."),
    conn: Connection = Depends(conexion),
) -> VinoDetalle:
    """Reemplaza todos los datos del vino, **incluidas la composición y los maridajes**.

    Todo va en una transacción: la composición anterior se borra y se inserta
    la nueva, y la suma al 100 % se verifica al confirmar. Si falla, el vino
    queda como estaba.

    Si el precio cambia, `trg_vino_auditoria_precio` registra en
    `auditoria_precio` el precio anterior, el nuevo y el usuario de la base
    (RN-13). Un precio igual al actual no deja registro.
    """

    with conn.transaction():
        if not datos.actualizar(conn, cod_vino, vino):
            raise HTTPException(404, f"El vino {cod_vino} no existe.")
        datos.reemplazar_composicion(conn, cod_vino, vino.composicion)
        datos.reemplazar_maridajes(conn, cod_vino, vino.maridajes)
    return _ficha_confirmada(conn, cod_vino)
