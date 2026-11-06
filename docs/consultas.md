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

Cada consulta individual documenta: código, tipo, enunciado, autor, fecha, referencia, dataset, análisis y estrategia, valores concretos del dataset de la Etapa 3 (`SEMILLA=20260427`, `ESCALA=1`), protocolo de ejecución, triggers/constraints/reglas de negocio, SQL principal comentado, controles antes y después, filas afectadas (`ROW_COUNT`), `EXPLAIN ANALYZE` cuando corresponde y casos negativos esperados.

### Herramientas de PostgreSQL utilizadas
- `JOIN` (incluido `LEFT JOIN`), `GROUP BY`, `HAVING`, agregaciones (`SUM`, `AVG`, `COUNT`, `COUNT(DISTINCT)`, `string_agg`).
- Subconsultas escalares, correlacionadas y de existencia (`NOT EXISTS`).
- Tabla común de expresiones (`WITH ... AS` / CTE).
- Funciones de ventana: `RANK() OVER (PARTITION BY ... ORDER BY ...)` y `SUM(...) OVER (... ROWS UNBOUNDED PRECEDING)`.
- `NULLIF` para evitar divisiones por cero.
- `date_trunc` y períodos relativos calculados desde `CURRENT_DATE` (nunca fechas fijas).
- Vistas del modelo: `v_ficha_vino`, `v_stock_total_vino`, `v_ventas_mensuales_sala`.
- Variable `:ROW_COUNT` de psql (`\echo 'Filas afectadas (Xn):' :ROW_COUNT`) para informar las filas de la sentencia principal. La versión anterior usaba `GET DIAGNOSTICS` dentro de un bloque `DO` nuevo, que siempre informaba 0 porque no veía la sentencia anterior.
- Transacciones explícitas: `BEGIN` → control previo → sentencia → control posterior → `ROLLBACK`, una por consulta de modificación.
- `EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)` para S9-S12.

> **Ejecución.** Cada archivo se ejecuta como propietario, dentro del contenedor `db`, con `consultas/ejecutar.sh`. El script usa `ON_ERROR_STOP=1` y termina con código distinto de 0 si alguna sentencia falla:
>
> ```bash
> docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
> docker compose exec db /opt/bodegas/consultas/ejecutar.sh update.sql -v cuit_bodega=33532580264
> ```
>
> Cada archivo define al comienzo todos sus parámetros, con un valor por omisión tomado de la carga (`\if :{?id_sala} \else \set id_sala 1 \endif`). Cualquiera se reemplaza con `-v`.
>
> - Los valores fijos son identificadores de catálogo que no dependen de `FECHA_REFERENCIA`: sala, vino, bodega, localidad.
> - Los que dependen de la historia simulada se eligen al ejecutar con `\gset`: el primer socio (I3), los vinos con stock en la sala 1 (I3) y el vino transferido a más salas en los últimos 15 días (S4).
>
> Los tipos de cliente, por ejemplo, cambian con `FECHA_REFERENCIA`: el cliente 1 es socio con la carga del 2026-10-27 y distribuidor con la del 2026-11-05.

## 2. Consultas representativas

A continuación se seleccionan las consultas más representativas por la herramienta SQL que demuestran. Los bloques completos están en los archivos originales de `consultas/`; aquí se explica la lógica y se referencia el archivo.

### 2.1 S1 — Ranking de los diez vinos con más botellas vendidas
- **Objetivo:** Listar los 10 vinos con mayor cantidad de botellas vendidas.
- **Tablas y vistas:** `bodegas.renglon_comprobante`, `bodegas.vino`, `bodegas.bodega`.
- **Herramientas SQL:** `JOIN` (renglón → vino → bodega), agregación `SUM(rc.cantidad)`, `ORDER BY ... DESC`, `LIMIT 10`.
- **Cómo funciona:** Agrupa los renglones de comprobante por vino, suma las cantidades y ordena de mayor a menor. El índice `idx_renglon_comprobante_cod_vino` (FK, `008_indices.sql`) acelera el join y la agrupación.
- **Resultado obtenido (carga del 2026-11-05):** 10 filas con el vino, tipo, precio, bodega y total de botellas.
- **Justificación:** Consulta directa de agregación que valida `JOIN` múltiple y `GROUP BY` con ordenamiento y límite.
- **Archivo:** `consultas/select.sql` (S1).

