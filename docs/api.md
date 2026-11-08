# Contrato de la API REST (Etapa 6) — borrador

Borrador del contrato HTTP de la Etapa 6, tomado de la consigna (`material/TPI_Bodegas_del_Atuel.pdf`, páginas 16 y 17: "Etapa 6. API REST"). **No está implementado**: hoy sólo existe `GET /salud`. Sirve para repartir el trabajo y para revisar, antes de escribir código, si la base ya permite cada operación con el rol de la API.

Principios que fija la consigna y `AGENTS.md`:

- La API se conecta como `bodegas_api` (grupo `bodegas_rw`), nunca como propietario.
- SQL directo y parametrizado, con una función por consulta en un módulo de acceso a datos.
- Totales, descuentos, stock, estados y auditoría los resuelve PostgreSQL. La API invoca funciones y procedimientos (`fn_registrar_venta`, `sp_terminar_*`, `sp_procesar_*`) y devuelve lo que la base calculó.
- Las operaciones de varias sentencias van en una transacción explícita.
- Los errores de PostgreSQL se traducen por `SQLSTATE` (sección 3).

Convenciones:

- JSON en UTF-8.
- Listados con `?limite=` (por omisión 20, máximo 100) y `?desplazamiento=` (por omisión 0). Responden `{"items": [...], "limite": n, "desplazamiento": n, "total": n}`.
- Errores con el cuerpo `ErrorRespuesta` (sección 3): `{"detail", "codigo", "restriccion"?, "columna"?, "errores"?}`. El mensaje de una regla de negocio es el de la base, por ejemplo "RN-09: stock insuficiente del vino 1 en la sala 1."
- Las rutas son las de la consigna. Detrás de nginx se publican bajo `/api` (ver la sección 5).

## 1. Endpoints

### Vinos

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `GET /vinos` | Filtros `tipo`, `id_cepa`, `cuit_bodega`, `anada`, más paginación | 200, listado | 400 (22P02, filtro mal formado) |
| `GET /vinos/{cod}` | — | 200, ficha de `v_ficha_vino`: corte con cepas y porcentajes, maridajes, stock total | 404 si no existe |
| `POST /vinos` | `{nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega, composicion: [{id_cepa, porcentaje}], maridajes: [id_maridaje]}` | 201, con `cod_vino` | 409 (23505, vino repetido: `uq_vino_identidad_comercial`); 422 (23514, por ejemplo precio ≤ 0 o graduación fuera de 5–20); 422 (23503, bodega o cepa inexistente); 409 (P0001, la composición no suma 100 %) |
| `PUT /vinos/{cod}` | Mismos campos | 200. Si cambia el precio, `trg_vino_auditoria_precio` registra la auditoría (RN-13) | 404, 422, 409 como en el alta |
| `DELETE /vinos/{cod}` | — | 204 | 404; **409 (23503)** si tiene ventas, ingresos, transferencias **o historia de precios** (`fk_auditoria_precio_vino`). En la práctica, un vino al que se le cambió el precio no se puede borrar |

El alta inserta `vino`, `composicion_vino` y `vino_maridaje` en **una transacción**. La regla de la composición al 100 % es un constraint trigger diferido: se verifica al confirmar.

### Clientes

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `GET /clientes` | Filtros `tipo`, `id_localidad`, más paginación | 200 | 400 |
| `GET /clientes/{id}` | — | 200, con los datos de su subtipo | 404 |
| `POST /clientes` | `{nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo, ...}`. Según `tipo`: `distribuidor: {zona_cobertura, nro_habilitacion}`, `exportador: {pais_destino_principal, permisos: [...]}` | 201, con `id_cliente` | 409 (23505, documento repetido: `uq_cliente_documento`); 422 (23514, 23502); 422 (23503, localidad inexistente, o un subtipo que no corresponde al tipo: `fk_distribuidor_cliente`); 409 (P0001 al confirmar: "Jerarquía de clientes: el cliente … no tiene su fila de subtipo.") |
| `PUT /clientes/{id}` | Datos comunes y del subtipo. `tipo` no se cambia | 200 | 404, 409, 422 |
| `DELETE /clientes/{id}` | — | 204. Los subtipos se borran en cascada | 404; **409 (23503)** si tiene comprobantes (`fk_comprobante_cliente`) |

