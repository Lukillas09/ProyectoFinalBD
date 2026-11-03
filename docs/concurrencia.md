# Concurrencia: la última botella

Guion reproducible para la demostración de la Etapa 2 (consigna, paso 8, y Anexo A.8): dos sesiones `psql` intentan vender la última botella de un vino en la misma sala.

> **Transacciones como tema no visto.** La aclaración docente declaró opcionales los temas no vistos y mencionó las transacciones como ejemplo (ver `docs/requisitos.md`, sección 4). Igual se implementan y se demuestran, porque la rúbrica las puntúa (Funciones, procedimientos, triggers y transacciones: 17 puntos) y porque RN-09 y la transferencia "sin cambios a medias" dependen de ellas.

Los resultados que figuran abajo son transcripciones autenticas de ejecuciones reales contra PostgreSQL 16. Cada bloque muestra la consulta SQL ejecutada (con `\set PROMPT1 'A> '` o `'B> '`) seguida del resultado que devuelve `psql`. Las horas cambian en cada ejecucion; el orden de los eventos y los errores, no.

> **Nota sobre las capturas:** no se incluyen imagenes PNG reconstruidas. Cada escenario tiene su transcripcion completa de terminal A y terminal B. Para generar las capturas solicitadas por la catedra, seguir la seccion "Capturas de terminal (manual)" al final de este documento.

## 1. Conceptos que se usan

- **Transacción:** `BEGIN … COMMIT` aplica todo o nada. `ROLLBACK`, o un error sin capturar, deshace todo lo hecho desde el `BEGIN`.
- **Nivel de aislamiento `READ COMMITTED`** (el valor por omisión de PostgreSQL y el que usan la API y estos guiones salvo el escenario 5):
  - cada sentencia ve los datos confirmados al momento de empezar *esa sentencia*;
  - si un `UPDATE` encuentra una fila bloqueada por otra transacción, espera. Cuando la otra confirma, vuelve a leer la versión nueva de la fila y aplica su cambio sobre ella.
- **`SELECT … FOR UPDATE`:** lee y bloquea las filas. Otra transacción que quiera bloquearlas o modificarlas espera hasta el `COMMIT` o `ROLLBACK` de la primera, y después ve el valor confirmado.
- **`REPEATABLE READ`:** toda la transacción ve una única foto tomada en su primera consulta. Si intenta modificar una fila que otra transacción cambió y confirmó después de esa foto, PostgreSQL la cancela con `40001 could not serialize access due to concurrent update`. La aplicación debe reintentar la transacción completa.

## 2. Preparación

Con el entorno levantado (`docker compose up -d`), abrir **dos terminales** en la raíz del repositorio.

Terminal A y terminal B, como propietario:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB"'
```

En cada `psql`, identificar la sesión para que se distinga en las capturas:

```sql
\set PROMPT1 'A> '   -- en la terminal A
\set PROMPT1 'B> '   -- en la terminal B
```

En la terminal A, cargar los datos de la demostración: una sala con **una** botella del vino 990001 y diez del vino 990002, que se usa en el escenario 4b.

```sql
BEGIN;
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
OVERRIDING SYSTEM VALUE VALUES (990001, '5600-C', 'Localidad concurrencia', 'Mendoza', 'Encargado C');
INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Calle concurrencia', '1', 'lunes', 990001);
INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30990000001', 'Bodega concurrencia', 'Dom');
INSERT INTO cepa (id_cepa, nombre, tipo) OVERRIDING SYSTEM VALUE VALUES (990001, 'Malbec concurrencia', 'tinta');
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Última botella', 'tinto', 2021, 750, 14.00, 12500.00, '30990000001'),
                               (990002, 'Segundo vino', 'tinto', 2021, 750, 14.00, 9000.00, '30990000001');
INSERT INTO composicion_vino VALUES (990001, 990001, 100.00), (990002, 990001, 100.00);
INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Cliente A', 'DNI', '99000001', 'Dir', 990001, 'socio'),
                               (990002, 'Cliente B', 'DNI', '99000002', 'Dir', 990001, 'socio');
