"""Fixtures comunes de las pruebas de la API.

Las pruebas corren dentro de Docker (servicio api-test), conectadas como
bodegas_api, contra un proyecto de Compose aislado y cargado (ver
api/README.md, "Pruebas"). Nunca se conectan como propietario.

Las rutas /_prueba/... existen sólo en la aplicación que arma la fixture
``cliente``: provocan errores reales de PostgreSQL para probar su traducción.
La aplicación de producción (app.main.app) no las tiene.
"""

import os
import uuid
from collections.abc import Callable, Iterator
from typing import Any

import psycopg
import pytest
from fastapi import Depends
from fastapi.testclient import TestClient
from psycopg import Connection

from app.database import conexion
from app.esquemas import Pagina, Paginacion
from app.main import crear_app


# --- Datos de la base, como bodegas_api ------------------------------------

def _conectar() -> Connection:
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        autocommit=True,
        options="-c search_path=bodegas,pg_catalog",
    )


@pytest.fixture(scope="session")
def consultar() -> Iterator[Callable[..., Any]]:
    """Ejecuta una consulta de lectura en una conexión aparte y devuelve el
    primer valor. Sirve para buscar datos del catálogo y para verificar que
    un error no dejó datos a medias."""

    conn = _conectar()

    def ejecutar(sql: str, params: tuple = ()) -> Any:
        fila = conn.execute(sql, params).fetchone()
        return None if fila is None else fila[0]

    yield ejecutar
    conn.close()


@pytest.fixture
def marca() -> str:
    """Valor único por prueba, para no chocar con el dataset ni con otras pruebas."""

    return "prueba-" + uuid.uuid4().hex[:10]


# --- Escenarios que provocan errores reales --------------------------------
# Cada escenario recibe una conexión dentro de una transacción y la marca de
# la prueba. Todos terminan en error, así que la transacción se revierte.

VINO = (
    "INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega) "
    "VALUES (%s, 'tinto', 2024, 750, 13.5, %s, (SELECT min(cuit) FROM bodega))"
)


def _unico(conn: Connection, marca: str) -> None:
    conn.execute(VINO, (marca, 1000))
    conn.execute(VINO, (marca, 1000))


def _falta_relacionado(conn: Connection, marca: str) -> None:
    conn.execute("INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje) VALUES (-1, 1, 100)")


def _con_dependientes(conn: Connection, marca: str) -> None:
    conn.execute(VINO, (marca, 1000))
    conn.execute("UPDATE vino SET precio = 2000 WHERE nombre = %s", (marca,))  # auditoría (RN-13)
    conn.execute("DELETE FROM vino WHERE nombre = %s", (marca,))


ESCENARIOS: dict[str, Callable[[Connection, str], None]] = {
    "unico": _unico,
    "falta_relacionado": _falta_relacionado,
    "con_dependientes": _con_dependientes,
    "check": lambda conn, marca: conn.execute(VINO, (marca, -5)),
    "no_nulo": lambda conn, marca: conn.execute(VINO, (None, 1000)),
    "largo": lambda conn, marca: conn.execute(VINO, (marca + "x" * 200, 1000)),
    "fuera_de_rango": lambda conn, marca: conn.execute("SELECT %s::smallint", (100000,)),
    "formato": lambda conn, marca: conn.execute("SELECT %s::integer", ("abc",)),
    "regla": lambda conn, marca: conn.execute(
        "SELECT fn_registrar_venta(1, 1, ARRAY[]::BIGINT[], ARRAY[]::INTEGER[])"),
    "no_existe": lambda conn, marca: conn.execute("CALL sp_procesar_transferencia(-1)"),
    "permiso": lambda conn, marca: conn.execute("SELECT count(*) FROM parcela"),
    "serializacion": lambda conn, marca: conn.execute(
        "DO $$ BEGIN RAISE EXCEPTION 'conflicto simulado' USING ERRCODE = '40001'; END $$"),
    # Constraint trigger diferido: el error aparece recién en el COMMIT.
    "diferido": lambda conn, marca: conn.execute(
        "INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, "
        "id_localidad, tipo) VALUES (%s, 'DNI', %s, 'Calle 1', (SELECT min(id_localidad) FROM localidad), "
        "'socio')", (marca, marca[-10:])),
}


def _localidades(conn: Connection, pagina: Paginacion) -> Pagina[dict]:
    # Patrón de listado paginado documentado en api/README.md: el total sale
    # de la misma consulta con count(*) OVER (); si la página quedó vacía por
    # el desplazamiento, no hay filas de donde leerlo y se cuenta aparte.
    filas = conn.execute(
        "SELECT id_localidad, nombre, count(*) OVER () AS total FROM localidad "
        "ORDER BY id_localidad LIMIT %s OFFSET %s",
        (pagina.limite, pagina.desplazamiento),
    ).fetchall()
    if filas:
        total = filas[0][2]
    elif pagina.desplazamiento > 0:
        total = conn.execute("SELECT count(*) FROM localidad").fetchone()[0]
    else:
        total = 0
    return Pagina[dict](
        items=[{"id_localidad": f[0], "nombre": f[1]} for f in filas],
        limite=pagina.limite, desplazamiento=pagina.desplazamiento, total=total,
    )


def _app_de_prueba():
    app = crear_app()

    def provocar(caso: str, marca: str, conn: Connection = Depends(conexion)) -> dict[str, str]:
        with conn.transaction():
            ESCENARIOS[caso](conn, marca)
        return {"resultado": "sin error"}

    def localidades(pagina: Paginacion = Depends(), conn: Connection = Depends(conexion)) -> Pagina[dict]:
        return _localidades(conn, pagina)

    app.add_api_route("/_prueba/error/{caso}", provocar, methods=["POST"])
    app.add_api_route("/_prueba/localidades", localidades)
    return app


@pytest.fixture(scope="session")
def cliente() -> Iterator[TestClient]:
    """Cliente HTTP de una aplicación igual a la real más las rutas de prueba."""

    with TestClient(_app_de_prueba()) as cliente_http:
        yield cliente_http
