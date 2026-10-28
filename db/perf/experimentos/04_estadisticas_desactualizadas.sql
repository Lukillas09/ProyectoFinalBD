-- Experimento 4: estadísticas desactualizadas.
-- Se usa un clon temporal de comprobante: los triggers impiden modificar
-- comprobantes reales, y autovacuum no analiza tablas temporales, así que la
-- estadística queda vieja hasta el ANALYZE manual (experimento determinista).
-- Transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;
CREATE TEMP TABLE clon AS
SELECT nro_comprobante, fecha, id_cliente, id_sala, total FROM comprobante;
CREATE INDEX exp_clon_sala ON clon (id_sala);
ANALYZE clon;

\echo '### A. Estadística inicial: la sala 1 es una de 40'
SELECT most_common_vals::TEXT::INTEGER[] AS valores_frecuentes_10,
       most_common_freqs[1:10] AS frecuencias
FROM pg_stats WHERE tablename = 'clon' AND attname = 'id_sala' LIMIT 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total) FROM clon WHERE id_sala = 1;

\echo '### B. Cambio de distribución SIN ANALYZE: el 90 % de las filas pasa a la sala 1'
UPDATE clon SET id_sala = 1 WHERE nro_comprobante % 10 <> 0;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total) FROM clon WHERE id_sala = 1;

\echo '### C. ANALYZE y el mismo plan otra vez'
ANALYZE clon;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total) FROM clon WHERE id_sala = 1;
ROLLBACK;
