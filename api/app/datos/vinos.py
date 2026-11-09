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

from app.esquemas import CepaDeCorte, FiltrosVino, Paginacion, VinoEntrada


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


# --- Alta (issue #26) -----------------------------------------------------
# Estas funciones no abren transacciones: las llama el endpoint dentro de
# ``with conn.transaction():``, porque la regla de la composición al 100 % es
# un constraint trigger diferido y falla recién en el COMMIT (api/README.md).

# cod_vino es GENERATED ALWAYS AS IDENTITY: lo asigna la base. bodegas_api no
# tiene USAGE sobre la secuencia y no lo necesita, porque el valor por omisión
# de una columna IDENTITY no verifica ese privilegio (lo comprueba
# tests/test_vinos_abm.py).
INSERTAR = """
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES (%(nombre)s, %(tipo)s, %(anada)s, %(volumen_ml)s, %(graduacion)s, %(precio)s, %(cuit_bodega)s)
RETURNING cod_vino
"""

# Las listas se insertan con unnest de arrays: una sola sentencia por tabla,
# sin importar cuántas cepas o maridajes traiga el vino, con el mismo patrón
# de arrays paralelos que fn_registrar_venta. Los dos arrays salen de la misma
# lista validada, así que siempre tienen el mismo largo. El cast da el tipo
# también a una lista vacía.
INSERTAR_COMPOSICION = """
INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje)
SELECT %(cod_vino)s, c.id_cepa, c.porcentaje
FROM unnest(%(cepas)s::integer[], %(porcentajes)s::numeric[]) AS c(id_cepa, porcentaje)
"""

INSERTAR_MARIDAJES = """
INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT %(cod_vino)s, m.id_maridaje
FROM unnest(%(maridajes)s::integer[]) AS m(id_maridaje)
"""


def _columnas(vino: VinoEntrada) -> dict:
    return vino.model_dump(include={"nombre", "tipo", "anada", "volumen_ml",
                                    "graduacion", "precio", "cuit_bodega"})


def insertar(conn: Connection, vino: VinoEntrada) -> int:
    """Inserta la fila de vino y devuelve el cod_vino que asignó la base."""

    fila = conn.execute(INSERTAR, _columnas(vino)).fetchone()
    assert fila is not None  # INSERT … RETURNING siempre devuelve la fila
    return fila[0]


def insertar_composicion(conn: Connection, cod_vino: int, composicion: list[CepaDeCorte]) -> None:
    conn.execute(INSERTAR_COMPOSICION, {
        "cod_vino": cod_vino,
        "cepas": [c.id_cepa for c in composicion],
        "porcentajes": [c.porcentaje for c in composicion],
    })


def insertar_maridajes(conn: Connection, cod_vino: int, maridajes: list[int]) -> None:
    conn.execute(INSERTAR_MARIDAJES, {"cod_vino": cod_vino, "maridajes": maridajes})


# --- Modificación (issue #26) ---------------------------------------------

# Reemplazo completo. precio va siempre en el SET: trg_vino_auditoria_precio
# (AFTER UPDATE OF precio) se evalúa, pero su WHEN (OLD.precio IS DISTINCT
# FROM NEW.precio) descarta los cambios que no existen. La auditoría la
# escribe ese trigger; la API no tiene permiso sobre auditoria_precio.
# RETURNING dice si el vino existía, sin una consulta previa. El UPDATE además
# bloquea la fila hasta el COMMIT: dos PUT del mismo vino se ordenan solos.
ACTUALIZAR = """
UPDATE vino
SET nombre = %(nombre)s, tipo = %(tipo)s, anada = %(anada)s, volumen_ml = %(volumen_ml)s,
    graduacion = %(graduacion)s, precio = %(precio)s, cuit_bodega = %(cuit_bodega)s
WHERE cod_vino = %(cod_vino)s
RETURNING cod_vino
"""

BORRAR_COMPOSICION = "DELETE FROM composicion_vino WHERE cod_vino = %(cod_vino)s"
BORRAR_MARIDAJES = "DELETE FROM vino_maridaje WHERE cod_vino = %(cod_vino)s"


def actualizar(conn: Connection, cod_vino: int, vino: VinoEntrada) -> bool:
    """Reemplaza los datos del vino. False si el vino no existe."""

    return conn.execute(ACTUALIZAR, {**_columnas(vino), "cod_vino": cod_vino}).fetchone() is not None


# Composición y maridajes se reemplazan enteros: DELETE de las filas del vino
# e INSERT de las nuevas, dentro de la transacción del endpoint. La suma al
# 100 % la revisa el trigger diferido una vez, al confirmar, sobre el estado
# final; si falla, el ROLLBACK deja la composición anterior intacta.
def reemplazar_composicion(conn: Connection, cod_vino: int, composicion: list[CepaDeCorte]) -> None:
    conn.execute(BORRAR_COMPOSICION, {"cod_vino": cod_vino})
    insertar_composicion(conn, cod_vino, composicion)


def reemplazar_maridajes(conn: Connection, cod_vino: int, maridajes: list[int]) -> None:
    conn.execute(BORRAR_MARIDAJES, {"cod_vino": cod_vino})
    insertar_maridajes(conn, cod_vino, maridajes)


# --- Baja (issue #26) -----------------------------------------------------

# Una sola sentencia, en autocommit. composicion_vino y vino_maridaje caen por
# ON DELETE CASCADE (el trigger diferido de la composición ignora un vino
# borrado). Ventas, ingresos, transferencias, stock y auditoría de precio
# tienen ON DELETE RESTRICT (RN-14): el 23503 "update or delete on table" lo
# traduce app/errores.py a 409.
BORRAR = "DELETE FROM vino WHERE cod_vino = %(cod_vino)s RETURNING cod_vino"


def borrar(conn: Connection, cod_vino: int) -> bool:
    """Borra el vino. False si no existe."""

    return conn.execute(BORRAR, {"cod_vino": cod_vino}).fetchone() is not None
