# Planes de ejecución - Consultas avanzadas S9 a S12 (Etapa 5)

## Métricas obtenidas con `db/perf/medir.sh` (etiqueta: despues)

| Consulta | Primera (ms) | Mediana (ms) | Filas leídas | Filas filtradas | Filas devueltas | Recorridos observados |
|----------|-------------|-------------|-------------|----------------|----------------|----------------------|
| S9 | 0.915 | 0.270 | 6 | 4 | 1 | Seq Scan x7 (bodega, cepa, composicion_vino, stock_deposito, stock_sala, vino, vino_maridaje) |
| S10 | 0.142 | 0.142 | 0 | 0 | 0 | Seq Scan on lote_uva |
| S11 | 2.735 | 0.338 | 10 | 0 | 2 | Seq Scan x3 (comprobante, renglon_comprobante, vino) |
| S12A | 0.135 | 0.121 | 12 | 0 | 2 | Seq Scan x4 (cliente, comprobante, renglon_comprobante, vino) |
| S12B | 0.208 | 0.195 | 11 | 0 | 0 | Seq Scan x4 (cliente, comprobante, renglon_comprobante, vino) |

> Nota: las mediciones se ejecutaron sobre un entorno con datos mínimos de validación (lote_uva, parcela y finca vacíos; 2 vinos, 3 comprobantes, 2 clientes, 1 bodega, 1 sala). Los tiempos son por tanto muy bajos (sub-milisegundo) y todos los recorridos son `Seq Scan` porque no hay volumen ni selectividad que justifique índices adicionales. No se agregaron índices nuevos: se respetan los existentes de la Etapa 4.

---

## S9 — Ficha completa de un vino

**Archivo del plan:** `docs/consultas/planes/S9_plan.txt`

- **Objetivo:** Obtener la ficha de un vino con datos del vino, cepas y porcentajes (corte), bodega productora, maridajes y stock total disponible, para un `cod_vino` dado.
- **Herramientas SQL utilizadas:** `JOIN` (vino-bodega, vino-stock, composicion_vino-cepa, vino_maridaje-maridaje), funciones de agregación (`string_agg` dentro de la vista), vista `v_ficha_vino`.
- **Tipo de recorrido observado:** `Seq Scan` sobre todas las tablas implicadas (volumen mínimo, sin filtros selectivos que usen índice).
- **Operaciones principales del plan:**
  - `Nested Loop Left Join` encadenados: `vino -> bodega`, `vino -> stock_deposito`, `vino -> stock_sala` (agrupado), `composicion_vino -> cepa` (para el corte), `vino_maridaje -> maridaje` (para maridajes).
  - `GroupAggregate` + `Sort` para el `string_agg` del corte (ordenado por `porcentaje DESC, ce.nombre`) y de los maridajes (ordenado por `m.nombre`).
  - Filtro `cod_vino = 990001` aplicado en el `Seq Scan on vino`.
- **Filas obtenidas:** 1 (el vino 990001).
- **Tiempo real de ejecución:** 0.270 ms (mediana), 0.915 ms (primera).
- **Interpretación del plan:** El planner expande la vista `v_ficha_vino` y ejecuta los `JOIN` y agregaciones internos. El corte y los maridajes se calculan en subconsultas separadas (`GroupAggregate`), evitando el producto cartesiano que multiplicaría el stock. No hay duplicación de cantidades de stock porque `stock_salas` se pre-agrupa por `cod_vino` antes de unirse.
- **Posibles mejoras:** Con volumen real, un índice en `vino(cod_vino)` (PK ya existe) y en las FK de `composicion_vino`, `vino_maridaje`, `stock_sala` y `stock_deposito` permitiría `Index Scan` en lugar de `Seq Scan`. No se agregan índices sin autorización.

---

## S10 — Rendimiento por parcela y campaña

**Archivo del plan:** `docs/consultas/planes/S10_plan.txt`

