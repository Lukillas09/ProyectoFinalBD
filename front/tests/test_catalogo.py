"""Pantalla 1: catálogo de vinos (filtros, paginación, detalle y 404)."""

import math
import re

from playwright.sync_api import Page, expect

POR_PAGINA = 20  # el catálogo pide de a 20 (limite=20)


def resumen(total: int) -> re.Pattern:
    """El texto "Página N de M · T vinos" con el total que devuelve la API."""

    return re.compile(rf"Página 1 de {math.ceil(total / POR_PAGINA)} · {total} vinos$")


def test_un_filtro_por_cepa_coincide_con_el_total_de_la_api(page: Page, api, consultar) -> None:
    id_cepa = consultar(
        "SELECT id_cepa FROM composicion_vino GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1")[0][0]
    total = api.get(f"vinos?id_cepa={id_cepa}&limite=1").json()["total"]
    assert total > 0

    page.goto("/#/vinos")
    page.get_by_label("Cepa").select_option(str(id_cepa))
    page.get_by_role("button", name="Filtrar").click()

    expect(page.get_by_text(resumen(total))).to_be_visible()
    # Los filtros viven en la URL (Atrás y recargar funcionan).
    expect(page).to_have_url(re.compile(rf"#/vinos\?id_cepa={id_cepa}$"))


def test_un_filtro_combinado_coincide_con_el_total_de_la_api(page: Page, api, consultar) -> None:
    id_cepa = consultar(
        "SELECT id_cepa FROM composicion_vino GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1")[0][0]
    tipo = consultar(
        "SELECT v.tipo FROM vino AS v JOIN composicion_vino AS cv USING (cod_vino) "
        "WHERE cv.id_cepa = %s ORDER BY v.cod_vino LIMIT 1", (id_cepa,))[0][0]
    total = api.get(f"vinos?tipo={tipo}&id_cepa={id_cepa}&limite=1").json()["total"]
    assert total > 0

    page.goto("/#/vinos")
    page.get_by_label("Tipo").select_option(tipo)
    page.get_by_label("Cepa").select_option(str(id_cepa))
    page.get_by_role("button", name="Filtrar").click()

    expect(page.get_by_text(resumen(total))).to_be_visible()


def test_un_filtro_sin_resultados_avisa(page: Page, api) -> None:
    assert api.get("vinos?tipo=espumante&anada=1900&limite=1").json()["total"] == 0

    page.goto("/#/vinos")
    page.get_by_label("Tipo").select_option("espumante")
    page.get_by_label("Añada").fill("1900")
    page.get_by_role("button", name="Filtrar").click()

    expect(page.get_by_text("No hay vinos con esos filtros.")).to_be_visible()


def test_la_paginacion_llega_a_la_ultima_pagina(page: Page, api) -> None:
    total = api.get("vinos?limite=1").json()["total"]
    ultima = math.ceil(total / POR_PAGINA)
    siguiente = page.get_by_role("button", name="Siguiente »")
    codigos: set[str] = set()

    page.goto("/#/vinos")
    for pagina in range(1, ultima + 1):
        expect(page.get_by_text(f"Página {pagina} de {ultima} · {total} vinos")).to_be_visible()
        codigos.update(page.locator("tbody tr td:first-child").all_inner_texts())
        if pagina < ultima:
            siguiente.click()

    expect(siguiente).to_be_disabled()
    # Cada vino aparece una sola vez: la paginación recorre todo el listado.
    assert len(codigos) == total


def test_el_detalle_de_un_vino_de_corte_muestra_sus_cepas_y_porcentajes(page: Page, consultar) -> None:
    cod_vino = consultar(
        "SELECT cod_vino FROM composicion_vino GROUP BY 1 HAVING count(*) >= 2 ORDER BY 1 LIMIT 1")[0][0]
    composicion = consultar(
        "SELECT c.nombre, c.tipo, cv.porcentaje FROM composicion_vino AS cv "
        "JOIN cepa AS c USING (id_cepa) WHERE cv.cod_vino = %s", (cod_vino,))
    assert len(composicion) >= 2

    page.goto(f"/#/vinos?ver={cod_vino}")

    detalle = page.get_by_role("complementary")
    tabla = detalle.get_by_role("table").first
    expect(tabla.get_by_role("row")).to_have_count(len(composicion) + 1)  # + el encabezado
    for nombre, tipo, porcentaje in composicion:
        fila = tabla.get_by_role("row").filter(has_text=f"{nombre} ({tipo})").filter(has_text=str(porcentaje))
        expect(fila).to_have_count(1)


def test_un_vino_inexistente_muestra_el_404_y_deja_el_listado(page: Page) -> None:
    page.goto("/#/vinos?ver=999999")

    alerta = page.get_by_role("alert")
    expect(alerta).to_contain_text("404 · no_encontrado")
    expect(alerta).to_contain_text("El vino 999999 no existe.")
    expect(page.get_by_text(re.compile(r"Página 1 de \d+ · \d+ vinos"))).to_be_visible()
