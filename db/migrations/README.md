# Migraciones

Las migraciones actuales son:

- `001_esquema.sql`: tipos, tabla técnica de control, tablas de negocio, PK y FK;
- `002_constraints.sql`: claves candidatas `UNIQUE`, reglas `CHECK` y valores `DEFAULT`;
- `003_funciones.sql`: funciones de cálculo (descuento, stock de sala, total, antigüedad) y el recálculo de importes;
- `004_procedimientos.sql`: terminar y procesar ingresos y transferencias, y `fn_registrar_venta`, único camino de venta de la API;
- `005_triggers.sql`: triggers de RN-05, RN-06/U6, RN-08 a RN-13 y totalidad de clientes; agrega la columna técnica `comprobante.xact_alta`, que cierra una venta confirmada a renglones nuevos;
- `006_vistas.sql`: stock total, ventas mensuales, documentos pendientes y ficha de vino;
- `007_roles.sql`: privilegios de `bodegas_rw` (API) y `bodegas_ro` (reportes).

`db/migrate.sh` las ordena por el prefijo numérico, ejecuta cada una en una transacción con el rol propietario, registra nombre y SHA-256 en `bodegas.schema_migration`, omite las ya aplicadas sin cambios y falla si detecta que se modificó una migración registrada. El servicio `migrate` de Docker Compose lo ejecuta en cada `docker compose up`, antes de arrancar la API.

Los archivos no llevan `BEGIN`/`COMMIT`: la transacción la abre el runner. `008_indices.sql` corresponde a la Etapa 4.

No usar `IF NOT EXISTS` dentro de migraciones para disimular diferencias de esquema. Una corrección posterior debe ir en un archivo nuevo con el siguiente número.
