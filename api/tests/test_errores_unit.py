"""Pruebas de traducir() (una por familia de SQLSTATE) y de traducir_http(), sin base de datos.

Los mensajes primarios son los textos reales de PostgreSQL 16 registrados en
tests/test_errores_db.py, que los provoca contra la base.
"""

import logging

import pytest

from app.errores import traducir, traducir_http


def test_23505_unique_409_con_restriccion() -> None:
    t = traducir("23505", 'duplicate key value violates unique constraint "uq_vino_identidad_comercial"',
                 "uq_vino_identidad_comercial")
    assert t.status == 409
    assert t.cuerpo.codigo == "23505"
    assert t.cuerpo.restriccion == "uq_vino_identidad_comercial"
    assert "uq_vino" not in t.cuerpo.detail  # mensaje genérico, sin el texto de PostgreSQL


def test_23503_falta_dato_relacionado_422() -> None:
    t = traducir("23503", 'insert or update on table "composicion_vino" violates foreign key '
                 'constraint "fk_composicion_vino_vino"', "fk_composicion_vino_vino")
    assert t.status == 422
    assert t.cuerpo.restriccion == "fk_composicion_vino_vino"


def test_23503_fila_con_dependientes_409() -> None:
    t = traducir("23503", 'update or delete on table "vino" violates foreign key constraint '
                 '"fk_auditoria_precio_vino" on table "auditoria_precio"', "fk_auditoria_precio_vino")
    assert t.status == 409
    assert t.cuerpo.restriccion == "fk_auditoria_precio_vino"
    assert t.nivel_log is None


def test_23503_texto_no_reconocido_409_y_aviso() -> None:
    t = traducir("23503", "la clave viola una restricción", "fk_x")
    assert t.status == 409
    assert t.nivel_log == logging.WARNING


def test_23514_check_422() -> None:
    t = traducir("23514", 'new row for relation "vino" violates check constraint "ck_vino_precio_positivo"',
                 "ck_vino_precio_positivo")
    assert (t.status, t.cuerpo.restriccion) == (422, "ck_vino_precio_positivo")


def test_23502_not_null_422_con_columna() -> None:
    t = traducir("23502", 'null value in column "nombre" of relation "vino" violates not-null constraint',
                 None, "nombre")
    assert (t.status, t.cuerpo.columna, t.cuerpo.restriccion) == (422, "nombre", None)


def test_p0001_regla_409_con_mensaje_de_la_base() -> None:
    t = traducir("P0001", "RN-09: stock insuficiente del vino 1 en la sala 1.")
    assert t.status == 409
    assert t.cuerpo.detail == "RN-09: stock insuficiente del vino 1 en la sala 1."


def test_p0002_no_existe_404() -> None:
    t = traducir("P0002", "La transferencia -1 no existe.")
    assert (t.status, t.cuerpo.detail) == (404, "La transferencia -1 no existe.")


@pytest.mark.parametrize(("sqlstate", "status"), [("22P02", 400), ("22001", 422), ("22003", 422)])
def test_datos_invalidos(sqlstate: str, status: int) -> None:
    t = traducir(sqlstate, 'invalid input syntax for type integer: "abc"')
    assert t.status == status
    assert "abc" not in t.cuerpo.detail  # no se repite el valor enviado


@pytest.mark.parametrize("sqlstate", ["40001", "40P01"])
def test_concurrencia_503_con_retry_after(sqlstate: str) -> None:
    t = traducir(sqlstate, "could not serialize access")
    assert t.status == 503
    assert t.encabezados == {"Retry-After": "1"}


def test_42501_500_sin_detalles_y_registrado() -> None:
    t = traducir("42501", "permission denied for table empleado")
    assert t.status == 500
    assert t.cuerpo.codigo == "interno"
    assert "empleado" not in t.cuerpo.detail
    assert t.nivel_log == logging.ERROR


@pytest.mark.parametrize("sqlstate", ["08006", None])
def test_conexion_503(sqlstate: str | None) -> None:
    t = traducir(sqlstate, None)
    assert (t.status, t.cuerpo.codigo) == (503, "no_disponible")


def test_sqlstate_desconocido_500_registrado() -> None:
    t = traducir("XX000", "internal error")
    assert (t.status, t.cuerpo.codigo, t.nivel_log) == (500, "interno", logging.ERROR)


# --- HTTPException --------------------------------------------------------

@pytest.mark.parametrize(
    ("status", "detail", "codigo", "texto"),
    [
        # Sin detalle propio, Starlette manda la frase en inglés: va el texto en español.
        (404, "Not Found", "no_encontrado", "Recurso no encontrado."),
        (405, "Method Not Allowed", "metodo_no_permitido", "Método no permitido para este recurso."),
        # Un detalle propio de un endpoint se respeta.
        (404, "El vino 7 no existe.", "no_encontrado", "El vino 7 no existe."),
        (503, "Base de datos no disponible.", "no_disponible", "Base de datos no disponible."),
        (418, "I'm a Teapot", "http_418", "Error en la solicitud."),
    ],
)
def test_http_codigo_por_estado(status: int, detail: str, codigo: str, texto: str) -> None:
    t = traducir_http(status, detail)
    assert (t.status, t.cuerpo.codigo, t.cuerpo.detail) == (status, codigo, texto)


def test_http_conserva_encabezados() -> None:
    t = traducir_http(405, "Method Not Allowed", {"Allow": "GET"})
    assert t.encabezados == {"Allow": "GET"}
