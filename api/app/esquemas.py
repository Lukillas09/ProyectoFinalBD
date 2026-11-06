"""Modelos Pydantic y parámetros compartidos por todos los endpoints."""

from typing import Generic, TypeVar

from fastapi import Query
from pydantic import BaseModel, Field


T = TypeVar("T")


class Paginacion:
    """Parámetros de paginación de los listados, validados por FastAPI.

    Uso: ``pagina: Paginacion = Depends()``. Fuera de rango, la respuesta es
    422 con codigo "validacion" (app/errores.py).
    """

    def __init__(
        self,
        limite: int = Query(20, ge=1, le=100, description="Cantidad de filas (1 a 100)."),
        desplazamiento: int = Query(0, ge=0, description="Filas a saltear desde el comienzo."),
    ) -> None:
        self.limite = limite
        self.desplazamiento = desplazamiento


class Pagina(BaseModel, Generic[T]):
    """Respuesta de un listado: ``Pagina[VinoResumen]``, por ejemplo.

    ``total`` es la cantidad de filas que cumplen los filtros, sin paginar.
    Un desplazamiento mayor que el total responde 200 con ``items`` vacío.
    """

    items: list[T]
    limite: int
    desplazamiento: int
    total: int


class ErrorCampo(BaseModel):
    """Un dato de entrada inválido, según la validación de FastAPI."""

    campo: str = Field(examples=["query.limite"])
    mensaje: str


class ErrorRespuesta(BaseModel):
    """Cuerpo de toda respuesta de error de la API (docs/api.md, sección 3).

    El front muestra siempre ``detail``. Los demás campos sirven para decidir
    o para depurar, y aparecen sólo cuando corresponden.
    """

    detail: str = Field(examples=["RN-09: stock insuficiente del vino 1 en la sala 1."])
    codigo: str = Field(
        examples=["P0001"],
        description="SQLSTATE de PostgreSQL, 'validacion', 'no_disponible' o 'interno'.",
    )
    restriccion: str | None = Field(
        default=None,
        examples=["uq_vino_identidad_comercial"],
        description="Restricción violada (23505, 23503, 23514).",
    )
    columna: str | None = Field(
        default=None, description="Columna sin valor (23502)."
    )
    errores: list[ErrorCampo] | None = Field(
        default=None, description="Datos de entrada inválidos (codigo 'validacion')."
    )
