-- =============================================================================
-- CONSULTAS UPDATE - ETAPA 5
-- Bodegas del Atuel - Trabajo Práctico Integrador BD 2026
-- =============================================================================
--
-- Cada consulta sigue el protocolo obligatorio:
--   BEGIN;
--   -- Control previo
--   -- Sentencia UPDATE
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
-- U1: Recalcular todos los totales de comprobantes aplicando el descuento del tipo de cliente
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U1
-- Tipo:             UPDATE
-- Enunciado:        Recalcular todos los totales de comprobantes aplicando el descuento del tipo de cliente
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se debe recalcular el total de cada comprobante usando la función fn_recalcular_comprobante
-- que a su vez invoca fn_descuento_cliente(id_cliente) y fn_total_comprobante(nro_comprobante).
-- El trigger trg_comprobante_recalcular_total (AFTER UPDATE OF descuento ON comprobante) 
-- recalcula el total. La PK de comprobante y la FK a cliente garantizan integridad referencial.
-- RN-06 y RN-08 son las reglas de negocio involucradas.
-- Se usa un UPDATE masivo con FROM para invocar la función por cada comprobante.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET (ETAPA 3)
-- -----------------------------------------------------------------------------
-- Ejecutar para ver comprobantes de ejemplo:
-- SELECT nro_comprobante, id_cliente, subtotal, descuento, total FROM bodegas.comprobante ORDER BY fecha DESC LIMIT 10;
-- Valores típicos: nro_comprobante 1-150125, id_cliente 1-20000, total calculado desde renglones.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: estado ANTES de la modificación
SELECT count(*) AS total_comprobantes,
       sum(total) AS suma_total_antes
  FROM bodegas.comprobante;

-- Sentencia principal: recalcular todos los comprobantes
UPDATE bodegas.comprobante c
   SET subtotal = 0, descuento = 0, total = 0  -- Valores temporales; fn_recalcular_comprobante los sobrescribe
  FROM (
    SELECT nro_comprobante
      FROM bodegas.comprobante
  ) AS sub
 WHERE c.nro_comprobante = sub.nro_comprobante;

-- Nota: El UPDATE anterior pone los importes a 0 para permitir que el trigger
-- trg_comprobante_importes acepte la modificación (requiere bodegas.recalculo_importes=on).
-- La función fn_recalcular_comprobante se invoca internamente por el trigger
-- AFTER INSERT de renglones, pero aquí no hay renglones nuevos.
-- Por tanto, debemos invocar fn_recalcular_comprobante explícitamente para cada comprobante:
DO $$
DECLARE
  v_nro BIGINT;
BEGIN
  FOR v_nro IN SELECT nro_comprobante FROM bodegas.comprobante LOOP
    PERFORM bodegas.fn_recalcular_comprobante(v_nro);
  END LOOP;
END $$;

-- Control posterior: estado DESPUÉS de la modificación
SELECT count(*) AS total_comprobantes,
       sum(total) AS suma_total_despues
  FROM bodegas.comprobante;

