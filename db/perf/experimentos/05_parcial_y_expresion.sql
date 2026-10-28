-- Experimento 5: cuándo el planificador puede usar un índice parcial, y por
-- qué date_trunc sobre TIMESTAMPTZ no se puede indexar.
-- Transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;

\echo '### A. Índice parcial de 008 (estado <> procesado) y distintas formas de pedir pendientes'
CREATE INDEX exp_pendientes ON transferencia (id_sala) WHERE estado <> 'procesado';
ANALYZE transferencia;
\echo 'A1. Mismo predicado que el índice:'
EXPLAIN (ANALYZE) SELECT id_sala, count(*) FROM transferencia WHERE estado <> 'procesado' GROUP BY id_sala;
\echo 'A2. Predicado equivalente para el negocio pero escrito con IN:'
EXPLAIN (ANALYZE) SELECT id_sala, count(*) FROM transferencia WHERE estado IN ('en_confeccion', 'terminado') GROUP BY id_sala;

\echo '### B. Parcial con fecha fija ("del año actual" en el apunte): WHERE fecha >= 2026-01-01'
CREATE INDEX exp_parcial_fecha ON comprobante (fecha) WHERE fecha >= '2026-01-01 00:00-03';
ANALYZE comprobante;
\echo 'B1. Consulta con fecha literal posterior al límite: el planificador prueba la implicación'
EXPLAIN (ANALYZE) SELECT count(*) FROM comprobante WHERE fecha >= '2026-10-21 00:00-03';
\echo 'B2. La misma idea con CURRENT_DATE: no puede probarla al planificar'
EXPLAIN (ANALYZE) SELECT count(*) FROM comprobante
WHERE fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '### C. Índice de expresión por mes'
\echo 'C1. date_trunc(month, fecha) con fecha TIMESTAMPTZ: el resultado depende de TimeZone'
SAVEPOINT c1;
\set ON_ERROR_STOP off
CREATE INDEX exp_mes ON comprobante (date_trunc('month', fecha));
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT c1;
\echo 'Volatilidad de las funciones involucradas (i = IMMUTABLE, s = STABLE):'
SELECT p.oid::regprocedure AS funcion, p.provolatile
FROM pg_proc AS p
WHERE p.oid IN ('date_trunc(text, timestamp with time zone)'::regprocedure,
                'date_trunc(text, timestamp without time zone)'::regprocedure,
                'timezone(text, timestamp with time zone)'::regprocedure)
ORDER BY 1::TEXT;
\echo 'C2. Alternativa: fijar la zona horaria antes de truncar (timestamp sin zona)'
CREATE INDEX exp_mes_local ON comprobante (date_trunc('month', fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'));
SELECT pg_size_pretty(pg_relation_size('exp_mes_local')) AS tamano;
ROLLBACK;
