# Índices y rendimiento (Etapa 4)

Informe de la etapa: consultas medidas, índices creados en `db/migrations/008_indices.sql` y su justificación, comparación antes y después, índices descartados, casos en que el planificador no usa un índice y costo de escritura.

Todo lo que figura acá se midió. El anexo está en `docs/rendimiento/`:
- `planes/`: plan completo de cada consulta, antes y después;
- `resultados_*.csv`: métricas;
- `contexto_*.txt`: configuración y lista de índices;
- `experimentos/`: salida completa de cada experimento.

## 1. Contexto de la medición

| Dato | Valor |
|---|---|
| Base | Carga de la Etapa 3: `SEMILLA=20260427`, `FECHA_REFERENCIA=2026-10-27`, `ESCALA=1`. `comprobante` tiene 150.125 filas (24 MB) y `renglon_comprobante` 538.306 (35 MB). |
| Fecha de la medición (`CURRENT_DATE`) | 2026-10-28 |
| PostgreSQL | 16.15 (imagen `postgres:16-alpine`) |
| Configuración | `shared_buffers` 128 MB, `work_mem` 4 MB, `effective_cache_size` 4 GB, `jit` activado, `random_page_cost` 4, `max_parallel_workers_per_gather` 2, `default_statistics_target` 100 (valores por omisión de la imagen) |
| Hardware | Intel Core i5-12500H (16 hilos), Docker Desktop 29.2.1 con 7,6 GiB de RAM |

**Protocolo.** Lo aplica `db/perf/medir.sh`, que delega en `medir.sql`:
- `ANALYZE` antes de cada serie;
- por consulta, una ejecución inicial y 5 repeticiones con `EXPLAIN (ANALYZE, BUFFERS)`; se informa la **mediana de las 5 repeticiones**, y el plan guardado es el de la repetición más cercana a esa mediana;
- tiempo, tipos de recorrido, filas leídas, filas descartadas por filtro y buffers se extraen del plan dentro de PostgreSQL;
- los `DELETE` se ejecutan dentro de un bloque que se revierte, así que la medición no cambia datos.

**Caché.** `shared_read` es 0 en todas las mediciones: los datos estaban en memoria, incluso en la primera ejecución. Por lo tanto, las mejoras reflejan menos trabajo de CPU y menos páginas recorridas, no menos lecturas de disco. Con caché fría o en un servidor con poca memoria, la diferencia a favor de los índices sería mayor.

**Línea base.** Antes de medir, `pg_indexes` del esquema `bodegas` tenía exactamente 42 índices: 31 de clave primaria y 11 de `UNIQUE`.

## 2. Consultas elegidas

Están en `db/perf/consultas_candidatas.sql`, con sus parámetros. Los períodos relativos se calculan desde `CURRENT_DATE` en hora local, aplicando `AT TIME ZONE` a la **constante** y no a la columna, para que la condición sobre `fecha` pueda usar un índice.

| Código | Consulta | Por qué se eligió |
|---|---|---|
| C1 | S8: ventas por sala del último trimestre | Rango de fechas sobre la tabla de 150.000 comprobantes. |
| C2 | S3: clientes por tipo en la sala 2 la última semana | Igualdad por sala y rango de fechas: caso del índice compuesto. |
| C3 | S5: salas con menos transferencias pendientes | 7 pendientes entre 5.088: caso del índice parcial. |
| C4 | D4: borrar socios sin compras con alta de más de 5 años (revertido) | Cada borrado verifica la FK `fk_comprobante_cliente`: muestra que **PostgreSQL no indexa las FK automáticamente**. |
| C5 | Ventas de un vino (base de S9 y S12) | `cod_vino` es la segunda columna de la PK de `renglon_comprobante`. Es la misma búsqueda del `RESTRICT` al borrar un vino. |
| C6 | Precio vigente de cada renglón del último mes, según la auditoría | Era el paso más lento de la carga (Etapa 3); es la base de U1. |
| C7 | S1: ranking de los 10 vinos más vendidos de toda la historia | Agrega toda la tabla: caso en que **ningún índice debería ayudar**. |

