"""Transferencias: alta, renglones, terminar y procesar (issue #29).

Corren con api/tests/ejecutar.sh, contra un proyecto aislado y cargado, como
bodegas_api. Sala y vinos se buscan en el dataset; cada prueba crea sus
propias transferencias por la API, así no depende del estado de otras.
"""

import threading
import time
from typing import Any, Callable

import pytest
from fastapi.testclient import TestClient


# Un número válido para BIGINT que ninguna transferencia de la carga alcanza.
INEXISTENTE = 9_000_000_000_000


def _sala(consultar: Callable[..., Any]) -> int:
    return consultar("SELECT min(id_sala) FROM sala_venta")


def _vino_con_stock(consultar_filas: Callable[..., list[tuple]], minimo: int = 2) -> tuple[int, int]:
    """Un vino con al menos ``minimo`` botellas en el depósito: (cod_vino, cantidad)."""

    filas = consultar_filas(
        "SELECT cod_vino, cantidad FROM stock_deposito WHERE cantidad >= %s ORDER BY cod_vino LIMIT 1",
        (minimo,))
    assert filas, "la carga no dejó stock en el depósito"
    return filas[0]


def _stock(consultar: Callable[..., Any], id_sala: int, cod_vino: int) -> tuple[int, int]:
    """(botellas en el depósito, botellas en la sala); 0 si no hay fila."""

    return (
        consultar("SELECT COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = %s), 0)",
                  (cod_vino,)),
        consultar("SELECT COALESCE((SELECT cantidad FROM stock_sala WHERE id_sala = %s AND cod_vino = %s), 0)",
                  (id_sala, cod_vino)),
    )


def _nueva(cliente: TestClient, id_sala: int) -> int:
    respuesta = cliente.post("/transferencias", json={"id_sala": id_sala})
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()["nro_transferencia"]


def _renglon(cliente: TestClient, nro: int, cod_vino: int, cantidad: int):
    return cliente.post(f"/transferencias/{nro}/renglones", json={"cod_vino": cod_vino, "cantidad": cantidad})


def _terminada(cliente: TestClient, id_sala: int, cod_vino: int, cantidad: int) -> int:
    nro = _nueva(cliente, id_sala)
    assert _renglon(cliente, nro, cod_vino, cantidad).status_code == 201
    assert cliente.post(f"/transferencias/{nro}/terminar").status_code == 200
    return nro


def _estado(consultar: Callable[..., Any], nro: int) -> str:
    return consultar("SELECT estado::text FROM transferencia WHERE nro_transferencia = %s", (nro,))


# --- Alta y consulta --------------------------------------------------------

def test_alta_en_confeccion_con_la_fecha_de_la_base(cliente, consultar) -> None:
    id_sala = _sala(consultar)

    # Estado y fecha enviados se ignoran: los fija la base (RN-11).
    respuesta = cliente.post("/transferencias", json={
        "id_sala": id_sala, "estado": "procesado", "fecha_confeccion": "2000-01-01"})

    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    assert datos["estado"] == "en_confeccion"
    assert datos["id_sala"] == id_sala
    assert datos["renglones"] == []
    assert datos["fecha_confeccion"] == consultar("SELECT CURRENT_DATE").isoformat()
    assert respuesta.headers["Location"] == f"/transferencias/{datos['nro_transferencia']}"

    consulta = cliente.get(respuesta.headers["Location"])
    assert consulta.status_code == 200
    assert consulta.json() == datos


def test_alta_con_sala_inexistente_422(cliente, consultar) -> None:
    antes = consultar("SELECT count(*) FROM transferencia")

    respuesta = cliente.post("/transferencias", json={"id_sala": 2_147_483_647})

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "El dato relacionado no existe.", "codigo": "23503",
                                "restriccion": "fk_transferencia_sala_venta"}
    assert consultar("SELECT count(*) FROM transferencia") == antes


def test_alta_sin_sala_422(cliente) -> None:
    respuesta = cliente.post("/transferencias", json={})

    assert respuesta.status_code == 422
    assert respuesta.json()["codigo"] == "validacion"


# --- Circuito completo -------------------------------------------------------

