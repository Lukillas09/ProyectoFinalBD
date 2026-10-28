-- Experimento 1: orden de las columnas del índice compuesto.
-- Misma consulta (ventas de la sala 2 en la última semana, núcleo de S3) con
-- (id_sala, fecha), con el orden inverso (fecha, id_sala), y la consulta de
-- S8 (sin sala fija) con (id_sala, fecha). Todo dentro de una transacción
-- revertida: la base no cambia. Cada EXPLAIN se ejecuta después de una
-- ejecución de calentamiento.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;

\echo '### A. Índice (id_sala, fecha): igualdad primero, rango después'
CREATE INDEX exp_sala_fecha ON comprobante (id_sala, fecha);
ANALYZE comprobante;
SELECT count(*) FROM comprobante WHERE id_sala = 2 AND fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires';
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente FROM comprobante AS c
WHERE c.id_sala = 2 AND c.fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### B. Orden inverso (fecha, id_sala): rango primero'
DROP INDEX exp_sala_fecha;
CREATE INDEX exp_fecha_sala ON comprobante (fecha, id_sala);
ANALYZE comprobante;
SELECT count(*) FROM comprobante WHERE id_sala = 2 AND fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires';
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente FROM comprobante AS c
WHERE c.id_sala = 2 AND c.fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### C. Orden inverso con un período largo (último año): el rango abarca miles de filas de otras salas'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente FROM comprobante AS c
WHERE c.id_sala = 2 AND c.fecha >= (CURRENT_DATE - INTERVAL '1 year') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### D. Mismo período largo con (id_sala, fecha)'
DROP INDEX exp_fecha_sala;
CREATE INDEX exp_sala_fecha ON comprobante (id_sala, fecha);
ANALYZE comprobante;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_cliente FROM comprobante AS c
WHERE c.id_sala = 2 AND c.fecha >= (CURRENT_DATE - INTERVAL '1 year') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### E. (id_sala, fecha) para S8 (todas las salas, sólo rango de fechas): la primera columna no está fijada'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_sala, sum(c.total) FROM comprobante AS c
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY c.id_sala;

ROLLBACK;
