"""Ingresos: alta, renglones, terminar y procesar (issue #30).

Corren con api/tests/ejecutar.sh, contra un proyecto aislado y cargado, como
bodegas_api. Transportista, bodega y vinos se buscan en el dataset; cada
prueba crea sus propios ingresos por la API.
"""

from datetime import datetime, timedelta
from typing import Any, Callable

import pytest
from fastapi.testclient import TestClient


# Un código válido para BIGINT que ningún ingreso de la carga alcanza.
INEXISTENTE = 9_000_000_000_000


def _transportista(consultar: Callable[..., Any]) -> int:
    return consultar("SELECT min(cod_transportista) FROM transportista")


def _bodega_con_vinos(consultar_filas: Callable[..., list[tuple]]) -> tuple[str, list[int]]:
    """Una bodega con al menos dos vinos: (cuit, [cod_vino, ...])."""

    filas = consultar_filas(
        "SELECT cuit_bodega, array_agg(cod_vino ORDER BY cod_vino) FROM vino "
        "GROUP BY cuit_bodega HAVING count(*) >= 2 ORDER BY cuit_bodega LIMIT 1")
    assert filas, "la carga no tiene una bodega con dos vinos"
    return filas[0]


def _deposito(consultar: Callable[..., Any], cod_vino: int) -> int:
    return consultar("SELECT COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = %s), 0)",
                     (cod_vino,))


def _nuevo(cliente: TestClient, consultar, cuit_bodega: str) -> int:
    respuesta = cliente.post("/ingresos", json={
        "cod_transportista": _transportista(consultar), "cuit_bodega": cuit_bodega})
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()["cod_ingreso"]


def _renglon(cliente: TestClient, cod: int, cod_vino: int, cantidad: int):
    return cliente.post(f"/ingresos/{cod}/renglones", json={"cod_vino": cod_vino, "cantidad": cantidad})


def _terminado(cliente: TestClient, consultar, cuit_bodega: str, cod_vino: int, cantidad: int) -> int:
    cod = _nuevo(cliente, consultar, cuit_bodega)
    assert _renglon(cliente, cod, cod_vino, cantidad).status_code == 201
    assert cliente.post(f"/ingresos/{cod}/terminar").status_code == 200
    return cod


def _estado(consultar: Callable[..., Any], cod: int) -> str:
    return consultar("SELECT estado::text FROM ingreso WHERE cod_ingreso = %s", (cod,))


def _renglones(consultar: Callable[..., Any], cod: int) -> int:
    return consultar("SELECT count(*) FROM renglon_ingreso WHERE cod_ingreso = %s", (cod,))


# --- Alta y consulta --------------------------------------------------------

def test_alta_en_confeccion_con_la_fecha_de_la_base(cliente, consultar, consultar_filas) -> None:
    cuit, _ = _bodega_con_vinos(consultar_filas)
    transportista = _transportista(consultar)

    # Estado y fecha enviados se ignoran: los fija la base.
    respuesta = cliente.post("/ingresos", json={
        "cod_transportista": transportista, "cuit_bodega": cuit,
        "estado": "procesado", "fecha": "2000-01-01T00:00:00Z"})

    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    assert datos["estado"] == "en_confeccion"
    assert (datos["cod_transportista"], datos["cuit_bodega"]) == (transportista, cuit)
    assert datos["renglones"] == []
    assert abs(datetime.fromisoformat(datos["fecha"]) - consultar("SELECT now()")) < timedelta(minutes=1)
    assert respuesta.headers["Location"] == f"/ingresos/{datos['cod_ingreso']}"

    consulta = cliente.get(respuesta.headers["Location"])
    assert consulta.status_code == 200
    assert consulta.json() == datos


