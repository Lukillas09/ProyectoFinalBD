# Concurrencia: la última botella

Guion reproducible para la demostración de la Etapa 2 (consigna, paso 8, y Anexo A.8): dos sesiones `psql` intentan vender la última botella de un vino en la misma sala.

> **Transacciones como tema no visto.** La aclaración docente declaró opcionales los temas no vistos y mencionó las transacciones como ejemplo (ver `docs/requisitos.md`, sección 4). Igual se implementan y se demuestran, porque la rúbrica las puntúa (Funciones, procedimientos, triggers y transacciones: 17 puntos) y porque RN-09 y la transferencia "sin cambios a medias" dependen de ellas.

Los resultados que figuran abajo se obtuvieron ejecutando cada escenario con dos sesiones concurrentes en PostgreSQL 16. Las horas cambian en cada ejecución; el orden de los eventos y los errores, no.

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

En la terminal A, cargar los datos de la demostración (una sala con **una** botella):

```sql
BEGIN;
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
OVERRIDING SYSTEM VALUE VALUES (990001, '5600-C', 'Localidad concurrencia', 'Mendoza', 'Encargado C');
INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Calle concurrencia', '1', 'lunes', 990001);
INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30990000001', 'Bodega concurrencia', 'Dom');
INSERT INTO cepa (id_cepa, nombre, tipo) OVERRIDING SYSTEM VALUE VALUES (990001, 'Malbec concurrencia', 'tinta');
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Última botella', 'tinto', 2021, 750, 14.00, 12500.00, '30990000001');
INSERT INTO composicion_vino VALUES (990001, 990001, 100.00);
INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo)
OVERRIDING SYSTEM VALUE VALUES (990001, 'Cliente A', 'DNI', '99000001', 'Dir', 990001, 'socio'),
                               (990002, 'Cliente B', 'DNI', '99000002', 'Dir', 990001, 'socio');
INSERT INTO socio_club VALUES (990001), (990002);
INSERT INTO stock_sala VALUES (990001, 990001, 1);
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

**Por qué el `CHECK (cantidad >= 0)` no alcanza:** el `CHECK` sólo valida el valor que se escribe, y 0 es válido. El problema no es un número negativo sino que B decidió con un dato viejo (leyó 1 antes de que A confirmara) y sobrescribió el resultado de A con un valor absoluto calculado afuera. Por eso el stock debe descontarse en la base, sobre la fila bloqueada.

> 📷 **Captura 1:** terminales A y B al finalizar el paso 9.

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

El `CHECK` protege el invariante "nunca negativo", no la decisión "hay stock para vender".

> 📷 **Captura 2:** terminal B mostrando el error del paso 6.

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

**Resultado observado:** B esperó hasta el `COMMIT` de A (≈1,5 s en la ejecución de prueba) y leyó 0. La lectura bloqueante hace que la decisión de B se tome con el dato ya confirmado.

> 📷 **Captura 3:** terminal B esperando (paso 3) y luego mostrando 0 (paso 6).

## 6. Escenario 4: la venta real (trigger RN-09)

En el sistema, la aplicación no lee ni descuenta el stock: inserta el renglón y la base hace todo. `trg_renglon_comprobante_completar` (`db/migrations/005_triggers.sql`) bloquea la fila de `stock_sala` con `FOR UPDATE` y rechaza si no alcanza. Después, `trg_renglon_comprobante_impactar` descuenta el stock.

Reponer la botella. Abrir las dos terminales **con la cuenta de la API**:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -h 127.0.0.1 -U "$DB_APP_USER" -d "$POSTGRES_DB"'
```

| Paso | Terminal A (API) | Terminal B (API) |
|---:|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `INSERT INTO comprobante (id_cliente, id_sala) VALUES (990001, 990001) RETURNING nro_comprobante;` → anotar el número (`nA`) | `INSERT INTO comprobante (id_cliente, id_sala) VALUES (990002, 990001) RETURNING nro_comprobante;` → anotar `nB` |
| 3 | `INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (nA, 990001, 1);` | |
| 4 | | `INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (nB, 990001, 1);` → **queda esperando** |
| 5 | `COMMIT;` | |
| 6 | | `ERROR: RN-09: stock insuficiente del vino 990001 en la sala 990001.`<br>`DETAIL: Se piden 1 botellas y la sala tiene 0.`<br>`HINT: Solicite una transferencia desde el depósito central.` |
| 7 | | `ROLLBACK;` (la transacción quedó abortada: el comprobante de B tampoco se guarda) |

**Resultado observado:** una sola venta confirmada, stock 0 y un mensaje de negocio claro para la segunda, que la API traducirá a HTTP 409. Como la venta es una transacción, el comprobante de B se descarta junto con su renglón: no quedan datos a medias.

> 📷 **Captura 4:** terminal B con el error RN-09.

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

**Qué cambia respecto de `READ COMMITTED`:**

- en `READ COMMITTED` el `UPDATE` de B espera, relee la fila confirmada y continúa (escenario 2);
- en `REPEATABLE READ`, B no puede actualizar una fila que cambió después de su foto: PostgreSQL cancela la transacción con 40001 y hay que reintentarla completa;
- la API traducirá 40001, y también 40P01 (deadlock), a HTTP 503 sugiriendo reintento.

El proyecto usa `READ COMMITTED` con bloqueos explícitos (`FOR UPDATE` en la venta y en los procedimientos). El comportamiento es predecible, la espera es corta y los errores que llegan al usuario son de negocio (RN-09), no de serialización.

> 📷 **Captura 5:** terminal B con el error 40001.

## 8. Limpieza

En una terminal del propietario:

```sql
BEGIN;
DELETE FROM comprobante WHERE id_sala = 990001;
DELETE FROM stock_sala WHERE id_sala = 990001;
DELETE FROM vino WHERE cod_vino = 990001;
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
| Dos ventas con varios vinos en orden inverso | Pueden producir un deadlock (40P01). PostgreSQL lo detecta y cancela una; la API sugiere reintentar. |
