# Diccionario de datos

## 1. Convenciones y tipos propios

Este diccionario corresponde exactamente a `db/migrations/001_esquema.sql` y `002_constraints.sql`. “Nulo: No” significa `NOT NULL`. `IDENTITY ALWAYS` describe generación de identidad, no un `DEFAULT` editable. Todos los objetos están en el esquema `bodegas`.

| Tipo | Definición | Regla |
|---|---|---|
| `cuit_dom` | `VARCHAR(11)` | `ck_cuit_dom_formato`: exactamente once dígitos (`^[0-9]{11}$`). La nulabilidad la decide cada columna. |
| `estado_documento` | ENUM | `en_confeccion`, `terminado`, `procesado`. |
| `tipo_cliente` | ENUM | `socio`, `distribuidor`, `exportador`. |

## 2. Metadato de migraciones

### `schema_migration`

Una fila registra un archivo aplicado. Es infraestructura, no una entidad de negocio.

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `archivo` | Nombre del archivo de migración | `VARCHAR(255)` | No | — | PK `pk_schema_migration` |
| `checksum_sha256` | Huella del contenido aplicado | `CHAR(64)` | No | — | `ck_schema_migration_checksum`: 64 caracteres hexadecimales minúsculos |
| `aplicada_en` | Instante de aplicación | `TIMESTAMPTZ` | No | —; lo informa el runner | — |

## 3. Territorio, red y personal

### `departamento`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_departamento` | Identificador interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_departamento` |
| `nombre` | Nombre del departamento | `VARCHAR(100)` | No | — | Parte de `uq_departamento_nombre_provincia` |
| `provincia` | Provincia a la que pertenece | `VARCHAR(100)` | No | — | Parte de `uq_departamento_nombre_provincia` |

### `localidad`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_localidad` | Identificador interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_localidad` |
| `codigo_postal` | Código postal, no único aisladamente | `VARCHAR(10)` | No | — | Parte de `uq_localidad_provincia_nombre_cp` |
| `nombre` | Nombre, no único aisladamente | `VARCHAR(100)` | No | — | Parte de `uq_localidad_provincia_nombre_cp` |
| `provincia` | Provincia | `VARCHAR(100)` | No | — | Parte de `uq_localidad_provincia_nombre_cp` |
| `encargado_regional` | Responsable comercial común a sus salas | `VARCHAR(120)` | No | — | — |

### `sala_venta`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_sala` | Identificador de sala | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_sala_venta` |
| `calle` | Calle de la dirección | `VARCHAR(120)` | No | — | Parte de `uq_sala_venta_direccion` |
| `numero` | Número o designación de puerta | `VARCHAR(20)` | No | — | Parte de `uq_sala_venta_direccion` |
| `dia_cierre` | Día semanal de cierre | `VARCHAR(10)` | No | — | `ck_sala_venta_dia_cierre`: lunes a domingo, sin tildes |
| `id_localidad` | Localidad de la sala | `INTEGER` | No | — | FK `fk_sala_venta_localidad`; parte de `uq_sala_venta_direccion` |

### `empleado`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cuit` | Identificador tributario del empleado | `cuit_dom` | No | — | PK `pk_empleado`; formato del dominio |
| `nombre` | Nombre del empleado | `VARCHAR(120)` | No | — | — |
| `fecha_ingreso` | Fecha de ingreso laboral | `DATE` | No | — | — |
| `salario` | Salario monetario | `NUMERIC(14,2)` | No | — | `ck_empleado_salario_positivo`: `> 0` |
| `id_sala` | Única sala en la que trabaja | `INTEGER` | No | — | FK `fk_empleado_sala_venta` |

## 4. Producción de uva

### `finca`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_finca` | Identificador interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_finca` |
| `nombre` | Nombre de la finca; no se presume único | `VARCHAR(120)` | No | — | — |
| `superficie_ha` | Superficie total en hectáreas | `NUMERIC(10,2)` | No | — | `ck_finca_superficie_positiva`: `> 0` |
| `id_departamento` | Departamento de ubicación | `INTEGER` | No | — | FK `fk_finca_departamento` |