@pytest.mark.parametrize(("campo", "valor", "restriccion"), [
    ("cod_transportista", 2_147_483_647, "fk_ingreso_transportista"),
    ("cuit_bodega", "99999999999", "fk_ingreso_bodega"),
])
def test_alta_con_dato_relacionado_inexistente_422(
    cliente, consultar, consultar_filas, campo, valor, restriccion
) -> None:
    cuit, _ = _bodega_con_vinos(consultar_filas)
    cuerpo = {"cod_transportista": _transportista(consultar), "cuit_bodega": cuit, campo: valor}
    antes = consultar("SELECT count(*) FROM ingreso")

    respuesta = cliente.post("/ingresos", json=cuerpo)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "El dato relacionado no existe.", "codigo": "23503",
                                "restriccion": restriccion}
    assert consultar("SELECT count(*) FROM ingreso") == antes


def test_alta_con_cuit_mal_formado_422(cliente, consultar) -> None:
    respuesta = cliente.post("/ingresos", json={
        "cod_transportista": _transportista(consultar), "cuit_bodega": "30-1234567-8"})

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"


# --- Circuito completo -------------------------------------------------------

def test_circuito_completo_suma_al_deposito(cliente, consultar, consultar_filas) -> None:
    cuit, (vino_a, vino_b, *_) = _bodega_con_vinos(consultar_filas)
    antes = (_deposito(consultar, vino_a), _deposito(consultar, vino_b))
    cod = _nuevo(cliente, consultar, cuit)

    assert _renglon(cliente, cod, vino_a, 120).status_code == 201
    renglon = _renglon(cliente, cod, vino_b, 30)
    assert renglon.status_code == 201, renglon.text
    assert renglon.headers["Location"] == f"/ingresos/{cod}"
    assert [(r["cod_vino"], r["cantidad"]) for r in renglon.json()["renglones"]] == [(vino_a, 120), (vino_b, 30)]
    # Agregar renglones no mueve stock: eso pasa recién al procesar.
    assert (_deposito(consultar, vino_a), _deposito(consultar, vino_b)) == antes

    terminar = cliente.post(f"/ingresos/{cod}/terminar")
    assert terminar.status_code == 200, terminar.text
    assert terminar.json()["estado"] == "terminado"

    procesar = cliente.post(f"/ingresos/{cod}/procesar")
    assert procesar.status_code == 200, procesar.text
    assert procesar.json()["estado"] == "procesado"
    assert (_deposito(consultar, vino_a), _deposito(consultar, vino_b)) == (antes[0] + 120, antes[1] + 30)

    assert cliente.get(f"/ingresos/{cod}").json() == procesar.json()


def test_procesar_dos_veces_409_sin_sumar_de_nuevo(cliente, consultar, consultar_filas) -> None:
    cuit, (vino, *_) = _bodega_con_vinos(consultar_filas)
    cod = _terminado(cliente, consultar, cuit, vino, 10)
    assert cliente.post(f"/ingresos/{cod}/procesar").status_code == 200
    despues = _deposito(consultar, vino)

    respuesta = cliente.post(f"/ingresos/{cod}/procesar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-10: el ingreso {cod} está procesado; sólo un ingreso terminado impacta en el depósito.",
        "codigo": "P0001"}
    # Impacto único: el depósito no volvió a sumar.
    assert _deposito(consultar, vino) == despues


# --- RN-16: vinos de la bodega de origen ---------------------------------------

def test_renglon_con_vino_de_otra_bodega_409(cliente, consultar, consultar_filas) -> None:
    cuit, _ = _bodega_con_vinos(consultar_filas)
    ajeno, bodega_ajena = consultar_filas(
        "SELECT cod_vino, cuit_bodega FROM vino WHERE cuit_bodega <> %s ORDER BY cod_vino LIMIT 1", (cuit,))[0]
    cod = _nuevo(cliente, consultar, cuit)

    respuesta = _renglon(cliente, cod, ajeno, 12)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-16: el vino {ajeno} es de la bodega {bodega_ajena}; el ingreso {cod} es de la bodega {cuit}.",
        "codigo": "P0001"}
    assert _renglones(consultar, cod) == 0


# --- Transiciones inválidas (RN-10) y bloqueo de renglones (RN-12) ------------

