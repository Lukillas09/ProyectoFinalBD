\set ON_ERROR_STOP on
\pset pager off

-- Reglas de negocio RN-01 a RN-15, totalidad de la jerarquía de clientes y U6.
-- Ejecutar como propietario después de aplicar 001 a 007. Toda la carga vive
-- en una transacción que termina en ROLLBACK.
--
-- Cada caso indica el error esperado. esperar_error verifica SQLSTATE,
-- constraint y un patrón del mensaje; falla si la sentencia es aceptada.
--
-- Los CONSTRAINT TRIGGER diferidos se comprueban con
-- SET CONSTRAINTS ALL IMMEDIATE dentro de un SAVEPOINT: el error aparece en
-- ese momento y ROLLBACK TO SAVEPOINT descarta los datos inválidos.

SET search_path TO bodegas, pg_catalog;
BEGIN;
\ir ayudantes.sql

-------------------------------------------------------------------------------
-- Datos base válidos
-------------------------------------------------------------------------------
INSERT INTO departamento (id_departamento, nombre, provincia)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'San Rafael RN', 'Mendoza RN');

INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
OVERRIDING SYSTEM VALUE
VALUES (910001, '5600-R', 'Localidad RN', 'Mendoza RN', 'Encargada RN');

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Calle RN', '1', 'lunes', 910001),
       (910002, 'Calle RN', '2', 'martes', 910001);

INSERT INTO finca (id_finca, nombre, superficie_ha, id_departamento)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Finca RN', 50.00, 910001);

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Malbec RN', 'tinta'),
       (910002, 'Cabernet RN', 'tinta');

INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
VALUES (910001, 1, 5.00, 2010, 910001);

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30910000001', 'Bodega RN', 'Domicilio RN');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Malbec Reserva RN', 'tinto', 2021, 750, 14.00, 1000.00, '30910000001'),
       (910002, 'Cabernet RN', 'tinto', 2022, 750, 13.50, 2000.00, '30910000001'),
       (910003, 'Sin stock RN', 'tinto', 2023, 750, 13.00, 500.00, '30910000001');

INSERT INTO composicion_vino (cod_vino, id_cepa, porcentaje)
VALUES (910001, 910001, 85.00), (910001, 910002, 15.00),
       (910002, 910002, 100.00),
       (910003, 910001, 100.00);

INSERT INTO maridaje (id_maridaje, nombre, temperatura_servicio_c)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Carnes rojas RN', 17.0);

INSERT INTO vino_maridaje (cod_vino, id_maridaje) VALUES (910001, 910001);

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Transporte RN', '30910000002', 'rn@example.invalid', '2604000001', 'Domicilio RN');

INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento,
                     direccion, id_localidad, fecha_alta, tipo)
OVERRIDING SYSTEM VALUE
VALUES (910001, 'Socio RN', 'DNI', '91000001', 'Dir', 910001, DATE '2026-01-01', 'socio'),
       (910002, 'Distribuidor RN', 'CUIT', '30910000003', 'Dir', 910001, DATE '2026-01-01', 'distribuidor'),
       (910003, 'Exportador 4 permisos RN', 'CUIT', '30910000004', 'Dir', 910001, DATE '2026-01-01', 'exportador'),
       (910004, 'Exportador 2 permisos RN', 'CUIT', '30910000005', 'Dir', 910001, DATE '2026-01-01', 'exportador');

INSERT INTO socio_club (id_cliente) VALUES (910001);
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
VALUES (910002, 'Sur RN', 'HAB-RN-1');
INSERT INTO exportador (id_cliente, pais_destino_principal)
VALUES (910003, 'Chile'), (910004, 'Brasil');

INSERT INTO permiso_exportacion (codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento)
VALUES ('RN-P1', 910003, DATE '2025-01-01', DATE '2027-01-01'),
       ('RN-P2', 910003, DATE '2025-01-01', DATE '2027-01-01'),
       ('RN-P3', 910003, DATE '2025-01-01', DATE '2027-01-01'),
       ('RN-P4', 910003, DATE '2025-01-01', DATE '2027-01-01'),
       ('RN-P5', 910004, DATE '2025-01-01', DATE '2027-01-01'),
       ('RN-P6', 910004, DATE '2025-01-01', DATE '2027-01-01');

INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
VALUES (910001, 910001, 5), (910001, 910002, 10), (910001, 910003, 4);

INSERT INTO stock_deposito (cod_vino, cantidad) VALUES (910001, 100);

-- Los datos base deben cumplir también las reglas diferidas.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
\echo 'OK: datos base válidos, incluidas las reglas diferidas.'

-------------------------------------------------------------------------------
-- RN-01: precio único en la red y mayor que cero.
-------------------------------------------------------------------------------
-- Funciona: el precio vive una sola vez, en vino.
SELECT pg_temp.afirmar(
  (SELECT precio FROM vino WHERE cod_vino = 910001) = 1000.00,
  'RN-01: el vino tiene un único precio');

