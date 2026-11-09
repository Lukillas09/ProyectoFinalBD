"""Acceso a datos para comprobantes y ventas (Etapa 6).

Concentra el SQL parametrizado: la API invoca a fn_registrar_venta
para registrar una venta completa, y consulta afterwards los datos
persistidos. No se calculan importes en Python.
"""

from psycopg import Connection

from app.esquemas import ComprobanteRenglonEntrada


# ---------------------------------------------------------------------------
# Registro de venta: convierte los renglones de la API en arrays paralelos
# y delega en fn_registrar_venta. La transacción la llama el endpoint.
# ---------------------------------------------------------------------------

# Los renglones vienen de la API como lista de {cod_vino, cantidad}.
# fn_registrar_venta espera dos arrays paralelos: BIGINT[] y INTEGER[].
# Esta función los construye y llama a la función.

_VENDER_SQL = "SELECT fn_registrar_venta(%s, %s, %s, %s)"


def registrar_venta(conn: Connection, id_cliente: int, id_sala: int, renglones: list[ComprobanteRenglonEntrada]) -> int:
    """Registra una venta completa mediante fn_registrar_venta.

    Args:
        conn: conexión abierta (la transacción la administra el endpoint).
        id_cliente: identificador del cliente.
        id_sala: identificador de la sala de venta.
        renglones: lista de ComprobanteRenglonEntrada.

    Returns:
        El nro_comprobante generado.

    Raises:
        psycopg.Error si fn_registrar_venta falla (stock insuficiente, vino
        repetido, cantidad no positiva, cliente/sala inexistente, vino
        inexistente).
    """

    vinos: list[int] = [r.cod_vino for r in renglones]
    cantidades: list[int] = [r.cantidad for r in renglones]

    with conn.cursor() as cur:
        cur.execute(_VENDER_SQL, (id_cliente, id_sala, vinos, cantidades))
        # fn_registrar_venta devuelve nro_comprobante BIGINT
        fila = cur.fetchone()
        assert fila is not None, "fn_registrar_venta no devolvió nro_comprobante"
        return fila[0]


# ---------------------------------------------------------------------------
# Consulta de un comprobante existente
# ---------------------------------------------------------------------------

_OBTENER_COMPROBANTE_SQL = """
SELECT c.nro_comprobante,
       c.fecha,
       c.id_cliente,
       c.id_sala,
       c.subtotal,
       c.descuento,
       fn_total_comprobante(c.nro_comprobante) AS total
FROM bodegas.comprobante AS c
WHERE c.nro_comprobante = %s
"""


def obtener_comprobante(conn: Connection, nro_comprobante: int) -> dict | None:
    """Consulta la cabecera de un comprobante y sus importes.

    Args:
        conn: conexión abierta.
        nro_comprobante: número de comprobante a buscar.

    Returns:
        Diccionario con los datos de la cabecera y el total, o None si no
        existe.
    """

    with conn.cursor() as cur:
        cur.execute(_OBTENER_COMPROBANTE_SQL, (nro_comprobante,))
        fila = cur.fetchone()
        if fila is None:
            return None
        return {
            "nro_comprobante": fila[0],
            "fecha": str(fila[1]) if fila[1] is not None else "",
            "id_cliente": fila[2],
            "id_sala": fila[3],
            "subtotal": str(fila[4]) if fila[4] is not None else "0",
            "descuento": str(fila[5]) if fila[5] is not None else "0",
            "total": str(fila[6]) if fila[6] is not None else "0",
        }


# ---------------------------------------------------------------------------
# Renglones del comprobante (después de registrada la venta)
# ---------------------------------------------------------------------------

_OBTENER_Renglones_SQL = """
SELECT rc.cod_vino,
       v.nombre AS nombre_vino,
       rc.cantidad,
       rc.subtotal AS total
FROM bodegas.renglon_comprobante AS rc
JOIN bodegas.vino AS v ON v.cod_vino = rc.cod_vino
JOIN bodegas.comprobante AS c ON c.nro_comprobante = rc.nro_comprobante
WHERE c.nro_comprobante = %s
ORDER BY rc.cod_vino
"""


def obtener_renglones(conn: Connection, nro_comprobante: int) -> list[dict]:
    """Devuelve los renglones de un comprobante con nombre de vino.

    Args:
        conn: conexión abierta.
        nro_comprobante: número de comprobante.

    Returns:
        Lista de diccionarios {cod_vino, nombre_vino, cantidad, total_parcial}.
    """

    with conn.cursor() as cur:
        cur.execute(_OBTENER_Renglones_SQL, (nro_comprobante,))
        return [
            {
                "cod_vino": row[0],
                "nombre_vino": row[1],
                "cantidad": row[2],
                "total_parcial": str(row[3]) if row[3] is not None else "0",
            }
            for row in cur.fetchall()
        ]