- **Objetivo:** Calcular el rendimiento en kg/ha de cada parcela por campaña (`SUM(kilos) / NULLIF(SUM(superficie_ha), 0)`) e identificar las parcelas cuyo rendimiento está por debajo del promedio de su finca en esa misma campaña.
- **Herramientas SQL utilizadas:** `CTE` (`WITH rendimiento_parcela`), `NULLIF` para evitar división por cero, subconsulta correlacionada (la subconsulta `SELECT AVG(rp2.kg_ha) FROM rendimiento_parcela rp2 WHERE rp2.id_finca = rp.id_finca AND rp2.campania = rp.campania` referencia columnas del nivel externo).
- **Tipo de recorrido observado:** `Seq Scan on lote_uva` (tabla vacía en este entorno).
- **Operaciones principales del plan:**
  - CTE `rendimiento_parcela`: `HashAggregate` agrupando por `id_finca, nro_parcela, campania`.
  - `Nested Loop` entre `lote_uva` y `parcela` con `Join Filter` en `id_finca` y `nro_parcela`.
  - Dos `SubPlan` (subconsultas correlacionadas) para calcular `prom_kg_ha` (una en el `SELECT`, otra en el `WHERE`).
  - `Sort` por `id_finca, nro_parcela, campania`.
- **Filas obtenidas:** 0 (tabla `lote_uva` vacía en entorno de validación).
- **Tiempo real de ejecución:** 0.142 ms.
- **Interpretación del plan:** El CTE se materializa y se escanea dos veces (una para el `prom_kg_ha` mostrado, otra para el filtro `WHERE`). Ambas son subconsultas correlacionadas reales (referencian `rp.id_finca` y `rp.campania` del nivel externo), no un `JOIN` entre CTEs. Con datos reales, el `HashAggregate` y las subconsultas correlacionadas serían los nodos de mayor costo.
- **Posibles mejoras:** Índices en `lote_uva(id_finca, nro_parcela, campania)` y `parcela(id_finca, nro_parcela)` para acelerar el `JOIN` y la agrupación. No se agregan sin autorización.

---

## S11 — Ranking de vinos y ventas acumuladas

**Archivo del plan:** `docs/consultas/planes/S11_plan.txt`

- **Objetivo:** (1) Ranking de vinos dentro de cada sala por botellas vendidas, y (2) ventas acumuladas mensuales por sala. Se resuelve en una sola consulta con dos funciones de ventana.
- **Herramientas SQL utilizadas:** `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`, `CTE` para la agregación base.
- **Tipo de recorrido observado:** `Seq Scan` sobre `comprobante`, `renglon_comprobante` y `vino`; `Hash Join` para las uniones.
- **Operaciones principales del plan:**
  - `HashAggregate` agrupando por `id_sala, mes, cod_vino, nombre` (ventas mensuales por vino).
  - `Hash Join` para unir `comprobante`, `renglon_comprobante` y `vino`.
  - `WindowAgg` (dos niveles): primero `SUM(...) OVER` (ventas acumuladas de la sala), luego `RANK() OVER` (ranking dentro de sala/mes).
  - `Incremental Sort` para el orden final por `id_sala, mes, rnk_mes`.
  - Filtro `rnk_mes <= 10` (top 10 por sala/mes).
- **Filas obtenidas:** 2.
- **Tiempo real de ejecución:** 0.338 ms (mediana), 2.735 ms (primera, con caché fría).
- **Interpretación del plan:** Las dos funciones de ventana se implementan como dos nodos `WindowAgg` encadenados. El `RANK()` resuelve empates (mismo rango para valores iguales, dejando huecos). La suma acumulada usa `ROWS UNBOUNDED PRECEDING` para el total cronológico de la sala. No hay duplicación de importes porque la agregación base se hace antes de aplicar las funciones de ventana.
- **Posibles mejoras:** Índice en `comprobante(fecha, id_sala)` para el filtro de período y agrupación por sala. No se agregan sin autorización.

---

## S12 — División relacional y anti-join

### S12A — Clientes que compraron todos los vinos de una bodega

**Archivo del plan:** `docs/consultas/planes/S12A_plan.txt`