def test_circuito_completo_mueve_el_stock(cliente, consultar, consultar_filas) -> None:
    id_sala = _sala(consultar)
    cod_vino, _ = _vino_con_stock(consultar_filas)
    deposito, sala = _stock(consultar, id_sala, cod_vino)
    nro = _nueva(cliente, id_sala)

    renglon = _renglon(cliente, nro, cod_vino, 2)
    assert renglon.status_code == 201, renglon.text
    assert renglon.headers["Location"] == f"/transferencias/{nro}"
    assert renglon.json()["estado"] == "en_confeccion"
    assert [(r["cod_vino"], r["cantidad"]) for r in renglon.json()["renglones"]] == [(cod_vino, 2)]
    assert renglon.json()["renglones"][0]["nombre_vino"]
    # Agregar un renglón no mueve stock: eso pasa recién al procesar.
    assert _stock(consultar, id_sala, cod_vino) == (deposito, sala)

    terminar = cliente.post(f"/transferencias/{nro}/terminar")
    assert terminar.status_code == 200, terminar.text
    assert terminar.json()["estado"] == "terminado"
    assert _stock(consultar, id_sala, cod_vino) == (deposito, sala)

    procesar = cliente.post(f"/transferencias/{nro}/procesar")
    assert procesar.status_code == 200, procesar.text
    assert procesar.json()["estado"] == "procesado"
    assert _stock(consultar, id_sala, cod_vino) == (deposito - 2, sala + 2)

    consulta = cliente.get(f"/transferencias/{nro}").json()
    assert consulta == procesar.json()


# --- Transiciones inválidas (RN-11) y bloqueo de renglones (RN-12) ------------

def test_renglon_en_transferencia_terminada_409(cliente, consultar, consultar_filas) -> None:
    id_sala = _sala(consultar)
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _terminada(cliente, id_sala, cod_vino, 1)
    otro_vino = consultar("SELECT min(cod_vino) FROM vino WHERE cod_vino <> %s", (cod_vino,))

    respuesta = _renglon(cliente, nro, otro_vino, 1)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-12: la transferencia {nro} está terminado; no admite cambios en sus renglones.",
        "codigo": "P0001"}
    assert consultar("SELECT count(*) FROM renglon_transferencia WHERE nro_transferencia = %s", (nro,)) == 1


