-- Bodegas del Atuel - procedimientos de ingresos y transferencias (Etapa 2)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Los procedimientos no hacen COMMIT. Un CALL se ejecuta dentro de la
-- transacción de quien lo invoca: si algo falla, no queda ningún cambio a
-- medias, y la API puede llamarlos dentro de su propia transacción.
--
-- Son SECURITY DEFINER (se ejecutan con los privilegios del propietario)
-- porque cambian estados y stocks sobre los que la API no tiene UPDATE. Así
-- la única forma que tiene la API de mover stock es este camino validado.
-- Fijan search_path para que nadie sustituya objetos con otros de su esquema.
--
-- 'procesado' exige la marca bodegas.procesando_documento, que verifica
-- trg_ingreso_estado / trg_transferencia_estado. La marca evita que el
-- propietario marque un documento como procesado con un UPDATE directo sin
-- impactar stock; no es un límite de seguridad, porque cualquier rol puede
-- fijar una variable propia. El límite para la API es no tener UPDATE sobre
-- ingreso ni transferencia.

SET search_path TO bodegas, pg_catalog;

-- sp_terminar_ingreso
-- Propósito: pasar un ingreso de en_confeccion a terminado (RN-10). El
--   trigger de estados valida la transición y que tenga renglones.
-- Parámetros: p_cod_ingreso.
-- Errores: P0002 si no existe; P0001 (RN-10) si la transición no es válida.
CREATE PROCEDURE sp_terminar_ingreso(p_cod_ingreso BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  UPDATE ingreso
  SET estado = 'terminado'
  WHERE cod_ingreso = p_cod_ingreso;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El ingreso % no existe.', p_cod_ingreso
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- sp_procesar_ingreso
-- Propósito: impactar un ingreso terminado en el stock del depósito central y
--   pasarlo a procesado (RN-10). Impacto único: un ingreso procesado no vuelve
--   a procesarse.
-- Parámetros: p_cod_ingreso.
-- Pasos: bloquea la cabecera FOR UPDATE (dos llamadas simultáneas se
--   serializan y la segunda ve 'procesado'), exige terminado y renglones, suma
--   cada renglón al depósito creando la fila si no existe y cambia el estado.
-- Errores: P0002 si no existe; P0001 (RN-10) si no está terminado.
CREATE PROCEDURE sp_procesar_ingreso(p_cod_ingreso BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_estado estado_documento;
BEGIN
  SELECT estado
  INTO v_estado
  FROM ingreso
  WHERE cod_ingreso = p_cod_ingreso
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El ingreso % no existe.', p_cod_ingreso
      USING ERRCODE = 'P0002';
  END IF;

  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION 'RN-10: el ingreso % está %; sólo un ingreso terminado impacta en el depósito.',
      p_cod_ingreso, v_estado
      USING ERRCODE = 'P0001',
            HINT = CASE v_estado
              WHEN 'procesado' THEN 'El ingreso ya fue procesado: su stock ya está en el depósito.'
              ELSE 'Termine el ingreso con sp_terminar_ingreso antes de procesarlo.'
            END;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM renglon_ingreso WHERE cod_ingreso = p_cod_ingreso
  ) THEN
    RAISE EXCEPTION 'RN-10: el ingreso % no tiene renglones.', p_cod_ingreso
      USING ERRCODE = 'P0001';
  END IF;

  -- Orden por vino: dos procesos concurrentes toman las filas del depósito en
  -- el mismo orden y no se bloquean en cruz.
  INSERT INTO stock_deposito (cod_vino, cantidad)
  SELECT cod_vino, cantidad
  FROM renglon_ingreso
  WHERE cod_ingreso = p_cod_ingreso
  ORDER BY cod_vino
  ON CONFLICT (cod_vino)
  DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

  PERFORM set_config('bodegas.procesando_documento', 'on', true);
  UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod_ingreso;
  PERFORM set_config('bodegas.procesando_documento', 'off', true);
END;
$$;

-- sp_terminar_transferencia
-- Propósito: pasar una transferencia de en_confeccion a terminado (RN-11).
-- Parámetros: p_nro_transferencia.
-- Errores: P0002 si no existe; P0001 (RN-11) si la transición no es válida.
CREATE PROCEDURE sp_terminar_transferencia(p_nro_transferencia BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  UPDATE transferencia
  SET estado = 'terminado'
  WHERE nro_transferencia = p_nro_transferencia;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La transferencia % no existe.', p_nro_transferencia
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- sp_procesar_transferencia
-- Propósito: mover del depósito central a la sala las botellas de una
--   transferencia terminada y pasarla a procesado (RN-11). No procesa si el
--   depósito no tiene stock suficiente.
-- Parámetros: p_nro_transferencia.
-- Pasos:
--   1. bloquea la cabecera FOR UPDATE y exige terminado;
--   2. bloquea las filas del depósito involucradas en orden de cod_vino, para
--      que dos transferencias concurrentes no se bloqueen en cruz;
--   3. verifica que, para CADA renglón, exista la fila del depósito y alcance.
--      Un UPDATE ... FROM sin esta verificación no descontaría nada para un
--      vino sin fila y no daría error (el caso señalado en el Anexo A.6);
--   4. descuenta del depósito, suma a la sala (creando la fila si no existe)
--      y cambia el estado.
-- Errores: P0002 si no existe; P0001 (RN-11) si no está terminada o falta
--   stock, con el detalle de cada vino faltante.
CREATE PROCEDURE sp_procesar_transferencia(p_nro_transferencia BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_estado estado_documento;
  v_id_sala INTEGER;
  v_faltantes TEXT;
BEGIN
  SELECT estado, id_sala
  INTO v_estado, v_id_sala
  FROM transferencia
  WHERE nro_transferencia = p_nro_transferencia
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La transferencia % no existe.', p_nro_transferencia
      USING ERRCODE = 'P0002';
  END IF;

  IF v_estado <> 'terminado' THEN
    RAISE EXCEPTION 'RN-11: la transferencia % está %; sólo una transferencia terminada impacta en el stock.',
      p_nro_transferencia, v_estado
      USING ERRCODE = 'P0001',
            HINT = CASE v_estado
              WHEN 'procesado' THEN 'La transferencia ya fue procesada.'
              ELSE 'Termine la transferencia con sp_terminar_transferencia antes de procesarla.'
            END;
  END IF;

  PERFORM 1
  FROM stock_deposito
  WHERE cod_vino IN (
    SELECT cod_vino
    FROM renglon_transferencia
    WHERE nro_transferencia = p_nro_transferencia
  )
  ORDER BY cod_vino
  FOR UPDATE;

  SELECT string_agg(
           format('vino %s: pide %s, hay %s',
                  r.cod_vino, r.cantidad,
                  COALESCE(d.cantidad::TEXT, 'sin fila en el depósito')),
           '; ' ORDER BY r.cod_vino)
  INTO v_faltantes
  FROM renglon_transferencia AS r
  LEFT JOIN stock_deposito AS d ON d.cod_vino = r.cod_vino
  WHERE r.nro_transferencia = p_nro_transferencia
    AND (d.cod_vino IS NULL OR d.cantidad < r.cantidad);

  IF v_faltantes IS NOT NULL THEN
    RAISE EXCEPTION 'RN-11: el depósito no tiene stock suficiente para la transferencia %.',
      p_nro_transferencia
      USING ERRCODE = 'P0001',
            DETAIL = v_faltantes,
            HINT = 'Procese ingresos de esos vinos o reduzca las cantidades antes de terminar la transferencia.';
  END IF;

  UPDATE stock_deposito AS d
  SET cantidad = d.cantidad - r.cantidad
  FROM renglon_transferencia AS r
  WHERE r.nro_transferencia = p_nro_transferencia
    AND d.cod_vino = r.cod_vino;

  INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
  SELECT v_id_sala, cod_vino, cantidad
  FROM renglon_transferencia
  WHERE nro_transferencia = p_nro_transferencia
  ORDER BY cod_vino
  ON CONFLICT (id_sala, cod_vino)
  DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

  PERFORM set_config('bodegas.procesando_documento', 'on', true);
  UPDATE transferencia
  SET estado = 'procesado'
  WHERE nro_transferencia = p_nro_transferencia;
  PERFORM set_config('bodegas.procesando_documento', 'off', true);
END;
$$;

REVOKE ALL ON PROCEDURE
  sp_terminar_ingreso(BIGINT),
  sp_procesar_ingreso(BIGINT),
  sp_terminar_transferencia(BIGINT),
  sp_procesar_transferencia(BIGINT)
FROM PUBLIC;

COMMENT ON PROCEDURE sp_terminar_ingreso(BIGINT) IS
  'RN-10: en_confeccion -> terminado. SECURITY DEFINER; el trigger de estados valida la transición.';
COMMENT ON PROCEDURE sp_procesar_ingreso(BIGINT) IS
  'RN-10: suma un ingreso terminado al depósito y lo pasa a procesado. Impacto único. Sin COMMIT interno.';
COMMENT ON PROCEDURE sp_terminar_transferencia(BIGINT) IS
  'RN-11: en_confeccion -> terminado. SECURITY DEFINER; el trigger de estados valida la transición.';
COMMENT ON PROCEDURE sp_procesar_transferencia(BIGINT) IS
  'RN-11: mueve stock del depósito a la sala si alcanza para cada renglón y la pasa a procesado. Sin COMMIT interno.';
