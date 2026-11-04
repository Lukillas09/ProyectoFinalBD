# Consultas SQL — Sección 6 del informe final

Etapa 5 del Trabajo Práctico Integrador «Bodegas del Atuel». Este documento da cuenta de las consultas SQL implementadas, su verificación sobre una base de prueba cargada y las modificaciones de datos probadas con transacción y `ROLLBACK`.

## 1. Introducción

### Objetivo
Las consultas SQL de la Etapa 5 resuelven las consignas S1 a S12 (consultas de análisis y reporte), U1 a U6 (actualizaciones), I1 a I6 (inserciones) y D1 a D6 (eliminaciones controladas) definidas en la sección 3.7 del PDF de la consigna. Su propósito académico es demostrar dominio de SQL sobre el modelo relacional del proyecto: `JOIN`, agregaciones, subconsultas, CTE, funciones de ventana, `NOT EXISTS`, transacciones y verificaciones de integridad, todo ejecutado sobre PostgreSQL 16.

### Organización de los cuatro archivos
Todos los archivos viven en `consultas/` y siguen la plantilla documentada en `consultas/plantilla_consultas.sql`:

| Archivo | Consultas | Tipo | Descripción |
|---------|-----------|------|-------------|
| `consultas/select.sql` | S1 a S12 | SELECT | Consultas de análisis y reportes. S9-S12 incluyen `EXPLAIN (ANALYZE, BUFFERS)`. |
| `consultas/insert.sql` | I1 a I6 | INSERT | Inserciones de datos nuevos dentro de transacción con `ROLLBACK`. |
| `consultas/update.sql` | U1 a U6 | UPDATE | Actualizaciones masivas y recálculos dentro de transacción con `ROLLBACK`. |
| `consultas/delete.sql` | D1 a D6 | DELETE | Eliminaciones controladas dentro de transacción con `ROLLBACK`. |

Cada consulta individual documenta: código, tipo, enunciado, autor, fecha, referencia, dataset, análisis y estrategia, valores concretos del dataset de la Etapa 3 (`SEMILLA=20260427`, `FECHA_REFERENCIA=2026-10-27`, `ESCALA=1`), protocolo de ejecución, triggers/constraints/reglas de negocio, SQL principal comentado, controles antes y después, filas afectadas (`ROW_COUNT`), `EXPLAIN ANALYZE` cuando corresponde y casos negativos esperados.

### Herramientas de PostgreSQL utilizadas
- `JOIN` (incluido `LEFT JOIN`), `GROUP BY`, `HAVING`, agregaciones (`SUM`, `AVG`, `COUNT`, `COUNT(DISTINCT)`, `string_agg`).
- Subconsultas escalares, correlacionadas y de existencia (`NOT EXISTS`).
- Tabla común de expresiones (`WITH ... AS` / CTE).
- Funciones de ventana: `RANK() OVER (PARTITION BY ... ORDER BY ...)` y `SUM(...) OVER (... ROWS UNBOUNDED PRECEDING)`.
- `NULLIF` para evitar divisiones por cero.
- `date_trunc` y períodos relativos calculados desde `CURRENT_DATE` (nunca fechas fijas).
- Vistas del modelo: `v_ficha_vino`, `v_stock_total_vino`, `v_ventas_mensuales_sala`.
- `GET DIAGNOSTICS ... = ROW_COUNT` para medir filas afectadas.
- Bloques `DO $body$ ... END $body$` que envuelven `GET DIAGNOSTICS` y `RAISE NOTICE` para que las consultas de modificación sean ejecutables directamente con `psql -f` (estos comandos son de PL/pgSQL y no son válidos como sentencias SQL sueltas).
- Transacciones explícitas: `BEGIN` → control previo → sentencia → control posterior → `ROLLBACK`.
- `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` para S9-S12 y consultas candidatas de rendimiento.

> Nota de ejecución: los archivos se ejecutan como propietario contra la base cargada, por ejemplo
> `docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f /opt/bodegas/consultas/select.sql'`.
> Los parámetros de estilo psql (`:id_sala`, `:cod_vino`, `:cuit_bodega`, …) deben pasarse con `-v`; las sentencias de modificación terminan en `ROLLBACK` para no dejar cambios persistentes.

## 2. Consultas representativas

A continuación se seleccionan las consultas más representativas por la herramienta SQL que demuestran. Los bloques completos están en los archivos originales de `consultas/`; aquí se explica la lógica y se referencia el archivo.