El alta inserta `cliente` y su fila de subtipo en **una transacción**: la regla de totalidad de la jerarquía es diferida. El descuento no se envía: lo calcula `fn_descuento_cliente` (RN-06), y la excepción del 35 % sólo se acepta para exportadores (U6).

### Comprobantes

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `POST /comprobantes` | `{id_cliente, id_sala, renglones: [{cod_vino, cantidad}]}` | 201: `{nro_comprobante, fecha, subtotal, descuento, total, renglones: [...]}` leídos de la base después de la venta | **409 (P0001)**: "RN-09: stock insuficiente…", vino repetido, cantidad no positiva, venta sin renglones. 422 (23503): cliente o sala inexistente (`fk_comprobante_cliente`, `fk_comprobante_sala_venta`). 422 (23502): vino inexistente (ver la nota) |
| `GET /comprobantes/{nro}` | — | 200, cabecera y renglones | 404 |

La venta es una sola llamada a `fn_registrar_venta(id_cliente, id_sala, vinos[], cantidades[])`, que crea cabecera y renglones en la misma transacción: todo o nada. La API no tiene `INSERT` sobre `comprobante` (sección 4).

Nota, verificada: con un `cod_vino` inexistente la base responde `23502: null value in column "precio_unitario"`, porque el trigger no encuentra el precio antes de que actúe la FK. El código se traduce bien (422), pero el mensaje no es claro para el usuario. Hay dos opciones: que la API valide la existencia del vino antes de vender, o una 009 que haga que el trigger levante P0002 ("El vino % no existe."). Queda como decisión de la Etapa 6.

### Transferencias e ingresos

| Método y ruta | Cuerpo | Respuesta | Errores esperados |
|---|---|---|---|
| `POST /transferencias` | `{id_sala}` | 201: `{nro_transferencia, estado: "en_confeccion"}` | 422 (23503) |
| `POST /transferencias/{nro}/renglones` | `{cod_vino, cantidad}` | 201 | 404; 409 (P0001, la transferencia ya no está en confección, RN-12); 409 (23505, vino repetido); 422 (23514) |
| `POST /transferencias/{nro}/terminar` | — | 200, `estado: "terminado"` (`CALL sp_terminar_transferencia`) | 404; 409 (P0001, transición inválida o sin renglones, RN-11) |
| `POST /transferencias/{nro}/procesar` | — | 200, `estado: "procesado"` (`CALL sp_procesar_transferencia`) | 404; 409 (P0001, sin stock en el depósito: no deja cambios) |
| `POST /ingresos` | `{cod_transportista, cuit_bodega}` | 201: `{cod_ingreso, estado: "en_confeccion"}` | 422 (23503) |
| `POST /ingresos/{cod}/renglones` | `{cod_vino, cantidad}` | 201 | igual que en transferencias (RN-10, RN-12) |
| `POST /ingresos/{cod}/terminar` | — | 200 (`CALL sp_terminar_ingreso`) | **No figura en la consigna**: ver la sección 6 |
| `POST /ingresos/{cod}/procesar` | — | 200 (`CALL sp_procesar_ingreso`) | 404; 409 (P0001, transición inválida, RN-10) |

### Reportes (consultas de la sección 8, sólo lectura)

| Método y ruta | Parámetros | Consulta base |
|---|---|---|
| `GET /reportes/top-vinos` | `limite` (10) | S1 |
| `GET /reportes/ventas-por-sala` | `desde`, `hasta` (por omisión, el último trimestre) | S8 y `v_ventas_mensuales_sala` |
| `GET /reportes/vinos-sin-stock` | `id_sala` | S6 |
| `GET /reportes/transportista-activo` | `dias` (30) | S7 |
| `GET /reportes/trazabilidad/{cod}` | — | **Pregunta a la cátedra** (sección 6) |

