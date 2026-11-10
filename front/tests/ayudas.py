"""Ayudas de las pruebas: formato como el del front y búsqueda de datos de prueba.

Los datos se buscan con SELECT en la carga (ids y stocks cambian con
FECHA_REFERENCIA). Las pruebas que modifican stock los buscan dentro de la
propia prueba y no en fixtures de sesión: así no dependen del orden de ejecución
(una venta le resta stock a un vino que otra prueba podría elegir).
"""

import re
from collections.abc import Callable
from decimal import Decimal


def normalizar(texto: str) -> str:
    """Colapsa espacios (incluido el no separable que usa Intl) como hace Playwright."""

    return re.sub(r"\s+", " ", texto).strip()


def moneda(valor: str) -> str:
    """El string de la API ("48220.00") como lo muestra el front con es-AR ("$ 48.220,00").

    Es el formato que las pruebas esperan ver; el cálculo de importes no sale de
    acá: los valores que se comparan los trae siempre la API o la base.
    """

    es_ar = f"{Decimal(valor):,.2f}".replace(",", "#").replace(".", ",").replace("#", ".")
    return f"$ {es_ar}"


# --- Stock --------------------------------------------------------------------

def stock_sala(consultar_valor: Callable, id_sala: int, cod_vino: int) -> int:
    """Un vino sin fila en stock_sala cuenta como 0, no como NULL."""

    return consultar_valor(
        "SELECT COALESCE((SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s), 0)",
        (id_sala, cod_vino),
    )


def stock_deposito(consultar_valor: Callable, cod_vino: int) -> int:
    return consultar_valor(
        "SELECT COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = %s), 0)",
        (cod_vino,),
    )


# --- Búsqueda de datos --------------------------------------------------------

def vino_con_stock_en_sala(consultar: Callable, id_sala: int, minimo: int) -> int:
    filas = consultar(
        "SELECT cod_vino FROM stock_sala WHERE id_sala = %s AND cantidad >= %s ORDER BY cod_vino LIMIT 1",
        (id_sala, minimo),
    )
    assert filas, f"la carga no tiene un vino con al menos {minimo} botellas en la sala {id_sala}"
    return filas[0][0]


def vino_sin_stock_en_sala(consultar: Callable, id_sala: int, deposito_minimo: int = 0) -> int:
    """Un vino que la sala no tiene (sin fila o en 0) y con stock en el depósito
    de al menos `deposito_minimo`: candidato a una transferencia."""

    filas = consultar(
        "SELECT v.cod_vino FROM vino AS v "
        "WHERE COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = v.cod_vino), 0) >= %s "
        "AND NOT EXISTS (SELECT 1 FROM stock_sala AS s "
        "                WHERE s.id_sala = %s AND s.cod_vino = v.cod_vino AND s.cantidad > 0) "
        "ORDER BY v.cod_vino LIMIT 1",
        (deposito_minimo, id_sala),
    )
    assert filas, f"la carga no tiene un vino sin stock en la sala {id_sala}"
    return filas[0][0]


def vino_con_deposito_chico(consultar: Callable) -> tuple[int, int]:
    """El vino con menos botellas (pero más de cero) en el depósito: (cod_vino, cantidad)."""

    filas = consultar(
        "SELECT cod_vino, cantidad FROM stock_deposito WHERE cantidad > 0 ORDER BY cantidad, cod_vino LIMIT 1"
    )
    assert filas, "la carga no tiene stock en el depósito"
    return filas[0]
