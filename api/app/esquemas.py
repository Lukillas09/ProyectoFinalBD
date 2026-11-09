"""Modelos Pydantic y parámetros de los endpoints.

Los importes y demás NUMERIC se modelan con Decimal, nunca con float. Pydantic
los serializa como string en el JSON ("4500.00"): se conserva la escala exacta
de PostgreSQL y el valor no pasa por un double (docs/api.md, "Vinos").
"""

from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Generic, Literal, TypeVar

from fastapi import Query
from pydantic import BaseModel, Field, field_validator


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


# --- Alta y modificación de vinos (issue #26) -----------------------------
# Pydantic valida sólo la forma: tipos, dominio y escala de cada columna,
# repetidos y al menos una cepa. Las reglas de negocio las decide PostgreSQL
# y llegan traducidas por app/errores.py: la suma 100 % (constraint trigger
# diferido, P0001), precio > 0, graduación 5-20, volumen > 0 y porcentaje en
# (0, 100] (CHECK, 23514). max_digits y decimal_places son la forma de la
# columna NUMERIC: sin ellos, PostgreSQL redondearía 1.234 a 1.23 en silencio.

class CepaDeCorte(BaseModel):
    """Una cepa del corte y su porcentaje."""

    id_cepa: int = Field(ge=1, le=MAX_INTEGER)
    porcentaje: Decimal = Field(max_digits=5, decimal_places=2, examples=["60.00"])


class VinoEntrada(BaseModel):
    """Cuerpo de POST /vinos y de PUT /vinos/{cod_vino} (reemplazo completo).

    Todos los campos son obligatorios, también ``maridajes``: en un PUT, un
    campo omitido no puede significar "borralo". Los decimales se aceptan como
    string ("4500.00", como los devuelve la API) o como número.
    """

    nombre: str = Field(min_length=1, max_length=100, examples=["Malbec Reserva"])
    tipo: TipoVino
    anada: int = Field(ge=1900, le=9999, description="Añada (ck_vino_anada).", examples=[2022])
    volumen_ml: int = Field(le=MAX_INTEGER, examples=[750])
    graduacion: Decimal = Field(max_digits=4, decimal_places=2, examples=["13.50"])
    precio: Decimal = Field(max_digits=14, decimal_places=2, examples=["4500.00"])
    cuit_bodega: str = Field(pattern=r"^[0-9]{11}$", description="CUIT de la bodega: 11 dígitos.")
    composicion: list[CepaDeCorte] = Field(min_length=1, description="Cepas sin repetir; deben sumar 100 %.")
    maridajes: list[Annotated[int, Field(ge=1, le=MAX_INTEGER)]] = Field(
        description="Códigos de maridaje sin repetir; puede ser [].")

    @field_validator("composicion")
    @classmethod
    def _cepas_sin_repetir(cls, composicion: list[CepaDeCorte]) -> list[CepaDeCorte]:
        cepas = [c.id_cepa for c in composicion]
        if len(cepas) != len(set(cepas)):
            raise ValueError("una cepa aparece más de una vez en la composición")
        return composicion

    @field_validator("maridajes")
    @classmethod
    def _maridajes_sin_repetir(cls, maridajes: list[int]) -> list[int]:
        if len(maridajes) != len(set(maridajes)):
            raise ValueError("un maridaje aparece más de una vez")
        return maridajes


# --- Clientes (issue #27) -------------------------------------------------
# Supertipo cliente y un subtipo por tipo (socio_club, distribuidor,
# exportador). El cuerpo y la ficha son uniones discriminadas por ``tipo``:
# cada tipo tiene sus propios campos obligatorios. Como en vinos, Pydantic
# valida sólo la forma (tipos y largos de los VARCHAR); las reglas las decide
# PostgreSQL. El descuento no viaja en el cuerpo: lo calcula
# fn_descuento_cliente (RN-06) y se muestra en la ficha.

# Los valores del ENUM tipo_cliente (001_esquema.sql).
TipoCliente = Literal["socio", "distribuidor", "exportador"]


class FiltrosCliente:
    """Filtros opcionales de GET /clientes, combinados con AND."""

    def __init__(
        self,
        tipo: TipoCliente | None = Query(None, description="Tipo de cliente (ENUM tipo_cliente)."),
        id_localidad: int | None = Query(None, ge=1, le=MAX_INTEGER, description="Localidad del cliente."),
    ) -> None:
        self.tipo = tipo
        self.id_localidad = id_localidad


class ClienteResumen(BaseModel):
    """Un cliente del listado. El descuento y los datos del subtipo están en la ficha."""

    id_cliente: int
    nombre_razon_social: str
    tipo_documento: str
    nro_documento: str
    tipo: TipoCliente
    id_localidad: int
    localidad: str = Field(description="Nombre de la localidad.")


class PermisoExportacion(BaseModel):
    """Un permiso de exportación. Que venza después de emitirse lo verifica la base."""

    codigo_permiso: str = Field(min_length=1, max_length=50, examples=["PE-2025-0001"])
    fecha_emision: date = Field(examples=["2025-03-01"])
    fecha_vencimiento: date = Field(examples=["2027-03-01"])


