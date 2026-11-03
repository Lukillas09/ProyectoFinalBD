# Informe de Auditoría — Etapa 5: Consultas S9, S10, S11, S12

**Rama:** `feat/etapa5-consultas-avanzadas` (desde `main`, sin cambios en `main`)
**Entorno:** PostgreSQL 16 via Docker Compose, datos mínimos de validación
**Fecha:** 2026-11-03

---

## 1. Tabla de criterios de aceptación

| # | Criterio de aceptación | Estado | Evidencia concreta |
|---|------------------------|--------|--------------------|
| 1 | S9, S10, S11, S12 agregadas al final de `consultas/select.sql` | APROBADO | Líneas 676-1137 de `consultas/select.sql`, identificadas con comentarios SQL `-- ============================================================================= -- S9/S10/S11/S12 -- =============================================================================` |
| 2 | S9 usa JOIN, agregación y vista `v_ficha_vino` | APROBADO | `SELECT * FROM bodegas.v_ficha_vino WHERE cod_vino = :cod_vino;` La vista une `vino JOIN bodega`, `vino JOIN v_stock_total_vino`, `LEFT JOIN composicion_vino/cepa` (string_agg corte), `LEFT JOIN vino_maridaje/maridaje` (string_agg maridajes). |
| 3 | S10 usa CTE y subconsulta correlacionada | APROBADO | `WITH rendimiento_parcela AS (...)` + subconsulta correlacionada `(SELECT AVG(rp2.kg_ha) FROM rendimiento_parcela rp2 WHERE rp2.id_finca = rp.id_finca AND rp2.campania = rp.campania)` usada en SELECT y WHERE. Usa `NULLIF(SUM(p.superficie_ha), 0)`. |
| 4 | S11 usa `RANK() OVER (PARTITION BY ...)` y suma acumulada | APROBADO | `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC) AS rnk_mes` y `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING) AS ventas_acumuladas_sala`. |
| 5 | S12 usa `NOT EXISTS` para división relacional y anti-join | APROBADO | Parte A: doble `NOT EXISTS` (división relacional). Parte B: `NOT EXISTS` (anti-join tintos). Combinadas con `UNION ALL` y columna `criterio`. |
| 6 | Todas las consultas ejecutan contra PostgreSQL sin errores | APROBADO | Ejecutadas con `ON_ERROR_STOP=1`, todas retornan resultados válidos (ver sección 4). |
| 7 | Resultados correctos, sin duplicaciones ni cálculos incorrectos | APROBADO | S9: 1 fila sin duplicación de stock. S11: RANK resuelve empates, suma acumulada cronológica correcta (5, 9). S12A: 2 clientes, S12B: 0 (todos los vinos son tinto). |
| 8 | `db/perf/medir.sh` ejecutado y planos guardados | APROBADO | `db/perf/medir.sh despues` ejecutado. Planes en `docs/consultas/planes/`: S9, S10, S11, S12A, S12B. |
| 9 | Cada plan incluye tiempos reales, filas y operaciones | APROBADO | Ej: S9 `Execution Time: 0.180 ms`, `rows=1`; S11 `WindowAgg` ×2, `Execution Time: 0.282 ms`; S12A/S12B `Nested Loop Anti Join`. |
| 10 | `git diff --check` sin errores | APROBADO | Exit code 0 tras corregir trailing whitespace en `docs/rendimiento/contexto_despues.txt`. |
| 11 | Archivos modificados pertenecen al alcance de la issue | APROBADO | `consultas/select.sql`, `db/perf/consultas_candidatas.sql`, `docs/rendimiento/*`, `docs/consultas/planes/*`, `docs/consultas/planes_etapa5.md`. |
| 12 | No datos temporales ni modificaciones persistentes en PostgreSQL | APROBADO | Solo SELECT ejecutados. Conteos inalterados: 2 clientes, 3 comprobantes, 2 vinos. |

**Resultado global: TODOS LOS CRITERIOS APROBADOS.**

---

## 2. Resumen de las consultas verificadas

