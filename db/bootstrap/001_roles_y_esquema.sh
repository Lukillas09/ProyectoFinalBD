#!/bin/sh

# Este script es ejecutado por la imagen oficial de PostgreSQL solamente cuando
# el volumen de datos está vacío. psql recibe las contraseñas como literales y
# los nombres de rol como identificadores, sin construir SQL desde el shell.
set -e

: "${POSTGRES_DB:?POSTGRES_DB es obligatoria}"
: "${POSTGRES_USER:?POSTGRES_USER es obligatoria}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD es obligatoria}"
: "${DB_OWNER_USER:?DB_OWNER_USER es obligatoria}"
: "${DB_OWNER_PASSWORD:?DB_OWNER_PASSWORD es obligatoria}"
: "${DB_APP_USER:?DB_APP_USER es obligatoria}"
: "${DB_APP_PASSWORD:?DB_APP_PASSWORD es obligatoria}"

if [ "$DB_OWNER_USER" = "$DB_APP_USER" ]; then
  echo "DB_OWNER_USER y DB_APP_USER deben ser cuentas diferentes." >&2
  exit 1
fi

if [ "$POSTGRES_USER" = "$DB_OWNER_USER" ] || [ "$POSTGRES_USER" = "$DB_APP_USER" ]; then
  echo "La cuenta de bootstrap debe ser distinta del propietario y de la API." >&2
  exit 1
fi

if [ "$POSTGRES_PASSWORD" = "$DB_OWNER_PASSWORD" ] \
  || [ "$POSTGRES_PASSWORD" = "$DB_APP_PASSWORD" ] \
  || [ "$DB_OWNER_PASSWORD" = "$DB_APP_PASSWORD" ]; then
  echo "Las tres cuentas deben usar contraseñas diferentes." >&2
  exit 1
fi

psql \
  --set=ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=db_name="$POSTGRES_DB" \
  --set=owner_user="$DB_OWNER_USER" \
  --set=owner_password="$DB_OWNER_PASSWORD" \
  --set=app_user="$DB_APP_USER" \
  --set=app_password="$DB_APP_PASSWORD" <<'SQL'
BEGIN;

SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  :'owner_user', :'owner_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'owner_user')
\gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  :'owner_user', :'owner_password'
)
\gexec

SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  :'app_user', :'app_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  :'app_user', :'app_password'
)
\gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'owner_user')
\gexec

REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
REVOKE CREATE, TEMPORARY ON DATABASE :"db_name" FROM :"app_user";
GRANT CONNECT ON DATABASE :"db_name" TO :"owner_user", :"app_user";

REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS bodegas AUTHORIZATION :"owner_user";
ALTER SCHEMA bodegas OWNER TO :"owner_user";
REVOKE ALL ON SCHEMA bodegas FROM PUBLIC;
GRANT USAGE ON SCHEMA bodegas TO :"app_user";
REVOKE CREATE ON SCHEMA bodegas FROM :"app_user";

ALTER ROLE :"owner_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;
ALTER ROLE :"app_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;

-- Esta etapa no anticipa permisos de datos. Las migraciones futuras deben
-- conceder por objeto solamente lo que cada operación de la API necesite.
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user" IN SCHEMA bodegas
  REVOKE ALL ON TABLES FROM :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user" IN SCHEMA bodegas
  REVOKE ALL ON SEQUENCES FROM :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user" IN SCHEMA bodegas
  REVOKE ALL ON ROUTINES FROM :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user" IN SCHEMA bodegas
  REVOKE ALL ON TYPES FROM :"app_user";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user"
  REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user"
  REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user"
  REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner_user"
  REVOKE USAGE ON TYPES FROM PUBLIC;

COMMIT;
SQL

echo "Roles limitados y esquema bodegas inicializados correctamente."
