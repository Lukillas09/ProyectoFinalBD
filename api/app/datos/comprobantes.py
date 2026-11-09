"""Consultas de comprobantes y ventas (issue #28).

La venta completa la registra fn_registrar_venta en una sola llamada: precio,
descuento, subtotales, totales y stock los calcula PostgreSQL. Este módulo sólo
la invoca y lee lo que quedó guardado.
"""

from psycopg import Connection
from psycopg.rows import dict_row


# fn_registrar_venta recibe los renglones como dos arreglos paralelos.
VENDER = """
SELECT fn_registrar_venta(%(id_cliente)s, %(id_sala)s,
                          %(vinos)s::bigint[], %(cantidades)s::integer[])
       AS nro_comprobante
"""

# Vinos pedidos que no existen. Se consulta antes de vender porque, para un
# vino inexistente, la base responde 23502 sobre precio_unitario: un mensaje
# que no le dice al cliente qué dato está mal (docs/api.md, Comprobantes).
VINOS_INEXISTENTES = """
SELECT pedido.cod_vino
FROM unnest(%(vinos)s::bigint[]) AS pedido (cod_vino)
WHERE NOT EXISTS (SELECT 1 FROM vino AS v WHERE v.cod_vino = pedido.cod_vino)
ORDER BY pedido.cod_vino
"""

# Los importes de la cabecera son los guardados: los mantiene la base (RN-08).
CABECERA = """
SELECT c.nro_comprobante, c.fecha, c.id_cliente, c.id_sala,
       c.subtotal, c.descuento, c.total
FROM comprobante AS c
WHERE c.nro_comprobante = %(nro)s
"""

RENGLONES = """
SELECT r.cod_vino, v.nombre AS nombre_vino, r.cantidad, r.precio_unitario,
       r.descuento_porcentaje, r.subtotal AS total_parcial
FROM renglon_comprobante AS r
JOIN vino AS v ON v.cod_vino = r.cod_vino
WHERE r.nro_comprobante = %(nro)s
ORDER BY r.cod_vino
"""


def vinos_inexistentes(conn: Connection, vinos: list[int]) -> list[int]:
    """Códigos pedidos que no corresponden a ningún vino."""

    filas = conn.execute(VINOS_INEXISTENTES, {"vinos": vinos}).fetchall()
    return [fila[0] for fila in filas]


def registrar_venta(
    conn: Connection, id_cliente: int, id_sala: int, vinos: list[int], cantidades: list[int]
) -> int:
    """Llama a fn_registrar_venta y devuelve el número de comprobante."""

    fila = conn.execute(
        VENDER,
        {"id_cliente": id_cliente, "id_sala": id_sala, "vinos": vinos, "cantidades": cantidades},
    ).fetchone()
    return fila[0]


def obtener(conn: Connection, nro: int) -> dict | None:
    """Cabecera y renglones de un comprobante, o None si no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        cabecera = cur.execute(CABECERA, {"nro": nro}).fetchone()
        if cabecera is None:
            return None
        cabecera["renglones"] = cur.execute(RENGLONES, {"nro": nro}).fetchall()
    return cabecera