### `cepa`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_cepa` | Identificador interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_cepa` |
| `nombre` | Nombre de variedad | `VARCHAR(100)` | No | — | `uq_cepa_nombre` |
| `tipo` | Clasificación cromática | `VARCHAR(6)` | No | — | `ck_cepa_tipo`: `tinta` o `blanca` |

### `parcela`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_finca` | Finca propietaria e identificadora | `INTEGER` | No | — | Parte de PK `pk_parcela`; FK `fk_parcela_finca` |
| `nro_parcela` | Número dentro de la finca | `INTEGER` | No | — | Parte de PK; `ck_parcela_numero_positivo`: `> 0` |
| `superficie_ha` | Superficie de parcela en hectáreas | `NUMERIC(10,2)` | No | — | `ck_parcela_superficie_positiva`: `> 0` |
| `anio_plantacion` | Año de plantación | `SMALLINT` | No | — | `ck_parcela_anio_plantacion_positivo`: `> 0` |
| `id_cepa` | Única cepa plantada | `INTEGER` | No | — | FK `fk_parcela_cepa` |

### `lote_uva`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `nro_lote` | Número global de lote, supuesto revisable | `BIGINT` | No | — | PK `pk_lote_uva` |
| `id_finca` | Finca de la parcela cosechada | `INTEGER` | No | — | Parte de FK compuesta `fk_lote_uva_parcela` y `uq_lote_uva_parcela_campania` |
| `nro_parcela` | Parcela dentro de la finca | `INTEGER` | No | — | Parte de FK compuesta y `uq_lote_uva_parcela_campania` |
| `campania` | Año de campaña | `SMALLINT` | No | — | `1900..9999`; parte del `UNIQUE` de cosecha |
| `fecha_cosecha` | Día de cosecha | `DATE` | No | — | `ck_lote_uva_fecha_campania`: su año coincide con campaña |
| `kilos` | Kilogramos cosechados | `NUMERIC(12,2)` | No | — | `ck_lote_uva_kilos_positivos`: `> 0` |
| `cuit_bodega` | Bodega destino | `cuit_dom` | No | — | FK `fk_lote_uva_bodega`; formato del dominio |

### `analisis_calidad`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_analisis` | Identificador de la medición | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_analisis_calidad` |
| `nro_lote` | Lote analizado | `BIGINT` | No | — | FK `fk_analisis_calidad_lote_uva` |
| `fecha_analisis` | Fecha del análisis | `DATE` | No | — | — |
| `grado_brix` | Concentración medida en grados Brix | `NUMERIC(5,2)` | No | — | `ck_analisis_calidad_brix_positivo`: `> 0` |
| `ph` | Medición de pH | `NUMERIC(4,2)` | No | — | `ck_analisis_calidad_ph`: `0..14` |
| `acidez_total` | Acidez total en g/L | `NUMERIC(6,2)` | No | — | `ck_analisis_calidad_acidez_no_negativa`: `>= 0` |

## 5. Bodegas y vinos

### `bodega`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cuit` | Identificador tributario natural | `cuit_dom` | No | — | PK `pk_bodega`; formato del dominio |
| `razon_social` | Razón social | `VARCHAR(150)` | No | — | — |
| `domicilio` | Domicilio | `VARCHAR(200)` | No | — | — |

