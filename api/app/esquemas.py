"""Modelos Pydantic y parámetros de los endpoints.

Los importes y demás NUMERIC se modelan con Decimal, nunca con float. Pydantic
los serializa como string en el JSON ("4500.00"): se conserva la escala exacta
de PostgreSQL y el valor no pasa por un double (docs/api.md, "Vinos").
"""

from decimal import Decimal
from typing import Generic, Literal, TypeVar

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
        description=(
            "SQLSTATE de PostgreSQL, 'validacion', 'no_disponible', 'interno' o el código "
            "de un error HTTP propio ('no_encontrado', 'metodo_no_permitido', ...)."
        ),
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


# --- Vinos (issue #25) ----------------------------------------------------

# Los valores de ck_vino_tipo (002_constraints.sql).
TipoVino = Literal["tinto", "blanco", "rosado", "espumante"]

# Rangos de los tipos de PostgreSQL: un valor fuera de rango responde 422 sin
# llegar a la base.
MAX_INTEGER = 2_147_483_647
MAX_BIGINT = 9_223_372_036_854_775_807


class FiltrosVino:
    """Filtros opcionales de GET /vinos, combinados con AND.

    Cada uno se valida con el mismo dominio que la columna en la base, así un
    valor inválido responde 422 (codigo "validacion") y nunca llega al SQL.
    """

    def __init__(
        self,
        tipo: TipoVino | None = Query(None, description="Tipo de vino (ck_vino_tipo)."),
        id_cepa: int | None = Query(None, ge=1, le=MAX_INTEGER,
                                    description="Vinos que tienen esta cepa en su composición."),
        cuit_bodega: str | None = Query(None, pattern=r"^[0-9]{11}$",
                                        description="CUIT de la bodega: 11 dígitos (cuit_dom)."),
        anada: int | None = Query(None, ge=1900, le=9999, description="Añada (ck_vino_anada)."),
    ) -> None:
        self.tipo = tipo
        self.id_cepa = id_cepa
        self.cuit_bodega = cuit_bodega
        self.anada = anada


class VinoResumen(BaseModel):
    """Un vino del listado. Mismos nombres que el cuerpo de POST /vinos (#26)."""

    cod_vino: int
    nombre: str
    tipo: TipoVino
    anada: int
    volumen_ml: int
    graduacion: Decimal = Field(examples=["13.50"])
    precio: Decimal = Field(examples=["4500.00"], description="Pesos, como string con 2 decimales.")
    cuit_bodega: str
    bodega: str = Field(description="Razón social de la bodega.")


class CepaEnVino(BaseModel):
    """Una cepa de la composición de un vino."""

    id_cepa: int
    cepa: str
    tipo_cepa: Literal["tinta", "blanca"]
    porcentaje: Decimal = Field(examples=["85.00"])


class MaridajeDeVino(BaseModel):
    """Un maridaje sugerido para un vino."""

    id_maridaje: int
    nombre: str
    temperatura_servicio_c: Decimal = Field(examples=["16.0"])


class VinoDetalle(VinoResumen):
    """Ficha de un vino: composición y maridajes estructurados, para editar."""

    stock_total: int = Field(description="Depósito central más la suma de las salas.")
    composicion: list[CepaEnVino] = Field(description="Ordenada por porcentaje, de mayor a menor.")
    maridajes: list[MaridajeDeVino] = Field(description="Ordenados por nombre.")
