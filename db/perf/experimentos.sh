#!/bin/sh

# Ejecuta los experimentos de db/perf/experimentos/ y guarda la salida de
# cada uno en docs/rendimiento/experimentos/<nombre>.txt.
# Cada experimento corre dentro de BEGIN ... ROLLBACK: la base no cambia.
#
# Uso, desde la raíz del repositorio y con el entorno levantado:
#   db/perf/experimentos.sh            (todos)
#   db/perf/experimentos.sh 04         (los que empiezan con 04)
set -eu

filtro="${1:-}"
export MSYS_NO_PATHCONV=1  # Git Bash: no reescribir las rutas del contenedor

cd "$(dirname "$0")/../.."
mkdir -p docs/rendimiento/experimentos

for archivo in db/perf/experimentos/"$filtro"*.sql; do
  nombre="$(basename "$archivo" .sql)"
  salida="docs/rendimiento/experimentos/$nombre.txt"
  echo "Experimento $nombre"
  docker compose exec -T db sh -c \
    'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' \
    < "$archivo" > "$salida" 2>&1
done

# Comprobación: los experimentos no dejaron índices ni datos nuevos.
docker compose exec -T db sh -c \
  'PGPASSWORD="$DB_OWNER_PASSWORD" psql -At -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -c "SELECT '"'"'índices en bodegas: '"'"' || count(*) FROM pg_indexes WHERE schemaname = '"'"'bodegas'"'"'"'
echo "Salidas en docs/rendimiento/experimentos/."
