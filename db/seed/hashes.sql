\set ON_ERROR_STOP on
\pset pager off

-- Huella de cada tabla de negocio, para comprobar que dos cargas con la misma
-- SEMILLA, FECHA_REFERENCIA y ESCALA producen los mismos datos.
-- md5 de todas las filas, en texto, ordenadas por la clave primaria.
-- Se excluye comprobante.xact_alta: es el identificador de la transacción de
-- carga y no puede repetirse entre ejecuciones. También schema_migration, que
-- registra el instante de aplicación de cada migración.
-- La zona horaria y el estilo de fecha se fijan para que el texto de los
-- TIMESTAMPTZ no dependa de la sesión.

SET TimeZone = 'UTC';
SET DateStyle = 'ISO, YMD';

SELECT string_agg(
         format('SELECT %L AS tabla, count(*) AS filas, md5(COALESCE(string_agg(ROW(%s)::TEXT, %L ORDER BY %s), %L)) AS huella FROM bodegas.%I',
                c.relname, columnas.lista, E'\n', clave.lista, '', c.relname),
         E'\nUNION ALL\n' ORDER BY c.relname)
       || E'\nORDER BY tabla'
FROM pg_class AS c
JOIN LATERAL (
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) AS lista
  FROM pg_attribute AS a
  WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    AND NOT (c.relname = 'comprobante' AND a.attname = 'xact_alta')
) AS columnas ON true
JOIN LATERAL (
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY array_position(i.indkey::SMALLINT[], a.attnum)) AS lista
  FROM pg_index AS i
  JOIN pg_attribute AS a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
  WHERE i.indrelid = c.oid AND i.indisprimary
) AS clave ON true
WHERE c.relnamespace = 'bodegas'::regnamespace AND c.relkind = 'r' AND c.relname <> 'schema_migration'
\gexec
