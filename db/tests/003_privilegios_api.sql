\set ON_ERROR_STOP on

-- Ejecutar con la cuenta de la API después de las migraciones. Comprueba los
-- privilegios que la cuenta tiene efectivamente (heredados de bodegas_rw)
-- contra la matriz esperada de 007_roles.sql: si sobra o falta alguno, falla
-- y lo nombra. Cada aserción falsa ejecuta RAISE EXCEPTION para que psql, con
-- ON_ERROR_STOP, termine con código distinto de cero.
SET search_path TO bodegas, pg_catalog;

SELECT (
  NOT rolsuper
  AND NOT rolcreatedb
  AND NOT rolcreaterole
  AND NOT rolreplication
  AND NOT rolbypassrls
) AS atributos_limitados
FROM pg_roles
WHERE rolname = current_user
\gset

SELECT (
  has_schema_privilege(current_user, 'bodegas', 'USAGE')
  AND NOT has_schema_privilege(current_user, 'bodegas', 'CREATE')
) AS esquema_limitado
\gset

\if :atributos_limitados
  \echo 'OK: la API no tiene atributos administrativos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'la API tiene atributos administrativos.'; END $$;
\endif

\if :esquema_limitado
  \echo 'OK: la API usa el esquema pero no puede crear objetos.'
\else
  DO $$ BEGIN RAISE EXCEPTION 'privilegios incorrectos sobre el esquema.'; END $$;
\endif

-- Matriz de privilegios de tabla y vista (nivel tabla).
DO $$
DECLARE
  v_esperado TEXT[] := ARRAY[
    'auditoria_precio:SELECT',
    'bodega:SELECT',
    'cepa:SELECT',
    'cliente:DELETE', 'cliente:INSERT', 'cliente:SELECT', 'cliente:UPDATE',
    'composicion_vino:DELETE', 'composicion_vino:INSERT', 'composicion_vino:SELECT', 'composicion_vino:UPDATE',
    'comprobante:SELECT',
    'distribuidor:DELETE', 'distribuidor:INSERT', 'distribuidor:SELECT', 'distribuidor:UPDATE',
    'exportador:DELETE', 'exportador:INSERT', 'exportador:SELECT', 'exportador:UPDATE',
    'ingreso:SELECT',
    'localidad:SELECT',
    'maridaje:SELECT',
    'permiso_exportacion:DELETE', 'permiso_exportacion:INSERT', 'permiso_exportacion:SELECT', 'permiso_exportacion:UPDATE',
    'renglon_comprobante:SELECT',
    'renglon_ingreso:DELETE', 'renglon_ingreso:INSERT', 'renglon_ingreso:SELECT',
    'renglon_transferencia:DELETE', 'renglon_transferencia:INSERT', 'renglon_transferencia:SELECT',
    'sala_venta:SELECT',
    'socio_club:DELETE', 'socio_club:INSERT', 'socio_club:SELECT', 'socio_club:UPDATE',
    'stock_deposito:SELECT',
    'stock_sala:SELECT',
    'transferencia:SELECT',
    'transportista:SELECT',
    'transportista_localidad:SELECT',
    'v_documentos_pendientes:SELECT',
    'v_ficha_vino:SELECT',
    'v_stock_total_vino:SELECT',
    'v_ventas_mensuales_sala:SELECT',
    'vino:DELETE', 'vino:INSERT', 'vino:SELECT', 'vino:UPDATE',
    'vino_maridaje:DELETE', 'vino_maridaje:INSERT', 'vino_maridaje:SELECT', 'vino_maridaje:UPDATE'
  ];
  v_real TEXT[];
  v_sobran TEXT[];
  v_faltan TEXT[];
BEGIN
  SELECT array_agg(c.relname || ':' || p.privilegio ORDER BY 1)
  INTO v_real
  FROM pg_class AS c
  CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                     ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) AS p(privilegio)
  WHERE c.relnamespace = 'bodegas'::regnamespace
    AND c.relkind IN ('r', 'v', 'm')
    AND has_table_privilege(current_user, c.oid, p.privilegio);

  SELECT array_agg(x ORDER BY x) INTO v_sobran
  FROM unnest(v_real) AS x WHERE x <> ALL (v_esperado);
  SELECT array_agg(x ORDER BY x) INTO v_faltan
  FROM unnest(v_esperado) AS x WHERE x <> ALL (COALESCE(v_real, '{}'));

  IF v_sobran IS NOT NULL OR v_faltan IS NOT NULL THEN
    RAISE EXCEPTION 'Privilegios de tabla de la API inesperados. Sobran: %. Faltan: %.',
      v_sobran, v_faltan;
  END IF;
