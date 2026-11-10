"""Catálogos de sólo lectura para los selectores del front (issue #49).

Sin paginación: son tablas de referencia chicas. Sin parámetros, así que no
hay nada que validar; los errores de PostgreSQL los traduce app/errores.py.
El SQL está en app/datos/catalogos.py.
"""

from typing import get_args

from fastapi import APIRouter, Depends
from psycopg import Connection

from app.database import conexion
from app.datos import catalogos as datos
from app.esquemas import Bodega, Cepa, Maridaje, Sala, TipoVino


router = APIRouter(prefix="/catalogos", tags=["catalogos"])


@router.get("/tipos-vino", summary="Tipos de vino")
def tipos_vino() -> list[str]:
    """Los valores admitidos para el tipo de un vino.

    No consulta la base: TipoVino replica ``CHECK (tipo IN ...)`` de
    ck_vino_tipo (db/migrations/002_constraints.sql) y ya valida el filtro y
    el alta de vinos. Publicarlo evita que el front escriba la lista a mano y
    quede desalineada con la API.
    """

    return list(get_args(TipoVino))


@router.get("/cepas", summary="Cepas, por nombre")
def cepas(conn: Connection = Depends(conexion)) -> list[Cepa]:
    return datos.listar_cepas(conn)


@router.get("/bodegas", summary="Bodegas, por razón social")
def bodegas(conn: Connection = Depends(conexion)) -> list[Bodega]:
    return datos.listar_bodegas(conn)


@router.get("/maridajes", summary="Maridajes, por nombre")
def maridajes(conn: Connection = Depends(conexion)) -> list[Maridaje]:
    return datos.listar_maridajes(conn)


@router.get("/salas", summary="Salas de venta con su localidad, por id")
def salas(conn: Connection = Depends(conexion)) -> list[Sala]:
    return datos.listar_salas(conn)
