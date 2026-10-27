\set ON_ERROR_STOP on
\pset pager off

-- RN-12 extendida a comprobantes: una venta confirmada no admite renglones
-- nuevos, aun para el propietario (no depende de privilegios).
-- Ejecutar como propietario. A diferencia de las otras pruebas, necesita un
-- comprobante confirmado en una transacción anterior, así que usa varias
-- transacciones:
--   1. limpia restos de una ejecución interrumpida;
--   2. confirma datos de prueba y una venta;
--   3. verifica, en otra transacción que termina en ROLLBACK;
--   4. borra los datos de prueba.
-- Si falla en el paso 3, los datos quedan hasta la próxima ejecución, que los
-- borra en el paso 1.

SET search_path TO bodegas, pg_catalog;

-- 1 y 4 usan el mismo bloque de limpieza. El borrado del comprobante es el de
-- D1 (arrastra sus renglones); el vino se borra con su composición.
\set limpieza 'DELETE FROM comprobante WHERE id_sala = 930001; DELETE FROM stock_sala WHERE id_sala = 930001; DELETE FROM vino WHERE cod_vino IN (930001, 930002); DELETE FROM cliente WHERE id_cliente = 930001; DELETE FROM sala_venta WHERE id_sala = 930001; DELETE FROM localidad WHERE id_localidad = 930001; DELETE FROM bodega WHERE cuit = ''30930000001''; DELETE FROM cepa WHERE id_cepa = 930001;'

BEGIN;
:limpieza
COMMIT;

-- 2. Datos de prueba y una venta confirmada.
BEGIN;
INSERT INTO localidad (id_localidad, codigo_postal, nombre, provincia, encargado_regional)
OVERRIDING SYSTEM VALUE VALUES (930001, '5600-E', 'Localidad E', 'Mendoza E', 'Encargado E');
INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE VALUES (930001, 'Calle E', '1', 'lunes', 930001);
INSERT INTO bodega (cuit, razon_social, domicilio) VALUES ('30930000001', 'Bodega E', 'Dom E');
INSERT INTO cepa (id_cepa, nombre, tipo) OVERRIDING SYSTEM VALUE VALUES (930001, 'Cepa E', 'tinta');
INSERT INTO vino (cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
OVERRIDING SYSTEM VALUE
VALUES (930001, 'Vino E', 'tinto', 2023, 750, 13.00, 1000.00, '30930000001'),
       (930002, 'Otro vino E', 'tinto', 2023, 750, 13.00, 1500.00, '30930000001');
INSERT INTO composicion_vino VALUES (930001, 930001, 100.00), (930002, 930001, 100.00);
INSERT INTO cliente (id_cliente, nombre_razon_social, tipo_documento, nro_documento,
                     direccion, id_localidad, tipo)
OVERRIDING SYSTEM VALUE VALUES (930001, 'Socio E', 'DNI', '93000001', 'Dir', 930001, 'socio');
INSERT INTO socio_club VALUES (930001);
INSERT INTO stock_sala VALUES (930001, 930001, 10), (930001, 930002, 10);
SELECT fn_registrar_venta(930001, 930001, ARRAY[930001]::BIGINT[], ARRAY[2]) AS nro_emitido \gset
COMMIT;
\echo 'OK: venta confirmada en una transacción anterior.'

-- 3. Verificación en una transacción nueva.
BEGIN;
\ir ayudantes.sql

-- Falla: agregar un renglón al comprobante emitido, como propietario. Se usa
-- otro vino con stock: sin la protección, el renglón sería aceptado.
-- Esperado P0001 'RN-12: ... ya fue emitido ...'.
SELECT pg_temp.esperar_error(
  format($sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
               VALUES (%s, 930002, 1) $sql$, :nro_emitido),
  'P0001', NULL, 'RN-12: el comprobante % ya fue emitido; no admite renglones nuevos.');

-- Falla: "reabrirlo" cambiando xact_alta. Esperado P0001 'RN-08: ...'.
SELECT pg_temp.esperar_error(
  format($sql$ UPDATE comprobante SET xact_alta = pg_current_xact_id()
               WHERE nro_comprobante = %s $sql$, :nro_emitido),
  'P0001', NULL, 'RN-08: un comprobante emitido no se modifica.');

-- Funciona: el recálculo de U1 sobre un comprobante viejo.
SELECT fn_recalcular_comprobante(:nro_emitido);
SELECT pg_temp.afirmar(
  (SELECT (subtotal, descuento, total) = (2000.00, 200.00, 1800.00)
   FROM comprobante WHERE nro_comprobante = :nro_emitido),
  'U1: fn_recalcular_comprobante funciona sobre un comprobante emitido');

-- Después del recálculo sigue cerrado: xact_alta no cambió.
SELECT pg_temp.esperar_error(
  format($sql$ INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
               VALUES (%s, 930002, 1) $sql$, :nro_emitido),
  'P0001', NULL, 'RN-12: el comprobante % ya fue emitido%');

SELECT pg_temp.afirmar(
  fn_stock_sala(930001, 930001) = 8 AND fn_stock_sala(930001, 930002) = 10,
  'RN-12: los intentos rechazados no descontaron stock');
ROLLBACK;
\echo 'OK: un comprobante emitido no admite renglones nuevos, aun como propietario; U1 sigue funcionando.'

-- 4. Limpieza.
BEGIN;
:limpieza
COMMIT;
\echo 'OK: datos de prueba eliminados.'
