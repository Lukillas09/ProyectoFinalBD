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
: "${DB_REPORT_USER:?DB_REPORT_USER es obligatoria}"
: "${DB_REPORT_PASSWORD:?DB_REPORT_PASSWORD es obligatoria}"

# Las cuatro cuentas deben ser distintas, con contraseñas distintas.
nombres="$POSTGRES_USER
$DB_OWNER_USER
$DB_APP_USER
$DB_REPORT_USER"
if [ "$(printf '%s\n' "$nombres" | sort -u | wc -l)" -ne 4 ]; then
  echo "Bootstrap, propietario, API y reportes deben ser cuentas diferentes." >&2
  exit 1
fi

claves="$POSTGRES_PASSWORD
$DB_OWNER_PASSWORD
$DB_APP_PASSWORD
$DB_REPORT_PASSWORD"
if [ "$(printf '%s\n' "$claves" | sort -u | wc -l)" -ne 4 ]; then
  echo "Las cuatro cuentas deben usar contraseñas diferentes." >&2
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
  --set=app_password="$DB_APP_PASSWORD" \
  --set=report_user="$DB_REPORT_USER" \
  --set=report_password="$DB_REPORT_PASSWORD" <<'SQL'
BEGIN;

-- Cuentas de conexión (identidad): propietario, API y reportes.
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  usuario, clave
)
FROM (VALUES
  (:'owner_user', :'owner_password'),
  (:'app_user', :'app_password'),
  (:'report_user', :'report_password')
) AS cuenta(usuario, clave)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = usuario)
\gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  usuario, clave
)
FROM (VALUES
  (:'owner_user', :'owner_password'),
  (:'app_user', :'app_password'),
  (:'report_user', :'report_password')
) AS cuenta(usuario, clave)
\gexec

-- Roles de grupo (permisos) con nombre fijo: 007_roles.sql les otorga los
-- privilegios sobre objetos sin depender de los nombres configurables de las
-- cuentas. No pueden iniciar sesión.
SELECT format(
  'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
  grupo
)
FROM (VALUES ('bodegas_rw'), ('bodegas_ro')) AS g(grupo)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = grupo)
\gexec

-- Las cuentas se crean NOINHERIT; la opción INHERIT de cada GRANT (PostgreSQL
-- 16) hace que la API y reportes hereden sólo el privilegio de su grupo.
GRANT bodegas_rw TO :"app_user" WITH INHERIT TRUE;
GRANT bodegas_ro TO :"report_user" WITH INHERIT TRUE;

-- El propietario no hereda (ya es dueño de todo), pero puede hacer SET ROLE a
-- cada grupo: las pruebas ejercitan así los permisos reales dentro de una
-- transacción que termina en ROLLBACK.
GRANT bodegas_rw, bodegas_ro TO :"owner_user" WITH INHERIT FALSE, SET TRUE;

SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'owner_user')
\gexec

REVOKE ALL ON DATABASE :"db_name" FROM PUBLIC;
REVOKE CREATE, TEMPORARY ON DATABASE :"db_name" FROM :"app_user", :"report_user";
GRANT CONNECT ON DATABASE :"db_name" TO :"owner_user", :"app_user", :"report_user";

REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS bodegas AUTHORIZATION :"owner_user";
ALTER SCHEMA bodegas OWNER TO :"owner_user";
REVOKE ALL ON SCHEMA bodegas FROM PUBLIC;
GRANT USAGE ON SCHEMA bodegas TO bodegas_rw, bodegas_ro;

ALTER ROLE :"owner_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;
ALTER ROLE :"app_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;
ALTER ROLE :"report_user" IN DATABASE :"db_name" SET search_path TO bodegas, pg_catalog;

-- El bootstrap no anticipa permisos de datos: 007_roles.sql concede por
-- objeto sólo lo que cada grupo necesita. Los objetos futuros del
-- propietario no reciben privilegios implícitos.
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

echo "Roles limitados, grupos y esquema bodegas inicializados correctamente."
