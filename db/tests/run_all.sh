#!/bin/sh

# Ejecuta las pruebas SQL en orden, cada una con el rol que le corresponde.
# Continúa ante una falla para mostrar el resultado completo, pero termina con
# código 1 si alguna prueba falló.
set -u

: "${POSTGRES_DB:?POSTGRES_DB es obligatoria}"
: "${DB_OWNER_USER:?DB_OWNER_USER es obligatoria}"
: "${DB_OWNER_PASSWORD:?DB_OWNER_PASSWORD es obligatoria}"
: "${DB_APP_USER:?DB_APP_USER es obligatoria}"
: "${DB_APP_PASSWORD:?DB_APP_PASSWORD es obligatoria}"
: "${DB_REPORT_USER:?DB_REPORT_USER es obligatoria}"
: "${DB_REPORT_PASSWORD:?DB_REPORT_PASSWORD es obligatoria}"

db_host="${DB_HOST:-127.0.0.1}"
tests_dir="${TESTS_DIR:-/opt/bodegas/db/tests}"
fallidas=0

# Uso: ejecutar_prueba archivo owner|api|reportes
ejecutar_prueba() {
  archivo="$1"
  rol="$2"

  case "$rol" in
    owner)
      usuario="$DB_OWNER_USER"
      clave="$DB_OWNER_PASSWORD"
      ;;
    api)
      usuario="$DB_APP_USER"
      clave="$DB_APP_PASSWORD"
      ;;
    reportes)
      usuario="$DB_REPORT_USER"
      clave="$DB_REPORT_PASSWORD"
      ;;
    *)
      echo "Rol desconocido: $rol" >&2
      exit 2
      ;;
  esac

  echo "=== $archivo (rol $rol: $usuario)"
  if PGPASSWORD="$clave" psql \
    --host="$db_host" \
    --username="$usuario" \
    --dbname="$POSTGRES_DB" \
    --no-psqlrc \
    --quiet \
    --output=/dev/null \
    --set=ON_ERROR_STOP=1 \
    --file="$tests_dir/$archivo"; then
    echo "=== PASA: $archivo"
  else
    echo "=== FALLA: $archivo (código $?)" >&2
    fallidas=$((fallidas + 1))
  fi
  echo
}

ejecutar_prueba 001_infraestructura.sql api
ejecutar_prueba 002_esquema_y_restricciones.sql owner
ejecutar_prueba 003_privilegios_api.sql api
ejecutar_prueba 004_reglas_negocio.sql owner
ejecutar_prueba 005_roles.sql owner
ejecutar_prueba 006_conexion_reportes.sql reportes

if [ "$fallidas" -gt 0 ]; then
  echo "Resultado: $fallidas prueba(s) fallida(s)." >&2
  exit 1
fi

echo "Resultado: todas las pruebas pasaron."