INSERT INTO socio_club VALUES (990001), (990002);
INSERT INTO stock_sala VALUES (990001, 990001, 1), (990001, 990002, 10);
COMMIT;
```

Antes de **cada** escenario, reponer la botella (terminal A):

```sql
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 990001 AND cod_vino = 990001;
```

Los escenarios 1 a 3 y 5 modifican `stock_sala` directamente para mostrar el mecanismo; por eso se ejecutan como propietario. La API no puede hacerlo: no tiene `UPDATE` sobre el stock. El escenario 4 usa el camino real de la API.

En cada paso, ejecutar la sentencia en la terminal indicada **y esperar** a que termine antes de pasar a la siguiente, salvo cuando el guion dice que queda esperando.

## 3. Escenario 1: sin bloqueo, la aplicación calcula el stock

Así trabajaría una aplicación que lee el stock, resta en su propio código y escribe el resultado.

| Paso | Terminal A | Terminal B |
|---:|---|---|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;` → **1** | |
| 4 | | La misma consulta → **1** |
| 5 | `UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 990001 AND cod_vino = 990001;` (1 − 1 calculado por la app) | |
| 6 | `COMMIT;` | |
| 7 | | `UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 990001 AND cod_vino = 990001;` |
| 8 | | `COMMIT;` |
| 9 | `SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;` → **0** | |

**Resultado observado:** ambas sesiones confirman su venta y el stock queda en 0. Se vendieron **dos** botellas habiendo **una**, y nadie recibió un error: es una **actualización perdida**.

Transcripción auténtica (sesiones A y B como propietario):

```
--- SALIDA SESION A ---
A> BEGIN;
BEGIN
A> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

A> SELECT pg_sleep(2);
 pg_sleep
----------

(1 row)

A> UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 990001 AND cod_vino = 990001;
UPDATE 1
A> COMMIT;
COMMIT
A> SELECT cantidad AS stock_final_desde_A FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 stock_final_desde_a
---------------------
                   0
(1 row)

--- SALIDA SESION B ---
B> BEGIN;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

B> SELECT pg_sleep(2);
 pg_sleep
----------

(1 row)

B> UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 990001 AND cod_vino = 990001;
UPDATE 1
B> COMMIT;
COMMIT
```

**Por qué el `CHECK (cantidad >= 0)` no alcanza:** el `CHECK` sólo valida el valor que se escribe, y 0 es válido. El problema no es un número negativo sino que B decidió con un dato viejo (leyó 1 antes de que A confirmara) y sobrescribió el resultado de A con un valor absoluto calculado afuera. Por eso el stock debe descontarse en la base, sobre la fila bloqueada.

**Captura de terminal requerida:** tomar una foto de la terminal A mostrando su `SELECT` → 1, `UPDATE` → `UPDATE 1`, `COMMIT`, y `SELECT final` → 0. Tomar una foto de la terminal B mostrando su `SELECT` → 1, `UPDATE` → `UPDATE 1`, `COMMIT`. Ambas terminales lado a lado evidencian la actualización perdida.

**Evidencia del escenario 1:**

[Escenario 1 - Actualización perdida sin FOR UPDATE](img/concurrencia/01_escenario1_sin_for_update_perdida_actualizacion.png)

## 4. Escenario 2: sin `FOR UPDATE`, descuento relativo

Reponer la botella. Ahora el `UPDATE` resta sobre el valor de la fila (`cantidad - 1`), pero nadie bloquea al leer.

| Paso | Terminal A | Terminal B |
|---:|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT cantidad … ;` → **1** | `SELECT cantidad … ;` → **1** (B también cree que hay stock) |
| 3 | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;` | |
| 4 | | El mismo `UPDATE`: **queda esperando** (A tiene la fila bloqueada) |
| 5 | `COMMIT;` | |
| 6 | | Se destraba y falla:<br>`ERROR: new row for relation "stock_sala" violates check constraint "ck_stock_sala_cantidad_no_negativa"`<br>`DETAIL: Failing row contains (990001, 990001, -1).` |
| 7 | | `ROLLBACK;` |

**Resultado observado:** el `CHECK` evitó el stock negativo: en `READ COMMITTED`, el `UPDATE` de B esperó, releyó la fila confirmada (0) y calculó −1. Pero:

