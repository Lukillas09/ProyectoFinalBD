\set ON_ERROR_STOP on

-- Ejecutar con la cuenta de reportes después de las migraciones. Comprueba
-- que la cuenta hereda efectivamente bodegas_ro: puede leer y no puede
-- escribir ni ejecutar procedimientos.
SET search_path TO bodegas, pg_catalog;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_roles
    WHERE rolname = current_user
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
  ) OR has_schema_privilege(current_user, 'bodegas', 'CREATE') THEN
    RAISE EXCEPTION 'La cuenta de reportes tiene atributos o privilegios administrativos.';
  END IF;

  -- Sólo SELECT, sobre todas las tablas y vistas salvo schema_migration.
  IF EXISTS (
    SELECT 1
    FROM pg_class AS c
    CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                       ('REFERENCES'), ('TRIGGER')) AS p(privilegio)
    WHERE c.relnamespace = 'bodegas'::regnamespace
      AND c.relkind IN ('r', 'v', 'm')
      AND has_table_privilege(current_user, c.oid, p.privilegio)
  ) THEN
    RAISE EXCEPTION 'La cuenta de reportes tiene privilegios de escritura.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class AS c
    WHERE c.relnamespace = 'bodegas'::regnamespace
      AND c.relkind IN ('r', 'v', 'm')
      AND (has_table_privilege(current_user, c.oid, 'SELECT')
           = (c.relname = 'schema_migration'))
  ) THEN
    RAISE EXCEPTION 'La lectura de reportes no cubre exactamente las tablas de negocio y vistas.';
  END IF;

  IF (SELECT array_agg(proname::TEXT ORDER BY proname)
      FROM pg_proc
      WHERE pronamespace = 'bodegas'::regnamespace
        AND has_function_privilege(current_user, oid, 'EXECUTE'))
     IS DISTINCT FROM ARRAY['fn_antiguedad_anios', 'fn_descuento_cliente',
                            'fn_stock_sala', 'fn_total_comprobante'] THEN
    RAISE EXCEPTION 'La cuenta de reportes ejecuta rutinas inesperadas.';
  END IF;
END;
$$;
\echo 'OK: reportes lee todas las tablas de negocio y vistas, y sólo ejecuta funciones de cálculo.'

-- Lectura real a través de la herencia.
SELECT count(*) AS vinos_en_ficha FROM v_ficha_vino;

-- Escritura real: debe fallar por privilegio (42501).
DO $$
BEGIN
  BEGIN
    INSERT INTO maridaje (nombre, temperatura_servicio_c) VALUES ('Intruso', 10);
    RAISE EXCEPTION 'Reportes pudo insertar.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    CALL sp_procesar_transferencia(1);
    RAISE EXCEPTION 'Reportes pudo ejecutar un procedimiento.';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$$;
\echo 'OK: reportes no puede escribir ni ejecutar procedimientos.'
