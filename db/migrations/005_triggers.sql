-- Bodegas del Atuel - triggers de reglas de negocio (Etapa 2)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Errores de negocio: RAISE EXCEPTION con SQLSTATE P0001 y mensaje que
-- empieza por la regla ("RN-09: ..."), más DETAIL/HINT cuando ayudan.
--
-- SECURITY DEFINER sólo donde hace falta: funciones que escriben tablas sobre
-- las que la API no tiene privilegios (stock, importes, auditoría) o que
-- bloquean filas con FOR UPDATE / FOR SHARE (PostgreSQL exige UPDATE sobre la
-- tabla para bloquear). Todas fijan search_path. El resto se ejecuta con los
-- privilegios de quien dispara el trigger.

SET search_path TO bodegas, pg_catalog;

-------------------------------------------------------------------------------
-- RN-08 / RN-09: venta. BEFORE INSERT en renglon_comprobante.
-- Completa precio, descuento y subtotal (la API no puede imponerlos) y
-- rechaza la venta si la sala no tiene stock suficiente.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_renglon_comprobante_completar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_id_sala INTEGER;
  v_id_cliente BIGINT;
  v_stock INTEGER;
BEGIN
  -- Bloquear la cabecera serializa los renglones de un mismo comprobante:
  -- así el recálculo de importes de una sesión no pisa el de otra.
  SELECT id_sala, id_cliente
  INTO v_id_sala, v_id_cliente
  FROM comprobante
  WHERE nro_comprobante = NEW.nro_comprobante
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NEW; -- la FK informará que el comprobante no existe
  END IF;

  -- Precio vigente y descuento del cliente: se ignora lo que se haya enviado.
  SELECT precio INTO NEW.precio_unitario FROM vino WHERE cod_vino = NEW.cod_vino;
  IF NOT FOUND THEN
    RETURN NEW; -- la FK informará que el vino no existe
  END IF;

  NEW.descuento_porcentaje := fn_descuento_cliente(v_id_cliente);
  NEW.subtotal := ROUND(
    NEW.cantidad * NEW.precio_unitario * (1 - NEW.descuento_porcentaje / 100),
    2
  );

  -- FOR UPDATE: otra venta del mismo vino en la misma sala espera a que esta
  -- termine y después ve el stock ya descontado (ver docs/concurrencia.md).
  SELECT cantidad
  INTO v_stock
  FROM stock_sala
  WHERE id_sala = v_id_sala
    AND cod_vino = NEW.cod_vino
  FOR UPDATE;

  IF NOT FOUND OR v_stock < NEW.cantidad THEN
    RAISE EXCEPTION 'RN-09: stock insuficiente del vino % en la sala %.',
      NEW.cod_vino, v_id_sala
      USING ERRCODE = 'P0001',
            DETAIL = format('Se piden %s botellas y la sala tiene %s.',
                            NEW.cantidad, COALESCE(v_stock, 0)),
            HINT = 'Solicite una transferencia desde el depósito central.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_completar
BEFORE INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_comprobante_completar();

-------------------------------------------------------------------------------
-- RN-08 / RN-09: venta. AFTER INSERT en renglon_comprobante.
-- Descuenta el stock de la sala y recalcula los importes de la cabecera.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_renglon_comprobante_impactar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  UPDATE stock_sala AS s
  SET cantidad = s.cantidad - NEW.cantidad
  FROM comprobante AS c
  WHERE c.nro_comprobante = NEW.nro_comprobante
    AND s.id_sala = c.id_sala
    AND s.cod_vino = NEW.cod_vino;

  PERFORM fn_recalcular_comprobante(NEW.nro_comprobante);
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_impactar
AFTER INSERT ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_comprobante_impactar();

-------------------------------------------------------------------------------
-- RN-08: un renglón vendido es histórico. BEFORE UPDATE OR DELETE.
-- No se modifica nunca. Sólo se borra junto con su comprobante (D1): en ese
-- borrado en cascada la cabecera ya no es visible para el trigger.
-- Borrar historia no repone stock (supuesto 14 de docs/requisitos.md).
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_renglon_comprobante_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'RN-08: los renglones de un comprobante emitido no se modifican.'
      USING ERRCODE = 'P0001',
            DETAIL = format('Comprobante %s, vino %s.', OLD.nro_comprobante, OLD.cod_vino),
            HINT = 'Precio y descuento quedan congelados al vender.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM comprobante WHERE nro_comprobante = OLD.nro_comprobante
  ) THEN
    RAISE EXCEPTION 'RN-08: no se borran renglones sueltos de un comprobante.'
      USING ERRCODE = 'P0001',
            DETAIL = format('Comprobante %s, vino %s.', OLD.nro_comprobante, OLD.cod_vino),
            HINT = 'Sólo se elimina el comprobante completo, que arrastra sus renglones.';
  END IF;

  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_inmutable
