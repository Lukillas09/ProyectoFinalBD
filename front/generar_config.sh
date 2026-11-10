#!/bin/sh
# Build del front para el static site de Render (Etapa 8, render.yaml).
#
# Copia sólo lo que se publica a front/dist/ (no publica pruebas, Dockerfile
# ni nginx.conf) y escribe un config.js con la URL pública de la API. En local
# no se usa: el config.js versionado sigue apuntando a /api a través de nginx.
set -eu

: "${API_BASE_URL:?Defina API_BASE_URL con la URL pública de la API (https://...)}"
case "$API_BASE_URL" in
  https://*) ;;
  *) echo "API_BASE_URL debe empezar con https://" >&2; exit 1 ;;
esac

origen="$(cd "$(dirname "$0")" && pwd)"
destino="$origen/dist"

rm -rf "$destino"
mkdir -p "$destino"
cp "$origen/index.html" "$origen/styles.css" "$destino/"
cp -R "$origen/js" "$destino/js"

# La URL va entre comillas JSON: printf con %s no interpreta su contenido.
printf 'window.BODEGAS_CONFIG = { apiBase: "%s" };\n' "${API_BASE_URL%/}" > "$destino/config.js"
echo "front/dist listo con apiBase=${API_BASE_URL%/}"
