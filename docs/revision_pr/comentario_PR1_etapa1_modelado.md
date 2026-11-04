# Comentario de revisión — PR #1

**PR:** #1 — Etapa 1: modelado, esquema físico y verificación desde cero  
**Rama:** `etapa-1-modelado` → `main` (mergeado)  
**Estado:** cerrado y mergeado  
**Enlace:** https://github.com/Lukillas09/ProyectoFinalBD/pull/1

## Parte del código revisada

DDL de la Etapa 1: `db/migrations/001_esquema.sql` y `db/migrations/002_constraints.sql`; el runner `db/migrate.sh`; el bootstrap `db/bootstrap/`; las pruebas `db/tests/001_infraestructura.sql`, `002_esquema_y_restricciones.sql`, `003_privilegios_api.sql` y `run_all.sh`; documentación `docs/modelo_conceptual.md`, `docs/modelo_relacional.md`, `docs/normalizacion.md`, `docs/diccionario_datos.md`, `docs/der/*.mmd`; y los archivos de configuración/infraestructura (`docker-compose.yml`, `README.md`, `AGENTS.md`, `CLAUDE.md`).

## Qué se verificó

- Se crea una base desde cero con un solo `docker compose up`: `db` hace el bootstrap (roles y esquema vacío `bodegas`) y `migrate` aplica las migraciones en orden numérico como propietario.
- `001_esquema.sql`: 30 tablas de negocio + la tabla técnica `schema_migration`; 31 PK y 35 FK (varias compuestas); un `DOMAIN` (`cuit_dom`); dos `ENUM` (`estado_documento`, `tipo_cliente`).
- `002_constraints.sql`: 11 `UNIQUE`, 36 `CHECK` (contando el dominio) y 17 columnas con `DEFAULT`; las restricciones van separadas del esqueleto relacional para que su propósito sea visible.
- Jerarquía de clientes: superclave `(id_cliente, tipo)` en `cliente` referenciada por FK compuestas de `socio_club`, `distribuidor` y `exportador`; cada subtipo fija su `tipo` con un `CHECK`, lo que impide que un cliente tenga filas de varios subtipos (exclusividad).
- `parcela` modelada como entidad débil (PK compuesta `id_finca, nro_parcela`); `fk_parcela_finca` usa `ON DELETE CASCADE` y `lk_lote_uva_parcela` también `ON DELETE CASCADE`.
- `migrate.sh`: ordena archivos `NNN_*.sql`, ejecuta cada uno en una transacción con `ON_ERROR_STOP`, registra nombre + SHA-256 + instante en `bodegas.schema_migration`, omite las ya aplicadas y falla si cambió el checksum. Nunca usa `IF NOT EXISTS`.
- Se eliminó el versionado de los PDF de la cátedra bajo `material/` (buena práctica: no se versionan materiales docentes).
- Pruebas 001, 002 y 003 pasan (rol API sin atributos administrativos, propietario dueño de los objetos, matriz de privilegios exacta). `run_all.sh` termina con código 0.

## Decisiones técnicas importantes

- **Clave candidata y PK de clientes:** `id_cliente` es subrogada (`IDENTITY`). La unicidad del documento real queda en `uq_cliente_documento (tipo_documento, nro_documento)`. El identificador de la PK es subrogado por simplicidad y porque los documentos naturales pueden cambiar o repetirse por tipo de documento.
- **Jerarquía de clientes:** se eligió "clase tabla por subtipo" con FK compuesta `(id_cliente, tipo)` para forzar que cada cliente pertenezca exactamente a un subtipo. Ventaja: integridad declarativa de exclusividad y totalidad (con ayuda de un constraint trigger diferido en 005). Riesgo: hay que mantener la columna `tipo` sincronizada entre `cliente` y el subtipo; se mitiga con `ON UPDATE RESTRICT` en las FK compuestas.
- **`stock_deposito` vs `stock_sala`:** el depósito central es único, así que `stock_deposito` tiene PK `(cod_vino)`; cada sala tiene muchas filas, así que `stock_sala` tiene PK `(id_sala, cod_vino)`. Coherente con el modelo.
- Los `DEFAULT` usan `CURRENT_DATE` / `CURRENT_TIMESTAMP` / `CURRENT_USER`. Esto es válido porque son `DEFAULT`, no `CHECK`: AGENTS.md prohíbe funciones no determinísticas dentro de un `CHECK`, no en un valor por omisión.

## Dudas o mejoras detectadas

- Ningún error funcional. Como observación de diseño para la defensa: ¿qué ocurre si un integrante intenta cambiar `cliente.tipo` de un cliente que ya tiene fila en un subtipo? La FK compuesta con `ON UPDATE RESTRICT` lo impide mientras exista la fila del subtipo; para cambiar de tipo hay que borrar el subtipo viejo, actualizar `tipo` e insertar el nuevo subtipo en la misma transacción (probado en `004_reglas_negocio.sql`, sección "totalidad de la jerarquía").
- `stock_sala.cantidad` tiene `CHECK (cantidad >= 0)` y `DEFAULT 0`; `fn_stock_sala` devuelve 0 si no hay fila, así que "sin fila" y "cantidad cero" significan lo mismo para vender (documentado en el comentario de la función).

## Aspectos que debe poder explicar cada integrante en la defensa

1. Qué representa cada entidad y por qué es independiente (p. ej. `finca`, `parcela` como entidad débil, `lote_uva`, `bodega`, `vino`, `cliente` y sus subtipos).
2. Cuáles son las claves candidatas y por qué se eligió una PK subrogada en la mayoría de tablas.
3. Dónde se definen las PK, FK, UNIQUE, CHECK, NOT NULL, DOMAIN y ENUM (`001_esquema.sql` y `002_constraints.sql`).
4. Cómo se ejecutan las migraciones desde cero y quién las ejecuta (`db/migrate.sh` como `bodegas_owner`, nunca la API ni el bootstrap).
5. Qué garantiza `schema_migration` (registro y SHA-256 para detectar modificaciones de migraciones aplicadas).
6. Por qué se removieron los PDF de `material/` del versionado.

Archivos para comprobar: `db/migrations/001_esquema.sql`, `db/migrations/002_constraints.sql`, `db/migrate.sh`, `db/tests/002_esquema_y_restricciones.sql`, `docs/modelo_relacional.md`, `README.md` (sección Migraciones).
