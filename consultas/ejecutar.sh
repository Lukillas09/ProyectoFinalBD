#!/bin/sh

# Ejecuta un archivo de consultas de la Etapa 5 como propietario, dentro del
# contenedor db, y termina con código distinto de 0 si alguna sentencia falla.
#
# Uso:
#   docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
#   docker compose exec db /opt/bodegas/consultas/ejecutar.sh update.sql -v cuit_bodega=30711234565
#
# Los argumentos después del archivo se pasan a psql (por ejemplo, -v para
# reemplazar los parámetros por omisión que define cada archivo).
# Cada consulta de modificación termina en ROLLBACK: el archivo no deja cambios.
set -eu

: "${POSTGRES_DB:?POSTGRES_DB es obligatoria}"
: "${DB_OWNER_USER:?DB_OWNER_USER es obligatoria}"
: "${DB_OWNER_PASSWORD:?DB_OWNER_PASSWORD es obligatoria}"

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 archivo.sql [opciones de psql]" >&2
  exit 2
fi

archivo="$1"
shift
case "$archivo" in
  */*) ruta="$archivo" ;;
  *) ruta="${CONSULTAS_DIR:-/opt/bodegas/consultas}/$archivo" ;;
esac

if [ ! -f "$ruta" ]; then
  echo "No existe el archivo de consultas: $ruta" >&2
  exit 2
fi

# ON_ERROR_STOP: el primer error corta la ejecución y psql sale con código 3.
if PGPASSWORD="$DB_OWNER_PASSWORD" psql \
  --host="${DB_HOST:-127.0.0.1}" \
  --username="$DB_OWNER_USER" \
  --dbname="$POSTGRES_DB" \
  --no-psqlrc \
  --pset=pager=off \
  --set=ON_ERROR_STOP=1 \
  "$@" \
  --file="$ruta"; then
  echo "=== OK: $archivo"
else
  codigo=$?
  echo "=== FALLA: $archivo (código $codigo)" >&2
  exit "$codigo"
fi