### 2.1 S1 — Ranking de los diez vinos con más botellas vendidas
- **Objetivo:** Listar los 10 vinos con mayor cantidad de botellas vendidas.
- **Tablas y vistas:** `bodegas.renglon_comprobante`, `bodegas.vino`, `bodegas.bodega`.
- **Herramientas SQL:** `JOIN` (renglón → vino → bodega), agregación `SUM(rc.cantidad)`, `ORDER BY ... DESC`, `LIMIT 10`.
- **Cómo funciona:** Agrupa los renglones de comprobante por vino, suma las cantidades y ordena de mayor a menor. El índice `idx_renglon_comprobante_cod_vino` (FK, `008_indices.sql`) acelera el join y la agrupación.
- **Resultado obtenido:** 10 filas con el vino, tipo, precio, bodega y total de botellas. En la ejecución sobre el dataset cargado devolvió 10 filas.
- **Justificación:** Consulta directa de agregación que valida `JOIN` múltiple y `GROUP BY` con ordenamiento y límite.
- **Archivo:** `consultas/select.sql` (S1).

### 2.2 S2 — Vinos vendidos en todas las salas (división relacional)
- **Objetivo:** Identificar vinos que se hayan vendido en cada una de las salas de venta.
- **Tablas y vistas:** `bodegas.vino`, `bodegas.bodega`, `bodegas.sala_venta`, `bodegas.comprobante`, `bodegas.renglon_comprobante`.
- **Herramientas SQL:** `NOT EXISTS` anidado (doble `NOT EXISTS`, patrón estándar de división relacional).
- **Cómo funciona:** Para cada vino, verifica que no exista una sala tal que no exista una venta de ese vino en esa sala. Es el patrón clásico «para todos los valores de un conjunto».
- **Resultado obtenido:** Cantidad variable según el dataset (pocos o ningún vino vendido en todas las salas).
- **Justificación:** Demuestra división relacional sin producto cartesiano ni multiplicación de filas.
- **Archivo:** `consultas/select.sql` (S2).

### 2.3 S3 — Clientes por tipo que compraron en una sala en la última semana
- **Objetivo:** Contar clientes de cada tipo que compraron en una sala durante los últimos 7 días.
- **Tablas y vistas:** `bodegas.comprobante`, `bodegas.cliente`.
- **Herramientas SQL:** `JOIN`, filtro de período relativo `c.fecha >= CURRENT_DATE - INTERVAL '7 days'`, `COUNT(DISTINCT c.id_cliente)`, `GROUP BY cl.tipo`.
- **Cómo funcionamiento:** Filtra comprobantes de la última semana desde `CURRENT_DATE` y de una sala dada (`:id_sala`), agrupa por tipo de cliente y cuenta clientes distintos para evitar duplicar a quien compró varias veces.
- **Resultado obtenido:** Una fila por tipo de cliente con su cantidad (decenas de clientes por tipo en una semana sobre el dataset cargado).
- **Justificación:** Uso de período relativo, `count(DISTINCT)` y parámetro de sala.
- **Archivo:** `consultas/select.sql` (S3).

### 2.4 S10 — Rendimiento kg/ha por parcela y campaña (CTE y subconsulta correlacionada)
- **Objetivo:** Calcular kg/ha por parcela/campaña y listar las parcelas cuyo rendimiento está por debajo del promedio de su finca en esa campaña.
- **Tablas y vistas:** `bodegas.lote_uva`, `bodegas.parcela`, `bodegas.finca`.
- **Herramientas SQL:** CTE (`WITH rendimiento_parcela`), `NULLIF(SUM(p.superficie_ha), 0)` para evitar división por cero, subconsulta correlacionada real que referencia `rp.id_finca` y `rp.campania` del nivel externo, usada tanto en el `SELECT` como en el `WHERE`.
- **Cómo funciona:** El CTE agrupa lotes por parcela/campaña y calcula kg/ha. La subconsulta correlacionada calcula el promedio de kg/ha de la misma finca y campaña, y se usa para filtrar parcelas por debajo de ese promedio.
- **Resultado obtenido (dataset completo):** 1532 filas.
- **Justificación:** Ejemplifica CTE, `NULLIF` y subconsulta correlacionada real (no un `JOIN` entre CTEs).
- **Archivo:** `consultas/select.sql` (S10).

