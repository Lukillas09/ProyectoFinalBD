# Comentario de revisión — PR #5

**PR:** #5 — Etapa 4: índices y rendimiento  
**Rama:** `etapa-4-indices` → `main` (mergeado)  
**Estado:** cerrado y mergeado  
**Enlace:** https://github.com/Lukillas09/ProyectoFinalBD/pull/5

## Parte del código revisada

`db/migrations/008_indices.sql` (6 índices); `db/perf/` (`medir.sh`, `medir.sql`, `consultas_candidatas.sql`, `experimentos.sh` y 6 experimentos SQL); documentación `docs/rendimiento.md` con planes de ejecución (`docs/rendimiento/planes/`), métricas (`resultados_antes.csv`, `resultados_despues.csv`), contexto (`contexto_antes.txt`, `contexto_despues.txt`) y salidas de experimentos (`docs/rendimiento/experimentos/`); cambios en `README.md`, `AGENTS.md`, `requisitos.md`.

## Qué se verificó

- **Seis índices nuevos (unos 15,8 MB), en total 48 índices en el esquema** (31 de PK + 11 de `UNIQUE` + 6 nuevos). Ninguna migración previa (001 a 007) se modificó.
- **Cada índice justificado con una medida real** (`EXPLAIN (ANALYZE, BUFFERS)`): consulta que acelera, tipo, orden de columnas, tamaño y tiempo de creación, todo documentado en el comentario de cada índice y en `docs/rendimiento.md`.
- **`idx_comprobante_id_sala_fecha (id_sala, fecha)`** — compuesto, igualidad primero y rango después. Para S3/S11. Se midió que el orden inverso `(fecha, id_sala)` lee más páginas de índice (99 vs 6 para el último año) porque recorre todas las salas del período y filtra `id_sala` dentro del índice.
- **`idx_comprobante_fecha (fecha) INCLUDE (id_sala, total)`** — variante con `INCLUDE` para consultas sin sala fija (S8, `v_ventas_mensuales_sala` por períodos). Permite **Index Only Scan** sin leer la tabla (`Heap Fetches: 0`) si el visibility map está al día.
- **`idx_comprobante_id_cliente (id_cliente)`** — índice de FK que PostgreSQL **no crea automáticamente**. Sin él, el control de `fk_comprobante_cliente` recorre los 150.125 comprobantes por cada cliente borrado (D4/D6) y se usa en anti-joins "clientes sin compras" (S12).
- **`idx_renglon_comprobante_cod_vino (cod_vino)`** — la PK `(nro_comprobante, cod_vino)` no sirve para buscar por la segunda columna. Acelera ventas de un vino (S9, S12) y el control `RESTRICT` al borrar/cambiar un vino.
- **`idx_transferencia_pendientes (id_sala) WHERE estado <> 'procesado'`** — parcial: solo 7 de 5.088 transferencias, 16 kB. El planificador lo usa solo si puede probar que el filtro de la consulta implica el del índice (p. ej. `estado <> 'procesado'` o `estado IN ('en_confeccion','terminado')`; **no** con `CURRENT_DATE - 7`).
- **`idx_auditoria_precio_cod_vino_fecha (cod_vino, fecha_hora)`** — compuesto para precio vigente: igualdad por vino y `ORDER BY fecha_hora DESC LIMIT 1`, resuelto con `Index Scan Backward`. Base de `U1`.
- **`CREATE INDEX`, no `CONCURRENTLY`:** `CONCURRENTLY` no puede ejecutarse dentro de una transacción y `migrate.sh` envuelve cada migración en una. Bloquea escrituras (no lecturas) mientras se construye; aquí dura décimas de segundo.
- **Medidas reales (mediana de 5 repeticiones):** C1 S8 −88,5 % (23,4 → 2,7 ms), C2 S3 −98,1 % (6,5 → 0,12 ms), C3 S5 −36 %, C4 D4 −98,5 % (3.620 → 53,6 ms; el control de la FK bajó de 3.517 ms a 11,3 ms), C5 ventas de un vino −36 % (27,7 → 17,8 ms), C6 precio vigente −95,8 % (693 → 29,2 ms), C7 S1 sin cambio de plan (control negativo, Seq Scan).
- **Costo de escritura medido:** carga de comprobantes ~7 veces más lenta con los índices; venta por el camino real `+35 %` (1,19 → 1,61 ms por venta), aceptable frente a lo que ganan las consultas.
- **Índices evaluados y descartados (medidos):** BRIN sobre `fecha` (correlación −0,005, no descarta nada; forzado es igual o peor), Hash sobre `id_cliente` (más grande que B-tree y no sirve para rango), índice de expresión por mes (`date_trunc` sobre `TIMESTAMPTZ` es `STABLE`, no `IMMUTABLE`, y ninguna consulta filtra por mes).
- **Etapa 4 verificada:** `run_all.sh` 7 de 7, `controles.sql` y `post_carga.sql` sobre base con `008`, prueba desde cero en proyecto aislado, `/salud` responde 200.

