"""Consultas de los reportes de sólo lectura (issue #31).

Son S1, S8, S6 y S7 de consultas/select.sql (Etapa 5), con los valores fijos
convertidos en parámetros. Los cambios respecto de la Etapa 5 son:

- un desempate estable en el ORDER BY (código de vino o de sala): sin él,
  dos filas con el mismo valor podrían salir en distinto orden en cada
  llamada, y el LIMIT de S1 podría cortar distinto;
- S8 recibe un período [desde, hasta]; por omisión, el último trimestre,
  como en la Etapa 5;
- S7 recibe la cantidad de días (la Etapa 5 usaba "1 month") y devuelve
  todos los transportistas empatados en el primer puesto, no uno solo.

Los importes son los guardados en comprobante: la API no los recalcula.

La trazabilidad (issue #32) no tiene consulta de la Etapa 5: es un supuesto
documentado en docs/requisitos.md (ver TRAZABILIDAD).
"""

import json
from datetime import date
from decimal import Decimal
from functools import partial

from psycopg import Connection
from psycopg.rows import dict_row
from psycopg.types.json import set_json_loads


# S1. Agrega toda la historia de ventas: ningún índice la acelera (la mide
# docs/rendimiento.md, C7).
TOP_VINOS = """
SELECT v.cod_vino, v.nombre, v.tipo, v.precio,
       b.razon_social AS bodega,
       SUM(rc.cantidad) AS total_botellas
FROM renglon_comprobante AS rc
JOIN vino AS v ON v.cod_vino = rc.cod_vino
JOIN bodega AS b ON b.cuit = v.cuit_bodega
GROUP BY v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social
ORDER BY total_botellas DESC, v.cod_vino
LIMIT %(limite)s
"""

# Período efectivo de S8. Los valores por omisión los calcula la base con su
# CURRENT_DATE, igual que la consulta de la Etapa 5, y no el reloj de la API.
PERIODO_VENTAS = """
SELECT COALESCE(%(desde)s::date, (CURRENT_DATE - INTERVAL '3 months')::date) AS desde,
       COALESCE(%(hasta)s::date, CURRENT_DATE) AS hasta
"""

# S8. hasta es inclusivo: fecha es TIMESTAMPTZ, así que se compara con el
# comienzo del día siguiente. El rango sobre fecha usa idx_comprobante_fecha.
VENTAS_POR_SALA = """
SELECT s.id_sala, s.calle, s.numero,
       l.nombre AS localidad,
       count(*) AS num_comprobantes,
       SUM(c.subtotal) AS importe_bruto,
       SUM(c.descuento) AS total_descuento,
       SUM(c.total) AS total_ventas
FROM comprobante AS c
JOIN sala_venta AS s ON s.id_sala = c.id_sala
JOIN localidad AS l ON l.id_localidad = s.id_localidad
WHERE c.fecha >= %(desde)s::date
  AND c.fecha < %(hasta)s::date + 1
GROUP BY s.id_sala, s.calle, s.numero, l.nombre
ORDER BY total_ventas DESC, s.id_sala
"""

SALA_EXISTE = "SELECT EXISTS (SELECT 1 FROM sala_venta WHERE id_sala = %(id_sala)s)"

# S6. Para una sala inexistente devolvería todos los vinos con stock en el
# depósito (el LEFT JOIN no encuentra stock de sala); por eso el endpoint
# verifica antes la sala.
VINOS_SIN_STOCK = """
SELECT v.cod_vino, v.nombre, v.tipo, v.graduacion, v.precio,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0) AS stock_deposito
FROM vino AS v
LEFT JOIN stock_sala AS s
  ON s.id_sala = %(id_sala)s
 AND s.cod_vino = v.cod_vino
LEFT JOIN stock_deposito AS d
  ON d.cod_vino = v.cod_vino
WHERE COALESCE(s.cantidad, 0) = 0
  AND COALESCE(d.cantidad, 0) > 0
ORDER BY v.nombre, v.cod_vino
"""

# S7. FETCH FIRST 1 ROW WITH TIES devuelve el primero y todos los que empatan
# con él en el ORDER BY; el LIMIT 1 de la Etapa 5 elegía uno al azar.
TRANSPORTISTA_ACTIVO = """
SELECT t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio,
       count(i.cod_ingreso) AS ingresos
FROM transportista AS t
JOIN ingreso AS i ON i.cod_transportista = t.cod_transportista
WHERE i.fecha >= CURRENT_DATE - %(dias)s::integer
GROUP BY t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio
ORDER BY ingresos DESC
FETCH FIRST 1 ROW WITH TIES
"""


def _filas(conn: Connection, sql: str, params: dict) -> list[dict]:
    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(sql, params).fetchall()


