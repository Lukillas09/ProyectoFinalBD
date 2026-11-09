"""Consultas de los documentos de stock: transferencias (issue #29) e ingresos (issue #30).

Cada documento tiene sus constantes SQL y una función por operación, con el
nombre del documento en el nombre (``crear_transferencia``,
``procesar_transferencia``, ...). Las de ingresos van al lado, con el mismo
formato. No se arma SQL genérico con nombres de tabla variables: cada consulta
se lee completa tal como llega a PostgreSQL.

Estado, fecha de confección y stock los mantiene la base. Este módulo crea la
cabecera, agrega renglones mientras el documento está en confección e invoca
los procedimientos sp_terminar_* y sp_procesar_*: el rol de la API no tiene
UPDATE sobre los estados ni sobre el stock (007_roles.sql).
"""

from psycopg import Connection
from psycopg.rows import dict_row


# --- Transferencias -------------------------------------------------------

# Sólo id_sala: estado y fecha los fijan el DEFAULT y trg_transferencia_fecha
# (RN-11). bodegas_api tiene INSERT únicamente sobre esa columna.
ALTA_TRANSFERENCIA = """
INSERT INTO transferencia (id_sala)
VALUES (%(id_sala)s)
RETURNING nro_transferencia
"""

# Un renglón para una transferencia existente. El INSERT ... SELECT no
# inserta nada si la transferencia no existe, y RETURNING sin fila es el 404:
# sin consulta previa no hay ventana entre "existe" y "agrego" (y la API no
# puede borrar transferencias). Sin esto, el trigger RN-12 dejaría pasar el
# renglón y la FK respondería 23503, que es 422. El bloqueo de una
# transferencia que ya no está en confección (RN-12), la cantidad positiva y
# el vino repetido los rechaza la base.
RENGLON_TRANSFERENCIA = """
INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
SELECT t.nro_transferencia, %(cod_vino)s::bigint, %(cantidad)s::integer
FROM transferencia AS t
WHERE t.nro_transferencia = %(nro)s
RETURNING nro_transferencia
"""

# Procedimientos SECURITY DEFINER: validan la transición (RN-11) y, al
# procesar, mueven el stock del depósito a la sala con FOR UPDATE. Un número
# inexistente responde P0002 (404).
TERMINAR_TRANSFERENCIA = "CALL sp_terminar_transferencia(%(nro)s::bigint)"
PROCESAR_TRANSFERENCIA = "CALL sp_procesar_transferencia(%(nro)s::bigint)"

# Cabecera y renglones en una sola sentencia: una sola foto de los datos,
# aunque otro pedido agregue un renglón al mismo tiempo.
TRANSFERENCIA = """
SELECT t.nro_transferencia, t.id_sala, t.fecha_confeccion, t.estado,
       COALESCE(
         (SELECT json_agg(json_build_object(
                   'cod_vino', r.cod_vino,
                   'nombre_vino', v.nombre,
                   'cantidad', r.cantidad)
                 ORDER BY r.cod_vino)
          FROM renglon_transferencia AS r
          JOIN vino AS v ON v.cod_vino = r.cod_vino
          WHERE r.nro_transferencia = t.nro_transferencia),
         '[]'::json) AS renglones
FROM transferencia AS t
WHERE t.nro_transferencia = %(nro)s
"""


def crear_transferencia(conn: Connection, id_sala: int) -> int:
    """Crea la cabecera en confección y devuelve su número."""

    return conn.execute(ALTA_TRANSFERENCIA, {"id_sala": id_sala}).fetchone()[0]


def agregar_renglon_transferencia(conn: Connection, nro: int, cod_vino: int, cantidad: int) -> bool:
    """Agrega un renglón; False si la transferencia no existe."""

    fila = conn.execute(
        RENGLON_TRANSFERENCIA, {"nro": nro, "cod_vino": cod_vino, "cantidad": cantidad}
    ).fetchone()
    return fila is not None


def terminar_transferencia(conn: Connection, nro: int) -> None:
    conn.execute(TERMINAR_TRANSFERENCIA, {"nro": nro})


def procesar_transferencia(conn: Connection, nro: int) -> None:
    conn.execute(PROCESAR_TRANSFERENCIA, {"nro": nro})


def obtener_transferencia(conn: Connection, nro: int) -> dict | None:
    """Cabecera y renglones, o None si la transferencia no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(TRANSFERENCIA, {"nro": nro}).fetchone()


# --- Ingresos ---------------------------------------------------------------

# Sólo transportista y bodega: estado y fecha los fijan los DEFAULT (RN-10).
# bodegas_api tiene INSERT únicamente sobre esas dos columnas.
ALTA_INGRESO = """
INSERT INTO ingreso (cod_transportista, cuit_bodega)
VALUES (%(cod_transportista)s, %(cuit_bodega)s)
RETURNING cod_ingreso
"""

# Mismo INSERT ... SELECT que en transferencias: sin fila devuelta, el
# ingreso no existe (404). RN-12 (sólo en confección) y RN-16 (vino de la
# bodega de origen, 009_ingreso_bodega.sql) los rechazan sus triggers.
RENGLON_INGRESO = """
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT i.cod_ingreso, %(cod_vino)s::bigint, %(cantidad)s::integer
FROM ingreso AS i
WHERE i.cod_ingreso = %(cod)s
RETURNING cod_ingreso
"""

# sp_procesar_ingreso suma al depósito con FOR UPDATE de la cabecera:
# procesar dos veces no suma dos veces (RN-10).
TERMINAR_INGRESO = "CALL sp_terminar_ingreso(%(cod)s::bigint)"
PROCESAR_INGRESO = "CALL sp_procesar_ingreso(%(cod)s::bigint)"

INGRESO = """
SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transportista, i.cuit_bodega,
       COALESCE(
         (SELECT json_agg(json_build_object(
                   'cod_vino', r.cod_vino,
                   'nombre_vino', v.nombre,
                   'cantidad', r.cantidad)
                 ORDER BY r.cod_vino)
          FROM renglon_ingreso AS r
          JOIN vino AS v ON v.cod_vino = r.cod_vino
          WHERE r.cod_ingreso = i.cod_ingreso),
         '[]'::json) AS renglones
FROM ingreso AS i
WHERE i.cod_ingreso = %(cod)s
"""


def crear_ingreso(conn: Connection, cod_transportista: int, cuit_bodega: str) -> int:
    """Crea la cabecera en confección y devuelve su código."""

    fila = conn.execute(
        ALTA_INGRESO, {"cod_transportista": cod_transportista, "cuit_bodega": cuit_bodega}
    ).fetchone()
    return fila[0]


def agregar_renglon_ingreso(conn: Connection, cod: int, cod_vino: int, cantidad: int) -> bool:
    """Agrega un renglón; False si el ingreso no existe."""

    fila = conn.execute(
        RENGLON_INGRESO, {"cod": cod, "cod_vino": cod_vino, "cantidad": cantidad}
    ).fetchone()
    return fila is not None


def terminar_ingreso(conn: Connection, cod: int) -> None:
    conn.execute(TERMINAR_INGRESO, {"cod": cod})


def procesar_ingreso(conn: Connection, cod: int) -> None:
    conn.execute(PROCESAR_INGRESO, {"cod": cod})


def obtener_ingreso(conn: Connection, cod: int) -> dict | None:
    """Cabecera y renglones, o None si el ingreso no existe."""

    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(INGRESO, {"cod": cod}).fetchone()
