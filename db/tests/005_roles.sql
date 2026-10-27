\set ON_ERROR_STOP on
\pset pager off

-- Operaciones reales con los privilegios de cada grupo.
-- Ejecutar como propietario: carga datos base y después hace SET LOCAL ROLE a
-- bodegas_rw (API) y bodegas_ro (reportes). El propietario es miembro de los
-- grupos sólo con la opción SET (ver db/bootstrap), así que dentro del SET ROLE
-- tiene exactamente los privilegios del grupo. Todo termina en ROLLBACK.
-- Las denegaciones esperan SQLSTATE 42501 (insufficient_privilege).

SET search_path TO bodegas, pg_catalog;
BEGIN;
\ir ayudantes.sql

-- Los ayudantes son del propietario; los grupos necesitan poder ejecutarlos.
GRANT EXECUTE ON FUNCTION
  pg_temp.esperar_error(TEXT, TEXT, TEXT, TEXT),
  pg_temp.afirmar(BOOLEAN, TEXT)
TO bodegas_rw, bodegas_ro;

-------------------------------------------------------------------------------
-- Funciones SECURITY DEFINER: lista cerrada, search_path fijo y sin PUBLIC.
-------------------------------------------------------------------------------
SELECT pg_temp.afirmar(
  (SELECT array_agg(proname::TEXT ORDER BY proname)
   FROM pg_proc
   WHERE pronamespace = 'bodegas'::regnamespace AND prosecdef)
  = ARRAY[
      'fn_trg_renglon_comprobante_completar', 'fn_trg_renglon_comprobante_impactar',
      'fn_trg_renglon_ingreso_bloqueo', 'fn_trg_renglon_transferencia_bloqueo',
      'fn_trg_vino_auditoria_precio', 'sp_procesar_ingreso',
      'sp_procesar_transferencia', 'sp_terminar_ingreso', 'sp_terminar_transferencia'],
  'sólo las rutinas previstas son SECURITY DEFINER');

SELECT pg_temp.afirmar(
  NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE pronamespace = 'bodegas'::regnamespace
      AND NOT ('search_path=bodegas, pg_temp' = ANY (COALESCE(proconfig, '{}')))
  ),
  'toda rutina del esquema fija search_path = bodegas, pg_temp');

SELECT pg_temp.afirmar(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc AS p
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS a
    WHERE p.pronamespace = 'bodegas'::regnamespace
      AND a.grantee = 0
  ),
  'ninguna rutina es ejecutable por PUBLIC');
\echo 'OK: SECURITY DEFINER acotado, search_path fijo y sin EXECUTE público.'

-------------------------------------------------------------------------------
-- Datos base (propietario).
-------------------------------------------------------------------------------
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
OVERRIDING SYSTEM VALUE VALUES (920001, '5600-P', 'Localidad P', 'Mendoza P', 'Encargado P');
INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE VALUES (920001, 'Calle P', '1', 'lunes', 920001);
INSERT INTO cepa (id_cepa, nombre, tipo) OVERRIDING SYSTEM VALUE VALUES (920001, 'Cepa P', 'tinta');
INSERT INTO maridaje (id_maridaje, nombre, temperatura_servicio_c)
OVERRIDING SYSTEM VALUE VALUES (920001, 'Maridaje P', 16.0);
INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30920000001', 'Bodega P', 'Dom P');
INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (920001, 'Transporte P', '30920000002', 'p@example.invalid', '2604000002', 'Dom P');
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (920001, 'Vino P', 'tinto', 2023, 750, 13.00, 1000.00, '30920000001');
INSERT INTO composicion_vino VALUES (920001, 920001, 100.00);
INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento,
                     direccion, id_localidad, tipo)
OVERRIDING SYSTEM VALUE VALUES (920001, 'Socio P', 'DNI', '92000001', 'Dir', 920001, 'socio');
INSERT INTO socio_club (id_cliente) VALUES (920001);
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (920001, 920001, 10);
INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (920001, 100);

-------------------------------------------------------------------------------
-- API: bodegas_rw
-------------------------------------------------------------------------------
SET LOCAL ROLE bodegas_rw;

-- Puede: catálogo, vistas y funciones de cálculo.
SELECT pg_temp.afirmar(
  (SELECT stock_total FROM v_ficha_vino WHERE cod_vino = 920001) = 110
  AND fn_stock_sala(920001, 920001) = 10
  AND fn_descuento_cliente(920001) = 10,
  'API: lee vistas y ejecuta funciones de cálculo');

-- Puede: alta de vino con composición (IDENTITY sin USAGE sobre la secuencia).
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino nuevo API', 'blanco', 2024, 750, 12.50, 900.00, '30920000001')
RETURNING cod_vino AS vino_api \gset
INSERT INTO composicion_vino VALUES (:vino_api, 920001, 100.00);
INSERT INTO vino_maridaje VALUES (:vino_api, 920001);
SELECT pg_temp.afirmar(
  NOT has_sequence_privilege('bodegas.vino_cod_vino_seq', 'USAGE'),
  'API: el alta con IDENTITY funcionó sin USAGE sobre la secuencia');

