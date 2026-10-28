-- Experimento 3: cuándo el planificador no usa un índice existente.
-- Índice de 008: comprobante (fecha) INCLUDE (id_sala, total).
-- A y B: el índice cubre la consulta (Index Only Scan): lo usa aun para el
--        83 % de la tabla, porque no necesita leer la tabla.
-- C y D: la consulta pide id_cliente, que no está en el índice: con baja
--        selectividad (83 %) prefiere recorrer la tabla. enable_seqscan = off
--        se usa SOLO para ver el costo del camino que descartó.
-- Transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;
CREATE INDEX exp_fecha_incl ON comprobante (fecha) INCLUDE (id_sala, total);
ANALYZE comprobante;

\echo '### Estadísticas de comprobante.fecha'
-- histogram_bounds es anyarray: se convierte para poder indexarlo.
SELECT n_distinct, correlation, cardinality(h) AS limites_histograma,
       h[1] AS primer_limite, h[cardinality(h)] AS ultimo_limite
FROM (SELECT n_distinct, correlation, histogram_bounds::TEXT::TIMESTAMPTZ[] AS h
      FROM pg_stats WHERE schemaname = 'bodegas' AND tablename = 'comprobante' AND attname = 'fecha') AS s;
SELECT count(*) FILTER (WHERE fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires') AS filas_5_anios,
       count(*) AS total,
       round(100.0 * count(*) FILTER (WHERE fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires') / count(*), 1) AS porcentaje
FROM comprobante;

\echo '### A. Último trimestre (pocas filas): usa el índice'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;

\echo '### B. Últimos 5 años (83 % de la tabla), consulta cubierta por el índice'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;

\echo '### C. Últimos 5 años pidiendo id_cliente (no está en el índice): recorre la tabla'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(DISTINCT c.id_cliente) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### D. Mismo caso forzando el índice (enable_seqscan = off, sólo para comparar costos)'
SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(DISTINCT c.id_cliente) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires';
RESET enable_seqscan;

\echo '### E. Sin forzar, con random_page_cost = 1.1 (valor habitual para SSD o datos en memoria)'
SET LOCAL random_page_cost = 1.1;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(DISTINCT c.id_cliente) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '5 years') AT TIME ZONE 'America/Argentina/Buenos_Aires';
ROLLBACK;