- B ya había leído 1 y la aplicación pudo haber mostrado "hay stock" o registrado otros datos de la venta;
- el error es una violación genérica de constraint, no un mensaje de negocio;
- en el escenario 1 (valor absoluto) el mismo `CHECK` no detecta nada.

Transcripción auténtica (sesiones A y B como propietario):

```
--- SALIDA SESION A ---
A> BEGIN;
BEGIN
A> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

A> SELECT pg_sleep(2);
 pg_sleep
----------

(1 row)

A> UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;
UPDATE 1
A> COMMIT;
COMMIT

--- SALIDA SESION B ---
B> BEGIN;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

B> SELECT pg_sleep(2);
 pg_sleep
----------

(1 row)

B> UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;
psql:/tmp/s2_b.sql:6: ERROR:  new row for relation "stock_sala" violates check constraint "ck_stock_sala_cantidad_no_negativa"
DETAIL:  Failing row contains (990001, 990001, -1).
```

El `CHECK` protege el invariante "nunca negativo", no la decisión "hay stock para vender".

**Captura de terminal requerida:** tomar una foto de la terminal B mostrando el `ERROR` de check constraint con `DETAIL: Failing row contains (990001, 990001, -1)`. La terminal A debe mostrar su `UPDATE` → `UPDATE 1` y `COMMIT` exitosos.
[Escenario 1 - Actualización perdida sin FOR UPDATE](img/concurrencia/02_escenario2_sin_for_update_descuento_relativo.png)

## 5. Escenario 3: con `SELECT … FOR UPDATE` (Anexo A.8)

Reponer la botella.

| Paso | Terminal A | Terminal B |
|---:|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001 FOR UPDATE;` → **1** | |
| 3 | | La misma consulta con `FOR UPDATE`: **queda esperando** |
| 4 | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;` | |
| 5 | `COMMIT;` | |
| 6 | | Recién ahora obtiene el resultado: **0**. La venta se rechaza. |
| 7 | | `ROLLBACK;` |

**Resultado observado:** B esperó hasta el `COMMIT` de A y leyó 0. La lectura bloqueante hace que la decisión de B se tome con el dato ya confirmado.

Transcripción auténtica (sesiones A y B como propietario):

```
--- SALIDA SESION A ---
A> BEGIN;
BEGIN
A> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001 FOR UPDATE;
 cantidad
----------
        1
(1 row)

A> SELECT pg_sleep(3);
 pg_sleep
----------

(1 row)

A> UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;
UPDATE 1
A> COMMIT;
COMMIT

--- SALIDA SESION B ---
B> BEGIN;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001 FOR UPDATE;
 cantidad
----------
        0
(1 row)

B> ROLLBACK;
ROLLBACK
```

**Captura de terminal requerida:** tomar una foto de la terminal B mostrando que su `SELECT ... FOR UPDATE` queda esperando (no devuelve resultado inmediatamente) y después del `COMMIT` de A devuelve `cantidad = 0`. La terminal A debe mostrar su `SELECT ... FOR UPDATE` → 1, `UPDATE` → `UPDATE 1`, `COMMIT`.
![Captura escenario3](03_escenario3_con_for_update_bloqueo_fila.png)

## 6. Escenario 4: la venta real (`fn_registrar_venta` y trigger RN-09)

En el sistema, la aplicación no lee ni descuenta el stock. Llama a `fn_registrar_venta` (`db/migrations/004_procedimientos.sql`), que crea la cabecera y los renglones en una sola llamada; la API no tiene `INSERT` directo sobre ventas. Los triggers hacen el resto:

- `trg_renglon_comprobante_completar` (`005_triggers.sql`) bloquea la fila de `stock_sala` con `FOR UPDATE` y rechaza si no alcanza;
- `trg_renglon_comprobante_impactar` descuenta el stock.

Reponer la botella. Abrir las dos terminales **con la cuenta de la API**:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -h 127.0.0.1 -U "$DB_APP_USER" -d "$POSTGRES_DB"'
```

| Paso | Terminal A (API) | Terminal B (API) |
|---:|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT fn_registrar_venta(990001, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]);` → devuelve el número de comprobante | |
| 3 | | `SELECT fn_registrar_venta(990002, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]);` → **queda esperando** |
| 4 | `COMMIT;` | |
| 5 | | `ERROR: RN-09: stock insuficiente del vino 990001 en la sala 990001.`<br>`DETAIL: Se piden 1 botellas y la sala tiene 0.`<br>`HINT: Solicite una transferencia desde el depósito central.` |
| 6 | | `ROLLBACK;` |