### Salud

`GET /salud`: 200 `{"estado": "ok", "base_de_datos": "disponible"}` si `SELECT 1` responde; 503 si no. **Implementado y probado** (`api/tests/test_salud.py`).

## 2. Transacciones

| Operación | Cómo |
|---|---|
| Venta | Una sentencia: `SELECT fn_registrar_venta(...)`. La función es atómica |
| Alta de vino, alta de cliente | `BEGIN` → `INSERT` cabecera → `INSERT` detalle → `COMMIT`; ante cualquier error, `ROLLBACK`. Los constraint triggers diferidos se verifican en el `COMMIT` |
| Terminar o procesar documentos | Una sentencia: `CALL sp_*`. El procedimiento valida el estado y aplica el stock |
| Concurrencia | 40001 y 40P01 se traducen a 503 con `Retry-After` (ver `docs/concurrencia.md`) |

Con psycopg 3: `with pool.connection() as conn, conn.transaction():`. El pool trabaja en `autocommit` y cada bloque `transaction()` emite `BEGIN`/`COMMIT`.

## 3. Traducción de errores por SQLSTATE

Implementado en `api/app/errores.py` (issue #24) y probado contra PostgreSQL 16 en `api/tests/test_errores_db.py`. Tabla de la consigna (página 17), completada con los códigos que levanta este modelo:

| SQLSTATE | Situación en PostgreSQL | HTTP | `detail` | Campos extra |
|---|---|---|---|---|
| `23505` | `UNIQUE` o `PRIMARY KEY` violada | 409 | "Ya existe un registro con esos datos." | `restriccion` |
| `23503` | `FOREIGN KEY`: el dato relacionado no existe | 422 | "El dato relacionado no existe." | `restriccion` |
| `23503` | `FOREIGN KEY`: la fila tiene dependientes | 409 | "No se puede borrar ni modificar: hay datos que dependen de este registro." | `restriccion` |
| `23514` | `CHECK` violado | 422 | "Un valor no cumple una regla de validación." | `restriccion` |
| `23502` | `NOT NULL` violado | 422 | "Falta un dato obligatorio." | `columna` |
| `P0001` | Regla de negocio de un trigger o procedimiento (`RAISE EXCEPTION`, RN-xx) | 409 | El mensaje de la base | — |
| `P0002` | Un procedimiento no encuentra la fila (por ejemplo "La transferencia % no existe.") | 404 | El mensaje de la base | — |
| `22P02` | Texto con formato inválido para el tipo | 400 | "Un valor no tiene el formato esperado." | — |
| `22001`, `22003` | Texto demasiado largo, número fuera de rango | 422 | Mensaje genérico | — |
| `40001`, `40P01` | Fallo de serialización o deadlock | 503 + `Retry-After: 1` | "La operación chocó con otra simultánea. Reintente." | — |
| `42501` y cualquier otro | Permiso denegado al rol de la API; error inesperado | **500**, registrado en el log | "Error interno del servidor." (`codigo` "interno") | — |
| `08xxx`, `PoolTimeout`, `PoolClosed`, conexión perdida | Base no disponible | 503 | "Base de datos no disponible." (`codigo` "no_disponible") | — |
| Validación de FastAPI | Parámetro o cuerpo inválido | 422 | "Datos de entrada inválidos." (`codigo` "validacion") | `errores: [{campo, mensaje}]` |
| `HTTPException` | Ruta inexistente, método no permitido, "no existe" de un endpoint, `/salud` sin base | El de la excepción (404, 405, 503, …) | El del endpoint o un texto en español | `codigo` por estado: `no_encontrado`, `metodo_no_permitido`, `no_disponible`, …; se conservan los encabezados (`Allow`) |

**Cuerpo de error.** Lo usan todos los errores de la API y está declarado como `ErrorRespuesta` en OpenAPI:

```json
{"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "uq_vino_identidad_comercial"}
{"detail": "Datos de entrada inválidos.", "codigo": "validacion", "errores": [{"campo": "query.limite", "mensaje": "Input should be less than or equal to 100"}]}
```

`detail` es siempre lo que se muestra al usuario. `codigo` es el SQLSTATE, o bien `validacion`, `no_disponible`, `interno` o el código de una `HTTPException` (`no_encontrado`, `metodo_no_permitido`, …; tabla completa en `api/README.md`). Un "no existe" propio de un endpoint es `raise HTTPException(404, "El vino 7 no existe.")`, y responde `{"detail": "El vino 7 no existe.", "codigo": "no_encontrado"}`.

**Por qué 23503 puede ser 409 o 422.** El mismo SQLSTATE cubre dos situaciones, y no se decide por el método HTTP: una venta (`POST`) con un cliente inexistente es 422. Se decide por `diag.message_primary`, cuyos dos textos se verificaron en PostgreSQL 16:

- `insert or update on table "composicion_vino" violates foreign key constraint "fk_composicion_vino_vino"`: falta el dato → **422**;
- `update or delete on table "vino" violates foreign key constraint "fk_auditoria_precio_vino" on table "auditoria_precio"`: hay dependientes → **409**.

`diag.table_name` no sirve para distinguirlos, porque en los dos casos informa la tabla que referencia (`composicion_vino` y `auditoria_precio`). El texto depende del idioma de los mensajes del servidor (`lc_messages`), que el rol de la API no puede cambiar. En inglés (`en_US.utf8` en la imagen actual, o `C`, `C.UTF-8`) es el mismo. Una prueba provoca los dos errores reales y verifica que empiecen así, sin fijar el valor de `lc_messages`. Si el servidor respondiera en otro idioma, los dos casos darían 409 con una advertencia en el log, y el 422 se recuperaría configurando el servidor en inglés.

**Por qué 42501 es 500 y no 403.** No es un problema del cliente: indica que el código intentó algo que el rol no tiene otorgado, o sea un error de la API o de sus privilegios. Si alguna vez se agrega autenticación, 403 queda para "el usuario no puede", que es otra cosa.

**Qué es `diag.message_primary` y qué no se devuelve.** PostgreSQL separa cada error en un mensaje primario corto, un DETAIL y un HINT.

- **Al cliente:**
  - el mensaje primario va tal cual sólo en P0001 y P0002, porque esos textos los escribimos nosotros en los `RAISE`;
  - en los demás casos va un texto genérico más el nombre estable de la restricción;
  - nunca va el DETAIL (`Key (nombre, …)=(…) already exists` repite valores de la fila);
  - nunca va el texto completo de la excepción, que en errores de conexión incluye servidor y usuario.
- **Al log:** SQLSTATE, mensaje primario y nombres de tabla o restricción, nunca datos de conexión. Lo verifica `test_permiso_denegado_500_sin_detalles_y_al_log`.

## 4. Privilegios de `bodegas_api` frente a este contrato

Verificado el 2026-11-05: se ejecutaron como `bodegas_api` las sentencias de cada endpoint, dentro de `BEGIN … ROLLBACK` con `ON_ERROR_ROLLBACK`, sobre la base cargada. Las huellas de `hashes.sql` quedaron iguales.

| Endpoint | Resultado con `007_roles.sql` |
|---|---|
| `GET /vinos` (con cepa y bodega), `GET /vinos/{cod}` | OK |
| `POST /vinos` (vino, composición y maridaje; diferidos verificados) | OK |
| `PUT /vinos/{cod}` (precio) | OK; `auditoria_precio` recibe 1 fila por el trigger |
| `DELETE /vinos/{cod}` | OK sin dependientes. 23503 con historia de precios (`fk_auditoria_precio_vino`) o con ventas (`fk_renglon_comprobante_vino`) |
| `GET /clientes` (con localidad), `POST` de los tres tipos con permiso de exportación, `PUT`, `DELETE` | OK; 23503 al borrar un cliente con ventas |
| `POST /comprobantes`, `GET /comprobantes/{nro}` | OK; P0001 "RN-09: stock insuficiente del vino 1 en la sala 1." al vender sin stock; 23503 con cliente o sala inexistente; 23502 con vino inexistente |
| Terminar o procesar un documento inexistente | P0002 "La transferencia 99999999 no existe." |
| Transferencias e ingresos: alta, renglones, terminar, procesar | OK; los dos documentos llegan a `procesado` |
| Reportes top-vinos, ventas-por-sala, vinos-sin-stock, transportista-activo | OK |
| **Reporte trazabilidad** | **42501**: `permission denied for table parcela` |
| Escrituras prohibidas: `UPDATE`/`INSERT`/`DELETE` en `comprobante`, `UPDATE stock_sala`, `UPDATE ingreso.estado`, `INSERT auditoria_precio`, `fn_recalcular_comprobante` | 42501 en todos, como corresponde |

**Faltante para una futura `009`** (no se modificó nada): `SELECT` sobre `parcela`, `lote_uva`, `finca` y `analisis_calidad` para `bodegas_rw`, y `departamento` si el reporte muestra el departamento de la finca. Todas son de sólo lectura. Se otorgan recién cuando la cátedra confirme qué significa la trazabilidad (sección 6). Hoy `bodegas_rw` tampoco lee `empleado`, que ningún endpoint usa.

## 5. Detalles de infraestructura para la Etapa 6

- **Swagger detrás de nginx (resuelto en #24).**
  - Directo: `http://localhost:8000/docs`.
  - Por el proxy: `http://localhost:8080/api/docs`.
  - nginx envía `X-Forwarded-Prefix: /api` y un middleware de la API lo pasa a `root_path` **sólo si vale exactamente `/api`**. Por el proxy, el HTML pide `/api/openapi.json` y el esquema declara `servers: [{"url": "/api"}]`, que es lo que usa "Try it out". Directo no hay `servers` y todo queda en `/`.
  - Descartados:
    - `FastAPI(root_path="/api")` fijo: rompe el acceso directo, que pasaría a pedir `/api/openapi.json` al puerto de la API;
    - una `location` extra en nginx para `/openapi.json`: "Try it out" llamaría a `/salud` del front.
- **Pruebas.** La consigna pide al menos 8 pruebas automáticas, 3 de ellas sobre reglas de la base. Candidatas: venta sin stock (409), transición de estado inválida (409), precio negativo (422). Se corren con `api/tests/ejecutar.sh`, en un proyecto de Compose aislado y cargado (`api/README.md`, "Pruebas").
- **Inyección SQL.** La demostración de inyección fallida se hace sobre un filtro de `GET /vinos`: el valor viaja como parámetro y se compara como texto.

## 6. Preguntas abiertas para la cátedra

1. **`/reportes/trazabilidad/{cod}`.** El modelo no vincula un vino con lotes de uva concretos. `lote_uva` registra a qué bodega se entregó cada cosecha, y `vino` tiene bodega, añada y corte (cepas). La interpretación posible, que se probó como SQL salvo por el permiso, es esta: lotes de las cepas del corte, cosechados en la añada del vino y entregados a su bodega, con finca, parcela y análisis de calidad. Es una aproximación, no una trazabilidad exacta. ¿Alcanza, o se espera otro alcance (por ejemplo, sólo el corte y la bodega)?
2. **`POST /ingresos/{cod}/terminar`.** La consigna lista sólo `procesar` para ingresos, "mismo circuito que las transferencias". Pero RN-10 exige pasar por `terminado`, y `sp_terminar_ingreso` existe. ¿Se agrega el endpoint, o `procesar` debe terminar y procesar en un paso?
3. **S12 B.** ¿"Clientes que nunca compraron tintos" incluye a los que no compraron nada? Hoy sí: son 4.715 de 7.170.