### 2.2 S2 — Vinos vendidos en todas las salas (división relacional)
- **Objetivo:** Identificar vinos que se hayan vendido en cada una de las salas de venta.
- **Tablas y vistas:** `bodegas.vino`, `bodegas.bodega`, `bodegas.sala_venta`, `bodegas.comprobante`, `bodegas.renglon_comprobante`.
- **Herramientas SQL:** `NOT EXISTS` anidado (doble `NOT EXISTS`, patrón estándar de división relacional).
- **Cómo funciona:** Para cada vino, verifica que no exista una sala tal que no exista una venta de ese vino en esa sala. Es el patrón clásico «para todos los valores de un conjunto».
- **Resultado obtenido (carga del 2026-11-05):** 20 vinos, los 20 "vinos de línea" que la carga garantiza en las 40 salas.
- **Justificación:** Demuestra división relacional sin producto cartesiano ni multiplicación de filas.
- **Archivo:** `consultas/select.sql` (S2).

### 2.3 S3 — Clientes por tipo que compraron en una sala en la última semana
- **Objetivo:** Contar clientes de cada tipo que compraron en una sala durante los últimos 7 días.
- **Tablas y vistas:** `bodegas.comprobante`, `bodegas.cliente`.
- **Herramientas SQL:** `JOIN`, filtro de período relativo `c.fecha >= CURRENT_DATE - INTERVAL '7 days'`, `COUNT(DISTINCT c.id_cliente)`, `GROUP BY cl.tipo`.
- **Cómo funciona:** Filtra comprobantes de la última semana desde `CURRENT_DATE` y de una sala dada (`:id_sala`), agrupa por tipo de cliente y cuenta clientes distintos para evitar duplicar a quien compró varias veces.
- **Resultado obtenido (carga del 2026-11-05, sala 1):** 3 filas, una por tipo de cliente. Con la carga del 2026-10-27, ejecutada el 2026-11-05, devuelve 0 filas: la última semana de `CURRENT_DATE` cae después del final de la historia.
- **Justificación:** Uso de período relativo, `count(DISTINCT)` y parámetro de sala.
- **Archivo:** `consultas/select.sql` (S3).

### 2.4 S10 — Rendimiento kg/ha por parcela y campaña (CTE y subconsulta correlacionada)
- **Objetivo:** Calcular kg/ha por parcela/campaña y listar las parcelas cuyo rendimiento está por debajo del promedio de su finca en esa campaña.
- **Tablas y vistas:** `bodegas.lote_uva`, `bodegas.parcela`, `bodegas.finca`.
- **Herramientas SQL:** CTE (`WITH rendimiento_parcela`), `NULLIF(SUM(p.superficie_ha), 0)` para evitar división por cero, subconsulta correlacionada real que referencia `rp.id_finca` y `rp.campania` del nivel externo, usada tanto en el `SELECT` como en el `WHERE`.
- **Cómo funciona:** El CTE agrupa lotes por parcela/campaña y calcula kg/ha. La subconsulta correlacionada calcula el promedio de kg/ha de la misma finca y campaña, y se usa para filtrar parcelas por debajo de ese promedio.
- **Resultado obtenido (carga del 2026-11-05):** 1.597 filas.
- **Justificación:** Ejemplifica CTE, `NULLIF` y subconsulta correlacionada real (no un `JOIN` entre CTEs).
- **Archivo:** `consultas/select.sql` (S10).

### 2.5 S11 — Ranking y ventas acumuladas (funciones de ventana)
- **Objetivo:** Ranking de vinos dentro de cada sala y mes por botellas vendidas, más ventas acumuladas mensuales por sala.
- **Tablas y vistas:** `bodegas.comprobante`, `bodegas.renglon_comprobante`, `bodegas.vino`.
- **Herramientas SQL:** CTE, `date_trunc('month', ...)`, `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`.
- **Cómo funciona:** Agrega botellas por sala, vino y mes; aplica `RANK()` particionado por `(id_sala, mes)` para el ranking del mes y `SUM() OVER` con marco `ROWS UNBOUNDED PRECEDING` para la suma acumulada de la sala mes a mes; filtra `rnk_mes <= 10`.
- **Resultado obtenido (carga del 2026-11-05):** 5.434 filas (top 10 de cada sala y mes del último año).
- **Justificación:** Demuestra funciones de ventana, particionado, ordenamiento y acumulado cronológico.
- **Archivo:** `consultas/select.sql` (S11).

