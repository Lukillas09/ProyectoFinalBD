# Comentario de revisión — PR #3

**PR:** #3 — Etapa 2: la API vende sólo con `fn_registrar_venta` y una venta confirmada no se reabre  
**Rama:** `etapa-2-logica` → `main` (mergeado)  
**Estado:** cerrado y mergeado  
**Enlace:** https://github.com/Lukillas09/ProyectoFinalBD/pull/3  
> Nota: es un follow-up de seguridad sobre el mismo ámbito de la Etapa 2, mergeado después del PR #2. Corrige una brecha que quedaba expuesta tras el PR #2.

## Parte del código revisada

Modificaciones: `db/migrations/004_procedimientos.sql` (`fn_registrar_venta` reescrito), `005_triggers.sql` (columna `xact_alta`, `trg_comprobante_alta`, chequeo de `xact_alta` en `trg_renglon_comprobante_completar`), `007_roles.sql` (se quita `INSERT` de la API sobre `renglon_comprobante`; queda solo `SELECT` en `comprobante`/`renglon_comprobante`), `db/tests/003_privilegios_api.sql`, `004_reglas_negocio.sql`, `005_roles.sql` y se añade `db/tests/007_comprobante_emitido.sql`; también `README.md`, `docs/concurrencia.md`, `docs/diccionario_datos.md`, `docs/modelo_relacional.md`, `docs/normalizacion.md`, `docs/requisitos.md`, `docs/trazabilidad.md`, `db/migrations/README.md`.

## Qué se verificó

- **Brecha de seguridad corregida:** tras el PR #2, la API tenía `INSERT` sobre `renglon_comprobante` y ningún trigger impedía agregar renglones a un comprobante confirmado en una transacción anterior. Eso descontaría stock y cambiaría importes de una venta histórica, violando RN-08 ("un comprobante emitido no se modifica"). El PR #3 cierra esto.
- **Columna técnica `comprobante.xact_alta` (`xid8`, `NOT NULL`, `DEFAULT pg_current_xact_id()`):** registra la transacción real que creó la cabecera. El trigger `BEFORE INSERT trg_comprobante_alta` la fuerza ignorando cualquier valor enviado (`NEW.xact_alta := pg_current_xact_id()`).
- **`trg_renglon_comprobante_completar` rechaza renglones de un comprobante emitido en otra transacción:** si `v_xact_alta <> pg_current_xact_id()` lanza `RN-12: el comprobante % ya fue emitido; no admite renglones nuevos.` (probado en 007_comprobante_emitido.sql, incluso para el propietario).
- **Por qué `xact_alta` y no `xmin`:** `pg_current_xact_id()` devuelve la transacción principal también dentro de un `SAVEPOINT` o bloque `EXCEPTION`; el `xmin` de una fila insertada en una subtransacción es el de la subtransacción; `xmin` cambia con cada `UPDATE` (el recálculo de `U1` haría parecer "nuevo" un comprobante viejo); `xact_alta` nunca se modifica; `xid8` es de 64 bits y no da la vuelta como `xmin` (32 bits). Todo esto está documentado en el comentario de 005_triggers.sql.
- **Límite:** el propietario podría desactivar el trigger deliberadamente (documentado en el comentario del trigger). No es un límite de seguridad contra el dueño, pero sí contra la API y errores accidentales.
- **Prueba nueva `007_comprobante_emitido.sql`:** crea una venta confirmada en una transacción anterior, intenta agregar renglones (debe rechazar con `RN-08`/`RN-12` aun como propietario), verifica que `U1` (`fn_recalcular_comprobante`) sigue funcionando, y limpia sus datos al terminar.
- Las pruebas 003, 004, 005 pasan con estos cambios (run_all.sh incluye 007).

## Decisiones técnicas importantes

- **La columna `xact_alta` se añade en una migración nueva (005) sobre una tabla que ya existe en 001.** Como la base se crea vacía al migrar de cero, el `DEFAULT` rellena filas existentes sin problema; en una base con datos ya habría que backfill. Aquí no aplica porque la migración se aplica en base vacía.
- **`fn_registrar_venta` se reescribe en 004** para crear la cabecera y los renglones en una sola llamada sin depender de `INSERT` directo de la API sobre `renglon_comprobante`. Mantiene las validaciones de entrada (listas del mismo largo, sin nulos, sin vinos repetidos, cantidades positivas) y el bloqueo de stock en orden de `cod_vino`.
- **`REVOKE ... FROM PUBLIC` sobre `fn_registrar_venta` y los procedimientos** se mantiene (ya estaba en 004; 007 solo otorga `EXECUTE` a `bodegas_rw`).

## Dudas o mejoras detectadas

- Ningún error funcional. Como observación: el cuerpo del comentario del PR #3 dice "Edita `00...`" (cortado en la descripción de GitHub). Convendría revisar que la descripción del PR esté completa antes de presentarlo en la defensa, aunque el código sí está completo.
- Revisar en defensa que `007_comprobante_emitido.sql` se ejecute con `ON_ERROR_STOP` y termine limpiando los datos (lo hace; se verificó pasando).

## Aspectos que debe poder explicar cada integrante en la defensa

1. Qué vulnerabilidad quedaba tras el PR #2 y cómo la cierra el PR #3 (venta confirmada no se reabre; RN-08).
2. Qué es `comprobante.xact_alta`, cómo se llena y por qué se elige frente a `xmin`.
3. Cómo impide el trigger `trg_renglon_comprobante_completar` agregar renglones a un comprobante de otra transacción.
4. Por qué el propietario aún puede desactivar el trigger y por qué eso no es un problema para la API (la API no tiene privilegios sobre esas tablas).
5. Qué prueba valida este comportamiento (`007_comprobante_emitido.sql`) y qué verifica (venta emitida no admite renglones nuevos, ni para el propietario; `U1` sigue funcionando).
6. Qué privilegios tiene la API sobre `comprobante` y `renglon_comprobante` tras el PR #3 (solo `SELECT`).

Archivos para comprobar: `db/migrations/005_triggers.sql` (sección `xact_alta` y `trg_renglon_comprobante_completar`), `db/migrations/004_procedimientos.sql` (`fn_registrar_venta`), `db/migrations/007_roles.sql`, `db/tests/007_comprobante_emitido.sql`, `docs/concurrencia.md` (sección "Agregar renglones a una venta ya confirmada").