BEFORE UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_comprobante_inmutable();

-------------------------------------------------------------------------------
-- RN-08: los importes del comprobante no se cargan a mano.
-- BEFORE INSERT OR UPDATE en comprobante. Al insertar, los importes deben ser
-- 0 (los completa el recálculo). Un comprobante emitido no se modifica; sólo
-- fn_recalcular_comprobante puede escribir sus importes, porque activa la
-- marca bodegas.recalculo_importes. Se eligió la marca y no pg_trigger_depth()
-- porque U1 recalcula fuera de un trigger y quedaría bloqueado.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_comprobante_importes()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.subtotal <> 0 OR NEW.descuento <> 0 OR NEW.total <> 0 THEN
      RAISE EXCEPTION 'RN-08: los importes de un comprobante no se cargan a mano.'
        USING ERRCODE = 'P0001',
              HINT = 'Inserte la cabecera sin importes y luego sus renglones: el total se calcula solo.';
    END IF;
    RETURN NEW;
  END IF;

  IF current_setting('bodegas.recalculo_importes', true) = 'on'
     AND (NEW.nro_comprobante, NEW.fecha, NEW.id_cliente, NEW.id_sala)
         IS NOT DISTINCT FROM
         (OLD.nro_comprobante, OLD.fecha, OLD.id_cliente, OLD.id_sala) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'RN-08: un comprobante emitido no se modifica.'
    USING ERRCODE = 'P0001',
          DETAIL = format('Comprobante %s.', OLD.nro_comprobante),
          HINT = 'Los importes sólo los recalcula fn_recalcular_comprobante.';
END;
$$;

CREATE TRIGGER trg_comprobante_importes
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_comprobante_importes();

-------------------------------------------------------------------------------
-- RN-08: todo comprobante tiene al menos un renglón.
-- CONSTRAINT TRIGGER diferido: la cabecera y sus renglones se insertan en una
-- misma transacción y la regla se comprueba al confirmarla.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_comprobante_con_renglones()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM comprobante WHERE nro_comprobante = NEW.nro_comprobante
  ) AND NOT EXISTS (
    SELECT 1 FROM renglon_comprobante WHERE nro_comprobante = NEW.nro_comprobante
  ) THEN
    RAISE EXCEPTION 'RN-08: el comprobante % no tiene renglones.', NEW.nro_comprobante
      USING ERRCODE = 'P0001',
            HINT = 'Inserte la cabecera y sus renglones en la misma transacción.';
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ctrg_comprobante_con_renglones
AFTER INSERT ON comprobante
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_comprobante_con_renglones();

