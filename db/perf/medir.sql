-- Medición de consultas con EXPLAIN (ANALYZE, BUFFERS), dentro de PostgreSQL.
-- Lo ejecuta db/perf/medir.sh: este archivo define la función y medir.sh
-- agrega una llamada por cada consulta de consultas_candidatas.sql.
--
-- Protocolo por consulta:
--   1 ejecución inicial (caché fría o tibia) + N repeticiones;
--   se informa la primera y la mediana de las repeticiones;
--   el plan guardado es el de la repetición más cercana a la mediana.
-- Cada ejecución corre dentro de un bloque que termina en una excepción
-- propia: así una sentencia que modifica datos (DELETE) se revierte siempre.

\set ON_ERROR_STOP on
SET search_path TO bodegas, pg_catalog;

CREATE TEMP TABLE medicion (
  codigo TEXT,
  primera_ms NUMERIC,
  mediana_ms NUMERIC,
  minimo_ms NUMERIC,
  maximo_ms NUMERIC,
  recorridos TEXT,
  filas_leidas BIGINT,
  filas_descartadas_filtro BIGINT,
  heap_fetches BIGINT,
  shared_hit BIGINT,
  shared_read BIGINT,
  disparadores TEXT
);
CREATE TEMP TABLE plan_texto (codigo TEXT, n INTEGER, linea TEXT);

CREATE FUNCTION pg_temp.medir(p_codigo TEXT, p_sql TEXT, p_repeticiones INTEGER)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_planes TEXT[] := '{}';
  v_tiempos NUMERIC[] := '{}';
  v_plan TEXT;
  v_linea TEXT;
  v_mediana NUMERIC;
  v_elegido INTEGER;
  v_loops BIGINT := 1;
  v_leidas BIGINT := 0;
  v_filtradas BIGINT := 0;
  v_heap BIGINT := 0;
  v_recorridos TEXT[] := '{}';
  v_m TEXT[];
  v_n INTEGER := 0;
  v_buffers TEXT;
BEGIN
  FOR i IN 0..p_repeticiones LOOP
    v_plan := '';
    BEGIN
      FOR v_linea IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        v_plan := v_plan || v_linea || E'\n';
      END LOOP;
      RAISE EXCEPTION USING ERRCODE = 'P0099';  -- revierte cualquier efecto
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
      NULL;
    END;
    v_planes := v_planes || v_plan;
    v_tiempos := v_tiempos || substring(v_plan FROM 'Execution Time: ([0-9.]+) ms')::NUMERIC;
  END LOOP;

  -- Mediana de las repeticiones (sin la primera) y la más cercana a ella.
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY t) INTO v_mediana
  FROM unnest(v_tiempos[2:]) AS t;
  SELECT i INTO v_elegido
  FROM generate_subscripts(v_tiempos, 1) AS i
  WHERE i > 1
  ORDER BY abs(v_tiempos[i] - v_mediana), i
  LIMIT 1;
  v_plan := v_planes[v_elegido];

  -- Métricas del plan elegido. "rows" y "Rows Removed" son promedios por
  -- ejecución del nodo: se multiplican por loops para obtener el total.
  FOREACH v_linea IN ARRAY string_to_array(rtrim(v_plan, E'\n'), E'\n') LOOP
    v_n := v_n + 1;
    INSERT INTO plan_texto VALUES (p_codigo, v_n, v_linea);

    v_m := regexp_match(v_linea, 'actual time=[0-9.]+\.\.[0-9.]+ rows=([0-9]+) loops=([0-9]+)');
    IF v_m IS NOT NULL THEN
      v_loops := v_m[2]::BIGINT;
      v_m := regexp_match(v_linea,
        '((?:Parallel )?(?:Seq Scan|Index Only Scan(?: Backward)?|Index Scan(?: Backward)?|Bitmap Heap Scan|Bitmap Index Scan)) (?:using (\S+) )?on (\S+)');
      IF v_m IS NOT NULL THEN
        v_recorridos := v_recorridos || (v_m[1] || ' ' || COALESCE(v_m[2] || ' on ', 'on ') || v_m[3]);
        IF v_m[1] NOT LIKE 'Bitmap Index Scan' THEN
          v_leidas := v_leidas
            + (regexp_match(v_linea, 'rows=([0-9]+) loops=[0-9]+\)$'))[1]::BIGINT * v_loops;
        END IF;
      END IF;
    END IF;

    v_m := regexp_match(v_linea, 'Rows Removed by Filter: ([0-9]+)');
    IF v_m IS NOT NULL THEN
      v_filtradas := v_filtradas + v_m[1]::BIGINT * v_loops;
    END IF;
    v_m := regexp_match(v_linea, 'Heap Fetches: ([0-9]+)');
    IF v_m IS NOT NULL THEN
      v_heap := v_heap + v_m[1]::BIGINT * v_loops;
    END IF;
    -- La primera línea "Buffers:" es la del nodo raíz e incluye a sus hijos
    -- (no incluye el trabajo de los triggers de FK, que se informa aparte).
    IF v_buffers IS NULL AND v_linea ~ 'Buffers: shared' THEN
      v_buffers := v_linea;
    END IF;
  END LOOP;

  INSERT INTO medicion
  SELECT p_codigo,
         v_tiempos[1],
         round(v_mediana, 3),
         (SELECT min(t) FROM unnest(v_tiempos[2:]) AS t),
         (SELECT max(t) FROM unnest(v_tiempos[2:]) AS t),
         (SELECT string_agg(DISTINCT r, '; ') FROM unnest(v_recorridos) AS r),
         v_leidas,
         v_filtradas,
         v_heap,
         COALESCE(substring(v_buffers FROM 'hit=([0-9]+)')::BIGINT, 0),
         COALESCE(substring(v_buffers FROM 'read=([0-9]+)')::BIGINT, 0),
         (SELECT string_agg(m[1] || ' ' || m[2] || ' ms (' || m[3] || ' llamadas)', '; ')
          FROM regexp_matches(v_plan, 'Trigger for constraint (\S+): time=([0-9.]+) calls=([0-9]+)', 'g') AS m);
END;
$$;

ANALYZE;

\pset footer off
