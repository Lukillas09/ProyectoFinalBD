# docs/defensa.md — Guía de estudio para la defensa oral

Proyecto: **Bodegas del Atuel** — TPI de Bases de Datos 2026, UTN FR San Rafael.
Rama de trabajo: `feat/etapa5-consultas-avanzadas`.

Este documento concentra preguntas probables de defensa y respuestas cortas, organizadas por etapa, más una sección de desafíos prácticos. Cada respuesta está vinculada al código real del repositorio.

## Introducción

**Objetivo general del proyecto.**
Modelar y operar el negocio de varias bodegas (producción, stock, ventas, transferencias, auditoría) con las reglas de negocio implementadas en PostgreSQL, no en la aplicación, y exponer un mínimo circuito web (API + front + Nginx) con salud de base de datos.

**Arquitectura básica.**
Navegador → Nginx (front, puerto 8080) → `/api/*` → FastAPI (puerto 8000) → pool Psycopg 3 → PostgreSQL 16 (rol limitado `bodegas_api`). Un servicio `migrate` de una sola ejecución aplica las migraciones como propietario antes de arrancar la API.

**Tecnologías utilizadas.**
PostgreSQL 16, Python + FastAPI + Psycopg 3 (pool), HTML/CSS/JS sin framework para el front, Nginx como proxy de mismo origen, Docker Compose.

**Organización de migraciones y pruebas.**
- Migraciones: `db/migrations/001_esquema.sql` a `008_indices.sql`, ejecutadas en orden por `db/migrate.sh` con el rol propietario, dentro de una transacción por archivo, con registro de nombre y SHA-256 en `bodegas.schema_migration`.
- Pruebas: `db/tests/run_all.sh` ejecuta `001` a `007` con el rol correspondiente a cada una; todas terminan en `ROLLBACK` salvo `007` que limpia sus datos.

---

## Etapa 1 — Modelado y esquema físico

**P1. ¿Qué representa la entidad `parcela` y por qué es una entidad independiente?**
R: Representa una división de una finca, identificada solo dentro de esa finca (`id_finca, nro_parcela`). Es independiente porque tiene propia superficie, año de plantación y cepa, y su clave primaria es compuesta `(id_finca, nro_parcela)` (entidad débil).
Ejemplo: `CREATE TABLE parcela (... CONSTRAINT pk_parcela PRIMARY KEY (id_finca, nro_parcela))`.
Archivo: `db/migrations/001_esquema.sql:97-114`.

**P2. ¿Cuál es la clave primaria de `cliente` y cuál es su clave candidata natural?**
R: PK es `id_cliente` (subrogada, `IDENTITY`). Candidata natural es `(tipo_documento, nro_documento)` con `UNIQUE`. Se eligió la subrogada por simplicidad y porque los documentos naturales pueden repetirse entre tipos de documento.
Ejemplo: `CONSTRAINT pk_cliente PRIMARY KEY (id_cliente)` y `CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, nro_documento)`.
Archivo: `db/migrations/001_esquema.sql:216-235`, `db/migrations/002_constraints.sql:90-92`.

**P3. ¿Cómo se garantiza que un cliente pertenezca exactamente a un subtipo (socio, distribuidor o exportador)?**
R: La FK compuesta `(id_cliente, tipo)` en cada subtipo referencia `cliente(id_cliente, tipo)`; cada subtipo tiene un `CHECK` que fija su `tipo` (p. ej. `socio_club.tipo = 'socio'`). La totalidad se cierra con un `CONSTRAINT TRIGGER` diferido en `005_triggers.sql`.
Archivo: `db/migrations/001_esquema.sql:241-275`, `db/migrations/002_constraints.sql:101-113`, `db/migrations/005_triggers.sql:578-634`.

**P4. ¿Qué accion `ON UPDATE`/`ON DELETE` usa `fk_parcela_finca` y por qué?**
R: `ON UPDATE CASCADE ON DELETE CASCADE`. Si se borra una finca, sus parcelas se borran; si cambia `id_finca`, se propaga. Justificación: la parcela no existe sin su finca.
Archivo: `db/migrations/001_esquema.sql:104-108`.

