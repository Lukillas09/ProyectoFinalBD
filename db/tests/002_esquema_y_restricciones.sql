\set ON_ERROR_STOP on
\pset pager off

-- Ejecutar como propietario después de aplicar 001 y 002. Toda la carga de
-- prueba vive en esta transacción y se revierte al final.
SET search_path TO bodegas, pg_catalog;
BEGIN;

DO $$
DECLARE
  v_tablas_faltantes TEXT;
BEGIN
  SELECT string_agg(nombre, ', ' ORDER BY nombre)
  INTO v_tablas_faltantes
  FROM (
    VALUES
      ('analisis_calidad'), ('auditoria_precio'), ('bodega'), ('cepa'),
      ('cliente'), ('composicion_vino'), ('comprobante'), ('departamento'),
      ('distribuidor'), ('empleado'), ('exportador'), ('finca'), ('ingreso'),
      ('localidad'), ('lote_uva'), ('maridaje'), ('parcela'),
      ('permiso_exportacion'), ('renglon_comprobante'), ('renglon_ingreso'),
      ('renglon_transferencia'), ('sala_venta'), ('schema_migration'),
      ('socio_club'), ('stock_deposito'), ('stock_sala'), ('transferencia'),
      ('transportista'), ('transportista_localidad'), ('vino'),
      ('vino_maridaje')
  ) AS esperada(nombre)
  WHERE to_regclass('bodegas.' || nombre) IS NULL;

  IF v_tablas_faltantes IS NOT NULL THEN
    RAISE EXCEPTION 'Faltan tablas esperadas: %', v_tablas_faltantes;
  END IF;

  IF (SELECT count(*) FROM schema_migration) <> 2 THEN
    RAISE EXCEPTION 'Se esperaban 2 migraciones registradas';
  END IF;
END;
$$;

-- Ayudante temporal: exige SQLSTATE y, cuando se indica, nombre de constraint.
CREATE FUNCTION pg_temp.esperar_error(
  p_sql TEXT,
  p_sqlstate TEXT,
  p_constraint TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_ocurrio BOOLEAN := FALSE;
  v_sqlstate TEXT;
  v_constraint TEXT;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sqlstate = RETURNED_SQLSTATE,
      v_constraint = CONSTRAINT_NAME;
    v_ocurrio := TRUE;

    IF v_sqlstate IS DISTINCT FROM p_sqlstate THEN
      RAISE EXCEPTION
        'SQLSTATE inesperado. Esperado %, recibido %', p_sqlstate, v_sqlstate;
    END IF;

    IF p_constraint IS NOT NULL
       AND v_constraint IS DISTINCT FROM p_constraint THEN
      RAISE EXCEPTION
        'Constraint inesperada. Esperada %, recibida %',
        p_constraint, v_constraint;
    END IF;
  END;

  IF NOT v_ocurrio THEN
    RAISE EXCEPTION 'La sentencia debía fallar y fue aceptada: %', p_sql;
  END IF;
END;
$$;

-- Datos mínimos válidos compartidos por los casos negativos.
INSERT INTO departamento (id_departamento, nombre, provincia)
OVERRIDING SYSTEM VALUE
VALUES (900001, 'San Rafael prueba', 'Mendoza prueba');

INSERT INTO localidad (
  id_localidad, codigo_postal, nombre, provincia, encargado_regional
)
OVERRIDING SYSTEM VALUE
VALUES (900001, '5600-T', 'Localidad prueba', 'Mendoza prueba', 'Encargado prueba');

INSERT INTO sala_venta (id_sala, calle, numero, dia_cierre, id_localidad)
OVERRIDING SYSTEM VALUE
VALUES (900001, 'Calle prueba', '100', 'lunes', 900001);

INSERT INTO finca (id_finca, nombre, superficie_ha, id_departamento)
OVERRIDING SYSTEM VALUE
VALUES (900001, 'Finca prueba', 100.00, 900001);

INSERT INTO cepa (id_cepa, nombre, tipo)
OVERRIDING SYSTEM VALUE
VALUES (900001, 'Cepa prueba', 'tinta');

INSERT INTO parcela (
  id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa
)
VALUES (900001, 1, 10.00, 2010, 900001);

INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30999999991', 'Bodega prueba', 'Domicilio prueba');

INSERT INTO vino (
  cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega
)
OVERRIDING SYSTEM VALUE
VALUES (
  900001, 'Vino prueba', 'tinto', 2025, 750, 13.50, 1000.00,
  '30999999991'
);

INSERT INTO cliente (
  id_cliente, nombre_razon_social, tipo_documento, nro_documento,
  direccion, id_localidad, fecha_alta, tipo, descuento_excepcion
)
OVERRIDING SYSTEM VALUE
VALUES (
  900001, 'Exportador prueba', 'CUIT', '30999999992',
  'Dirección prueba', 900001, DATE '2026-01-01', 'exportador', NULL
);

INSERT INTO exportador (id_cliente, pais_destino_principal)
VALUES (900001, 'Chile');

INSERT INTO transportista (
  cod_transportista, razon_social, cuit, email, telefono, domicilio
)
OVERRIDING SYSTEM VALUE
VALUES (
  900001, 'Transportista prueba', '30999999993',
  'prueba@example.invalid', '2604000000', 'Domicilio prueba'
);

INSERT INTO transferencia (
  nro_transferencia, id_sala, fecha_confeccion, estado
)
OVERRIDING SYSTEM VALUE
VALUES (900001, 900001, DATE '2026-10-22', 'en_confeccion');

-- PK compuesta: no puede repetirse (finca, nro_parcela).
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO parcela (
      id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa
    ) VALUES (900001, 1, 8.00, 2012, 900001)
  $sql$,
  '23505',
  'pk_parcela'
);

