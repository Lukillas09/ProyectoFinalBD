#!/bin/sh
# Pasos de la Etapa 8 contra la base de Render, desde la PC (Git Bash o Linux).
#
#   db/nube/render.sh verificar-admin   ¿el admin puede crear roles? (antes de todo)
#   db/nube/render.sh bootstrap         roles, grupos y esquema (admin de Render)
#   db/nube/render.sh migrar            001..010 en orden, como propietario
#   db/nube/render.sh cargar            carga reproducible (ESCALA de render.env)
#   db/nube/render.sh controles|huellas|conteos|tamano
#   db/nube/render.sh backup            pg_dump -Fc a db/nube/salida/ (no se versiona)
#   db/nube/render.sh restaurar <dump>  restaura en una base NUEVA local y compara
#   db/nube/render.sh psql-api|psql-reportes|psql-propietario|sin-ssl
#
# Requiere db/nube/render.env (copiar de render.env.example) y la IP propia
# habilitada en la lista de acceso de la base. Al terminar, vaciarla.
set -eu

aqui="$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })"
export MSYS_NO_PATHCONV=1  # Git Bash: no reescribir rutas de los contenedores
[ -f "$aqui/render.env" ] || { echo "Falta $aqui/render.env (copiar render.env.example)." >&2; exit 1; }

compose() { docker compose -f "$aqui/compose.render.yml" "$@"; }

case "${1:-}" in
  cargar)
    compose run --build --rm seed ;;
  restaurar)
    dump="${2:?Uso: render.sh restaurar db/nube/salida/<archivo>.dump}"
    nombre="$(basename "$dump")"
    compose build herramientas >/dev/null
    # Base NUEVA: un contenedor local vacío con la misma imagen de db, cuyo
    # bootstrap crea los mismos roles. Contraseña del superusuario al azar.
    docker rm -f bodegas_restaurada >/dev/null 2>&1 || true
    docker run -d --name bodegas_restaurada --env-file "$aqui/render.env" \
      -e POSTGRES_USER=restauracion -e POSTGRES_PASSWORD="r$(date +%s%N)" \
      -v "$aqui/salida:/salida:ro" bodegas_nube_herramientas >/dev/null
    # La imagen oficial inicializa con un servidor temporal y después reinicia:
    # se espera el fin de la inicialización y que el servidor definitivo responda.
    until docker logs bodegas_restaurada 2>&1 | grep -q "PostgreSQL init process complete"; do sleep 2; done
    until docker exec bodegas_restaurada pg_isready -q -h 127.0.0.1; do sleep 1; done
    echo "== pg_restore en la base nueva (como propietario)"
    # El bootstrap ya creó el esquema bodegas, vacío, y el volcado lo crea de nuevo:
    # se lo borra antes. No se usa --clean: sobre una base nueva, pg_restore intenta
    # primero desarmar la vista v_documentos_pendientes con un esqueleto que usa el
    # tipo estado_documento, que todavía no existe, y falla. El error era inofensivo
    # pero cortaba el script. Con --exit-on-error, cualquier error que quede es real.
    docker exec bodegas_restaurada sh -c 'psql -X -q -v ON_ERROR_STOP=1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA bodegas"'
    docker exec bodegas_restaurada sh -c 'pg_restore --exit-on-error -U "$DB_OWNER_USER" -d "$POSTGRES_DB" "/salida/'"$nombre"'"'
    echo "== Conteos: Render vs restaurada"
    compose run --rm herramientas conteos > "$aqui/salida/conteos_render.txt"
    docker exec -i bodegas_restaurada sh -c 'psql -X -U "$DB_OWNER_USER" -d "$POSTGRES_DB"' < "$aqui/conteos.sql" > "$aqui/salida/conteos_restaurada.txt"
    if diff "$aqui/salida/conteos_render.txt" "$aqui/salida/conteos_restaurada.txt"; then
      echo "Conteos IDÉNTICOS."; cat "$aqui/salida/conteos_restaurada.txt"
    else
      echo "Los conteos DIFIEREN." >&2; exit 1
    fi
    echo "La base restaurada queda en el contenedor bodegas_restaurada (docker rm -f bodegas_restaurada para borrarla)."
    ;;
  "")
    sed -n '2,13p' "$0"; exit 2 ;;
  *)
    compose run --build --rm herramientas "$@" ;;
esac
