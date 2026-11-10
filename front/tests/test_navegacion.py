"""Navegación entre las cinco pantallas y el indicador de salud."""

import re

import pytest
from playwright.sync_api import Page, expect

PESTANAS = [
    ("Catálogo", "Catálogo de vinos"),
    ("Nuevo vino", "Nuevo vino"),
    ("Nueva venta", "Nueva venta"),
    ("Transferencias", "Transferencias"),
    ("Tablero", "Tablero"),
]

# Lo que responde nginx cuando la API no puede hablar con la base.
SALUD_503 = '{"detail": "Base de datos no disponible.", "codigo": "no_disponible"}'


@pytest.mark.parametrize(("pestana", "titulo"), PESTANAS)
def test_cada_pestana_carga_su_pantalla(page: Page, pestana: str, titulo: str) -> None:
    page.goto("/#/vinos")
    navegacion = page.get_by_role("navigation", name="Secciones principales")

    navegacion.get_by_role("link", name=pestana, exact=True).click()

    # Las pantallas pendientes muestran un h2 y el texto "pendiente"; las
    # implementadas, un h1.
    expect(page.get_by_role("heading", level=1, name=titulo, exact=True)).to_be_visible()
    expect(page.locator("#vista")).not_to_contain_text("pendiente")
    # La pestaña activa es la única con aria-current.
    expect(navegacion.get_by_role("link", name=pestana, exact=True)).to_have_attribute("aria-current", "page")
    expect(navegacion.locator("[aria-current]")).to_have_count(1)


def test_el_indicador_de_salud_dice_disponible(page: Page) -> None:
    page.goto("/#/vinos")

    expect(page.locator("#estado-texto")).to_have_text("Sistema disponible")
    expect(page.locator("#estado")).to_have_class(re.compile(r"estado--disponible"))


def test_con_un_503_el_indicador_pasa_a_no_disponible_y_se_recupera(page: Page) -> None:
    page.route("**/api/salud", lambda ruta: ruta.fulfill(
        status=503, content_type="application/json", body=SALUD_503))

    page.goto("/#/vinos")

    expect(page.locator("#estado-texto")).to_have_text("Sistema no disponible")
    expect(page.locator("#estado-detalle")).to_contain_text("503 · no_disponible")
    expect(page.locator("#estado")).to_have_class(re.compile(r"estado--no-disponible"))

    # Al volver la base, "Reintentar" vuelve a consultar y el indicador se recupera.
    page.unroute("**/api/salud")
    page.get_by_role("button", name="Reintentar").click()
    expect(page.locator("#estado-texto")).to_have_text("Sistema disponible")