-- Falla: precio cero. Esperado 23514 en ck_vino_precio_positivo.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE vino SET precio = 0 WHERE cod_vino = 910001 $sql$,
  '23514', 'ck_vino_precio_positivo');
\echo 'OK: RN-01'

-------------------------------------------------------------------------------
-- RN-02: una sala pertenece a una localidad con un único encargado regional.
-------------------------------------------------------------------------------
-- Funciona: el encargado se obtiene de la localidad de la sala.
SELECT pg_temp.afirmar(
  (SELECT l.encargado_regional
   FROM sala_venta AS s JOIN localidad AS l ON l.id_localidad = s.id_localidad
   WHERE s.id_sala = 910002) = 'Encargada RN',
  'RN-02: el encargado se lee de la localidad');

-- Falla: localidad inexistente. Esperado 23503 en fk_sala_venta_localidad.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
        VALUES ('Otra', '9', 'lunes', 999999) $sql$,
  '23503', 'fk_sala_venta_localidad');
\echo 'OK: RN-02'

-------------------------------------------------------------------------------
-- RN-03: cada empleado trabaja en una sola sala.
-------------------------------------------------------------------------------
-- Funciona.
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20910000001', 'Empleada RN', DATE '2019-03-01', 500000.00, 910001);

-- Falla: sin sala. Esperado 23502 (NOT NULL).
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
        VALUES ('20910000002', 'Sin sala', DATE '2020-01-01', 1.00, NULL) $sql$,
  '23502');

-- Falla: sala inexistente. Esperado 23503 en fk_empleado_sala_venta.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
        VALUES ('20910000003', 'Sala falsa', DATE '2020-01-01', 1.00, 999999) $sql$,
  '23503', 'fk_empleado_sala_venta');
\echo 'OK: RN-03'

-------------------------------------------------------------------------------
-- RN-04: una cepa por parcela; una cosecha por parcela y campaña.
-------------------------------------------------------------------------------
-- Funciona.
INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (910001, 910001, 1, 2025, DATE '2025-03-10', 8000.00, '30910000001');

-- Falla: segunda cosecha en la campaña. Esperado 23505 en uq_lote_uva_parcela_campania.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO lote_uva (nro_lote, id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
        VALUES (910002, 910001, 1, 2025, DATE '2025-04-01', 100.00, '30910000001') $sql$,
  '23505', 'uq_lote_uva_parcela_campania');

-- Falla: parcela sin cepa. Esperado 23502 (NOT NULL).
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa)
        VALUES (910001, 2, 1.00, 2015, NULL) $sql$,
  '23502');
\echo 'OK: RN-04'

-------------------------------------------------------------------------------
-- RN-05: la composición suma exactamente 100 (CONSTRAINT TRIGGER diferido).
-------------------------------------------------------------------------------
-- Funciona: dos INSERT con suma intermedia 60 y final 100.
SAVEPOINT rn05_ok;
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910010, 'Corte RN', 'tinto', 2024, 750, 13.00, 900.00, '30910000001');
INSERT INTO composicion_vino VALUES (910010, 910001, 60.00);
INSERT INTO composicion_vino VALUES (910010, 910002, 40.00);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
ROLLBACK TO SAVEPOINT rn05_ok;

-- Falla al cerrar: composición 90 %. Esperado P0001 'RN-05: ...'.
SAVEPOINT rn05_90;
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910011, 'Corte 90 RN', 'tinto', 2024, 750, 13.00, 900.00, '30910000001');
INSERT INTO composicion_vino VALUES (910011, 910001, 90.00);
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'RN-05: la composición del vino 910011 suma 90.00 %%');
ROLLBACK TO SAVEPOINT rn05_90;

-- Falla al cerrar: vino sin cepas. Esperado P0001 'RN-05: ... suma 0 %'.
SAVEPOINT rn05_vacio;
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910012, 'Sin cepas RN', 'tinto', 2024, 750, 13.00, 900.00, '30910000001');
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'RN-05: la composición del vino 910012 suma 0 %%');
ROLLBACK TO SAVEPOINT rn05_vacio;

-- Falla al cerrar: modificar un corte existente a 75 + 15.
SAVEPOINT rn05_update;
UPDATE composicion_vino SET porcentaje = 75.00 WHERE cod_vino = 910001 AND id_cepa = 910001;
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'RN-05: la composición del vino 910001 suma 90.00 %%');
ROLLBACK TO SAVEPOINT rn05_update;

-- Funciona: un vino creado y borrado en la misma transacción se ignora.
SAVEPOINT rn05_borrado;
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910013, 'Efímero RN', 'tinto', 2024, 750, 13.00, 900.00, '30910000001');
DELETE FROM vino WHERE cod_vino = 910013;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
ROLLBACK TO SAVEPOINT rn05_borrado;
\echo 'OK: RN-05'