### `vino`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_vino` | Código interno del producto | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_vino` |
| `nombre` | Nombre comercial | `VARCHAR(100)` | No | — | Parte de `uq_vino_identidad_comercial` |
| `tipo` | Tipo de vino | `VARCHAR(12)` | No | — | `ck_vino_tipo`: tinto, blanco, rosado o espumante |
| `anada` | Año de añada | `SMALLINT` | No | — | `ck_vino_anada`: `1900..9999`; parte de candidata |
| `volumen_ml` | Volumen de la presentación | `INTEGER` | No | — | `ck_vino_volumen_positivo`; parte de candidata |
| `graduacion` | Graduación alcohólica | `NUMERIC(4,2)` | No | — | `ck_vino_graduacion`: `5..20` |
| `precio` | Precio actual único en la red | `NUMERIC(14,2)` | No | — | `ck_vino_precio_positivo`: `> 0` |
| `cuit_bodega` | Bodega elaboradora | `cuit_dom` | No | — | FK `fk_vino_bodega`; parte de `uq_vino_identidad_comercial` |

### `composicion_vino`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_vino` | Vino compuesto | `BIGINT` | No | — | Parte de PK; FK `fk_composicion_vino_vino` |
| `id_cepa` | Cepa participante | `INTEGER` | No | — | Parte de PK; FK `fk_composicion_vino_cepa` |
| `porcentaje` | Porcentaje de corte de la cepa | `NUMERIC(5,2)` | No | — | `ck_composicion_vino_porcentaje`: `> 0` y `<= 100`; suma 100 pendiente |

### `maridaje`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_maridaje` | Identificador interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_maridaje` |
| `nombre` | Nombre de la recomendación | `VARCHAR(100)` | No | — | `uq_maridaje_nombre` |
| `temperatura_servicio_c` | Temperatura sugerida en °C | `NUMERIC(4,1)` | No | — | —; el enunciado no fija un rango |

### `vino_maridaje`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_vino` | Vino recomendado | `BIGINT` | No | — | Parte de PK; FK `fk_vino_maridaje_vino` |
| `id_maridaje` | Maridaje recomendado | `INTEGER` | No | — | Parte de PK; FK `fk_vino_maridaje_maridaje` |

## 6. Clientes y ventas

### `cliente`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_cliente` | Identificador interno | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_cliente`; parte de `uq_cliente_id_tipo` |
| `nombre_razon_social` | Nombre personal o razón social | `VARCHAR(150)` | No | — | — |
| `tipo_documento` | Tipo de documento | `VARCHAR(20)` | No | — | Parte de `uq_cliente_documento` |
| `nro_documento` | Número de documento | `VARCHAR(30)` | No | — | Parte de `uq_cliente_documento` |
| `direccion` | Dirección postal | `VARCHAR(200)` | No | — | — |
| `id_localidad` | Localidad del cliente | `INTEGER` | No | — | FK `fk_cliente_localidad` |
| `fecha_alta` | Día de alta | `DATE` | No | `CURRENT_DATE` | — |
| `tipo` | Discriminador de subtipo | `tipo_cliente` | No | — | Parte de `uq_cliente_id_tipo` (superclave destino de las FK de subtipos); `RESTRICT` impide cambiarlo si existe fila de subtipo |
| `descuento_excepcion` | Excepción individual al descuento base | `NUMERIC(5,2)` | Sí | `NULL` implícito | `ck_cliente_descuento_excepcion`: sólo 35 para tipo exportador |

### `socio_club`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_cliente` | Cliente que pertenece al subtipo | `BIGINT` | No | — | PK `pk_socio_club`; parte de FK compuesta `fk_socio_club_cliente` |
| `tipo` | Discriminador fijo del subtipo | `tipo_cliente` | No | `'socio'` | `ck_socio_club_tipo`: sólo `socio`; parte de FK compuesta `fk_socio_club_cliente` |

### `distribuidor`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_cliente` | Cliente que pertenece al subtipo | `BIGINT` | No | — | PK `pk_distribuidor`; parte de FK compuesta `fk_distribuidor_cliente` |
| `tipo` | Discriminador fijo del subtipo | `tipo_cliente` | No | `'distribuidor'` | `ck_distribuidor_tipo`: sólo `distribuidor`; parte de FK compuesta `fk_distribuidor_cliente` |
| `zona_cobertura` | Zona comercial cubierta | `VARCHAR(150)` | No | — | — |
| `nro_habilitacion` | Habilitación del distribuidor | `VARCHAR(50)` | No | — | `uq_distribuidor_habilitacion` |