**Resultado observado:** B esperó hasta el `COMMIT` de A y recibió el mensaje de negocio RN-09. No quedó ningún comprobante de B: la función es todo o nada y la transacción abortada descartó también su cabecera. Stock final: 0.

Transcripción auténtica (sesiones A y B como cuenta de la API):

```
--- SALIDA SESION A ---
A> BEGIN;
BEGIN
A> SELECT fn_registrar_venta(990001, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]);
 fn_registrar_venta
--------------------
                 21
(1 row)

A> SELECT pg_sleep(3);
 pg_sleep
----------

(1 row)

A> COMMIT;
COMMIT

--- SALIDA SESION B ---
B> BEGIN;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT fn_registrar_venta(990002, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]);
psql: ERROR:  RN-09: stock insuficiente del vino 990001 en la sala 990001.
DETAIL:  Se piden 1 botellas y la sala tiene 0.
HINT:  Solicite una transferencia desde el deposito central.
CONTEXT:  PL/pgSQL function fn_trg_renglon_comprobante_completar() line 50 at RAISE
```

**Captura de terminal requerida:** tomar una foto de la terminal B mostrando el `ERROR: RN-09: stock insuficiente del vino 990001 en la sala 990001.` con el `DETAIL` y `HINT`. La terminal A debe mostrar su `SELECT fn_registrar_venta(...)` → número de comprobante, y `COMMIT`.

### 6.1 Escenario 4b: dos ventas de varios vinos en orden inverso

Reponer: `UPDATE stock_sala SET cantidad = 10 WHERE id_sala = 990001;` (terminal del propietario).

| Paso | Terminal A (API) | Terminal B (API) |
|---:|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT fn_registrar_venta(990001, 990001, ARRAY[990001, 990002]::BIGINT[], ARRAY[1, 1]);` | |
| 3 | | `SELECT fn_registrar_venta(990002, 990001, ARRAY[990002, 990001]::BIGINT[], ARRAY[1, 1]);` → **queda esperando** |
| 4 | `COMMIT;` | |
| 5 | | Devuelve su número de comprobante. `COMMIT;` |

**Resultado observado:** las dos ventas se confirman y el stock queda en 8 y 8. B pidió los vinos al revés, pero `fn_registrar_venta` bloquea las filas de stock **en orden de `cod_vino`**: las dos sesiones piden primero 990001, así que una espera a la otra y no se bloquean en cruz.

Transcripción auténtica (sesiones A y B como cuenta de la API):

```
--- SALIDA SESION A ---
A> BEGIN;
BEGIN
A> SELECT fn_registrar_venta(990001, 990001, ARRAY[990001,990002]::BIGINT[], ARRAY[1,1]);
 fn_registrar_venta
--------------------
                 23
(1 row)

A> SELECT pg_sleep(3);
 pg_sleep
----------

(1 row)

A> COMMIT;
COMMIT

--- SALIDA SESION B ---
B> BEGIN;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT fn_registrar_venta(990002, 990001, ARRAY[990002,990001]::BIGINT[], ARRAY[1,1]);
 fn_registrar_venta
--------------------
                 24
(1 row)

B> COMMIT;
COMMIT
```

Si cada venta bloqueara en el orden en que recibe los vinos, A podría tener 990001 esperando 990002 mientras B tiene 990002 esperando 990001. PostgreSQL detectaría el deadlock y cancelaría una con `40P01`.

**Captura de terminal requerida:** tomar una foto de ambas terminales mostrando que cada una obtuvo su número de comprobante (A → 23, B → 24) y ambas hicieron `COMMIT` exitoso.

## 7. Escenario 5: `REPEATABLE READ`

Reponer la botella. Volver a las terminales del propietario.

| Paso | Terminal A | Terminal B |
|---:|---|---|
| 1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | `BEGIN ISOLATION LEVEL REPEATABLE READ;` |
| 2 | `SELECT cantidad … ;` → **1** | `SELECT cantidad … ;` → **1** (se toma la foto de B) |
| 3 | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;` | |
| 4 | `COMMIT;` | |
| 5 | | `SELECT cantidad … ;` → **sigue viendo 1** (su foto) |
| 6 | | `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE …;`<br>`ERROR: could not serialize access due to concurrent update` (SQLSTATE 40001) |
| 7 | | `ROLLBACK;` |