-------------------------------------------------------------------------------
-- RN-06 y U6: descuento por tipo; excepción del 35 % con más de tres permisos.
-------------------------------------------------------------------------------
-- Funciona: 10 / 20 / 30 según tipo.
SELECT pg_temp.afirmar(
  fn_descuento_cliente(910001) = 10 AND fn_descuento_cliente(910002) = 20
  AND fn_descuento_cliente(910004) = 30,
  'RN-06: descuento base por tipo');

-- Falla: cliente inexistente. Esperado P0002.
SELECT pg_temp.esperar_error(
  'SELECT fn_descuento_cliente(999999)', 'P0002', NULL,
  'El cliente 999999 no existe.');

-- Falla: 35 % a un exportador con dos permisos. Esperado P0001 'RN-06: ...'.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = 910004 $sql$,
  'P0001', NULL, 'RN-06: la excepción del 35 % sólo corresponde%');

-- Falla: excepción distinta de 35. Esperado 23514 en ck_cliente_descuento_excepcion.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE cliente SET descuento_excepcion = 30 WHERE id_cliente = 910003 $sql$,
  '23514', 'ck_cliente_descuento_excepcion');

-- Funciona: exportador con cuatro permisos recibe la excepción.
UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = 910003;
SELECT pg_temp.afirmar(fn_descuento_cliente(910003) = 35, 'U6: excepción aplicada');

-- Falla al cerrar: quitar un permiso deja la excepción con tres. Esperado P0001.
SAVEPOINT u6_borra;
DELETE FROM permiso_exportacion WHERE codigo_permiso = 'RN-P4';
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'RN-06: el exportador 910003 conserva la excepción del 35 % con sólo 3 permiso(s).');
ROLLBACK TO SAVEPOINT u6_borra;

-- Funciona: quitar el permiso y la excepción en la misma transacción.
SAVEPOINT u6_ok;
DELETE FROM permiso_exportacion WHERE codigo_permiso = 'RN-P4';
UPDATE cliente SET descuento_excepcion = NULL WHERE id_cliente = 910003;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
ROLLBACK TO SAVEPOINT u6_ok;
\echo 'OK: RN-06 y U6'

-------------------------------------------------------------------------------
-- RN-07: varios permisos por exportador; vencimiento posterior a emisión.
-------------------------------------------------------------------------------
-- Funciona: el exportador tiene cuatro permisos.
SELECT pg_temp.afirmar(
  (SELECT count(*) FROM permiso_exportacion WHERE id_exportador = 910003) = 4,
  'RN-07: varios permisos por exportador');

-- Falla: vence el mismo día. Esperado 23514 en ck_permiso_exportacion_fechas.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO permiso_exportacion VALUES ('RN-PX', 910003, DATE '2026-05-01', DATE '2026-05-01') $sql$,
  '23514', 'ck_permiso_exportacion_fechas');
\echo 'OK: RN-07'

-------------------------------------------------------------------------------
-- RN-08 y RN-09: venta, importes calculados y stock de sala.
-------------------------------------------------------------------------------
-- Funciona: venta a un socio (10 %). Precio, descuento y subtotal enviados se
-- ignoran: los completa el trigger.
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910001, 910001, 910001);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad,
                                 precio_unitario, descuento_porcentaje, subtotal)
VALUES (910001, 910001, 2, 1.00, 0, 0);

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
VALUES (910001, 910002, 1);

SELECT pg_temp.afirmar(
  (SELECT (precio_unitario, descuento_porcentaje, subtotal) = (1000.00, 10.00, 1800.00)
   FROM renglon_comprobante WHERE nro_comprobante = 910001 AND cod_vino = 910001),
  'RN-08: renglón con precio vigente, descuento del cliente y subtotal neto');

SELECT pg_temp.afirmar(
  (SELECT (subtotal, descuento, total) = (4000.00, 400.00, 3600.00)
   FROM comprobante WHERE nro_comprobante = 910001),
  'RN-08: cabecera recalculada (bruto, descuento, neto)');

SELECT pg_temp.afirmar(
  fn_total_comprobante(910001) = 3600.00,
  'RN-08: fn_total_comprobante coincide con la cabecera');

SELECT pg_temp.afirmar(
  fn_stock_sala(910001, 910001) = 3 AND fn_stock_sala(910001, 910002) = 9,
  'RN-09: la venta descontó el stock de la sala');

SELECT pg_temp.afirmar(fn_stock_sala(910002, 910001) = 0, 'fn_stock_sala: 0 sin fila');

-- Funciona: venta a un exportador con excepción (35 %).
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910004, 910003, 910001);
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910004, 910002, 1);
SELECT pg_temp.afirmar(
  (SELECT (descuento_porcentaje, subtotal) = (35.00, 1300.00)
   FROM renglon_comprobante WHERE nro_comprobante = 910004),
  'RN-06: el renglón copia el descuento efectivo del cliente');

-- Funciona: recalcular deja los mismos importes.
SELECT fn_recalcular_comprobante(910001);
SELECT pg_temp.afirmar(
  (SELECT total FROM comprobante WHERE nro_comprobante = 910001) = 3600.00,
  'RN-08: recálculo idempotente');

