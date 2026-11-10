#!/bin/sh
# Pasos contra la base de Render. Corre DENTRO del contenedor de herramientas
# (la imagen de db: psql, pg_dump, migrate.sh, migraciones y SQL de control).
# Se invoca con db/nube/render.sh <paso>; las credenciales llegan de
# db/nube/render.env (no versionado). Siempre con TLS (sslmode=require).
set -eu

: "${DB_HOST:?Defina DB_HOST (host EXTERNO de la base de Render) en render.env}"
export PGHOST="$DB_HOST" PGPORT="${DB_PORT:-5432}" PGSSLMODE=require PGDATABASE="$POSTGRES_DB"

como() {  # como <usuario> <clave> psql ...
  usuario="$1"; clave="$2"; shift 2
  PGUSER="$usuario" PGPASSWORD="$clave" "$@"
}

seed=/opt/bodegas/db/seed
case "${1:-}" in
  verificar-admin)
    # Antes de tocar nada: ¿el administrador puede crear roles y traspasar la base?
    como "$RENDER_ADMIN_USER" "$RENDER_ADMIN_PASSWORD" psql -X -c "
      SELECT rolname, rolsuper, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = current_user;" \
      -c "SELECT version();" -c "SELECT ssl, version AS tls FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
    ;;
  bootstrap) sh /nube/bootstrap_render.sh ;;
  migrar) /opt/bodegas/db/migrate.sh ;;
  controles)
    como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 -f "$seed/controles.sql" -f "$seed/post_carga.sql"
    ;;
  huellas) como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 -f "$seed/hashes.sql" ;;
  conteos) como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 -f /nube/conteos.sql ;;
  tamano)
    como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" psql -X -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano;"
    ;;
  backup)
    archivo="/nube/salida/bodegas_render_$(date +%Y%m%d_%H%M).dump"
    mkdir -p /nube/salida
    como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" pg_dump -Fc --schema=bodegas -f "$archivo"
    ls -l "$archivo"
    ;;
  # Sesiones interactivas para las pruebas de seguridad (#69).
  psql-propietario) shift; como "$DB_OWNER_USER" "$DB_OWNER_PASSWORD" psql -X "$@" ;;
  psql-api) shift; como "$DB_APP_USER" "$DB_APP_PASSWORD" psql -X "$@" ;;
  psql-reportes) shift; como "$DB_REPORT_USER" "$DB_REPORT_PASSWORD" psql -X "$@" ;;
  sin-ssl)
    # Debe fallar: Render rechaza conexiones externas sin TLS (R4).
    PGSSLMODE=disable PGUSER="$DB_REPORT_USER" PGPASSWORD="$DB_REPORT_PASSWORD" psql -X -c "SELECT 1" ;;
  *)
    echo "Pasos: verificar-admin bootstrap migrar controles huellas conteos tamano backup psql-propietario psql-api psql-reportes sin-ssl" >&2
    exit 2 ;;
esac