Transcripción auténtica (sesiones A y B como propietario):

```
--- SALIDA SESION A ---
A> BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
A> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

A> SELECT pg_sleep(3);
 pg_sleep
----------

(1 row)

A> UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;
UPDATE 1
A> COMMIT;
COMMIT

--- SALIDA SESION B ---
B> BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
B> SELECT pg_sleep(0.5);
 pg_sleep
----------

(1 row)

B> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

B> SELECT pg_sleep(3);
 pg_sleep
----------

(1 row)

B> SELECT cantidad FROM stock_sala WHERE id_sala = 990001 AND cod_vino = 990001;
 cantidad
----------
        1
(1 row)

B> UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 990001 AND cod_vino = 990001;
psql:/tmp/s5_b.sql:7: ERROR:  could not serialize access due to concurrent update

B> ROLLBACK;
ROLLBACK
```

**Resultado observado:** B recibe `40001 could not serialize access due to concurrent update` y debe reintentar la transacción completa.

**Qué cambia respecto de `READ COMMITTED`:**

- en `READ COMMITTED` el `UPDATE` de B espera, relee la fila confirmada y continúa (escenario 2);
- en `REPEATABLE READ`, B no puede actualizar una fila que cambió después de su foto: PostgreSQL cancela la transacción con 40001 y hay que reintentarla completa;
- la API traducirá 40001, y también 40P01 (deadlock), a HTTP 503 sugiriendo reintento.

El proyecto usa `READ COMMITTED` con bloqueos explícitos (`FOR UPDATE` en la venta y en los procedimientos). El comportamiento es predecible, la espera es corta y los errores que llegan al usuario son de negocio (RN-09), no de serialización.

**Captura de terminal requerida:** tomar una foto de la terminal B mostrando el `ERROR: could not serialize access due to concurrent update`. La terminal A debe mostrar su `UPDATE` → `UPDATE 1` y `COMMIT`.

## 8. Limpieza

En una terminal del propietario:

```sql
BEGIN;
DELETE FROM comprobante WHERE id_sala = 990001;
DELETE FROM stock_sala WHERE id_sala = 990001;
DELETE FROM vino WHERE cod_vino IN (990001, 990002);
DELETE FROM cliente WHERE id_cliente IN (990001, 990002);
DELETE FROM sala_venta WHERE id_sala = 990001;
DELETE FROM localidad WHERE id_localidad = 990001;
DELETE FROM bodega WHERE cuit = '30990000001';
DELETE FROM cepa WHERE id_cepa = 990001;
COMMIT;
```

El borrado de comprobantes es el de D1: arrastra los renglones en cascada.

## 9. Otros puntos de concurrencia resueltos en la base

| Situación | Mecanismo |
|---|---|
| Dos renglones del mismo comprobante a la vez | El trigger BEFORE bloquea la cabecera `FOR UPDATE`: el recálculo de importes de una sesión no pisa el de la otra. |
| Procesar el mismo ingreso o transferencia dos veces a la vez | `sp_procesar_*` bloquean la cabecera `FOR UPDATE`; la segunda llamada espera y encuentra `procesado` (RN-10/RN-11). |
| Dos transferencias que usan los mismos vinos | `sp_procesar_transferencia` bloquea las filas del depósito en orden de `cod_vino`: todas las sesiones piden los bloqueos en el mismo orden y no se bloquean en cruz. |
| Editar un renglón mientras otra sesión termina el documento | El trigger RN-12 bloquea la cabecera `FOR SHARE`: el cambio de estado espera a que termine la edición, o la edición encuentra el documento ya terminado. |
| Dos ventas con varios vinos en orden inverso | `fn_registrar_venta` bloquea el stock en orden de `cod_vino` (escenario 4b): no hay deadlock. |
| Agregar renglones a una venta ya confirmada | `comprobante.xact_alta` + `trg_renglon_comprobante_completar` (RN-12): se rechaza aun para el propietario. |
| Otros bloqueos en orden distinto (por ejemplo, operaciones manuales del propietario) | Pueden producir un deadlock (40P01). PostgreSQL lo detecta y cancela una; la API sugiere reintentar. |

