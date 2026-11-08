"""Catálogo de vinos: sólo lectura (issue #25). Alta, modificación y baja: #26."""

from fastapi import APIRouter, Depends, HTTPException, Path
from psycopg import Connection

from app.database import conexion
from app.datos import vinos as datos
from app.esquemas import MAX_BIGINT, ErrorRespuesta, FiltrosVino, Pagina, Paginacion, VinoDetalle, VinoResumen


router = APIRouter(prefix="/vinos", tags=["vinos"])


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
    responses={404: {"model": ErrorRespuesta, "description": "El vino no existe."}},
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