-- Falla: importes cargados a mano. Esperado P0001 'RN-08: ...'.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO comprobante (id_cliente, id_sala, subtotal, descuento, total)
        VALUES (910001, 910001, 100, 0, 100) $sql$,
  'P0001', NULL, 'RN-08: los importes de un comprobante no se cargan a mano.');

-- Falla: modificar el total o la sala de un comprobante emitido.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE comprobante SET total = 0, subtotal = 0, descuento = 0 WHERE nro_comprobante = 910001 $sql$,
  'P0001', NULL, 'RN-08: un comprobante emitido no se modifica.');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE comprobante SET id_sala = 910002 WHERE nro_comprobante = 910001 $sql$,
  'P0001', NULL, 'RN-08: un comprobante emitido no se modifica.');

-- Falla: modificar o borrar un renglón suelto.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE renglon_comprobante SET cantidad = 1 WHERE nro_comprobante = 910001 AND cod_vino = 910001 $sql$,
  'P0001', NULL, 'RN-08: los renglones de un comprobante emitido no se modifican.');
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM renglon_comprobante WHERE nro_comprobante = 910001 AND cod_vino = 910001 $sql$,
  'P0001', NULL, 'RN-08: no se borran renglones sueltos de un comprobante.');

-- Falla al cerrar: comprobante sin renglones. Esperado P0001 'RN-08: ...'.
SAVEPOINT rn08_vacio;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910005, 910001, 910001);
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'RN-08: el comprobante 910005 no tiene renglones.');
ROLLBACK TO SAVEPOINT rn08_vacio;

-- Falla: venta sin stock suficiente. Esperado P0001 'RN-09: ...'. No deja
-- cambios: ni stock descontado ni importes en la cabecera.
SAVEPOINT rn09_sin_stock;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910002, 910001, 910001);
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910002, 910001, 50) $sql$,
  'P0001', NULL, 'RN-09: stock insuficiente del vino 910001 en la sala 910001.');
SELECT pg_temp.afirmar(
  fn_stock_sala(910001, 910001) = 3
  AND (SELECT total FROM comprobante WHERE nro_comprobante = 910002) = 0
  AND NOT EXISTS (SELECT 1 FROM renglon_comprobante WHERE nro_comprobante = 910002),
  'RN-09: la venta rechazada no dejó cambios');

-- Falla: la sala no tiene fila de stock para el vino.
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910003, 910001, 910002);
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910003, 910001, 1) $sql$,
  'P0001', NULL, 'RN-09: stock insuficiente del vino 910001 en la sala 910002.');
ROLLBACK TO SAVEPOINT rn09_sin_stock;

-- Falla: stock negativo. Esperado 23514 en ck_stock_sala_cantidad_no_negativa.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE stock_sala SET cantidad = -1 WHERE id_sala = 910001 AND cod_vino = 910001 $sql$,
  '23514', 'ck_stock_sala_cantidad_no_negativa');

-- Funciona: D1 borra el comprobante completo con sus renglones (cascada) y no
-- repone stock: es depuración histórica, no anulación.
DELETE FROM comprobante WHERE nro_comprobante = 910004;
SELECT pg_temp.afirmar(
  NOT EXISTS (SELECT 1 FROM renglon_comprobante WHERE nro_comprobante = 910004)
  AND fn_stock_sala(910001, 910002) = 8,
  'D1: renglones borrados en cascada; stock sin reponer');

-- Funciona: la transacción que crea la cabecera queda registrada aunque se
-- envíe otro valor, y los renglones de esa misma transacción se aceptan
-- (también dentro de un SAVEPOINT).
SAVEPOINT rn12_xact;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala, xact_alta)
OVERRIDING SYSTEM VALUE
VALUES (910007, 910001, 910001, '1');
SELECT pg_temp.afirmar(
  (SELECT xact_alta FROM comprobante WHERE nro_comprobante = 910007) = pg_current_xact_id(),
  'RN-12: xact_alta = transacción actual, ignorando el valor enviado');
ROLLBACK TO SAVEPOINT rn12_xact;

-- Falla: modificar xact_alta para "reabrir" un comprobante.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE comprobante SET xact_alta = '1' WHERE nro_comprobante = 910001 $sql$,
  'P0001', NULL, 'RN-08: un comprobante emitido no se modifica.');

-------------------------------------------------------------------------------
-- RN-08 / RN-09: fn_registrar_venta, único camino de venta de la API.
-------------------------------------------------------------------------------
-- Funciona: venta de tres renglones enviados en cualquier orden. Se revierte
-- al final para no alterar el stock que verifican las secciones siguientes.
SAVEPOINT venta_ok;
DO $$
DECLARE
  v_nro BIGINT;
  v_antes INTEGER[];