## 10. Comparación y conceptos clave

### 10.1 Diferencias entre READ COMMITTED y REPEATABLE READ

| Aspecto | READ COMMITTED (default) | REPEATABLE READ |
|---|---|---|
| Foto de los datos | Cada sentencia ve los datos confirmados al empezar *esa sentencia* | Toda la transacción ve una única foto tomada en su primera consulta |
| UPDATE sobre fila modificada por otra tx | Espera a que la otra confirme, re-lee la versión nueva y aplica el cambio | Cancela con `40001` si la fila cambió después de la foto |
| Aplicación en el proyecto | Se usa con bloqueos explícitos (`FOR UPDATE`) | No es el modo de operación del proyecto |
| Manejo de errores | Errores de negocio (RN-09, CHECK) o de constraint | Errores de serialización (40001) que requieren reintento completo |

### 10.2 Funcionamiento de los bloqueos de fila

Un bloqueo de fila (`FOR UPDATE` o `FOR SHARE`) impide que otra transacción modifique o bloquee la misma fila hasta que el bloqueador haga `COMMIT` o `ROLLBACK`. Esto serializa el acceso a datos críticos:

- **Sin bloqueo:** dos sesiones pueden leer el mismo valor (1), ambas calcular su propio resultado y escribirlo, causando una actualización perdida (Escenario 1).
- **Con bloqueo:** la segunda sesión espera en el `FOR UPDATE` hasta que la primera libera el bloqueo, luego lee el valor ya confirmado y decide en consecuencia (Escenarios 2, 3 y 4).

### 10.3 Función de SELECT … FOR UPDATE

`SELECT … FOR UPDATE` lee las filas y las bloquea con modo de exclusión. Mientras el bloqueo esté activo:

- Otra sesión que ejecute `SELECT … FOR UPDATE` o `UPDATE` sobre la misma fila queda **esperando**.
- Cuando el bloqueador confirma (`COMMIT`), la espera termina y la segunda sesión ve el valor ya confirmado.
- Cuando el bloqueador deshace (`ROLLBACK`), la fila vuelve al estado anterior.

Este mecanismo es lo que permite que `fn_registrar_venta` y los triggers rechacen ventas sin stock con un mensaje de negocio claro (RN-09) en lugar de permitir actualizaciones perdidas.

### 10.4 Significado del error SQLSTATE 40001

El error `40001 could not serialize access due to concurrent update` ocurre en `REPEATABLE READ` cuando una transacción intenta modificar una fila que fue cambiada y confirmada por otra transacción *después* de que la primera tomó su foto inicial. PostgreSQL detecta que no puede garantizar el aislamiento y cancela la transacción.

La aplicación debe **reintentar la transacción completa** desde el `BEGIN`. En el proyecto, este error se traduce a HTTP 503 sugeriendo reintento.

### 10.5 Conclusión: con y sin bloqueo explícito

| Sin `FOR UPDATE` | Con `FOR UPDATE` |
|---|---|
| Ambas sesiones leen stock = 1 | La segunda sesión espera hasta que la primera confirma |
| Ambas escriben stock = 0 (se venden 2 botellas habiendo 1) | La segunda sesión lee stock = 0 y rechaza la venta |
| No hay error; los datos están corruptos | Error de negocio (RN-09) o de constraint; los datos son consistentes |
| El `CHECK (cantidad >= 0)` no siempre detecta el problema | El bloqueo previene el problema antes de que ocurra |

El bloqueo explícito de filas es el mecanismo correcto para prevenir actualizaciones perdidas en operaciones de stock. El proyecto lo combina con `READ COMMITTED` (el nivel por defecto de PostgreSQL) para obtener un comportamiento predecible, esperas cortas y errores de negocio claros en lugar de errores de serialización.

---

## 11. Capturas de terminal (manual)