## 3. Índices creados (`008_indices.sql`)

Tamaños medidos con `pg_relation_size` sobre la base cargada. Los tiempos de creación se midieron creando cada índice dentro de una transacción revertida.

| Índice | Tipo pedido | Acelera | Por qué ese tipo y ese orden | Tamaño | Creación |
|---|---|---|---|---:|---:|
| `idx_comprobante_id_sala_fecha (id_sala, fecha)` | **Compuesto** | C2 (S3), S11 | Igualdad (`id_sala`) primero y rango (`fecha`) después: el índice ubica el tramo de una sala y lo recorre ordenado por fecha (sección 5). | 4,6 MB | 65 ms |
| `idx_comprobante_fecha (fecha) INCLUDE (id_sala, total)` | **Variante con INCLUDE** | C1 (S8), C6, ventas por período | El compuesto no sirve sin sala fija. `INCLUDE` guarda `id_sala` y `total` en las hojas sin hacerlos parte de la clave, así que S8 se resuelve con **Index Only Scan**, sin leer la tabla (`Heap Fetches: 0`). | 6,0 MB | 59 ms |
| `idx_comprobante_id_cliente (id_cliente)` | **Clave foránea** | C4 (D4, D6), anti-joins de S12 | Sin él, el control de `fk_comprobante_cliente` recorre los 150.125 comprobantes por cada cliente borrado. | 1,3 MB | 48 ms |
| `idx_renglon_comprobante_cod_vino (cod_vino)` | **Clave foránea** | C5 (S9, S12), `RESTRICT` de vino | La PK `(nro_comprobante, cod_vino)` no sirve para buscar por la segunda columna. | 3,7 MB | 112 ms |
| `idx_transferencia_pendientes (id_sala) WHERE estado <> 'procesado'` | **Parcial** | C3 (S5), `v_documentos_pendientes` | Indexa sólo las 7 transferencias pendientes; las 5.081 procesadas no ocupan lugar. El planificador lo usa porque el filtro de la consulta **implica** el del índice (sección 7). | 16 kB | 4 ms |
| `idx_auditoria_precio_cod_vino_fecha (cod_vino, fecha_hora)` | Compuesto | C6 (precio vigente, U1) | Igualdad por vino y el cambio más reciente anterior a la fecha: `Index Scan Backward` con `LIMIT 1`. | 128 kB | 3 ms |

**Total de índices nuevos:** unos 15,8 MB, frente a los 59 MB de `comprobante` y `renglon_comprobante` juntas.

**`CREATE INDEX` frente a `CONCURRENTLY`.** `CREATE INDEX` impide escribir en la tabla mientras construye el índice, aunque permite leerla; acá eso dura décimas de segundo. `CREATE INDEX CONCURRENTLY` permite seguir escribiendo, pero **no puede ejecutarse dentro de un bloque de transacción**, y `db/migrate.sh` aplica cada migración en una. Además es más lento y, si falla, deja un índice inválido que hay que borrar. En una base productiva con escrituras continuas se crearía con `CONCURRENTLY`, fuera del runner.

## 4. Comparación antes y después

Mediana de 5 repeticiones. Filas leídas: suma de las filas que producen los nodos de recorrido. Buffers: los del nodo raíz; en C4 no incluyen el trabajo de los triggers de FK, que se informa aparte.