-- Puede: cambiar un precio; la auditoría la escribe el trigger.
UPDATE vino SET precio = 950.00 WHERE cod_vino = :vino_api;
SELECT pg_temp.afirmar(
  EXISTS (SELECT 1 FROM auditoria_precio WHERE cod_vino = :vino_api AND precio_nuevo = 950.00),
  'API: cambio de precio auditado por trigger');

-- Puede: alta de cliente con su subtipo.
INSERT INTO cliente (nombre_razon_social, tipo_documento, nro_documento, direccion, id_localidad, tipo)
VALUES ('Distribuidor API', 'CUIT', '30920000009', 'Dir', 920001, 'distribuidor')
RETURNING id_cliente AS cliente_api \gset
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
VALUES (:cliente_api, 'Zona API', 'HAB-API');

-- Puede: vender. La base completa precio, descuento, stock e importes.
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:cliente_api, 920001)
RETURNING nro_comprobante AS comprobante_api \gset
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
VALUES (:comprobante_api, 920001, 3);
SELECT pg_temp.afirmar(
  (SELECT total FROM comprobante WHERE nro_comprobante = :comprobante_api) = 2400.00
  AND fn_stock_sala(920001, 920001) = 7,
  'API: venta con total calculado (20 %) y stock descontado');

-- Puede: ingreso completo por procedimientos.
INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (920001, '30920000001')
RETURNING cod_ingreso AS ingreso_api \gset
INSERT INTO renglon_ingreso VALUES (:ingreso_api, 920001, 24);
UPDATE renglon_ingreso SET cantidad = 12 WHERE cod_ingreso = :ingreso_api;
CALL sp_terminar_ingreso(:ingreso_api);
CALL sp_procesar_ingreso(:ingreso_api);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 920001) = 112,
  'API: ingreso procesado por procedimiento');

-- Puede: transferencia completa por procedimientos.
INSERT INTO transferencia (id_sala) VALUES (920001)
RETURNING nro_transferencia AS transferencia_api \gset
INSERT INTO renglon_transferencia VALUES (:transferencia_api, 920001, 2);
CALL sp_terminar_transferencia(:transferencia_api);
CALL sp_procesar_transferencia(:transferencia_api);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 920001) = 110
  AND fn_stock_sala(920001, 920001) = 9,
  'API: transferencia procesada por procedimiento');

-- Las reglas diferidas se cumplen también con el rol de la API.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- No puede: tocar stock, auditoría, importes, estados ni la tabla técnica.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE stock_sala SET cantidad = 999 WHERE id_sala = 920001 $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (920001, 1) $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM stock_sala $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo) VALUES (920001, 1, 2) $sql$,
  '42501');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE comprobante SET total = 0 $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO comprobante (id_cliente, id_sala, total) VALUES (920001, 920001, 0) $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario)
        VALUES (1, 920001, 1, 1) $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM renglon_comprobante $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE ingreso SET estado = 'procesado' $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE transferencia SET estado = 'terminado' $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_recalcular_comprobante(1) $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ SELECT archivo FROM schema_migration $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ SELECT salario FROM empleado $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ TRUNCATE vino $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ CREATE TABLE intruso (id INTEGER) $sql$, '42501');
\echo 'OK: la API opera por los caminos previstos y no toca stock, auditoría, importes ni estados.'

RESET ROLE;

-------------------------------------------------------------------------------
-- Reportes: bodegas_ro
-------------------------------------------------------------------------------
SET LOCAL ROLE bodegas_ro;

-- Puede: leer tablas, vistas y ejecutar funciones de cálculo.
SELECT pg_temp.afirmar(
  (SELECT count(*) FROM v_ventas_mensuales_sala WHERE id_sala = 920001) = 1
  AND (SELECT count(*) FROM empleado) >= 0
  AND fn_total_comprobante(:comprobante_api) = 2400.00,
  'reportes: lee tablas, vistas y funciones de cálculo');

-- No puede: escribir, ejecutar procedimientos ni leer la tabla técnica.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30920000099', 'X', 'Y') $sql$,
  '42501');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE vino SET precio = 1 $sql$, '42501');
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM cliente $sql$, '42501');
SELECT pg_temp.esperar_error(
  'CALL sp_procesar_ingreso(1)', '42501');
SELECT pg_temp.esperar_error(
  $sql$ SELECT archivo FROM schema_migration $sql$, '42501');
\echo 'OK: reportes sólo lee.'

RESET ROLE;
ROLLBACK;
\echo 'OK: los datos de prueba fueron revertidos.'
