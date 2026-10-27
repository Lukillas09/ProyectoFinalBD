#!/bin/sh

# Aplica migraciones numeradas como propietario, una por transacción.
# Registra el SHA-256 de cada archivo y rechaza cambios posteriores.
set -eu

: "${POSTGRES_DB:?POSTGRES_DB es obligatoria}"
: "${DB_OWNER_USER:?DB_OWNER_USER es obligatoria}"
: "${DB_OWNER_PASSWORD:?DB_OWNER_PASSWORD es obligatoria}"

migrations_dir="${MIGRATIONS_DIR:-/opt/bodegas/db/migrations}"

if [ ! -d "$migrations_dir" ]; then
  echo "No existe el directorio de migraciones: $migrations_dir" >&2
  exit 1
fi

export PGPASSWORD="$DB_OWNER_PASSWORD"

psql_owner() {
  psql \
    --host=127.0.0.1 \
    --username="$DB_OWNER_USER" \
    --dbname="$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 \
    "$@"
}

tracker_exists="$(
  psql_owner --tuples-only --no-align --command="
    SELECT CASE
      WHEN to_regclass('bodegas.schema_migration') IS NULL THEN 'no'
      ELSE 'si'
    END;
  "
)"

found_migration=no

for migration_path in "$migrations_dir"/[0-9][0-9][0-9]_*.sql; do
  if [ ! -f "$migration_path" ]; then
    continue
  fi

  found_migration=si
  migration_name="$(basename "$migration_path")"
  migration_checksum="$(sha256sum "$migration_path" | awk '{print $1}')"
  stored_checksum=""

  if [ "$tracker_exists" = "si" ]; then
    stored_checksum="$(
      psql_owner \
        --tuples-only \
        --no-align \
        --set=migration_name="$migration_name" <<'SQL'
SELECT checksum_sha256
FROM bodegas.schema_migration
WHERE archivo = :'migration_name';
SQL
    )"
  fi

  if [ -n "$stored_checksum" ]; then
    if [ "$stored_checksum" != "$migration_checksum" ]; then
      echo "ERROR: $migration_name ya fue aplicada y su checksum cambió." >&2
      echo "Cree una migración nueva; no modifique una migración aplicada." >&2
      exit 1
    fi

    echo "OMITIDA: $migration_name ya fue aplicada sin cambios."
    continue
  fi

  echo "APLICANDO: $migration_name"
  psql_owner \
    --set=migration_name="$migration_name" \
    --set=migration_checksum="$migration_checksum" <<SQL
BEGIN;
\i $migration_path
INSERT INTO bodegas.schema_migration (
  archivo,
  checksum_sha256,
  aplicada_en
) VALUES (
  :'migration_name',
  :'migration_checksum',
  CURRENT_TIMESTAMP
);
COMMIT;
SQL

  tracker_exists=si
  echo "APLICADA: $migration_name"
done

if [ "$found_migration" = "no" ]; then
  echo "No se encontraron archivos NNN_*.sql en $migrations_dir." >&2
  exit 1
fi

echo "Migraciones verificadas y aplicadas correctamente."
