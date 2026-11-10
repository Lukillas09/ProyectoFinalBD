"""Pantalla 3: nueva venta. Es el criterio central de la etapa: una venta sin stock
muestra el mensaje de la regla (RN-09) y no deja datos a medias.

Los importes los calcula fn_registrar_venta en PostgreSQL; la pantalla muestra los
de la respuesta, y estas pruebas los comparan con la API y con la base.
"""

import re

from playwright.sync_api import Page, expect

from ayudas import moneda, normalizar, stock_sala, vino_con_stock_en_sala, vino_sin_stock_en_sala


def preparar_venta(page: Page, id_cliente: int, id_sala: int, renglones: list[tuple[int, int]]) -> None:
    """Confirma el cliente, elige la sala y agrega los renglones (cod_vino, cantidad)."""

    page.goto("/#/venta")
    sala = page.get_by_label("Sala")
    expect(sala).to_be_enabled()  # las salas ya llegaron del catálogo

    page.get_by_label("Cliente (cód.)").fill(str(id_cliente))
    page.get_by_role("button", name="Buscar").click()
    expect(page.locator(".venta__cliente-confirmado")).to_contain_text("descuento")
    sala.select_option(str(id_sala))

    for agregados, (cod_vino, cantidad) in enumerate(renglones, start=1):
        page.get_by_label("Cód. vino").fill(str(cod_vino))
        page.get_by_label("Cantidad").fill(str(cantidad))
        page.get_by_role("button", name="Agregar").click()
        expect(page.get_by_role("button", name=re.compile(r"^Quitar"))).to_have_count(agregados)


def test_una_venta_valida_muestra_los_importes_de_la_base(page: Page, api, consultar, id_cliente, id_sala) -> None:
    cod_vino = vino_con_stock_en_sala(consultar, id_sala, minimo=5)

    preparar_venta(page, id_cliente, id_sala, [(cod_vino, 2)])
    page.get_by_role("button", name="Registrar venta").click()

    aviso = page.get_by_text(re.compile(r"Comprobante Nº \d+ registrado\."))
    expect(aviso).to_be_visible()
    nro = re.search(r"Nº (\d+)", aviso.inner_text()).group(1)

    comprobante = api.get(f"comprobantes/{nro}").json()
    # Renglones: nombre, cantidad, precio, descuento y parcial, como los guardó la base.
    esperados = [
        [r["nombre_vino"], str(r["cantidad"]), moneda(r["precio_unitario"]),
         f"{r['descuento_porcentaje']} %", moneda(r["total_parcial"])]
        for r in comprobante["renglones"]
    ]
    filas = page.locator(".venta--comprobante tbody tr")
    expect(filas).to_have_count(len(esperados))
    vistos = [[normalizar(celda) for celda in fila.locator("td").all_inner_texts()] for fila in filas.all()]
    assert vistos == esperados

    totales = [normalizar(t) for t in page.locator(".venta__totales dd").all_inner_texts()]
    assert totales == [moneda(comprobante["subtotal"]), moneda(comprobante["descuento"]), moneda(comprobante["total"])]

    # Y lo que muestra la pantalla es lo que quedó guardado en la base.
    guardado = consultar(
        "SELECT subtotal, descuento, total FROM comprobante WHERE nro_comprobante = %s", (int(nro),))[0]
    assert totales == [moneda(str(valor)) for valor in guardado]


def test_una_venta_sin_stock_muestra_rn09_y_no_deja_datos_a_medias(page: Page, consultar, consultar_valor, id_cliente, id_sala) -> None:
    con_stock = vino_con_stock_en_sala(consultar, id_sala, minimo=2)
    sin_stock = vino_sin_stock_en_sala(consultar, id_sala)

    def estado_de_la_base() -> tuple[int, int, int]:
        return (
            consultar_valor("SELECT count(*) FROM comprobante"),
            consultar_valor("SELECT count(*) FROM renglon_comprobante"),
            stock_sala(consultar_valor, id_sala, con_stock),
        )

    antes = estado_de_la_base()
    # El renglón con stock va primero: se procesaría antes del que falla, y su
    # descuento de stock también tiene que revertirse.
    preparar_venta(page, id_cliente, id_sala, [(con_stock, 2), (sin_stock, 1)])
    page.get_by_role("button", name="Registrar venta").click()

    alerta = page.get_by_role("alert")
    expect(alerta).to_contain_text("409 · P0001")
    expect(alerta).to_contain_text(f"RN-09: stock insuficiente del vino {sin_stock} en la sala {id_sala}.")
    expect(alerta).to_contain_text("No se registró ningún comprobante.")
    # La lista queda cargada para corregirla.
    expect(page.get_by_role("button", name=re.compile(r"^Quitar"))).to_have_count(2)

    despues = estado_de_la_base()
    print(f"\ncomprobantes:                {antes[0]} -> {despues[0]}")
    print(f"renglones de comprobante:    {antes[1]} -> {despues[1]}")
    print(f"stock del vino {con_stock} en la sala {id_sala}: {antes[2]} -> {despues[2]}")
    assert despues == antes