| Consulta | Antes | Después | Mejora | Recorrido antes | Recorrido después | Filas descartadas por filtro | Buffers (shared hit) |
|---|---:|---:|---:|---|---|---:|---:|
| C1 S8 | 23,4 ms | **2,7 ms** | **−88,5 %** | Parallel Seq Scan | **Index Only Scan** `idx_comprobante_fecha` | 143.782 → 0 | 3.064 → 37 |
| C2 S3 | 6,5 ms | **0,12 ms** | **−98,1 %** | Parallel Seq Scan | Bitmap Index Scan `idx_comprobante_id_sala_fecha` | 150.120 → 0 | 3.083 → 30 |
| C3 S5 | 0,24 ms | 0,16 ms | −36 % | Seq Scan | Bitmap Index Scan sobre el parcial | 5.081 → 0 | 35 → 4 |
| C4 D4 | 3.620 ms | **53,6 ms** | **−98,5 %** | Seq Scan (en el control de FK) | Index Scan `idx_comprobante_id_cliente` | 14.740 → 14.740 | 4.737 → 16.762 |
| C5 ventas de un vino | 27,7 ms | 17,8 ms | −36 % | Parallel Seq Scan sobre renglones | Parallel Bitmap Heap Scan con `idx_renglon_comprobante_cod_vino` | 523.178 → 0 | 7.565 → 3.222 |
| C6 precio vigente | 693 ms | **29,2 ms** | **−95,8 %** | Seq Scan sobre la auditoría, 7.439 veces | **Index Scan Backward** `idx_auditoria_precio_cod_vino_fecha` | 27.010.309 → 0 | 290.346 → 28.095 |
| C7 S1 | 88,6 ms | 78,1 ms | sin cambio de plan | Parallel Seq Scan | Parallel Seq Scan | 0 → 0 | 4.513 → 4.551 |

**Lectura:**

- **C4 es el caso más claro.** El tiempo de `fk_comprobante_cliente` en las 695 llamadas bajó de **3.517 ms a 11,3 ms**. Los buffers del nodo raíz suben porque ahora el plan principal también usa el índice para el anti-join, pero el costo dominante, el de la FK, desaparece.
- **C6:** cada una de las 7.439 búsquedas pasa de recorrer las 3.617 filas de la auditoría a leer una sola entrada del índice.
- **C5 mejora poco:** el índice resuelve los renglones del vino, pero el plan sigue recorriendo `comprobante` para obtener la sala de cada renglón con un hash join. Un índice que lo evitara tendría que cubrir el join completo; no se justifica para esta consulta.
- **C3:** la ganancia absoluta es mínima porque la tabla es chica (5.088 filas). El índice parcial vale por lo que no indexa y por su tamaño de 16 kB.
- **C7 no cambia de plan.** La diferencia de tiempo (88,6 → 78,1 ms) es variación entre series, no efecto de un índice: ver la sección 8.

**Criterio de aceptación:** hay mejora medida en 6 de las 7 consultas; C7 es el control negativo.

## 5. Orden de las columnas del índice compuesto

`db/perf/experimentos/01_orden_compuesto.sql`, con salida en `docs/rendimiento/experimentos/01_orden_compuesto.txt`. Misma consulta, ventas de la sala 2, con los dos órdenes posibles:

| Período | `(id_sala, fecha)` | `(fecha, id_sala)` |
|---|---|---|
| Última semana | 0,061 ms, 3 páginas de índice | 0,057 ms, 5 páginas de índice |
| Último año | **0,20 ms en el índice, 6 páginas, 1,6 ms total** | 2,27 ms en el índice, 99 páginas, 3,0 ms total |

**Por qué gana `(id_sala, fecha)`.** Con `(fecha, id_sala)`, el índice recorre **todas** las entradas del período, de las 40 salas, y descarta las que no son de la sala 2. Con `(id_sala, fecha)`, va directo al tramo de la sala 2 y dentro de él lee sólo el rango de fechas.

**La regla es "igualdad primero, rango después",** más que "la columna más selectiva primero" como simplifica el apunte. La fecha es más selectiva que la sala, pero como se usa con un rango, ponerla primero deja a `id_sala` como filtro dentro del índice.

**Lo que no resuelve el compuesto.** Con `(id_sala, fecha)`, una consulta **sin sala fija** (S8) no puede usar el índice, porque su primera columna no está acotada, y el planificador recorre la tabla (28,4 ms). Por eso existe el segundo índice, que empieza por `fecha` e incluye `id_sala` y `total`.

## 6. Índices evaluados y descartados

`experimentos/02_descartados.sql`.

### 6.1 BRIN sobre `comprobante.fecha`

Un BRIN guarda, por cada rango de 128 páginas, el mínimo y el máximo de la columna. Sirve si el orden físico de la tabla sigue a la columna: eso es la **correlación** de `pg_stats`.