- **Objetivo:** Clientes que compraron todos los vinos de una bodega dada (`cuit_bodega = '30990000001'`), implementado mediante división relacional (doble negación).
- **Herramientas SQL utilizadas:** `NOT EXISTS` anidado (doble negación), `JOIN` entre `comprobante` y `renglon_comprobante` en la subconsulta interna.
- **Tipo de recorrido observado:** `Seq Scan` sobre `cliente`, `vino`, `comprobante`, `renglon_comprobante`; `Nested Loop Anti Join` con `Materialize` y `SubPlan`.
- **Operaciones principales del plan:**
  - `Seq Scan on cliente c` (nivel externo).
  - `Seq Scan on vino v` filtrado por `cuit_bodega` (los vinos de la bodega).
  - `Nested Loop Anti Join`: para cada cliente, verifica que NO exista un vino de la bodega que el cliente no haya comprado.
  - `SubPlan 2` (`Hash Join` entre `renglon_comprobante` y `comprobante`): verifica las compras efectivas del cliente.
  - `Join Filter: (NOT (hashed SubPlan 2))` — la doble negación se materializa como anti-join.
- **Filas obtenidas:** 2.
- **Tiempo real de ejecución:** 0.121 ms.
- **Interpretación del plan:** La división relacional "clientes para los que no existe un vino de la bodega que no hayan comprado" se ejecuta como `Nested Loop Anti Join` con un `SubPlan` correlacionado. No hay falsos positivos por `JOIN` porque se usa `NOT EXISTS` (existencia, no multiplicación de filas). Bodegas sin vinos producirían resultado vacío (no hay vacío verdaderamente verdadero), lo cual es correcto.
- **Posibles mejoras:** Índice en `vino(cuit_bodega)` y en `comprobante(id_cliente)` para las subconsultas correlacionadas. No se agregan sin autorización.

### S12B — Clientes que nunca compraron vinos tintos

**Archivo del plan:** `docs/consultas/planes/S12B_plan.txt`

- **Objetivo:** Clientes que nunca compraron vinos de tipo `tinto`, implementado mediante anti-join.
- **Herramientas SQL utilizadas:** `NOT EXISTS` (anti-join), `JOIN` entre `comprobante`, `renglon_comprobante` y `vino` filtrado por `tipo = 'tinto'`.
- **Tipo de recorrido observado:** `Seq Scan` sobre `cliente`, `comprobante`, `renglon_comprobante`, `vino`; `Nested Loop Anti Join` con `Materialize` y `Hash Join`.
- **Operaciones principales del plan:**
  - `Seq Scan on cliente c` (nivel externo).
  - `Hash Join` entre `comprobante`, `renglon_comprobante` y `vino` filtrado por `v.tipo = 'tinto'` (compra de tintos).
  - `Nested Loop Anti Join` con `Join Filter: (cmp.id_cliente = c.id_cliente)`: descarta clientes que aparecen en el conjunto de compradores de tintos.
  - `Materialize` para el lado derecho del anti-join.
- **Filas obtenidas:** 0 (en este entorno todos los vinos son `tinto` y los clientes los compraron).
- **Tiempo real de ejecución:** 0.195 ms.
- **Interpretación del plan:** El anti-join identifica clientes que NO tienen ninguna fila en el conjunto de compras de vinos tintos. Es una implementación real de anti-join (no un `LEFT JOIN ... WHERE IS NULL` simulado). Los falsos positivos se evitan porque `NOT EXISTS` solo verifica existencia, no cuenta filas.
- **Posibles mejoras:** Índice en `vino(tipo)` y `comprobante(id_cliente)` para el anti-join. No se agregan sin autorización.

---

## Diferencia entre costo estimado y tiempo real

- **Costo estimado:** es la unidad arbitraria de PostgreSQL (cost) basada en estadísticas del planner. En los planes se ve como `cost=0.00..9.27` etc.
- **Tiempo real medido:** es el `Execution Time` reportado por `EXPLAIN (ANALYZE, BUFFERS)` en milisegundos, obtenido con `db/perf/medir.sh`. Ejemplo S9: costo estimado `6.32`, tiempo real `0.270 ms`. No son directamente comparables (diferentes unidades).

---

## Archivos de planes generados

| Consulta | Archivo |
|----------|---------|
| S9 | `docs/consultas/planes/S9_plan.txt` |
| S10 | `docs/consultas/planes/S10_plan.txt` |
| S11 | `docs/consultas/planes/S11_plan.txt` |
| S12A | `docs/consultas/planes/S12A_plan.txt` |
| S12B | `docs/consultas/planes/S12B_plan.txt` |

S11 y S12 contienen dos consultas independientes cada una (S12 tiene dos partes), por lo que se generó un plan por cada una.