**P5. ¿Cuántas tablas tiene el esquema y quién es su dueño?**
R: 31 tablas (30 de negocio + `schema_migration`). Todas pertenecen al rol propietario (`bodegas_owner`); la API no crea objetos.
Archivo: `db/migrations/001_esquema.sql`, prueba `db/tests/001_infraestructura.sql`.

**P6. ¿Qué es `schema_migration` y para qué sirve?**
R: Tabla técnica que registra nombre, SHA-256 e instante de cada migración aplicada. Permite omitir las ya aplicadas y detectar si una migración registrada fue modificada. No pertenece al modelo de negocio.
Archivo: `db/migrations/001_esquema.sql:25-30`, `db/migrations/README.md`.

**P7. ¿Cómo se crean las migraciones y con qué rol?**
R: Con `db/migrate.sh`, ordenando `NNN_*.sql`, cada una en su propia transacción con `ON_ERROR_STOP`, como `DB_OWNER_USER` (propietario), nunca como la API ni el bootstrap.
Archivo: `db/migrate.sh`, `db/migrations/README.md`, `README.md` sección Migraciones.

**P8. ¿Qué restricciones hay en `comprobante` y cuál es su propósito?**
R: `ck_comprobante_importes` impone `subtotal >= 0`, `descuento >= 0`, `descuento <= subtotal` y `total = subtotal - descuento`. Los importes no se cargan a mano: el trigger `BEFORE INSERT OR UPDATE` los exige en 0 al insertar y solo permite modificarlos vía `fn_recalcular_comprobante` con la marca GUC `bodegas.recalculo_importes`.
Archivo: `db/migrations/002_constraints.sql:119-126`, `db/migrations/005_triggers.sql:202-233`.

**P9. ¿Por qué no se usa `FLOAT` para dinero?**
R: Se usa `NUMERIC(14,2)` para importes, precios, salario, superficies, kilos, graduación, etc., para evitar errores de punto flotante en cálculos monetarios.
Archivo: `db/migrations/001_esquema.sql` (columnas `NUMERIC`), `AGENTS.md`.

**P10. ¿Qué es `cuit_dom` y dónde se aplica?**
R: Un `DOMAIN` sobre `VARCHAR(11)` que valida el formato `^[0-9]{11}$`. Se aplica a `empleado.cuit`, `bodega.cuit`, `transportista.cuit` y `ingreso.cuit_bodega`.
Archivo: `db/migrations/001_esquema.sql:8-10`, `db/migrations/002_constraints.sql:7-9`.

**P11. ¿Cuáles son los `ENUM` del modelo y dónde se usan?**
R: `estado_documento` (`en_confeccion`, `terminado`, `procesado`) en `ingreso.estado` y `transferencia.estado`; `tipo_cliente` (`socio`, `distribuidor`, `exportador`) en `cliente.tipo` y los subtipos.
Archivo: `db/migrations/001_esquema.sql:12-22`.

