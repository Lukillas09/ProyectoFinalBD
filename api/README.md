# API (FastAPI + Psycopg 3)

Hoy la API expone sólo `GET /salud`, que ejecuta `SELECT 1` y responde 200, o 503 si PostgreSQL no responde. El contrato de la Etapa 6 está en [docs/api.md](../docs/api.md).

## Estado actual

| Archivo | Qué hace |
|---|---|
| `app/config.py` | Lee y valida la configuración desde variables de entorno (`DB_HOST`, `DB_USER`, …). Nunca arma ni registra una URL con la contraseña |
| `app/database.py` | Crea el pool (`psycopg_pool.ConnectionPool`) y el `SELECT 1` del control de salud |
| `app/main.py` | Abre y cierra el pool con el ciclo de vida de FastAPI, y define `/salud` |
| `tests/test_salud.py` | `/salud` responde 200 con la base real y 503 sin base |

Decisiones del pool:

- **`check=ConnectionPool.check_connection`.** Cada conexión se prueba antes de entregarla. Sin esto, después de reiniciar PostgreSQL el primer pedido recibía una conexión muerta y respondía 503. Verificado: 1 respuesta 503 tras reiniciar `db` sin `check`, 0 en tres reinicios con `check`.
- **`autocommit=True`.** Las transacciones se abren de forma explícita donde hacen falta (ver más abajo).
- **`open(wait=False)`.** La API arranca aunque la base todavía no responda; `/salud` informa 503 hasta que la base esté disponible.

Las versiones de `requirements.txt` están fijadas con `==`: son las que instalaba la imagen el 2026-11-05.

## Organización prevista para la Etapa 6

```
app/
  main.py          crea la app, registra routers y el manejador de errores
  config.py
  database.py      pool y helper de transacción
  datos/           acceso a datos: una función por consulta, SQL visible
    vinos.py
    clientes.py
    comprobantes.py
    documentos.py  transferencias e ingresos
    reportes.py
  routers/         un router por recurso: valida entrada, llama a datos/, arma la respuesta
    vinos.py  clientes.py  comprobantes.py  transferencias.py  ingresos.py  reportes.py
  errores.py       traducción SQLSTATE -> HTTP (docs/api.md, sección 3)
  esquemas.py      modelos Pydantic de entrada y salida
tests/
```

Reglas:

- **SQL sólo en `datos/`.** Cada función recibe una conexión y parámetros, ejecuta una consulta parametrizada (`cur.execute(sql, params)`, nunca f-strings ni concatenación con datos del usuario) y devuelve filas. Las columnas van explícitas, nunca `SELECT *`.
- **Los routers no escriben SQL ni calculan importes, descuentos o stock.** Llaman a `fn_registrar_venta`, `CALL sp_terminar_*`, `CALL sp_procesar_*`, y devuelven lo que la base calculó.
- **Transacciones explícitas** para las operaciones de varias sentencias (alta de vino con composición, alta de cliente con subtipo):

  ```python
  with pool.connection() as conn, conn.transaction():
      cod = datos.vinos.insertar(conn, vino)
      datos.vinos.insertar_composicion(conn, cod, composicion)
  ```

- **Errores en un solo lugar.** `errores.py` registra un manejador de `psycopg.Error` que lee `error.sqlstate` y `error.diag.message_primary`, y responde con la tabla de `docs/api.md`. No expone el detalle interno ni datos de conexión. Los 42501 se registran en el log y responden 500.
- **Rol de conexión:** `bodegas_api` (`DB_USER`), nunca el propietario. Los privilegios que necesita cada endpoint están verificados en `docs/api.md`, sección 4.

## Criterio de incorporación

No se crean carpetas ni archivos vacíos por adelantado. Cada pieza entra con su primer uso real:

- `datos/x.py` y `routers/x.py` junto con el primer endpoint del recurso `x`;
- `errores.py` con la primera operación que puede fallar por una regla de la base;
- `esquemas.py` con el primer cuerpo de entrada.

Cada endpoint nuevo llega con al menos una prueba en `tests/`. La consigna pide 8 en total, 3 de ellas provocando una regla de la base: venta sin stock (409), transición de estado inválida (409), precio negativo (422).

## Pruebas

Corren dentro de Docker, en la red interna donde está `db`, con el mismo rol y las mismas variables que la API. El servicio `api-test` (perfil `test`) usa la etapa `test` de `api/Dockerfile`: `pytest` y `httpx` están en `requirements-dev.txt` y no entran en la imagen de ejecución.

```bash
docker compose up -d --wait               # db y migraciones
docker compose --profile test run --rm --build api-test
```

Salida esperada (verificada el 2026-11-05):

```
tests/test_salud.py::test_salud_responde_200_con_la_base_disponible PASSED
tests/test_salud.py::test_salud_responde_503_sin_base PASSED
```

La prueba del 503 apunta la configuración a un puerto donde no escucha nada (`DB_PORT=1`), así que no hace falta detener la base. Starlette emite un aviso de deprecación sobre `httpx` en su `TestClient`. Se mantiene `httpx` porque es lo que usa hoy el `TestClient` de FastAPI.