### `exportador`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_cliente` | Cliente que pertenece al subtipo | `BIGINT` | No | — | PK `pk_exportador`; parte de FK compuesta `fk_exportador_cliente` |
| `tipo` | Discriminador fijo del subtipo | `tipo_cliente` | No | `'exportador'` | `ck_exportador_tipo`: sólo `exportador`; parte de FK compuesta `fk_exportador_cliente` |
| `pais_destino_principal` | País principal de exportación | `VARCHAR(100)` | No | — | — |

### `permiso_exportacion`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `codigo_permiso` | Código global supuesto del permiso | `VARCHAR(50)` | No | — | PK `pk_permiso_exportacion` |
| `id_exportador` | Exportador titular | `BIGINT` | No | — | FK `fk_permiso_exportacion_exportador` |
| `fecha_emision` | Día de emisión | `DATE` | No | — | Parte de `ck_permiso_exportacion_fechas` |
| `fecha_vencimiento` | Día de vencimiento | `DATE` | No | — | Debe ser posterior a emisión |

### `comprobante`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `nro_comprobante` | Número global del comprobante | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_comprobante` |
| `fecha` | Instante de venta | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — |
| `id_cliente` | Comprador | `BIGINT` | No | — | FK `fk_comprobante_cliente` |
| `id_sala` | Sala de venta | `INTEGER` | No | — | FK `fk_comprobante_sala_venta` |
| `subtotal` | Importe bruto de cabecera | `NUMERIC(14,2)` | No | `0` | `>= 0`; parte de `ck_comprobante_importes` |
| `descuento` | Descuento monetario total | `NUMERIC(14,2)` | No | `0` | Entre 0 y subtotal |
| `total` | Importe neto | `NUMERIC(14,2)` | No | `0` | `total = subtotal - descuento` |

### `renglon_comprobante`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `nro_comprobante` | Cabecera de venta | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_comprobante_comprobante` |
| `cod_vino` | Vino vendido | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_comprobante_vino` |
| `cantidad` | Botellas vendidas | `INTEGER` | No | — | `ck_renglon_comprobante_cantidad_positiva`: `> 0` |
| `precio_unitario` | Precio histórico por botella | `NUMERIC(14,2)` | No | — | `ck_renglon_comprobante_precio_positivo`: `> 0` |
| `descuento_porcentaje` | Porcentaje histórico aplicado | `NUMERIC(5,2)` | No | — | `ck_renglon_comprobante_descuento`: `0..100` |
| `subtotal` | Neto del renglón | `NUMERIC(14,2)` | No | — | `ck_renglon_comprobante_subtotal`: fórmula redondeada a 2 decimales |

## 7. Logística, stock y auditoría

### `transportista`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_transportista` | Código interno | `INTEGER` | No | `IDENTITY ALWAYS` | PK `pk_transportista` |
| `razon_social` | Razón social | `VARCHAR(150)` | No | — | — |
| `cuit` | Identificador tributario | `cuit_dom` | No | — | `uq_transportista_cuit`; formato del dominio |
| `email` | Correo de contacto | `VARCHAR(254)` | No | — | — |
| `telefono` | Teléfono de contacto | `VARCHAR(30)` | No | — | — |
| `domicilio` | Domicilio | `VARCHAR(200)` | No | — | — |

### `transportista_localidad`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_transportista` | Transportista que presta servicio | `INTEGER` | No | — | Parte de PK; FK `fk_transportista_localidad_transportista` |
| `id_localidad` | Localidad cubierta | `INTEGER` | No | — | Parte de PK; FK `fk_transportista_localidad_localidad` |