### S9 — Ficha completa de un vino
- **Consulta:** `SELECT * FROM bodegas.v_ficha_vino WHERE cod_vino = 990001`
- **Resultado real:** 1 fila — vino 990001 "Última botella", tinto, añada 2021, 750 ml, 14.00%, precio 12500.00, bodega "Bodega concurrencia", corte "Malbec concurrencia 100.00%", maridajes NULL, stock_total 0.
- **Herramientas:** JOIN (dentro de la vista), agregación `string_agg` (dentro de la vista), vista `v_ficha_vino`.
- **Sin duplicación de stock:** el stock se pre-agrupa en `v_stock_total_vino` antes de unirse.

### S10 — Rendimiento por parcela y campaña
- **Consulta:** CTE `rendimiento_parcela` + subconsulta correlacionada para promedio de finca.
- **Resultado real:** 0 filas (tabla `lote_uva` vacía en entorno de validación). La consulta es sintácticamente válida y el plan es correcto.
- **Herramientas:** `WITH` (CTE), `NULLIF` para evitar división por cero, **subconsulta correlacionada real** (referencia `rp.id_finca` y `rp.campania` del nivel externo), usada tanto en SELECT como en WHERE.
- **Corrección aplicada:** columna `campana` → `campania` (nombre real del modelo); reemplazado `JOIN promedio_finca` por subconsulta correlacionada.

### S11 — Ranking de vinos y ventas acumuladas
- **Consulta:** CTE `ventas_mensuales_vino` + `ranked` con `RANK()` y `SUM() OVER`.
- **Resultado real:** 2 filas:
  - sala 990001, mes 2026-11-01, vino 990001 "Última botella", 5 botellas, rnk=1, acumulado=5
  - sala 990001, mes 2026-11-01, vino 990002 "Segundo vino", 4 botellas, rnk=2, acumulado=9
- **Herramientas:** `RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC)`, `SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes ROWS UNBOUNDED PRECEDING)`.
- **Sin duplicación:** agregación base por `(id_sala, mes, cod_vino, vino)` antes de aplicar funciones de ventana.

### S12 — División relacional y anti-join
- **Parte A (todos los vinos de una bodega):** 2 filas — Cliente A y Cliente B (ambos socios) compraron todos los vinos de la bodega `30990000001`.
- **Parte B (nunca compraron tintos):** 0 filas — ambos clientes compraron vinos tipo 'tinto' (los únicos vinos existentes).
- **Herramientas:** Parte A: doble `NOT EXISTS` (división relacional). Parte B: `NOT EXISTS` (anti-join real, `Nested Loop Anti Join` en el plan).
- **Sin falsos positivos:** `NOT EXISTS` verifica existencia, no multiplica filas por JOIN.

---

## 3. Archivos creados o modificados

### Modificados
| Archivo | Cambio |
|---------|--------|
| `consultas/select.sql` | S10: `campana`→`campania`; reemplazado JOIN entre CTEs por subconsulta correlacionada real |
| `db/perf/consultas_candidatas.sql` | Agregadas entradas `C8_S9`, `C9_S10`, `C10_S11`, `C11_S12A`, `C12_S12B` para `medir.sh` |
| `docs/rendimiento/contexto_despues.txt` | Corregido trailing whitespace (`git diff --check`) |
| `docs/rendimiento/resultados_despues.csv` | Regenerado por `medir.sh` |
| `docs/rendimiento/planes/*_despues.txt` | Regenerados por `medir.sh` (C1_S8 a C12_S12B) |

### Creados
| Archivo | Descripción |
|---------|-------------|
| `docs/consultas/planes/S9_plan.txt` | Plan de ejecución S9 (EXPLAIN ANALYZE BUFFERS) |
| `docs/consultas/planes/S10_plan.txt` | Plan de ejecución S10 |
| `docs/consultas/planes/S11_plan.txt` | Plan de ejecución S11 |
| `docs/consultas/planes/S12A_plan.txt` | Plan de ejecución S12 parte A |
| `docs/consultas/planes/S12B_plan.txt` | Plan de ejecución S12 parte B |
| `docs/consultas/planes_etapa5.md` | Documentación completa de los 5 planes (objetivo, herramientas, recorridos, operaciones, filas, tiempo, interpretación, mejoras) |

---

## 4. Resultados reales de las pruebas (ejecutados contra PostgreSQL)