-------------------------------------------------------------------------------
-- RN-10 / RN-11: transiciones de estado de ingresos y transferencias.
-- Un documento nace en_confeccion y avanza en_confeccion -> terminado ->
-- procesado, sin retrocesos ni saltos. Para terminar necesita renglones.
-- 'procesado' sólo desde sp_procesar_*, que activan la marca
-- bodegas.procesando_documento (ver 004_procedimientos.sql).
-------------------------------------------------------------------------------
CREATE FUNCTION fn_validar_transicion_estado(
  p_regla TEXT,
  p_documento TEXT,
  p_anterior estado_documento,
  p_nuevo estado_documento,
  p_tiene_renglones BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
-- STABLE: no modifica datos; sólo lee la marca de la transacción.
STABLE
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF p_anterior IS NULL THEN
    IF p_nuevo <> 'en_confeccion' THEN
      RAISE EXCEPTION '%: % se crea en estado en_confeccion.', p_regla, p_documento
        USING ERRCODE = 'P0001',
              DETAIL = format('Estado recibido: %s.', p_nuevo);
    END IF;
    RETURN;
  END IF;

  IF p_anterior = p_nuevo THEN
    RETURN;
  END IF;

  IF p_anterior = 'en_confeccion' AND p_nuevo = 'terminado' THEN
    IF NOT p_tiene_renglones THEN
      RAISE EXCEPTION '%: no se puede terminar % sin renglones.', p_regla, p_documento
        USING ERRCODE = 'P0001',
              HINT = 'Agregue al menos un renglón mientras está en confección.';
    END IF;
    RETURN;
  END IF;

  IF p_anterior = 'terminado' AND p_nuevo = 'procesado' THEN
    IF current_setting('bodegas.procesando_documento', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION '%: % sólo pasa a procesado mediante su procedimiento.', p_regla, p_documento
        USING ERRCODE = 'P0001',
              HINT = 'Use sp_procesar_ingreso o sp_procesar_transferencia: impactan el stock y cambian el estado juntos.';
    END IF;
    RETURN;
  END IF;

  RAISE EXCEPTION '%: transición de estado inválida para %: % -> %.',
    p_regla, p_documento, p_anterior, p_nuevo
    USING ERRCODE = 'P0001',
          DETAIL = 'Sólo se permite en_confeccion -> terminado -> procesado, sin retrocesos ni saltos.';
END;
$$;

CREATE FUNCTION fn_trg_ingreso_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  PERFORM fn_validar_transicion_estado(
    'RN-10',
    format('el ingreso %s', NEW.cod_ingreso),
    CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado END,
    NEW.estado,
    EXISTS (SELECT 1 FROM renglon_ingreso WHERE cod_ingreso = NEW.cod_ingreso)
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE INSERT OR UPDATE OF estado ON ingreso
FOR EACH ROW EXECUTE FUNCTION fn_trg_ingreso_estado();

CREATE FUNCTION fn_trg_transferencia_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  PERFORM fn_validar_transicion_estado(
    'RN-11',
    format('la transferencia %s', NEW.nro_transferencia),
    CASE WHEN TG_OP = 'UPDATE' THEN OLD.estado END,
    NEW.estado,
    EXISTS (
      SELECT 1 FROM renglon_transferencia
      WHERE nro_transferencia = NEW.nro_transferencia
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE OF estado ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_transferencia_estado();

-------------------------------------------------------------------------------
-- RN-12: un ingreso o una transferencia que no está en confección no admite
-- agregar, modificar ni quitar renglones. BEFORE INSERT/UPDATE/DELETE.
-- Bloquea la cabecera FOR SHARE: nadie puede terminarla mientras se edita un
-- renglón. Si la cabecera ya no existe en un DELETE, es el borrado en cascada
-- de un documento completo (D5) y se permite.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_renglon_ingreso_bloqueo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_cod BIGINT;
  v_estado estado_documento;
BEGIN
  FOREACH v_cod IN ARRAY CASE TG_OP
      WHEN 'INSERT' THEN ARRAY[NEW.cod_ingreso]
      WHEN 'DELETE' THEN ARRAY[OLD.cod_ingreso]
      ELSE ARRAY[OLD.cod_ingreso, NEW.cod_ingreso]
    END
  LOOP
    SELECT estado INTO v_estado
    FROM ingreso
    WHERE cod_ingreso = v_cod
    FOR SHARE;

    -- Sin cabecera: en INSERT/UPDATE la FK lo informará; en DELETE es cascada.
    CONTINUE WHEN NOT FOUND;

    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'RN-12: el ingreso % está %; no admite cambios en sus renglones.',
        v_cod, v_estado
        USING ERRCODE = 'P0001',
              HINT = 'Sólo se editan los renglones de un documento en confección.';
    END IF;
  END LOOP;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_ingreso_bloqueo();

CREATE FUNCTION fn_trg_renglon_transferencia_bloqueo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_nro BIGINT;
  v_estado estado_documento;
BEGIN
  FOREACH v_nro IN ARRAY CASE TG_OP
      WHEN 'INSERT' THEN ARRAY[NEW.nro_transferencia]
      WHEN 'DELETE' THEN ARRAY[OLD.nro_transferencia]
      ELSE ARRAY[OLD.nro_transferencia, NEW.nro_transferencia]
    END
  LOOP
    SELECT estado INTO v_estado
    FROM transferencia
    WHERE nro_transferencia = v_nro
    FOR SHARE;

    CONTINUE WHEN NOT FOUND;

    IF v_estado <> 'en_confeccion' THEN
      RAISE EXCEPTION 'RN-12: la transferencia % está %; no admite cambios en sus renglones.',
        v_nro, v_estado
        USING ERRCODE = 'P0001',
              HINT = 'Sólo se editan los renglones de un documento en confección.';
    END IF;
  END LOOP;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_transferencia_bloqueo();

-------------------------------------------------------------------------------
-- RN-11: la fecha de confección de una transferencia es la actual y no se
-- modifica. BEFORE INSERT fuerza CURRENT_DATE (ignora el valor enviado);
-- BEFORE UPDATE rechaza cualquier cambio. Va en un trigger y no en un CHECK
-- porque depende de la fecha actual.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_transferencia_fecha()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_confeccion := CURRENT_DATE;
  ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
    RAISE EXCEPTION 'RN-11: la fecha de confección de la transferencia % no se modifica.',
      OLD.nro_transferencia
      USING ERRCODE = 'P0001',
            DETAIL = format('Fecha registrada: %s.', OLD.fecha_confeccion);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_transferencia_fecha();

-------------------------------------------------------------------------------
-- RN-13: todo cambio de precio queda auditado. AFTER UPDATE OF precio.
-- Registra session_user: la cuenta que abrió la conexión. Dentro de una
-- función SECURITY DEFINER, current_user (y el DEFAULT CURRENT_USER de la
-- columna) devolvería siempre al propietario. Con la API, el registro dirá la
-- cuenta de la API: la base no conoce al usuario final mientras no exista
-- autenticación.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_vino_auditoria_precio()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  INSERT INTO auditoria_precio (
    cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario_bd
  ) VALUES (
    NEW.cod_vino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, session_user
  );
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio
AFTER UPDATE OF precio ON vino
FOR EACH ROW
WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION fn_trg_vino_auditoria_precio();

-------------------------------------------------------------------------------
-- RN-05: la composición de cada vino suma exactamente 100 y tiene al menos
-- una cepa. CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED: dentro de la
-- transacción la suma puede pasar por estados intermedios (85 + 15 se cargan
-- en dos INSERT); se comprueba al confirmar. Dispara en composicion_vino y en
-- el alta de vino. Un vino borrado en la misma transacción se ignora.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_composicion_vino_100()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_vinos BIGINT[];
  v_cod BIGINT;
  v_cepas INTEGER;
  v_suma NUMERIC;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_vinos := ARRAY[NEW.cod_vino];
  ELSIF TG_OP = 'DELETE' THEN
    v_vinos := ARRAY[OLD.cod_vino];
  ELSE
    v_vinos := ARRAY[OLD.cod_vino, NEW.cod_vino];
  END IF;

  FOREACH v_cod IN ARRAY v_vinos LOOP
    SELECT count(c.id_cepa), COALESCE(SUM(c.porcentaje), 0)
    INTO v_cepas, v_suma
    FROM vino AS v
    LEFT JOIN composicion_vino AS c ON c.cod_vino = v.cod_vino
    WHERE v.cod_vino = v_cod
    GROUP BY v.cod_vino;

    CONTINUE WHEN NOT FOUND; -- vino borrado en la misma transacción

    IF v_cepas = 0 OR v_suma <> 100 THEN
      RAISE EXCEPTION 'RN-05: la composición del vino % suma % %%; debe sumar exactamente 100 %%.',
        v_cod, v_suma
        USING ERRCODE = 'P0001',
              DETAIL = format('Cepas cargadas: %s.', v_cepas),
              HINT = 'Ajuste los porcentajes de corte antes de confirmar la transacción.';
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ctrg_composicion_vino_suma
AFTER INSERT OR UPDATE OR DELETE ON composicion_vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_composicion_vino_100();

CREATE CONSTRAINT TRIGGER ctrg_vino_composicion
AFTER INSERT ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_composicion_vino_100();

-------------------------------------------------------------------------------
-- Totalidad de la jerarquía de clientes: todo cliente tiene la fila del
-- subtipo que corresponde a su tipo. La exclusividad ya la garantizan las FK
-- compuestas de 001; una FK no puede exigir que exista el hijo, por eso esta
-- parte es un CONSTRAINT TRIGGER diferido. Permite cambiar de tipo en una
-- transacción: borrar el subtipo viejo, actualizar tipo, insertar el nuevo.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_cliente_subtipo_total()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_id BIGINT;
  v_tipo tipo_cliente;
  v_tiene BOOLEAN;
BEGIN
  IF TG_TABLE_NAME = 'cliente' THEN
    v_id := NEW.id_cliente;
  ELSE
    v_id := OLD.id_cliente;
  END IF;

  SELECT tipo INTO v_tipo FROM cliente WHERE id_cliente = v_id;
  IF NOT FOUND THEN
    RETURN NULL; -- cliente borrado: su subtipo se fue en cascada
  END IF;

  v_tiene := CASE v_tipo
    WHEN 'socio' THEN EXISTS (SELECT 1 FROM socio_club WHERE id_cliente = v_id)
    WHEN 'distribuidor' THEN EXISTS (SELECT 1 FROM distribuidor WHERE id_cliente = v_id)
    WHEN 'exportador' THEN EXISTS (SELECT 1 FROM exportador WHERE id_cliente = v_id)
  END;

  IF NOT v_tiene THEN
    RAISE EXCEPTION 'Jerarquía de clientes: el cliente % es de tipo % y no tiene su fila de subtipo.',
      v_id, v_tipo
      USING ERRCODE = 'P0001',
            HINT = 'Inserte el cliente y su subtipo (socio_club, distribuidor o exportador) en la misma transacción.';
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ctrg_cliente_subtipo
AFTER INSERT OR UPDATE OF tipo ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_cliente_subtipo_total();

CREATE CONSTRAINT TRIGGER ctrg_socio_club_total
AFTER DELETE OR UPDATE ON socio_club
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_cliente_subtipo_total();

CREATE CONSTRAINT TRIGGER ctrg_distribuidor_total
AFTER DELETE OR UPDATE ON distribuidor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_cliente_subtipo_total();

CREATE CONSTRAINT TRIGGER ctrg_exportador_total
AFTER DELETE OR UPDATE ON exportador
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_cliente_subtipo_total();

-------------------------------------------------------------------------------
-- RN-06 / U6: la excepción del 35 % sólo corresponde a un exportador con más
-- de tres permisos (se cuentan todos sus permisos, como dice U6).
-- Al asignarla se valida en el momento (BEFORE). Si después se quita o se
-- reasigna un permiso y la excepción queda sin respaldo, la transacción se
-- rechaza al confirmar, salvo que en ella también se quite la excepción.
-------------------------------------------------------------------------------
CREATE FUNCTION fn_trg_cliente_excepcion()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_permisos INTEGER;
BEGIN
  SELECT count(*) INTO v_permisos
  FROM permiso_exportacion
  WHERE id_exportador = NEW.id_cliente;

  IF v_permisos <= 3 THEN
    RAISE EXCEPTION 'RN-06: la excepción del 35 %% sólo corresponde a exportadores con más de tres permisos.'
      USING ERRCODE = 'P0001',
            DETAIL = format('El cliente %s tiene %s permiso(s).', NEW.id_cliente, v_permisos),
            HINT = 'Sin excepción se aplica el descuento base del tipo de cliente.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cliente_excepcion
BEFORE INSERT OR UPDATE OF descuento_excepcion ON cliente
FOR EACH ROW
WHEN (NEW.descuento_excepcion IS NOT NULL)
EXECUTE FUNCTION fn_trg_cliente_excepcion();

CREATE FUNCTION fn_trg_permiso_excepcion()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_permisos INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cliente
    WHERE id_cliente = OLD.id_exportador
      AND descuento_excepcion IS NOT NULL
  ) THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_permisos
  FROM permiso_exportacion
  WHERE id_exportador = OLD.id_exportador;

  IF v_permisos <= 3 THEN
    RAISE EXCEPTION 'RN-06: el exportador % conserva la excepción del 35 %% con sólo % permiso(s).',
      OLD.id_exportador, v_permisos
      USING ERRCODE = 'P0001',
            HINT = 'Quite la excepción (descuento_excepcion = NULL) en la misma transacción o conserve más de tres permisos.';
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ctrg_permiso_excepcion
AFTER DELETE OR UPDATE OF id_exportador ON permiso_exportacion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_permiso_excepcion();

-------------------------------------------------------------------------------
-- Privilegios y documentación de las funciones de trigger.
-- Una función de trigger no puede llamarse directamente y PostgreSQL no
-- verifica EXECUTE al dispararla; igual se revoca PUBLIC para que ninguna
-- quede expuesta por omisión.
-------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  fn_trg_renglon_comprobante_completar(),
  fn_trg_renglon_comprobante_impactar(),
  fn_trg_renglon_comprobante_inmutable(),
  fn_trg_comprobante_importes(),
  fn_trg_comprobante_con_renglones(),
  fn_validar_transicion_estado(TEXT, TEXT, estado_documento, estado_documento, BOOLEAN),
  fn_trg_ingreso_estado(),
  fn_trg_transferencia_estado(),
  fn_trg_renglon_ingreso_bloqueo(),
  fn_trg_renglon_transferencia_bloqueo(),
  fn_trg_transferencia_fecha(),
  fn_trg_vino_auditoria_precio(),
  fn_trg_composicion_vino_100(),
  fn_trg_cliente_subtipo_total(),
  fn_trg_cliente_excepcion(),
  fn_trg_permiso_excepcion()
FROM PUBLIC;

COMMENT ON TRIGGER trg_renglon_comprobante_completar ON renglon_comprobante IS
  'RN-08/RN-09: completa precio, descuento y subtotal; rechaza sin stock (bloquea la fila FOR UPDATE).';
COMMENT ON TRIGGER trg_renglon_comprobante_impactar ON renglon_comprobante IS
  'RN-08/RN-09: descuenta stock de la sala y recalcula los importes de la cabecera.';
COMMENT ON TRIGGER trg_renglon_comprobante_inmutable ON renglon_comprobante IS
  'RN-08: renglón vendido no se modifica; sólo se borra con su comprobante.';
COMMENT ON TRIGGER trg_comprobante_importes ON comprobante IS
  'RN-08: importes no se cargan a mano; el comprobante emitido no se modifica.';
COMMENT ON TRIGGER ctrg_comprobante_con_renglones ON comprobante IS
  'RN-08: al confirmar, todo comprobante tiene al menos un renglón. Diferido.';
COMMENT ON TRIGGER trg_ingreso_estado ON ingreso IS
  'RN-10: alta en confección y transiciones sin retroceso; procesado sólo por procedimiento.';
COMMENT ON TRIGGER trg_transferencia_estado ON transferencia IS
  'RN-11: alta en confección y transiciones sin retroceso; procesado sólo por procedimiento.';
COMMENT ON TRIGGER trg_renglon_ingreso_bloqueo ON renglon_ingreso IS
  'RN-12: renglones editables sólo con el ingreso en confección; permite la cascada de D5.';
COMMENT ON TRIGGER trg_renglon_transferencia_bloqueo ON renglon_transferencia IS
  'RN-12: renglones editables sólo con la transferencia en confección.';
COMMENT ON TRIGGER trg_transferencia_fecha ON transferencia IS
  'RN-11: fecha de confección = fecha actual al crear; inmutable después.';
COMMENT ON TRIGGER trg_vino_auditoria_precio ON vino IS
  'RN-13: registra precio anterior, nuevo, instante y session_user.';
COMMENT ON TRIGGER ctrg_composicion_vino_suma ON composicion_vino IS
  'RN-05: al confirmar, la composición suma 100 y tiene al menos una cepa. Diferido.';
COMMENT ON TRIGGER ctrg_vino_composicion ON vino IS
  'RN-05: un vino nuevo debe tener composición válida al confirmar. Diferido.';
COMMENT ON TRIGGER ctrg_cliente_subtipo ON cliente IS
  'Totalidad de la jerarquía: el cliente tiene la fila de su subtipo al confirmar. Diferido.';
COMMENT ON TRIGGER ctrg_socio_club_total ON socio_club IS
  'Totalidad de la jerarquía al quitar o mover un socio. Diferido.';
COMMENT ON TRIGGER ctrg_distribuidor_total ON distribuidor IS
  'Totalidad de la jerarquía al quitar o mover un distribuidor. Diferido.';
COMMENT ON TRIGGER ctrg_exportador_total ON exportador IS
  'Totalidad de la jerarquía al quitar o mover un exportador. Diferido.';
COMMENT ON TRIGGER trg_cliente_excepcion ON cliente IS
  'RN-06/U6: la excepción del 35 % exige más de tres permisos.';
COMMENT ON TRIGGER ctrg_permiso_excepcion ON permiso_exportacion IS
  'RN-06/U6: quitar permisos no puede dejar una excepción sin respaldo. Diferido.';
