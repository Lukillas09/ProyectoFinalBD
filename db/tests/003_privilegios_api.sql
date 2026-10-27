\set ON_ERROR_STOP on

-- Ejecutar como el mismo rol limitado de la API, después de las migraciones.
-- Cada aserción falsa ejecuta RAISE EXCEPTION para que psql, con
-- ON_ERROR_STOP, termine con código distinto de cero.
SELECT (
  NOT rolsuper
  AND NOT rolcreatedb
  AND NOT rolcreaterole
  AND NOT rolreplication
  AND NOT rolbypassrls
) AS atributos_limitados
FROM pg_roles
WHERE rolname = current_user
\gset

SELECT (
  has_schema_privilege(current_user, 'bodegas', 'USAGE')
  AND NOT has_schema_privilege(current_user, 'bodegas', 'CREATE')
) AS esquema_limitado
\gset

SELECT (
  (SELECT count(*)
   FROM pg_class AS objeto
   JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
   WHERE esquema.nspname = 'bodegas'
     AND objeto.relkind = 'r') = 31
  AND NOT EXISTS (
    SELECT 1
    FROM pg_class AS objeto
    JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
    WHERE esquema.nspname = 'bodegas'
      AND objeto.relkind IN ('r', 'p', 'v', 'm')
      AND (
        has_table_privilege(current_user, objeto.oid, 'SELECT')
        OR has_table_privilege(current_user, objeto.oid, 'INSERT')
        OR has_table_privilege(current_user, objeto.oid, 'UPDATE')
        OR has_table_privilege(current_user, objeto.oid, 'DELETE')
        OR has_table_privilege(current_user, objeto.oid, 'TRUNCATE')
        OR has_table_privilege(current_user, objeto.oid, 'REFERENCES')
        OR has_table_privilege(current_user, objeto.oid, 'TRIGGER')
      )
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_class AS objeto
    JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
    WHERE esquema.nspname = 'bodegas'
      AND objeto.relkind = 'S'
      AND (
        has_sequence_privilege(current_user, objeto.oid, 'USAGE')
        OR has_sequence_privilege(current_user, objeto.oid, 'SELECT')
        OR has_sequence_privilege(current_user, objeto.oid, 'UPDATE')
      )
  )
) AS sin_privilegios_objetos
\gset

\if :atributos_limitados
  \echo 'OK: la API sigue sin atributos administrativos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'la API tiene atributos administrativos.'; END $$;
\endif

\if :esquema_limitado
  \echo 'OK: la API usa el esquema pero no puede crear objetos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'privilegios incorrectos sobre el esquema.'; END $$;
\endif

\if :sin_privilegios_objetos
  \echo 'OK: existen 31 tablas y la API aún no tiene DML ni acceso a secuencias.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'cantidad de tablas o privilegios de la API inesperados.'; END $$;
\endif
