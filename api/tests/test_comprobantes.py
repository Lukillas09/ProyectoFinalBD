"""Ventas: POST /comprobantes y GET /comprobantes/{nro} (issue #28; revisadas en #33).

Corren con api/tests/ejecutar.sh, contra un proyecto aislado y cargado, como
bodegas_api. Sala, vinos con stock y cliente se buscan en el dataset.

Toda venta pasa por fn_registrar_venta, que es todo o nada. Por eso cada
prueba de error verifica que no quedó ningún comprobante nuevo y que el
stock de la sala no cambió, ni siquiera el de los renglones que se
procesaron antes del que falló.
"""

from typing import Any, Callable

import pytest


def _datos_de_venta(consultar: Callable[..., Any], consultar_filas: Callable[..., list[tuple]]):
    """(id_cliente, id_sala, [vino_a, vino_b]): dos vinos con al menos 3 botellas en la sala."""

    filas = consultar_filas(
        "SELECT id_sala, array_agg(cod_vino ORDER BY cod_vino) FROM stock_sala "
        "WHERE cantidad >= 3 GROUP BY id_sala HAVING count(*) >= 2 ORDER BY id_sala LIMIT 1")
    assert filas, "la carga no dejó una sala con dos vinos en stock"
    id_sala, vinos = filas[0]
    return consultar("SELECT min(id_cliente) FROM cliente"), id_sala, vinos[:2]


def _stock(consultar: Callable[..., Any], id_sala: int, cod_vino: int) -> int:
    return consultar("SELECT COALESCE((SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s), 0)",
                     (id_sala, cod_vino))


def _estado(consultar: Callable[..., Any], id_sala: int, vinos: list[int]) -> tuple:
    """Lo que una venta rechazada no puede cambiar: cuántos comprobantes hay y el stock de la sala."""

    return (consultar("SELECT count(*) FROM comprobante"),
            tuple(_stock(consultar, id_sala, v) for v in vinos))


def _vender(cliente, id_cliente: int, id_sala: int, renglones: list[tuple[int, int]]):
    return cliente.post("/comprobantes", json={
        "id_cliente": id_cliente, "id_sala": id_sala,
        "renglones": [{"cod_vino": v, "cantidad": c} for v, c in renglones]})


# --- Venta correcta ---------------------------------------------------------------

def test_venta_correcta_con_los_importes_de_la_base(cliente, consultar, consultar_filas) -> None:
    id_cliente, id_sala, (vino_a, vino_b) = _datos_de_venta(consultar, consultar_filas)
    stock_antes = (_stock(consultar, id_sala, vino_a), _stock(consultar, id_sala, vino_b))

    respuesta = _vender(cliente, id_cliente, id_sala, [(vino_b, 1), (vino_a, 2)])

    assert respuesta.status_code == 201, respuesta.text
    venta = respuesta.json()
    nro = venta["nro_comprobante"]
    assert respuesta.headers["Location"] == f"/comprobantes/{nro}"
    assert (venta["id_cliente"], venta["id_sala"]) == (id_cliente, id_sala)
    # Precio y descuento los congela la base (RN-06, RN-08); la API no calcula.
    descuento = str(consultar("SELECT fn_descuento_cliente(%s)", (id_cliente,)))
    assert [(r["cod_vino"], r["cantidad"]) for r in venta["renglones"]] == [(vino_a, 2), (vino_b, 1)]
    for renglon in venta["renglones"]:
        assert renglon["precio_unitario"] == str(consultar("SELECT precio FROM vino WHERE cod_vino = %s",
                                                           (renglon["cod_vino"],)))
        assert renglon["descuento_porcentaje"] == descuento
    guardado = consultar_filas("SELECT subtotal, descuento, total FROM comprobante WHERE nro_comprobante = %s",
                               (nro,))[0]
    assert (venta["subtotal"], venta["descuento"], venta["total"]) == tuple(str(x) for x in guardado)
    # El stock lo descuenta la base (RN-09).
    assert (_stock(consultar, id_sala, vino_a), _stock(consultar, id_sala, vino_b)) == (
        stock_antes[0] - 2, stock_antes[1] - 1)

    consulta = cliente.get(f"/comprobantes/{nro}")
    assert consulta.status_code == 200
    assert consulta.json() == venta


# --- Rechazos: ninguno deja datos a medias ------------------------------------------