-- Verificar filas afectadas
DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO INVOLUCRADOS
-- -----------------------------------------------------------------------------
-- Triggers BEFORE:
--   trg_comprobante_importes (RN-08): valida que la marca bodegas.recalculo_importes esté 'on'
-- Triggers AFTER:
--   (ninguno directo en este UPDATE masivo, pero fn_recalcular_comprobante hace UPDATE interno)
-- CHECK constraints:
--   ck_comprobante_importes: total = subtotal - descuento, subtotal >= 0, descuento >= 0
-- FOREIGN KEY constraints:
--   fk_comprobante_id_cliente, fk_comprobante_id_sala
-- Reglas de negocio:
--   RN-06 (descuento según tipo de cliente), RN-08 (total derivado de renglones y descuento)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL (versión parametrizada para uso individual)
-- -----------------------------------------------------------------------------
/*
-- Para recalcular un solo comprobante:
SELECT bodegas.fn_recalcular_comprobante(:nro_comprobante);

-- Para recalcular todos (versión SET-based alternativa):
UPDATE bodegas.comprobante
   SET (subtotal, descuento, total) = (0, 0, 0)
 WHERE nro_comprobante IN (SELECT nro_comprobante FROM bodegas.comprobante);
-- Luego invocar fn_recalcular_comprobante para cada uno (en DO block como arriba)
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: comprobante inexistente en fn_recalcular_comprobante
-- SELECT bodegas.fn_recalcular_comprobante(999999999);
-- Esperado: SQLSTATE P0002 (no_data_found), mensaje "El comprobante 999999999 no existe."

-- Caso: comprobante sin renglones (violación de RN-08)
-- INSERT INTO bodegas.comprobante (id_cliente, id_sala) VALUES (1, 1)  -- sin renglones
-- Esperado: SQLSTATE P0001 del constraint trigger ctrg_comprobante_con_renglones
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES Y DECISIONES DE DISEÑO
-- -----------------------------------------------------------------------------
-- Se usa fn_recalcular_comprobante en un DO block porque encapsula la lógica de RN-08
-- y respeta la inmutabilidad de renglones confirmados (RN-12 / columna xact_alta).
-- El UPDATE masivo directo con SET (subtotal, descuento, total) = fn_recalcular... 
-- no es posible porque fn_recalcular_comprobante retorna VOID y modifica la tabla internamente.
-- La marca bodegas.recalculo_importes se enciende/apaga dentro de la función.


-- =============================================================================
-- U2: Aumentar 20 % el salario de empleados con más de cinco años de antigüedad
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U2
-- Tipo:             UPDATE
-- Enunciado:        Aumentar 20 % el salario de empleados con más de cinco años de antigüedad
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se usa la función fn_antiguedad_anios(fecha_ingreso, CURRENT_DATE) para calcular
-- los años completos de antigüedad. Se actualiza salario = salario * 1.20
-- donde fn_antiguedad_anios(fecha_ingreso) > 5.
-- fn_antiguedad_anios es IMMUTABLE, por lo que el planificador puede evaluarla
-- en la llamada. No hay triggers sobre empleado.salario.
-- CHECK constraint: ck_empleado_salario_positivo (salario > 0) - siempre se cumple al aumentar.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver empleados con >5 años:
-- SELECT cuit, nombre, fecha_ingreso, salario, bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios
--   FROM bodegas.empleado
--  WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
--  ORDER BY anios DESC;
-- Valores típicos: fecha_ingreso entre 2010-2024, salario 50000-500000.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY anios_antiguedad DESC;

-- Sentencia principal
UPDATE bodegas.empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5;

-- Control posterior
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY anios_antiguedad DESC;

DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints: ck_empleado_salario_positivo (salario > 0) - se cumple al aumentar
-- FOREIGN KEY: fk_empleado_sala_venta (id_sala)
-- Reglas de negocio: Ninguna RN directa; U2 es una consulta de mantenimiento
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sin empleados con >5 años (dataset pequeño)
-- UPDATE ... WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
-- Esperado: 0 filas afectadas, sin error
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- fn_antiguedad_anios usa CURRENT_DATE como DEFAULT, que se evalúa en la llamada.
-- El ROUND a 2 decimales mantiene la precisión de NUMERIC(14,2).


-- =============================================================================
-- U3: Aumentar 13 % el precio de vinos de una bodega elegida
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U3
-- Tipo:             UPDATE
-- Enunciado:        Aumentar 13 % el precio de vinos de una bodega elegida
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se actualiza vino.precio = ROUND(precio * 1.13, 2) para vinos de una bodega
-- identificada por CUIT o razón social. El trigger trg_vino_auditoria_precio
-- (AFTER UPDATE OF precio) registra automáticamente el cambio en auditoria_precio
-- con precio_anterior, precio_nuevo, fecha_hora y session_user (RN-13).
-- CHECK constraints: ck_vino_precio_positivo (precio > 0) - se cumple al aumentar.
-- FK: fk_vino_bodega (cuit_bodega)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver bodegas y sus vinos:
-- SELECT b.cuit, b.razon_social, v.cod_vino, v.nombre, v.precio
--   FROM bodegas.bodega b
--   JOIN bodegas.vino v ON v.cuit_bodega = b.cuit
--  ORDER BY b.razon_social, v.cod_vino
--  LIMIT 20;
-- Valores típicos: precio 500-10000, cuit_bodega 11 dígitos.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: precios antes del aumento
SELECT v.cod_vino, v.nombre, v.precio AS precio_antes,
       b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.cuit = :cuit_bodega  -- parámetro: ej. '20123456789'
 ORDER BY v.cod_vino;

-- Sentencia principal
UPDATE bodegas.vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = :cuit_bodega;

-- Control posterior: precios después del aumento
SELECT v.cod_vino, v.nombre, v.precio AS precio_despues,
       ROUND(v.precio / NULLIF(v.precio / 1.13, 0) * 100 - 100, 2) AS pct_cambio_calculado,
       b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.cuit = :cuit_bodega
 ORDER BY v.cod_vino;

-- Verificar auditoría (RN-13)
SELECT ap.cod_vino, v.nombre, ap.precio_anterior, ap.precio_nuevo,
       ap.fecha_hora, ap.usuario_bd
  FROM bodegas.auditoria_precio ap
  JOIN bodegas.vino v ON v.cod_vino = ap.cod_vino
 WHERE ap.fecha_hora >= (SELECT max(fecha_hora) FROM bodegas.auditoria_precio) - INTERVAL '1 minute'
   AND v.cuit_bodega = :cuit_bodega
 ORDER BY ap.fecha_hora DESC;

DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers AFTER:
--   trg_vino_auditoria_precio (RN-13): registra cambio de precio en auditoria_precio
-- CHECK constraints:
--   ck_vino_precio_positivo (precio > 0) - siempre se cumple al aumentar 13%
--   ck_vino_graduacion, ck_vino_tipo, ck_vino_volumen_positivo, etc. - no afectados
-- FOREIGN KEY:
--   fk_vino_bodega (cuit_bodega) - valida existencia de la bodega
-- Reglas de negocio:
--   RN-01 (precio único y positivo), RN-13 (auditoría de cambios de precio)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = :cuit_bodega;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: bodega inexistente
-- UPDATE bodegas.vino SET precio = precio * 1.13 WHERE cuit_bodega = '99999999999';
-- Esperado: 0 filas afectadas (no error, solo no hace nada por FK que no encuentra coincidencias)

-- Caso: precio resultante violaría CHECK - imposible al aumentar un precio > 0
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El trigger de auditoría usa session_user, que en la API será la cuenta de la API.
-- La auditoría es automática e inmutable (no se puede evitar sin desactivar el trigger).


-- =============================================================================
-- U4: Intercambiar lunes y miércoles como día de cierre, en una sola sentencia
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U4
-- Tipo:             UPDATE
-- Enunciado:        Intercambiar lunes y miércoles como día de cierre, en una sola sentencia
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se debe intercambiar los valores 'lunes' <-> 'miercoles' en sala_venta.dia_cierre
-- en una sola sentencia UPDATE. Se usa CASE WHEN para hacer el intercambio atómico.
-- CHECK constraint: ck_sala_venta_dia_cierre valida valores en la lista de 7 días.
-- No hay triggers sobre dia_cierre.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver distribución actual:
-- SELECT dia_cierre, count(*) AS cantidad
--   FROM bodegas.sala_venta
--  GROUP BY dia_cierre
--  ORDER BY cantidad DESC;
-- Valores: 'lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo
SELECT dia_cierre, count(*) AS cantidad
  FROM bodegas.sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

-- Sentencia principal: intercambio atómico en una sola sentencia
UPDATE bodegas.sala_venta
   SET dia_cierre = CASE
                      WHEN dia_cierre = 'lunes' THEN 'miercoles'
                      WHEN dia_cierre = 'miercoles' THEN 'lunes'
                      ELSE dia_cierre
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');

-- Control posterior
SELECT dia_cierre, count(*) AS cantidad
  FROM bodegas.sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints:
--   ck_sala_venta_dia_cierre (dia_cierre IN ('lunes','martes','miercoles','jueves','viernes','sabado','domingo'))
--   Los valores destino están en la lista, por lo que siempre pasa.
-- Reglas de negocio: RN-02 (sala en una localidad) - no afectado
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.sala_venta
   SET dia_cierre = CASE
                      WHEN dia_cierre = 'lunes' THEN 'miercoles'
                      WHEN dia_cierre = 'miercoles' THEN 'lunes'
                      ELSE dia_cierre
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sin salas con lunes o miércoles
-- UPDATE ... WHERE dia_cierre IN ('lunes', 'miercoles');
-- Esperado: 0 filas afectadas, sin error
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El CASE WHEN evalúa el valor original de cada fila antes de cualquier asignación,
-- garantizando el intercambio atómico sin necesidad de columna temporal ni transacción.


-- =============================================================================
-- U5: Aplicar 15 % de rebaja a los diez vinos menos vendidos de la red
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U5
-- Tipo:             UPDATE
-- Enunciado:        Aplicar 15 % de rebaja a los diez vinos menos vendidos de la red
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se identifican los 10 vinos con menos botellas vendidas (suma de cantidad en
-- renglon_comprobante). Se aplica descuento: precio = ROUND(precio * 0.85, 2).
-- El trigger trg_vino_auditoria_precio registra cada cambio (RN-13).
-- CHECK: ck_vino_precio_positivo - precio > 0, al reducir 15% se mantiene >0 si precio original > 0.
-- Período: "de la red" implica todo el historial, no un período relativo.
-- Se usa CTE con LIMIT 10 para seleccionar los vinos.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver ranking de ventas:
-- SELECT v.cod_vino, v.nombre, COALESCE(SUM(rc.cantidad), 0) AS total_vendido
--   FROM bodegas.vino v
--   LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
--  GROUP BY v.cod_vino, v.nombre
--  ORDER BY total_vendido ASC, v.cod_vino
--  LIMIT 15;
-- Valores típicos: muchos vinos con 0 ventas, otros con pocas unidades.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: los 10 menos vendidos antes
WITH ventas AS (
  SELECT v.cod_vino, v.nombre, v.precio AS precio_antes,
         COALESCE(SUM(rc.cantidad), 0) AS total_vendido
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino, v.nombre, v.precio
)
SELECT cod_vino, nombre, precio_antes, total_vendido
  FROM ventas
 ORDER BY total_vendido ASC, cod_vino
 LIMIT 10;

-- Sentencia principal
WITH menos_vendidos AS (
  SELECT v.cod_vino
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
   LIMIT 10
)
UPDATE bodegas.vino v
   SET precio = ROUND(v.precio * 0.85, 2)
  FROM menos_vendidos mv
 WHERE v.cod_vino = mv.cod_vino;

-- Control posterior: los 10 menos vendidos después
WITH ventas AS (
  SELECT v.cod_vino, v.nombre, v.precio AS precio_despues,
         COALESCE(SUM(rc.cantidad), 0) AS total_vendido
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino, v.nombre, v.precio
)
SELECT cod_vino, nombre, precio_despues, total_vendido,
       ROUND(precio_despues / NULLIF(precio_despues / 0.85, 0) * 100 - 100, 2) AS pct_cambio
  FROM ventas
 ORDER BY total_vendido ASC, cod_vino
 LIMIT 10;

-- Verificar auditoría
SELECT ap.cod_vino, v.nombre, ap.precio_anterior, ap.precio_nuevo,
       ap.fecha_hora, ap.usuario_bd
  FROM bodegas.auditoria_precio ap
  JOIN bodegas.vino v ON v.cod_vino = ap.cod_vino
 WHERE ap.fecha_hora >= (SELECT max(fecha_hora) FROM bodegas.auditoria_precio) - INTERVAL '1 minute'
 ORDER BY ap.fecha_hora DESC;

DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers AFTER:
--   trg_vino_auditoria_precio (RN-13): registra cada cambio de precio
-- CHECK constraints:
--   ck_vino_precio_positivo (precio > 0) - al reducir 15% de un precio > 0, el resultado sigue > 0
-- Reglas de negocio: RN-01 (precio único y positivo), RN-13 (auditoría)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
WITH menos_vendidos AS (
  SELECT v.cod_vino
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
   LIMIT 10
)
UPDATE bodegas.vino v
   SET precio = ROUND(v.precio * 0.85, 2)
  FROM menos_vendidos mv
 WHERE v.cod_vino = mv.cod_vino;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: menos de 10 vinos en la base
-- El LIMIT 10 devuelve los que hay; UPDATE afecta solo esos.
-- Esperado: filas afectadas = total de vinos (si < 10)

-- Caso: empate en ventas (mismo total_vendido)
-- El ORDER BY cod_vino desempata determinísticamente.
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "De la red" = todas las salas, todo el historial (no período relativo).
-- El LEFT JOIN incluye vinos sin ventas (total_vendido = 0), que son los primeros candidatos.
-- La auditoría registra cada cambio individual con session_user.


-- =============================================================================
-- U6: Elevar a 35 % el descuento de exportadores con más de tres permisos
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U6
-- Tipo:             UPDATE
-- Enunciado:        Elevar a 35 % el descuento de exportadores con más de tres permisos
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se actualiza cliente.descuento_excepcion = 35.00 para exportadores que tengan
-- más de 3 permisos en permiso_exportacion. El trigger BEFORE trg_cliente_excepcion
-- valida que el exportador tenga >3 permisos al asignar la excepción (RN-06/U6).
-- El constraint trigger diferido ctrg_permiso_excepcion verifica al confirmar
-- que no quede una excepción sin respaldo.
-- CHECK: ck_cliente_descuento_excepcion exige tipo='exportador' y valor=35.00.
-- FK: fk_permiso_exportacion_exportador (id_exportador -> exportador.id_cliente)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver exportadores y sus permisos:
-- SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion,
--        count(pe.codigo_permiso) AS num_permisos
--   FROM bodegas.cliente c
--   JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
--   LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
--  WHERE c.tipo = 'exportador'
--  GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
--  ORDER BY num_permisos DESC;
-- Valores típicos: exportadores con 1-10 permisos, descuento_excepcion NULL o 35.00.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
BEGIN;

-- Control previo: exportadores con >3 permisos y su descuento actual
SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion AS desc_antes,
       count(pe.codigo_permiso) AS num_permisos
  FROM bodegas.cliente c
  JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
 WHERE c.tipo = 'exportador'
 GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
 HAVING count(pe.codigo_permiso) > 3
 ORDER BY num_permisos DESC;

-- Sentencia principal
UPDATE bodegas.cliente c
   SET descuento_excepcion = 35.00
  FROM (
    SELECT e.id_cliente
      FROM bodegas.exportador e
      JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
     GROUP BY e.id_cliente
     HAVING count(pe.codigo_permiso) > 3
  ) AS sub
 WHERE c.id_cliente = sub.id_cliente
   AND (c.descuento_excepcion IS NULL OR c.descuento_excepcion <> 35.00);

-- Control posterior
SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion AS desc_despues,
       count(pe.codigo_permiso) AS num_permisos
  FROM bodegas.cliente c
  JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
 WHERE c.tipo = 'exportador'
 GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
 HAVING count(pe.codigo_permiso) > 3
 ORDER BY num_permisos DESC;

DO $body$
DECLARE filas_afectadas integer;
BEGIN
  GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
  RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
END $body$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE:
--   trg_cliente_excepcion (RN-06/U6): valida >3 permisos al asignar descuento_excepcion
-- Constraint triggers DEFERRABLE:
--   ctrg_permiso_excepcion (RN-06/U6): al confirmar, valida que no quede excepción sin >3 permisos
-- CHECK constraints:
--   ck_cliente_descuento_excepcion (tipo='exportador' AND descuento_excepcion=35.00)
--   ck_exportador_tipo (tipo = 'exportador')
-- FOREIGN KEY:
--   fk_cliente_localidad, fk_exportador_cliente, fk_permiso_exportacion_exportador
-- Reglas de negocio: RN-06 (descuento según tipo + excepción exportador >3 permisos)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.cliente c
   SET descuento_excepcion = 35.00
  FROM (
    SELECT e.id_cliente
      FROM bodegas.exportador e
      JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
     GROUP BY e.id_cliente
     HAVING count(pe.codigo_permiso) > 3
  ) AS sub
 WHERE c.id_cliente = sub.id_cliente
   AND (c.descuento_excepcion IS NULL OR c.descuento_excepcion <> 35.00);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: exportador con exactamente 3 permisos (no califica)
-- UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = :id_exp_3_permisos;
-- Esperado: SQLSTATE P0001 del trigger trg_cliente_excepcion
--   "RN-06: la excepción del 35% sólo corresponde a exportadores con más de tres permisos."

-- Caso: cliente no exportador (tipo socio/distribuidor)
-- UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = :id_socio;
-- Esperado: SQLSTATE 23514 (check_violation), constraint ck_cliente_descuento_excepcion
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- La validación ocurre en dos niveles: BEFORE (inmediata) y DEFERRABLE (al commit).
-- Esto permite quitar permisos y la excepción en la misma transacción.
-- Se filtra WHERE descuento_excepcion IS NULL OR <> 35.00 para evitar UPDATE innecesarios.