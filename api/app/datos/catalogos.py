"""Consultas de los catálogos de sólo lectura para los selectores del front (issue #49).

Son tablas de referencia chicas (15 cepas, 20 bodegas, 8 maridajes, 40 salas
en la carga completa): se devuelven enteras, sin paginar. Ninguna consulta
recibe valores externos. El ORDER BY termina en la clave primaria para que dos
filas con el mismo nombre salgan siempre en el mismo orden.
"""

from psycopg import Connection
from psycopg.rows import dict_row


CEPAS = """
SELECT id_cepa, nombre, tipo
FROM cepa
ORDER BY nombre, id_cepa
"""

BODEGAS = """
SELECT cuit, razon_social
FROM bodega
ORDER BY razon_social, cuit
"""

MARIDAJES = """
SELECT id_maridaje, nombre, temperatura_servicio_c
FROM maridaje
ORDER BY nombre, id_maridaje
"""

# La localidad va por nombre: el front muestra "calle número (localidad)" y
# no necesita un segundo pedido para resolver id_localidad.
SALAS = """
SELECT s.id_sala, s.calle, s.numero,
       l.nombre AS localidad
FROM sala_venta AS s
JOIN localidad AS l ON l.id_localidad = s.id_localidad
ORDER BY s.id_sala
"""


def _filas(conn: Connection, sql: str) -> list[dict]:
    with conn.cursor(row_factory=dict_row) as cur:
        return cur.execute(sql).fetchall()


def listar_cepas(conn: Connection) -> list[dict]:
    return _filas(conn, CEPAS)


def listar_bodegas(conn: Connection) -> list[dict]:
    return _filas(conn, BODEGAS)


def listar_maridajes(conn: Connection) -> list[dict]:
    return _filas(conn, MARIDAJES)


def listar_salas(conn: Connection) -> list[dict]:
    return _filas(conn, SALAS)
