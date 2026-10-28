\set ON_ERROR_STOP on
\pset pager off

-- Operaciones nuevas sobre la base cargada, por el camino normal
-- (fn_registrar_venta, sp_terminar_*, sp_procesar_*), con los triggers otra
-- vez activos. Demuestra que la carga histórica no dejó las reglas apagadas.
-- Ejecutar como propietario después de la carga. Termina en ROLLBACK: las
-- operaciones nuevas tendrían la fecha real y romperían la reproducibilidad.

SET search_path TO bodegas, pg_catalog;
BEGIN;
\ir ../tests/ayudantes.sql
-- Sólo se muestran los \echo y los errores.
\o /dev/null

-- Datos elegidos de la base cargada.
SELECT array_agg(cod_vino ORDER BY cod_vino) AS vinos_sala1
FROM (SELECT cod_vino FROM stock_sala WHERE id_sala = 1 AND cantidad >= 2
      ORDER BY cantidad DESC, cod_vino LIMIT 3) AS x
\gset
SELECT min(id_cliente) AS cliente FROM cliente WHERE tipo = 'socio' \gset
SELECT min(nro_comprobante) AS comprobante_cargado FROM comprobante \gset
SELECT d.cod_vino AS vino_deposito, d.cantidad AS stock_deposito, v.cuit_bodega AS bodega
FROM stock_deposito AS d JOIN vino AS v USING (cod_vino)
WHERE d.cantidad >= 10 ORDER BY d.cantidad DESC, d.cod_vino LIMIT 1
\gset
SELECT min(cod_ingreso) AS ingreso_procesado FROM ingreso WHERE estado = 'procesado' \gset

-- Funciona: venta nueva de tres vinos con fn_registrar_venta.
SELECT fn_registrar_venta(:cliente, 1, :'vinos_sala1'::BIGINT[], ARRAY[1, 1, 1]) AS venta_nueva \gset
SELECT pg_temp.afirmar(
  (SELECT count(*) FROM renglon_comprobante WHERE nro_comprobante = :venta_nueva) = 3
  AND (SELECT total FROM comprobante WHERE nro_comprobante = :venta_nueva) = fn_total_comprobante(:venta_nueva)
  AND (SELECT total FROM comprobante WHERE nro_comprobante = :venta_nueva) > 0,
  'venta nueva con importes calculados por la base');
\echo 'OK: venta nueva con fn_registrar_venta sobre la base cargada.'

-- Falla: venta sin stock (RN-09) y no deja cambios.
SELECT pg_temp.esperar_error(
  format('SELECT fn_registrar_venta(%s, 1, ARRAY[%s]::BIGINT[], ARRAY[1000000])', :cliente, (:'vinos_sala1'::BIGINT[])[1]),
  'P0001', NULL, 'RN-09: stock insuficiente%');
\echo 'OK: RN-09 rechaza una venta sin stock.'

-- Falla: agregar un renglón a un comprobante cargado (RN-12), aun como propietario.
SELECT pg_temp.esperar_error(
  format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 1)',
         :comprobante_cargado, :vino_deposito),
  'P0001', NULL, 'RN-12: el comprobante % ya fue emitido%');
\echo 'OK: RN-12 rechaza renglones nuevos en un comprobante cargado.'

-- Falla: volver a procesar un ingreso histórico (RN-10).
SELECT pg_temp.esperar_error(
  format('CALL sp_procesar_ingreso(%s)', :ingreso_procesado),
  'P0001', NULL, 'RN-10: el ingreso % está procesado;%');
SELECT pg_temp.esperar_error(
  format('INSERT INTO renglon_ingreso VALUES (%s, %s, 1)', :ingreso_procesado, :vino_deposito),
  'P0001', NULL, 'RN-12: el ingreso % está procesado;%');
\echo 'OK: RN-10 y RN-12 protegen los ingresos cargados.'

-- Funciona: ingreso nuevo de la bodega del vino, terminado y procesado.
INSERT INTO ingreso (cod_transportista, cuit_bodega) VALUES (1, :'bodega')
RETURNING cod_ingreso AS ingreso_nuevo \gset
INSERT INTO renglon_ingreso VALUES (:ingreso_nuevo, :vino_deposito, 120);
CALL sp_terminar_ingreso(:ingreso_nuevo);
CALL sp_procesar_ingreso(:ingreso_nuevo);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino_deposito) = :stock_deposito + 120,
  'ingreso nuevo procesado suma al depósito');
\echo 'OK: ingreso nuevo con sp_terminar_ingreso y sp_procesar_ingreso.'

-- Funciona: transferencia nueva a la sala 1.
INSERT INTO transferencia (id_sala) VALUES (1) RETURNING nro_transferencia AS transferencia_nueva \gset
INSERT INTO renglon_transferencia VALUES (:transferencia_nueva, :vino_deposito, 10);
CALL sp_terminar_transferencia(:transferencia_nueva);
CALL sp_procesar_transferencia(:transferencia_nueva);
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino_deposito) = :stock_deposito + 110
  AND (SELECT fecha_confeccion FROM transferencia WHERE nro_transferencia = :transferencia_nueva) = CURRENT_DATE,
  'transferencia nueva procesada, con la fecha actual forzada');
\echo 'OK: transferencia nueva con sp_terminar_transferencia y sp_procesar_transferencia.'

-- Falla: transferencia sin stock suficiente (RN-11) y no deja cambios.
INSERT INTO transferencia (id_sala) VALUES (1) RETURNING nro_transferencia AS transferencia_grande \gset
INSERT INTO renglon_transferencia VALUES (:transferencia_grande, :vino_deposito, 10000000);
CALL sp_terminar_transferencia(:transferencia_grande);
SELECT pg_temp.esperar_error(
  format('CALL sp_procesar_transferencia(%s)', :transferencia_grande),
  'P0001', NULL, 'RN-11: el depósito no tiene stock suficiente%');
SELECT pg_temp.afirmar(
  (SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino_deposito) = :stock_deposito + 110,
  'la transferencia rechazada no cambió el depósito');
\echo 'OK: RN-11 rechaza una transferencia sin stock sin dejar cambios.'

-- Funciona: un cambio de precio queda auditado por el trigger (RN-13).
UPDATE vino SET precio = precio + 10 WHERE cod_vino = :vino_deposito;
SELECT pg_temp.afirmar(
  EXISTS (SELECT 1 FROM auditoria_precio WHERE cod_vino = :vino_deposito AND usuario_bd = session_user),
  'cambio de precio auditado');
\echo 'OK: RN-13 audita un cambio de precio nuevo.'

-- Las reglas diferidas se cumplen sobre todo lo anterior.
SET CONSTRAINTS ALL IMMEDIATE;
\echo 'OK: reglas diferidas verificadas.'

ROLLBACK;
\echo 'OK: operaciones de verificación revertidas; la base cargada no cambió.'
