#!/bin/sh

# Mide las consultas de db/perf/consultas_candidatas.sql con
# EXPLAIN (ANALYZE, BUFFERS) y guarda en docs/rendimiento/:
#   planes/<CODIGO>_<etiqueta>.txt   plan de la repetición mediana
#   resultados_<etiqueta>.csv        tiempos, recorridos, filas y buffers
#   contexto_<etiqueta>.txt          versión, configuración, fechas e índices
#
# Uso, desde la raíz del repositorio y con el entorno levantado:
#   db/perf/medir.sh antes      (sólo índices de PK y UNIQUE)
#   db/perf/medir.sh despues    (con 008_indices.sql aplicada)
# REPETICIONES (por omisión 5) define cuántas veces se repite cada consulta
# después de la primera ejecución.
#
# No modifica datos: los DELETE se miden dentro de un bloque que se revierte.
set -eu

etiqueta="${1:?Uso: db/perf/medir.sh antes|despues}"
repeticiones="${REPETICIONES:-5}"
export MSYS_NO_PATHCONV=1  # Git Bash: no reescribir las rutas del contenedor

cd "$(dirname "$0")/../.."
salida_contenedor=/tmp/medicion_bodegas
mkdir -p docs/rendimiento/planes
docker compose exec -T db sh -c "rm -rf $salida_contenedor && mkdir -p $salida_contenedor/planes"

{
  cat db/perf/medir.sql

  # Contexto de la medición.
  printf '\\o %s/contexto_%s.txt\n' "$salida_contenedor" "$etiqueta"
  cat <<'SQL'
SELECT version();
SELECT CURRENT_DATE AS fecha_medicion,
       (SELECT max(fecha) AT TIME ZONE 'America/Argentina/Buenos_Aires' FROM comprobante)::DATE AS ultima_venta_cargada;
SELECT name, setting, unit FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'effective_cache_size', 'jit', 'random_page_cost',
               'max_parallel_workers_per_gather', 'default_statistics_target')
ORDER BY name;
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(format('bodegas.%I', indexname)::regclass)) AS tamano
FROM pg_indexes WHERE schemaname = 'bodegas' ORDER BY tablename, indexname;
SQL
  printf '\\o\n'

  # Una llamada a pg_temp.medir por consulta, y su plan a un archivo.
  awk -v rep="$repeticiones" -v dir="$salida_contenedor/planes" -v etiqueta="$etiqueta" '
    function emitir() {
      if (codigo == "") return
      sub(/[[:space:];]+$/, "", sql)
      printf "SELECT pg_temp.medir(\047%s\047, $consulta$%s$consulta$, %d);\n", codigo, sql, rep
      printf "\\pset tuples_only on\n\\pset format unaligned\n"
      printf "\\o %s/%s_%s.txt\n", dir, codigo, etiqueta
      printf "SELECT linea FROM plan_texto WHERE codigo = \047%s\047 ORDER BY n;\n", codigo
      printf "\\o\n\\pset tuples_only off\n\\pset format aligned\n"
      printf "\\echo medida: %s\n", codigo
    }
    /^-- @consulta / { emitir(); codigo = $3; sql = ""; next }
    codigo != "" { sql = sql $0 "\n" }
    END { emitir() }
  ' db/perf/consultas_candidatas.sql

  printf '\\copy (SELECT * FROM medicion ORDER BY codigo) TO %s/resultados_%s.csv WITH (FORMAT csv, HEADER)\n' \
    "$salida_contenedor" "$etiqueta"
  cat <<'SQL'
SELECT codigo, primera_ms, mediana_ms, recorridos, filas_leidas, filas_descartadas_filtro,
       shared_hit, shared_read
FROM medicion ORDER BY codigo;
SQL
} | docker compose exec -T db sh -c \
  'PGPASSWORD="$DB_OWNER_PASSWORD" psql -q -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1'

docker compose cp "db:$salida_contenedor/." docs/rendimiento/ >/dev/null
echo "Planes y resultados guardados en docs/rendimiento/ (etiqueta: $etiqueta)."
