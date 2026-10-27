-- Bodegas del Atuel - privilegios de los roles (Etapa 2)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Roles del proyecto:
-- - propietario (DB_OWNER_USER): dueño de todos los objetos; aplica migraciones.
-- - bodegas_rw: grupo de la API (DB_APP_USER lo hereda). Lectura y la
--   escritura que necesitan los endpoints de la Etapa 6.
-- - bodegas_ro: grupo de reportes (DB_REPORT_USER lo hereda). Sólo lectura.
-- Las cuentas de conexión y los grupos los crea db/bootstrap: el propietario es
-- NOCREATEROLE y una migración no puede crear roles. Aquí sólo se otorgan y
-- revocan privilegios sobre objetos, siempre a los grupos (nombres fijos).
--
-- Principio: la API no escribe directamente stock, auditoría, importes ni
-- estados. Esas columnas cambian sólo por triggers y procedimientos
-- SECURITY DEFINER que validan las reglas. Los privilegios por columna además
-- impiden que la API envíe precio, descuento o importes.

SET search_path TO bodegas, pg_catalog;

-- Nada público por omisión (el bootstrap ya cerró los privilegios
-- predeterminados; se repite explícitamente sobre lo existente).
REVOKE ALL ON ALL TABLES IN SCHEMA bodegas FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA bodegas FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA bodegas FROM PUBLIC;

-------------------------------------------------------------------------------
-- API: bodegas_rw
-------------------------------------------------------------------------------

-- Catálogos que la API consulta para filtros y altas.
GRANT SELECT ON
  localidad, sala_venta, bodega, cepa, maridaje,
  transportista, transportista_localidad
TO bodegas_rw;

-- Catálogo y CRUD de vinos con su composición y maridajes.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  vino, composicion_vino, vino_maridaje
TO bodegas_rw;

-- CRUD de clientes con sus tres subtipos y permisos de exportación.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  cliente, socio_club, distribuidor, exportador, permiso_exportacion
TO bodegas_rw;

-- Ventas: alta de cabecera y renglones. Sólo las columnas que decide el
-- usuario; precio, descuento, subtotal e importes los calcula la base.
GRANT SELECT ON comprobante, renglon_comprobante TO bodegas_rw;
GRANT INSERT (id_cliente, id_sala) ON comprobante TO bodegas_rw;
GRANT INSERT (nro_comprobante, cod_vino, cantidad) ON renglon_comprobante TO bodegas_rw;

-- Ingresos y transferencias: alta de cabecera y edición de renglones en
-- confección. El estado cambia sólo con CALL sp_terminar_* / sp_procesar_*.
GRANT SELECT ON ingreso, transferencia TO bodegas_rw;
GRANT INSERT (cod_transportista, cuit_bodega) ON ingreso TO bodegas_rw;
GRANT INSERT (id_sala) ON transferencia TO bodegas_rw;
GRANT SELECT, INSERT, UPDATE (cantidad), DELETE ON
  renglon_ingreso, renglon_transferencia
TO bodegas_rw;

-- Stock y auditoría: sólo lectura.
GRANT SELECT ON stock_sala, stock_deposito, auditoria_precio TO bodegas_rw;

-- Vistas para catálogo y reportes de la API.
GRANT SELECT ON
  v_stock_total_vino, v_ventas_mensuales_sala,
  v_documentos_pendientes, v_ficha_vino
TO bodegas_rw;

-- Funciones de cálculo (lectura) y procedimientos de estado.
GRANT EXECUTE ON FUNCTION
  fn_descuento_cliente(BIGINT),
  fn_stock_sala(INTEGER, BIGINT),
  fn_total_comprobante(BIGINT),
  fn_antiguedad_anios(DATE, DATE)
TO bodegas_rw;

GRANT EXECUTE ON PROCEDURE
  sp_terminar_ingreso(BIGINT),
  sp_procesar_ingreso(BIGINT),
  sp_terminar_transferencia(BIGINT),
  sp_procesar_transferencia(BIGINT)
TO bodegas_rw;

-- PostgreSQL no verifica EXECUTE sobre una función de trigger al dispararla,
-- pero sí sobre las funciones que ella llama. trg_ingreso_estado y
-- trg_transferencia_estado se ejecutan con los privilegios de quien inserta
-- (no son SECURITY DEFINER) y llaman a esta validación, que no modifica datos.
GRANT EXECUTE ON FUNCTION
  fn_validar_transicion_estado(TEXT, TEXT, estado_documento, estado_documento, BOOLEAN)
TO bodegas_rw;

-------------------------------------------------------------------------------
-- Reportes: bodegas_ro
-------------------------------------------------------------------------------

-- Lectura de todas las tablas de negocio y vistas; nada de la tabla técnica.
GRANT SELECT ON ALL TABLES IN SCHEMA bodegas TO bodegas_ro;
REVOKE SELECT ON schema_migration FROM bodegas_ro;

-- Sólo funciones de cálculo; ningún procedimiento ni función que escriba.
GRANT EXECUTE ON FUNCTION
  fn_descuento_cliente(BIGINT),
  fn_stock_sala(INTEGER, BIGINT),
  fn_total_comprobante(BIGINT),
  fn_antiguedad_anios(DATE, DATE)
TO bodegas_ro;
