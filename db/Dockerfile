FROM postgres:16-alpine

# COPY evita problemas de bind mounts con carpetas sincronizadas en Windows y
# garantiza finales LF/permisos de ejecución para el bootstrap.
COPY --chmod=755 bootstrap/001_roles_y_esquema.sh /docker-entrypoint-initdb.d/001_roles_y_esquema.sh
COPY --chmod=755 migrate.sh /opt/bodegas/db/migrate.sh

# Las migraciones no se aplican en el bootstrap: las ejecuta el servicio
# migrate de Compose como propietario. Las pruebas quedan para ejecución manual.
COPY migrations /opt/bodegas/db/migrations
COPY seed /opt/bodegas/db/seed
COPY tests /opt/bodegas/db/tests
COPY --chmod=755 tests/run_all.sh /opt/bodegas/db/tests/run_all.sh

# Consultas de la Etapa 5. consultas/ está fuera de ./db: llega como contexto
# adicional "consultas" (additional_contexts en docker-compose.yml), así el
# contexto de build de db no se amplía a todo el repositorio.
COPY --from=consultas --chmod=644 select.sql insert.sql update.sql delete.sql /opt/bodegas/consultas/
COPY --from=consultas --chmod=755 ejecutar.sh /opt/bodegas/consultas/ejecutar.sh
