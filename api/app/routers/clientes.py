"""Clientes de los tres tipos: listado, ficha, alta, modificación y baja (issue #27).

Los endpoints no capturan psycopg.Error: lo traduce app/errores.py. Las
operaciones de varias sentencias abren la transacción acá, con
``with conn.transaction():``: la totalidad de la jerarquía es un constraint
trigger diferido que se verifica recién en el COMMIT, al salir del bloque.
"""

from fastapi import APIRouter, Depends, HTTPException, Path
from psycopg import Connection
from pydantic import TypeAdapter

from app.database import conexion
from app.datos import clientes as datos
from app.esquemas import (
    MAX_BIGINT, ClienteDetalle, ClienteResumen, ErrorRespuesta, FiltrosCliente, Pagina, Paginacion,
)


router = APIRouter(prefix="/clientes", tags=["clientes"])

# Arma el modelo de la ficha que corresponde al tipo de la fila.
_FICHA = TypeAdapter(ClienteDetalle)


def _error(descripcion: str) -> dict:
    return {"model": ErrorRespuesta, "description": descripcion}


@router.get("", summary="Listar clientes con filtros")
def listar_clientes(
    filtros: FiltrosCliente = Depends(),
    pagina: Paginacion = Depends(),
    conn: Connection = Depends(conexion),
) -> Pagina[ClienteResumen]:
    """Clientes ordenados por código. Los filtros son opcionales y se combinan con AND."""

    items, total = datos.listar(conn, filtros, pagina)
    return Pagina[ClienteResumen](
        items=[ClienteResumen(**item) for item in items],
        limite=pagina.limite,
        desplazamiento=pagina.desplazamiento,
        total=total,
    )


@router.get(
    "/{id_cliente}",
    summary="Ficha de un cliente",
    responses={404: _error("El cliente no existe.")},
)
def obtener_cliente(
    id_cliente: int = Path(ge=1, le=MAX_BIGINT, description="Código del cliente."),
    conn: Connection = Depends(conexion),
) -> ClienteDetalle:
    """Datos comunes, los de su subtipo (y los permisos si es exportador) y el
    descuento que le aplica la base (`fn_descuento_cliente`, RN-06)."""

    fila = datos.detalle(conn, id_cliente)
    if fila is None:
        raise HTTPException(404, f"El cliente {id_cliente} no existe.")
    return _FICHA.validate_python(fila)
