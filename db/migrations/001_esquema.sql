-- Bodegas del Atuel - esquema base
-- Ejecutar con el rol propietario sobre PostgreSQL 16.
-- Esta migración crea tipos, tablas, PK y FK. Las restricciones adicionales
-- se agregan en 002_constraints.sql.

SET search_path TO bodegas, pg_catalog;

CREATE DOMAIN cuit_dom AS VARCHAR(11)
  CONSTRAINT ck_cuit_dom_formato
  CHECK (VALUE ~ '^[0-9]{11}$');

CREATE TYPE estado_documento AS ENUM (
  'en_confeccion',
  'terminado',
  'procesado'
);

CREATE TYPE tipo_cliente AS ENUM (
  'socio',
  'distribuidor',
  'exportador'
);

-- Metadato técnico usado por db/migrate.sh. No pertenece al modelo de negocio.
CREATE TABLE schema_migration (
  archivo          VARCHAR(255) NOT NULL,
  checksum_sha256  CHAR(64) NOT NULL,
  aplicada_en      TIMESTAMPTZ NOT NULL,
  CONSTRAINT pk_schema_migration PRIMARY KEY (archivo)
);

CREATE TABLE departamento (
  id_departamento  INTEGER GENERATED ALWAYS AS IDENTITY,
  nombre           VARCHAR(100) NOT NULL,
  provincia        VARCHAR(100) NOT NULL,
  CONSTRAINT pk_departamento PRIMARY KEY (id_departamento)
);

CREATE TABLE localidad (
  id_localidad        INTEGER GENERATED ALWAYS AS IDENTITY,
  codigo_postal       VARCHAR(10) NOT NULL,
  nombre              VARCHAR(100) NOT NULL,
  provincia           VARCHAR(100) NOT NULL,
  encargado_regional  VARCHAR(120) NOT NULL,
  CONSTRAINT pk_localidad PRIMARY KEY (id_localidad)
);

