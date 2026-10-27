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

  -- Las etapas posteriores agregan migraciones: se exige que estén las dos
  -- que crean el esquema y las restricciones base, no un total fijo.
  IF (SELECT count(*) FROM schema_migration
      WHERE archivo IN ('001_esquema.sql', '002_constraints.sql')) <> 2 THEN
    RAISE EXCEPTION 'Faltan 001_esquema.sql o 002_constraints.sql en schema_migration';
  END IF;
END;
$$;

-- esperar_error(sql, sqlstate, constraint, patrón de mensaje)
\ir ayudantes.sql

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

-- Jerarquía de clientes: un socio válido, con su fila de subtipo.
INSERT INTO cliente (
  id_cliente, nombre_razon_social, tipo_documento, nro_documento,
  direccion, id_localidad, fecha_alta, tipo
)
OVERRIDING SYSTEM VALUE
VALUES (
  900003, 'Socio prueba', 'DNI', '30999999',
  'Dirección socio', 900001, DATE '2026-02-01', 'socio'
);

INSERT INTO socio_club (id_cliente) VALUES (900003);

-- Exclusividad: un socio no puede insertarse como exportador. El DEFAULT
-- completa tipo = 'exportador' y el par (900003, exportador) no existe en
-- cliente. Error esperado: 23503 en fk_exportador_cliente.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO exportador (id_cliente, pais_destino_principal)
    VALUES (900003, 'Brasil')
  $sql$,
  '23503',
  'fk_exportador_cliente'
);

-- Tampoco declarando el tipo real del cliente: el discriminador del subtipo
-- es constante. Error esperado: 23514 en ck_exportador_tipo.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO exportador (id_cliente, tipo, pais_destino_principal)
    VALUES (900003, 'socio', 'Brasil')
  $sql$,
  '23514',
  'ck_exportador_tipo'
);

-- Un cliente no puede estar en dos subtipos: el exportador 900001 no puede
-- agregarse como distribuidor. Error esperado: 23503 en
-- fk_distribuidor_cliente.
SELECT pg_temp.esperar_error(
  $sql$
    INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion)
    VALUES (900001, 'Zona prueba', 'HAB-PRUEBA')
  $sql$,
  '23503',
  'fk_distribuidor_cliente'
);

-- Cambiar el tipo de un cliente con fila de subtipo dejaría ambos
-- desalineados; ON UPDATE RESTRICT lo rechaza. Error esperado: 23503 en
-- fk_socio_club_cliente.
SELECT pg_temp.esperar_error(
  $sql$
    UPDATE cliente SET tipo = 'distribuidor' WHERE id_cliente = 900003
  $sql$,
  '23503',
  'fk_socio_club_cliente'
);

\echo 'OK: estructura, PK/FK, UNIQUE, NOT NULL, CHECK, ENUM y DOMAIN verificados.'
\echo 'OK: exclusividad de subtipos de cliente verificada.'
ROLLBACK;
\echo 'OK: los datos mínimos de prueba fueron revertidos.'
