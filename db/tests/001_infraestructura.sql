\set ON_ERROR_STOP on

-- Se ejecuta conectado como el mismo rol limitado que utiliza la API.
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

-- Prueba deliberadamente previa a las migraciones. Debe ejecutarse después de
-- un bootstrap limpio y antes de db/migrate.sh. Si las migraciones ya fueron
-- aplicadas, falla para no confundir ambos estados del ciclo de vida.
SELECT (
  NOT EXISTS (
    SELECT 1
    FROM pg_class AS objeto
    JOIN pg_namespace AS esquema ON esquema.oid = objeto.relnamespace
    WHERE esquema.nspname = 'bodegas'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_proc AS rutina
    JOIN pg_namespace AS esquema ON esquema.oid = rutina.pronamespace
    WHERE esquema.nspname = 'bodegas'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_type AS tipo
    JOIN pg_namespace AS esquema ON esquema.oid = tipo.typnamespace
    WHERE esquema.nspname = 'bodegas'
  )
) AS sin_objetos_negocio
\gset

\if :atributos_limitados
  \echo 'OK: el rol de la API no tiene atributos administrativos.'
\else
  \echo 'ERROR: el rol de la API tiene atributos administrativos.'
  \quit 1
\endif

\if :propietario_limitado
  \echo 'OK: el propietario es una cuenta separada y no administrativa.'
\else
  \echo 'ERROR: el propietario no cumple los atributos esperados.'
  \quit 1
\endif

\if :propiedad_esquema
  \echo 'OK: el propietario es dueño de la base y del esquema bodegas.'
\else
  \echo 'ERROR: la propiedad de la base o del esquema no es la esperada.'
  \quit 1
\endif

\if :permisos_limitados
  \echo 'OK: el rol de la API puede conectarse y no puede crear objetos.'
\else
  \echo 'ERROR: los privilegios del rol de la API no son los esperados.'
  \quit 1
\endif

\if :sin_membresias
  \echo 'OK: el rol de la API no hereda privilegios de otros roles.'
\else
  \echo 'ERROR: el rol de la API tiene membresías inesperadas.'
  \quit 1
\endif

\if :defaults_cerrados
  \echo 'OK: PUBLIC y la API no reciben privilegios predeterminados futuros.'
\else
  \echo 'ERROR: hay privilegios predeterminados futuros demasiado amplios.'
  \quit 1
\endif

\if :sin_objetos_negocio
  \echo 'OK: bootstrap aislado; todavía no hay objetos del modelo de negocio.'
\else
  \echo 'ERROR: esta prueba sólo corresponde al bootstrap previo a migraciones.'
  \quit 1
\endif
