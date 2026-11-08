"""Consultas del catálogo de vinos (issue #25).

Cada filtro opcional tiene la forma ``(%(x)s::tipo IS NULL OR columna = %(x)s)``:
la consulta es siempre la misma y los valores viajan como parámetros, nunca
como texto del SQL. El cast le dice a PostgreSQL el tipo del parámetro aunque
llegue NULL.
"""

import json
from decimal import Decimal
from functools import partial

from psycopg import Connection
from psycopg.rows import dict_row
from psycopg.types.json import set_json_loads

from app.esquemas import FiltrosVino, Paginacion


# La cepa se filtra con EXISTS y no con JOIN: un JOIN a composicion_vino repite
# cada vino de corte una vez por cepa cuando el filtro no se usa, e inflaría
# count(*) OVER (). EXISTS es un semi-join: nunca multiplica filas.
# ORDER BY la PK: sin un orden total, LIMIT/OFFSET no da páginas estables.
LISTAR = """
SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
       v.cuit_bodega, b.razon_social AS bodega,
       count(*) OVER () AS total
FROM vino AS v
JOIN bodega AS b ON b.cuit = v.cuit_bodega
WHERE (%(tipo)s::varchar IS NULL OR v.tipo = %(tipo)s)
  AND (%(cuit_bodega)s::varchar IS NULL OR v.cuit_bodega = %(cuit_bodega)s)
  AND (%(anada)s::smallint IS NULL OR v.anada = %(anada)s)
  AND (%(id_cepa)s::integer IS NULL OR EXISTS (
        SELECT 1 FROM composicion_vino AS c
        WHERE c.cod_vino = v.cod_vino AND c.id_cepa = %(id_cepa)s))
ORDER BY v.cod_vino
LIMIT %(limite)s OFFSET %(desplazamiento)s
"""

# Mismo WHERE que LISTAR. Sólo se usa cuando la página quedó vacía por el
# desplazamiento y no hay filas de donde leer el total (api/README.md).
CONTAR = """
SELECT count(*)
FROM vino AS v
WHERE (%(tipo)s::varchar IS NULL OR v.tipo = %(tipo)s)
  AND (%(cuit_bodega)s::varchar IS NULL OR v.cuit_bodega = %(cuit_bodega)s)
  AND (%(anada)s::smallint IS NULL OR v.anada = %(anada)s)
  AND (%(id_cepa)s::integer IS NULL OR EXISTS (
        SELECT 1 FROM composicion_vino AS c
        WHERE c.cod_vino = v.cod_vino AND c.id_cepa = %(id_cepa)s))
"""


def listar(conn: Connection, filtros: FiltrosVino, pagina: Paginacion) -> tuple[list[dict], int]:
    """Una página de vinos que cumplen los filtros y el total sin paginar."""

    parametros = {
        "tipo": filtros.tipo,
        "cuit_bodega": filtros.cuit_bodega,
        "anada": filtros.anada,
        "id_cepa": filtros.id_cepa,
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


# Ficha completa en una sola sentencia: una sola foto de los datos. Con tres
# consultas sueltas en autocommit, un cambio de composición entre una y otra
# (PUT del #26) dejaría una ficha mezclada. Composición y maridajes salen
# estructurados con json_agg, en el mismo orden que v_ficha_vino, y se
# agregan en subconsultas propias para no multiplicar filas entre sí. El
# stock es el de v_stock_total_vino (depósito + salas).
DETALLE = """
SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
       v.cuit_bodega, b.razon_social AS bodega, st.stock_total,
       COALESCE((
         SELECT json_agg(json_build_object(
                  'id_cepa', c.id_cepa, 'cepa', ce.nombre, 'tipo_cepa', ce.tipo,
                  'porcentaje', c.porcentaje)
                ORDER BY c.porcentaje DESC, ce.nombre)
         FROM composicion_vino AS c
         JOIN cepa AS ce ON ce.id_cepa = c.id_cepa
         WHERE c.cod_vino = v.cod_vino), '[]') AS composicion,
       COALESCE((
         SELECT json_agg(json_build_object(
                  'id_maridaje', m.id_maridaje, 'nombre', m.nombre,
                  'temperatura_servicio_c', m.temperatura_servicio_c)
                ORDER BY m.nombre)
         FROM vino_maridaje AS vm
         JOIN maridaje AS m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = v.cod_vino), '[]') AS maridajes
FROM vino AS v
JOIN bodega AS b ON b.cuit = v.cuit_bodega
JOIN v_stock_total_vino AS st ON st.cod_vino = v.cod_vino
WHERE v.cod_vino = %(cod_vino)s
"""

# Por omisión, psycopg decodifica el JSON con json.loads, que convierte 85.00
# en float. Con parse_float=Decimal, porcentajes y temperaturas llegan exactos.
_JSON_CON_DECIMALES = partial(json.loads, parse_float=Decimal)


def detalle(conn: Connection, cod_vino: int) -> dict | None:
    """Ficha de un vino, o None si no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        set_json_loads(_JSON_CON_DECIMALES, cur)
        return cur.execute(DETALLE, {"cod_vino": cod_vino}).fetchone()