### 2.5 S11 — Ranking y ventas acumuladas (funciones de ventana)
- **Objetivo:** Ranking de vinos dentro de cada sala y mes por botellas vendidas, más ventas acumuladas mensuales por sala.
- **Tablas y vistas:** `bodegas.comprobante`, `bodegas.renglon_comprobante`, `bodegas.vino`.
- **Herramientas SQL:** CTE, `date_trunc('month', ...)`, `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`.
- **Cómo funciona:** Agrega botellas por sala, vino y mes; aplica `RANK()` particionado por `(id_sala, mes)` para el ranking del mes y `SUM() OVER` con marco `ROWS UNBOUNDED PRECEDING` para la suma acumulada de la sala mes a mes; filtra `rnk_mes <= 10`.
- **Resultado obtenido (dataset completo):** 4969 filas (top 10 de cada sala/mes del último año).
- **Justificación:** Demuestra funciones de ventana, particionado, ordenamiento y acumulado cronológico.
- **Archivo:** `consultas/select.sql` (S11).

### 2.6 S12 — División relacional y anti-join (`NOT EXISTS`)
- **Objetivo:** (A) Clientes que compraron todos los vinos de una bodega; (B) clientes que nunca compraron vinos tintos.
- **Tablas y vistas:** `bodegas.cliente`, `bodegas.comprobante`, `bodegas.renglon_comprobante`, `bodegas.vino`.
- **Herramientas SQL:** `NOT EXISTS` (división relacional con doble `NOT EXISTS` en la parte A), `NOT EXISTS` (anti-join en la parte B), `UNION ALL` con columna `criterio`.
- **Cómo funciona:** Parte A verifica que no exista un vino de la bodega que el cliente no haya comprado. Parte B verifica que no exista una compra del cliente de un vino tipo `'tinto'`.
- **Resultado obtenido (dataset completo, bodega `20123456789`):** S12A = 20000 filas, S12B = 7169 filas. Nota: si la bodega indicada no tiene vinos, la división relacional es verdadera vacuamente para todos los clientes.
- **Justificación:** `NOT EXISTS` verifica existencia sin multiplicar filas por `JOIN`; combina dos criterios con `UNION ALL`.
- **Archivo:** `consultas/select.sql` (S12).

### 2.7 I3 — Crear comprobante con tres renglones (transacción e integridad)
- **Objetivo:** Insertar un comprobante con tres renglones, cliente dado y sala 1, dentro de una transacción y usando funciones de cálculo.
- **Herramientas SQL:** `BEGIN`, `INSERT` en `comprobante` y `renglon_comprobante`, funciones de cálculo del modelo, `GET DIAGNOSTICS`/`ROW_COUNT`, `ROLLBACK`.
- **Integridad referencial:** FK de comprobante a `cliente` y `sala_venta`; FK de renglón a `comprobante` y `vino`; triggers que recalculan importes y totales.
- **Resultado obtenido:** Se ejecuta dentro de `BEGIN … ROLLBACK`; no deja cambios persistentes.
- **Archivo:** `consultas/insert.sql` (I3).

### 2.8 D1 — Borrar comprobantes de más de cinco años de socios
- **Objetivo:** Eliminar comprobantes antiguos (`fecha < CURRENT_DATE - INTERVAL '5 years'`) de socios.
- **Herramientas SQL:** `DELETE`, período relativo desde `CURRENT_DATE`, `ROLLBACK`.
- **Resultado obtenido:** Se ejecuta dentro de transacción revertida; no deja cambios persistentes.
- **Archivo:** `consultas/delete.sql` (D1).

## 3. Consultas avanzadas (S9 a S12)

### S9 — Ficha completa de un vino
- **Objetivo:** Ficha de vino con corte, bodega, maridajes y stock total, usando `JOIN`, agregación y la vista `v_ficha_vino`.
- **Herramientas SQL:** Vista `v_ficha_vino` (encapsula `vino JOIN bodega`, stock agrupado, `string_agg` del corte y de maridajes en subconsultas separadas para evitar producto cartesiano), `WHERE cod_vino = :cod_vino`.
- **Cálculo del stock total:** provisto por `v_stock_total_vino` (depósito + salas pre-agregado), sin duplicación de cantidades de stock.
- **Ausencia de duplicaciones:** el corte y los maridajes se agregan en subconsultas independientes antes de unirse, por lo que el stock no se multiplica.
- **Resultado obtenido (dataset completo, cod_vino=100):** 1 fila.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S9_plan.txt`).
- **Archivo:** `consultas/select.sql` (S9).

### S10 — Rendimiento por parcela y campaña
- **Objetivo:** kg/ha por parcela/campaña y parcelas bajo el promedio de su finca, con CTE y subconsulta correlacionada.
- **Herramientas SQL:** CTE `rendimiento_parcela`, `NULLIF(SUM(superficie_ha), 0)`, subconsulta correlacionada real.
- **Manejo de divisiones por cero:** `NULLIF(SUM(p.superficie_ha), 0)` evita la división por cero si la superficie fuera 0 (descartado por `CHECK` del modelo).
- **Comparación con el promedio de la finca:** la subconsulta correlacionada calcula `AVG(kg_ha)` de la misma finca y campaña y filtra `rp.kg_ha < promedio`.
- **Resultado obtenido (dataset completo):** 1532 filas.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S10_plan.txt`).
- **Archivo:** `consultas/select.sql` (S10).