### `ingreso`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_ingreso` | Código del documento | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_ingreso` |
| `fecha` | Instante de creación | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — |
| `estado` | Estado del circuito | `estado_documento` | No | `'en_confeccion'` | Valores cerrados por ENUM; transiciones pendientes |
| `cod_transportista` | Empresa que trasladó | `INTEGER` | No | — | FK `fk_ingreso_transportista` |
| `cuit_bodega` | Bodega de origen | `cuit_dom` | No | — | FK `fk_ingreso_bodega`; formato del dominio |

### `renglon_ingreso`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_ingreso` | Cabecera de ingreso | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_ingreso_ingreso` |
| `cod_vino` | Vino recibido | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_ingreso_vino` |
| `cantidad` | Botellas ingresadas | `INTEGER` | No | — | `ck_renglon_ingreso_cantidad_positiva`: `> 0` |

### `transferencia`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `nro_transferencia` | Número de solicitud | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_transferencia` |
| `id_sala` | Sala solicitante | `INTEGER` | No | — | FK `fk_transferencia_sala_venta` |
| `fecha_confeccion` | Día de confección | `DATE` | No | `CURRENT_DATE` | Inmutabilidad pendiente de trigger |
| `estado` | Estado del circuito | `estado_documento` | No | `'en_confeccion'` | Valores cerrados por ENUM; transiciones pendientes |

### `renglon_transferencia`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `nro_transferencia` | Cabecera de transferencia | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_transferencia_transferencia` |
| `cod_vino` | Vino solicitado | `BIGINT` | No | — | Parte de PK; FK `fk_renglon_transferencia_vino` |
| `cantidad` | Botellas solicitadas | `INTEGER` | No | — | `ck_renglon_transferencia_cantidad_positiva`: `> 0` |

### `stock_sala`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_sala` | Sala que mantiene el saldo | `INTEGER` | No | — | Parte de PK; FK `fk_stock_sala_sala_venta` |
| `cod_vino` | Vino del saldo | `BIGINT` | No | — | Parte de PK; FK `fk_stock_sala_vino` |
| `cantidad` | Botellas disponibles | `INTEGER` | No | `0` | `ck_stock_sala_cantidad_no_negativa`: `>= 0` |

### `stock_deposito`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `cod_vino` | Vino del saldo central | `BIGINT` | No | — | PK `pk_stock_deposito`; FK `fk_stock_deposito_vino` |
| `cantidad` | Botellas disponibles | `INTEGER` | No | `0` | `ck_stock_deposito_cantidad_no_negativa`: `>= 0` |

### `auditoria_precio`

| Columna | Descripción | Tipo | Nulo | Por defecto/generación | Restricciones |
|---|---|---|---:|---|---|
| `id_auditoria` | Identificador del evento | `BIGINT` | No | `IDENTITY ALWAYS` | PK `pk_auditoria_precio` |
| `cod_vino` | Vino modificado | `BIGINT` | No | — | FK `fk_auditoria_precio_vino` |
| `precio_anterior` | Precio previo | `NUMERIC(14,2)` | No | — | `ck_auditoria_precio_valores`: `> 0` |
| `precio_nuevo` | Precio resultante | `NUMERIC(14,2)` | No | — | `> 0` y distinto del anterior |
| `fecha_hora` | Instante auditado | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — |
| `usuario_bd` | Rol PostgreSQL que realizó el cambio | `VARCHAR(63)` | No | `CURRENT_USER` | — |

## 8. Reglas deliberadamente no atribuidas a una columna

El diccionario describe estructura física, no afirma que las siguientes reglas ya estén implementadas: suma 100 % de composición; mínimos de hijos; totalidad de la jerarquía de clientes (la exclusividad sí está protegida por las FK compuestas); calificación de U6; cálculo agregado de cabecera; stock suficiente; transiciones e impacto único; bloqueo de renglones; fecha inmutable; auditoría automática. Sus columnas existen, pero sus mecanismos de funciones/procedimientos/triggers pertenecen a la etapa siguiente.
