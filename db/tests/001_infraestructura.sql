\set ON_ERROR_STOP on

-- Se ejecuta conectado como el mismo rol limitado que utiliza la API.
-- Es válida tanto después del bootstrap como después de migrar: comprueba
-- cuentas, propiedad y permisos, no el contenido del esquema.
--
-- psql no tiene un \quit con código de salida (ignora el argumento y sale con
-- 0). Por eso cada aserción falsa ejecuta un RAISE EXCEPTION: con
-- ON_ERROR_STOP, psql termina con código distinto de cero.
SELECT current_user AS rol_api, current_database() AS base_actual, 1 AS conexion;

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

SELECT pg_get_userbyid(datdba) AS owner_user
FROM pg_database
WHERE datname = current_database()
\gset

SELECT (
  :'owner_user' <> current_user
  AND NOT rolsuper
  AND NOT rolcreatedb
  AND NOT rolcreaterole
  AND NOT rolreplication
  AND NOT rolbypassrls
) AS propietario_limitado
FROM pg_roles
WHERE rolname = :'owner_user'
\gset

SELECT (
  pg_get_userbyid(nspowner) = :'owner_user'
) AS propiedad_esquema
FROM pg_namespace
WHERE nspname = 'bodegas'
\gset

SELECT (
  has_database_privilege(current_user, current_database(), 'CONNECT')
  AND NOT has_database_privilege(current_user, current_database(), 'CREATE')
  AND NOT has_database_privilege(current_user, current_database(), 'TEMPORARY')
  AND has_schema_privilege(current_user, 'bodegas', 'USAGE')
  AND NOT has_schema_privilege(current_user, 'bodegas', 'CREATE')
  AND NOT EXISTS (
    SELECT 1
    FROM pg_namespace
    WHERE nspname <> 'information_schema'
      AND nspname NOT LIKE 'pg\_%' ESCAPE '\'
      AND has_schema_privilege(current_user, oid, 'CREATE')
  )
) AS permisos_limitados
\gset

SELECT NOT EXISTS (
  SELECT 1
  FROM pg_auth_members
  WHERE member = (SELECT oid FROM pg_roles WHERE rolname = current_user)
) AS sin_membresias
\gset

SELECT NOT EXISTS (
  SELECT 1
  FROM pg_default_acl AS privilegio
  CROSS JOIN LATERAL aclexplode(privilegio.defaclacl) AS detalle
  WHERE privilegio.defaclrole = (
    SELECT oid FROM pg_roles WHERE rolname = :'owner_user'
  )
    AND detalle.grantee IN (
      0,
      (SELECT oid FROM pg_roles WHERE rolname = current_user)
    )
) AS defaults_cerrados
\gset

-- Antes de migrar no hay objetos y la condición se cumple trivialmente;
-- después, garantiza que ninguna migración se ejecutó con otra cuenta.
SELECT (
  NOT EXISTS (
    SELECT 1
    FROM pg_class AS objeto
    JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
    WHERE esquema.nspname = 'bodegas'
      AND pg_get_userbyid(objeto.relowner) <> :'owner_user'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_proc AS rutina
    JOIN pg_namespace AS esquema ON esquema.oid = rutina.pronamespace
    WHERE esquema.nspname = 'bodegas'
      AND pg_get_userbyid(rutina.proowner) <> :'owner_user'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_type AS tipo
    JOIN pg_namespace AS esquema ON esquema.oid = tipo.typnamespace
    WHERE esquema.nspname = 'bodegas'
      AND pg_get_userbyid(tipo.typowner) <> :'owner_user'
  )
) AS objetos_del_propietario
\gset

SELECT count(*) AS tablas_bodegas
FROM pg_class AS objeto
JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
WHERE esquema.nspname = 'bodegas'
  AND objeto.relkind = 'r'
\gset

\if :atributos_limitados
  \echo 'OK: el rol de la API no tiene atributos administrativos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'el rol de la API tiene atributos administrativos.'; END $$;
\endif

\if :propietario_limitado
  \echo 'OK: el propietario es una cuenta separada y no administrativa.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'el propietario no cumple los atributos esperados.'; END $$;
\endif

\if :propiedad_esquema
  \echo 'OK: el propietario es dueño de la base y del esquema bodegas.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'la propiedad de la base o del esquema no es la esperada.'; END $$;
\endif

\if :permisos_limitados
  \echo 'OK: el rol de la API puede conectarse y no puede crear objetos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'los privilegios del rol de la API no son los esperados.'; END $$;
\endif

\if :sin_membresias
  \echo 'OK: el rol de la API no hereda privilegios de otros roles.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'el rol de la API tiene membresías inesperadas.'; END $$;
\endif

\if :defaults_cerrados
  \echo 'OK: PUBLIC y la API no reciben privilegios predeterminados futuros.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'hay privilegios predeterminados futuros demasiado amplios.'; END $$;
\endif

\if :objetos_del_propietario
  \echo 'OK: todos los objetos del esquema bodegas pertenecen al propietario.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'hay objetos del esquema bodegas creados por otra cuenta.'; END $$;
\endif

-- Informativo: describe el momento del ciclo de vida sin hacer fallar la prueba.
\echo 'INFO: tablas actuales en el esquema bodegas:' :tablas_bodegas
