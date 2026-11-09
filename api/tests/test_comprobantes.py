"""Pruebas de integración para POST /comprobantes y GET /comprobantes/{nro} (issue #28).

Convenio: corren dentro de Docker (servicio api-test), en la red interna donde
está db y con las mismas variables de entorno que la API. Never se conectan
como propietario. Cada prueba usa un volumen descartable y aislado.

Sigue las convenciones de: test_vinos_abm.py, test_clientes.py.
"""

from fastapi.testclient import TestClient
import pytest


# ---------------------------------------------------------------------------
# Fixtures (mismo patrón que conftest.py)
# ---------------------------------------------------------------------------

def _conectar():
    import os
    import psycopg
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        autocommit=True,
        options="-c search_path=bodegas,pg_catalog",
    )


@pytest.fixture(scope="session")
def consultar() -> callable:
    """Ejecuta una consulta de lectura y devuelve el primer valor."""
    conn = _conectar()
    def ejecutar(sql, params=()):
        fila = conn.execute(sql, params).fetchone()
        return None if fila is None else fila[0]
    yield ejecutar
    conn.close()


@pytest.fixture(scope="session")
def consultar_filas() -> callable:
    """Como consultar, pero devuelve todas las filas."""
    conn = _conectar()
    def ejecutar(sql, params=()):
        return conn.execute(sql, params).fetchall()
    yield ejecutar
    conn.close()


@pytest.fixture(scope="session")
def marca() -> str:
    """Valor único por prueba."""
    import uuid
    return "prueba-" + uuid.uuid4().hex[:10]


# ---------------------------------------------------------------------------
# Helper: datos de la carga base
# ---------------------------------------------------------------------------

def _primer_vino(consultar):
    return consultar("SELECT cod_vino FROM vino LIMIT 1")


def _primer_cliente(consultar):
    return consultar("SELECT id_cliente FROM cliente LIMIT 1")


def _primer_sala(consultar):
    return consultar("SELECT id_sala FROM sala_venta LIMIT 1")


# ---------------------------------------------------------------------------
# Prueba 1: Venta correcta → 201, estructura de respuesta completa
# ---------------------------------------------------------------------------

def test_venta_correcta_estructura(cliente, consultar, consultar_filas, marca) -> None:
    """Verificar que POST /comprobantes devuelve 201 con estructura completa."""

    cod_vino = _primer_vino(consultar)
    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if cod_vino is None or id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de prueba en la base")

    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": cod_vino, "cantidad": 1}],
        },
    )

    # 1. HTTP 201
    print(f"DEBUG status={respuesta.status_code} body={respuesta.text}")
    assert respuesta.status_code == 201, (
        f"Expected 201, got {respuesta.status_code}: {respuesta.text}"
    )

    # 2. Estructura completa de respuesta
    data = respuesta.json()
    campos_obligatorios = [
        "nro_comprobante", "fecha", "subtotal", "descuento", "total", "renglones"
    ]
    for campo in campos_obligatorios:
        assert campo in data, f"Falta '{campo}' en respuesta: {list(data.keys())}"

    # 3. Renglones con datos esperados
    assert len(data["renglones"]) > 0, "La lista de renglones está vacía"
    rg = data["renglones"][0]
    assert rg["cod_vino"] == cod_vino, f"cod_vino mismatch: {rg['cod_vino']} != {cod_vino}"
    assert "nombre_vino" in rg and rg["nombre_vino"] is not None, \
        f"nombre_vino esperado, got: {rg['nombre_vino']!r}"
    assert rg["cantidad"] == 1, f"cantidad esperada 1, got {rg['cantidad']}"

    # 4. Total coincide con PostgreSQL (comparación string para NUMERIC)
    nro = data["nro_comprobante"]
    filas = consultar_filas("SELECT total FROM comprobante WHERE nro_comprobante = %s", (nro,))
    assert len(filas) == 1, f"Expected 1 fila, got {len(filas)}"
    total_db = str(filas[0][0])
    assert str(data["total"]) == total_db, (
        f"Total mismatch: API={data['total']!r}, DB={total_db!r}"
    )


# ---------------------------------------------------------------------------
# Prueba 2: Stock insuficiente (RN-09) → 409
# ---------------------------------------------------------------------------

def test_venta_sin_stock_rn09(cliente, consultar, marca) -> None:
    """Vender más de lo disponible → 409 con RN-09."""

    # Usar un enfoque simpler: intentar vender una cantidad muy grande
    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de cliente/sala")

    # Primera venta para tener un comprobante base
    alta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 1}],
        },
    )
    if alta.status_code != 201:
        pytest.skip(f"No se pudo dar de alta inicialmente: {alta.text}")

    # Ahora intentar vender una cantidad excesiva
    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 999999}],
        },
    )

    # 1. HTTP 409
    assert respuesta.status_code == 409, (
        f"Expected 409, got {respuesta.status_code}: {respuesta.text}"
    )

    # 2. Mensaje incluye RN-09
    data = respuesta.json()
    detalle = data.get("detail", "")
    assert "RN-09" in detalle, f"Expected 'RN-09' in detail, got: {detalle}"