BEGIN
  v_antes := ARRAY[fn_stock_sala(910001, 910001), fn_stock_sala(910001, 910002),
                   fn_stock_sala(910001, 910003)];

  v_nro := fn_registrar_venta(910001, 910001,
                              ARRAY[910003, 910001, 910002]::BIGINT[],
                              ARRAY[1, 1, 2]);

  PERFORM pg_temp.afirmar(
    (SELECT count(*) FROM renglon_comprobante WHERE nro_comprobante = v_nro) = 3,
    'fn_registrar_venta: tres renglones');
  -- Socio 10 %: 1 x 500 + 1 x 1000 + 2 x 2000 = 5500 bruto.
  PERFORM pg_temp.afirmar(
    (SELECT (subtotal, descuento, total) = (5500.00, 550.00, 4950.00)
     FROM comprobante WHERE nro_comprobante = v_nro),
    'fn_registrar_venta: importes calculados por la base');
  PERFORM pg_temp.afirmar(
    ARRAY[fn_stock_sala(910001, 910001), fn_stock_sala(910001, 910002),
          fn_stock_sala(910001, 910003)]
    = ARRAY[v_antes[1] - 1, v_antes[2] - 2, v_antes[3] - 1],
    'fn_registrar_venta: stock descontado por renglón');
END;
$$;
ROLLBACK TO SAVEPOINT venta_ok;

-- Falla: un renglón sin stock. No queda ni la cabecera ni los renglones
-- anteriores, y el stock de los otros vinos no cambia.
DO $$
DECLARE
  v_comprobantes BIGINT;
  v_stock INTEGER;
BEGIN
  SELECT count(*) INTO v_comprobantes FROM comprobante;
  v_stock := fn_stock_sala(910001, 910001);

  PERFORM pg_temp.esperar_error(
    'SELECT fn_registrar_venta(910001, 910001, ARRAY[910001, 910002]::BIGINT[], ARRAY[1, 999])',
    'P0001', NULL, 'RN-09: stock insuficiente del vino 910002 en la sala 910001.');

  PERFORM pg_temp.afirmar(
    (SELECT count(*) FROM comprobante) = v_comprobantes
    AND fn_stock_sala(910001, 910001) = v_stock,
    'fn_registrar_venta: la venta rechazada no dejó cabecera, renglones ni stock descontado');
END;
$$;

-- Falla: validaciones de la entrada.
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_registrar_venta(910001, 910001, ARRAY[]::BIGINT[], ARRAY[]::INTEGER[]) $sql$,
  'P0001', NULL, 'RN-08: una venta debe tener al menos un renglón.');
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_registrar_venta(910001, 910001, ARRAY[910001, 910002]::BIGINT[], ARRAY[1]) $sql$,
  'P0001', NULL, 'RN-08: vinos y cantidades deben ser listas del mismo largo.');
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_registrar_venta(910001, 910001, ARRAY[910001]::BIGINT[], ARRAY[0]) $sql$,
  'P0001', NULL, 'RN-15: las cantidades vendidas deben ser positivas.');
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_registrar_venta(910001, 910001, ARRAY[910001, 910001]::BIGINT[], ARRAY[1, 1]) $sql$,
  'P0001', NULL, 'RN-08: un vino no puede repetirse en la misma venta.');
SELECT pg_temp.esperar_error(
  $sql$ SELECT fn_registrar_venta(910001, 910001, ARRAY[NULL]::BIGINT[], ARRAY[1]) $sql$,
  'P0001', NULL, 'RN-08: todos los renglones deben indicar un vino.');
\echo 'OK: RN-08 y RN-09 (incluida fn_registrar_venta)'

-------------------------------------------------------------------------------
-- RN-10: estados de ingreso e impacto único en el depósito.
-------------------------------------------------------------------------------
-- Funciona: el ingreso nace en confección.
INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910001, 910001, '30910000001'), (910002, 910001, '30910000001');
SELECT pg_temp.afirmar(
  (SELECT estado FROM ingreso WHERE cod_ingreso = 910001) = 'en_confeccion',
  'RN-10: estado inicial');

-- Falla: crear un ingreso ya terminado. Esperado P0001 'RN-10: ...'.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO ingreso (cod_transportista, cuit_bodega, estado)
        VALUES (910001, '30910000001', 'terminado') $sql$,
  'P0001', NULL, 'RN-10: el ingreso % se crea en estado en_confeccion.');

-- Falla: terminar sin renglones.
SELECT pg_temp.esperar_error(
  'CALL sp_terminar_ingreso(910001)', 'P0001', NULL,
  'RN-10: no se puede terminar el ingreso 910001 sin renglones.');

-- Funciona: con renglones se termina.
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (910001, 910001, 30), (910001, 910002, 20);
CALL sp_terminar_ingreso(910001);

-- Falla: retroceso terminado -> en_confeccion.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE ingreso SET estado = 'en_confeccion' WHERE cod_ingreso = 910001 $sql$,
  'P0001', NULL, 'RN-10: transición de estado inválida para el ingreso 910001: terminado -> en_confeccion.');