**P12. ¿Qué decisiones de modelado son las más importantes para defender?**
R: Clave compuesta `(id_cliente, tipo)` para la jerarquía de clientes; `parcela` como entidad débil; `stock_deposito` con PK `(cod_vino)` (depósito único) vs `stock_sala` con PK `(id_sala, cod_vino)`; `xact_alta` (agregada en el PR #3) para cerrar ventas emitidas.
Archivos: `db/migrations/001_esquema.sql`, `db/migrations/005_triggers.sql:33-34`.

---

## Etapa 2 — Reglas de negocio y transacciones

**P1. ¿Cuál es el único camino de venta de la API y por qué?**
R: `fn_registrar_venta(id_cliente, id_sala, vinos BIGINT[], cantidades INTEGER[])`. La API no tiene `INSERT` sobre `comprobante` ni `renglon_comprobante`, así que no puede dejar cabeceras vacías ni agregar renglones a una venta existente.
Archivo: `db/migrations/004_procedimientos.sql:248-326`, `db/migrations/007_roles.sql:53`.

**P2. ¿Qué hacen `BEGIN`, `COMMIT` y `ROLLBACK` en este proyecto?**
R: Agrupan operaciones en una transacción todo-o-nada. Los procedimientos no hacen `COMMIT` interno; se ejecutan dentro de la transacción del llamante. Las pruebas terminan en `ROLLBACK` para no dejar cambios.
Archivo: `db/migrations/004_procedimientos.sql:6-8`, `db/tests/004_reglas_negocio.sql:16,828`.

**P3. ¿Cómo se controla el stock al vender y qué impide vender sin stock?**
R: El trigger `BEFORE INSERT` `trg_renglon_comprobante_completar` bloquea la fila de `stock_sala` con `SELECT ... FOR UPDATE` y rechaza con `RN-09` si `cantidad < NEW.cantidad` o no hay fila. `AFTER INSERT` descuenta el stock.
Archivo: `db/migrations/005_triggers.sql:61-156`.

**P4. ¿Qué ocurre si dos usuarios intentan vender la última botella al mismo tiempo?**
R: El segundo `SELECT ... FOR UPDATE` espera hasta el `COMMIT` del primero, luego lee stock 0 y recibe `RN-09: stock insuficiente`. No queda comprobante ni stock descalzado (todo o nada). Documentado en `docs/concurrencia.md` escenario 4.
Archivo: `docs/concurrencia.md:133-153`, `db/migrations/005_triggers.sql:107-121`.

**P5. ¿Cómo se evitan deadlocks en ventas de varios vinos?**
R: `fn_registrar_venta` bloquea las filas de `stock_sala` en orden de `cod_vino`. Dos sesiones concurrentes piden los bloqueos en el mismo orden, así no se bloquean en cruz (escenario 4b de concurrencia).
Archivo: `db/migrations/004_procedimientos.sql:303-308`, `docs/concurrencia.md:157-173`.

**P6. ¿Qué es `FOR UPDATE` y dónde se usa?**
R: Bloquea filas al leerlas para serializar escrituras concurrentes. Se usa en la venta (stock), `sp_procesar_ingreso` (cabecera y depósito), `sp_procesar_transferencia` (cabecera y depósito), y los triggers de renglones (cabecera).
Archivo: `db/migrations/004_procedimientos.sql:64-67,154-183`, `db/migrations/005_triggers.sql:75-79,107-112`.

**P7. ¿Qué nivel de aislamiento usa el proyecto y por qué?**
R: `READ COMMITTED` (por defecto de PostgreSQL) con bloqueos explícitos (`FOR UPDATE`). Es predecible, las esperas son cortas y los errores al usuario son de negocio (`RN-09`), no de serialización. `REPEATABLE READ` se documenta pero no se usa en la API.
Archivo: `docs/concurrencia.md:9-16,175-195`.

**P8. ¿Cómo se registra una venta y qué calcula la base automáticamente?**
R: `fn_registrar_venta` crea la cabecera (importes en 0) y los renglones; el trigger `BEFORE INSERT` completa `precio_unitario` (vigente), `descuento_porcentaje` (del cliente) y `subtotal`; el `AFTER INSERT` descuenta stock y recalcula `total` de la cabecera.
Archivo: `db/migrations/005_triggers.sql:61-156`, `db/migrations/003_funciones.sql:83-112`.

**P9. ¿Qué son `fn_descuento_cliente`, `fn_stock_sala`, `fn_total_comprobante` y `fn_antiguedad_anios`?**
R: Funciones de cálculo reutilizables (Etapa 2). Las tres primeras son `STABLE`; `fn_antiguedad_anios` es `IMMUTABLE` (su `DEFAULT CURRENT_DATE` se evalúa en la llamada, por eso no se puede indexar sobre ella).
Archivo: `db/migrations/003_funciones.sql:24-139`, prueba de volatilidad en `db/tests/004_reglas_negocio.sql:801-809`.

**P10. ¿Qué validaciones hace `fn_registrar_venta` antes de insertar?**
R: Al menos un renglón; listas del mismo largo; sin vinos nulos ni repetidos; cantidades positivas; y bloquea stock para todos los vinos de la venta.
Archivo: `db/migrations/004_procedimientos.sql:264-308`.

**P11. ¿Qué es `xact_alta` y qué problema resuelve?**
R: Columna `xid8` en `comprobante` que registra la transacción real que creó la cabecera. El trigger impide agregar renglones a un comprobante creado en otra transacción (`RN-12`), cerrando la venta confirmada.
Archivo: `db/migrations/005_triggers.sql:33-91`.

**P12. ¿Qué reglas de negocio se prueban en `004_reglas_negocio.sql`?**
R: RN-01 a RN-15, U6, totalidad de la jerarquía de clientes y volatilidad de funciones, con casos de éxito y rechazo, todo dentro de una transacción revertida.
Archivo: `db/tests/004_reglas_negocio.sql`.

---

## Etapa 3 — Consultas y vistas

**P1. ¿Cuáles son las vistas del proyecto y qué hace cada una?**
R: `v_stock_total_vino` (depósito + salas + total por vino), `v_ventas_mensuales_sala` (comprobantes e importes por sala y mes), `v_documentos_pendientes` (ingresos y transferencias no procesados), `v_ficha_vino` (bodega, corte, maridajes y stock total para S9).
Archivo: `db/migrations/006_vistas.sql`.

**P2. ¿Cómo se resuelve el corte y los maridajes en `v_ficha_vino` sin multiplicar filas?**
R: Con subconsultas agrupadas (`GROUP BY cod_vino`) que usan `string_agg`, unidas con `LEFT JOIN` por vino, así una fila de vino no se duplica al combinar corte y maridajes.
Archivo: `db/migrations/006_vistas.sql:114-131`.

**P3. ¿Por qué `v_ventas_mensuales_sala` no es materializada?**
R: Cambia con cada venta y una copia quedaría desactualizada entre refrescos. La Etapa 4 evaluó materializarla y decidió NO hacerlo (costo de refresco ~182 ms y datos obsoletos sin consumidor de alta frecuencia).
Archivo: `db/migrations/006_vistas.sql:43`, `docs/rendimiento.md:13`.

**P4. ¿Cómo se ejecuta una consulta representativa con JOIN y agregación?**
R: Ejemplo: ventas de un vino con su comprobante:
```sql
SELECT r.cod_vino, count(*) AS ventas, sum(r.cantidad) AS botellas
FROM bodegas.renglon_comprobante r
JOIN bodegas.comprobante c ON c.nro_comprobante = r.nro_comprobante
WHERE r.cod_vino = 1
GROUP BY r.cod_vino;
```
Archivo: `consultas/select.sql` (S5/S9), verificación ejecutada en esta sesión.

**P5. ¿Qué usa `v_stock_total_vino` para obtener el stock total?**
R: `LEFT JOIN` a `stock_deposito` y a una subconsulta que suma `stock_sala` por vino; vinos sin stock aparecen con 0 gracias a `COALESCE`.
Archivo: `db/migrations/006_vistas.sql:16-31`.

**P6. ¿Cómo se manejan los períodos relativos en las consultas de la Etapa 5?**
R: Se calculan desde `CURRENT_DATE`, nunca con fechas fijas, y se aplica `AT TIME ZONE` a la constante, no a la columna, para que el filtro sobre `fecha` pueda usar índice.
Archivo: `consultas/README.md:30-35`, `docs/rendimiento.md:33`.

**P7. ¿Qué consulta es un control negativo en rendimiento y por qué?**
R: C7 / S1 (ranking de los 10 vinos más vendidos): agrega toda la tabla, no cambia de plan con índices (Seq Scan), y su variación de tiempo no es efecto de índice.
Archivo: `docs/rendimiento.md:4,74-82`.

**P8. ¿Cómo se verifica que una vista devuelve datos correctos?**
R: Consultando `v_ficha_vino` y comparando con las tablas base (`vino`, `bodega`, `composicion_vino`, `maridaje`, `stock_sala`, `stock_deposito`). Ejecutado en esta sesión: devuelve 3 registros con corte, maridajes y stock_total.
Archivo: `db/migrations/006_vistas.sql`, verificación práctica realizada.

---

## Etapa 4 — Índices y rendimiento

**P1. ¿Cuántos índices hay y cuáles son los seis nuevos de la Etapa 4?**
R: 48 en total (31 PK + 11 UNIQUE + 6 nuevos). Los nuevos: `idx_comprobante_id_sala_fecha`, `idx_comprobante_fecha`, `idx_comprobante_id_cliente`, `idx_renglon_comprobante_cod_vino`, `idx_transferencia_pendientes`, `idx_auditoria_precio_cod_vino_fecha`.
Archivo: `db/migrations/008_indices.sql`, `docs/rendimiento.md:3`.

**P2. ¿Por qué el orden del índice compuesto es `(id_sala, fecha)` y no `(fecha, id_sala)`?**
R: Igualdad primero (`id_sala`), rango después (`fecha`). Con `(fecha, id_sala)` se recorren todas las salas del período y se filtra `id_sala` dentro del índice; se midió más páginas (99 vs 6 en el último año).
Archivo: `db/migrations/008_indices.sql:20-28`, `docs/rendimiento.md:5`.

**P3. ¿Para qué sirve `INCLUDE (id_sala, total)` en `idx_comprobante_fecha`?**
R: Permite Index Only Scan sin leer la tabla (`Heap Fetches: 0`) para consultas sin sala fija (S8), porque `id_sala` y `total` viajan en las hojas sin ser parte de la clave.
Archivo: `db/migrations/008_indices.sql:30-37`, `docs/rendimiento.md:3`.

**P4. ¿Por qué PostgreSQL no indexa las FK automáticamente y cuál es el impacto?**
R: No lo hace por defecto. Sin `idx_comprobante_id_cliente`, borrar un cliente obliga a recorrer los 150.125 comprobantes por cada cliente borrado (control de `fk_comprobante_cliente`). Se midió de 3.620 ms a 53,6 ms.
Archivo: `db/migrations/008_indices.sql:39-46`, `docs/rendimiento.md:4`.

**P5. ¿Qué es un índice parcial y cuándo lo usa el planificador?**
R: Indexa solo filas que cumplen una condición (`estado <> 'procesado'`). El planificador lo usa solo si puede probar, al planificar, que el filtro de la consulta implica el del índice. No lo usa con `CURRENT_DATE - 7` porque no es constante al planificar.
Archivo: `db/migrations/008_indices.sql:56-65`, `docs/rendimiento.md:7`.

**P6. ¿Qué es `EXPLAIN (ANALYZE, BUFFERS)` y qué se mide?**
R: Ejecuta la consulta y muestra el plan real: tiempo, tipo de recorrido, filas leídas, filas descartadas y buffers. Se usó para medir antes y después de cada índice.
Archivo: `db/perf/medir.sh`, `db/perf/medir.sql`, `docs/rendimiento.md:2`.

**P7. ¿Cuándo el planificador no usa un índice existente?**
R: Con baja selectividad cuando hay que ir a la tabla por columnas no cubiertas (caso C: pide `id_cliente`, estima más caro que Seq Scan); también si las estadísticas están desactualizadas (se necesita `ANALYZE`).
Archivo: `docs/rendimiento.md:8`, `docs/rendimiento/experimentos/03_indice_no_usado.sql`.

**P8. ¿Qué recorridos se observan en los planes?**
R: `Seq Scan` (C7, C4 antes), `Index Only Scan` (C1 después, C3 parcial), `Bitmap Index Scan` + `Bitmap Heap Scan` (C2, C5), `Index Scan Backward` (C6 precio vigente).
Archivo: `docs/rendimiento.md:4`, planes en `docs/rendimiento/planes/`.

**P9. ¿Cuál es el costo de escritura de los índices?**
R: Carga de comprobantes ~7 veces más lenta con índices; venta por `fn_registrar_venta` +35 % (1,19 → 1,61 ms por venta). Espacio: ~15,8 MB nuevos.
Archivo: `docs/rendimiento.md:9`.

**P10. ¿Qué índices se evaluaron y descartaron, y por qué?**
R: BRIN sobre `fecha` (correlación −0,005, no descarta nada); Hash sobre `id_cliente` (más grande que B-tree y no sirve para rango); índice de expresión por mes (`date_trunc` sobre `TIMESTAMPTZ` es `STABLE`, no `IMMUTABLE`).
Archivo: `docs/rendimiento.md:6`.

**P11. ¿Por qué se decidió NO materializar `v_ventas_mensuales_sala`?**
R: Las consultas típicas ya resuelven en 5,7-76,2 ms con la vista convencional; materializar introduce datos obsoletos entre refrescos y ~182 ms de costo por refresco en el camino de venta, sin consumidor de alta frecuencia.
Archivo: `docs/rendimiento.md:13`.

**P12. ¿Cómo se mide el rendimiento y dónde están los resultados?**
R: `db/perf/medir.sh` ejecuta `ANALYZE` y 5 repeticiones con `EXPLAIN (ANALYZE, BUFFERS)`, informa la mediana y guarda planes en `docs/rendimiento/planes/` y métricas en `resultados_antes.csv` / `resultados_despues.csv`.
Archivo: `db/perf/medir.sh`, `docs/rendimiento.md`.

---

## Desafíos prácticos de defensa

**D1. ¿Cómo verificarías que no se puede vender sin stock?**
Comando (como propietario, dentro de transacción revertida):
```sql
BEGIN;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala) VALUES (910002, 910001, 910001);
-- stock de vino 910001 en sala 910001 es 3
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910002, 910001, 50);
-- ERROR: RN-09: stock insuficiente del vino 910001 en la sala 910001.
SELECT fn_stock_sala(910001, 910001); -- espera 3 (sin cambios)
ROLLBACK;
```
Resultado esperado: error `P0001` con `RN-09`, y el stock permanece en 3 sin cabecera ni renglones.
Archivo: `db/tests/004_reglas_negocio.sql:373-384`.

**D2. ¿Qué ocurre si dos usuarios intentan vender la última botella?**
Comando en dos sesiones psql con la cuenta de la API:
```sql
-- Sesión A
BEGIN;
SELECT fn_registrar_venta(990001, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]); -- OK
COMMIT;
-- Sesión B (ejecutada mientras A está abierta)
BEGIN;
SELECT fn_registrar_venta(990002, 990001, ARRAY[990001]::BIGINT[], ARRAY[1]);
-- queda esperando hasta COMMIT de A, luego:
-- ERROR: RN-09: stock insuficiente del vino 990001 en la sala 990001.
ROLLBACK;
```
Resultado esperado: B espera, recibe `RN-09`, stock final 0, sin comprobante de B.
Archivo: `docs/concurrencia.md:133-153`.

**D3. ¿Cómo comprobarías una clave foránea?**
Comando:
```sql
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES ('Otra','9','lunes',999999);
-- ERROR: 23503 en fk_sala_venta_localidad (localidad inexistente)
```
Resultado esperado: error de integridad referencial `23503` en la restricción `fk_sala_venta_localidad`.
Archivo: `db/migrations/001_esquema.sql:53-59`, `db/tests/002_esquema_y_restricciones.sql:128-131`.

**D4. ¿Cómo ejecutarías las migraciones desde cero?**
Comando:
```bash
docker compose up --build -d   # levanta db, migra como propietario, arranca api y front
```
O manual:
```bash
docker compose exec db /opt/bodegas/db/migrate.sh
```
Resultado esperado: `migrate` aplica 001 a 008 con código 0 y omite las ya aplicadas en siguientes ejecuciones.
Archivo: `db/migrate.sh`, `db/migrations/README.md`, `README.md`.

**D5. ¿Cómo analizarías una consulta lenta?**
Comando:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT r.cod_vino, count(*)
FROM bodegas.renglon_comprobante r
JOIN bodegas.comprobante c ON c.nro_comprobante = r.nro_comprobante
WHERE r.cod_vino = 1
GROUP BY r.cod_vino;
```
Resultado esperado: plan con `Bitmap Index Scan` sobre `idx_renglon_comprobante_cod_vino` y `Index Only Scan` sobre `pk_comprobante`; tiempo de ejecución en ms.
Archivo: `db/migrations/008_indices.sql:52-54`, verificación ejecutada en esta sesión.

**D6. ¿Cómo justificarías un índice?**
Con una medición `EXPLAIN (ANALYZE, BUFFERS)` antes y después, reportando mediana de repeticiones, tipo de recorrido, filas y buffers. Ejemplo: `idx_comprobante_id_cliente` reduce el control de `fk_comprobante_cliente` de 3.620 ms a 53,6 ms.
Archivo: `docs/rendimiento.md:4`, `docs/rendimiento/resultados_antes.csv`, `docs/rendimiento/resultados_despues.csv`.

**D7. ¿Cómo modificarías una regla de negocio?**
En una migración nueva (`009_*.sql`, nunca modificar una aplicada), ajustando el trigger o `CHECK` correspondiente y agregando el caso de prueba en `db/tests/004_reglas_negocio.sql`, todo dentro de una transacción revertida.
Archivo: `db/migrations/README.md`, `AGENTS.md` (migraciones).

**D8. ¿Cómo verificarías que una transacción se revierte correctamente?**
Comando:
```sql
BEGIN;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala) VALUES (910002, 910001, 910001);
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910002, 910001, 50);
-- ERROR: RN-09 (revierte todo)
ROLLBACK;
SELECT count(*) FROM comprobante WHERE nro_comprobante = 910002; -- espera 0
```
Resultado esperado: tras el error y `ROLLBACK`, no queda ni la cabecera ni los renglones.
Archivo: `db/tests/004_reglas_negocio.sql:373-384`.

---

## Validación de la documentación

- Todas las respuestas fueron contrastadas con el código real del repositorio (`db/migrations/`, `db/tests/`, `docs/`, `consultas/`).
- Los ejemplos SQL son compatibles con PostgreSQL 16 y se ejecutaron contra la base levantada en esta sesión.
- Las referencias a archivos (`db/migrations/001_esquema.sql`, `005_triggers.sql`, `008_indices.sql`, `db/tests/004_reglas_negocio.sql`, `docs/concurrencia.md`, `docs/rendimiento.md`, `consultas/select.sql`) existen en el repositorio.
- No hay contradicciones entre etapas; los ejemplos no dependen de datos que no existan sin indicarlo (los ids de ejemplo `910001`, `990001` son de las pruebas de reglas de negocio y de concurrencia respectivamente).

## Cantidad de preguntas por etapa

- Introducción: contextual, sin conteo de preguntas.
- Etapa 1: 12 preguntas (P1-P12).
- Etapa 2: 12 preguntas (P1-P12).
- Etapa 3: 8 preguntas (P1-P8).
- Etapa 4: 12 preguntas (P1-P12).
- Desafíos prácticos: 8 desafíos (D1-D8).

Total: 52 preguntas/desafíos.

---

## Estado de los comentarios de revisión de Pull Requests

Los cinco comentarios de revisión fueron preparados localmente en `docs/revision_pr/` y no se publicaron en GitHub porque no se encontró `GH_TOKEN` configurado en el entorno (no hay herramienta autorizada para comentar en los PR):

1. `comentario_PR1_etapa1_modelado.md` — PR #1 (Etapa 1).
2. `comentario_PR2_etapa2_logica_integridad.md` — PR #2 (Etapa 2: integridad y lógica).
3. `comentario_PR3_etapa2_venta_confirmada_no_se_reabre.md` — PR #3 (Etapa 2: venta confirmada no se reabre).
4. `comentario_PR4_etapa3_carga_masiva.md` — PR #4 (Etapa 3: carga masiva).
5. `comentario_PR5_etapa4_indices_rendimiento.md` — PR #5 (Etapa 4: índices y rendimiento).

Cada comentario incluye: parte del código revisada, verificaciones realizadas, decisiones técnicas, dudas/mejoras y aspectos para la defensa. Quedan listos para publicación manual en los PR correspondientes.
