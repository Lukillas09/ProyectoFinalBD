#!/bin/sh
# Bootstrap de roles y esquema en Render (Etapa 8, issue #67).
#
# Hace lo mismo que db/bootstrap/001_roles_y_esquema.sh, pero lo ejecuta el
# usuario administrador de Render, que NO es superusuario (tiene CREATEROLE y
# CREATEDB). En PostgreSQL 16 eso obliga a cambiar el orden:
#   1. Para traspasar la base a bodegas_owner, el administrador tiene que poder
#      hacer SET ROLE a ese rol: se concede la membresía WITH SET TRUE (el
#      administrador tiene ADMIN OPTION sobre los roles que crea).
#   2. Los permisos sobre la base, el esquema public y el esquema bodegas los
#      da el nuevo dueño (SET ROLE bodegas_owner): un no superusuario sólo
#      puede otorgar privilegios sobre objetos de los que es dueño.
#   3. Al final se revoca la membresía: el administrador no queda con acceso
#      a los datos a través del propietario.
# Mismos roles, mismos atributos y mismos permisos que en local.
set -eu

: "${POSTGRES_DB:?POSTGRES_DB es obligatoria}"
: "${RENDER_ADMIN_USER:?RENDER_ADMIN_USER es obligatoria}"
: "${RENDER_ADMIN_PASSWORD:?RENDER_ADMIN_PASSWORD es obligatoria}"
: "${DB_OWNER_USER:?}" "${DB_OWNER_PASSWORD:?}" "${DB_APP_USER:?}" "${DB_APP_PASSWORD:?}"
: "${DB_REPORT_USER:?}" "${DB_REPORT_PASSWORD:?}"

if [ "$(printf '%s\n' "$RENDER_ADMIN_USER" "$DB_OWNER_USER" "$DB_APP_USER" "$DB_REPORT_USER" | sort -u | wc -l)" -ne 4 ] \
  || [ "$(printf '%s\n' "$RENDER_ADMIN_PASSWORD" "$DB_OWNER_PASSWORD" "$DB_APP_PASSWORD" "$DB_REPORT_PASSWORD" | sort -u | wc -l)" -ne 4 ]; then
  echo "Administrador, propietario, API y reportes deben ser cuentas distintas, con contraseñas distintas." >&2
  exit 1
fi

export PGUSER="$RENDER_ADMIN_USER" PGPASSWORD="$RENDER_ADMIN_PASSWORD" PGDATABASE="$POSTGRES_DB"

psql \
  --set=ON_ERROR_STOP=1 \
  --set=db_name="$POSTGRES_DB" \
  --set=owner_user="$DB_OWNER_USER" \
  --set=owner_password="$DB_OWNER_PASSWORD" \
  --set=app_user="$DB_APP_USER" \
  --set=app_password="$DB_APP_PASSWORD" \
  --set=report_user="$DB_REPORT_USER" \
  --set=report_password="$DB_REPORT_PASSWORD" <<'SQL'
BEGIN;

-- Cuentas de conexión: propietario, API y reportes.
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  usuario, clave)
FROM (VALUES (:'owner_user', :'owner_password'), (:'app_user', :'app_password'),
             (:'report_user', :'report_password')) AS cuenta(usuario, clave)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = usuario)
\gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', usuario, clave)
FROM (VALUES (:'owner_user', :'owner_password'), (:'app_user', :'app_password'),
             (:'report_user', :'report_password')) AS cuenta(usuario, clave)
\gexec

-- Roles de grupo con nombre fijo (007_roles.sql les da los permisos).
SELECT format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS', grupo)
FROM (VALUES ('bodegas_rw'), ('bodegas_ro')) AS g(grupo)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = grupo)
\gexec

GRANT bodegas_rw TO :"app_user" WITH INHERIT TRUE;
GRANT bodegas_ro TO :"report_user" WITH INHERIT TRUE;
GRANT bodegas_rw, bodegas_ro TO :"owner_user" WITH INHERIT FALSE, SET TRUE;

-- search_path de cada cuenta (lo puede fijar quien tiene CREATEROLE).
ALTER ROLE :"owner_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;
ALTER ROLE :"app_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;
ALTER ROLE :"report_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;

-- (1) Traspaso de la base al propietario del proyecto.
GRANT :"owner_user" TO CURRENT_USER WITH INHERIT FALSE, SET TRUE;
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'owner_user')
\gexec

-- (2) Desde acá, como dueño de la base (y por eso del esquema public).
SET ROLE :"owner_user";

REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO :"owner_user", :"app_user", :"report_user";

REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS bodegas;
REVOKE ALL ON SCHEMA bodegas FROM PUBLIC;
GRANT USAGE ON SCHEMA bodegas TO bodegas_rw, bodegas_ro;

ALTER DEFAULT PRIVILEGES REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE USAGE ON TYPES FROM PUBLIC;

RESET ROLE;

-- (3) El administrador deja de poder actuar como propietario.
REVOKE :"owner_user" FROM CURRENT_USER;

COMMIT;
SQL

echo "Roles, grupos y esquema bodegas inicializados en Render."