def top_vinos(conn: Connection, limite: int) -> list[dict]:
    return _filas(conn, TOP_VINOS, {"limite": limite})


def periodo_ventas(conn: Connection, desde: date | None, hasta: date | None) -> tuple[date, date]:
    """El período pedido, con el último trimestre por omisión."""

    return conn.execute(PERIODO_VENTAS, {"desde": desde, "hasta": hasta}).fetchone()


def ventas_por_sala(conn: Connection, desde: date, hasta: date) -> list[dict]:
    return _filas(conn, VENTAS_POR_SALA, {"desde": desde, "hasta": hasta})


def sala_existe(conn: Connection, id_sala: int) -> bool:
    return conn.execute(SALA_EXISTE, {"id_sala": id_sala}).fetchone()[0]


def vinos_sin_stock(conn: Connection, id_sala: int) -> list[dict]:
    return _filas(conn, VINOS_SIN_STOCK, {"id_sala": id_sala})


def transportista_activo(conn: Connection, dias: int) -> list[dict]:
    """Los transportistas con más ingresos en los últimos ``dias`` días, con empates."""

    return _filas(conn, TRANSPORTISTA_ACTIVO, {"dias": dias})


# --- Trazabilidad (issue #32) -------------------------------------------------

# El modelo no registra qué lotes se usaron para elaborar un vino. Supuesto
# (docs/requisitos.md, sección 3.8): los lotes "posibles" de un vino son los
# que su bodega recibió en la campaña de su añada, de parcelas plantadas con
# alguna cepa de su corte. Es una aproximación, no una trazabilidad exacta.
# Una sola sentencia, con json_agg anidado, como la ficha de vinos: una sola
# foto de los datos. Los lotes van por fecha de cosecha y los análisis de
# cada lote por fecha.
TRAZABILIDAD = """
SELECT v.cod_vino, v.nombre, v.anada, v.cuit_bodega,
       b.razon_social AS bodega,
       (SELECT json_agg(json_build_object(
                 'id_cepa', c.id_cepa, 'cepa', c.nombre, 'tipo_cepa', c.tipo,
                 'porcentaje', cv.porcentaje)
               ORDER BY cv.porcentaje DESC, c.id_cepa)
        FROM composicion_vino AS cv
        JOIN cepa AS c ON c.id_cepa = cv.id_cepa
        WHERE cv.cod_vino = v.cod_vino) AS corte,
       COALESCE(
         (SELECT json_agg(json_build_object(
                   'nro_lote', l.nro_lote,
                   'campania', l.campania,
                   'fecha_cosecha', l.fecha_cosecha,
                   'kilos', l.kilos,
                   'id_cepa', c.id_cepa,
                   'cepa', c.nombre,
                   'id_finca', f.id_finca,
                   'finca', f.nombre,
                   'departamento', d.nombre,
                   'provincia', d.provincia,
                   'nro_parcela', l.nro_parcela,
                   'analisis', COALESCE(
                     (SELECT json_agg(json_build_object(
                               'fecha_analisis', a.fecha_analisis,
                               'grado_brix', a.grado_brix,
                               'ph', a.ph,
                               'acidez_total', a.acidez_total)
                             ORDER BY a.fecha_analisis, a.id_analisis)
                      FROM analisis_calidad AS a
                      WHERE a.nro_lote = l.nro_lote),
                     '[]'::json))
                 ORDER BY l.fecha_cosecha, l.nro_lote)
          FROM lote_uva AS l
          JOIN parcela AS p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
          JOIN composicion_vino AS cv ON cv.cod_vino = v.cod_vino AND cv.id_cepa = p.id_cepa
          JOIN cepa AS c ON c.id_cepa = p.id_cepa
          JOIN finca AS f ON f.id_finca = l.id_finca
          JOIN departamento AS d ON d.id_departamento = f.id_departamento
          WHERE l.cuit_bodega = v.cuit_bodega
            AND l.campania = v.anada),
         '[]'::json) AS lotes
FROM vino AS v
JOIN bodega AS b ON b.cuit = v.cuit_bodega
WHERE v.cod_vino = %(cod_vino)s
"""

# Por omisión, psycopg lee los números de un JSON como float. Con
# parse_float=Decimal, kilos, porcentajes y mediciones llegan exactos.
_JSON_CON_DECIMALES = partial(json.loads, parse_float=Decimal)


def trazabilidad(conn: Connection, cod_vino: int) -> dict | None:
    """El vino, su corte y los lotes que pudieron originarlo; None si el vino no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        set_json_loads(_JSON_CON_DECIMALES, cur)
        return cur.execute(TRAZABILIDAD, {"cod_vino": cod_vino}).fetchone()