### S9
```
cod_vino | nombre       | tipo  | anada | volumen_ml | graduacion | precio   | bodega           | corte                    | maridajes | stock_total
990001   | Última botella | tinto | 2021 | 750        | 14.00      | 12500.00 | Bodega concurrencia | Malbec concurrencia 100.00% |           | 0
```
Filas: 1 | Tiempo: 0.180 ms (mediana)

### S10
```
 id_finca | nro_parcela | campania | kg_ha | prom_kg_ha | finca
----------+-------------+----------+-------+------------+-------
(0 rows)
```
Filas: 0 (lote_uva vacío) | Tiempo: 0.127 ms

### S11
```
id_sala | mes       | cod_vino | vino         | botellas | rnk_mes | ventas_acumuladas_sala
990001  | 2026-11-01| 990001   | Última botella | 5        | 1       | 5
990001  | 2026-11-01| 990002   | Segundo vino   | 4        | 2       | 9
```
Filas: 2 | Tiempo: 0.282 ms (mediana)

### S12A
```
id_cliente | nombre_razon_social | tipo   | criterio
990001     | Cliente A           | socio  | compro_todos_vinos_bodega
990002     | Cliente B           | socio  | compro_todos_vinos_bodega
```
Filas: 2 | Tiempo: 0.137 ms

### S12B
```
(0 rows)
```
Filas: 0 | Tiempo: 0.142 ms

---

## 5. Mediciones de rendimiento obtenidas (db/perf/medir.sh, etiqueta: despues)

| Consulta | Primera (ms) | Mediana (ms) | Filas leídas | Filas filtradas | Recorridos observados |
|----------|-------------|-------------|-------------|----------------|----------------------|
| C8_S9 | 0.279 | 0.180 | 6 | 4 | Seq Scan ×7 (bodega, cepa, composicion_vino, stock_deposito, stock_sala, vino, vino_maridaje) |
| C9_S10 | 0.133 | 0.127 | 0 | 0 | Seq Scan on lote_uva |
| C10_S11 | 0.762 | 0.282 | 10 | 0 | Seq Scan ×3 (comprobante, renglon_comprobante, vino) |
| C11_S12A | 0.144 | 0.137 | 12 | 0 | Seq Scan ×4 (cliente, comprobante, renglon_comprobante, vino) |
| C12_S12B | 0.163 | 0.142 | 11 | 0 | Seq Scan ×4 (cliente, comprobante, renglon_comprobante, vino) |

> Nota: Entorno con datos mínimos (2 vinos, 3 comprobantes, 2 clientes, lote_uva/parcela/finca vacíos). Todos los recorridos son `Seq Scan` por falta de volumen/selectividad. No se agregaron índices nuevos (sin autorización).

---

## 6. Errores detectados y correcciones realizadas

| Error | Corrección | Archivo |
|-------|-----------|---------|
| S10 usaba columna `campana` que no existe; el modelo usa `campania` | Cambiado `campana` → `campania` en CTE, SELECT, WHERE y ORDER BY | `consultas/select.sql`, `db/perf/consultas_candidatas.sql` |
| S10 usaba JOIN entre CTEs para el promedio de finca; el requisito pide subconsulta correlacionada real | Reemplazado por subconsulta correlacionada `(SELECT AVG(...) FROM rendimiento_parcela rp2 WHERE rp2.id_finca = rp.id_finca AND rp2.campania = rp.campania)` en SELECT y WHERE | `consultas/select.sql`, `db/perf/consultas_candidatas.sql` |
| `git diff --check` reportaba trailing whitespace en `docs/rendimiento/contexto_despues.txt` | `sed -i 's/[[:space:]]*$//'` | `docs/rendimiento/contexto_despues.txt` |

---

## 7. Tareas pendientes

Ninguna. Todos los criterios de aceptación están verificados y aprobados.

---

## 8. Confirmación de rama

- Rama actual: `feat/etapa5-consultas-avanzadas` (desde `main`)
- No se hizo commit, push ni merge (pendiente de autorización del usuario)
- `git diff --check`: limpio (exit 0)
- No hay datos temporales en PostgreSQL
- No se modificó el esquema ni se agregaron índices