class ClienteBase(BaseModel):
    """Datos comunes de los tres tipos (tabla cliente)."""

    nombre_razon_social: str = Field(min_length=1, max_length=150, examples=["Distribuidora Cuyo S.A."])
    tipo_documento: str = Field(min_length=1, max_length=20, examples=["CUIT"])
    nro_documento: str = Field(min_length=1, max_length=30, examples=["30712345678"])
    direccion: str = Field(min_length=1, max_length=200, examples=["Av. San Martín 1234"])
    id_localidad: int = Field(ge=1, le=MAX_INTEGER)


class SocioEntrada(ClienteBase):
    """Socio del club: no tiene datos propios además de los comunes."""

    tipo: Literal["socio"]


class DistribuidorEntrada(ClienteBase):
    tipo: Literal["distribuidor"]
    zona_cobertura: str = Field(min_length=1, max_length=150, examples=["Sur de Mendoza"])
    nro_habilitacion: str = Field(min_length=1, max_length=50, examples=["HAB-0001"])


class ExportadorEntrada(ClienteBase):
    tipo: Literal["exportador"]
    pais_destino_principal: str = Field(min_length=1, max_length=100, examples=["Brasil"])
    permisos: list[PermisoExportacion] = Field(
        description="Permisos de exportación sin repetir códigos; puede ser [].")

    @field_validator("permisos")
    @classmethod
    def _codigos_sin_repetir(cls, permisos: list[PermisoExportacion]) -> list[PermisoExportacion]:
        codigos = [p.codigo_permiso for p in permisos]
        if len(codigos) != len(set(codigos)):
            raise ValueError("un código de permiso aparece más de una vez")
        return permisos


class _DatosDeLaBase(BaseModel):
    """Campos de la ficha que no se envían: los asigna o calcula PostgreSQL."""

    id_cliente: int
    localidad: str = Field(description="Nombre de la localidad.")
    fecha_alta: date = Field(description="La asigna la base al dar de alta (DEFAULT CURRENT_DATE).")
    descuento: Decimal = Field(
        examples=["30.00"],
        description="Porcentaje que se aplica en las ventas, calculado por fn_descuento_cliente (RN-06): "
                    "la excepción del 35 % si la tiene, o 10, 20 o 30 según el tipo.")


class SocioDetalle(SocioEntrada, _DatosDeLaBase):
    pass


class DistribuidorDetalle(DistribuidorEntrada, _DatosDeLaBase):
    pass


class ExportadorDetalle(ExportadorEntrada, _DatosDeLaBase):
    pass


# Ficha de GET /clientes/{id_cliente}: el campo tipo elige el modelo. Tiene los
# mismos campos que el cuerpo del PUT más los de _DatosDeLaBase, así que lo
# que devuelve el GET se puede volver a enviar (esos campos se ignoran).
ClienteDetalle = Annotated[
    SocioDetalle | DistribuidorDetalle | ExportadorDetalle, Field(discriminator="tipo")
]


# Cuerpo de POST /clientes y de PUT /clientes/{id_cliente}: el campo tipo elige
# el modelo, así un distribuidor sin nro_habilitacion responde 422 antes de
# llegar a la base. Un campo que no es del modelo, como descuento o
# descuento_excepcion, se ignora (como en VinoEntrada).
ClienteEntrada = Annotated[
    SocioEntrada | DistribuidorEntrada | ExportadorEntrada, Field(discriminator="tipo")
]


# --- Comprobantes (issue #28) ------------------------------------------------

class ComprobanteRenglonEntrada(BaseModel):
    """Renglón pedido en POST /comprobantes."""

    # Sólo la forma: que la cantidad sea positiva y que un vino no se repita lo
    # decide fn_registrar_venta (RN-15, RN-08), con su mensaje de regla.
    cod_vino: int = Field(ge=1, le=MAX_BIGINT)
    cantidad: int = Field(ge=-2_147_483_648, le=2_147_483_647)


class ComprobanteEntrada(BaseModel):
    """Cuerpo de POST /comprobantes."""

    id_cliente: int = Field(ge=1, le=MAX_BIGINT)
    id_sala: int = Field(ge=1, le=2_147_483_647)
    renglones: list[ComprobanteRenglonEntrada]


class ComprobanteRenglonRespuesta(BaseModel):
    """Renglón guardado: precio y descuento congelados al vender (RN-06)."""

    cod_vino: int
    nombre_vino: str
    cantidad: int
    precio_unitario: Decimal = Field(examples=["4500.00"])
    descuento_porcentaje: Decimal = Field(examples=["10.00"])
    total_parcial: Decimal = Field(
        examples=["4050.00"], description="Subtotal neto del renglón, calculado por la base."
    )


class ComprobanteSalida(BaseModel):
    """Respuesta de POST /comprobantes y de GET /comprobantes/{nro}."""

    nro_comprobante: int
    fecha: datetime
    id_cliente: int
    id_sala: int
    subtotal: Decimal = Field(examples=["4500.00"], description="Bruto: suma de cantidad × precio.")
    descuento: Decimal = Field(examples=["450.00"], description="Descuento en pesos.")
    total: Decimal = Field(examples=["4050.00"], description="Neto: subtotal − descuento.")
    renglones: list[ComprobanteRenglonRespuesta]
