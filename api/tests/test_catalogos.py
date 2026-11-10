"""GET /catalogos/* contra la base cargada (issue #49).

Cada lista se compara con la misma consulta ordenada hecha como bodegas_api:
mismas filas, mismo orden. Los datos salen del dataset, nunca escritos fijos.
"""

import os
from decimal import Decimal

import httpx
import pytest


def test_tipos_de_vino(cliente) -> None:
    respuesta = cliente.get("/catalogos/tipos-vino")

    assert respuesta.status_code == 200
    # Los de ck_vino_tipo (002_constraints.sql), en el orden del CHECK.
    assert respuesta.json() == ["tinto", "blanco", "rosado", "espumante"]


# ruta, claves del contrato, tabla para contar y la consulta ordenada esperada
CATALOGOS = [
    ("cepas", ["id_cepa", "nombre", "tipo"], "cepa",
     "SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre, id_cepa"),
    ("bodegas", ["cuit", "razon_social"], "bodega",
     "SELECT cuit, razon_social FROM bodega ORDER BY razon_social, cuit"),
    ("maridajes", ["id_maridaje", "nombre", "temperatura_servicio_c"], "maridaje",
     "SELECT id_maridaje, nombre, temperatura_servicio_c FROM maridaje ORDER BY nombre, id_maridaje"),
    ("salas", ["id_sala", "calle", "numero", "localidad"], "sala_venta",
     "SELECT s.id_sala, s.calle, s.numero, l.nombre FROM sala_venta AS s "
     "JOIN localidad AS l ON l.id_localidad = s.id_localidad ORDER BY s.id_sala"),
]


@pytest.mark.parametrize(("ruta", "claves", "tabla", "esperada"), CATALOGOS,
                         ids=[c[0] for c in CATALOGOS])
def test_catalogo_completo_y_ordenado(cliente, consultar, consultar_filas,
                                      ruta, claves, tabla, esperada) -> None:
    respuesta = cliente.get(f"/catalogos/{ruta}")

    assert respuesta.status_code == 200, respuesta.text
    items = respuesta.json()
    assert items, "la carga debería tener filas"
    assert all(list(item) == claves for item in items)
    # tabla sale de CATALOGOS, no de una entrada externa.
    assert len(items) == consultar(f"SELECT count(*) FROM {tabla}")
    # str() iguala el Decimal de la base con el string del JSON.
    assert [[str(item[c]) for c in claves] for item in items] == \
        [[str(v) for v in fila] for fila in consultar_filas(esperada)]


def test_temperatura_como_string_decimal(cliente) -> None:
    for maridaje in cliente.get("/catalogos/maridajes").json():
        temperatura = maridaje["temperatura_servicio_c"]
        # NUMERIC(4,1): un decimal exacto, "16.0", sin pasar por float.
        assert isinstance(temperatura, str)
        assert Decimal(temperatura).as_tuple().exponent == -1


def test_localidad_de_cada_sala(cliente, consultar) -> None:
    for sala in cliente.get("/catalogos/salas").json():
        assert sala["localidad"] == consultar(
            "SELECT l.nombre FROM sala_venta AS s JOIN localidad AS l USING (id_localidad) "
            "WHERE s.id_sala = %s", (sala["id_sala"],))


def test_las_cinco_rutas_en_openapi(cliente) -> None:
    rutas = cliente.get("/openapi.json").json()["paths"]

    for ruta in ["tipos-vino", "cepas", "bodegas", "maridajes", "salas"]:
        operacion = rutas[f"/catalogos/{ruta}"]["get"]
        assert operacion["tags"] == ["catalogos"]
        assert operacion["summary"]


def test_salas_por_el_proxy() -> None:
    # El circuito que usa el navegador: nginx (/api) -> API -> PostgreSQL.
    respuesta = httpx.get(f"{os.environ['FRONT_URL']}/api/catalogos/salas", timeout=5)

    assert respuesta.status_code == 200
    assert respuesta.json()