END;
$$;
\echo 'OK: la matriz de privilegios de tablas y vistas es exactamente la esperada.'

-- Privilegios por columna. Ventas: ninguna columna insertable (sólo
-- fn_registrar_venta). Documentos: la API decide sala, bodega, transportista,
-- vino y cantidad; nunca estados ni fechas.
DO $$
DECLARE
  v_fallas TEXT;
BEGIN
  SELECT string_agg(format('%s.%s %s (esperado %s)', tabla, columna, privilegio, esperado), '; ')
  INTO v_fallas
  FROM (VALUES
    ('comprobante', 'id_cliente', 'INSERT', FALSE),
    ('comprobante', 'id_sala', 'INSERT', FALSE),
    ('comprobante', 'total', 'INSERT', FALSE),
    ('comprobante', 'fecha', 'INSERT', FALSE),
    ('comprobante', 'xact_alta', 'INSERT', FALSE),
    ('comprobante', 'total', 'UPDATE', FALSE),
    ('renglon_comprobante', 'nro_comprobante', 'INSERT', FALSE),
    ('renglon_comprobante', 'cantidad', 'INSERT', FALSE),
    ('renglon_comprobante', 'precio_unitario', 'INSERT', FALSE),
    ('renglon_comprobante', 'descuento_porcentaje', 'INSERT', FALSE),
    ('renglon_comprobante', 'subtotal', 'INSERT', FALSE),
    ('ingreso', 'cuit_bodega', 'INSERT', TRUE),
    ('ingreso', 'estado', 'INSERT', FALSE),
    ('ingreso', 'estado', 'UPDATE', FALSE),
    ('transferencia', 'id_sala', 'INSERT', TRUE),
    ('transferencia', 'fecha_confeccion', 'INSERT', FALSE),
    ('transferencia', 'estado', 'UPDATE', FALSE),
    ('renglon_ingreso', 'cantidad', 'UPDATE', TRUE),
    ('renglon_ingreso', 'cod_vino', 'UPDATE', FALSE),
    ('renglon_transferencia', 'cantidad', 'UPDATE', TRUE),
    ('stock_sala', 'cantidad', 'UPDATE', FALSE),
    ('stock_deposito', 'cantidad', 'INSERT', FALSE),
    ('auditoria_precio', 'precio_nuevo', 'INSERT', FALSE)
  ) AS e(tabla, columna, privilegio, esperado)
  WHERE has_column_privilege(current_user, 'bodegas.' || tabla, columna, privilegio)
        IS DISTINCT FROM esperado;

  IF v_fallas IS NOT NULL THEN
    RAISE EXCEPTION 'Privilegios de columna inesperados: %', v_fallas;
  END IF;
END;
$$;
\echo 'OK: sin INSERT directo de ventas; los documentos no aceptan estados ni fechas.'

-- Rutinas: sólo cálculos de lectura y procedimientos de estado.
DO $$
DECLARE
  v_esperado TEXT[] := ARRAY[
    'fn_antiguedad_anios', 'fn_descuento_cliente', 'fn_registrar_venta',
    'fn_stock_sala', 'fn_total_comprobante', 'fn_validar_transicion_estado',
    'sp_procesar_ingreso', 'sp_procesar_transferencia',
    'sp_terminar_ingreso', 'sp_terminar_transferencia'
  ];
  v_real TEXT[];
BEGIN
  SELECT array_agg(proname::TEXT ORDER BY proname)
  INTO v_real
  FROM pg_proc
  WHERE pronamespace = 'bodegas'::regnamespace
    AND has_function_privilege(current_user, oid, 'EXECUTE');

  IF v_real IS DISTINCT FROM v_esperado THEN
    RAISE EXCEPTION 'Rutinas ejecutables por la API inesperadas: %', v_real;
  END IF;
END;
$$;
\echo 'OK: la API ejecuta sólo cálculos, la validación de estados, la venta y los procedimientos.'

-- Secuencias: no hace falta USAGE para insertar en columnas IDENTITY
-- (lo demuestra 005_roles.sql con un alta real).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE relnamespace = 'bodegas'::regnamespace
      AND relkind = 'S'
      AND (has_sequence_privilege(current_user, oid, 'USAGE')
           OR has_sequence_privilege(current_user, oid, 'UPDATE'))
  ) THEN
    RAISE EXCEPTION 'La API tiene privilegios sobre secuencias.';
  END IF;
END;
$$;
\echo 'OK: la API no tiene privilegios sobre secuencias.'