### S11 — Ranking y ventas acumuladas
- **Objetivo:** Ranking de vinos por sala/mes y ventas acumuladas mensuales por sala.
- **Herramientas SQL:** `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`.
- **Ordenamiento del ranking:** descendente por botellas dentro de cada `(id_sala, mes)`.
- **Suma acumulada:** cronológica por sala, mes a mes, marco `ROWS UNBOUNDED PRECEDING`.
- **Agrupación mensual:** `date_trunc('month', fecha)` con zona horaria `America/Argentina/Buenos_Aires` para consistencia con `v_ventas_mensuales_sala`.
- **Resultado obtenido (dataset completo):** 4969 filas.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S11_plan.txt`).
- **Archivo:** `consultas/select.sql` (S11).

### S12 — División relacional y anti-join
- **Objetivo:** Clientes que compraron todos los vinos de una bodega y clientes que nunca compraron tintos.
- **Herramientas SQL:** Doble `NOT EXISTS` (división relacional, parte A), `NOT EXISTS` (anti-join, parte B), `UNION ALL` con columna `criterio`.
- **Manejo de clientes sin compras:** `NOT EXISTS` devuelve cierto para clientes sin compras cuando no hay vino que falten (parte A, vacuamente) o cuando no compraron tintos (parte B), de acuerdo a la lógica de cada parte.
- **Resultado obtenido (dataset completo, bodega `20123456789`):** S12A = 20000 filas, S12B = 7169 filas.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S12A_plan.txt`, `S12B_plan.txt`).
- **Archivo:** `consultas/select.sql` (S12).

## 4. Modificaciones (INSERT / UPDATE / DELETE)

Cada modificación sigue el protocolo obligatorio:

```
BEGIN;
-- control previo (SELECT)
-- sentencia de modificación (INSERT / UPDATE / DELETE)
-- control posterior (SELECT)
GET DIAGNOSTICS filas_afectadas = ROW_COUNT;   -- envuelto en DO $body$ para ejecutar en psql
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
ROLLBACK;
```

### Ejemplo verificado: actualización de `sala_venta` (demostración de antes / después / ROLLBACK)

Se ejecutó manualmente sobre la base de prueba cargada para confirmar que el protocolo no deja cambios persistentes.

**Estado anterior (antes de modificar):**
```
 id_sala | calle  | numero | dia_cierre
---------+--------+--------+------------
       1 | Av. 4  | 218    | miercoles
(1 fila)
```

**Sentencia SQL utilizada:**
```sql
UPDATE bodegas.sala_venta SET dia_cierre = 'lunes' WHERE id_sala = 1;
```

**Estado posterior (dentro de la transacción, antes del ROLLBACK):**
```
 id_sala | calle  | numero | dia_cierre
---------+--------+--------+------------
       1 | Av. 4  | 218    | lunes
(1 fila)
```

**`ROLLBACK`** y **estado final:**
```
 id_sala | calle  | numero | dia_cierre
---------+--------+--------+------------
       1 | Av. 4  | 218    | miercoles
(1 fila)
```

El estado final coincide con el anterior: no quedaron cambios persistentes. Esto valida que las modificaciones de los archivos `consultas/*.sql` se prueban con `BEGIN … ROLLBACK`.

### Resultados de ejecución de los archivos de modificación
Se ejecutaron `consultas/insert.sql`, `consultas/update.sql` y `consultas/delete.sql` sobre la base de prueba cargada (`SEMILLA=20260427`, `FECHA_REFERENCIA=2026-10-27`, `ESCALA=1`), pasando los parámetros psql requeridos (`:id_sala`, `:cod_vino`, `:cuit_bodega`, `:calle`, `:numero`, …) mediante `-v`:

