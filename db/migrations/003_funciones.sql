-- Bodegas del Atuel - funciones reutilizables (Etapa 2)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Convenciones de esta etapa:
-- - Toda rutina fija su search_path para no depender de la sesión que la
--   invoque (y, en las SECURITY DEFINER, para que nadie pueda sustituir
--   tablas u operadores con objetos propios en otro esquema).
-- - PostgreSQL ignora la precisión (p,s) en el tipo de retorno: se declara
--   NUMERIC y los valores se producen ya redondeados a dos decimales.
-- - "No existe" se informa con SQLSTATE P0002 (no_data_found); una regla de
--   negocio violada, con P0001 y un mensaje que empieza por "RN-XX:".

SET search_path TO bodegas, pg_catalog;

-- fn_descuento_cliente
-- Propósito: porcentaje de descuento efectivo de un cliente (RN-06, U6):
--   la excepción individual si existe; si no, la base de su tipo
--   (socio 10, distribuidor 20, exportador 30).
-- Parámetros: p_id_cliente, cliente a consultar.
-- Volatilidad: STABLE. Lee tablas: el resultado no cambia dentro de una
--   sentencia, pero sí entre sentencias si cambia el cliente.
-- Errores: P0002 si el cliente no existe.
CREATE FUNCTION fn_descuento_cliente(p_id_cliente BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_tipo tipo_cliente;
  v_excepcion NUMERIC(5,2);
BEGIN
  SELECT tipo, descuento_excepcion
  INTO v_tipo, v_excepcion
  FROM cliente
  WHERE id_cliente = p_id_cliente;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente % no existe.', p_id_cliente
      USING ERRCODE = 'P0002',
            HINT = 'Verifique el identificador del cliente.';
  END IF;

  RETURN COALESCE(
    v_excepcion,
    CASE v_tipo
      WHEN 'socio' THEN 10.00
      WHEN 'distribuidor' THEN 20.00
      WHEN 'exportador' THEN 30.00
    END
  );
END;
$$;

COMMENT ON FUNCTION fn_descuento_cliente(BIGINT) IS
  'RN-06/U6: descuento efectivo (excepción o 10/20/30 según tipo). STABLE. P0002 si el cliente no existe.';

-- fn_stock_sala
-- Propósito: botellas disponibles de un vino en una sala (RN-09).
-- Parámetros: p_id_sala, sala; p_cod_vino, vino.
-- Volatilidad: STABLE. Lee stock_sala.
-- Resultado: 0 si la sala no tiene fila para ese vino; no distingue "sin
--   fila" de "cantidad cero" porque para vender ambos significan no hay stock.
CREATE FUNCTION fn_stock_sala(p_id_sala INTEGER, p_cod_vino BIGINT)
RETURNS INTEGER
LANGUAGE sql
STABLE
SET search_path = bodegas, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT cantidad
     FROM stock_sala
     WHERE id_sala = p_id_sala
       AND cod_vino = p_cod_vino),
    0
  );
$$;

COMMENT ON FUNCTION fn_stock_sala(INTEGER, BIGINT) IS
  'RN-09: stock de un vino en una sala; 0 si no hay fila. STABLE.';

-- fn_total_comprobante
-- Propósito: total neto de un comprobante como suma de los subtotales netos
--   de sus renglones (RN-08). Es la definición de "total" del modelo.
-- Parámetros: p_nro_comprobante, comprobante a calcular.
-- Volatilidad: STABLE. Lee comprobante y renglon_comprobante.
-- Errores: P0002 si el comprobante no existe; 0 si todavía no tiene renglones.
CREATE FUNCTION fn_total_comprobante(p_nro_comprobante BIGINT)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SET search_path = bodegas, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM comprobante WHERE nro_comprobante = p_nro_comprobante
  ) THEN
    RAISE EXCEPTION 'El comprobante % no existe.', p_nro_comprobante
      USING ERRCODE = 'P0002';
  END IF;

  RETURN (
    SELECT COALESCE(SUM(subtotal), 0)
    FROM renglon_comprobante
    WHERE nro_comprobante = p_nro_comprobante
  );
END;
$$;

COMMENT ON FUNCTION fn_total_comprobante(BIGINT) IS
  'RN-08: suma de subtotales netos de los renglones. STABLE. P0002 si el comprobante no existe.';

-- fn_antiguedad_anios
-- Propósito: años completos transcurridos desde una fecha de ingreso hasta
--   una fecha de referencia (U2, D3).
-- Parámetros: p_fecha_ingreso; p_fecha_ref, por omisión CURRENT_DATE.
-- Volatilidad: IMMUTABLE. El cuerpo depende sólo de sus argumentos
--   (age(date, date) es inmutable). El DEFAULT CURRENT_DATE no lo contradice:
--   PostgreSQL reemplaza el valor por omisión en la llamada, antes de invocar
--   la función, así que fn_antiguedad_anios(x) se planifica como
--   fn_antiguedad_anios(x, CURRENT_DATE) y no se precalcula como constante.
--   Por la misma razón un índice sobre fn_antiguedad_anios(columna) es
--   rechazado. Sería incorrecto, en cambio, usar CURRENT_DATE dentro del cuerpo
--   de una función IMMUTABLE.
CREATE FUNCTION fn_antiguedad_anios(
  p_fecha_ingreso DATE,
  p_fecha_ref DATE DEFAULT CURRENT_DATE
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
SET search_path = bodegas, pg_temp
AS $$
  SELECT EXTRACT(YEAR FROM age(p_fecha_ref, p_fecha_ingreso))::INTEGER;
$$;

COMMENT ON FUNCTION fn_antiguedad_anios(DATE, DATE) IS
  'Años completos entre ingreso y referencia (por omisión hoy). IMMUTABLE: el DEFAULT se evalúa en la llamada.';

-- fn_recalcular_comprobante
-- Propósito: único camino para escribir los importes de un comprobante
--   (RN-08). Calcula subtotal bruto, descuento monetario y total neto desde
--   los renglones, de modo que total = subtotal - descuento. La usan el
--   trigger AFTER INSERT de renglones y la consulta U1 de la Etapa 5.
-- Parámetros: p_nro_comprobante, comprobante a recalcular.
-- Volatilidad: VOLATILE. Modifica datos.
-- Mecanismo: activa la marca de transacción bodegas.recalculo_importes que
--   trg_comprobante_importes exige para aceptar el UPDATE, y la apaga al
--   terminar. Si el UPDATE falla, la subtransacción revierte también la marca.
--   La marca protege contra errores de quien tiene UPDATE (el propietario);
--   el límite de seguridad para la API es no tener UPDATE sobre comprobante.
-- Errores: P0002 si el comprobante no existe.
CREATE FUNCTION fn_recalcular_comprobante(p_nro_comprobante BIGINT)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_bruto NUMERIC(14,2);
  v_neto NUMERIC(14,2);
BEGIN
  v_neto := fn_total_comprobante(p_nro_comprobante);

  SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
  INTO v_bruto
  FROM renglon_comprobante
  WHERE nro_comprobante = p_nro_comprobante;

  PERFORM set_config('bodegas.recalculo_importes', 'on', true);

  UPDATE comprobante
  SET subtotal = v_bruto,
      descuento = v_bruto - v_neto,
      total = v_neto
  WHERE nro_comprobante = p_nro_comprobante;

  PERFORM set_config('bodegas.recalculo_importes', 'off', true);
END;
$$;

COMMENT ON FUNCTION fn_recalcular_comprobante(BIGINT) IS
  'RN-08: recalcula subtotal bruto, descuento y total desde los renglones. Único camino de escritura de importes.';