| Tabla | Correlación de `fecha` | Tamaño del BRIN | Resultado (ventas del último trimestre) |
|---|---:|---:|---|
| `comprobante` real | **−0,005** | 24 kB | El planificador no lo elige. Forzado, recorre 1.065 bloques "lossy" por worker y descarta 71.891 filas por worker al rechequear: **25,2 ms, igual o peor que el recorrido completo (22,5 ms)**. |
| Copia ordenada por fecha | **1** | 24 kB (frente a 3,3 MB de un B-tree) | 128 bloques, **4,1 ms**. |

**Descartado:** con este orden físico, BRIN no descarta nada.

**Por qué la tabla está desordenada.** La carga de la Etapa 3 inserta los comprobantes en orden de fecha, pero después calcula los importes con un `UPDATE` de todas las filas. Cada fila actualizada se escribe en otro lugar, así que el orden se pierde. Además, ese `UPDATE` dejó la tabla con **3.060 páginas, de las que sólo 1.657 tienen filas vivas**: unas 1.400 páginas quedaron vacías después de que autovacuum liberó las versiones viejas.

**Mejora posible para el generador:** calcular los importes en el mismo `INSERT … SELECT` en lugar de un `UPDATE` posterior. Conservaría el orden, con lo que BRIN se volvería viable, y evitaría las páginas vacías. Queda como pendiente porque requiere recargar los datos.

### 6.2 Hash frente a B-tree sobre `comprobante.id_cliente`

| Índice | Tamaño | Igualdad (cliente 1500) | Rango (`BETWEEN 1500 AND 1510`) |
|---|---:|---|---|
| B-tree | **1,35 MB** | 0,05 ms | Lo usa |
| Hash | 4,6 MB | 0,03 ms | **No lo puede usar:** el planificador recorre la tabla (5,2 ms) |

**Descartado:** el Hash ocupa más del triple y sólo sirve para igualdad. Esto **contradice** al apunte, que le atribuye eficiencia en espacio: en PostgreSQL 16 y con estos datos, el B-tree es más chico. En velocidad de igualdad, la diferencia está dentro del ruido.

## 7. Cuándo se usa un índice parcial

`experimentos/05_parcial_y_expresion.sql`. El planificador usa un índice parcial sólo si puede **probar, al planificar**, que el `WHERE` de la consulta implica el del índice.

| Índice parcial | Filtro de la consulta | ¿Lo usa? |
|---|---|---|
| `WHERE estado <> 'procesado'` | `estado <> 'procesado'` | Sí (Index Only Scan) |
| `WHERE estado <> 'procesado'` | `estado IN ('en_confeccion', 'terminado')` | **Sí**: PostgreSQL prueba que cada valor de la lista es distinto de `procesado` |
| `WHERE fecha >= '2026-01-01'` (fecha fija, como el ejemplo "del año actual" del apunte) | `fecha >= '2026-10-21'` (literal) | Sí |
| `WHERE fecha >= '2026-01-01'` | `fecha >= CURRENT_DATE - 7 días` | **No**: recorre la tabla (22 ms). `CURRENT_DATE` no es una constante al planificar, así que no puede probar la implicación. |

**Correcciones al apunte:**
- un índice parcial con fecha fija **no es "del año actual"**: queda fijo en esa fecha, crece con el tiempo y no sirve para consultas relativas a `CURRENT_DATE`;
- por eso el índice parcial de `008` usa un **estado** y no una fecha.

**Índice de expresión por mes, evaluado y no adoptado.**
- `date_trunc('month', fecha)` sobre `TIMESTAMPTZ` es **STABLE**, porque depende del parámetro `TimeZone` de la sesión. Por eso PostgreSQL lo rechaza en un índice: `functions in index expression must be marked IMMUTABLE`.
- La alternativa es fijar la zona antes de truncar: `date_trunc('month', fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')`. `timezone(text, timestamptz)` y `date_trunc(text, timestamp)` son IMMUTABLE, y el índice se crea (1 MB).
- No se adoptó: ninguna consulta medida filtra por mes, y `v_ventas_mensuales_sala` agrega toda la tabla.

