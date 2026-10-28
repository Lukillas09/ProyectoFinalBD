-- Experimento 2: índices evaluados y descartados.
-- A. BRIN sobre comprobante.fecha: depende de que el orden físico de la tabla
--    siga a la fecha. Se mide sobre la tabla real y sobre una copia ordenada.
-- B. Hash frente a B-tree sobre comprobante.id_cliente (búsqueda por igualdad).
-- Todo dentro de una transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;

\echo '### A1. Correlación entre el orden físico y la fecha (1 = ordenada, 0 = al azar)'
SELECT tablename, attname, correlation FROM pg_stats
WHERE schemaname = 'bodegas' AND tablename = 'comprobante' AND attname IN ('fecha', 'nro_comprobante');

\echo '### A2. BRIN sobre la tabla real'
CREATE INDEX exp_brin_fecha ON comprobante USING brin (fecha);
ANALYZE comprobante;
SELECT pg_size_pretty(pg_relation_size('exp_brin_fecha')) AS tamano_brin;
\echo 'Plan elegido por el planificador:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
\echo 'Forzando el uso del BRIN (enable_seqscan = off, sólo para comparar):'
SET LOCAL enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;
RESET enable_seqscan;

\echo '### A3. La misma tabla copiada en orden de fecha'
CREATE TEMP TABLE comprobante_ordenado AS
SELECT nro_comprobante, fecha, id_cliente, id_sala, total FROM comprobante ORDER BY fecha;
ANALYZE comprobante_ordenado;
SELECT attname, correlation FROM pg_stats WHERE tablename = 'comprobante_ordenado' AND attname = 'fecha';
CREATE INDEX exp_brin_fecha_ordenado ON comprobante_ordenado USING brin (fecha);
CREATE INDEX exp_btree_fecha_ordenado ON comprobante_ordenado (fecha);
SELECT pg_size_pretty(pg_relation_size('exp_brin_fecha_ordenado')) AS tamano_brin,
       pg_size_pretty(pg_relation_size('exp_btree_fecha_ordenado')) AS tamano_btree;
DROP INDEX exp_btree_fecha_ordenado;
ANALYZE comprobante_ordenado;
SELECT count(*) FROM comprobante_ordenado WHERE fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires';
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_sala, sum(total) FROM comprobante_ordenado
WHERE fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY id_sala;

\echo '### B. Hash frente a B-tree sobre comprobante.id_cliente'
CREATE INDEX exp_btree_cliente ON comprobante (id_cliente);
CREATE INDEX exp_hash_cliente ON comprobante USING hash (id_cliente);
SELECT pg_size_pretty(pg_relation_size('exp_btree_cliente')) AS tamano_btree,
       pg_size_pretty(pg_relation_size('exp_hash_cliente')) AS tamano_hash;
ANALYZE comprobante;
\echo 'Igualdad (cliente 1500): el planificador puede elegir cualquiera de los dos'
EXPLAIN (ANALYZE, BUFFERS) SELECT nro_comprobante FROM comprobante WHERE id_cliente = 1500;
DROP INDEX exp_btree_cliente;
\echo 'Sólo con Hash: igualdad'
EXPLAIN (ANALYZE, BUFFERS) SELECT nro_comprobante FROM comprobante WHERE id_cliente = 1500;
\echo 'Sólo con Hash: rango (no lo puede usar)'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM comprobante WHERE id_cliente BETWEEN 1500 AND 1510;

ROLLBACK;