def test_renglon_en_ingreso_terminado_409(cliente, consultar, consultar_filas) -> None:
    cuit, (vino_a, vino_b, *_) = _bodega_con_vinos(consultar_filas)
    cod = _terminado(cliente, consultar, cuit, vino_a, 1)

    respuesta = _renglon(cliente, cod, vino_b, 1)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-12: el ingreso {cod} está terminado; no admite cambios en sus renglones.",
        "codigo": "P0001"}
    assert _renglones(consultar, cod) == 1


def test_procesar_sin_terminar_409(cliente, consultar, consultar_filas) -> None:
    cuit, (vino, *_) = _bodega_con_vinos(consultar_filas)
    cod = _nuevo(cliente, consultar, cuit)
    assert _renglon(cliente, cod, vino, 5).status_code == 201
    antes = _deposito(consultar, vino)

    respuesta = cliente.post(f"/ingresos/{cod}/procesar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["detail"].startswith(f"RN-10: el ingreso {cod} está en_confeccion;")
    assert _estado(consultar, cod) == "en_confeccion"
    assert _deposito(consultar, vino) == antes


def test_terminar_sin_renglones_409(cliente, consultar, consultar_filas) -> None:
    cuit, _ = _bodega_con_vinos(consultar_filas)
    cod = _nuevo(cliente, consultar, cuit)

    respuesta = cliente.post(f"/ingresos/{cod}/terminar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["detail"] == f"RN-10: no se puede terminar el ingreso {cod} sin renglones."
    assert _estado(consultar, cod) == "en_confeccion"


def test_terminar_un_ingreso_procesado_409(cliente, consultar, consultar_filas) -> None:
    cuit, (vino, *_) = _bodega_con_vinos(consultar_filas)
    cod = _terminado(cliente, consultar, cuit, vino, 1)
    assert cliente.post(f"/ingresos/{cod}/procesar").status_code == 200

    respuesta = cliente.post(f"/ingresos/{cod}/terminar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["detail"] == (
        f"RN-10: transición de estado inválida para el ingreso {cod}: procesado -> terminado.")
    assert _estado(consultar, cod) == "procesado"


# --- Renglones: reglas de fila -------------------------------------------------

def test_renglon_repetido_409(cliente, consultar, consultar_filas) -> None:
    cuit, (vino, *_) = _bodega_con_vinos(consultar_filas)
    cod = _nuevo(cliente, consultar, cuit)
    assert _renglon(cliente, cod, vino, 1).status_code == 201

    respuesta = _renglon(cliente, cod, vino, 3)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["restriccion"] == "pk_renglon_ingreso"
    assert consultar("SELECT cantidad FROM renglon_ingreso WHERE cod_ingreso = %s", (cod,)) == 1


@pytest.mark.parametrize("cantidad", [0, -5])
def test_renglon_cantidad_no_positiva_422(cliente, consultar, consultar_filas, cantidad) -> None:
    cuit, (vino, *_) = _bodega_con_vinos(consultar_filas)
    cod = _nuevo(cliente, consultar, cuit)

    respuesta = _renglon(cliente, cod, vino, cantidad)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514",
                                "restriccion": "ck_renglon_ingreso_cantidad_positiva"}
    assert _renglones(consultar, cod) == 0


def test_renglon_con_vino_inexistente_422(cliente, consultar, consultar_filas) -> None:
    cuit, _ = _bodega_con_vinos(consultar_filas)
    cod = _nuevo(cliente, consultar, cuit)

    respuesta = _renglon(cliente, cod, INEXISTENTE, 1)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["restriccion"] == "fk_renglon_ingreso_vino"


# --- Inexistente ---------------------------------------------------------------

@pytest.mark.parametrize(("metodo", "ruta", "cuerpo"), [
    ("GET", "", None),
    ("POST", "/renglones", {"cod_vino": 1, "cantidad": 1}),
    ("POST", "/terminar", None),
    ("POST", "/procesar", None),
])
def test_ingreso_inexistente_404(cliente, metodo, ruta, cuerpo) -> None:
    respuesta = cliente.request(metodo, f"/ingresos/{INEXISTENTE}{ruta}", json=cuerpo)

    assert respuesta.status_code == 404, respuesta.text
    assert respuesta.json()["detail"] == f"El ingreso {INEXISTENTE} no existe."