-- Falla: pasar a procesado sin el procedimiento.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = 910001 $sql$,
  'P0001', NULL, 'RN-10: el ingreso 910001 sólo pasa a procesado mediante su procedimiento.');

-- Falla: procesar un ingreso en confección.
SELECT pg_temp.esperar_error(
  'CALL sp_procesar_ingreso(910002)', 'P0001', NULL,
  'RN-10: el ingreso 910002 está en_confeccion;%');

-- Falla: procesar un ingreso inexistente. Esperado P0002.
SELECT pg_temp.esperar_error('CALL sp_procesar_ingreso(999999)', 'P0002');

-- Funciona: procesar suma al depósito (fila existente y fila nueva).
CALL sp_procesar_ingreso(910001);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 130
  AND (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910002) = 20
  AND (SELECT estado FROM ingreso WHERE cod_ingreso = 910001) = 'procesado',
  'RN-10: ingreso impactado y procesado');

-- Falla: procesar dos veces (impacto único).
SELECT pg_temp.esperar_error(
  'CALL sp_procesar_ingreso(910001)', 'P0001', NULL,
  'RN-10: el ingreso 910001 está procesado;%');
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 130,
  'RN-10: el segundo intento no volvió a sumar');
\echo 'OK: RN-10'

-------------------------------------------------------------------------------
-- RN-11: transferencias. Fecha actual inmutable, estados y stock suficiente.
-------------------------------------------------------------------------------
-- Funciona: la fecha enviada se ignora y queda la actual.
INSERT INTO transferencia (nro_transferencia, id_sala, fecha_confeccion)
OVERRIDING SYSTEM VALUE
VALUES (910001, 910002, DATE '2020-01-01');
SELECT pg_temp.afirmar(
  (SELECT fecha_confeccion FROM transferencia WHERE nro_transferencia = 910001) = CURRENT_DATE,
  'RN-11: fecha de confección = fecha actual');

-- Falla: cambiar la fecha.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1 WHERE nro_transferencia = 910001 $sql$,
  'P0001', NULL, 'RN-11: la fecha de confección de la transferencia 910001 no se modifica.');

-- Falla: salto en_confeccion -> procesado.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE transferencia SET estado = 'procesado' WHERE nro_transferencia = 910001 $sql$,
  'P0001', NULL, 'RN-11: transición de estado inválida para la transferencia 910001: en_confeccion -> procesado.');

-- Funciona: procesar mueve stock del depósito a la sala (crea filas nuevas).
INSERT INTO renglon_transferencia (nro_transferencia, cod_vino, cantidad)
VALUES (910001, 910001, 50), (910001, 910002, 5);
CALL sp_terminar_transferencia(910001);
CALL sp_procesar_transferencia(910001);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 80
  AND (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910002) = 15
  AND fn_stock_sala(910002, 910001) = 50
  AND fn_stock_sala(910002, 910002) = 5
  AND (SELECT estado FROM transferencia WHERE nro_transferencia = 910001) = 'procesado',
  'RN-11: transferencia impactada y procesada');

-- Falla: procesar dos veces.
SELECT pg_temp.esperar_error(
  'CALL sp_procesar_transferencia(910001)', 'P0001', NULL,
  'RN-11: la transferencia 910001 está procesado;%');

-- Falla: stock insuficiente en el depósito. No deja cambios.
INSERT INTO transferencia (nro_transferencia, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910002, 910001);
INSERT INTO renglon_transferencia VALUES (910002, 910001, 1000);
CALL sp_terminar_transferencia(910002);
SELECT pg_temp.esperar_error(
  'CALL sp_procesar_transferencia(910002)', 'P0001', NULL,
  'RN-11: el depósito no tiene stock suficiente para la transferencia 910002.');
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 80
  AND fn_stock_sala(910001, 910001) = 3
  AND (SELECT estado FROM transferencia WHERE nro_transferencia = 910002) = 'terminado',
  'RN-11: la transferencia sin stock no dejó cambios');

-- Falla: un vino sin fila en el depósito, junto con otro que sí alcanza.
-- Nada se mueve y el DETAIL nombra el vino faltante.
INSERT INTO transferencia (nro_transferencia, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910003, 910001);
INSERT INTO renglon_transferencia VALUES (910003, 910001, 1), (910003, 910003, 1);
CALL sp_terminar_transferencia(910003);
DO $$
DECLARE
  v_mensaje TEXT;
  v_detalle TEXT;
BEGIN
  CALL sp_procesar_transferencia(910003);
  RAISE EXCEPTION 'La transferencia sin fila en depósito debía fallar';
EXCEPTION WHEN raise_exception THEN
  GET STACKED DIAGNOSTICS v_mensaje = MESSAGE_TEXT, v_detalle = PG_EXCEPTION_DETAIL;
  IF v_mensaje NOT LIKE 'RN-11: el depósito no tiene stock suficiente%'
     OR v_detalle NOT LIKE '%vino 910003: pide 1, hay sin fila en el depósito%' THEN
    RAISE EXCEPTION 'Error inesperado: % / %', v_mensaje, v_detalle;
  END IF;
