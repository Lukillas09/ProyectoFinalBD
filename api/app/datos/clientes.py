"""Consultas de clientes (issue #27).

Mismo patrón que datos/vinos.py: cada filtro opcional es
``(%(x)s::tipo IS NULL OR columna = %(x)s)``, con la consulta siempre igual y
los valores como parámetros.
"""

from psycopg import Connection
from psycopg.rows import dict_row

from app.esquemas import (
    ClienteBase, ClienteEntrada, DistribuidorEntrada, ExportadorEntrada, FiltrosCliente, Paginacion,
    PermisoExportacion, SocioEntrada,
)


# ORDER BY la PK: sin un orden total, LIMIT/OFFSET no da páginas estables.
LISTAR = """
SELECT c.id_cliente, c.nombre_razon_social, c.tipo_documento, c.nro_documento, c.tipo,
       c.id_localidad, l.nombre AS localidad,
       count(*) OVER () AS total
FROM cliente AS c
JOIN localidad AS l ON l.id_localidad = c.id_localidad
WHERE (%(tipo)s::tipo_cliente IS NULL OR c.tipo = %(tipo)s::tipo_cliente)
  AND (%(id_localidad)s::integer IS NULL OR c.id_localidad = %(id_localidad)s)
ORDER BY c.id_cliente
LIMIT %(limite)s OFFSET %(desplazamiento)s
"""

# Mismo WHERE que LISTAR, para la página vacía por el desplazamiento.
CONTAR = """
SELECT count(*)
FROM cliente AS c
WHERE (%(tipo)s::tipo_cliente IS NULL OR c.tipo = %(tipo)s::tipo_cliente)
  AND (%(id_localidad)s::integer IS NULL OR c.id_localidad = %(id_localidad)s)
"""


def listar(conn: Connection, filtros: FiltrosCliente, pagina: Paginacion) -> tuple[list[dict], int]:
    """Una página de clientes que cumplen los filtros y el total sin paginar."""

    parametros = {
        "tipo": filtros.tipo,
        "id_localidad": filtros.id_localidad,
        "limite": pagina.limite,
        "desplazamiento": pagina.desplazamiento,
    }
    with conn.cursor(row_factory=dict_row) as cur:
        filas = cur.execute(LISTAR, parametros).fetchall()
        if filas:
            total = filas[0]["total"]
            for fila in filas:
                del fila["total"]
            return filas, total
        if pagina.desplazamiento > 0:
            fila = cur.execute(CONTAR, parametros).fetchone()
            return [], fila["count"] if fila else 0
        return [], 0


# Ficha en una sola sentencia, como la de vinos: una sola foto de los datos.
# Los LEFT JOIN traen la fila del subtipo que tenga (exactamente una, por la
# exclusividad y la totalidad de la jerarquía); las columnas de los otros
# subtipos llegan NULL y el modelo de la ficha las ignora. El descuento lo
# calcula la base con fn_descuento_cliente (RN-06), no la API.
DETALLE = """
SELECT c.id_cliente, c.nombre_razon_social, c.tipo_documento, c.nro_documento, c.direccion,
       c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.tipo,
       fn_descuento_cliente(c.id_cliente) AS descuento,
       d.zona_cobertura, d.nro_habilitacion, e.pais_destino_principal,
       COALESCE((
         SELECT json_agg(json_build_object(
                  'codigo_permiso', p.codigo_permiso, 'fecha_emision', p.fecha_emision,
                  'fecha_vencimiento', p.fecha_vencimiento)
                ORDER BY p.fecha_emision, p.codigo_permiso)
         FROM permiso_exportacion AS p
         WHERE p.id_exportador = c.id_cliente), '[]') AS permisos
FROM cliente AS c
JOIN localidad AS l ON l.id_localidad = c.id_localidad
LEFT JOIN distribuidor AS d ON d.id_cliente = c.id_cliente
LEFT JOIN exportador AS e ON e.id_cliente = c.id_cliente
WHERE c.id_cliente = %(id_cliente)s
"""


