"""Pantalla 5: tablero (top 10, ventas por sala con gráfico y vinos sin stock).

Sólo lee: cada sección se compara con lo que devuelve la API.
"""

import re
from decimal import Decimal

from playwright.sync_api import Page, expect

from ayudas import moneda, normalizar

TOP = "Top 10 vinos más vendidos"
VENTAS = re.compile(r"^Ventas por sala")
SIN_STOCK = "Vinos sin stock en una sala"
SALUD_503 = '{"detail": "Base de datos no disponible.", "codigo": "no_disponible"}'


def test_el_top_10_es_el_de_la_api(page: Page, api) -> None:
    items = api.get("reportes/top-vinos?limite=10").json()["items"]
    assert len(items) == 10

    page.goto("/#/tablero")
    top = page.get_by_role("region", name=TOP)
    filas = top.locator("tbody tr")
    expect(filas).to_have_count(10)

    vistas = [[normalizar(c) for c in fila.locator("td").all_inner_texts()] for fila in filas.all()]
    esperadas = [
        [str(posicion), v["nombre"], v["tipo"], v["bodega"], moneda(v["precio"]), str(v["total_botellas"])]
        for posicion, v in enumerate(items, start=1)
    ]
    assert vistas == esperadas


def test_el_grafico_de_ventas_tiene_una_barra_por_sala_y_la_primera_es_la_mayor(page: Page, api) -> None:
    items = api.get("reportes/ventas-por-sala").json()["items"]
    assert len(items) > 1
    totales = [Decimal(v["total_ventas"]) for v in items]
    # La API ordena de mayor a menor: es la base la que decide cuál es la primera.
    assert totales == sorted(totales, reverse=True)

    page.goto("/#/tablero")
    ventas = page.get_by_role("region", name=VENTAS)
    barras = ventas.locator("svg rect.tablero__barra")
    expect(barras).to_have_count(len(items))

    anchos = barras.evaluate_all("barras => barras.map(b => Number(b.getAttribute('width')))")
    assert anchos[0] == max(anchos) > 0
    assert anchos == sorted(anchos, reverse=True)

    # La primera barra es la sala de mayor total, y los importes son los de la base.
    etiquetas = [normalizar(t) for t in ventas.locator("svg text.tablero__etiqueta").all_text_contents()]
    assert etiquetas[0].startswith(f"Sala {items[0]['id_sala']} ·")
    importes = [normalizar(t) for t in ventas.locator("svg text.tablero__importe").all_text_contents()]
    assert importes == [moneda(v["total_ventas"]) for v in items]
    # Y la tabla de abajo tiene una fila por sala.
    expect(ventas.locator("tbody tr")).to_have_count(len(items))


def test_vinos_sin_stock_de_una_sala_tiene_las_filas_de_la_api(page: Page, api, id_sala) -> None:
    items = api.get(f"reportes/vinos-sin-stock?id_sala={id_sala}").json()["items"]
    assert items

    page.goto("/#/tablero")
    sin_stock = page.get_by_role("region", name=SIN_STOCK)
    sala = sin_stock.get_by_label("Sala")
    expect(sala).to_be_enabled()
    sala.select_option(str(id_sala))
    sin_stock.get_by_role("button", name="Consultar").click()

    expect(sin_stock.get_by_text(re.compile(rf"^{len(items)} vinos?$"))).to_be_visible()
    expect(sin_stock.locator("tbody tr")).to_have_count(len(items))


def test_un_503_en_top_vinos_deja_visibles_las_otras_dos_secciones(page: Page) -> None:
    page.route("**/api/reportes/top-vinos*", lambda ruta: ruta.fulfill(
        status=503, content_type="application/json", body=SALUD_503))

    page.goto("/#/tablero")

    expect(page.get_by_role("region", name=TOP).get_by_role("alert")).to_contain_text("503 · no_disponible")
    # El gráfico de ventas y el selector de salas siguen funcionando.
    ventas = page.get_by_role("region", name=VENTAS)
    expect(ventas.locator("svg rect.tablero__barra").first).to_be_visible()
    sin_stock = page.get_by_role("region", name=SIN_STOCK)
    expect(sin_stock.get_by_label("Sala")).to_be_enabled()
    expect(page.get_by_role("alert")).to_have_count(1)
