"""Pantalla 4: transferencias con renglones y botones según el estado.

Los botones se habilitan según el estado que devuelve la API: es una ayuda
visual. La transición y el movimiento de stock los decide PostgreSQL (RN-11,
RN-12), y las pruebas lo verifican en la base.
"""

import re

from playwright.sync_api import Page, expect

from ayudas import stock_deposito, stock_sala, vino_con_deposito_chico, vino_sin_stock_en_sala

CANTIDAD = 5


def crear_transferencia(page: Page, id_sala: int) -> int:
    page.goto("/#/transferencias")
    sala = page.get_by_label("Sala")
    expect(sala).to_be_enabled()
    sala.select_option(str(id_sala))
    page.get_by_role("button", name="Crear transferencia").click()

    expect(page).to_have_url(re.compile(r"#/transferencias/\d+$"))
    nro = int(page.url.rsplit("/", 1)[1])
    expect(page.get_by_role("heading", name=re.compile(rf"^Transferencia Nº {nro} "))).to_be_visible()
    return nro


def agregar_renglon(page: Page, cod_vino: int, cantidad: int) -> None:
    page.get_by_label("Cód. vino").fill(str(cod_vino))
    page.get_by_label("Cantidad").fill(str(cantidad))
    page.get_by_role("button", name="Agregar renglón").click()
    # La primera celda de la fila es el código del vino (la cantidad podría coincidir con él).
    expect(page.locator("tbody tr td:first-child").filter(has_text=re.compile(rf"^{cod_vino}$"))).to_have_count(1)


def verificar_botones(page: Page, estado: str, agregar: bool, terminar: bool, procesar: bool) -> None:
    """El estado que se ve y qué botones están habilitados."""

    expect(page.locator(".insignia")).to_have_text(estado)
    for nombre, habilitado in [("Agregar renglón", agregar), ("Terminar", terminar), ("Procesar", procesar)]:
        boton = page.get_by_role("button", name=nombre, exact=True)
        if habilitado:
            expect(boton).to_be_enabled()
        else:
            expect(boton).to_be_disabled()


def test_recorrido_de_los_tres_estados_y_movimiento_de_stock(page: Page, consultar, consultar_valor, id_sala) -> None:
    cod_vino = vino_sin_stock_en_sala(consultar, id_sala, deposito_minimo=CANTIDAD)
    deposito_antes = stock_deposito(consultar_valor, cod_vino)
    sala_antes = stock_sala(consultar_valor, id_sala, cod_vino)

    nro = crear_transferencia(page, id_sala)
    verificar_botones(page, "en confección", agregar=True, terminar=True, procesar=False)
    expect(page.get_by_text("Todavía no tiene renglones.")).to_be_visible()

    agregar_renglon(page, cod_vino, CANTIDAD)
    # Agregar un renglón no mueve stock: sólo procesar lo hace.
    assert stock_deposito(consultar_valor, cod_vino) == deposito_antes
    assert stock_sala(consultar_valor, id_sala, cod_vino) == sala_antes

    page.get_by_role("button", name="Terminar", exact=True).click()
    verificar_botones(page, "terminado", agregar=False, terminar=False, procesar=True)
    assert consultar_valor("SELECT estado FROM transferencia WHERE nro_transferencia = %s", (nro,)) == "terminado"

    page.get_by_role("button", name="Procesar", exact=True).click()
    verificar_botones(page, "procesado", agregar=False, terminar=False, procesar=False)
    assert consultar_valor("SELECT estado FROM transferencia WHERE nro_transferencia = %s", (nro,)) == "procesado"

    # La sala recibe lo que sale del depósito: la base movió el stock.
    assert stock_sala(consultar_valor, id_sala, cod_vino) == sala_antes + CANTIDAD
    assert stock_deposito(consultar_valor, cod_vino) == deposito_antes - CANTIDAD


def test_procesar_sin_stock_en_el_deposito_muestra_rn11_y_no_mueve_nada(page: Page, consultar, consultar_valor, id_sala) -> None:
    cod_vino, en_deposito = vino_con_deposito_chico(consultar)
    sala_antes = stock_sala(consultar_valor, id_sala, cod_vino)

    nro = crear_transferencia(page, id_sala)
    agregar_renglon(page, cod_vino, en_deposito + 1)  # una botella más de las que hay
    page.get_by_role("button", name="Terminar", exact=True).click()
    verificar_botones(page, "terminado", agregar=False, terminar=False, procesar=True)

    page.get_by_role("button", name="Procesar", exact=True).click()

    alerta = page.get_by_role("alert")
    expect(alerta).to_contain_text("409 · P0001")
    expect(alerta).to_contain_text(f"RN-11: el depósito no tiene stock suficiente para la transferencia {nro}.")
    expect(alerta).to_contain_text("La transferencia sigue terminada; no se movió stock.")
    # Sigue terminada: se puede volver a intentar cuando haya stock.
    verificar_botones(page, "terminado", agregar=False, terminar=False, procesar=True)
    assert consultar_valor("SELECT estado FROM transferencia WHERE nro_transferencia = %s", (nro,)) == "terminado"
    assert stock_deposito(consultar_valor, cod_vino) == en_deposito
    assert stock_sala(consultar_valor, id_sala, cod_vino) == sala_antes


def test_terminar_sin_renglones_muestra_rn11_y_sigue_en_confeccion(page: Page, id_sala) -> None:
    nro = crear_transferencia(page, id_sala)

    page.get_by_role("button", name="Terminar", exact=True).click()

    alerta = page.get_by_role("alert")
    expect(alerta).to_contain_text(f"RN-11: no se puede terminar la transferencia {nro} sin renglones.")
    verificar_botones(page, "en confección", agregar=True, terminar=True, procesar=False)
