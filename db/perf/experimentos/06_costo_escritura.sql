-- Experimento 6: costo de escritura de los índices de 008.
-- A. Carga de 150.125 comprobantes y 538.306 renglones en clones temporales,
--    sólo con la PK y con la PK más los índices nuevos (3 corridas cada una).
-- B. Ventas con fn_registrar_venta (camino real, con triggers) sin y con los
--    índices nuevos sobre las tablas reales.
-- Todo dentro de una transacción revertida.
\set ON_ERROR_STOP on
\pset pager off
SET search_path TO bodegas, pg_catalog;
BEGIN;

CREATE TEMP TABLE costo (prueba TEXT, corrida INTEGER, segundos NUMERIC);

CREATE FUNCTION pg_temp.cargar(p_tabla TEXT, p_origen TEXT, p_prueba TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  v_inicio TIMESTAMPTZ;
BEGIN
  FOR i IN 1..3 LOOP
    EXECUTE format('TRUNCATE %s', p_tabla);
    v_inicio := clock_timestamp();
    EXECUTE format('INSERT INTO %s SELECT * FROM %s', p_tabla, p_origen);
    INSERT INTO costo VALUES (p_prueba, i, extract(epoch FROM clock_timestamp() - v_inicio));
  END LOOP;
END;
$$;

CREATE TEMP TABLE c_comprobante (LIKE comprobante INCLUDING DEFAULTS);
ALTER TABLE c_comprobante ADD PRIMARY KEY (nro_comprobante);
CREATE TEMP TABLE c_renglon (LIKE renglon_comprobante INCLUDING DEFAULTS);
ALTER TABLE c_renglon ADD PRIMARY KEY (nro_comprobante, cod_vino);

SELECT pg_temp.cargar('c_comprobante', 'comprobante', 'comprobante: sólo PK');
SELECT pg_temp.cargar('c_renglon', 'renglon_comprobante', 'renglon_comprobante: sólo PK');

CREATE INDEX ON c_comprobante (id_sala, fecha);
CREATE INDEX ON c_comprobante (fecha) INCLUDE (id_sala, total);
CREATE INDEX ON c_comprobante (id_cliente);
CREATE INDEX ON c_renglon (cod_vino);

SELECT pg_temp.cargar('c_comprobante', 'comprobante', 'comprobante: PK + 3 índices de 008');
SELECT pg_temp.cargar('c_renglon', 'renglon_comprobante', 'renglon_comprobante: PK + índice de 008');

\echo '### A. Carga masiva en clones (segundos por corrida)'
SELECT prueba, string_agg(round(segundos, 3)::TEXT, ' / ' ORDER BY corrida) AS corridas,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY segundos)::NUMERIC, 3) AS mediana
FROM costo GROUP BY prueba ORDER BY prueba;

\echo '### Tamaño de tablas e índices en los clones'
SELECT c.relname AS tabla, pg_size_pretty(pg_relation_size(c.oid)) AS tabla_tamano,
       pg_size_pretty(pg_indexes_size(c.oid)) AS indices_tamano,
       (SELECT count(*) FROM pg_index AS i WHERE i.indrelid = c.oid) AS indices
FROM pg_class AS c WHERE c.relname IN ('c_comprobante', 'c_renglon') AND c.relpersistence = 't';

\echo '### B. Ventas por el camino real (fn_registrar_venta): 300 ventas de 3 vinos'
-- Stock de sobra en la sala 1 para los vinos elegidos (se revierte).
CREATE TEMP TABLE vinos_venta AS
SELECT cod_vino FROM stock_sala WHERE id_sala = 1 ORDER BY cod_vino LIMIT 9;
UPDATE stock_sala SET cantidad = cantidad + 100000
WHERE id_sala = 1 AND cod_vino IN (SELECT cod_vino FROM vinos_venta);

-- Devuelve los segundos: el ROLLBACK TO SAVEPOINT deshace las ventas (y
-- cualquier fila escrita dentro), así que el tiempo se guarda con \gset.
CREATE FUNCTION pg_temp.vender() RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
  v_vinos BIGINT[];
  v_inicio TIMESTAMPTZ;
BEGIN
  SELECT array_agg(cod_vino ORDER BY cod_vino) INTO v_vinos FROM vinos_venta;
  v_inicio := clock_timestamp();
  FOR i IN 0..299 LOOP
    PERFORM fn_registrar_venta(1, 1, v_vinos[(i % 3) * 3 + 1 : (i % 3) * 3 + 3], ARRAY[1, 1, 1]);
  END LOOP;
  RETURN extract(epoch FROM clock_timestamp() - v_inicio);
END;
$$;

-- Cada tanda parte del mismo estado gracias al SAVEPOINT; la primera
-- calienta la caché y no se informa.
SAVEPOINT tanda;
SELECT pg_temp.vender() AS calentamiento \gset
ROLLBACK TO SAVEPOINT tanda;
SELECT pg_temp.vender() AS sin1 \gset
ROLLBACK TO SAVEPOINT tanda;
SELECT pg_temp.vender() AS sin2 \gset
ROLLBACK TO SAVEPOINT tanda;
CREATE INDEX ON comprobante (id_sala, fecha);
CREATE INDEX ON comprobante (fecha) INCLUDE (id_sala, total);
CREATE INDEX ON comprobante (id_cliente);
CREATE INDEX ON renglon_comprobante (cod_vino);
SAVEPOINT tanda_indices;
SELECT pg_temp.vender() AS con1 \gset
ROLLBACK TO SAVEPOINT tanda_indices;
SELECT pg_temp.vender() AS con2 \gset
ROLLBACK TO SAVEPOINT tanda_indices;

INSERT INTO costo VALUES
  ('ventas: sin índices de 008', 1, :sin1), ('ventas: sin índices de 008', 2, :sin2),
  ('ventas: con índices de 008', 1, :con1), ('ventas: con índices de 008', 2, :con2);
SELECT prueba, string_agg(round(segundos, 3)::TEXT, ' / ' ORDER BY corrida) AS segundos_300_ventas,
       round(avg(segundos) / 300 * 1000, 2) AS ms_por_venta
FROM costo WHERE prueba LIKE 'ventas%' GROUP BY prueba ORDER BY prueba DESC;
ROLLBACK;
