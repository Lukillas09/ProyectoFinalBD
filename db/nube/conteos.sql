-- Filas por tabla del esquema bodegas (Etapa 8, backup y restauración).
-- Se corre en la base de Render y en la restaurada: las dos salidas deben ser
-- idénticas. query_to_xml permite un count(*) por tabla sin SQL dinámico en el
-- cliente; los nombres salen del catálogo, no de una entrada externa.
SELECT c.relname AS tabla,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM %I.%I', n.nspname, c.relname),
                           false, true, '')))[1]::text::bigint AS filas
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'bodegas' AND c.relkind IN ('r', 'p')
ORDER BY c.relname;
