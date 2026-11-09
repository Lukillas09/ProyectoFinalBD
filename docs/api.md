# Contrato de la API REST (Etapa 6) — borrador

Borrador del contrato HTTP de la Etapa 6, tomado de la consigna (`material/TPI_Bodegas_del_Atuel.pdf`, páginas 16 y 17: "Etapa 6. API REST"). **Implementado hasta ahora:** `GET /salud`, el catálogo de vinos (`GET /vinos` y `GET /vinos/{cod_vino}`, issue #25) y su alta, modificación y baja (`POST /vinos`, `PUT` y `DELETE /vinos/{cod_vino}`, issue #26), el CRUD de clientes de los tres tipos (`/clientes`, issue #27), la venta y consulta de comprobantes (`/comprobantes`, issue #28) y el circuito de transferencias (`/transferencias`, issue #29). El resto sirve para repartir el trabajo y para revisar, antes de escribir código, si la base ya permite cada operación con el rol de la API.

Principios que fija la consigna y `AGENTS.md`:

- La API se conecta como `bodegas_api` (grupo `bodegas_rw`), nunca como propietario.
- SQL directo y parametrizado, con una función por consulta en un módulo de acceso a datos.
- Totales, descuentos, stock, estados y auditoría los resuelve PostgreSQL. La API invoca funciones y procedimientos (`fn_registrar_venta`, `sp_terminar_*`, `sp_procesar_*`) y devuelve lo que la base calculó.
- Las operaciones de varias sentencias van en una transacción explícita.
- Los errores de PostgreSQL se traducen por `SQLSTATE` (sección 3).

Convenciones:

- JSON en UTF-8.
- Dinero y demás `NUMERIC` viajan como **string** con la escala de la columna: `"precio": "43660.00"`, `"porcentaje": "40.00"` (ver "Vinos").
- Listados con `?limite=` (por omisión 20, máximo 100) y `?desplazamiento=` (por omisión 0). Responden `{"items": [...], "limite": n, "desplazamiento": n, "total": n}`.
- Errores con el cuerpo `ErrorRespuesta` (sección 3): `{"detail", "codigo", "restriccion"?, "columna"?, "errores"?}`. El mensaje de una regla de negocio es el de la base, por ejemplo "RN-09: stock insuficiente del vino 1 en la sala 1."
- Las rutas son las de la consigna. Detrás de nginx se publican bajo `/api` (ver la sección 5).

## 1. Endpoints

### Vinos

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `GET /vinos` | Filtros `tipo`, `id_cepa`, `cuit_bodega`, `anada`, más paginación | 200, `Pagina[VinoResumen]` | 422 (`validacion`, filtro inválido) |
| `GET /vinos/{cod_vino}` | — | 200, `VinoDetalle`: bodega, composición y maridajes estructurados, stock total | 404 (`no_encontrado`); 422 si `cod_vino` no es un entero de 1 a 2^63−1 |
| `POST /vinos` | `VinoEntrada`: `{nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega, composicion: [{id_cepa, porcentaje}], maridajes: [id_maridaje]}` | 201, `VinoDetalle` (la ficha del GET) y `Location: /vinos/{cod_vino}` | 409 (23505, vino repetido: `uq_vino_identidad_comercial`); 422 (23514, por ejemplo precio ≤ 0 o graduación fuera de 5–20); 422 (23503, bodega, cepa o maridaje inexistente); 409 (P0001, la composición no suma 100 %); 422 (`validacion`, forma inválida) |
| `PUT /vinos/{cod_vino}` | `VinoEntrada`: reemplazo completo, incluidas composición y maridajes | 200, `VinoDetalle`. Si cambia el precio, `trg_vino_auditoria_precio` registra la auditoría (RN-13) | 404 (`no_encontrado`); 409 y 422 como en el alta |
| `DELETE /vinos/{cod_vino}` | — | 204 | 404; **409 (23503)** si tiene ventas, ingresos, transferencias **o historia de precios** (`fk_auditoria_precio_vino`). En la práctica, un vino al que se le cambió el precio no se puede borrar |

El alta inserta `vino`, `composicion_vino` y `vino_maridaje` en **una transacción**. La regla de la composición al 100 % es un constraint trigger diferido: se verifica al confirmar. Detalle en "ABM implementado (issue #26)".

#### Catálogo implementado (issue #25)

Código: `api/app/datos/vinos.py` (SQL), `api/app/routers/vinos.py` (rutas) y `api/app/esquemas.py` (modelos). Pruebas: `api/tests/test_vinos_catalogo.py`.

**Filtros de `GET /vinos`.** Todos son opcionales y se combinan con AND. Cada uno se valida con el mismo dominio que la columna, así que un valor inválido responde 422 y nunca llega a la base:

| Parámetro | Validación | Igual que en la base |
|---|---|---|
| `tipo` | `tinto`, `blanco`, `rosado` o `espumante` | `ck_vino_tipo` |
| `id_cepa` | Entero de 1 a 2.147.483.647 | `INTEGER` |
| `cuit_bodega` | 11 dígitos (`^[0-9]{11}$`) | `cuit_dom` |
| `anada` | Entero de 1900 a 9999 | `ck_vino_anada` |

- Los vinos salen ordenados por `cod_vino`, así las páginas son estables.
- `id_cepa` devuelve los vinos que tienen esa cepa en su composición. Se resuelve con `EXISTS`, así un vino de corte aparece una sola vez.
- El SQL es siempre el mismo: cada filtro tiene la forma `(%(x)s::tipo IS NULL OR columna = %(x)s)` y el valor viaja como parámetro.

```json
GET /vinos?limite=2&tipo=tinto&anada=2020
{
  "items": [
    {"cod_vino": 7, "nombre": "Malbec Icono", "tipo": "tinto", "anada": 2020, "volumen_ml": 750,
     "graduacion": "15.50", "precio": "54730.00", "cuit_bodega": "30584932674", "bodega": "Bodega Molina S.R.L."},
    {"cod_vino": 9, "nombre": "Tempranillo Joven", "tipo": "tinto", "anada": 2020, "volumen_ml": 750,
     "graduacion": "15.50", "precio": "16380.00", "cuit_bodega": "33525245174", "bodega": "Bodega Fernandez S.A."}
  ],
  "limite": 2, "desplazamiento": 0, "total": 34
}
```

Un desplazamiento mayor que el total responde 200 con la lista vacía: `GET /vinos?tipo=rosado&desplazamiento=1000` devuelve `{"items": [], "limite": 20, "desplazamiento": 1000, "total": 70}`.

**Ficha (`GET /vinos/{cod_vino}`).** Composición y maridajes vienen estructurados, no como texto, para que el formulario de edición de la Etapa 7 los use directo. Los nombres de los campos son los del cuerpo de `POST /vinos`. `stock_total` es depósito más salas (`v_stock_total_vino`).

```json
GET /vinos/5
{
  "cod_vino": 5, "nombre": "Merlot Selección", "tipo": "tinto", "anada": 2021, "volumen_ml": 750,
  "graduacion": "14.50", "precio": "36340.00", "cuit_bodega": "30505499219", "bodega": "Bodega Fernandez S.A.",
  "stock_total": 2805,
  "composicion": [
    {"id_cepa": 3, "cepa": "Merlot", "tipo_cepa": "tinta", "porcentaje": "40.00"},
    {"id_cepa": 4, "cepa": "Syrah", "tipo_cepa": "tinta", "porcentaje": "40.00"},
    {"id_cepa": 2, "cepa": "Cabernet Sauvignon", "tipo_cepa": "tinta", "porcentaje": "20.00"}
  ],
  "maridajes": [
    {"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio_c": "17.0"},
    {"id_maridaje": 7, "nombre": "Entradas y fiambres", "temperatura_servicio_c": "10.0"}
  ]
}
```

- La composición va de mayor a menor porcentaje, y los maridajes por nombre: el mismo orden que `v_ficha_vino`.
- La ficha sale de **una sola sentencia**, con `json_agg` en subconsultas, así que es una sola foto de los datos. Con tres consultas sueltas en autocommit, un cambio de composición entre una y otra dejaría una ficha mezclada.
- No se usa `v_ficha_vino`, porque arma la composición y los maridajes como texto ("Malbec 85%, Cabernet 15%").

**Errores:**

- `GET /vinos/999999` → 404 `{"detail": "El vino 999999 no existe.", "codigo": "no_encontrado"}`.
- `GET /vinos?tipo=tinto' OR '1'='1` → 422 `{"detail": "Datos de entrada inválidos.", "codigo": "validacion", "errores": [{"campo": "query.tipo", "mensaje": "Input should be 'tinto', 'blanco', 'rosado' or 'espumante'"}]}`.

**Por qué el dinero va como string.** Los modelos usan `Decimal`, y Pydantic lo serializa como string. Así se conserva la escala exacta de `NUMERIC` (`"43660.00"`) y el valor no pasa nunca por un `float`, ni en Python ni en el `JSON.parse` del navegador.

- En OpenAPI figura como `string`.
- El front convierte con `Number()` sólo para mostrar.
- Los porcentajes y temperaturas de la ficha salen de un JSON de PostgreSQL. Se leen con `json.loads(parse_float=Decimal)` por el mismo motivo: por omisión, `json.loads` los convertiría en `float`.

**Rendimiento.** Medido con `EXPLAIN (ANALYZE, BUFFERS)` sobre la carga ESCALA=1 (600 vinos en 8 páginas de 8 kB, 867 filas de composición). Todas las consultas tardan menos de 1,3 ms. Ningún filtro usa índices de la Etapa 4, y no se agregan índices:

- sin filtro de bodega, el planificador recorre `pk_vino` en orden y corta en el `LIMIT`;
- `cuit_bodega` usa `uq_vino_identidad_comercial`, cuya primera columna es `cuit_bodega`;
- el `EXISTS` de `id_cepa` se resuelve con un hash de `composicion_vino`.

En el detalle, `v_stock_total_vino` recorre `stock_sala` entero (4.000 filas, 0,12 ms), porque la PK `(id_sala, cod_vino)` no sirve para buscar por vino. Con este tamaño, un índice no se justifica. Los tiempos están en el PR del issue #25.

#### ABM implementado (issue #26)

Código: `api/app/datos/vinos.py` (`insertar*`, `actualizar`, `reemplazar_*`, `borrar`), `api/app/routers/vinos.py` y `VinoEntrada` en `api/app/esquemas.py`. Pruebas: `api/tests/test_vinos_abm.py`.

**Cuerpo de `POST` y `PUT` (`VinoEntrada`).** Todos los campos son obligatorios, también `maridajes` (puede ser `[]`). En un `PUT`, un campo omitido no puede significar "borralo". Los decimales se aceptan como string (`"4500.00"`, como los devuelve la API) o como número JSON.

```json
{"nombre": "Malbec Cabernet Demo", "tipo": "tinto", "anada": 2024, "volumen_ml": 750,
 "graduacion": "13.50", "precio": "4500.00", "cuit_bodega": "30505499219",
 "composicion": [{"id_cepa": 1, "porcentaje": "60.00"}, {"id_cepa": 2, "porcentaje": "40.00"}],
 "maridajes": [1, 2]}
```

**Qué valida la API y qué valida la base.** Pydantic valida sólo la forma. Las reglas de negocio las rechaza PostgreSQL y llegan traducidas por `app/errores.py`:

| Valida Pydantic (422 `validacion`) | Rechaza PostgreSQL |
|---|---|
| Tipos y campos obligatorios | Composición que no suma 100 %: P0001 → 409 (constraint trigger diferido, RN-05) |
| `tipo` (los valores de `ck_vino_tipo`), `anada` 1900–9999, `cuit_bodega` de 11 dígitos, `nombre` de 1 a 100 caracteres | `precio` ≤ 0, `graduacion` fuera de 5–20, `volumen_ml` ≤ 0, `porcentaje` fuera de (0, 100]: 23514 → 422 |
| Escala de los NUMERIC: `precio` hasta 2 decimales, `graduacion` y `porcentaje` también | Bodega, cepa o maridaje inexistente: 23503 → 422 |
| Al menos una cepa; cepas y maridajes sin repetir | Vino repetido (misma bodega, nombre, añada y volumen): 23505 → 409 |

La escala se valida porque PostgreSQL redondearía en silencio `1000.005` a `1000.01` en `NUMERIC(14,2)`. Es la forma de la columna, no una regla de negocio.

**Alta (`POST /vinos`).** Responde 201 con la ficha, la misma de `GET /vinos/{cod_vino}`, y con `Location`.

- Las tres inserciones van en **una transacción** (`with conn.transaction():` en el endpoint). La composición y los maridajes se insertan con `unnest` de arrays: una sentencia por tabla, sin importar el largo de las listas.
- **La suma al 100 % se verifica en el `COMMIT`.** Los constraint triggers `ctrg_vino_composicion` y `ctrg_composicion_vino_suma` son `DEFERRABLE INITIALLY DEFERRED`: dentro de la transacción, la composición pasa por estados intermedios (el vino sin cepas, después 60 + 40), y la regla se evalúa recién al confirmar. Si falla, el `COMMIT` termina en `ROLLBACK` y no queda ni el vino ni sus maridajes. Las pruebas lo verifican con `count(*)`.
- La ficha se lee **después del COMMIT**, en la misma conexión: la respuesta muestra lo confirmado.
- `Location` es una ruta relativa con el prefijo público: `/vinos/668` directo y `/api/vinos/668` por nginx.
- `cod_vino` es `IDENTITY`. `bodegas_api` no tiene `USAGE` sobre `vino_cod_vino_seq` (`nextval()` da 42501) y no lo necesita, porque el valor por omisión de una columna `IDENTITY` no verifica ese privilegio. Lo prueba `test_alta_sin_usage_sobre_la_secuencia`.
- Los números de la secuencia no vuelven atrás con el `ROLLBACK`: un alta rechazada en el `COMMIT` deja un hueco en `cod_vino`. En el ejemplo de abajo, el alta con 90 % consumió el 669.

```json
POST /vinos  (el cuerpo de arriba)
201  Location: /api/vinos/668
{"cod_vino": 668, "nombre": "Malbec Cabernet Demo", "tipo": "tinto", "anada": 2024, "volumen_ml": 750,
 "graduacion": "13.50", "precio": "4500.00", "cuit_bodega": "30505499219", "bodega": "Bodega Fernandez S.A.",
 "stock_total": 0,
 "composicion": [{"id_cepa": 1, "cepa": "Malbec", "tipo_cepa": "tinta", "porcentaje": "60.00"},
                 {"id_cepa": 2, "cepa": "Cabernet Sauvignon", "tipo_cepa": "tinta", "porcentaje": "40.00"}],
 "maridajes": [{"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_servicio_c": "17.0"},
               {"id_maridaje": 2, "nombre": "Quesos duros", "temperatura_servicio_c": "16.0"}]}

POST /vinos con 60 % + 30 %
409  {"detail": "RN-05: la composición del vino 669 suma 90.00 %; debe sumar exactamente 100 %.", "codigo": "P0001"}

POST /vinos con "precio": "-100.00"
422  {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514", "restriccion": "ck_vino_precio_positivo"}

POST /vinos con "graduacion": "25.00"
422  {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514", "restriccion": "ck_vino_graduacion"}

POST /vinos repetido
409  {"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "uq_vino_identidad_comercial"}

POST /vinos con la cepa 1 dos veces
422  {"detail": "Datos de entrada inválidos.", "codigo": "validacion",
      "errores": [{"campo": "body.composicion", "mensaje": "Value error, una cepa aparece más de una vez en la composición"}]}
```

**Modificación (`PUT /vinos/{cod_vino}`): reemplazo completo.** Responde 200 con la ficha actualizada.

- En una transacción:
  1. `UPDATE vino … RETURNING cod_vino`; sin fila, 404;
  2. `DELETE` de la composición y los maridajes del vino;
  3. `INSERT` de los nuevos.
- La suma al 100 % se verifica al confirmar, sobre el estado final. Si la composición nueva no suma 100, el `ROLLBACK` deja **todo** como estaba: composición, maridajes, precio y su auditoría.
- El 404 sale del propio `UPDATE`, sin una consulta previa: no hay ventana entre "existe" y "actualizo". El `UPDATE` además bloquea la fila del vino hasta el `COMMIT`, así que dos `PUT` del mismo vino se aplican uno después del otro.
- **Auditoría de precio (RN-13).**
  - La escribe `trg_vino_auditoria_precio`, no la API. `bodegas_api` sólo tiene `SELECT` sobre `auditoria_precio`.
  - El `UPDATE` siempre incluye `precio`, pero el trigger tiene `WHEN (OLD.precio IS DISTINCT FROM NEW.precio)`: un precio igual al actual no deja fila. Tampoco la deja `"4950.0"` frente a `4950.00`, porque en `NUMERIC` son iguales.
  - **`usuario_bd` siempre es `bodegas_api`.** El trigger es `SECURITY DEFINER` y registra `session_user`, la cuenta que abrió la conexión. `current_user`, o el `DEFAULT CURRENT_USER` de la columna, dirían el propietario. La API se conecta siempre con la misma cuenta y no hay autenticación de usuarios finales, así que la base no puede saber qué persona hizo el cambio.

```json
PUT /vinos/668 con "precio": "4950.00"
200  {... "precio": "4950.00" ...}
SELECT precio_anterior, precio_nuevo, usuario_bd FROM auditoria_precio WHERE cod_vino = 668;
 4500.00 | 4950.00 | bodegas_api                  (una fila; repetir el PUT con "4950.0" no agrega otra)

PUT /vinos/668 con [{"id_cepa": 3, "porcentaje": "80.00"}]
409  {"detail": "RN-05: la composición del vino 668 suma 80.00 %; debe sumar exactamente 100 %.", "codigo": "P0001"}
     (composicion_vino conserva 60/40)

PUT /vinos/999999
404  {"detail": "El vino 999999 no existe.", "codigo": "no_encontrado"}
```

**Baja (`DELETE /vinos/{cod_vino}`).** Una sentencia, `DELETE … RETURNING`. Responde 204 sin cuerpo, o 404 si el vino no existe.

- `composicion_vino` y `vino_maridaje` caen por `ON DELETE CASCADE`. El trigger diferido de la composición ignora un vino borrado.
- **Un vino al que se le cambió el precio no se puede borrar**, como uno con ventas, ingresos, transferencias o stock: responde 409. Es una decisión de diseño (RN-14). `auditoria_precio` es historia, y su FK con `ON DELETE RESTRICT` impide perderla al borrar el maestro. Swagger lo dice en la descripción del endpoint.
- Para retirar del catálogo un vino con historia haría falta una baja lógica (por ejemplo, una columna `activo`), que hoy no está en el modelo.

```json
DELETE /vinos/668          (tiene un cambio de precio)
409  {"detail": "No se puede borrar ni modificar: hay datos que dependen de este registro.", "codigo": "23503", "restriccion": "fk_auditoria_precio_vino"}

DELETE /vinos/1            (tiene ventas)
409  {"detail": "No se puede borrar ni modificar: hay datos que dependen de este registro.", "codigo": "23503", "restriccion": "fk_renglon_comprobante_vino"}
```

**Sin autenticación.** Como todo el contrato de la consigna, las escrituras no piden credenciales. Antes de publicar la API en la nube (Etapa 8) habría que protegerlas, con una clave o restringiéndolas en nginx. Es una decisión de alcance pendiente.

### Clientes

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `GET /clientes` | Filtros `tipo` (`socio`, `distribuidor`, `exportador`) e `id_localidad`, más paginación | 200, `Pagina[ClienteResumen]` | 422 (`validacion`, filtro inválido) |
| `GET /clientes/{id_cliente}` | — | 200, `ClienteDetalle`: datos comunes, los de su subtipo, permisos si es exportador y `descuento` (`fn_descuento_cliente`) | 404 (`no_encontrado`) |
| `POST /clientes` | `ClienteEntrada`, según `tipo`: comunes `{nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo}`; `distribuidor` agrega `{zona_cobertura, nro_habilitacion}`; `exportador` agrega `{pais_destino_principal, permisos: [{codigo_permiso, fecha_emision, fecha_vencimiento}]}` | 201, `ClienteDetalle` y `Location: /clientes/{id_cliente}` | 409 (23505: `uq_cliente_documento`, `uq_distribuidor_habilitacion`, `pk_permiso_exportacion`); 422 (23514, `ck_permiso_exportacion_fechas`); 422 (23503, `fk_cliente_localidad`); 422 (`validacion`, por ejemplo un distribuidor sin `nro_habilitacion`) |
| `PUT /clientes/{id_cliente}` | `ClienteEntrada`: datos comunes y del subtipo, incluidos los permisos. `tipo` tiene que ser el del cliente | 200, `ClienteDetalle` | 404; **409 (23503)** si cambia el `tipo` (`fk_socio_club_cliente`, `fk_distribuidor_cliente` o `fk_exportador_cliente`); 409 (P0001, RN-06) si un exportador con la excepción del 35 % queda con tres permisos o menos; 409 y 422 como en el alta |
| `DELETE /clientes/{id_cliente}` | — | 204. El subtipo y los permisos se borran en cascada | 404; **409 (23503)** si tiene comprobantes (`fk_comprobante_cliente`) |

El alta inserta `cliente`, su fila de subtipo y los permisos en **una transacción**: la regla de totalidad de la jerarquía es diferida. El descuento no se envía: lo calcula `fn_descuento_cliente` (RN-06). Detalle en "CRUD implementado (issue #27)".

#### CRUD implementado (issue #27)

Código: `api/app/datos/clientes.py`, `api/app/routers/clientes.py` y los modelos de clientes en `api/app/esquemas.py`. Pruebas: `api/tests/test_clientes.py`.

**Supertipo más subtipos.**

- `cliente` guarda los datos comunes y el discriminador `tipo`. Cada subtipo tiene su tabla: `socio_club` no agrega columnas, `distribuidor` y `exportador` sí, y el exportador tiene además sus `permiso_exportacion`.
- **Exclusividad: FK compuesta.** Cada fila de subtipo lleva un `tipo` constante, con DEFAULT y CHECK (`ck_distribuidor_tipo`, …), y referencia `cliente (id_cliente, tipo)`. Un cliente sólo puede tener la fila del subtipo que declara. Si un socio recibe una fila en `distribuidor`, la base responde 23503 `fk_distribuidor_cliente`; lo prueba el escenario `subtipo_ajeno`.
- **Totalidad: constraint trigger diferido.** Una FK no puede exigir que exista el hijo. `ctrg_cliente_subtipo` y los `ctrg_*_total` verifican en el `COMMIT` que todo cliente tenga la fila de su tipo: P0001 "Jerarquía de clientes: el cliente N es de tipo X y no tiene su fila de subtipo." Es diferido porque dentro de la transacción el cliente existe un momento sin su subtipo. Lo prueba el escenario `diferido`.

**Cuerpo de `POST` y `PUT`: una unión discriminada por `tipo`** (`ClienteEntrada`). Todos los tipos llevan los datos comunes: `nombre_razon_social`, `tipo_documento`, `nro_documento`, `direccion` e `id_localidad`. Según el tipo:

| `tipo` | Campos propios, todos obligatorios |
|---|---|
| `socio` | — |
| `distribuidor` | `zona_cobertura`, `nro_habilitacion` |
| `exportador` | `pais_destino_principal`, `permisos: [{codigo_permiso, fecha_emision, fecha_vencimiento}]` (puede ser `[]`) |

```json
{"tipo": "exportador", "nombre_razon_social": "Vinos del Sur Export S.A.", "tipo_documento": "CUIT",
 "nro_documento": "30712345678", "direccion": "Av. San Martín 1234", "id_localidad": 21,
 "pais_destino_principal": "Brasil",
 "permisos": [{"codigo_permiso": "PE-DEMO-1", "fecha_emision": "2025-03-01", "fecha_vencimiento": "2027-03-01"},
              {"codigo_permiso": "PE-DEMO-2", "fecha_emision": "2025-06-01", "fecha_vencimiento": "2026-06-01"}]}
```

En Swagger el cuerpo aparece como `oneOf` con `discriminator: tipo`, un esquema por tipo.

**Qué valida la API y qué valida la base.**

| Valida Pydantic (422 `validacion`) | Rechaza PostgreSQL |
|---|---|
| `tipo` existente; los campos obligatorios de ese tipo (un distribuidor sin `nro_habilitacion` responde `body.distribuidor.nro_habilitacion`) | Documento repetido: 23505 `uq_cliente_documento` → 409 |
| Largo de cada `VARCHAR`; fechas con formato válido | Habilitación repetida: 23505 `uq_distribuidor_habilitacion` → 409 |
| Códigos de permiso sin repetir dentro del cuerpo | Código de permiso ya usado (es una PK global): 23505 `pk_permiso_exportacion` → 409 |
| | Permiso que vence antes de emitirse: 23514 `ck_permiso_exportacion_fechas` → 422 |
| | Localidad inexistente: 23503 `fk_cliente_localidad` → 422 |

**El descuento no viaja en el cuerpo.**

- Lo calcula `fn_descuento_cliente` (RN-06): la excepción del 35 % si el cliente la tiene, o 10, 20 o 30 según el tipo. La ficha lo muestra en `descuento`.
- Si el cuerpo trae `descuento` o `descuento_excepcion`, se ignoran, como cualquier campo que no es del modelo. La API nunca escribe esa columna.
- Si el descuento viajara en el cuerpo, cualquiera podría elegirse el suyo, y la base tendría dos fuentes de verdad para el mismo dato. La excepción del 35 % la asigna U6, y `trg_cliente_excepcion` exige más de tres permisos.
- `fecha_alta` tampoco se envía: la pone el `DEFAULT CURRENT_DATE` y el PUT no la cambia.

**Alta (`POST /clientes`).** Responde 201 con la ficha y `Location`.

- En una transacción:
  1. `INSERT` en `cliente`;
  2. `INSERT` de la fila del subtipo, sin `tipo`: lo pone su DEFAULT y la FK compuesta comprueba que coincida;
  3. permisos con `unnest` de arrays, como la composición de un vino.
- **Un alta fallida no deja el cliente sin su subtipo.** El cliente se inserta primero: si después falla el subtipo o un permiso, el ROLLBACK se lo lleva. Las pruebas lo verifican con `count(*)` en cuatro casos: habilitación repetida, permiso que vence antes, permiso de otro exportador y localidad inexistente.
- `id_cliente` es `IDENTITY`: `bodegas_api` no tiene `USAGE` sobre su secuencia y no lo necesita, como en vinos.

**Modificación (`PUT /clientes/{id_cliente}`).** Reemplaza los datos comunes y los del subtipo en una transacción. Los permisos de un exportador se reemplazan enteros: `DELETE` de los suyos e `INSERT` de los del cuerpo. El 404 sale del `UPDATE … RETURNING`. Lo que devuelve el GET se puede reenviar, porque `id_cliente`, `localidad`, `fecha_alta` y `descuento` se ignoran.

- **El `tipo` no se cambia, y lo impide la base.** `tipo` va en el `SET` del `UPDATE`.
  - Con el mismo valor, PostgreSQL no revisa las FK.
  - Si cambia, la FK compuesta del subtipo actual (`ON UPDATE RESTRICT`) rechaza el `UPDATE` con 23503 y responde 409. Por ejemplo, un exportador enviado como socio da `fk_exportador_cliente`.
  - Cambiar de tipo exigiría borrar el subtipo viejo e insertar el nuevo en una transacción. La totalidad diferida lo permite, pero el issue lo deja fuera.
- **Permisos y excepción (RN-06).** Si el exportador tiene la excepción del 35 % y el PUT lo deja con tres permisos o menos, `ctrg_permiso_excepcion` (diferido) rechaza el `COMMIT`: 409 "RN-06: el exportador N conserva la excepción del 35 % con sólo 2 permiso(s).", y los permisos quedan como estaban.

**Baja (`DELETE /clientes/{id_cliente}`).** Una sentencia, `DELETE … RETURNING`. Responde 204, o 404 si el cliente no existe.

- La fila del subtipo y los permisos caen por `ON DELETE CASCADE`. Los triggers diferidos ignoran un cliente borrado.
- **Un cliente con compras no se puede borrar:** `fk_comprobante_cliente` (`ON DELETE RESTRICT`) responde 409. Los comprobantes son historia.

Respuestas reales por `/api/...` (proyecto aislado con la carga `ESCALA=0.1`):

```json
POST /clientes  (el cuerpo de arriba)
201  Location: /api/clientes/2005
{"id_cliente": 2005, "localidad": "General Alvear", "fecha_alta": "2026-11-08", "descuento": "30.00",
 "nombre_razon_social": "Vinos del Sur Export S.A.", "tipo_documento": "CUIT", "nro_documento": "30712345678",
 "direccion": "Av. San Martín 1234", "id_localidad": 21, "tipo": "exportador", "pais_destino_principal": "Brasil",
 "permisos": [{"codigo_permiso": "PE-DEMO-1", "fecha_emision": "2025-03-01", "fecha_vencimiento": "2027-03-01"},
              {"codigo_permiso": "PE-DEMO-2", "fecha_emision": "2025-06-01", "fecha_vencimiento": "2026-06-01"}]}

POST /clientes distribuidor sin nro_habilitacion
422  {"detail": "Datos de entrada inválidos.", "codigo": "validacion",
      "errores": [{"campo": "body.distribuidor.nro_habilitacion", "mensaje": "Field required"}]}

POST /clientes distribuidor con una habilitación existente   (después: 0 clientes con ese documento)
409  {"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "uq_distribuidor_habilitacion"}

POST /clientes exportador con un permiso que vence antes de emitirse
422  {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514", "restriccion": "ck_permiso_exportacion_fechas"}

POST /clientes con un documento repetido
409  {"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "uq_cliente_documento"}

PUT /clientes/2005 con "tipo": "socio"
409  {"detail": "No se puede borrar ni modificar: hay datos que dependen de este registro.", "codigo": "23503", "restriccion": "fk_exportador_cliente"}

DELETE /clientes/1          (tiene compras)
409  {"detail": "No se puede borrar ni modificar: hay datos que dependen de este registro.", "codigo": "23503", "restriccion": "fk_comprobante_cliente"}

DELETE /clientes/2005
204  (sin permisos ni fila de exportador)
```

El mensaje genérico del 409 por cambio de tipo es el de toda FK con dependientes (sección 3). La `restriccion` dice cuál fue: el subtipo actual del cliente.

### Comprobantes

| Método y ruta | Cuerpo / parámetros | Respuesta | Errores esperados |
|---|---|---|---|
| `POST /comprobantes` | `{id_cliente, id_sala, renglones: [{cod_vino, cantidad}]}` | 201 con `Location`: `{nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total, renglones: [{cod_vino, nombre_vino, cantidad, precio_unitario, descuento_porcentaje, total_parcial}]}`, leídos de la base en la misma transacción de la venta | **409 (P0001)**: "RN-09: stock insuficiente…", vino repetido, cantidad no positiva, venta sin renglones. 422 (23503): cliente o sala inexistente (`fk_comprobante_cliente`, `fk_comprobante_sala_venta`). 422 (`dato_invalido`): vino inexistente, "No existen los vinos: 999999." (ver la nota) |
| `GET /comprobantes/{nro}` | — | 200, cabecera con los importes guardados y renglones | 404 (`no_encontrado`) |

La venta es una sola llamada a `fn_registrar_venta(id_cliente, id_sala, vinos[], cantidades[])`, que crea cabecera y renglones en la misma transacción: todo o nada. La API no tiene `INSERT` sobre `comprobante` (sección 4).

Nota: con un `cod_vino` inexistente la base responde `23502: null value in column "precio_unitario"`, porque el trigger no encuentra el precio antes de que actúe la FK. **Decisión (issue #28):** la API consulta en una sola sentencia qué vinos pedidos no existen, dentro de la misma transacción de la venta, y responde 422 con sus códigos. Se descartó una migración `009`: el mensaje mejora sin tocar la base. Las demás reglas (venta vacía, cantidad no positiva, vino repetido, stock) no se validan en la API: las decide `fn_registrar_venta` y llegan como P0001 con el mensaje de la regla.

### Transferencias e ingresos

| Método y ruta | Cuerpo | Respuesta | Errores esperados |
|---|---|---|---|
| `POST /transferencias` | `{id_sala}` | 201, `TransferenciaDetalle` en `en_confeccion`, sin renglones, y `Location: /transferencias/{nro}` | 422 (23503, `fk_transferencia_sala_venta`); 422 (`validacion`) |
| `GET /transferencias/{nro}` | — | 200, `TransferenciaDetalle`: `{nro_transferencia, id_sala, fecha_confeccion, estado, renglones: [{cod_vino, nombre_vino, cantidad}]}` | 404 (`no_encontrado`) |
| `POST /transferencias/{nro}/renglones` | `{cod_vino, cantidad}` | 201, `TransferenciaDetalle` con el renglón nuevo, y `Location` | 404; 409 (P0001, la transferencia ya no está en confección, RN-12); 409 (23505, `pk_renglon_transferencia`, vino repetido); 422 (23514, cantidad no positiva); 422 (23503, vino inexistente) |
| `POST /transferencias/{nro}/terminar` | — | 200, `TransferenciaDetalle` en `terminado` (`CALL sp_terminar_transferencia`) | 404 (P0002); 409 (P0001, transición inválida o sin renglones, RN-11) |
| `POST /transferencias/{nro}/procesar` | — | 200, `TransferenciaDetalle` en `procesado` (`CALL sp_procesar_transferencia`) | 404 (P0002); 409 (P0001: no está terminada, ya fue procesada o falta stock en el depósito; no deja cambios) |
| `POST /ingresos` | `{cod_transportista, cuit_bodega}` | 201: `{cod_ingreso, estado: "en_confeccion"}` | 422 (23503) |
| `POST /ingresos/{cod}/renglones` | `{cod_vino, cantidad}` | 201 | igual que en transferencias (RN-10, RN-12) |
| `POST /ingresos/{cod}/terminar` | — | 200 (`CALL sp_terminar_ingreso`) | **No figura en la consigna**: ver la sección 6 |
| `POST /ingresos/{cod}/procesar` | — | 200 (`CALL sp_procesar_ingreso`) | 404; 409 (P0001, transición inválida, RN-10) |

#### Circuito de transferencias implementado (issue #29)

Código: `api/app/datos/documentos.py` (SQL), `api/app/routers/transferencias.py` (rutas) y los modelos de transferencias en `api/app/esquemas.py`. Pruebas: `api/tests/test_transferencias.py`.

**`documentos.py`, compartido con ingresos (#30).** Cada documento tiene sus constantes SQL y una función por operación, con el nombre del documento en el nombre (`crear_transferencia`, `procesar_transferencia`, …). Ingresos agrega las suyas al lado con el mismo formato. Se descartó un módulo genérico que arme el SQL con nombres de tabla variables (`psycopg.sql.Identifier`): ahorra repetición, pero el SQL deja de leerse completo en el código.

**Qué hace la API y qué hace la base.** La API crea la cabecera, agrega renglones e invoca los dos procedimientos. Cada operación es **una sola sentencia**, atómica en autocommit, y la transferencia se lee después de confirmarla. Todo lo demás lo decide PostgreSQL:

| Regla | Mecanismo en la base | Respuesta |
|---|---|---|
| RN-11: nace en confección con la fecha actual | `DEFAULT 'en_confeccion'`, `trg_transferencia_fecha` (fuerza `CURRENT_DATE`) y el `INSERT` sólo sobre `id_sala` | `estado` y `fecha_confeccion` enviados en el cuerpo se ignoran |
| RN-11: `en_confeccion → terminado → procesado`, sin saltos ni retrocesos; terminar exige renglones | `trg_transferencia_estado` (`fn_validar_transicion_estado`); `procesado` sólo desde `sp_procesar_transferencia` | 409 (P0001) |
| RN-12: los renglones se editan sólo en confección | `trg_renglon_transferencia_bloqueo` (bloquea la cabecera `FOR SHARE`) | 409 (P0001) |
| Cantidad positiva, un renglón por vino, vino existente | `ck_renglon_transferencia_cantidad_positiva`, `pk_renglon_transferencia`, `fk_renglon_transferencia_vino` | 422 (23514), 409 (23505), 422 (23503) |
| RN-11: procesar mueve el stock, todo o nada | `sp_procesar_transferencia` (`SECURITY DEFINER`); la API no tiene `UPDATE` sobre stock ni estados | 409 (P0001) si falta stock, sin cambios |

- **Las respuestas devuelven la transferencia completa**, incluidos el alta y el renglón nuevo. El front de la Etapa 7 redibuja la pantalla con una sola respuesta y habilita los botones según `estado`.
- **404 de un renglón sin consulta previa.** El renglón se inserta con `INSERT … SELECT … FROM transferencia WHERE nro_transferencia = %(nro)s RETURNING …`. Si la transferencia no existe, no se inserta nada y `RETURNING` no devuelve fila: 404, como el `UPDATE … RETURNING` de `PUT /vinos`. Sin esto, el trigger RN-12 dejaría pasar el renglón (no encuentra cabecera y supone un borrado en cascada) y la FK respondería 23503, que es 422. No hay ventana entre "existe" y "agrego": la API no puede borrar transferencias. Un `SELECT … FOR SHARE` previo tampoco serviría, porque exige `UPDATE` sobre la tabla.
- **Terminar una transferencia ya terminada responde 200 sin cambios.** `fn_validar_transicion_estado` acepta un estado igual al anterior: no es una transición. Una procesada no vuelve a terminado (409).
- **404 con dos `codigo`.** `GET` y renglones responden `no_encontrado` (lo decide el endpoint); terminar y procesar, `P0002` (lo decide el procedimiento). El `detail` es el mismo: "La transferencia N no existe.".
- **Sin stock, el `detail` no lista los vinos faltantes.** El procedimiento los informa en el DETAIL ("vino 600: pide 164, hay 163"), y `errores.py` nunca envía el DETAIL de PostgreSQL (sección 3).
- **La fecha es la del servidor de base, que está en UTC.** Una transferencia creada después de las 21 h de Argentina queda con la fecha del día siguiente. Pasa lo mismo con todas las fechas de la base (`fecha_alta` de clientes, `fecha` de comprobantes); corregirlo es fijar la zona horaria de la base, una decisión pendiente que no es de este issue.

**Concurrencia: `FOR UPDATE` y orden de bloqueo.** `sp_procesar_transferencia`:

1. bloquea la cabecera con `SELECT … FOR UPDATE` y exige `terminado`. Dos procesos de la misma transferencia se serializan: el segundo espera, ve `procesado` y responde 409, sin mover stock otra vez;
2. bloquea las filas de `stock_deposito` de sus vinos **en orden de `cod_vino`**. Dos transferencias con vinos en común piden los bloqueos en el mismo orden y no se bloquean en cruz (deadlock);
3. verifica el stock de cada renglón, incluidos los vinos sin fila en el depósito, y recién entonces descuenta, suma a la sala y cambia el estado.

`test_procesar_concurrente_espera_y_no_mueve_dos_veces` lo prueba por la API: otra sesión procesa la transferencia sin confirmar; el `POST /procesar` queda esperando el bloqueo (visible en `pg_stat_activity` con `wait_event_type = 'Lock'`); al confirmar, la API responde 409 y las botellas se movieron una sola vez. La demostración con dos sesiones de `psql` está en `docs/concurrencia.md`.

Respuestas reales por `/api/...` (proyecto aislado con la carga `ESCALA=0.1`):

```json
POST /transferencias  {"id_sala": 1, "estado": "procesado", "fecha_confeccion": "2000-01-01"}
201  Location: /api/transferencias/4484
{"nro_transferencia": 4484, "id_sala": 1, "fecha_confeccion": "2026-11-09", "estado": "en_confeccion", "renglones": []}

POST /transferencias/4485/terminar          (sin renglones)
409  {"detail": "RN-11: no se puede terminar la transferencia 4485 sin renglones.", "codigo": "P0001"}

POST /transferencias/4485/renglones  {"cod_vino": 1, "cantidad": 12}
201  Location: /api/transferencias/4485
{"nro_transferencia": 4485, "id_sala": 1, "fecha_confeccion": "2026-11-09", "estado": "en_confeccion",
 "renglones": [{"cod_vino": 1, "nombre_vino": "Malbec Clásico", "cantidad": 12}]}

POST /transferencias/4485/renglones  {"cod_vino": 1, "cantidad": 1}
409  {"detail": "Ya existe un registro con esos datos.", "codigo": "23505", "restriccion": "pk_renglon_transferencia"}

POST /transferencias/4485/renglones  {"cod_vino": 1, "cantidad": 0}
422  {"detail": "Un valor no cumple una regla de validación.", "codigo": "23514", "restriccion": "ck_renglon_transferencia_cantidad_positiva"}

POST /transferencias/4485/procesar          (en confección)
409  {"detail": "RN-11: la transferencia 4485 está en_confeccion; sólo una transferencia terminada impacta en el stock.", "codigo": "P0001"}

POST /transferencias/4485/terminar
200  {... "estado": "terminado" ...}

POST /transferencias/4485/renglones  {"cod_vino": 1, "cantidad": 1}
409  {"detail": "RN-12: la transferencia 4485 está terminado; no admite cambios en sus renglones.", "codigo": "P0001"}

POST /transferencias/4485/procesar
200  {... "estado": "procesado" ...}     (depósito −12 y sala 1 +12 del vino 1)

POST /transferencias/4485/procesar
409  {"detail": "RN-11: la transferencia 4485 está procesado; sólo una transferencia terminada impacta en el stock.", "codigo": "P0001"}

POST /transferencias/4487/procesar          (pide 164 botellas del vino 600; el depósito tiene 163)
409  {"detail": "RN-11: el depósito no tiene stock suficiente para la transferencia 4487.", "codigo": "P0001"}
     (después: el depósito sigue con 163 y la transferencia sigue terminada)

POST /transferencias/999999999/procesar
404  {"detail": "La transferencia 999999999 no existe.", "codigo": "P0002"}

POST /transferencias  {"id_sala": 99999}
422  {"detail": "El dato relacionado no existe.", "codigo": "23503", "restriccion": "fk_transferencia_sala_venta"}
```

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
| `POST /vinos` (vino, composición y maridaje; diferidos verificados) | OK. Sin `USAGE` sobre `vino_cod_vino_seq` (`nextval()` da 42501): el `INSERT` en la columna `IDENTITY` no lo necesita (verificado de nuevo en el #26) |
| `PUT /vinos/{cod}` (precio) | OK; `auditoria_precio` recibe 1 fila por el trigger |
| `DELETE /vinos/{cod}` | OK sin dependientes. 23503 con historia de precios (`fk_auditoria_precio_vino`) o con ventas (`fk_renglon_comprobante_vino`) |
| `GET /clientes` (con localidad), `POST` de los tres tipos con permiso de exportación, `PUT`, `DELETE` | OK; 23503 al borrar un cliente con ventas. Sin `USAGE` sobre la secuencia de `cliente`: el `INSERT` en la columna `IDENTITY` no lo necesita (verificado en el #27). Cambiar `tipo` en el `UPDATE` da 23503 por la FK compuesta del subtipo |
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
- **Inyección SQL.** La demostración de inyección fallida se hace sobre un filtro de `GET /vinos`: el valor viaja como parámetro y se compara como texto. Para el issue #34 hay una segunda en una escritura: `test_texto_con_caracteres_especiales_se_guarda_tal_cual` da de alta un vino llamado `Malbec '; DROP TABLE vino; -- …`. El nombre se guarda tal cual y la tabla sigue existiendo.

## 6. Preguntas abiertas para la cátedra

1. **`/reportes/trazabilidad/{cod}`.** El modelo no vincula un vino con lotes de uva concretos. `lote_uva` registra a qué bodega se entregó cada cosecha, y `vino` tiene bodega, añada y corte (cepas). La interpretación posible, que se probó como SQL salvo por el permiso, es esta: lotes de las cepas del corte, cosechados en la añada del vino y entregados a su bodega, con finca, parcela y análisis de calidad. Es una aproximación, no una trazabilidad exacta. ¿Alcanza, o se espera otro alcance (por ejemplo, sólo el corte y la bodega)?
2. **`POST /ingresos/{cod}/terminar`.** La consigna lista sólo `procesar` para ingresos, "mismo circuito que las transferencias". Pero RN-10 exige pasar por `terminado`, y `sp_terminar_ingreso` existe. ¿Se agrega el endpoint, o `procesar` debe terminar y procesar en un paso?
3. **S12 B.** ¿"Clientes que nunca compraron tintos" incluye a los que no compraron nada? Hoy sí: son 4.715 de 7.170.
