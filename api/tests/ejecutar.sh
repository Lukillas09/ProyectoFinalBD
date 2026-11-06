#!/bin/sh

# Corre las pruebas de la API en un proyecto de Compose aislado, desde un
# volumen vacío, y lo baja al terminar. Nunca usa el proyecto por defecto: las
# pruebas que escriben no tocan los datos de trabajo.
#
# Uso (desde cualquier carpeta, en Git Bash o Linux):
#   api/tests/ejecutar.sh                    todas las pruebas
#   api/tests/ejecutar.sh -k paginacion      los argumentos van a pytest
#   MANTENER=1 api/tests/ejecutar.sh         deja el proyecto arriba para depurar
#
# Variables: PROYECTO (bodegas_pruebas), ESCALA de la carga (0.1),
# API_PORT y FRONT_PORT en el host (18800 y 18880), ENV_FILE (.env.example).
set -u

# Git Bash: pwd -W da la ruta con unidad (C:/...), que entiende docker.exe.
raiz="$(cd "$(dirname "$0")/../.." && { pwd -W 2>/dev/null || pwd; })"
proyecto="${PROYECTO:-bodegas_pruebas}"
escala="${ESCALA:-0.1}"
export MSYS_NO_PATHCONV=1  # Git Bash: no reescribir rutas de los contenedores
export API_PORT="${API_PORT:-18800}"
export FRONT_PORT="${FRONT_PORT:-18880}"

compose() {
  docker compose --project-directory "$raiz" --env-file "${ENV_FILE:-$raiz/.env.example}" \
    -p "$proyecto" "$@"
}

bajar() {
  if [ "${MANTENER:-0}" = 1 ]; then
    echo "== Proyecto $proyecto queda arriba (MANTENER=1). Para bajarlo:"
    echo "   docker compose -p $proyecto down -v"
  else
    compose down -v >/dev/null 2>&1
  fi
}

echo "== Proyecto $proyecto desde un volumen vacío"
compose down -v >/dev/null 2>&1
if ! compose up -d --build --wait; then
  echo "No se pudo levantar el proyecto $proyecto." >&2
  bajar
  exit 1
fi

echo "== Carga reproducible con ESCALA=$escala"
salida_carga="$(compose --profile seed run --build --rm -e ESCALA="$escala" seed 2>&1)"
if [ $? -ne 0 ]; then
  echo "$salida_carga" | tail -20 >&2
  bajar
  exit 1
fi
echo "$salida_carga" | grep "Tiempo total"

echo "== pytest (rol bodegas_api)"
compose --profile test run --build --rm api-test \
  python -m pytest -v -p no:cacheprovider tests "$@"
codigo=$?

bajar
exit "$codigo"