-- FK compuesta: el par finca/parcela debe existir como tal.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO lote_uva (
      nro_lote, id_finca, nro_parcela, campania,
      fecha_cosecha, kilos, cuit_bodega
    ) VALUES (
      800000, 900001, 999, 2026,
      DATE '2026-03-01', 1000.00, '30999999991'
    )
  $sql$,
  '23503',
  'fk_lote_uva_parcela'
);

-- UNIQUE adicional: tipo y número de documento identifican a un cliente.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO cliente (
      id_cliente, nombre_razon_social, tipo_documento, nro_documento,
      direccion, id_localidad, fecha_alta, tipo
    ) OVERRIDING SYSTEM VALUE VALUES (
      900002, 'Cliente duplicado', 'CUIT', '30999999992',
      'Otra dirección', 900001, DATE '2026-01-02', 'socio'
    )
  $sql$,
  '23505',
  'uq_cliente_documento'
);

-- FK simple: una sala no puede apuntar a una localidad inexistente.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO sala_venta (
      id_sala, calle, numero, dia_cierre, id_localidad
    ) OVERRIDING SYSTEM VALUE VALUES (
      900002, 'Sin localidad', '1', 'martes', 999999
    )
  $sql$,
  '23503',
  'fk_sala_venta_localidad'
);

-- NOT NULL: el nombre del empleado es obligatorio.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
    VALUES ('30999999994', NULL, DATE '2025-01-01', 100000.00, 900001)
  $sql$,
  '23502'
);

-- Superficie inválida.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO finca (
      id_finca, nombre, superficie_ha, id_departamento
    ) OVERRIDING SYSTEM VALUE VALUES (
      900002, 'Finca sin superficie', 0, 900001
    )
  $sql$,
  '23514',
  'ck_finca_superficie_positiva'
);

-- Importe inválido.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO vino (
      cod_vino, nombre, tipo, anada, volumen_ml,
      graduacion, precio, cuit_bodega
    ) OVERRIDING SYSTEM VALUE VALUES (
      900002, 'Vino precio cero', 'tinto', 2025, 750,
      13.50, 0, '30999999991'
    )
  $sql$,
  '23514',
  'ck_vino_precio_positivo'
);

-- Cantidad inválida.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO renglon_transferencia (
      nro_transferencia, cod_vino, cantidad
    ) VALUES (900001, 900001, 0)
  $sql$,
  '23514',
  'ck_renglon_transferencia_cantidad_positiva'
);

-- Graduación fuera del intervalo 5..20.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO vino (
      cod_vino, nombre, tipo, anada, volumen_ml,
      graduacion, precio, cuit_bodega
    ) OVERRIDING SYSTEM VALUE VALUES (
      900003, 'Vino graduación inválida', 'tinto', 2025, 750,
      21.00, 1000.00, '30999999991'
    )
  $sql$,
  '23514',
  'ck_vino_graduacion'
);

-- El permiso debe vencer después de emitirse.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO permiso_exportacion (
      codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento
    ) VALUES (
      'PERMISO-INVALIDO', 900001, DATE '2026-05-01', DATE '2026-05-01'
    )
  $sql$,
  '23514',
  'ck_permiso_exportacion_fechas'
);

-- Primera cosecha válida de la parcela en la campaña.
INSERT INTO lote_uva (
  nro_lote, id_finca, nro_parcela, campania,
  fecha_cosecha, kilos, cuit_bodega
) VALUES (
  800001, 900001, 1, 2026,
  DATE '2026-03-10', 1000.00, '30999999991'
);

-- Segunda cosecha de la misma parcela/campaña: debe rechazarse.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO lote_uva (
      nro_lote, id_finca, nro_parcela, campania,
      fecha_cosecha, kilos, cuit_bodega
    ) VALUES (
      800002, 900001, 1, 2026,
      DATE '2026-03-20', 900.00, '30999999991'
    )
  $sql$,
  '23505',
  'uq_lote_uva_parcela_campania'
);

-- El stock puede ser cero, pero nunca negativo.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    VALUES (900001, 900001, -1)
  $sql$,
  '23514',
  'ck_stock_sala_cantidad_no_negativa'
);

-- El DOMAIN valida CUIT de exactamente once dígitos.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO bodega (cuit, razon_social, domicilio)
    VALUES ('CUIT-MALO', 'Bodega inválida', 'Domicilio')
  $sql$,
  '23514',
  'ck_cuit_dom_formato'
);

\echo 'OK: estructura, PK/FK, UNIQUE, NOT NULL, CHECK, ENUM y DOMAIN verificados.'
ROLLBACK;
\echo 'OK: los datos mínimos de prueba fueron revertidos.'