def test_procesar_sin_terminar_409(cliente, consultar, consultar_filas) -> None:
    id_sala = _sala(consultar)
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _nueva(cliente, id_sala)
    assert _renglon(cliente, nro, cod_vino, 1).status_code == 201
    antes = _stock(consultar, id_sala, cod_vino)

    respuesta = cliente.post(f"/transferencias/{nro}/procesar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["codigo"] == "P0001"
    assert respuesta.json()["detail"].startswith(f"RN-11: la transferencia {nro} está en_confeccion;")
    assert _estado(consultar, nro) == "en_confeccion"
    assert _stock(consultar, id_sala, cod_vino) == antes


def test_procesar_sin_stock_409_sin_cambios(cliente, consultar, consultar_filas) -> None:
    id_sala = _sala(consultar)
    cod_vino, disponible = _vino_con_stock(consultar_filas, minimo=1)
    nro = _terminada(cliente, id_sala, cod_vino, disponible + 1)
    antes = _stock(consultar, id_sala, cod_vino)

    respuesta = cliente.post(f"/transferencias/{nro}/procesar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json() == {
        "detail": f"RN-11: el depósito no tiene stock suficiente para la transferencia {nro}.",
        "codigo": "P0001"}
    # Todo o nada: ni el depósito, ni la sala, ni el estado cambiaron.
    assert _stock(consultar, id_sala, cod_vino) == antes
    assert _estado(consultar, nro) == "terminado"


def test_terminar_sin_renglones_409(cliente, consultar) -> None:
    nro = _nueva(cliente, _sala(consultar))

    respuesta = cliente.post(f"/transferencias/{nro}/terminar")

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["detail"] == f"RN-11: no se puede terminar la transferencia {nro} sin renglones."
    assert _estado(consultar, nro) == "en_confeccion"


def test_transiciones_despues_de_procesar(cliente, consultar, consultar_filas) -> None:
    id_sala = _sala(consultar)
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _terminada(cliente, id_sala, cod_vino, 1)

    # Terminar una transferencia ya terminada no es una transición: no cambia nada.
    otra_vez = cliente.post(f"/transferencias/{nro}/terminar")
    assert otra_vez.status_code == 200, otra_vez.text
    assert otra_vez.json()["estado"] == "terminado"

    assert cliente.post(f"/transferencias/{nro}/procesar").status_code == 200
    despues = _stock(consultar, id_sala, cod_vino)

    # Impacto único: procesar dos veces no mueve el stock otra vez.
    procesar = cliente.post(f"/transferencias/{nro}/procesar")
    assert procesar.status_code == 409, procesar.text
    assert procesar.json()["detail"].startswith(f"RN-11: la transferencia {nro} está procesado;")
    assert _stock(consultar, id_sala, cod_vino) == despues

    # Sin retrocesos.
    terminar = cliente.post(f"/transferencias/{nro}/terminar")
    assert terminar.status_code == 409, terminar.text
    assert terminar.json()["detail"] == (
        f"RN-11: transición de estado inválida para la transferencia {nro}: procesado -> terminado.")
    assert _estado(consultar, nro) == "procesado"


# --- Concurrencia: FOR UPDATE en sp_procesar_transferencia --------------------

def _esperando_bloqueo(consultar: Callable[..., Any], segundos: float = 10) -> bool:
    """True cuando alguna sesión espera un bloqueo dentro de sp_procesar_transferencia."""

    limite = time.monotonic() + segundos
    while time.monotonic() < limite:
        if consultar(
            "SELECT count(*) FROM pg_stat_activity "
            "WHERE datname = current_database() AND wait_event_type = 'Lock' "
            "AND left(query, 30) = 'CALL sp_procesar_transferencia'"
        ):
            return True
        time.sleep(0.05)
    return False


def test_procesar_concurrente_espera_y_no_mueve_dos_veces(
    cliente, consultar, consultar_filas, conexion_aparte
) -> None:
    """Dos procesos de la misma transferencia a la vez: el segundo espera el
    FOR UPDATE de la cabecera, encuentra 'procesado' y no mueve stock."""

    id_sala = _sala(consultar)
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _terminada(cliente, id_sala, cod_vino, 1)
    deposito, sala = _stock(consultar, id_sala, cod_vino)
    resultado: dict[str, Any] = {}

    def procesar_por_la_api() -> None:
        resultado["respuesta"] = cliente.post(f"/transferencias/{nro}/procesar")

    hilo = threading.Thread(target=procesar_por_la_api)
    # Otra sesión procesa primero y no confirma: retiene el bloqueo de la cabecera.
    with conexion_aparte.transaction():
        conexion_aparte.execute("CALL sp_procesar_transferencia(%s::bigint)", (nro,))
        hilo.start()
        assert _esperando_bloqueo(consultar), "el pedido de la API no quedó esperando el bloqueo"
        # Sin confirmar, las demás sesiones todavía ven el stock anterior.
        assert _stock(consultar, id_sala, cod_vino) == (deposito, sala)
    # COMMIT: la API recién ahora lee la cabecera, y la encuentra procesada.
    hilo.join(timeout=30)

    respuesta = resultado["respuesta"]
    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["detail"].startswith(f"RN-11: la transferencia {nro} está procesado;")
    # Las botellas se movieron una sola vez.
    assert _stock(consultar, id_sala, cod_vino) == (deposito - 1, sala + 1)


# --- Renglones: reglas de fila -------------------------------------------------

def test_renglon_repetido_409(cliente, consultar, consultar_filas) -> None:
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _nueva(cliente, _sala(consultar))
    assert _renglon(cliente, nro, cod_vino, 1).status_code == 201

    respuesta = _renglon(cliente, nro, cod_vino, 3)

    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["restriccion"] == "pk_renglon_transferencia"
    assert consultar("SELECT cantidad FROM renglon_transferencia WHERE nro_transferencia = %s", (nro,)) == 1


@pytest.mark.parametrize("cantidad", [0, -5])
def test_renglon_cantidad_no_positiva_422(cliente, consultar, consultar_filas, cantidad) -> None:
    cod_vino, _ = _vino_con_stock(consultar_filas)
    nro = _nueva(cliente, _sala(consultar))

    respuesta = _renglon(cliente, nro, cod_vino, cantidad)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json() == {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514",
                                "restriccion": "ck_renglon_transferencia_cantidad_positiva"}
    assert consultar("SELECT count(*) FROM renglon_transferencia WHERE nro_transferencia = %s", (nro,)) == 0


def test_renglon_con_vino_inexistente_422(cliente, consultar) -> None:
    nro = _nueva(cliente, _sala(consultar))

    respuesta = _renglon(cliente, nro, INEXISTENTE, 1)

    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["restriccion"] == "fk_renglon_transferencia_vino"


# --- Inexistente ---------------------------------------------------------------

@pytest.mark.parametrize(("metodo", "ruta", "cuerpo"), [
    ("GET", "", None),
    ("POST", "/renglones", {"cod_vino": 1, "cantidad": 1}),
    ("POST", "/terminar", None),
    ("POST", "/procesar", None),
])
def test_transferencia_inexistente_404(cliente, metodo, ruta, cuerpo) -> None:
    respuesta = cliente.request(metodo, f"/transferencias/{INEXISTENTE}{ruta}", json=cuerpo)

    assert respuesta.status_code == 404, respuesta.text
    # El texto viene del endpoint o del procedimiento, no del 404 de ruta inexistente.
    assert respuesta.json()["detail"] == f"La transferencia {INEXISTENTE} no existe."
