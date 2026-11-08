"""Consultas de clientes (issue #27).

Mismo patrón que datos/vinos.py: cada filtro opcional es
``(%(x)s::tipo IS NULL OR columna = %(x)s)``, con la consulta siempre igual y
los valores como parámetros.
"""

from psycopg import Connection
from psycopg.rows import dict_row

from app.esquemas import FiltrosCliente, Paginacion


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
