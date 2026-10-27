-- Bodegas del Atuel - restricciones adicionales
-- UNIQUE, CHECK y DEFAULT se separan del esqueleto relacional para que su
-- propósito sea visible y verificable en la etapa de integridad.

SET search_path TO bodegas, pg_catalog;

ALTER TABLE schema_migration
  ADD CONSTRAINT ck_schema_migration_checksum
  CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$');

ALTER TABLE departamento
  ADD CONSTRAINT uq_departamento_nombre_provincia
  UNIQUE (nombre, provincia);

ALTER TABLE localidad
  ADD CONSTRAINT uq_localidad_provincia_nombre_cp
  UNIQUE (provincia, nombre, codigo_postal);

ALTER TABLE sala_venta
  ADD CONSTRAINT uq_sala_venta_direccion
  UNIQUE (id_localidad, calle, numero),
  ADD CONSTRAINT ck_sala_venta_dia_cierre
  CHECK (dia_cierre IN (
    'lunes', 'martes', 'miercoles', 'jueves',
    'viernes', 'sabado', 'domingo'
  ));

ALTER TABLE empleado
  ADD CONSTRAINT ck_empleado_salario_positivo
  CHECK (salario > 0);

ALTER TABLE finca
  ADD CONSTRAINT ck_finca_superficie_positiva
  CHECK (superficie_ha > 0);

ALTER TABLE cepa
  ADD CONSTRAINT uq_cepa_nombre
  UNIQUE (nombre),
  ADD CONSTRAINT ck_cepa_tipo
  CHECK (tipo IN ('tinta', 'blanca'));

ALTER TABLE parcela
  ADD CONSTRAINT ck_parcela_numero_positivo
  CHECK (nro_parcela > 0),
  ADD CONSTRAINT ck_parcela_superficie_positiva
  CHECK (superficie_ha > 0),
  ADD CONSTRAINT ck_parcela_anio_plantacion_positivo
  CHECK (anio_plantacion > 0);

ALTER TABLE lote_uva
  ADD CONSTRAINT uq_lote_uva_parcela_campania
  UNIQUE (id_finca, nro_parcela, campania),
  ADD CONSTRAINT ck_lote_uva_campania
  CHECK (campania BETWEEN 1900 AND 9999),
  ADD CONSTRAINT ck_lote_uva_fecha_campania
  CHECK (EXTRACT(YEAR FROM fecha_cosecha)::SMALLINT = campania),
  ADD CONSTRAINT ck_lote_uva_kilos_positivos
  CHECK (kilos > 0);

ALTER TABLE analisis_calidad
  ADD CONSTRAINT ck_analisis_calidad_brix_positivo
  CHECK (grado_brix > 0),
  ADD CONSTRAINT ck_analisis_calidad_ph
  CHECK (ph BETWEEN 0 AND 14),
  ADD CONSTRAINT ck_analisis_calidad_acidez_no_negativa
  CHECK (acidez_total >= 0);

ALTER TABLE vino
  ADD CONSTRAINT uq_vino_identidad_comercial
  UNIQUE (cuit_bodega, nombre, anada, volumen_ml),
  ADD CONSTRAINT ck_vino_tipo
  CHECK (tipo IN ('tinto', 'blanco', 'rosado', 'espumante')),
  ADD CONSTRAINT ck_vino_anada
  CHECK (anada BETWEEN 1900 AND 9999),
  ADD CONSTRAINT ck_vino_volumen_positivo
  CHECK (volumen_ml > 0),
  ADD CONSTRAINT ck_vino_graduacion
  CHECK (graduacion BETWEEN 5 AND 20),
  ADD CONSTRAINT ck_vino_precio_positivo
  CHECK (precio > 0);

ALTER TABLE composicion_vino
  ADD CONSTRAINT ck_composicion_vino_porcentaje
  CHECK (porcentaje > 0 AND porcentaje <= 100);

ALTER TABLE maridaje
  ADD CONSTRAINT uq_maridaje_nombre
  UNIQUE (nombre);

