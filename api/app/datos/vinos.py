"""Consultas del catálogo de vinos (issue #25).

Cada filtro opcional tiene la forma ``(%(x)s::tipo IS NULL OR columna = %(x)s)``:
la consulta es siempre la misma y los valores viajan como parámetros, nunca
como texto del SQL. El cast le dice a PostgreSQL el tipo del parámetro aunque
llegue NULL.
"""

from psycopg import Connection
from psycopg.rows import dict_row

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