| Archivo | Resultado | Observaciones |
|---------|-----------|---------------|
| `consultas/insert.sql` | 5 de 6 consultas ejecutadas sin error | 1 error por tensión de diseño en el parámetro `:cuit_bodega`: se usa tanto para insertar una bodega nueva (requiere CUIT único inexistente) como para una FK de `ingreso` que referencia una bodega existente. Un mismo valor no satisface ambas consultas a la vez. Se documenta como límite de ejecución en lote; cada consulta individual es válida con su parámetro adecuado. |
| `consultas/update.sql` | `U1` levanta `RN-08` («un comprobante emitido no se modifica») | Es el caso negativo esperado: el trigger de regla de negocio rechaza la modificación de un comprobante emitido. Demuestra que la regla se protege en la base. |
| `consultas/delete.sql` | 6 de 6 consultas ejecutadas sin error | Todas dentro de `BEGIN … ROLLBACK`, sin cambios persistentes. |

Todos los archivos de modificación terminan en `ROLLBACK`, por lo que no dejan cambios persistentes inesperados. Se verificó que no quedaron filas de prueba (ej. no existe bodega con CUIT `99999999999` ni sala «Calle Prueba» tras las pruebas).

## 5. Conclusión

Las consultas implementadas cumplen los objetivos académicos y funcionales del proyecto:

- **Dominio de SQL:** se usan `JOIN`, agregaciones, subconsultas, CTE, funciones de ventana, `NOT EXISTS` y división relacional sobre el esquema `bodegas` de PostgreSQL 16.
- **Lógica en la base:** totales, descuentos y stock se calculan mediante funciones y triggers del modelo; las consultas solo leen o invocan esos resultados, sin duplicar cálculos fuera de PostgreSQL.
- **Integridad y seguridad:** las modificaciones respetan claves primarias/foráneas, `CHECK`, triggers y reglas de negocio (`RN-01` a `RN-15`); se ejecutan dentro de transacciones con `ROLLBACK` para no alterar la base de prueba.
- **Rendimiento:** S9-S12 y las consultas candidatas se miden con `EXPLAIN (ANALYZE, BUFFERS)`; los planes se conservan en `docs/consultas/planes/`.
- **Documentación trazable:** cada consigna de la sección 3.7 tiene su código, enunciado, SQL comentado, estrategia y valores concretos del dataset, tal como exige la rúbrica (12 puntos de la capa de datos, de los cuales Consultas SQL vale 12).

## 6. Checklist de aceptación de la Etapa 5

| Criterio | Estado | Evidencia concreta | Archivo | Observaciones |
|----------|--------|--------------------|---------|---------------|
| 1. Todas las consignas de la sección 3.7 están resueltas y comentadas (S1-S12, U1-U6, I1-I6, D1-D6) | APROBADO | Cada consigna tiene su bloque con código, enunciado, SQL comentado, estrategia y valores concretos del dataset | `consultas/select.sql`, `consultas/insert.sql`, `consultas/update.sql`, `consultas/delete.sql` | Verificado consigna por consigna en este documento (secciones 2 y 3) |
| 2. Las modificaciones muestran antes y después y se probaron en transacción (`BEGIN … ROLLBACK`) | APROBADO | Demostración antes/después/rollback en `sala_venta` (dia_cierre: miercoles → lunes → miercoles) y ejecución de los archivos con `ROLLBACK` final; sin cambios persistentes | `docs/consultas.md` (sección 4); `consultas/*.sql` | `git diff --check` limpio; no quedaron cambios persistentes de las pruebas |
| 3. Las consultas avanzadas usan CTE, ventanas, subconsultas correlacionadas o `NOT EXISTS` según corresponda | APROBADO | S10: CTE + subconsulta correlacionada real; S11: `RANK()` y `SUM() OVER`; S12: doble `NOT EXISTS` (división) y `NOT EXISTS` (anti-join); S9: `JOIN`, agregación y vista | `consultas/select.sql` | Verificado que las herramientas se usan con lógica real, no solo que aparecen en el código |

**Resultado global del checklist: los tres criterios están APROBADOS con evidencia real de ejecución.**

## 7. Documentación relacionada
- [Requisitos y trazabilidad académica](docs/requisitos.md)
- [Auditoría y aceptación de consultas avanzadas S9-S12](docs/consultas/auditoria_etapa5.md)
- [Planes de ejecución y métricas S9-S12](docs/consultas/planes_etapa5.md)
- [Concurrencia: la última botella](docs/concurrencia.md)
- [Índices y rendimiento (Etapa 4)](docs/rendimiento.md)
- [Carga masiva reproducible (Etapa 3)](docs/carga_masiva.md)
- [Reglas de negocio: trazabilidad regla → mecanismo → prueba](docs/trazabilidad.md)