ALTER TABLE cliente
  ADD CONSTRAINT uq_cliente_documento
  UNIQUE (tipo_documento, nro_documento),
  ADD CONSTRAINT ck_cliente_descuento_excepcion
  CHECK (
    descuento_excepcion IS NULL
    OR (tipo = 'exportador' AND descuento_excepcion = 35.00)
  );

-- El discriminador de cada subtipo es constante; junto con la FK compuesta
-- de 001 impide que un cliente tenga la fila de otro subtipo.
ALTER TABLE socio_club
  ADD CONSTRAINT ck_socio_club_tipo
  CHECK (tipo = 'socio');

ALTER TABLE distribuidor
  ADD CONSTRAINT uq_distribuidor_habilitacion
  UNIQUE (nro_habilitacion),
  ADD CONSTRAINT ck_distribuidor_tipo
  CHECK (tipo = 'distribuidor');

ALTER TABLE exportador
  ADD CONSTRAINT ck_exportador_tipo
  CHECK (tipo = 'exportador');

ALTER TABLE permiso_exportacion
  ADD CONSTRAINT ck_permiso_exportacion_fechas
  CHECK (fecha_vencimiento > fecha_emision);

ALTER TABLE comprobante
  ADD CONSTRAINT ck_comprobante_importes
  CHECK (
    subtotal >= 0
    AND descuento >= 0
    AND descuento <= subtotal
    AND total = subtotal - descuento
  );

ALTER TABLE renglon_comprobante
  ADD CONSTRAINT ck_renglon_comprobante_cantidad_positiva
  CHECK (cantidad > 0),
  ADD CONSTRAINT ck_renglon_comprobante_precio_positivo
  CHECK (precio_unitario > 0),
  ADD CONSTRAINT ck_renglon_comprobante_descuento
  CHECK (descuento_porcentaje BETWEEN 0 AND 100),
  ADD CONSTRAINT ck_renglon_comprobante_subtotal
  CHECK (
    subtotal = ROUND(
      cantidad * precio_unitario * (1 - descuento_porcentaje / 100),
      2
    )
  );

ALTER TABLE transportista
  ADD CONSTRAINT uq_transportista_cuit
  UNIQUE (cuit);

ALTER TABLE renglon_ingreso
  ADD CONSTRAINT ck_renglon_ingreso_cantidad_positiva
  CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
  ADD CONSTRAINT ck_renglon_transferencia_cantidad_positiva
  CHECK (cantidad > 0);

ALTER TABLE stock_sala
  ADD CONSTRAINT ck_stock_sala_cantidad_no_negativa
  CHECK (cantidad >= 0);

ALTER TABLE stock_deposito
  ADD CONSTRAINT ck_stock_deposito_cantidad_no_negativa
  CHECK (cantidad >= 0);

ALTER TABLE auditoria_precio
  ADD CONSTRAINT ck_auditoria_precio_valores
  CHECK (
    precio_anterior > 0
    AND precio_nuevo > 0
    AND precio_anterior <> precio_nuevo
  );

ALTER TABLE cliente
  ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

ALTER TABLE socio_club
  ALTER COLUMN tipo SET DEFAULT 'socio';

ALTER TABLE distribuidor
  ALTER COLUMN tipo SET DEFAULT 'distribuidor';

ALTER TABLE exportador
  ALTER COLUMN tipo SET DEFAULT 'exportador';

ALTER TABLE comprobante
  ALTER COLUMN fecha SET DEFAULT CURRENT_TIMESTAMP,
  ALTER COLUMN subtotal SET DEFAULT 0,
  ALTER COLUMN descuento SET DEFAULT 0,
  ALTER COLUMN total SET DEFAULT 0;

ALTER TABLE ingreso
  ALTER COLUMN fecha SET DEFAULT CURRENT_TIMESTAMP,
  ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE transferencia
  ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE,
  ALTER COLUMN estado SET DEFAULT 'en_confeccion';

ALTER TABLE stock_sala
  ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE stock_deposito
  ALTER COLUMN cantidad SET DEFAULT 0;

ALTER TABLE auditoria_precio
  ALTER COLUMN fecha_hora SET DEFAULT CURRENT_TIMESTAMP,
  ALTER COLUMN usuario_bd SET DEFAULT CURRENT_USER;