### 2.6 S12 — División relacional y anti-join (`NOT EXISTS`)
- **Objetivo:** (A) Clientes que compraron todos los vinos de una bodega; (B) clientes que nunca compraron vinos tintos.
- **Tablas y vistas:** `bodegas.cliente`, `bodegas.comprobante`, `bodegas.renglon_comprobante`, `bodegas.vino`.
- **Herramientas SQL:** `NOT EXISTS` (división relacional con doble `NOT EXISTS` en la parte A), `NOT EXISTS` (anti-join en la parte B), `UNION ALL` con columna `criterio`.
- **Cómo funciona:** Parte A verifica que no exista un vino de la bodega que el cliente no haya comprado. Parte B verifica que no exista una compra del cliente de un vino tipo `'tinto'`.
- **Resultado obtenido (carga del 2026-11-05, bodega `30555408710`):** S12A da 2.663 clientes y S12B 7.170. Si la bodega no tiene vinos, la división relacional es verdadera vacuamente para todos los clientes: pasaba con el CUIT inexistente `20123456789` de la versión anterior.
- **Justificación:** `NOT EXISTS` verifica existencia sin multiplicar filas por `JOIN`; combina dos criterios con `UNION ALL`.
- **Archivo:** `consultas/select.sql` (S12).

### 2.7 I3 — Crear comprobante con tres renglones (transacción e integridad)
- **Objetivo:** Insertar un comprobante con tres renglones, cliente dado y sala 1, dentro de una transacción y usando funciones de cálculo.
- **Herramientas SQL:** `BEGIN`, `fn_registrar_venta(cliente, sala, vinos[], cantidades[])`, que inserta cabecera y renglones; los triggers completan precio, descuento y subtotal, descuentan stock y recalculan la cabecera. Después, `ROLLBACK`.
- **Integridad referencial:** FK de comprobante a `cliente` y `sala_venta`; FK de renglón a `comprobante` y `vino`; triggers que recalculan importes y totales.
- **Resultado obtenido (carga del 2026-11-05):** un comprobante nuevo del socio 2 (descuento 10 %) en la sala 1 (el 150.340 en esa corrida: la secuencia avanza aunque haya `ROLLBACK`), con 3 renglones de 1, 2 y 3 botellas, dentro de `BEGIN … ROLLBACK`.
- **Archivo:** `consultas/insert.sql` (I3).

### 2.8 D1 — Borrar comprobantes de más de cinco años de socios
- **Objetivo:** Eliminar comprobantes antiguos (`fecha < CURRENT_DATE - INTERVAL '5 years'`) de socios.
- **Herramientas SQL:** `DELETE`, período relativo desde `CURRENT_DATE`, `ROLLBACK`.
- **Resultado obtenido (carga del 2026-11-05):** borra 11.815 comprobantes y 42.330 renglones dentro de la transacción revertida (ver la tabla de la sección 4).
- **Archivo:** `consultas/delete.sql` (D1).

## 3. Consultas avanzadas (S9 a S12)

