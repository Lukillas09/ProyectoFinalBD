-- Ayudantes compartidos por las pruebas. Se incluyen con \ir dentro de una
-- transacción; viven en pg_temp y desaparecen al cerrar la sesión.

-- Ejecuta p_sql y exige que falle con el SQLSTATE indicado. Opcionalmente
-- exige el nombre de la constraint y que el mensaje cumpla un patrón LIKE.
-- Si la sentencia no falla, o falla de otra forma, la prueba se detiene.
CREATE FUNCTION pg_temp.esperar_error(
  p_sql TEXT,
  p_sqlstate TEXT,
  p_constraint TEXT DEFAULT NULL,
  p_mensaje TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_ocurrio BOOLEAN := FALSE;
  v_sqlstate TEXT;
  v_constraint TEXT;
  v_mensaje TEXT;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sqlstate = RETURNED_SQLSTATE,
      v_constraint = CONSTRAINT_NAME,
      v_mensaje = MESSAGE_TEXT;
    v_ocurrio := TRUE;

    IF v_sqlstate IS DISTINCT FROM p_sqlstate THEN
      RAISE EXCEPTION
        'SQLSTATE inesperado. Esperado %, recibido %: %',
        p_sqlstate, v_sqlstate, v_mensaje;
    END IF;

    IF p_constraint IS NOT NULL
       AND v_constraint IS DISTINCT FROM p_constraint THEN
      RAISE EXCEPTION
        'Constraint inesperada. Esperada %, recibida %',
        p_constraint, v_constraint;
    END IF;

    IF p_mensaje IS NOT NULL AND v_mensaje NOT LIKE p_mensaje THEN
      RAISE EXCEPTION
        'Mensaje inesperado. Patrón "%", recibido "%"', p_mensaje, v_mensaje;
    END IF;
  END;

  IF NOT v_ocurrio THEN
    RAISE EXCEPTION 'La sentencia debía fallar y fue aceptada: %', p_sql;
  END IF;
END;
$$;

-- Afirmación simple: detiene la prueba con un mensaje claro si no se cumple.
CREATE FUNCTION pg_temp.afirmar(p_condicion BOOLEAN, p_descripcion TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_condicion IS NOT TRUE THEN
    RAISE EXCEPTION 'Afirmación fallida: %', p_descripcion;
  END IF;
END;
$$;