CREATE TABLE sala_venta (
  id_sala       INTEGER GENERATED ALWAYS AS IDENTITY,
  calle         VARCHAR(120) NOT NULL,
  numero        VARCHAR(20) NOT NULL,
  dia_cierre    VARCHAR(10) NOT NULL,
  id_localidad  INTEGER NOT NULL,
  CONSTRAINT pk_sala_venta PRIMARY KEY (id_sala),
  CONSTRAINT fk_sala_venta_localidad
    FOREIGN KEY (id_localidad)
    REFERENCES localidad (id_localidad)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE empleado (
  cuit           cuit_dom NOT NULL,
  nombre         VARCHAR(120) NOT NULL,
  fecha_ingreso  DATE NOT NULL,
  salario        NUMERIC(14,2) NOT NULL,
  id_sala        INTEGER NOT NULL,
  CONSTRAINT pk_empleado PRIMARY KEY (cuit),
  CONSTRAINT fk_empleado_sala_venta
    FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE finca (
  id_finca         INTEGER GENERATED ALWAYS AS IDENTITY,
  nombre           VARCHAR(120) NOT NULL,
  superficie_ha    NUMERIC(10,2) NOT NULL,
  id_departamento  INTEGER NOT NULL,
  CONSTRAINT pk_finca PRIMARY KEY (id_finca),
  CONSTRAINT fk_finca_departamento
    FOREIGN KEY (id_departamento)
    REFERENCES departamento (id_departamento)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE cepa (
  id_cepa  INTEGER GENERATED ALWAYS AS IDENTITY,
  nombre   VARCHAR(100) NOT NULL,
  tipo     VARCHAR(6) NOT NULL,
  CONSTRAINT pk_cepa PRIMARY KEY (id_cepa)
);

-- Entidad débil: nro_parcela sólo identifica dentro de una finca.
CREATE TABLE parcela (
  id_finca          INTEGER NOT NULL,
  nro_parcela       INTEGER NOT NULL,
  superficie_ha     NUMERIC(10,2) NOT NULL,
  anio_plantacion   SMALLINT NOT NULL,
  id_cepa           INTEGER NOT NULL,
  CONSTRAINT pk_parcela PRIMARY KEY (id_finca, nro_parcela),
  CONSTRAINT fk_parcela_finca
    FOREIGN KEY (id_finca)
    REFERENCES finca (id_finca)
    ON UPDATE CASCADE
    ON DELETE CASCADE,
  CONSTRAINT fk_parcela_cepa
    FOREIGN KEY (id_cepa)
    REFERENCES cepa (id_cepa)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE bodega (
  cuit          cuit_dom NOT NULL,
  razon_social  VARCHAR(150) NOT NULL,
  domicilio     VARCHAR(200) NOT NULL,
  CONSTRAINT pk_bodega PRIMARY KEY (cuit)
);

CREATE TABLE lote_uva (
  nro_lote       BIGINT NOT NULL,
  id_finca       INTEGER NOT NULL,
  nro_parcela    INTEGER NOT NULL,
  campania       SMALLINT NOT NULL,
  fecha_cosecha  DATE NOT NULL,
  kilos          NUMERIC(12,2) NOT NULL,
  cuit_bodega    cuit_dom NOT NULL,
  CONSTRAINT pk_lote_uva PRIMARY KEY (nro_lote),
  CONSTRAINT fk_lote_uva_parcela
    FOREIGN KEY (id_finca, nro_parcela)
    REFERENCES parcela (id_finca, nro_parcela)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT fk_lote_uva_bodega
    FOREIGN KEY (cuit_bodega)
    REFERENCES bodega (cuit)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

CREATE TABLE analisis_calidad (
  id_analisis    BIGINT GENERATED ALWAYS AS IDENTITY,
  nro_lote       BIGINT NOT NULL,
  fecha_analisis DATE NOT NULL,
  grado_brix     NUMERIC(5,2) NOT NULL,
  ph             NUMERIC(4,2) NOT NULL,
  acidez_total   NUMERIC(6,2) NOT NULL,
  CONSTRAINT pk_analisis_calidad PRIMARY KEY (id_analisis),
  CONSTRAINT fk_analisis_calidad_lote_uva
    FOREIGN KEY (nro_lote)
    REFERENCES lote_uva (nro_lote)
    ON UPDATE CASCADE
    ON DELETE CASCADE
);

CREATE TABLE vino (
  cod_vino       BIGINT GENERATED ALWAYS AS IDENTITY,
  nombre         VARCHAR(100) NOT NULL,
  tipo           VARCHAR(12) NOT NULL,
  anada          SMALLINT NOT NULL,
  volumen_ml     INTEGER NOT NULL,
  graduacion     NUMERIC(4,2) NOT NULL,
  precio         NUMERIC(14,2) NOT NULL,
  cuit_bodega    cuit_dom NOT NULL,
  CONSTRAINT pk_vino PRIMARY KEY (cod_vino),
  CONSTRAINT fk_vino_bodega
    FOREIGN KEY (cuit_bodega)
    REFERENCES bodega (cuit)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

CREATE TABLE composicion_vino (
  cod_vino   BIGINT NOT NULL,
  id_cepa    INTEGER NOT NULL,
  porcentaje NUMERIC(5,2) NOT NULL,
  CONSTRAINT pk_composicion_vino PRIMARY KEY (cod_vino, id_cepa),
  CONSTRAINT fk_composicion_vino_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_composicion_vino_cepa
    FOREIGN KEY (id_cepa)
    REFERENCES cepa (id_cepa)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE maridaje (
  id_maridaje            INTEGER GENERATED ALWAYS AS IDENTITY,
  nombre                 VARCHAR(100) NOT NULL,
  temperatura_servicio_c NUMERIC(4,1) NOT NULL,
  CONSTRAINT pk_maridaje PRIMARY KEY (id_maridaje)
);

CREATE TABLE vino_maridaje (
  cod_vino     BIGINT NOT NULL,
  id_maridaje  INTEGER NOT NULL,
  CONSTRAINT pk_vino_maridaje PRIMARY KEY (cod_vino, id_maridaje),
  CONSTRAINT fk_vino_maridaje_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_vino_maridaje_maridaje
    FOREIGN KEY (id_maridaje)
    REFERENCES maridaje (id_maridaje)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE cliente (
  id_cliente            BIGINT GENERATED ALWAYS AS IDENTITY,
  nombre_razon_social   VARCHAR(150) NOT NULL,
  tipo_documento        VARCHAR(20) NOT NULL,
  nro_documento         VARCHAR(30) NOT NULL,
  direccion             VARCHAR(200) NOT NULL,
  id_localidad          INTEGER NOT NULL,
  fecha_alta            DATE NOT NULL,
  tipo                   tipo_cliente NOT NULL,
  descuento_excepcion   NUMERIC(5,2),
  CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
  CONSTRAINT fk_cliente_localidad
    FOREIGN KEY (id_localidad)
    REFERENCES localidad (id_localidad)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE socio_club (
  id_cliente BIGINT NOT NULL,
  CONSTRAINT pk_socio_club PRIMARY KEY (id_cliente),
  CONSTRAINT fk_socio_club_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE distribuidor (
  id_cliente      BIGINT NOT NULL,
  zona_cobertura  VARCHAR(150) NOT NULL,
  nro_habilitacion VARCHAR(50) NOT NULL,
  CONSTRAINT pk_distribuidor PRIMARY KEY (id_cliente),
  CONSTRAINT fk_distribuidor_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE exportador (
  id_cliente             BIGINT NOT NULL,
  pais_destino_principal VARCHAR(100) NOT NULL,
  CONSTRAINT pk_exportador PRIMARY KEY (id_cliente),
  CONSTRAINT fk_exportador_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE permiso_exportacion (
  codigo_permiso   VARCHAR(50) NOT NULL,
  id_exportador    BIGINT NOT NULL,
  fecha_emision    DATE NOT NULL,
  fecha_vencimiento DATE NOT NULL,
  CONSTRAINT pk_permiso_exportacion PRIMARY KEY (codigo_permiso),
  CONSTRAINT fk_permiso_exportacion_exportador
    FOREIGN KEY (id_exportador)
    REFERENCES exportador (id_cliente)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE comprobante (
  nro_comprobante BIGINT GENERATED ALWAYS AS IDENTITY,
  fecha           TIMESTAMPTZ NOT NULL,
  id_cliente      BIGINT NOT NULL,
  id_sala         INTEGER NOT NULL,
  subtotal        NUMERIC(14,2) NOT NULL,
  descuento       NUMERIC(14,2) NOT NULL,
  total           NUMERIC(14,2) NOT NULL,
  CONSTRAINT pk_comprobante PRIMARY KEY (nro_comprobante),
  CONSTRAINT fk_comprobante_cliente
    FOREIGN KEY (id_cliente)
    REFERENCES cliente (id_cliente)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT,
  CONSTRAINT fk_comprobante_sala_venta
    FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE renglon_comprobante (
  nro_comprobante     BIGINT NOT NULL,
  cod_vino            BIGINT NOT NULL,
  cantidad            INTEGER NOT NULL,
  precio_unitario     NUMERIC(14,2) NOT NULL,
  descuento_porcentaje NUMERIC(5,2) NOT NULL,
  subtotal            NUMERIC(14,2) NOT NULL,
  CONSTRAINT pk_renglon_comprobante PRIMARY KEY (nro_comprobante, cod_vino),
  CONSTRAINT fk_renglon_comprobante_comprobante
    FOREIGN KEY (nro_comprobante)
    REFERENCES comprobante (nro_comprobante)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_renglon_comprobante_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE transportista (
  cod_transportista INTEGER GENERATED ALWAYS AS IDENTITY,
  razon_social      VARCHAR(150) NOT NULL,
  cuit              cuit_dom NOT NULL,
  email             VARCHAR(254) NOT NULL,
  telefono          VARCHAR(30) NOT NULL,
  domicilio         VARCHAR(200) NOT NULL,
  CONSTRAINT pk_transportista PRIMARY KEY (cod_transportista)
);

CREATE TABLE transportista_localidad (
  cod_transportista INTEGER NOT NULL,
  id_localidad      INTEGER NOT NULL,
  CONSTRAINT pk_transportista_localidad PRIMARY KEY (cod_transportista, id_localidad),
  CONSTRAINT fk_transportista_localidad_transportista
    FOREIGN KEY (cod_transportista)
    REFERENCES transportista (cod_transportista)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_transportista_localidad_localidad
    FOREIGN KEY (id_localidad)
    REFERENCES localidad (id_localidad)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
);

CREATE TABLE ingreso (
  cod_ingreso       BIGINT GENERATED ALWAYS AS IDENTITY,
  fecha             TIMESTAMPTZ NOT NULL,
  estado            estado_documento NOT NULL,
  cod_transportista INTEGER NOT NULL,
  cuit_bodega       cuit_dom NOT NULL,
  CONSTRAINT pk_ingreso PRIMARY KEY (cod_ingreso),
  CONSTRAINT fk_ingreso_transportista
    FOREIGN KEY (cod_transportista)
    REFERENCES transportista (cod_transportista)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT,
  CONSTRAINT fk_ingreso_bodega
    FOREIGN KEY (cuit_bodega)
    REFERENCES bodega (cuit)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
);

CREATE TABLE renglon_ingreso (
  cod_ingreso BIGINT NOT NULL,
  cod_vino    BIGINT NOT NULL,
  cantidad    INTEGER NOT NULL,
  CONSTRAINT pk_renglon_ingreso PRIMARY KEY (cod_ingreso, cod_vino),
  CONSTRAINT fk_renglon_ingreso_ingreso
    FOREIGN KEY (cod_ingreso)
    REFERENCES ingreso (cod_ingreso)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_renglon_ingreso_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE transferencia (
  nro_transferencia BIGINT GENERATED ALWAYS AS IDENTITY,
  id_sala           INTEGER NOT NULL,
  fecha_confeccion  DATE NOT NULL,
  estado            estado_documento NOT NULL,
  CONSTRAINT pk_transferencia PRIMARY KEY (nro_transferencia),
  CONSTRAINT fk_transferencia_sala_venta
    FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE renglon_transferencia (
  nro_transferencia BIGINT NOT NULL,
  cod_vino          BIGINT NOT NULL,
  cantidad          INTEGER NOT NULL,
  CONSTRAINT pk_renglon_transferencia PRIMARY KEY (nro_transferencia, cod_vino),
  CONSTRAINT fk_renglon_transferencia_transferencia
    FOREIGN KEY (nro_transferencia)
    REFERENCES transferencia (nro_transferencia)
    ON UPDATE RESTRICT
    ON DELETE CASCADE,
  CONSTRAINT fk_renglon_transferencia_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE stock_sala (
  id_sala  INTEGER NOT NULL,
  cod_vino BIGINT NOT NULL,
  cantidad INTEGER NOT NULL,
  CONSTRAINT pk_stock_sala PRIMARY KEY (id_sala, cod_vino),
  CONSTRAINT fk_stock_sala_sala_venta
    FOREIGN KEY (id_sala)
    REFERENCES sala_venta (id_sala)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT,
  CONSTRAINT fk_stock_sala_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

-- El depósito central es único, por eso cada vino tiene una sola fila.
CREATE TABLE stock_deposito (
  cod_vino BIGINT NOT NULL,
  cantidad INTEGER NOT NULL,
  CONSTRAINT pk_stock_deposito PRIMARY KEY (cod_vino),
  CONSTRAINT fk_stock_deposito_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);

CREATE TABLE auditoria_precio (
  id_auditoria    BIGINT GENERATED ALWAYS AS IDENTITY,
  cod_vino        BIGINT NOT NULL,
  precio_anterior NUMERIC(14,2) NOT NULL,
  precio_nuevo    NUMERIC(14,2) NOT NULL,
  fecha_hora      TIMESTAMPTZ NOT NULL,
  usuario_bd      VARCHAR(63) NOT NULL,
  CONSTRAINT pk_auditoria_precio PRIMARY KEY (id_auditoria),
  CONSTRAINT fk_auditoria_precio_vino
    FOREIGN KEY (cod_vino)
    REFERENCES vino (cod_vino)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
);