### S9 — Ficha completa de un vino
- **Objetivo:** Ficha de vino con corte, bodega, maridajes y stock total, usando `JOIN`, agregación y la vista `v_ficha_vino`.
- **Herramientas SQL:** Vista `v_ficha_vino` (encapsula `vino JOIN bodega`, stock agrupado, `string_agg` del corte y de maridajes en subconsultas separadas para evitar producto cartesiano), `WHERE cod_vino = :cod_vino`.
- **Cálculo del stock total:** provisto por `v_stock_total_vino` (depósito + salas pre-agregado), sin duplicación de cantidades de stock.
- **Ausencia de duplicaciones:** el corte y los maridajes se agregan en subconsultas independientes antes de unirse, por lo que el stock no se multiplica.
- **Resultado obtenido (carga del 2026-11-05, `cod_vino = 1`):** 1 fila.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S9_plan.txt`).
- **Archivo:** `consultas/select.sql` (S9).

### S10 — Rendimiento por parcela y campaña
- **Objetivo:** kg/ha por parcela/campaña y parcelas bajo el promedio de su finca, con CTE y subconsulta correlacionada.
- **Herramientas SQL:** CTE `rendimiento_parcela`, `NULLIF(SUM(superficie_ha), 0)`, subconsulta correlacionada real.
- **Manejo de divisiones por cero:** `NULLIF(SUM(p.superficie_ha), 0)` evita la división por cero si la superficie fuera 0 (descartado por `CHECK` del modelo).
- **Comparación con el promedio de la finca:** la subconsulta correlacionada calcula `AVG(kg_ha)` de la misma finca y campaña y filtra `rp.kg_ha < promedio`.
- **Resultado obtenido (carga del 2026-11-05):** 1.597 filas, en 568,6 ms. La subconsulta correlacionada sobre el CTE se ejecuta 3.201 veces (`docs/consultas/planes_etapa5.md`).
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S10_plan.txt`).
- **Archivo:** `consultas/select.sql` (S10).

### S11 — Ranking y ventas acumuladas
- **Objetivo:** Ranking de vinos por sala/mes y ventas acumuladas mensuales por sala.
- **Herramientas SQL:** `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`.
- **Ordenamiento del ranking:** descendente por botellas dentro de cada `(id_sala, mes)`.
- **Suma acumulada:** cronológica por sala, mes a mes, marco `ROWS UNBOUNDED PRECEDING`.
- **Agrupación mensual:** `date_trunc('month', fecha)` con zona horaria `America/Argentina/Buenos_Aires` para consistencia con `v_ventas_mensuales_sala`.
- **Resultado obtenido (carga del 2026-11-05):** 5.434 filas.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S11_plan.txt`).
- **Archivo:** `consultas/select.sql` (S11).

### S12 — División relacional y anti-join
- **Objetivo:** Clientes que compraron todos los vinos de una bodega y clientes que nunca compraron tintos.
- **Herramientas SQL:** Doble `NOT EXISTS` (división relacional, parte A), `NOT EXISTS` (anti-join, parte B), `UNION ALL` con columna `criterio`.
- **Manejo de clientes sin compras:**
  - En la parte A, la doble negación es verdadera "vacuamente" si la bodega no tiene vinos: devolvería los 20.000 clientes. Eso pasaba con la versión anterior, que usaba el CUIT inexistente `20123456789`. Ahora el parámetro por omisión es una bodega real.
  - En la parte B, los clientes sin ninguna compra también "nunca compraron tintos".
- **Resultado obtenido (carga del 2026-11-05, bodega `30555408710`, 3 vinos):** 9.833 filas. S12A da 2.663 clientes que compraron los tres vinos. S12B da 7.170 clientes, de los que 4.715 no tienen ninguna compra y 2.455 compraron pero nunca un tinto.
- **`EXPLAIN (ANALYZE)`:** incluido y ejecutado sin errores (ver `docs/consultas/planes/S12A_plan.txt`, `S12B_plan.txt`).
- **Archivo:** `consultas/select.sql` (S12).

## 4. Ejecución y verificación

### 4.1 Protocolo de cada modificación

```
\echo '>>> Xn'
BEGIN;
-- control previo (SELECT)
-- sentencia principal (INSERT / UPDATE / DELETE, o la función que la hace)
\echo 'Filas afectadas (Xn):' :ROW_COUNT
-- control posterior (SELECT)
ROLLBACK;
```

Cada consulta de modificación está en su propia transacción revertida. Con `ON_ERROR_STOP=1`, un error corta el archivo, y `ejecutar.sh` devuelve el código de psql.

Ejemplo real, U4, que intercambia lunes y miércoles en una sola sentencia:

```
 dia_cierre | cantidad          UPDATE 23                    dia_cierre | cantidad
 lunes      |       11          Filas afectadas (U4): 23     lunes      |       12
 miercoles  |       12                                       miercoles  |       11
