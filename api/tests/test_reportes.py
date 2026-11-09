"""Reportes de sólo lectura (issue #31).

Criterio de aceptación: cada reporte devuelve lo mismo que su consulta de la
Etapa 5 (consultas/select.sql) con los mismos parámetros. Las consultas de
referencia de abajo son las de select.sql, sólo con el valor fijo
reemplazado por un parámetro. Las diferencias buscadas (desempate en el
orden, empates en S7) se comparan aparte.
"""

from datetime import timedelta
from decimal import Decimal
from typing import Any

import pytest


# --- Consultas de la Etapa 5 (consultas/select.sql) --------------------------

S1 = """
SELECT v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social AS bodega,
       SUM(rc.cantidad) AS total_botellas
  FROM bodegas.renglon_comprobante rc
  JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 GROUP BY v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social
 ORDER BY total_botellas DESC
 LIMIT %s
"""

# S8 tal cual: último trimestre, sin límite superior.
S8 = """
SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
       count(*) AS num_comprobantes, SUM(c.subtotal) AS importe_bruto,
       SUM(c.descuento) AS total_descuento, SUM(c.total) AS total_ventas
  FROM bodegas.comprobante c
  JOIN bodegas.sala_venta s ON s.id_sala = c.id_sala
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_ventas DESC
"""

# S8 con un período [desde, hasta] explícito, como lo recibe la API.
S8_PERIODO = S8.replace(
    "WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'",
    "WHERE c.fecha >= %s::date AND c.fecha < %s::date + 1")

S6 = """
SELECT v.cod_vino, v.nombre, v.tipo, v.graduacion, v.precio,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0) AS stock_deposito
  FROM bodegas.vino v
  LEFT JOIN bodegas.stock_sala s
    ON s.id_sala = %s
   AND s.cod_vino = v.cod_vino
  LEFT JOIN bodegas.stock_deposito d
    ON d.cod_vino = v.cod_vino
 WHERE COALESCE(s.cantidad, 0) = 0
   AND COALESCE(d.cantidad, 0) > 0
 ORDER BY v.nombre
"""

# S7 con días en lugar de "1 month" y sin LIMIT: el ranking completo.
S7 = """
SELECT t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio,
       count(i.cod_ingreso) AS ingresos_ultimo_mes
  FROM bodegas.transportista t
  JOIN bodegas.ingreso i ON i.cod_transportista = t.cod_transportista
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 day' * %s
 GROUP BY t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio
 ORDER BY ingresos_ultimo_mes DESC
"""


def _texto(valor: Any) -> Any:
    # La API envía los NUMERIC como string con su escala ("43660.00").
    return str(valor) if isinstance(valor, Decimal) else valor


def _filas(filas: list[tuple]) -> list[tuple]:
    return [tuple(_texto(v) for v in fila) for fila in filas]


def _items(respuesta) -> list[tuple]:
    assert respuesta.status_code == 200, respuesta.text
    return [tuple(item.values()) for item in respuesta.json()["items"]]


# --- S1: top-vinos ---------------------------------------------------------------

@pytest.mark.parametrize("limite", [10, 3])
def test_top_vinos_igual_que_s1(cliente, consultar_filas, limite) -> None:
    api = _items(cliente.get("/reportes/top-vinos", params={"limite": limite}))
    referencia = _filas(consultar_filas(S1, (limite,)))
    todas = set(_filas(consultar_filas(S1, (100_000,))))

    assert len(api) == limite
    # Las mismas cantidades en el mismo orden. Si hay empate en el último
    # puesto, la Etapa 5 corta al azar y la API por código de vino: por eso
    # se compara que cada fila de la API sea una fila real del ranking.
    assert [fila[-1] for fila in api] == [fila[-1] for fila in referencia]
    assert set(api) <= todas


# --- S8: ventas-por-sala ------------------------------------------------------------

def test_ventas_por_sala_sin_parametros_es_s8(cliente, consultar, consultar_filas) -> None:
    respuesta = cliente.get("/reportes/ventas-por-sala")
    api = _items(respuesta)

    assert api, "el último trimestre debería tener ventas"
    assert sorted(api) == sorted(_filas(consultar_filas(S8)))
    assert [fila[-1] for fila in api] == sorted((fila[-1] for fila in api), key=Decimal, reverse=True)
    datos = respuesta.json()
    assert datos["desde"] == consultar("SELECT (CURRENT_DATE - INTERVAL '3 months')::date").isoformat()
    assert datos["hasta"] == consultar("SELECT CURRENT_DATE").isoformat()


