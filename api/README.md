# API (FastAPI + Psycopg 3)

## Estado actual

| Endpoint | Issue |
|---|---|
| `GET /salud` | Infraestructura |
| `GET /vinos` (filtros `tipo`, `id_cepa`, `cuit_bodega`, `anada` y paginación) | #25 |
| `GET /vinos/{cod_vino}` (ficha con composición y maridajes estructurados) | #25 |
| `POST /vinos` (con composición y maridajes, en una transacción) | #26 |
| `PUT /vinos/{cod_vino}` (reemplazo completo; la auditoría de precio la registra la base) | #26 |
| `DELETE /vinos/{cod_vino}` (409 si tiene ventas, movimientos, stock o cambios de precio) | #26 |
| `GET /clientes` (filtros `tipo`, `id_localidad` y paginación) | #27 |
| `GET /clientes/{id_cliente}` (ficha con su subtipo, permisos y el descuento que calcula la base) | #27 |
| `POST /clientes` (cliente, subtipo y permisos en una transacción; cuerpo según `tipo`) | #27 |
| `PUT /clientes/{id_cliente}` (datos comunes y del subtipo; el `tipo` no se cambia) | #27 |
| `DELETE /clientes/{id_cliente}` (409 si tiene comprobantes) | #27 |

Todo se apoya en la **base común de la Etapa 6** (issue #24):

- traducción de errores por SQLSTATE;
- conexión por pedido y transacciones explícitas;
- paginación;
- Swagger detrás de nginx;
- pruebas aisladas.

Los demás endpoints de negocio llegan con los issues #28 a #32, según el contrato de [docs/api.md](../docs/api.md).

## Qué hay

| Archivo | Qué hace |
|---|---|
| `app/config.py` | Lee y valida la configuración desde variables de entorno (`DB_HOST`, `DB_USER`, …). Nunca arma ni registra una URL con la contraseña |
| `app/database.py` | Pool (`check_connection`, `autocommit=True`), la dependencia `conexion` y el `SELECT 1` de `/salud` |
| `app/errores.py` | `traducir()`, una función pura SQLSTATE → HTTP, y `registrar_manejadores()` |
| `app/esquemas.py` | `ErrorRespuesta`, `Paginacion` y `Pagina[T]`; modelos, filtros y cuerpo de entrada (`VinoEntrada`) de vinos; uniones discriminadas por `tipo` de clientes (`ClienteEntrada`, `ClienteDetalle`) |
| `app/datos/vinos.py` | SQL de vinos: `listar()`, `detalle()`, `insertar*()`, `actualizar()`, `reemplazar_*()` y `borrar()` |
| `app/routers/vinos.py` | `GET`, `POST`, `PUT` y `DELETE` de `/vinos` |
| `app/datos/clientes.py` | SQL de clientes: `listar()`, `detalle()`, `insertar()`, `insertar_subtipo()`, `insertar_permisos()`, `actualizar()`, `actualizar_subtipo()` y `borrar()` |
| `app/routers/clientes.py` | `GET`, `POST`, `PUT` y `DELETE` de `/clientes` |
| `app/main.py` | `crear_app()`: ciclo de vida del pool, middleware del prefijo `/api`, manejadores de error, OpenAPI y `/salud` |
| `tests/` | Pruebas con pytest, más `ejecutar.sh` (ver "Pruebas") |

Decisiones del pool:

- **`check=ConnectionPool.check_connection`.** Cada conexión se prueba antes de entregarla. Sin esto, después de reiniciar PostgreSQL el primer pedido recibía una conexión muerta y respondía 503. Verificado: 1 respuesta 503 tras reiniciar `db` sin `check`, 0 en cuatro reinicios con `check`.
- **`autocommit=True`.** Cada sentencia suelta se confirma sola; las transacciones se abren de forma explícita (ver más abajo).
- **`open(wait=False)`.** La API arranca aunque la base todavía no responda; `/salud` informa 503 hasta que esté disponible.

Las versiones de `requirements*.txt` están fijadas con `==`.

## Cómo escribir un endpoint

### Conexión y transacciones

Cada endpoint que use la base recibe una conexión del pool con `Depends(conexion)`. Al terminar el pedido vuelve al pool, aunque haya un error.

- **Una sola sentencia** (una lectura, `SELECT fn_registrar_venta(...)`, `CALL sp_procesar_...`): se usa la conexión tal cual. En autocommit esa sentencia ya es atómica.
- **Varias sentencias que deben ir juntas** (alta de vino con su composición, alta de cliente con su subtipo): `with conn.transaction():`. Si algo falla dentro del bloque, todo se revierte.

El ejemplo real es el alta de vinos (`app/routers/vinos.py`, resumido):

```python
@router.post("", status_code=201)
def crear_vino(vino: VinoEntrada, request: Request, response: Response,
               conn: Connection = Depends(conexion)) -> VinoDetalle:
    with conn.transaction():
        cod_vino = datos.insertar(conn, vino)
        datos.insertar_composicion(conn, cod_vino, vino.composicion)
        datos.insertar_maridajes(conn, cod_vino, vino.maridajes)
    # Acá ya pasó el COMMIT: la suma de la composición al 100 % fue verificada.
    response.headers["Location"] = ...
    return _ficha_confirmada(conn, cod_vino)
```

Las funciones de `app/datos/` no abren transacciones: las abre el endpoint, que sabe qué sentencias van juntas. Una `HTTPException` dentro del bloque también revierte, como el 404 de `PUT /vinos/{cod_vino}` cuando el `UPDATE … RETURNING` no encuentra el vino.

La transacción se abre **dentro del endpoint**, no en una dependencia, por los constraint triggers diferidos (composición al 100 %, jerarquía de clientes). Esos triggers fallan recién en el `COMMIT`, al salir del bloque `with`, y así el error llega al manejador antes de armar la respuesta. Una dependencia con `yield` haría el `COMMIT` después de que FastAPI arma la respuesta. Lo prueba `test_constraint_trigger_diferido_falla_en_el_commit`: 409 con el mensaje de la base, y el cliente no queda guardado.

### Errores

Los endpoints **no capturan** `psycopg.Error`: lo dejan subir y `app/errores.py` lo traduce con la tabla de `docs/api.md`, sección 3. Todos los errores responden con el mismo cuerpo (`ErrorRespuesta`):

```json
{"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "uq_vino_identidad_comercial"}
```

- `detail` es siempre lo que se muestra.
  - En P0001 y P0002 es el mensaje de la base ("RN-09: stock insuficiente…").
  - En las restricciones es un texto genérico en español, más el nombre de la restricción en `restriccion` (o la columna en `columna`, para NOT NULL).
- Nunca va el DETAIL de PostgreSQL ni el texto completo de la excepción.
- Los 42501 y los SQLSTATE desconocidos responden 500 y quedan en el log (SQLSTATE, mensaje primario y nombres de tabla o restricción).
- Los errores de validación de FastAPI usan el mismo cuerpo: `codigo` "validacion" y la lista `errores` con `campo` y `mensaje`.

**"No existe" y otros errores propios: `HTTPException`.** Un `GET` por clave que no encuentra la fila responde 404 así (código real en `app/routers/vinos.py`):

```python
@router.get("/{cod_vino}")
def obtener_vino(cod_vino: int = Path(ge=1, le=MAX_BIGINT),
                 conn: Connection = Depends(conexion)) -> VinoDetalle:
    vino = datos.detalle(conn, cod_vino)
    if vino is None:
        raise HTTPException(404, f"El vino {cod_vino} no existe.")
    return VinoDetalle(**vino)
```

```json
{"detail": "El vino 7 no existe.", "codigo": "no_encontrado"}
```

Toda `HTTPException`, incluidas las que levanta Starlette, sale con el mismo cuerpo y un `codigo` según el estado:

| Estado | `codigo` | Ejemplo |
|---|---|---|
| 404 | `no_encontrado` | Ruta inexistente, o un "no existe" propio |
| 405 | `metodo_no_permitido` | Método no permitido; se conserva el encabezado `Allow` |
| 503 | `no_disponible` | `/salud` sin base |
| 400 / 401 / 403 / 409 / 500 | `solicitud_invalida` / `no_autenticado` / `prohibido` / `conflicto` / `interno` | — |
| Otro | `http_<estado>` | — |

El `detail` que escribe el endpoint se respeta. Si no hay uno (Starlette pone la frase en inglés, "Not Found"), va un texto en español.

**Si la base responde en otro idioma.** Para separar los dos 23503, `errores.py` compara el comienzo del mensaje de PostgreSQL con `insert or update on table` (falta el dato → 422) y `update or delete on table` (hay dependientes → 409). Esos textos son los del servidor en inglés: `en_US.utf8` (la imagen actual), `C` o `C.UTF-8`.

- Si `lc_messages` estuviera en otro idioma (por ejemplo, en la nube de la Etapa 8), los dos casos responderían **409** y quedaría una advertencia en el log por cada uno.
- Nada se rompe, pero el 422 de "falta el dato relacionado" se perdería. Se corrige configurando el servidor en inglés; el rol de la API no puede cambiarlo.
- `test_textos_de_23503_que_reconoce_la_traduccion` provoca los dos errores reales y verifica sus textos, sin fijar el valor de `lc_messages`. Si falla en un entorno nuevo, ese entorno responde en otro idioma.

### Listados paginados

Parámetros comunes con `Depends()`: `limite` (por omisión 20, de 1 a 100) y `desplazamiento` (por omisión 0, ≥ 0). Fuera de rango, la respuesta es 422 con `codigo` "validacion". La respuesta es `Pagina[T]`: `{"items", "limite", "desplazamiento", "total"}`.

`total` sale **de la misma consulta**, con `count(*) OVER ()`: un solo viaje a la base y la misma foto de los datos que los `items`. Si la página quedó vacía porque el desplazamiento supera el total, no hay filas de donde leerlo y se cuenta aparte. La respuesta es 200 con `items: []`, nunca 404.

El ejemplo real es `GET /vinos`:

- `app/datos/vinos.py` (`listar`, con las constantes `LISTAR` y `CONTAR`);
- `app/routers/vinos.py` (`listar_vinos`).

Los filtros opcionales se escriben como `(%(x)s::tipo IS NULL OR columna = %(x)s)`. La consulta es siempre la misma, y el cast le dice a PostgreSQL el tipo del parámetro aunque llegue NULL. Los filtros se declaran en una clase de dependencia (`FiltrosVino`, como `Paginacion`), con el mismo dominio que la columna; así un valor inválido responde 422 y no llega a la base.

El patrón está probado contra la base en `tests/test_paginacion.py`, sobre `localidad`, y en `tests/test_vinos_catalogo.py`. Siempre hace falta `ORDER BY`: sin él, `LIMIT/OFFSET` no garantiza páginas estables.

## Swagger

- Directo: `http://localhost:8000/docs`.
- Por el proxy: `http://localhost:8080/api/docs`.

nginx quita `/api` y avisa el prefijo con `X-Forwarded-Prefix: /api`. El middleware `PrefijoDelProxy` lo pasa a `root_path`; así, por el proxy, Swagger pide `/api/openapi.json` y "Try it out" llama a `/api/...`.

Sólo se acepta exactamente `/api`. Swagger incrusta el prefijo en su HTML sin escaparlo, así que aceptar un valor arbitrario enviado al puerto de la API sería un XSS reflejado.

## Organización y criterio de incorporación

```
app/
  datos/      una función por consulta, SQL parametrizado y visible (vinos.py, clientes.py)
  routers/    un router por recurso: valida, llama a datos/, responde (vinos.py, clientes.py)
```

- **SQL sólo en `app/datos/`.** Siempre parámetros (`%s` o `%(nombre)s`), nunca f-strings ni concatenación con datos del usuario. Columnas explícitas, nunca `SELECT *`.
- **Los routers no calculan** importes, descuentos ni stock: llaman a `fn_registrar_venta` y a `CALL sp_*`, y devuelven lo que la base calculó.
- **Rol de conexión:** `bodegas_api`, nunca el propietario. Los privilegios de cada endpoint están verificados en `docs/api.md`, sección 4.
- No se crean carpetas ni archivos vacíos por adelantado: cada pieza entra con su primer uso real, y cada endpoint con sus pruebas. `datos/` y `routers/` no tienen `__init__.py`: Python los importa como paquetes de espacio de nombres.
- **Validación de entrada sólo de forma.** Pydantic valida tipos, dominio y escala de cada columna, y repetidos en las listas. Las reglas de negocio (por ejemplo, `precio > 0` o la composición al 100 %) no se repiten en Python: las rechaza PostgreSQL y las traduce `app/errores.py` (ver `VinoEntrada`).
- **Un cuerpo distinto por tipo: unión discriminada.** Cuando los campos obligatorios dependen de un discriminador, como el `tipo` de un cliente, el cuerpo es `Annotated[A | B | C, Field(discriminator="tipo")]`: Pydantic elige el modelo por `tipo` y un campo faltante del subtipo responde 422 (`body.distribuidor.nro_habilitacion`). En OpenAPI queda como `oneOf` con `discriminator`. La ficha de respuesta usa la misma forma y se arma con `TypeAdapter(...).validate_python(fila)` (ver `routers/clientes.py`).
- **Listas en una sola sentencia.** Las filas hijas se insertan con `unnest` de arrays (`INSERT … SELECT … FROM unnest(%(ids)s::integer[], …)`), como en `datos/vinos.py` y los permisos de `datos/clientes.py`.
- **Dinero y `NUMERIC` como `Decimal`**, nunca `float`. En el JSON salen como string (`"precio": "43660.00"`). Si un `NUMERIC` llega dentro de un JSON armado en PostgreSQL (`json_agg`), se lee con `set_json_loads(partial(json.loads, parse_float=Decimal), cur)`, como en `datos/vinos.py`.
- Un router por recurso se registra en `crear_app()` (`app/main.py`), junto con su etiqueta en `ETIQUETAS`.

## Pruebas

```bash
api/tests/ejecutar.sh                  # todas (unos 60 s)
api/tests/ejecutar.sh -k paginacion    # los argumentos van a pytest
MANTENER=1 api/tests/ejecutar.sh       # deja el proyecto arriba para depurar
```

El script hace esto:

1. levanta un **proyecto de Compose aislado** (`bodegas_pruebas`) desde un volumen vacío, con `.env.example`;
2. lo carga con `ESCALA=0.1` (2.000 clientes, unos 15.000 comprobantes, unos 6 s);
3. corre pytest en el servicio `api-test`;
4. lo baja con `down -v`;
5. devuelve el código de pytest.

**Nunca usa el proyecto por defecto**: las pruebas que escriben (ventas, transferencias) no tocan los datos de trabajo. Variables: `PROYECTO`, `ESCALA`, `API_PORT` / `FRONT_PORT` (18800 / 18880 en el host) y `ENV_FILE`.

Reglas para las pruebas de los issues siguientes:

- **Rol `bodegas_api`**, el mismo de la API. El propietario no se usa para preparar datos.
- **Datos que hacen falta.**
  - Catálogos y stock existente se **buscan** en el dataset con la fixture `consultar` (lectura como `bodegas_api`), por ejemplo `consultar("SELECT min(cuit) FROM bodega")`. No se escriben ids fijos: el dataset cambia con `FECHA_REFERENCIA`.
  - Lo que la prueba crea lleva un **valor único** (fixture `marca`) y se crea **por la propia API** cuando el endpoint existe.
- **Sin datos a medias.** Cada prueba de error verifica con `consultar` que no quedó nada, por ejemplo `consultar("SELECT count(*) FROM cliente WHERE nombre_razon_social = %s", (marca,)) == 0`.
- **Errores reales sin rutas falsas en la app.** `conftest.py` arma la aplicación con `crear_app()` y le agrega rutas `/_prueba/...` sólo para las pruebas. `app.main.app` no las tiene.
- **Swagger se prueba por HTTP real.** `api-test` está en las redes `datos` y `web`, y llama a `http://api:8000` y a `http://front/api/...`.

`docker compose --profile test run --rm api-test` sigue funcionando contra un entorno ya levantado y cargado, pero las pruebas que escriben quedarían en esa base. Por eso el camino documentado es `ejecutar.sh`.

Starlette emite un aviso de deprecación sobre `httpx` en su `TestClient`; se mantiene `httpx` porque es lo que usa hoy el `TestClient` de FastAPI.