```

### 4.2 Resultado (2026-11-05)

Base cargada desde un volumen vacío con `SEMILLA=20260427`, `ESCALA=1` y `FECHA_REFERENCIA=2026-11-05`, igual a la fecha de ejecución. `controles.sql` dio 0. Se ejecutaron los cuatro archivos con `ejecutar.sh` y los parámetros por omisión, y se tomaron las huellas de `db/seed/hashes.sql` antes y después.

| Archivo | Código de salida | Tiempo | Huellas de las 30 tablas |
|---|---:|---:|---|
| `select.sql` | 0 | 5 s | sin cambios |
| `insert.sql` | 0 | < 1 s | sin cambios |
| `update.sql` | 0 | 17 s (U1: ~16 s) | sin cambios |
| `delete.sql` | 0 | 2 s | sin cambios |

Filas devueltas (S) o afectadas por la sentencia principal (I, U, D):

| Consulta | Filas | Consulta | Filas | Consulta | Filas |
|---|---:|---|---:|---|---:|
| S1 | 10 | I1 | 1 | U1 | 150.338 comprobantes recalculados, 0 importes cambiados |
| S2 | 20 | I2 | 192 | U2 | 92 |
| S3 | 3 | I3 | 1 comprobante, 3 renglones | U3 | 3 |
| S4 | 5 | I4 | 1 | U4 | 23 |
| S5 | 40 | I5 | 1 | U5 | 10 |
| S6 | 498 | I6 | 1 ingreso, 1 renglón | U6 | 1.017 |
| S7 | 1 | D1 | 11.815 comprobantes, 42.330 renglones | D4 | 693 |
| S8 | 40 | D2 | 3 | D5 | 3.432 |
| S9 | 1 | D3 | 2 | D6 | 127 |
| S10 | 1.597 | | | | |
| S11 | 5.434 | | | | |
| S12 | 9.833 (A: 2.663, B: 7.170) | | | | |

Con la carga del 2026-10-27, ejecutada el mismo 2026-11-05, los cuatro archivos también terminan con exit 0 y sin cambios en las huellas. S3 devuelve 0 filas porque la última semana queda fuera de la historia: por eso antes de la demo se regenera con la fecha del día.

### 4.3 Qué se corrigió en la Etapa 5

En la versión integrada en `main` los cuatro archivos cortaban en el primer error con `ON_ERROR_STOP=1`. Con `ON_ERROR_STOP=0` sumaban 42 errores:

- 28 por variables de psql nunca definidas;
- 13 por transacciones ya abortadas;
- 1 de RN-08: U1 hacía un `UPDATE` directo de importes, que `trg_comprobante_importes` rechaza.

Además:

- el comando del README apuntaba a `/opt/bodegas/consultas/`, que no existía en la imagen;
- los CUIT iban sin comillas;
- el "Filas afectadas" siempre daba 0.

La corrección se describe en `consultas/README.md`.

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
| 2. Las modificaciones muestran antes y después y se probaron en transacción (`BEGIN … ROLLBACK`) | APROBADO | Los cuatro archivos corren con `ejecutar.sh` (`ON_ERROR_STOP=1`) con exit 0; cada modificación informa sus filas; las huellas de `hashes.sql` son idénticas antes y después | `docs/consultas.md` (sección 4); `consultas/*.sql` | Verificado el 2026-11-05 sobre cargas desde volumen vacío |
| 3. Las consultas avanzadas usan CTE, ventanas, subconsultas correlacionadas o `NOT EXISTS` según corresponda | APROBADO | S10: CTE + subconsulta correlacionada real; S11: `RANK()` y `SUM() OVER`; S12: doble `NOT EXISTS` (división) y `NOT EXISTS` (anti-join); S9: `JOIN`, agregación y vista | `consultas/select.sql` | Verificado que las herramientas se usan con lógica real, no solo que aparecen en el código |

**Resultado global del checklist: los tres criterios están APROBADOS con evidencia real de ejecución.**

## 7. Documentación relacionada
- [Requisitos y trazabilidad académica](requisitos.md)
- [Auditoría y aceptación de consultas avanzadas S9-S12](consultas/auditoria_etapa5.md)
- [Planes de ejecución y métricas S9-S12](consultas/planes_etapa5.md)
- [Concurrencia: la última botella](concurrencia.md)
- [Índices y rendimiento (Etapa 4)](rendimiento.md)
- [Carga masiva reproducible (Etapa 3)](carga_masiva.md)
- [Reglas de negocio: trazabilidad regla → mecanismo → prueba](trazabilidad.md)
