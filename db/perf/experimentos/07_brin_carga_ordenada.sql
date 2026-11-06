-- Experimento 7: BRIN sobre comprobante.fecha con la carga corregida de la
-- Etapa 5, que inserta los comprobantes en orden de fecha
-- (docs/carga_masiva.md, sección 11; docs/rendimiento.md, sección 6.1).
-- Compara tres caminos para las ventas del último trimestre: sin índice sobre
-- fecha, sólo BRIN y el B-tree con INCLUDE de 008_indices.sql.
-- Todo lo que cambia el esquema ocurre dentro de una transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;

\echo '### 1. Orden físico después de ANALYZE (1 = ordenada, 0 = al azar)'
ANALYZE comprobante;
SELECT attname, round(correlation::numeric, 5) AS correlation FROM pg_stats
WHERE schemaname = 'bodegas' AND tablename = 'comprobante' AND attname IN ('fecha', 'nro_comprobante');
SELECT relpages AS paginas,
       (SELECT count(DISTINCT (ctid::text::point)[0]) FROM comprobante) AS paginas_con_filas,
       pg_size_pretty(pg_relation_size('comprobante')) AS tamano
FROM pg_class WHERE oid = 'comprobante'::regclass;
SELECT count(*) AS filas_ultimo_trimestre FROM comprobante
WHERE fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### 2. Con los índices de 008 (idx_comprobante_fecha INCLUDE), tres ejecuciones'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;

BEGIN;
-- Se quitan los índices de 008 que contienen fecha para aislar cada camino;
-- el ROLLBACK los restaura.
DROP INDEX idx_comprobante_fecha;
DROP INDEX idx_comprobante_id_sala_fecha;

\echo '### 3. Sin índice sobre fecha, tres ejecuciones'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;

\echo '### 4. Sólo BRIN (sin forzar el planificador), tres ejecuciones'
CREATE INDEX exp_brin_fecha ON comprobante USING brin (fecha);
CREATE INDEX exp_btree_fecha ON comprobante (fecha);
SELECT pg_size_pretty(pg_relation_size('exp_brin_fecha')) AS tamano_brin,
       pg_size_pretty(pg_relation_size('exp_btree_fecha')) AS tamano_btree_solo_fecha;
DROP INDEX exp_btree_fecha;
ANALYZE comprobante;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
ROLLBACK;

\echo '### 5. Los índices quedaron como estaban'
SELECT count(*) AS indices_en_bodegas FROM pg_indexes WHERE schemaname = 'bodegas';
