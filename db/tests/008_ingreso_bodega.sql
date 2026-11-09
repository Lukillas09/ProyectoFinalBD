\set ON_ERROR_STOP on
\pset pager off

-- RN-16 (009_ingreso_bodega.sql): un ingreso sólo admite vinos de su bodega
-- de origen. Ejecutar como propietario. Todo vive en una transacción que
-- termina en ROLLBACK.

SET search_path TO bodegas, pg_catalog;
BEGIN;
\ir ayudantes.sql

-------------------------------------------------------------------------------
-- Datos base: dos bodegas con un vino cada una y un transportista.
-------------------------------------------------------------------------------
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30930000001', 'Bodega Origen B', 'Dom B'),
       ('30930000002', 'Bodega Ajena B', 'Dom B');

INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (930001, 'Vino Origen B', 'tinto', 2022, 750, 13.50, 1000.00, '30930000001'),
       (930002, 'Otro Origen B', 'blanco', 2023, 750, 12.50, 900.00, '30930000001'),
       (930003, 'Vino Ajeno B', 'tinto', 2022, 750, 13.50, 1000.00, '30930000002');

INSERT INTO transportista (cod_transportista, razon_social, cuit, email, telefono, domicilio)
OVERRIDING SYSTEM VALUE
VALUES (930001, 'Transporte B', '30930000003', 'b@example.invalid', '2604000003', 'Dom B');

INSERT INTO ingreso (cod_ingreso, cod_transportista, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (930001, 930001, '30930000001');

-------------------------------------------------------------------------------
-- RN-16
-------------------------------------------------------------------------------
-- Funciona: vinos de la bodega del ingreso.
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
VALUES (930001, 930001, 10), (930001, 930002, 5);

-- Falla: vino de otra bodega. Esperado P0001 'RN-16: ...'.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (930001, 930003, 1) $sql$,
  'P0001', NULL,
  'RN-16: el vino 930003 es de la bodega 30930000002; el ingreso 930001 es de la bodega 30930000001.');

-- Falla: cambiar el vino de un renglón por uno de otra bodega.
SELECT pg_temp.esperar_error(
  $sql$ UPDATE renglon_ingreso SET cod_vino = 930003 WHERE cod_ingreso = 930001 AND cod_vino = 930002 $sql$,
  'P0001', NULL, 'RN-16: el vino 930003 es de la bodega 30930000002;%');

-- Funciona: cambiar sólo la cantidad no vuelve a verificar la bodega.
UPDATE renglon_ingreso SET cantidad = 12 WHERE cod_ingreso = 930001 AND cod_vino = 930001;

-- Falla: cabecera y renglón en una sola sentencia (la forma de la consulta
-- I6). El trigger ve la cabecera que acaba de insertar el CTE.
SELECT pg_temp.esperar_error(
  $sql$ WITH nuevo AS (
          INSERT INTO ingreso (cod_transportista, cuit_bodega)
          VALUES (930001, '30930000001') RETURNING cod_ingreso)
        INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
        SELECT cod_ingreso, 930003, 120 FROM nuevo $sql$,
  'P0001', NULL, 'RN-16: el vino 930003 es de la bodega 30930000002;%');

-- Funciona: la misma sentencia con un vino de la bodega del ingreso.
WITH nuevo AS (
  INSERT INTO ingreso (cod_transportista, cuit_bodega)
  VALUES (930001, '30930000002') RETURNING cod_ingreso)
INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT cod_ingreso, 930003, 120 FROM nuevo;

-- Falla con 23503, no con RN-16: ingreso o vino inexistente los informa la FK.
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (939999, 930001, 1) $sql$,
  '23503', 'fk_renglon_ingreso_ingreso');
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (930001, 939999, 1) $sql$,
  '23503', 'fk_renglon_ingreso_vino');

-- Falla con RN-12 primero: un ingreso terminado no admite renglones, aunque
-- el vino además sea de otra bodega (trg_renglon_ingreso_bloqueo se dispara
-- antes que trg_renglon_ingreso_bodega).
CALL sp_terminar_ingreso(930001);
SELECT pg_temp.esperar_error(
  $sql$ INSERT INTO renglon_ingreso VALUES (930001, 930003, 1) $sql$,
  'P0001', NULL, 'RN-12: el ingreso 930001 está terminado;%');

\echo 'OK: RN-16'

ROLLBACK;
\echo 'OK: los datos de prueba fueron revertidos.'