@pytest.mark.consigna
def test_venta_sin_stock_409_sin_cambios(cliente, consultar, consultar_filas) -> None:
    """Prueba de la consigna: stock insuficiente -> 409, sin cambios parciales (RN-09)."""

    id_cliente, id_sala, (vino_a, vino_b) = _datos_de_venta(consultar, consultar_filas)
    antes = _estado(consultar, id_sala, [vino_a, vino_b])
    pedido_b = _stock(consultar, id_sala, vino_b) + 1

    # El renglón de vino_a (con stock) se procesa primero, porque la función
    # inserta por código de vino; el de vino_b falla después.
    respuesta = _vender(cliente, id_cliente, id_sala, [(vino_a, 1), (vino_b, pedido_b)])

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-09: stock insuficiente del vino {vino_b} en la sala {id_sala}.", "codigo": "P0001"}
    # Ni la cabecera, ni el renglón de vino_a, ni su descuento de stock.
    assert _estado(consultar, id_sala, [vino_a, vino_b]) == antes


@pytest.mark.parametrize(("renglones", "detalle"), [
    pytest.param("repetido", "RN-08: un vino no puede repetirse en la misma venta.", id="vino-repetido"),
    pytest.param("cero", "RN-15: las cantidades vendidas deben ser positivas.", id="cantidad-cero"),
    pytest.param("vacio", "RN-08: una venta debe tener al menos un renglón.", id="sin-renglones"),
])
def test_regla_de_la_venta_409_sin_cambios(cliente, consultar, consultar_filas, renglones, detalle) -> None:
    id_cliente, id_sala, (vino_a, vino_b) = _datos_de_venta(consultar, consultar_filas)
    pedido = {"repetido": [(vino_a, 1), (vino_a, 1)],
              "cero": [(vino_a, 1), (vino_b, 0)],
              "vacio": []}[renglones]
    antes = _estado(consultar, id_sala, [vino_a, vino_b])

    respuesta = _vender(cliente, id_cliente, id_sala, pedido)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {"detail": detalle, "codigo": "P0001"}
    assert _estado(consultar, id_sala, [vino_a, vino_b]) == antes


@pytest.mark.parametrize(("campo", "restriccion"), [
    ("id_cliente", "fk_comprobante_cliente"),
    ("id_sala", "fk_comprobante_sala_venta"),
])
def test_cliente_o_sala_inexistente_422_sin_cambios(cliente, consultar, consultar_filas, campo, restriccion) -> None:
    id_cliente, id_sala, (vino_a, vino_b) = _datos_de_venta(consultar, consultar_filas)
    antes = _estado(consultar, id_sala, [vino_a, vino_b])
    datos = {"id_cliente": id_cliente, "id_sala": id_sala, campo: 2_147_483_647}

    respuesta = _vender(cliente, datos["id_cliente"], datos["id_sala"], [(vino_a, 1)])

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "El dato relacionado no existe.", "codigo": "23503",
                                "restriccion": restriccion}
    assert _estado(consultar, id_sala, [vino_a, vino_b]) == antes


def test_vino_inexistente_422_con_su_codigo(cliente, consultar, consultar_filas) -> None:
    id_cliente, id_sala, (vino_a, vino_b) = _datos_de_venta(consultar, consultar_filas)
    antes = _estado(consultar, id_sala, [vino_a, vino_b])

    respuesta = _vender(cliente, id_cliente, id_sala, [(vino_a, 1), (999_999_999, 1)])

    assert respuesta.status_code == 422, respuesta.text
    # La API lo detecta antes de vender (la base respondería 23502 sobre precio_unitario).
    assert respuesta.json() == {"detail": "No existen los vinos: 999999999.", "codigo": "dato_invalido"}
    assert _estado(consultar, id_sala, [vino_a, vino_b]) == antes


@pytest.mark.parametrize("cuerpo", [
    {"id_cliente": 1, "id_sala": 1},
    {"id_cliente": "uno", "id_sala": 1, "renglones": []},
    {"id_cliente": 1, "id_sala": 1, "renglones": [{"cod_vino": 1}]},
])
def test_forma_invalida_422(cliente, consultar, cuerpo) -> None:
    antes = consultar("SELECT count(*) FROM comprobante")

    respuesta = cliente.post("/comprobantes", json=cuerpo)

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"
    assert consultar("SELECT count(*) FROM comprobante") == antes


# --- Consulta ------------------------------------------------------------------------

def test_comprobante_inexistente_404(cliente) -> None:
    respuesta = cliente.get("/comprobantes/999999999")

    assert respuesta.status_code == 404
    # El 404 del endpoint, no el de una ruta inexistente: trae el número.
    assert respuesta.json() == {"detail": "El comprobante 999999999 no existe.", "codigo": "no_encontrado"}
