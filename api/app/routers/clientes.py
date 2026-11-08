"""Clientes de los tres tipos: listado, ficha, alta, modificación y baja (issue #27).

Los endpoints no capturan psycopg.Error: lo traduce app/errores.py. Las
operaciones de varias sentencias abren la transacción acá, con
``with conn.transaction():``: la totalidad de la jerarquía es un constraint
trigger diferido que se verifica recién en el COMMIT, al salir del bloque.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Request, Response, status
from psycopg import Connection
from pydantic import TypeAdapter

from app.database import conexion
from app.datos import clientes as datos
from app.esquemas import (
    MAX_BIGINT, ClienteDetalle, ClienteEntrada, ClienteResumen, ErrorRespuesta, FiltrosCliente, Pagina,
    Paginacion,
)


router = APIRouter(prefix="/clientes", tags=["clientes"])

# Arma el modelo de la ficha que corresponde al tipo de la fila.
_FICHA = TypeAdapter(ClienteDetalle)


def _error(descripcion: str) -> dict:
    return {"model": ErrorRespuesta, "description": descripcion}


def _ficha(conn: Connection, id_cliente: int) -> ClienteDetalle:
    """La ficha del cliente, o 404. Después de un alta o una modificación se
    lee tras el COMMIT, en la misma conexión: muestra lo que quedó confirmado."""

    fila = datos.detalle(conn, id_cliente)
    if fila is None:
        raise HTTPException(404, f"El cliente {id_cliente} no existe.")
    return _FICHA.validate_python(fila)


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

    return _ficha(conn, id_cliente)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Dar de alta un cliente con su subtipo",
    responses={
        409: _error("Documento repetido (23505, uq_cliente_documento), habilitación repetida "
                    "(uq_distribuidor_habilitacion) o código de permiso ya usado (pk_permiso_exportacion)."),
        422: _error("Forma inválida (validacion: por ejemplo, un distribuidor sin nro_habilitacion), "
                    "permiso que vence antes de emitirse (23514) o localidad inexistente (23503)."),
    },
)
def crear_cliente(
    c: ClienteEntrada,
    request: Request,
    response: Response,
    conn: Connection = Depends(conexion),
) -> ClienteDetalle:
    """Inserta el cliente y la fila de su subtipo (y los permisos si es
    exportador) en **una transacción**. El cuerpo cambia según `tipo`.

    La base exige que todo cliente tenga la fila de su subtipo (constraint
    trigger diferido, verificado al confirmar): si cualquier inserción falla,
    no queda nada guardado. El descuento no se envía: lo calcula la base y
    aparece en la ficha que se responde.
    """

    with conn.transaction():
        id_cliente = datos.insertar(conn, c)
        datos.insertar_subtipo(conn, id_cliente, c)
    # Ruta relativa con el prefijo público, como en vinos: /clientes/N directo
    # y /api/clientes/N por nginx.
    response.headers["Location"] = request.scope.get("root_path", "") + router.url_path_for(
        "obtener_cliente", id_cliente=id_cliente)
    return _ficha(conn, id_cliente)


@router.put(
    "/{id_cliente}",
    summary="Modificar un cliente (datos comunes y del subtipo)",
    responses={
        404: _error("El cliente no existe."),
        409: _error("Cambio de tipo (23503: la FK compuesta del subtipo lo impide, por ejemplo "
                    "fk_socio_club_cliente), documento, habilitación o permiso repetido (23505), o un "
                    "exportador con la excepción del 35 % que queda con tres permisos o menos (P0001, RN-06)."),
        422: _error("Forma inválida (validacion), permiso que vence antes de emitirse (23514) o "
                    "localidad inexistente (23503)."),
    },
)
def modificar_cliente(
    c: ClienteEntrada,
    id_cliente: int = Path(ge=1, le=MAX_BIGINT, description="Código del cliente."),
    conn: Connection = Depends(conexion),
) -> ClienteDetalle:
    """Reemplaza los datos comunes y los del subtipo, **incluidos los permisos**
    de un exportador, en una transacción.

    **El `tipo` no se puede cambiar**: tiene que ser el del cliente. Si es
    otro, la clave foránea compuesta del subtipo actual rechaza el cambio y
    responde 409. `fecha_alta` y el descuento no se modifican por acá.
    """

    with conn.transaction():
        if not datos.actualizar(conn, id_cliente, c):
            raise HTTPException(404, f"El cliente {id_cliente} no existe.")
        datos.actualizar_subtipo(conn, id_cliente, c)
    return _ficha(conn, id_cliente)