## Decisiones técnicas importantes

- **Criterio de aceptación:** se crearon solo los índices que una consulta medida justifica; se descartaron los que no ganan nada (BRIN, Hash, expresión por mes). Cada índice tiene su costo de escritura y espacio, documentado en `docs/rendimiento.md` 9.
- **Baja selectividad y páginas vacías:** `docs/rendimiento.md` 8.1 explica que el planificador puede no usar un índice existente aunque exista (caso C: pide una columna no cubierta, estima más caro que Seq Scan). La tabla `comprobante` tiene páginas vacías por el `UPDATE` posterior de la carga (mejora pendiente de Etapa 3).
- **C7 como control negativo:** confirma que no todos los índices ayudan; un Seq Scan es correcto para agregar toda la tabla (S1 ranking de los 10 vinos más vendidos).

## Dudas o mejoras detectadas

- Ningún error funcional. Oportunidad de mejora (Etapa 5): medir S9 a S12 con `EXPLAIN (ANALYZE)`; S9 y S12 deberían aprovechar `idx_renglon_comprobante_cod_vino`, y S12 también `idx_comprobante_id_cliente` (`docs/rendimiento.md` 12).
- **Materialización de `v_ventas_mensuales_sala`:** `docs/rendimiento.md` 13 mide una versión materializada (más rápida, 0,1-1,0 ms) pero decide **NO materializar**: las consultas típicas ya resuelven en 5,7-76,2 ms con la vista convencional, materializar introduce datos obsoletos entre refrescos y añade ~182 ms de costo por refresco en el camino de venta, y no hay consumidor de alta frecuencia aún. Un integrante debe poder defender esta decisión.
- Los tiempos dependen de la máquina y de la fecha de carga; solo se comparan mediciones tomadas en el mismo entorno.

## Aspectos que debe poder explicar cada integrante en la defensa

1. Qué seis índices se crearon en `008_indices.sql` y qué consulta acelera cada uno.
2. Por qué el orden de columnas del compuesto es `(id_sala, fecha)` y no `(fecha, id_sala)` (igualdad primero, rango después).
3. Para qué sirve `INCLUDE (id_sala, total)` y qué es un Index Only Scan.
4. Por qué PostgreSQL no indexa las FK automáticamente y cuál es el impacto de no tener `idx_comprobante_id_cliente` al borrar clientes.
5. Por qué la PK de `renglon_comprobante` no sirve para buscar por `cod_vino` y qué índice lo resuelve.
6. Qué es un índice parcial, cuándo el planificador lo usa y por qué `CURRENT_DATE` impide usarlo (no es constante al planificar).
7. Qué es `EXPLAIN (ANALYZE, BUFFERS)` y cómo se interpreta un plan (Seq Scan, Index Scan, Bitmap Heap Scan, Index Only Scan).
8. Cuál es el costo de escritura y de espacio de los índices, y por qué no se creó un índice por cada consulta posible.
9. Por qué se descartaron BRIN, Hash y el índice de expresión por mes (mediciones reales).
10. Por qué se decidió NO materializar `v_ventas_mensuales_sala` a pesar de que es más rápida.

Archivos para comprobar: `db/migrations/008_indices.sql`, `db/perf/consultas_candidatas.sql`, `db/perf/medir.sh`, `docs/rendimiento.md` (secciones 3, 4, 6, 7, 8, 9, 12, 13), `docs/rendimiento/planes/`, `docs/rendimiento/experimentos/`.