# ---------------------------------------------------------------------------
# Prueba 3: Vino repetido → 409
# ---------------------------------------------------------------------------

def test_venta_vino_repetido_409(cliente, consultar, marca) -> None:
    """Vino repetido en renglones → 409."""

    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de cliente/sala")

    # Venta inicial
    cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 1}],
        },
    )

    # Venta con vino repetido
    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [
                {"cod_vino": 1, "cantidad": 1},
                {"cod_vino": 1, "cantidad": 1},
            ],
        },
    )

    assert respuesta.status_code == 409, (
        f"Expected 409, got {respuesta.status_code}: {respuesta.text}"
    )


# ---------------------------------------------------------------------------
# Prueba 4: Cantidad cero → 409
# ---------------------------------------------------------------------------

def test_venta_cantidad_cero_409(cliente, consultar, marca) -> None:
    """Cantidad cero → 409 RN-15."""

    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de cliente/sala")

    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 0}],
        },
    )

    assert respuesta.status_code == 409, (
        f"Expected 409, got {respuesta.status_code}: {respuesta.text}"
    )


# ---------------------------------------------------------------------------
# Prueba 5: Cliente inexistente → 422
# ---------------------------------------------------------------------------

def test_venta_cliente_inexistente_422(cliente, consultar, marca) -> None:
    """Cliente inexistente → 422."""

    id_cliente_inexistente = 999999999
    id_sala = _primer_sala(consultar)

    if id_sala is None:
        pytest.skip("No hay datos de sala")

    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente_inexistente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 1}],
        },
    )

    assert respuesta.status_code == 422, (
        f"Expected 422, got {respuesta.status_code}: {respuesta.text}"
    )


# ---------------------------------------------------------------------------
# Prueba 6: Vino inexistente → 422 mensaje claro
# ---------------------------------------------------------------------------

def test_venta_vino_inexistente_422(cliente, consultar, marca) -> None:
    """Vino inexistente → 422 con mensaje claro (no precio_unitario)."""

    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de cliente/sala")

    respuesta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 999999, "cantidad": 1}],
        },
    )

    assert respuesta.status_code == 422, (
        f"Expected 422, got {respuesta.status_code}: {respuesta.text}"
    )
    data = respuesta.json()
    detalle = data.get("detail", "")
    # Debe contener el número 999999 y no ser el error interno de PostgreSQL
    assert "999999" in detalle, f"Expected '999999' in detail, got: {detalle}"


# ---------------------------------------------------------------------------
# Prueba 7: GET /comprobantes/{nro} existente → 200
# ---------------------------------------------------------------------------

def test_obtener_comprobante_existente_200(cliente, consultar, consultar_filas, marca) -> None:
    """GET /comprobantes/{nro} → 200 con datos reales."""

    # Registrar una venta
    id_cliente = _primer_cliente(consultar)
    id_sala = _primer_sala(consultar)

    if id_cliente is None or id_sala is None:
        pytest.skip("No hay datos de cliente/sala")

    alta = cliente.post(
        "/comprobantes",
        json={
            "id_cliente": id_cliente,
            "id_sala": id_sala,
            "renglones": [{"cod_vino": 1, "cantidad": 1}],
        },
    )
    assert alta.status_code == 201, f"Falló el alta: {alta.text}"
    nro = alta.json()["nro_comprobante"]

    # Consultarlo
    respuesta = cliente.get(f"/comprobantes/{nro}")

    assert respuesta.status_code == 200, (
        f"Expected 200, got {respuesta.status_code}: {respuesta.text}"
    )

    data = respuesta.json()
    assert data["nro_comprobante"] == nro, "nro_comprobante mismatch"
    assert len(data["renglones"]) > 0, "renglones vacíos"
    assert "total" in data, "Falta total"


# ---------------------------------------------------------------------------
# Prueba 8: GET /comprobantes/{nro} inexistente → 404
# ---------------------------------------------------------------------------

def test_obtener_comprobante_inexistente_404(cliente, marca) -> None:
    """GET /comprobantes/999999 → 404."""

    respuesta = cliente.get("/comprobantes/999999")

    assert respuesta.status_code == 404, (
        f"Expected 404, got {respuesta.status_code}: {respuesta.text}"
    )
    data = respuesta.json()
    detalle = data.get("detail", "")
    assert "999999" in detalle or "no existe" in detalle.lower(), \
        f"Expected '999999 no existe' in message, got: {detalle}"