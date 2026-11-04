# Comentario de revisión — PR #2

**PR:** #2 — Etapa 2: integridad y lógica en la base de datos  
**Rama:** `etapa-2-logica` → `main` (mergeado)  
**Estado:** cerrado y mergeado  
**Enlace:** https://github.com/Lukillas09/ProyectoFinalBD/pull/3  
> Nota: GitHub reporta la rama como `etapa-2-logica`; el PR es el segundo de la secuencia y cubre funciones, procedimientos, triggers, vistas, privilegios y pruebas de la Etapa 2. El cierre de comprobantes emitidos (brecha de seguridad) se agrega en el PR #3.

## Parte del código revisada

Migraciones de la Etapa 2: `db/migrations/003_funciones.sql`, `004_procedimientos.sql`, `005_triggers.sql`, `006_vistas.sql`, `007_roles.sql`; actualizaciones del bootstrap `db/bootstrap/001_roles_y_esquema.sh` (cuenta de reportes y roles de grupo); pruebas `db/tests/004_reglas_negocio.sql`, `005_roles.sql`, `006_conexion_reportes.sql`, `ayudantes.sql` y modificaciones a `001_*`/`002_*`/`003_*`/`run_all.sh`; documentación `docs/concurrencia.md`, `docs/trazabilidad.md`, `docs/diccionario_datos.md`, `README.md`, `AGENTS.md`, `requisitos.md`.

## Qué se verificó

- **Funciones (003):** `fn_descuento_cliente`, `fn_stock_sala`, `fn_total_comprobante` (STABLE) y `fn_antiguedad_anios` (IMMUTABLE; el `DEFAULT CURRENT_DATE` se evalúa en la llamada, no se precalcula, por eso no se puede indexar sobre ella — probado con error 42P17 en 004). Todas fijan `search_path`.
- **Procedimientos (004):** `sp_terminar_ingreso`, `sp_procesar_ingreso`, `sp_terminar_transferencia`, `sp_procesar_transferencia`. Son `SECURITY DEFINER` (cambian estados y stock sobre los que la API no tiene UPDATE), no hacen `COMMIT` (se ejecutan dentro de la transacción del llamante), bloquean la cabecera `FOR UPDATE` e impactan stock en orden de `cod_vino` para evitar deadlocks.
- **Triggers (005):** 20 triggers (10 BEFORE, 2 AFTER, 8 constraint triggers diferidos). `RN-08/RN-09` en `renglon_comprobante`: BEFORE INSERT bloquea cabecera `FOR UPDATE`, completa precio/descuento/subtotal (la API no puede imponerlos), valida stock `FOR UPDATE` y rechaza sin stock; AFTER INSERT descuenta stock y recalcula importes. `RN-05` composición suma 100 (constraint trigger diferido). `RN-10/RN-11` transiciones de estado sin retrocesos. `RN-12` renglones bloqueados fuera de confección. `RN-13` auditoría de precio.
- **Vistas (006):** `v_stock_total_vino`, `v_ventas_mensuales_sala`, `v_documentos_pendientes`, `v_ficha_vino`. Columnas explícitas, sin `ORDER BY`, la vista se ejecuta con privilegios del dueño (propietario).
- **Roles y privilegios (007):** la API (`bodegas_rw`) solo lee `comprobante`/`renglon_comprobante`; vende únicamente con `fn_registrar_venta`. No tiene INSERT/UPDATE directo sobre stock, auditoría, importes ni estados. Reportes (`bodegas_ro`) solo lectura.
- **Pruebas:** 004 (RN-01 a RN-15, U6, totalidad de jerarquía de clientes, funciones, volatilidad declarada) y 005 (API y reportes con `SET ROLE`; lo prohibido da 42501; funciones SECURITY DEFINER) pasan. 006 (reportes solo lectura) pasa. Todo dentro de transacción con `ROLLBACK`, salvo 007 que no existe aún en este PR.

## Decisiones técnicas importantes