def test_ventas_por_sala_con_periodo(cliente, consultar, consultar_filas) -> None:
    # Un tramo de 30 días al comienzo de la historia cargada (depende de FECHA_REFERENCIA).
    hasta = consultar("SELECT min(fecha)::date + 60 FROM comprobante")
    desde = hasta - timedelta(days=30)

    respuesta = cliente.get("/reportes/ventas-por-sala", params={"desde": desde, "hasta": hasta})
    api = _items(respuesta)

    assert api
    assert respuesta.json()["desde"] == desde.isoformat()
    assert respuesta.json()["hasta"] == hasta.isoformat()
    assert sorted(api) == sorted(_filas(consultar_filas(S8_PERIODO, (desde, hasta))))


# --- S6: vinos-sin-stock --------------------------------------------------------------

def test_vinos_sin_stock_igual_que_s6(cliente, consultar, consultar_filas) -> None:
    # Una sala a la que le falte algún vino que el depósito tiene.
    id_sala = consultar(
        "SELECT min(s.id_sala) FROM sala_venta AS s WHERE EXISTS ("
        " SELECT 1 FROM stock_deposito AS d"
        " LEFT JOIN stock_sala AS ss ON ss.id_sala = s.id_sala AND ss.cod_vino = d.cod_vino"
        " WHERE d.cantidad > 0 AND COALESCE(ss.cantidad, 0) = 0)")
    assert id_sala is not None, "la carga no dejó vinos sin stock en ninguna sala"

    respuesta = cliente.get("/reportes/vinos-sin-stock", params={"id_sala": id_sala})
    api = _items(respuesta)

    assert api
    assert respuesta.json()["id_sala"] == id_sala
    assert sorted(api) == sorted(_filas(consultar_filas(S6, (id_sala,))))
    # Mismo orden que S6 (por nombre); la API desempata por código.
    assert [(f[1], f[0]) for f in api] == sorted((f[1], f[0]) for f in api)
    assert all(f[5] == 0 and f[6] > 0 for f in api)


def test_vinos_sin_stock_sala_inexistente_404(cliente) -> None:
    # S6 sola devolvería todos los vinos con stock en el depósito.
    respuesta = cliente.get("/reportes/vinos-sin-stock", params={"id_sala": 2_147_483_647})

    assert respuesta.status_code == 404, respuesta.text
    assert respuesta.json() == {"detail": "La sala 2147483647 no existe.", "codigo": "no_encontrado"}


# --- S7: transportista-activo ---------------------------------------------------------

@pytest.mark.parametrize("dias", [30, 3650])
def test_transportista_activo_igual_que_s7(cliente, consultar_filas, dias) -> None:
    respuesta = cliente.get("/reportes/transportista-activo", params={"dias": dias})
    api = _items(respuesta)
    ranking = _filas(consultar_filas(S7, (dias,)))

    assert api, "debería haber ingresos en el período"
    maximo = ranking[0][-1]
    # Todos los que empatan en el primer puesto, y sólo ellos. El primero de
    # la Etapa 5 (LIMIT 1) siempre está entre ellos.
    assert sorted(api) == sorted(fila for fila in ranking if fila[-1] == maximo)
    assert ranking[0] in api
    assert respuesta.json()["dias"] == dias


def test_transportista_activo_devuelve_todos_los_empatados(cliente, consultar, consultar_filas) -> None:
    """Fabrica un empate en el último día: la carga termina en FECHA_REFERENCIA,
    así que en ese período sólo cuentan los ingresos creados por las pruebas."""

    transportistas = [fila[0] for fila in consultar_filas(
        "SELECT cod_transportista FROM transportista ORDER BY cod_transportista LIMIT 2")]
    bodega = consultar("SELECT min(cuit) FROM bodega")
    cuenta = dict(consultar_filas(
        "SELECT cod_transportista, count(*) FROM ingreso "
        "WHERE fecha >= CURRENT_DATE - 1 GROUP BY cod_transportista"))
    objetivo = max([1, *cuenta.values()])
    # Los dos primeros transportistas llegan al máximo actual del período.
    for cod in transportistas:
        for _ in range(objetivo - cuenta.get(cod, 0)):
            alta = cliente.post("/ingresos", json={"cod_transportista": cod, "cuit_bodega": bodega})
            assert alta.status_code == 201, alta.text

    respuesta = cliente.get("/reportes/transportista-activo", params={"dias": 1})
    api = respuesta.json()["items"]

    # Los dos empatados aparecen; S7 con LIMIT 1 habría mostrado uno solo.
    assert set(transportistas) <= {item["cod_transportista"] for item in api}
    assert {item["ingresos"] for item in api} == {objetivo}


# --- Parámetros inválidos ---------------------------------------------------------------