END;
$$;
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 80
  AND fn_stock_sala(910001, 910001) = 3
  AND NOT EXISTS (SELECT 1 FROM stock_deposito WHERE cod_vino = 910003),
  'RN-11: la transferencia con vino sin fila no dejó cambios');
\echo 'OK: RN-11'

-------------------------------------------------------------------------------
-- RN-12: renglones bloqueados fuera de confección; D5 sigue funcionando.
-------------------------------------------------------------------------------
-- Falla: agregar un renglón a un ingreso procesado.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (910001, 910003, 1) $sql$,
  'P0001', NULL, 'RN-12: el ingreso 910001 está procesado; no admite cambios en sus renglones.');

-- Falla: modificar un renglón de una transferencia terminada.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE renglon_transferencia SET cantidad = 1 WHERE nro_transferencia = 910002 $sql$,
  'P0001', NULL, 'RN-12: la transferencia 910002 está terminado;%');

-- Falla: quitar un renglón de un ingreso procesado.
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM renglon_ingreso WHERE cod_ingreso = 910001 AND cod_vino = 910001 $sql$,
  'P0001', NULL, 'RN-12: el ingreso 910001 está procesado;%');

-- Funciona: en confección se agrega, modifica y quita.
INSERT INTO renglon_ingreso VALUES (910002, 910001, 10);
UPDATE renglon_ingreso SET cantidad = 12 WHERE cod_ingreso = 910002 AND cod_vino = 910001;
DELETE FROM renglon_ingreso WHERE cod_ingreso = 910002 AND cod_vino = 910001;

-- Funciona: D5 borra un ingreso procesado y sus renglones en cascada, sin
-- tocar el stock ya impactado.
DELETE FROM ingreso WHERE cod_ingreso = 910001;
SELECT pg_temp.afirmar(
  NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE cod_ingreso = 910001)
  AND (SELECT cantidad FROM stock_deposito WHERE cod_vino = 910001) = 80,
  'D5: ingreso procesado borrado con sus renglones; stock intacto');
\echo 'OK: RN-12 y D5'

-------------------------------------------------------------------------------
-- RN-13: auditoría de precio.
-------------------------------------------------------------------------------
-- Funciona: cambio de precio auditado con el usuario de la sesión.
UPDATE vino SET precio = 1100.00 WHERE cod_vino = 910001;
SELECT pg_temp.afirmar(
  (SELECT (precio_anterior, precio_nuevo, usuario_bd) = (1000.00, 1100.00, session_user::TEXT)
   FROM auditoria_precio WHERE cod_vino = 910001),
  'RN-13: auditoría con precios y usuario');

-- Funciona: otros cambios o el mismo precio no generan auditoría.
UPDATE vino SET graduacion = 14.10 WHERE cod_vino = 910001;
UPDATE vino SET precio = 1100.00 WHERE cod_vino = 910001;
SELECT pg_temp.afirmar(
  (SELECT count(*) FROM auditoria_precio WHERE cod_vino = 910001) = 1,
  'RN-13: sólo los cambios reales de precio se auditan');

-- Funciona: la venta pasada conserva su precio histórico.
SELECT pg_temp.afirmar(
  (SELECT precio_unitario FROM renglon_comprobante
   WHERE nro_comprobante = 910001 AND cod_vino = 910001) = 1000.00,
  'RN-08: el renglón conserva el precio del momento de la venta');

-- Falla: auditoría con precios iguales. Esperado 23514 en ck_auditoria_precio_valores.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo)
        VALUES (910001, 10, 10) $sql$,
  '23514', 'ck_auditoria_precio_valores');
\echo 'OK: RN-13'

-------------------------------------------------------------------------------
-- RN-14: no se borran transportista, bodega ni vino con movimientos.
-------------------------------------------------------------------------------
-- Falla: bodega con vinos y movimientos. Esperado 23503.
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM bodega WHERE cuit = '30910000001' $sql$,
  '23503', NULL, '%table "bodega"%');

-- Falla: vino vendido. Esperado 23503.
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM vino WHERE cod_vino = 910001 $sql$,
  '23503', NULL, '%table "vino"%');

-- Falla: transportista con ingresos. Esperado 23503 en fk_ingreso_transportista.
SELECT pg_temp.esperar_error(
  $sql$ DELETE FROM transportista WHERE cod_transportista = 910001 $sql$,
  '23503', 'fk_ingreso_transportista');

-- Funciona: un vino sin movimientos se borra con su composición.
SAVEPOINT rn14_ok;
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (910020, 'Sin movimientos RN', 'blanco', 2024, 750, 12.00, 800.00, '30910000001');
INSERT INTO composicion_vino VALUES (910020, 910001, 100.00);
DELETE FROM vino WHERE cod_vino = 910020;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
ROLLBACK TO SAVEPOINT rn14_ok;
\echo 'OK: RN-14'