- **Venta como función, no procedimiento:** `fn_registrar_venta` devuelve `nro_comprobante` y es el único camino de venta de la API. Recibe dos arrays paralelos (`BIGINT[]`, `INTEGER[]`) en lugar de `jsonb`: Psycopg convierte una lista de Python a array de PostgreSQL sin código adicional y PostgreSQL valida los tipos al recibir la llamada.
- **Todo o nada sin COMMIT interno:** `fn_registrar_venta` se ejecuta dentro de la transacción de quien la llama. Si un renglón falla (p. ej. `RN-09` sin stock), se revierte toda la sentencia: no queda ni la cabecera ni los renglones anteriores.
- **Prevención de deadlock:** `fn_registrar_venta` bloquea las filas de `stock_sala` en orden de `cod_vino`; dos ventas concurrentes de varios vinos piden los bloqueos en el mismo orden y no se bloquean en cruz (escenario 4b de `docs/concurrencia.md`).
- **Marca GUC `bodegas.recalculo_importes`:** `fn_recalcular_comprobante` activa la marca antes del `UPDATE` de importes y la apaga al terminar; `trg_comprobante_importes` la exige. Protege contra escritura manual de importes por el propietario, pero no es un límite de seguridad para la API (que no tiene UPDATE sobre `comprobante`).
- **`xact_alta` NO está en este PR:** se agrega en el PR #3. En el estado tras PR #2, la API tiene `INSERT` sobre `renglon_comprobante` y ningún trigger impide agregar renglones a un comprobante confirmado de otra transacción (violación de RN-08). Esa es la brecha que cierra el PR #3.

## Dudas o mejoras detectadas

- Ningún error funcional. Pregunta de diseño para la defensa: `fn_recalcular_comprobante` permite al propietario reescribir importes si activa la marca GUC. ¿Es aceptable que el propietario pueda hacerlo? El comentario de 004 y 005 aclara que no es un límite de seguridad, sino una protección contra errores; el límite real para la API es no tener privilegios sobre esas columnas.
- El comentario de 003 aclara que `fn_antiguedad_anios` es `IMMUTABLE` aunque tenga `DEFAULT CURRENT_DATE`: el valor por omisión se reemplaza en la llamada, por lo que no es constante para la planificación. Un integrante debe poder explicar por qué un índice sobre `bodegas.fn_antiguedad_anios(columna)` se rechaza con 42P17.

## Aspectos que debe poder explicar cada integrante en la defensa

1. Qué funciones y procedimientos existen y cuál es el propósito de cada uno (`003_funciones.sql`, `004_procedimientos.sql`).
2. Por qué `fn_registrar_venta` es el único camino de venta y qué privilegiados tiene la API sobre ventas (solo `SELECT`; `EXECUTE` sobre `fn_registrar_venta`).
3. Cómo se controla el stock (`RN-09`) y qué impide vender sin stock (trigger `BEFORE INSERT` con `SELECT ... FOR UPDATE` sobre `stock_sala`).
4. Cómo se usan las transacciones: `BEGIN`, `COMMIT`, `ROLLBACK`; los procedimientos no hacen `COMMIT` interno.
5. Qué es `FOR UPDATE` y dónde se usa (venta, `sp_procesar_ingreso`, `sp_procesar_transferencia`).
6. Nivel de aislamiento: `READ COMMITTED` por defecto, con bloqueos explícitos; `REPEATABLE READ` se menciona en `docs/concurrencia.md` pero no se usa en la API.
7. Cómo se traduce un error de PostgreSQL (`SQLSTATE P0001` para reglas de negocio, `P0002` para "no existe") sin filtrar detalles internos.

Archivos para comprobar: `db/migrations/003_funciones.sql`, `db/migrations/004_procedimientos.sql`, `db/migrations/005_triggers.sql`, `db/migrations/007_roles.sql`, `db/tests/004_reglas_negocio.sql`, `db/tests/005_roles.sql`, `docs/concurrencia.md`, `docs/trazabilidad.md`.
