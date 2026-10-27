# Migraciones

Las migraciones actuales son:

- `001_esquema.sql`: tipos, tabla técnica de control, tablas de negocio, PK y FK;
- `002_constraints.sql`: claves candidatas `UNIQUE`, reglas `CHECK` y valores `DEFAULT`.

`db/migrate.sh` las ordena por el prefijo numérico, ejecuta cada una en una transacción con el rol propietario, registra nombre y SHA-256 en `bodegas.schema_migration`, omite las ya aplicadas sin cambios y falla si detecta que se modificó una migración registrada. El servicio `migrate` de Docker Compose lo ejecuta en cada `docker compose up`, antes de arrancar la API.

No usar `IF NOT EXISTS` dentro de migraciones para disimular diferencias de esquema. Una corrección posterior debe ir en un archivo nuevo con el siguiente número.