@pytest.mark.parametrize(("ruta", "params"), [
    ("/reportes/top-vinos", {"limite": 0}),
    ("/reportes/top-vinos", {"limite": 101}),
    ("/reportes/top-vinos", {"limite": "diez"}),
    ("/reportes/ventas-por-sala", {"desde": "2026-02-30"}),
    ("/reportes/vinos-sin-stock", {}),
    ("/reportes/vinos-sin-stock", {"id_sala": 0}),
    ("/reportes/transportista-activo", {"dias": 0}),
    ("/reportes/transportista-activo", {"dias": 3651}),
])
def test_parametro_invalido_422(cliente, ruta, params) -> None:
    respuesta = cliente.get(ruta, params=params)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["codigo"] == "validacion"


@pytest.mark.parametrize("params", [
    {"desde": "2026-05-01", "hasta": "2026-04-01"},
    # Sólo hasta, anterior al comienzo del trimestre por omisión.
    {"hasta": "2000-01-01"},
])
def test_periodo_invertido_422(cliente, params) -> None:
    respuesta = cliente.get("/reportes/ventas-por-sala", params=params)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["codigo"] == "dato_invalido"
    assert respuesta.json()["detail"].startswith("El período es inválido: desde (")


# --- Trazabilidad (issue #32) ----------------------------------------------------

# Los lotes compatibles con un vino según el supuesto de docs/requisitos.md,
# escritos aparte del SQL de la API: misma bodega, campaña = añada y cepa
# de la parcela en el corte.
LOTES_COMPATIBLES = """
SELECT l.nro_lote
FROM lote_uva AS l
JOIN parcela AS p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
JOIN vino AS v ON v.cuit_bodega = l.cuit_bodega AND v.anada = l.campania
WHERE v.cod_vino = %s
  AND p.id_cepa IN (SELECT id_cepa FROM composicion_vino WHERE cod_vino = v.cod_vino)
ORDER BY l.fecha_cosecha, l.nro_lote
"""

VINO_CON_LOTES = """
SELECT min(v.cod_vino) FROM vino AS v
WHERE {} EXISTS (
  SELECT 1 FROM lote_uva AS l
  JOIN parcela AS p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
  JOIN composicion_vino AS cv ON cv.cod_vino = v.cod_vino AND cv.id_cepa = p.id_cepa
  WHERE l.cuit_bodega = v.cuit_bodega AND l.campania = v.anada)
"""


def test_trazabilidad_de_un_vino_con_lotes(cliente, consultar, consultar_filas) -> None:
    cod_vino = consultar(VINO_CON_LOTES.format(""))
    assert cod_vino is not None, "la carga no tiene vinos con lotes compatibles"

    respuesta = cliente.get(f"/reportes/trazabilidad/{cod_vino}")

    assert respuesta.status_code == 200, respuesta.text
    datos = respuesta.json()
    esperados = [fila[0] for fila in consultar_filas(LOTES_COMPATIBLES, (cod_vino,))]
    assert [lote["nro_lote"] for lote in datos["lotes"]] == esperados

    bodega, anada = consultar_filas("SELECT cuit_bodega, anada FROM vino WHERE cod_vino = %s", (cod_vino,))[0]
    assert (datos["cuit_bodega"], datos["anada"]) == (bodega, anada)
    cepas_del_corte = {cepa["id_cepa"] for cepa in datos["corte"]}
    for lote in datos["lotes"]:
        assert lote["campania"] == anada
        assert lote["id_cepa"] in cepas_del_corte
        assert len(lote["analisis"]) == consultar(
            "SELECT count(*) FROM analisis_calidad WHERE nro_lote = %s", (lote["nro_lote"],))
    # Los NUMERIC del JSON armado en PostgreSQL llegan exactos, como string.
    primero = datos["lotes"][0]
    assert primero["kilos"] == str(consultar("SELECT kilos FROM lote_uva WHERE nro_lote = %s",
                                             (primero["nro_lote"],)))


def test_trazabilidad_de_un_vino_sin_lotes(cliente, consultar) -> None:
    cod_vino = consultar(VINO_CON_LOTES.format("NOT"))
    assert cod_vino is not None, "la carga no tiene vinos sin lotes compatibles"

    respuesta = cliente.get(f"/reportes/trazabilidad/{cod_vino}")

    assert respuesta.status_code == 200, respuesta.text
    assert respuesta.json()["lotes"] == []
    assert respuesta.json()["corte"], "todo vino tiene corte (RN-05)"


def test_trazabilidad_de_un_vino_inexistente_404(cliente) -> None:
    respuesta = cliente.get("/reportes/trazabilidad/999999999")

    assert respuesta.status_code == 404, respuesta.text
    assert respuesta.json() == {"detail": "El vino 999999999 no existe.", "codigo": "no_encontrado"}


def test_trazabilidad_codigo_invalido_422(cliente) -> None:
    respuesta = cliente.get("/reportes/trazabilidad/0")

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"