-------------------------------------------------------------------------------
-- RN-15: cantidades, superficies, kilos y precios positivos; graduación 5..20.
-------------------------------------------------------------------------------
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (910002, 910002, 0) $sql$,
  '23514', 'ck_renglon_ingreso_cantidad_positiva');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE finca SET superficie_ha = 0 WHERE id_finca = 910001 $sql$,
  '23514', 'ck_finca_superficie_positiva');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE lote_uva SET kilos = 0 WHERE nro_lote = 910001 $sql$,
  '23514', 'ck_lote_uva_kilos_positivos');
SELECT pg_temp.esperar_error(
  $sql$ UPDATE vino SET graduacion = 20.50 WHERE cod_vino = 910002 $sql$,
  '23514', 'ck_vino_graduacion');
SAVEPOINT rn15_venta;
INSERT INTO comprobante (nro_comprobante, id_cliente, id_sala)
OVERRIDING SYSTEM VALUE
VALUES (910006, 910001, 910001);
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (910006, 910001, 0) $sql$,
  '23514', 'ck_renglon_comprobante_cantidad_positiva');
ROLLBACK TO SAVEPOINT rn15_venta;

-- Funciona: graduación en el límite.
UPDATE vino SET graduacion = 20.00 WHERE cod_vino = 910002;
\echo 'OK: RN-15'

-------------------------------------------------------------------------------
-- Totalidad de la jerarquía de clientes (CONSTRAINT TRIGGER diferido).
-------------------------------------------------------------------------------
-- Falla al cerrar: cliente sin fila de subtipo.
SAVEPOINT total_sin;
INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento,
                     direccion, id_localidad, tipo)
OVERRIDING SYSTEM VALUE
VALUES (910010, 'Sin subtipo RN', 'DNI', '91000010', 'Dir', 910001, 'socio');
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'Jerarquía de clientes: el cliente 910010 es de tipo socio y no tiene su fila de subtipo.');
ROLLBACK TO SAVEPOINT total_sin;

-- Falla al cerrar: quitar el subtipo y dejar el cliente.
SAVEPOINT total_borra;
DELETE FROM distribuidor WHERE id_cliente = 910002;
SELECT pg_temp.esperar_error(
  'SET CONSTRAINTS ALL IMMEDIATE', 'P0001', NULL,
  'Jerarquía de clientes: el cliente 910002 es de tipo distribuidor%');
ROLLBACK TO SAVEPOINT total_borra;

-- Funciona: cambio de tipo en una transacción.
SAVEPOINT total_cambio;
DELETE FROM socio_club WHERE id_cliente = 910001;
UPDATE cliente SET tipo = 'distribuidor' WHERE id_cliente = 910001;
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
VALUES (910001, 'Norte RN', 'HAB-RN-2');
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.afirmar(fn_descuento_cliente(910001) = 20, 'cambio de tipo aplicado');
ROLLBACK TO SAVEPOINT total_cambio;
\echo 'OK: totalidad de la jerarquía de clientes'

-------------------------------------------------------------------------------
-- Funciones: volatilidad declarada y fn_antiguedad_anios.
-------------------------------------------------------------------------------
SELECT pg_temp.afirmar(
  (SELECT string_agg(proname || '=' || provolatile::TEXT, ',' ORDER BY proname)
   FROM pg_proc
   WHERE pronamespace = 'bodegas'::regnamespace
     AND proname IN ('fn_descuento_cliente', 'fn_stock_sala',
                     'fn_total_comprobante', 'fn_antiguedad_anios',
                     'fn_recalcular_comprobante'))
  = 'fn_antiguedad_anios=i,fn_descuento_cliente=s,fn_recalcular_comprobante=v,fn_stock_sala=s,fn_total_comprobante=s',
  'volatilidad declarada de las funciones');

SELECT pg_temp.afirmar(
  fn_antiguedad_anios(DATE '2020-06-01', DATE '2026-05-31') = 5
  AND fn_antiguedad_anios(DATE '2020-06-01', DATE '2026-06-01') = 6
  AND fn_antiguedad_anios(CURRENT_DATE - 1) = 0,
  'fn_antiguedad_anios: años completos');

-- Falla: un índice no puede depender del DEFAULT CURRENT_DATE. Esperado 42P17.
CREATE TEMP TABLE t_antiguedad (ingreso DATE);
SELECT pg_temp.esperar_error(
  'CREATE INDEX ON t_antiguedad (bodegas.fn_antiguedad_anios(ingreso))',
  '42P17', NULL, 'functions in index expression must be marked IMMUTABLE');
\echo 'OK: funciones'

-- El estado final completo cumple las reglas diferidas.
SET CONSTRAINTS ALL IMMEDIATE;
\echo 'OK: el estado final cumple todas las reglas diferidas.'

ROLLBACK;
\echo 'OK: los datos de prueba fueron revertidos.'
