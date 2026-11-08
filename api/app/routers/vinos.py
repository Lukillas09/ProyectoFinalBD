"""Catálogo de vinos: sólo lectura (issue #25). Alta, modificación y baja: #26."""

from fastapi import APIRouter, Depends
from psycopg import Connection

from app.database import conexion
from app.datos import vinos as datos
from app.esquemas import FiltrosVino, Pagina, Paginacion, VinoResumen


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