## 8. Cuándo el planificador no usa un índice existente

### 8.1 Baja selectividad (`experimentos/03_indice_no_usado.sql`)

Estadísticas de `comprobante.fecha`: `n_distinct` −0,998 (casi todos los valores son distintos), histograma de 101 límites entre 2020-10-27 y 2026-10-27. Los últimos 5 años son **125.091 de 150.125 filas (83,3 %)**.

| Caso | Plan elegido | Costo estimado | Tiempo |
|---|---|---:|---:|
| A. Último trimestre, consulta cubierta por el índice | Index Only Scan | — | 1,4 ms |
| B. Últimos 5 años, **consulta cubierta** por el índice (`id_sala`, `total`) | **Parallel Index Only Scan** | 5.461 | 17,7 ms |
| C. Últimos 5 años pidiendo `id_cliente`, que **no está en el índice** | **Seq Scan**: el índice existe y no se usa | 17.299 | 64,0 ms |
| D. Caso C forzando el índice (`enable_seqscan = off`, sólo para comparar) | Bitmap Heap Scan | 20.262 | 38,0 ms |
| E. Caso C con `random_page_cost = 1.1` | Seq Scan | 17.299 | 61,1 ms |

**Lectura:**

- **B: un índice que cubre la consulta se usa aunque se lea el 83 % de la tabla.** Un Index Only Scan, con todas las páginas marcadas como visibles (`Heap Fetches: 0`), no necesita visitar la tabla. Recorrerlo es más barato que leer las páginas de datos.
- **C: si hay que ir a la tabla por cada fila**, porque se pide `id_cliente`, el planificador estima que leer el 83 % de las filas a través del índice cuesta más (20.262) que recorrer la tabla (17.299), y no lo usa. Es el caso clásico de baja selectividad.
- **D muestra el límite del modelo de costos:** forzado, el índice fue **más rápido** (38 ms contra 64 ms), aunque su costo estimado era mayor. La causa no es el modelo de disco, porque con `random_page_cost = 1.1` (E) la elección no cambia. Es la tabla con páginas vacías de la sección 6.1:
  - el planificador calcula el recorrido completo sobre **3.060 páginas**;
  - el Bitmap Heap Scan visita sólo las **1.657** que tienen filas vivas.

  Una tabla compactada (`VACUUM FULL` o `CLUSTER`) resolvería la discrepancia.

### 8.2 Estadísticas desactualizadas (`experimentos/04_estadisticas_desactualizadas.sql`)

Sobre un clon temporal de `comprobante`: los triggers impiden modificar comprobantes reales, y autovacuum no analiza tablas temporales, así que el experimento es determinista. El clon tiene un índice sobre `id_sala`.

| Paso | Estimación del planificador | Filas reales | Plan | Tiempo |
|---|---:|---:|---|---:|
| A. Estadística al día: la sala 1 es una de 40 (frecuencia ≈ 2,5 %) | 3.173 | 3.333 | Bitmap Heap Scan | 3,3 ms |
| B. `UPDATE` que pasa el **90 %** de las filas a la sala 1, **sin `ANALYZE`** | **5.961** | **135.440** | Bitmap Heap Scan (elegido con la estimación vieja) | 23,8 ms |
| C. `ANALYZE` y la misma consulta | 135.393 | 135.440 | **Seq Scan** | 21,2 ms |

Sin `ANALYZE`, el planificador subestimó las filas **23 veces** y eligió el plan pensado para pocas filas. Con la estadística al día, cambia a recorrer la tabla.

La diferencia de tiempo es chica porque todo está en memoria. Con lecturas de disco, el Bitmap sobre el 90 % de la tabla haría mucho más acceso aleatorio. La evidencia fuerte es el error de estimación, que en consultas con joins se propaga a la elección de todo el plan.

## 9. Costo de escritura

`experimentos/06_costo_escritura.sql`, todo en transacciones revertidas. Medianas de 3 corridas.

**Carga masiva en clones** (`INSERT … SELECT` de la tabla completa):