No se generaron imágenes PNG reconstruidas con Python. Cada escenario tiene su transcripción completa y auténtica de terminal A y terminal B arriba en este documento. Para producir las capturas que solicita la cátedra, seguir estos pasos con dos terminales reales:

### 11.1 Levantar el entorno

```bash
docker compose up -d db
docker compose up -d migrate
```

Esperar a que `db` y `migrate` terminen correctamente.

### 11.2 Abrir dos terminales como propietario

Terminal A:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB"'
```

Terminal B: mismo comando.

En cada `psql`, identificar la sesión:

```sql
\set PROMPT1 'A> '   -- terminal A
\set PROMPT1 'B> '   -- terminal B
```

### 11.3 Cargar datos de demostración (terminal A)

Ejecutar el bloque de `setup` de la sección 2 del guion (inserts de localidad, sala, bodega, cepa, vino, cliente, socio_club, stock_sala con una botella de 990001 y diez de 990002).

### 11.4 Antes de cada escenario, reponer (terminal A)

```sql
UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 990001 AND cod_vino = 990001;
```

Para el escenario 4b: `UPDATE stock_sala SET cantidad = 10 WHERE id_sala = 990001;`

### 11.5 Ejecutar cada escenario paso a paso

Ejecutar cada sentencia en la terminal indicada **y esperar a que termine** antes de pasar a la siguiente, salvo cuando el guion diga que queda esperando. Para los escenarios con espera real (3, 4, 4b, 5), lanzar una sesión en segundo plano o usar `pg_sleep` para sincronizar.

Tomar una foto de **ambas terminales** al finalizar cada escenario, asegurando que se vean:
- El prompt `A>` o `B>` que identifica la sesión
- La consulta SQL completa ejecutada
- El resultado que devuelve `psql` (filas, `UPDATE n`, `COMMIT`, `ROLLBACK`, o el `ERROR` completo con `DETAIL` y `HINT`)
- El stock final cuando corresponda

### 11.6 Qué debe mostrar cada captura

| Escenario | Terminal A debe mostrar | Terminal B debe mostrar |
|---|---|---|
| 1 | `SELECT` → 1, `UPDATE 0`, `COMMIT`, `SELECT final` → 0 | `SELECT` → 1, `UPDATE 0`, `COMMIT` |
| 2 | `SELECT` → 1, `UPDATE` → `UPDATE 1`, `COMMIT` | `SELECT` → 1, `UPDATE` → `ERROR check constraint` con `DETAIL: Failing row contains (990001, 990001, -1)` |
| 3 | `SELECT ... FOR UPDATE` → 1, `UPDATE` → `UPDATE 1`, `COMMIT` | `SELECT ... FOR UPDATE` (espera), luego → 0, `ROLLBACK` |
| 4 | `SELECT fn_registrar_venta(...)` → nro comprobante, `COMMIT` | `SELECT fn_registrar_venta(...)` → `ERROR: RN-09: stock insuficiente...` con `DETAIL` y `HINT` |
| 4b | `SELECT fn_registrar_venta(...)` → nro 23, `COMMIT` | `SELECT fn_registrar_venta(...)` → nro 24, `COMMIT` |
| 5 | `BEGIN ISOLATION LEVEL REPEATABLE READ`, `SELECT` → 1, `UPDATE` → `UPDATE 1`, `COMMIT` | `BEGIN ISOLATION LEVEL REPEATABLE READ`, `SELECT` → 1 (foto), `SELECT` → 1 (sigue), `UPDATE` → `ERROR: could not serialize access due to concurrent update` |

### 11.7 Limpieza (terminal del propietario)

```sql
BEGIN;
DELETE FROM comprobante WHERE id_sala = 990001;
DELETE FROM stock_sala WHERE id_sala = 990001;
DELETE FROM vino WHERE cod_vino IN (990001, 990002);
DELETE FROM cliente WHERE id_cliente IN (990001, 990002);
DELETE FROM sala_venta WHERE id_sala = 990001;
DELETE FROM localidad WHERE id_localidad = 990001;
DELETE FROM bodega WHERE cuit = '30990000001';
DELETE FROM cepa WHERE id_cepa = 990001;
COMMIT;
```

Verificar que todos los `DELETE` devolvieron filas > 0 y que no queda rastro de los ids 990001/990002.
