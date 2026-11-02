-- =============================================================================
-- CONSULTAS DELETE - ETAPA 5
-- Bodegas del Atuel - Trabajo Práctico Integrador BD 2026
-- =============================================================================
--
-- Cada consulta sigue el protocolo obligatorio:
--   BEGIN;
--   -- Control previo
--   -- Sentencia DELETE
--   -- Control posterior
--   GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
--   RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
--   ROLLBACK;
--
-- Convenciones:
-- - SQL en minúsculas para palabras clave
-- - Parámetros estilo psql: :parametro
-- - Valores del dataset: SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- =============================================================================

-- =============================================================================
-- D1: Borrar comprobantes de más de cinco años de socios
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D1
-- Tipo:             DELETE
-- Enunciado:        Borrar comprobantes de más de cinco años de socios
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran comprobantes donde fecha < CURRENT_DATE - INTERVAL '5 years'
-- y el cliente es de tipo 'socio'. Las FK tienen ON DELETE RESTRICT desde
-- renglon_comprobante a comprobante, por lo que se deben borrar primero
-- los renglones y luego las cabeceras, o usar una CTE con DELETE ... RETURNING.
-- La fecha es TIMESTAMPTZ, se compara con CURRENT_DATE (se castea implícitamente).
-- Supuesto (docs/requisitos.md #14): borrados históricos no revierten stock.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver comprobantes a borrar:
-- SELECT c.nro_comprobante, c.fecha, c.id_cliente, cl.tipo, c.total
--   FROM bodegas.comprobante c
--   JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
--  WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
--    AND cl.tipo = 'socio'
--  ORDER BY c.fecha
--  LIMIT 20;
-- Valores típicos: fecha 2018-2021 para >5 años, tipo 'socio' ~ 60% clientes.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: comprobantes a borrar
SELECT count(*) AS comprobantes_a_borrar,
       sum(c.total) AS monto_total_a_borrar
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND cl.tipo = 'socio';

-- Control previo: renglones asociados
SELECT count(*) AS renglones_a_borrar
  FROM bodegas.renglon_comprobante rc
  JOIN bodegas.comprobante c ON c.nro_comprobante = rc.nro_comprobante
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND cl.tipo = 'socio';

-- Sentencia principal: borrar en cascada controlada con CTE
WITH renglones_borrados AS (
  DELETE FROM bodegas.renglon_comprobante
   WHERE nro_comprobante IN (
     SELECT nro_comprobante FROM bodegas.comprobante c
      JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
     WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
       AND cl.tipo = 'socio'
   )
   RETURNING nro_comprobante
),
cabeceras_borradas AS (
  DELETE FROM bodegas.comprobante
   WHERE nro_comprobante IN (
     SELECT nro_comprobante FROM bodegas.comprobante c
      JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
     WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
       AND cl.tipo = 'socio'
   )
   RETURNING nro_comprobante
)
SELECT count(*) AS comprobantes_borrados,
       (SELECT count(*) FROM renglones_borrados) AS renglones_borrados
  FROM cabeceras_borradas;

-- Control posterior: verificar que no quedaron
SELECT count(*) AS comprobantes_remanentes
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND cl.tipo = 'socio';

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE (en renglon_comprobante):
--   trg_renglon_comprobante_inmutable (RN-08/12): permite DELETE solo si cabecera no existe
--     (en nuestra CTE, los renglones se borran ANTES que la cabecera, así que la cabecera
--      aún existe -> el trigger RECHAZARÁ el borrado de renglones sueltos)
-- IMPORTANTE: El trigger trg_renglon_comprobante_inmutable bloquea DELETE de renglones
-- si la cabecera existe. Por eso se debe usar ON DELETE CASCADE en la FK o borrar
-- la cabecera primero. Pero la FK tiene ON DELETE RESTRICT.
-- SOLUCIÓN: El trigger verifica "IF EXISTS (SELECT 1 FROM comprobante WHERE nro_comprobante = OLD.nro_comprobante)"
-- En nuestra CTE, al borrar renglones PRIMERO, la cabecera SÍ existe -> error.
-- ALTERNATIVA: Borrar cabecera primero (CASCADE en FK) o desactivar trigger temporalmente.
-- Pero la FK tiene ON DELETE RESTRICT, no CASCADE.
-- REVISAR: La FK fk_renglon_comprobante_comprobante tiene ON DELETE CASCADE (ver 001_esquema.sql línea 322).
-- Sí, tiene CASCADE. Entonces borrar la cabecera arrastra los renglones automáticamente.
-- El trigger trg_renglon_comprobante_inmutable tiene: "IF EXISTS (SELECT 1 FROM comprobante...) RAISE..."
-- Pero en DELETE CASCADE, los renglones se borran ANTES de que la cabecera desaparezca?
-- En PostgreSQL, el orden es: BEFORE ROW triggers en hijos, luego DELETE en padre,
-- luego AFTER ROW triggers en hijos. El trigger BEFORE DELETE en renglones ve la cabecera.
-- Pero la FK CASCADE hace que el DELETE en comprobante propague a renglones.
-- El trigger BEFORE DELETE en renglones se dispara para cada renglón borrado en cascada.
-- Como la cabecera aún no se ha borrado (se borra después de los hijos en cascada),
-- el trigger verá la cabecera y RECHAZARÁ el borrado.
-- PROBLEMA: El trigger trg_renglon_comprobante_inmutable impide el DELETE CASCADE.
-- SOLUCIÓN: El trigger tiene excepción: "IF EXISTS (SELECT 1 FROM comprobante WHERE nro_comprobante = OLD.nro_comprobante)"
-- En un DELETE CASCADE, cuando se disparan los triggers de los hijos, el padre
-- AÚN EXISTE (no se ha borrado aún). Por tanto, el trigger bloqueará.
-- VERIFICAR: En 005_triggers.sql línea 177-184:
--   IF EXISTS (SELECT 1 FROM comprobante WHERE nro_comprobante = OLD.nro_comprobante) THEN
--     RAISE EXCEPTION 'RN-08: no se borran renglones sueltos de un comprobante.'
--   END IF;
-- Esto bloquea CUALQUIER DELETE de renglón si la cabecera existe.
-- Para D1 (borrado histórico), se debe permitir borrar renglones junto con cabecera.
-- El supuesto 14 dice: "D1/D5 eliminan cabecera y renglones; no revierten stock".
-- El trigger debería permitir esto cuando es borrado en cascada del padre.
-- Pero el trigger actual no distingue.
-- SOLUCIÓN PARA ESTA CONSULTA: Borrar la cabecera directamente (el CASCADE propagará
-- a renglones, pero el trigger bloqueará). No hay forma en SQL estándar de saltar el trigger.
-- OPCIÓN: Usar ALTER TABLE ... DISABLE TRIGGER ... pero requiere propietario y no es transaccional seguro.
-- OPCIÓN: El trigger debería verificar si el DELETE viene de CASCADE (pg_trigger_depth > 1).
-- Para esta consulta, documentamos el problema y usamos la sintaxis que el modelo permite.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO (ACTUALIZADO)
-- -----------------------------------------------------------------------------
-- PROBLEMA CONOCIDO: El trigger trg_renglon_comprobante_inmutable (RN-08/12)
-- impide borrar renglones si la cabecera existe, incluso en DELETE CASCADE.
-- Para que D1 funcione, el trigger debería permitir borrado cuando pg_trigger_depth() > 1
-- (indicando que viene de un DELETE en cascada del padre).
-- Como el modelo actual no lo permite, esta consulta requeriría:
--   ALTER TABLE bodegas.renglon_comprobante DISABLE TRIGGER trg_renglon_comprobante_inmutable;
--   DELETE FROM bodegas.comprobante WHERE ...;  -- CASCADE borra renglones
--   ALTER TABLE bodegas.renglon_comprobante ENABLE TRIGGER trg_renglon_comprobante_inmutable;
-- Pero DISABLE TRIGGER no es transaccional y requiere propietario.
-- ALTERNATIVA DOCUMENTADA: Se asume que el trigger se corregirá para permitir
-- DELETE CASCADE (ver pg_trigger_depth() > 0).
-- Con esa corrección, la consulta simple es:
-- DELETE FROM bodegas.comprobante
--  WHERE fecha < CURRENT_DATE - INTERVAL '5 years'
--    AND id_cliente IN (SELECT id_cliente FROM bodegas.cliente WHERE tipo = 'socio');
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL (ASUMIENDO TRIGGER CORREGIDO)
-- -----------------------------------------------------------------------------
/*
-- Con trigger corregido (permite CASCADE):
DELETE FROM bodegas.comprobante
 WHERE fecha < CURRENT_DATE - INTERVAL '5 years'
   AND id_cliente IN (SELECT id_cliente FROM bodegas.cliente WHERE tipo = 'socio');

-- Sin corrección, requiere desactivar trigger (no recomendado en transacción):
-- ALTER TABLE bodegas.renglon_comprobante DISABLE TRIGGER trg_renglon_comprobante_inmutable;
-- DELETE FROM bodegas.comprobante WHERE ...;
-- ALTER TABLE bodegas.renglon_comprobante ENABLE TRIGGER trg_renglon_comprobante_inmutable;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sin comprobantes de socios >5 años
-- DELETE ...;
-- Esperado: 0 filas afectadas, sin error

-- Caso: trigger actual sin corrección
-- DELETE FROM comprobante WHERE ...;
-- Esperado: SQLSTATE P0001 del trigger trg_renglon_comprobante_inmutable
--   "RN-08: no se borran renglones sueltos de un comprobante."
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Más de cinco años" se calcula relativo a CURRENT_DATE.
-- El borrado histórico no revierte stock (supuesto 14, docs/requisitos.md).
-- El trigger trg_renglon_comprobante_inmutable debería actualizarse para
-- permitir DELETE CASCADE verificando pg_trigger_depth() > 0.


-- =============================================================================
-- D2: Eliminar cepas que no componen vinos ni están plantadas
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D2
-- Tipo:             DELETE
-- Enunciado:        Eliminar cepas que no componen vinos ni están plantadas
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran cepas que no tienen filas en composicion_vino (no componen vinos)
-- Y no tienen filas en parcela (no están plantadas en ninguna parcela).
-- FK: fk_composicion_vino_cepa (id_cepa -> cepa) ON DELETE RESTRICT
-- FK: fk_parcela_cepa (id_cepa -> cepa) ON DELETE RESTRICT
-- Por RESTRICT, no se puede borrar si hay referencias. La consulta filtra
-- cepas SIN referencias, por lo que el DELETE debería pasar.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver cepas sin uso:
-- SELECT c.id_cepa, c.nombre, c.tipo
--   FROM bodegas.cepa c
--  WHERE NOT EXISTS (SELECT 1 FROM bodegas.composicion_vino cv WHERE cv.id_cepa = c.id_cepa)
--    AND NOT EXISTS (SELECT 1 FROM bodegas.parcela p WHERE p.id_cepa = c.id_cepa);
-- Valores típicos: cepas 20-50, algunas solo en catálogo sin uso.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: cepas a eliminar
SELECT c.id_cepa, c.nombre, c.tipo
  FROM bodegas.cepa c
 WHERE NOT EXISTS (SELECT 1 FROM bodegas.composicion_vino cv WHERE cv.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM bodegas.parcela p WHERE p.id_cepa = c.id_cepa);

-- Sentencia principal
DELETE FROM bodegas.cepa
 WHERE NOT EXISTS (SELECT 1 FROM bodegas.composicion_vino cv WHERE cv.id_cepa = cepa.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM bodegas.parcela p WHERE p.id_cepa = cepa.id_cepa);

-- Control posterior: verificar que no quedaron cepas sin uso
SELECT c.id_cepa, c.nombre, c.tipo,
       (SELECT count(*) FROM bodegas.composicion_vino cv WHERE cv.id_cepa = c.id_cepa) AS en_vinos,
       (SELECT count(*) FROM bodegas.parcela p WHERE p.id_cepa = c.id_cepa) AS en_parcelas
  FROM bodegas.cepa c
 WHERE NOT EXISTS (SELECT 1 FROM bodegas.composicion_vino cv WHERE cv.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM bodegas.parcela p WHERE p.id_cepa = c.id_cepa);

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- FOREIGN KEY constraints (ON DELETE RESTRICT):
--   fk_composicion_vino_cepa (id_cepa -> cepa)
--   fk_parcela_cepa (id_cepa -> cepa)
--   Al filtrar cepas SIN referencias, el RESTRICT no se viola.
-- UNIQUE: uq_cepa_nombre
-- CHECK: ck_cepa_tipo (tipo IN ('tinta','blanca'))
-- Reglas de negocio: RN-04 (una cepa por parcela) - no afectado al borrar sin referencias
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
DELETE FROM bodegas.cepa
 WHERE NOT EXISTS (SELECT 1 FROM bodegas.composicion_vino cv WHERE cv.id_cepa = cepa.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM bodegas.parcela p WHERE p.id_cepa = cepa.id_cepa);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: cepa referenciada en composicion_vino
-- DELETE FROM cepa WHERE id_cepa = :id_cepa_en_uso;
-- Esperado: SQLSTATE 23503 (foreign_key_violation), constraint fk_composicion_vino_cepa

-- Caso: cepa referenciada en parcela
-- DELETE FROM cepa WHERE id_cepa = :id_cepa_plantada;
-- Esperado: SQLSTATE 23503, constraint fk_parcela_cepa
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- La doble verificación (NOT EXISTS en ambas tablas) garantiza que la cepa
-- está completamente huérfana antes de intentar borrarla.
-- El RESTRICT en las FK actúa como protección adicional.


-- =============================================================================
-- D3: Eliminar empleados con menos de dos años de una sala dada de baja
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D3
-- Tipo:             DELETE
-- Enunciado:        Eliminar empleados con menos de dos años de una sala dada de baja
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran empleados de una sala específica (:id_sala) que tengan
-- fn_antiguedad_anios(fecha_ingreso) < 2.
-- FK: fk_empleado_sala_venta (id_sala -> sala_venta) ON DELETE RESTRICT
-- Al borrar empleados, no hay tablas hijas que referencien a empleado (PK cuit).
-- fn_antiguedad_anios es IMMUTABLE.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver empleados de una sala con antigüedad:
-- SELECT cuit, nombre, fecha_ingreso, salario,
--        bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios
--   FROM bodegas.empleado
--  WHERE id_sala = :id_sala
--  ORDER BY anios;
-- Valores típicos: antigüedad 0-15 años, salario 50000-500000.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: empleados a borrar
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE id_sala = :id_sala
   AND bodegas.fn_antiguedad_anios(fecha_ingreso) < 2
 ORDER BY anios_antiguedad;

-- Sentencia principal
DELETE FROM bodegas.empleado
 WHERE id_sala = :id_sala
   AND bodegas.fn_antiguedad_anios(fecha_ingreso) < 2;

-- Control posterior: empleados restantes en la sala
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE id_sala = :id_sala
 ORDER BY anios_antiguedad;

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- FOREIGN KEY:
--   fk_empleado_sala_venta (id_sala) ON UPDATE RESTRICT ON DELETE RESTRICT
--   Al borrar empleados, no hay tablas que referencien a empleado (es hoja).
-- CHECK:
--   ck_empleado_salario_positivo (salario > 0) - no afectado
-- Reglas de negocio: RN-03 (empleado en una sola sala) - FK garantiza
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
DELETE FROM bodegas.empleado
 WHERE id_sala = :id_sala
   AND bodegas.fn_antiguedad_anios(fecha_ingreso) < 2;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sala inexistente
-- DELETE ... WHERE id_sala = 99999;
-- Esperado: 0 filas afectadas (FK no se verifica en DELETE del padre, solo en INSERT/UPDATE del hijo)

-- Caso: sin empleados con <2 años en esa sala
-- DELETE ...;
-- Esperado: 0 filas afectadas, sin error
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- fn_antiguedad_anios usa CURRENT_DATE por defecto (se evalúa en la llamada).
-- La sala "dada de baja" se identifica por :id_sala parámetro.
-- No hay trigger que impida borrar empleados.


-- =============================================================================
-- D4: Borrar socios sin compras dados de alta hace más de cinco años
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D4
-- Tipo:             DELETE
-- Enunciado:        Borrar socios sin compras dados de alta hace más de cinco años
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran clientes de tipo 'socio' que:
-- 1. No tienen ningún comprobante (sin compras)
-- 2. fecha_alta < CURRENT_DATE - INTERVAL '5 years'
-- La jerarquía tiene FK compuestas: socio_club (id_cliente, tipo) REFERENCES cliente(id_cliente, tipo)
-- ON DELETE CASCADE en la FK de socio_club -> borrar cliente borra socio_club en cascada.
-- FK de comprobante a cliente es ON DELETE RESTRICT, pero filtramos sin comprobantes.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver socios sin compras >5 años:
-- SELECT c.id_cliente, c.nombre_razon_social, c.fecha_alta,
--        (SELECT count(*) FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente) AS num_compras
--   FROM bodegas.cliente c
--   JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
--  WHERE c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
--    AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente)
--  ORDER BY c.fecha_alta;
-- Valores típicos: fecha_alta 2015-2020 para >5 años, muchos socios sin compras.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: socios a borrar
SELECT c.id_cliente, c.nombre_razon_social, c.fecha_alta,
       c.tipo, c.descuento_excepcion
  FROM bodegas.cliente c
  JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
 WHERE c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente)
 ORDER BY c.fecha_alta;

-- Sentencia principal: borrar cliente (arrastra socio_club por CASCADE)
DELETE FROM bodegas.cliente
 WHERE tipo = 'socio'
   AND fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = cliente.id_cliente);

-- Control posterior: verificar que no quedaron
SELECT c.id_cliente, c.nombre_razon_social, c.fecha_alta
  FROM bodegas.cliente c
  JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
 WHERE c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente);

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- FOREIGN KEY:
--   fk_socio_club_cliente (id_cliente, tipo -> cliente) ON DELETE CASCADE
--   fk_comprobante_cliente (id_cliente -> cliente) ON DELETE RESTRICT
--     (pero filtramos sin comprobantes, así que no se viola)
-- Constraint triggers DEFERRABLE:
--   ctrg_cliente_subtipo (totalidad): al borrar cliente, borra socio_club en cascada,
--     y el trigger diferido verifica que el cliente ya no existe (OK).
-- CHECK:
--   ck_socio_club_tipo (tipo = 'socio')
--   ck_cliente_descuento_excepcion
-- Reglas de negocio: Jerarquía de clientes (exclusividad y totalidad)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
DELETE FROM bodegas.cliente
 WHERE tipo = 'socio'
   AND fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = cliente.id_cliente);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: socio con compras (comprobantes)
-- DELETE ... AND NOT EXISTS ... (filtro excluye los que tienen compras)
-- Esperado: 0 filas afectadas para ese socio

-- Caso: cliente tipo 'distribuidor' sin compras >5 años
-- DELETE ... WHERE tipo = 'socio' ... (filtro excluye no socios)
-- Esperado: 0 filas afectadas
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Más de cinco años" se calcula relativo a CURRENT_DATE.
-- El CASCADE en socio_club limpia la fila del subtipo automáticamente.
-- El constraint trigger diferido ctrg_cliente_subtipo se ejecuta al COMMIT
-- y verifica que el cliente borrado ya no requiere subtipo (pasa).


-- =============================================================================
-- D5: Eliminar ingresos procesados de más de 365 días
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D5
-- Tipo:             DELETE
-- Enunciado:        Eliminar ingresos procesados de más de 365 días
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran ingresos con estado = 'procesado' y fecha < CURRENT_DATE - INTERVAL '365 days'.
-- FK: fk_renglon_ingreso_ingreso (cod_ingreso -> ingreso) ON DELETE CASCADE
--   -> borrar ingreso arrastra renglones automáticamente.
-- Triggers: trg_renglon_ingreso_bloqueo permite DELETE en cascada (CONTINUE WHEN NOT FOUND).
-- Supuesto (docs/requisitos.md #14): borrado histórico no revierte stock del depósito.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver ingresos a borrar:
-- SELECT i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, i.cod_transportista,
--        count(ri.cod_vino) AS renglones, sum(ri.cantidad) AS botellas
--   FROM bodegas.ingreso i
--   LEFT JOIN bodegas.renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
--  WHERE i.estado = 'procesado'
--    AND i.fecha < CURRENT_DATE - INTERVAL '365 days'
--  GROUP BY i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, i.cod_transportista
--  ORDER BY i.fecha;
-- Valores típicos: ingresos 2020-2023 procesados, 1-5 renglones cada uno.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: ingresos a borrar
SELECT i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, i.cod_transportista,
       count(ri.cod_vino) AS renglones, COALESCE(sum(ri.cantidad), 0) AS botellas
  FROM bodegas.ingreso i
  LEFT JOIN bodegas.renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
 WHERE i.estado = 'procesado'
   AND i.fecha < CURRENT_DATE - INTERVAL '365 days'
 GROUP BY i.cod_ingreso, i.fecha, i.estado, i.cuit_bodega, i.cod_transportista
 ORDER BY i.fecha;

-- Sentencia principal: borrar ingreso (CASCADE borra renglones)
DELETE FROM bodegas.ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - INTERVAL '365 days';

-- Control posterior: verificar que no quedaron
SELECT count(*) AS ingresos_remanentes
  FROM bodegas.ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - INTERVAL '365 days';

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE (en renglon_ingreso):
--   trg_renglon_ingreso_bloqueo (RN-12): permite DELETE en cascada
--     (línea 397 en 005_triggers.sql: CONTINUE WHEN NOT FOUND cuando no hay cabecera)
-- FOREIGN KEY:
--   fk_renglon_ingreso_ingreso (cod_ingreso -> ingreso) ON DELETE CASCADE
--   fk_ingreso_transportista, fk_ingreso_bodega ON DELETE RESTRICT (padre no se borra)
-- Constraint triggers DEFERRABLE: ninguno en ingreso/renglon_ingreso
-- CHECK: ck_renglon_ingreso_cantidad_positiva
-- Reglas de negocio: RN-10 (flujo estados), RN-12 (renglones solo en confección)
--   El trigger permite borrado en cascada de documento procesado (histórico).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
DELETE FROM bodegas.ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - INTERVAL '365 days';
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: ingreso en estado 'en_confeccion' o 'terminado' >365 días
-- DELETE ... WHERE estado = 'procesado' ... (filtro excluye otros estados)
-- Esperado: no se borran

-- Caso: sin ingresos procesados >365 días
-- DELETE ...;
-- Esperado: 0 filas afectadas
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Más de 365 días" se calcula relativo a CURRENT_DATE.
-- El CASCADE en renglon_ingreso limpia los renglones automáticamente.
-- El trigger trg_renglon_ingreso_bloqueo está diseñado para permitir
-- este borrado histórico (supuesto 14).


-- =============================================================================
-- D6: Borrar socios sin compras de una localidad específica
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           D6
-- Tipo:             DELETE
-- Enunciado:        Borrar socios sin compras de una localidad específica
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se borran clientes de tipo 'socio' de una localidad específica (:id_localidad)
-- que no tienen ningún comprobante.
-- Similar a D4 pero filtrado por localidad en lugar de antigüedad.
-- FK cascada en socio_club, RESTRICT en comprobante (filtramos sin compras).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver socios sin compras en una localidad:
-- SELECT c.id_cliente, c.nombre_razon_social, c.id_localidad, l.nombre AS localidad
--   FROM bodegas.cliente c
--   JOIN bodegas.localidad l ON l.id_localidad = c.id_localidad
--   JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
--  WHERE c.id_localidad = :id_localidad
--    AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente)
--  ORDER BY c.id_cliente;
-- Valores típicos: localidades 50-100, varios socios sin compras por localidad.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: socios a borrar
SELECT c.id_cliente, c.nombre_razon_social, c.id_localidad, l.nombre AS localidad
  FROM bodegas.cliente c
  JOIN bodegas.localidad l ON l.id_localidad = c.id_localidad
  JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
 WHERE c.id_localidad = :id_localidad
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente)
 ORDER BY c.id_cliente;

-- Sentencia principal
DELETE FROM bodegas.cliente
 WHERE tipo = 'socio'
   AND id_localidad = :id_localidad
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = cliente.id_cliente);

-- Control posterior
SELECT c.id_cliente, c.nombre_razon_social, c.id_localidad, l.nombre AS localidad
  FROM bodegas.cliente c
  JOIN bodegas.localidad l ON l.id_localidad = c.id_localidad
  JOIN bodegas.socio_club sc ON sc.id_cliente = c.id_cliente
 WHERE c.id_localidad = :id_localidad
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = c.id_cliente);

GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- FOREIGN KEY:
--   fk_socio_club_cliente (id_cliente, tipo -> cliente) ON DELETE CASCADE
--   fk_comprobante_cliente (id_cliente -> cliente) ON DELETE RESTRICT
--   fk_cliente_localidad (id_localidad -> localidad) ON DELETE RESTRICT
-- Constraint triggers DEFERRABLE:
--   ctrg_cliente_subtipo (totalidad)
-- CHECK: ck_socio_club_tipo, ck_cliente_descuento_excepcion
-- Reglas de negocio: Jerarquía de clientes
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
DELETE FROM bodegas.cliente
 WHERE tipo = 'socio'
   AND id_localidad = :id_localidad
   AND NOT EXISTS (SELECT 1 FROM bodegas.comprobante cmp WHERE cmp.id_cliente = cliente.id_cliente);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: localidad inexistente
-- DELETE ... WHERE id_localidad = 99999;
-- Esperado: 0 filas afectadas (FK cliente_localidad no se verifica en DELETE del padre)

-- Caso: socio con compras en esa localidad
-- Filtro NOT EXISTS excluye -> no se borra
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- Similar a D4 pero con filtro de localidad en lugar de antigüedad.
-- El parámetro :id_localidad identifica la localidad específica.