| Carga | Sólo PK | PK + índices de 008 | Diferencia |
|---|---:|---:|---|
| 150.125 comprobantes (+3 índices) | 0,17 s | 1,22 s | **unas 7 veces más lenta** |
| 538.306 renglones (+1 índice) | 1,10 s | 1,23 s | +12 % |

**Por qué los comprobantes cuestan tanto más.** Las filas llegan en el orden físico de la tabla, que no sigue a la fecha (sección 6.1). Así, cada inserción en los índices sobre `fecha` cae en una hoja distinta del árbol, con más divisiones de páginas y menos localidad. Con datos llegando en orden de fecha, como en un sistema real donde las ventas se registran a medida que ocurren, el costo sería menor. En el clon, los 4 índices de `comprobante` ocupan 19 MB frente a 13 MB de la tabla.

**Venta por el camino real** (`fn_registrar_venta`, con todos sus triggers), 300 ventas de 3 vinos, en dos tandas:

| | Por venta |
|---|---:|
| Sin índices de 008 | 1,19 ms |
| Con índices de 008 | 1,61 ms (**+35 %**) |

Cada venta inserta un comprobante, que actualiza 4 índices en lugar de 1, y tres renglones, que actualizan 2 índices en lugar de 1, además de recalcular stock e importes. El costo extra (0,4 ms por venta) es aceptable frente a lo que ganan las consultas.

**Tamaños.**
- Los 6 índices nuevos suman unos 15,8 MB.
- En `comprobante`, el total de índices pasa de 6,6 MB (sólo la PK) a 18,6 MB, frente a 24 MB de tabla.
- En `renglon_comprobante`, de 21 MB a 24,7 MB, frente a 35 MB de tabla.

## 10. Verificación

- `run_all.sh` 7 de 7, `controles.sql` con `fecha_referencia=2026-10-27` (55 controles, 0 violaciones) y `post_carga.sql`, **sobre la base con `008` aplicada**.
- **Desde cero en `bda_etapa4_prueba`:**
  - `migrate` aplicó 001 a 008 con código 0;
  - carga con `ESCALA=0.1`;
  - controles con `-v minimo_mayor=10000`, `post_carga.sql` y `run_all.sh` sin fallas;
  - `/salud` respondió 200 directo y por el proxy;
  - `down -v` sólo de ese proyecto.

## 11. Conclusiones

1. **Los mayores beneficios** están donde el plan recorría una tabla grande para encontrar pocas filas:
   - el control de una **FK sin índice**: 3,6 s a 54 ms;
   - una **búsqueda repetida** dentro de un join: 693 a 29 ms;
   - un **rango corto de fechas**: 23 a 2,7 ms.
2. **El orden del índice compuesto se justifica con la forma de la consulta** (igualdad y después rango), no con la selectividad de cada columna aislada.
3. **Un índice que cubre la consulta (`INCLUDE`)** se usa incluso para grandes porciones de la tabla. Uno que no la cubre se abandona con baja selectividad.
4. **BRIN depende del orden físico**, y el orden físico depende de cómo se cargaron los datos. Se verifica con `pg_stats.correlation` antes de crearlo.
5. **Los índices cuestan en cada escritura** (+35 % por venta en este caso) y en espacio (unos 16 MB). Por eso se crearon sólo los que una consulta medida justifica, y se descartaron los que no ganaban nada (BRIN, Hash) o que ninguna consulta usa (expresión por mes).

## 12. Pendientes para la Etapa 5

- Medir con `EXPLAIN (ANALYZE)` las consultas avanzadas S9 a S12, como pide la consigna. S9 y S12 deberían aprovechar `idx_renglon_comprobante_cod_vino`, y S12 también `idx_comprobante_id_cliente`.
- U1: el recálculo de todos los comprobantes recorre toda la tabla; no se espera que un índice lo cambie.
- Mejora opcional de la Etapa 3: calcular los importes en el `INSERT` en lugar de un `UPDATE` posterior (sección 6.1). Si se hace, hay que recargar los datos y repetir estas mediciones.