def detalle(conn: Connection, id_cliente: int) -> dict | None:
    """Ficha de un cliente con los datos de su subtipo, o None si no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(DETALLE, {"id_cliente": id_cliente}).fetchone()


# --- Alta (issue #27) -----------------------------------------------------
# Estas funciones no abren transacciones: las llama el endpoint dentro de
# ``with conn.transaction():``. La totalidad de la jerarquía (todo cliente
# tiene la fila de su subtipo) es un constraint trigger diferido y se
# verifica en el COMMIT; si una inserción falla, el ROLLBACK se lleva todo.

# id_cliente es IDENTITY y fecha_alta tiene DEFAULT CURRENT_DATE: los pone la
# base. descuento_excepcion no se escribe: el descuento no viaja en el cuerpo.
INSERTAR = """
INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo)
VALUES (%(nombre_razon_social)s, %(tipo_documento)s, %(nro_documento)s, %(direccion)s,
        %(id_localidad)s, %(tipo)s::tipo_cliente)
RETURNING id_cliente
"""

# La fila del subtipo no lleva tipo: lo pone su DEFAULT ('socio', ...), y la
# FK compuesta (id_cliente, tipo) comprueba que coincida con cliente.tipo.
INSERTAR_SOCIO = "INSERT INTO socio_club (id_cliente) VALUES (%(id_cliente)s)"

INSERTAR_DISTRIBUIDOR = """
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
VALUES (%(id_cliente)s, %(zona_cobertura)s, %(nro_habilitacion)s)
"""

INSERTAR_EXPORTADOR = """
INSERT INTO exportador (id_cliente, pais_destino_principal)
VALUES (%(id_cliente)s, %(pais_destino_principal)s)
"""

# Arrays paralelos con unnest, como la composición de un vino: una sentencia
# para todos los permisos. El cast da el tipo también a una lista vacía.
INSERTAR_PERMISOS = """
INSERT INTO permiso_exportacion (codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento)
SELECT p.codigo, %(id_cliente)s, p.emision, p.vencimiento
FROM unnest(%(codigos)s::varchar[], %(emisiones)s::date[], %(vencimientos)s::date[])
     AS p(codigo, emision, vencimiento)
"""


def _comunes(c: ClienteBase) -> dict:
    return c.model_dump(include={"nombre_razon_social", "tipo_documento", "nro_documento",
                                 "direccion", "id_localidad", "tipo"})


def insertar(conn: Connection, c: ClienteEntrada) -> int:
    """Inserta la fila de cliente y devuelve el id_cliente que asignó la base."""

    fila = conn.execute(INSERTAR, _comunes(c)).fetchone()
    assert fila is not None  # INSERT … RETURNING siempre devuelve la fila
    return fila[0]


def insertar_permisos(conn: Connection, id_cliente: int, permisos: list[PermisoExportacion]) -> None:
    conn.execute(INSERTAR_PERMISOS, {
        "id_cliente": id_cliente,
        "codigos": [p.codigo_permiso for p in permisos],
        "emisiones": [p.fecha_emision for p in permisos],
        "vencimientos": [p.fecha_vencimiento for p in permisos],
    })


def insertar_subtipo(conn: Connection, id_cliente: int, c: ClienteEntrada) -> None:
    """Inserta la fila del subtipo (y los permisos de un exportador).

    El isinstance sólo elige la tabla según el modelo que validó Pydantic; no
    decide ninguna regla.
    """

    if isinstance(c, SocioEntrada):
        conn.execute(INSERTAR_SOCIO, {"id_cliente": id_cliente})
    elif isinstance(c, DistribuidorEntrada):
        conn.execute(INSERTAR_DISTRIBUIDOR, {"id_cliente": id_cliente, "zona_cobertura": c.zona_cobertura,
                                             "nro_habilitacion": c.nro_habilitacion})
    else:
        conn.execute(INSERTAR_EXPORTADOR, {"id_cliente": id_cliente,
                                           "pais_destino_principal": c.pais_destino_principal})
        insertar_permisos(conn, id_cliente, c.permisos)


# --- Modificación (issue #27) ---------------------------------------------

# tipo va en el SET, igual que el precio de un vino. Con el mismo valor,
# PostgreSQL no revisa las FK que apuntan a (id_cliente, tipo). Si cambia, la
# FK compuesta del subtipo actual (ON UPDATE RESTRICT) rechaza el UPDATE con
# 23503 y app/errores.py lo traduce a 409: el tipo no se cambia porque la base
# lo impide, no porque lo revise la API. descuento_excepcion y fecha_alta no
# se tocan. RETURNING dice si el cliente existía, sin una consulta previa.
ACTUALIZAR = """
UPDATE cliente
SET nombre_razon_social = %(nombre_razon_social)s, tipo_documento = %(tipo_documento)s,
    nro_documento = %(nro_documento)s, direccion = %(direccion)s, id_localidad = %(id_localidad)s,
    tipo = %(tipo)s::tipo_cliente
