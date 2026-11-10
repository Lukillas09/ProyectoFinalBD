"""Pantalla 2: alta y edición de vino con composición de cepas.

RN-05 (la composición suma 100 %) y RN-13 (auditoría del precio) las aplica
PostgreSQL; la pantalla sólo muestra lo que responde la API. Cada prueba crea su
propio vino, con un nombre único.
"""

import re
import uuid
from decimal import Decimal

from playwright.sync_api import Page, expect


def nombre_unico(prefijo: str) -> str:
    return f"Prueba E2E {prefijo} {uuid.uuid4().hex[:8]}"


def llenar_vino(page: Page, nombre: str, cuit: str, cepas: list[tuple[int, str]]) -> None:
    """Completa el formulario de alta. `cepas` son (id_cepa, porcentaje como se escribe)."""

    # Los campos se buscan dentro de <main>: el logo del encabezado también tiene
    # un aria-label con la palabra "Bodega".
    formulario = page.get_by_role("main")
    formulario.get_by_label("Nombre").fill(nombre)
    formulario.get_by_label("Tipo").select_option("tinto")
    formulario.get_by_label("Añada").fill("2024")
    formulario.get_by_label("Volumen (ml)").fill("750")
    formulario.get_by_label("Graduación (%)").fill("13.50")
    formulario.get_by_label("Precio").fill("4500.00")
    formulario.get_by_label("Bodega").select_option(cuit)
    for numero, (id_cepa, porcentaje) in enumerate(cepas, start=1):
        if numero > 1:
            formulario.get_by_role("button", name="+ Agregar cepa").click()
        formulario.get_by_label(f"Cepa {numero}", exact=True).select_option(str(id_cepa))
        formulario.get_by_label(f"Porcentaje de la cepa {numero}", exact=True).fill(porcentaje)


def datos_de_la_carga(consultar) -> tuple[str, list[int]]:
    """Una bodega y dos cepas de la carga."""

    cuit = consultar("SELECT min(cuit) FROM bodega")[0][0]
    cepas = [fila[0] for fila in consultar("SELECT id_cepa FROM cepa ORDER BY id_cepa LIMIT 2")]
    assert len(cepas) == 2
    return cuit, cepas


def test_alta_con_composicion_al_90_muestra_rn05_y_el_vino_no_existe(page: Page, consultar, consultar_valor) -> None:
    cuit, (cepa_a, cepa_b) = datos_de_la_carga(consultar)
    nombre = nombre_unico("RN-05")

    page.goto("/#/vinos/nuevo")
    llenar_vino(page, nombre, cuit, [(cepa_a, "85"), (cepa_b, "5")])
    page.get_by_role("button", name="Guardar").click()

    alerta = page.get_by_role("alert")
    expect(alerta).to_contain_text("409 · P0001")
    expect(alerta).to_contain_text(re.compile(
        r"RN-05: la composición del vino \d+ suma 90\.00 %; debe sumar exactamente 100 %\."))
    # El formulario conserva lo escrito y no se fue a ninguna ficha.
    expect(page.get_by_label("Nombre")).to_have_value(nombre)
    expect(page).to_have_url(re.compile(r"#/vinos/nuevo$"))
    # La transacción se revirtió: el vino no existe.
    assert consultar_valor("SELECT count(*) FROM vino WHERE nombre = %s", (nombre,)) == 0


def test_alta_correcta_60_y_40_lleva_a_la_ficha_con_su_composicion(page: Page, consultar, consultar_valor) -> None:
    cuit, (cepa_a, cepa_b) = datos_de_la_carga(consultar)
    maridajes = consultar("SELECT nombre, temperatura_servicio_c FROM maridaje ORDER BY id_maridaje LIMIT 2")
    nombre = nombre_unico("Corte")

    page.goto("/#/vinos/nuevo")
    llenar_vino(page, nombre, cuit, [(cepa_a, "60"), (cepa_b, "40")])
    for marcado, temperatura in maridajes:
        page.get_by_label(f"{marcado} ({temperatura} °C)").check()
    page.get_by_role("button", name="Guardar").click()

    # Lleva a la ficha del catálogo, con lo que guardó la base.
    expect(page).to_have_url(re.compile(r"#/vinos\?ver=\d+$"))
    detalle = page.get_by_role("complementary")
    expect(detalle.get_by_role("heading", level=2)).to_have_text(f"{nombre} · 2024")
    filas = detalle.get_by_role("table").first.get_by_role("row")
    expect(filas).to_have_count(3)  # encabezado + 2 cepas
    expect(filas.filter(has_text="60.00")).to_have_count(1)
    expect(filas.filter(has_text="40.00")).to_have_count(1)
    for marcado, temperatura in maridajes:
        expect(detalle.get_by_role("listitem").filter(has_text=f"{marcado} · {temperatura} °C")).to_have_count(1)

    cod_vino = int(page.url.rsplit("=", 1)[1])
    assert consultar_valor("SELECT count(*) FROM composicion_vino WHERE cod_vino = %s", (cod_vino,)) == 2
    assert consultar_valor("SELECT count(*) FROM vino_maridaje WHERE cod_vino = %s", (cod_vino,)) == 2


def test_editar_solo_el_precio_actualiza_la_ficha_y_registra_la_auditoria(page: Page, api, consultar, consultar_valor) -> None:
    cuit, (cepa_a, _) = datos_de_la_carga(consultar)
    nombre = nombre_unico("Edición")
    # El vino de partida se crea por la propia API (no por SQL).
    creado = api.post("vinos", data={
        "nombre": nombre, "tipo": "tinto", "anada": 2024, "volumen_ml": 750, "graduacion": "13.50",
        "precio": "4500.00", "cuit_bodega": cuit,
        "composicion": [{"id_cepa": cepa_a, "porcentaje": "100.00"}], "maridajes": [],
    })
    assert creado.status == 201, creado.text()
    cod_vino = creado.json()["cod_vino"]
    assert consultar_valor("SELECT count(*) FROM auditoria_precio WHERE cod_vino = %s", (cod_vino,)) == 0

    page.goto(f"/#/vinos/{cod_vino}/editar")
    # La edición precarga los valores tal como los devuelve la API.
    expect(page.get_by_label("Precio")).to_have_value("4500.00")
    expect(page.get_by_label("Graduación (%)")).to_have_value("13.50")
    expect(page.get_by_role("heading", level=1)).to_have_text(f"Editar vino Nº {cod_vino} · {nombre}")
    page.get_by_label("Precio").fill("5100.00")
    page.get_by_role("button", name="Guardar").click()

    expect(page).to_have_url(re.compile(rf"#/vinos\?ver={cod_vino}$"))
    expect(page.get_by_role("complementary")).to_contain_text(re.compile(r"\$\s*5\.100,00"))
    # RN-13: el trigger de la base registró el cambio, una sola vez.
    auditoria = consultar(
        "SELECT precio_anterior, precio_nuevo FROM auditoria_precio WHERE cod_vino = %s", (cod_vino,))
    assert auditoria == [(Decimal("4500.00"), Decimal("5100.00"))]
