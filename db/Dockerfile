FROM postgres:16-alpine

# COPY evita problemas de bind mounts con carpetas sincronizadas en Windows y
# garantiza finales LF/permisos de ejecución para el bootstrap.
COPY --chmod=755 bootstrap/001_roles_y_esquema.sh /docker-entrypoint-initdb.d/001_roles_y_esquema.sh
COPY --chmod=755 migrate.sh /opt/bodegas/db/migrate.sh

# Las pruebas y migraciones quedan disponibles para ejecución manual;
# no se aplican automáticamente durante el bootstrap.
COPY migrations /opt/bodegas/db/migrations
COPY seed /opt/bodegas/db/seed
COPY tests /opt/bodegas/db/tests