WHERE id_cliente = %(id_cliente)s
RETURNING id_cliente
"""

ACTUALIZAR_DISTRIBUIDOR = """
UPDATE distribuidor
SET zona_cobertura = %(zona_cobertura)s, nro_habilitacion = %(nro_habilitacion)s
WHERE id_cliente = %(id_cliente)s
"""

ACTUALIZAR_EXPORTADOR = """
UPDATE exportador
SET pais_destino_principal = %(pais_destino_principal)s
WHERE id_cliente = %(id_cliente)s
"""

BORRAR_PERMISOS = "DELETE FROM permiso_exportacion WHERE id_exportador = %(id_cliente)s"


def actualizar(conn: Connection, id_cliente: int, c: ClienteEntrada) -> bool:
    """Reemplaza los datos comunes del cliente. False si el cliente no existe."""

    return conn.execute(ACTUALIZAR, {**_comunes(c), "id_cliente": id_cliente}).fetchone() is not None


def actualizar_subtipo(conn: Connection, id_cliente: int, c: ClienteEntrada) -> None:
    """Reemplaza los datos del subtipo. Los permisos de un exportador se
    reemplazan enteros: DELETE de los suyos e INSERT de los del cuerpo.

    Si el exportador tiene la excepción del 35 % y queda con tres permisos o
    menos, ctrg_permiso_excepcion (diferido) rechaza el COMMIT (RN-06) y el
    ROLLBACK deja los permisos como estaban.
    """

    if isinstance(c, DistribuidorEntrada):
        conn.execute(ACTUALIZAR_DISTRIBUIDOR, {"id_cliente": id_cliente, "zona_cobertura": c.zona_cobertura,
                                               "nro_habilitacion": c.nro_habilitacion})
    elif isinstance(c, ExportadorEntrada):
        conn.execute(ACTUALIZAR_EXPORTADOR, {"id_cliente": id_cliente,
                                             "pais_destino_principal": c.pais_destino_principal})
        conn.execute(BORRAR_PERMISOS, {"id_cliente": id_cliente})
        insertar_permisos(conn, id_cliente, c.permisos)
    # Un socio no tiene datos propios.


# --- Baja (issue #27) -----------------------------------------------------

# Una sola sentencia, en autocommit. La fila del subtipo y los permisos caen
# por ON DELETE CASCADE; los triggers diferidos de la jerarquía y de la
# excepción ignoran un cliente borrado. Con comprobantes, fk_comprobante_cliente
# (ON DELETE RESTRICT) da 23503 "update or delete on table" y app/errores.py lo
# traduce a 409.
BORRAR = "DELETE FROM cliente WHERE id_cliente = %(id_cliente)s RETURNING id_cliente"


def borrar(conn: Connection, id_cliente: int) -> bool:
    """Borra el cliente con su subtipo y sus permisos. False si no existe."""

    return conn.execute(BORRAR, {"id_cliente": id_cliente}).fetchone() is not None


def existe(conn: Connection, id_cliente: int) -> bool:
    """Verifica si existe un cliente con el dado id."""

    fila = conn.execute(
        "SELECT 1 FROM cliente WHERE id_cliente = %s LIMIT 1", (id_cliente,)
    ).fetchone()
    return fila is not None
