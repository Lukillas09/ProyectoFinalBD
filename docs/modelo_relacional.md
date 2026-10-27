# Modelo relacional

## 1. Convenciones

- `PK(...)`: clave primaria.
- `AK(...)`: clave candidata alternativa implementada con `UNIQUE` y `NOT NULL`.
- `FK(...) -> TABLA(...)`: clave foránea.
- Un atributo subrayado conceptualmente se representa aquí dentro de `PK` o `AK`.
- Todas las relaciones pertenecen al esquema `bodegas`.
- `cuit_dom` es un dominio `VARCHAR(11)` de once dígitos; `estado_documento` y `tipo_cliente` son enumerados.

El modelo usa claves subrogadas cuando el enunciado no ofrece un identificador estable y conserva las claves naturales declaradas como candidatas. Agregar un ID no reemplaza la búsqueda de candidatas ni demuestra normalización.

## 2. Relaciones resultantes

### 2.1 Territorio, red comercial y personal

```text
DEPARTAMENTO(
  id_departamento, nombre, provincia,
  PK(id_departamento), AK(nombre, provincia)
)

LOCALIDAD(
  id_localidad, codigo_postal, nombre, provincia, encargado_regional,
  PK(id_localidad), AK(provincia, nombre, codigo_postal)
)

SALA_VENTA(
  id_sala, calle, numero, dia_cierre, id_localidad,
  PK(id_sala), AK(id_localidad, calle, numero),
  FK(id_localidad) -> LOCALIDAD(id_localidad)
)

EMPLEADO(
  cuit, nombre, fecha_ingreso, salario, id_sala,
  PK(cuit), FK(id_sala) -> SALA_VENTA(id_sala)
)
```

`encargado_regional` se guarda en `LOCALIDAD`, no en `SALA_VENTA`: la dependencia relevante es `id_localidad -> encargado_regional`. Nombre y código postal no son únicos aisladamente.

### 2.2 Producción de uva

```text
FINCA(
  id_finca, nombre, superficie_ha, id_departamento,
  PK(id_finca),
  FK(id_departamento) -> DEPARTAMENTO(id_departamento)
)

CEPA(
  id_cepa, nombre, tipo,
  PK(id_cepa), AK(nombre)
)

PARCELA(
  id_finca, nro_parcela, superficie_ha, anio_plantacion, id_cepa,
  PK(id_finca, nro_parcela),
  FK(id_finca) -> FINCA(id_finca),
  FK(id_cepa) -> CEPA(id_cepa)
)

LOTE_UVA(
  nro_lote, id_finca, nro_parcela, campania, fecha_cosecha,
  kilos, cuit_bodega,
  PK(nro_lote), AK(id_finca, nro_parcela, campania),
  FK(id_finca, nro_parcela) -> PARCELA(id_finca, nro_parcela),
  FK(cuit_bodega) -> BODEGA(cuit)
)

ANALISIS_CALIDAD(
  id_analisis, nro_lote, fecha_analisis, grado_brix, ph, acidez_total,
  PK(id_analisis), FK(nro_lote) -> LOTE_UVA(nro_lote)
)
```

`PARCELA` conserva la clave de la entidad propietaria porque es débil. La candidata de `LOTE_UVA` implementa RN-04. `campania` es un año, no una tabla, porque la consigna no le asigna atributos propios.

### 2.3 Bodegas, vinos y recomendaciones

```text
BODEGA(
  cuit, razon_social, domicilio,
  PK(cuit)
)

VINO(
  cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega,
  PK(cod_vino), AK(cuit_bodega, nombre, anada, volumen_ml),
  FK(cuit_bodega) -> BODEGA(cuit)
)

COMPOSICION_VINO(
  cod_vino, id_cepa, porcentaje,
  PK(cod_vino, id_cepa),
  FK(cod_vino) -> VINO(cod_vino),
  FK(id_cepa) -> CEPA(id_cepa)
)

MARIDAJE(
  id_maridaje, nombre, temperatura_servicio_c,
  PK(id_maridaje), AK(nombre)
)

VINO_MARIDAJE(
  cod_vino, id_maridaje,
  PK(cod_vino, id_maridaje),
  FK(cod_vino) -> VINO(cod_vino),
  FK(id_maridaje) -> MARIDAJE(id_maridaje)
)
```

La temperatura depende del maridaje, tal como dice la consigna; no se trasladó a `VINO_MARIDAJE`. `COMPOSICION_VINO.porcentaje` depende del par completo. La suma 100 % no se deduce de la PK ni del `CHECK` por fila y queda para un trigger diferido.

### 2.4 Clientes, especialización y ventas

```text
CLIENTE(
  id_cliente, nombre_razon_social, tipo_documento, nro_documento,
  direccion, id_localidad, fecha_alta, tipo, descuento_excepcion,
  PK(id_cliente), AK(tipo_documento, nro_documento),
  UNIQUE(id_cliente, tipo),
  FK(id_localidad) -> LOCALIDAD(id_localidad)
)

SOCIO_CLUB(
  id_cliente, tipo,
  PK(id_cliente), CHECK(tipo = 'socio'),
  FK(id_cliente, tipo) -> CLIENTE(id_cliente, tipo)
)

DISTRIBUIDOR(
  id_cliente, tipo, zona_cobertura, nro_habilitacion,
  PK(id_cliente), AK(nro_habilitacion), CHECK(tipo = 'distribuidor'),
  FK(id_cliente, tipo) -> CLIENTE(id_cliente, tipo)
)

EXPORTADOR(
  id_cliente, tipo, pais_destino_principal,
  PK(id_cliente), CHECK(tipo = 'exportador'),
  FK(id_cliente, tipo) -> CLIENTE(id_cliente, tipo)
)

PERMISO_EXPORTACION(
  codigo_permiso, id_exportador, fecha_emision, fecha_vencimiento,
  PK(codigo_permiso),
  FK(id_exportador) -> EXPORTADOR(id_cliente)
)

COMPROBANTE(
  nro_comprobante, fecha, id_cliente, id_sala, subtotal, descuento, total,
  PK(nro_comprobante),
  FK(id_cliente) -> CLIENTE(id_cliente),
  FK(id_sala) -> SALA_VENTA(id_sala)
)

RENGLON_COMPROBANTE(
  nro_comprobante, cod_vino, cantidad, precio_unitario,
  descuento_porcentaje, subtotal,
  PK(nro_comprobante, cod_vino),
  FK(nro_comprobante) -> COMPROBANTE(nro_comprobante),
  FK(cod_vino) -> VINO(cod_vino)
)
```

`UNIQUE(id_cliente, tipo)` no es una clave candidata nueva, porque `id_cliente` ya es clave por sí solo. Es una superclave declarada para que las FK compuestas de los subtipos puedan referenciarla. Cada subtipo repite el discriminador como constante: con ese `CHECK`, la FK sólo encuentra el par `(id_cliente, tipo)` si el cliente declara ese mismo tipo. `PERMISO_EXPORTACION` sigue referenciando `EXPORTADOR(id_cliente)`, que es PK, y ahora además queda garantizado que esa fila pertenece a un cliente de tipo exportador.

`descuento_excepcion` es nullable: sin valor, una función futura devolverá el descuento base de `tipo` (10/20/30); con valor sólo admite el 35 % de un exportador. El renglón copia el porcentaje efectivamente aplicado para conservar historia.

En `COMPROBANTE`, `subtotal` es el bruto de la venta, `descuento` un importe monetario y `total` el neto. En `RENGLON_COMPROBANTE`, `subtotal` es el neto redondeado a dos decimales. El DDL protege la aritmética dentro de cada fila, pero la igualdad entre la cabecera y el conjunto de renglones requiere un trigger.

### 2.5 Logística, stock y auditoría

```text
TRANSPORTISTA(
  cod_transportista, razon_social, cuit, email, telefono, domicilio,
  PK(cod_transportista), AK(cuit)
)

TRANSPORTISTA_LOCALIDAD(
  cod_transportista, id_localidad,
  PK(cod_transportista, id_localidad),
  FK(cod_transportista) -> TRANSPORTISTA(cod_transportista),
  FK(id_localidad) -> LOCALIDAD(id_localidad)
)

INGRESO(
  cod_ingreso, fecha, estado, cod_transportista, cuit_bodega,
  PK(cod_ingreso),
  FK(cod_transportista) -> TRANSPORTISTA(cod_transportista),
  FK(cuit_bodega) -> BODEGA(cuit)
)

RENGLON_INGRESO(
  cod_ingreso, cod_vino, cantidad,
  PK(cod_ingreso, cod_vino),
  FK(cod_ingreso) -> INGRESO(cod_ingreso),
  FK(cod_vino) -> VINO(cod_vino)
)

TRANSFERENCIA(
  nro_transferencia, id_sala, fecha_confeccion, estado,
  PK(nro_transferencia),
  FK(id_sala) -> SALA_VENTA(id_sala)
)

RENGLON_TRANSFERENCIA(
  nro_transferencia, cod_vino, cantidad,
  PK(nro_transferencia, cod_vino),
  FK(nro_transferencia) -> TRANSFERENCIA(nro_transferencia),
  FK(cod_vino) -> VINO(cod_vino)
)

STOCK_SALA(
  id_sala, cod_vino, cantidad,
  PK(id_sala, cod_vino),
  FK(id_sala) -> SALA_VENTA(id_sala),
  FK(cod_vino) -> VINO(cod_vino)
)

STOCK_DEPOSITO(
  cod_vino, cantidad,
  PK(cod_vino), FK(cod_vino) -> VINO(cod_vino)
)

AUDITORIA_PRECIO(
  id_auditoria, cod_vino, precio_anterior, precio_nuevo,
  fecha_hora, usuario_bd,
  PK(id_auditoria), FK(cod_vino) -> VINO(cod_vino)
)
```

No existe `DEPOSITO` porque sólo hay uno y no tiene atributos. Tampoco existe una relación `LOTE_UVA`–`VINO`: sería una extensión de trazabilidad no respaldada por el escenario.

### 2.6 Relación técnica

```text
SCHEMA_MIGRATION(
  archivo, checksum_sha256, aplicada_en,
  PK(archivo)
)
```

No pertenece al dominio; registra la aplicación y el contenido de los archivos SQL. El runner la crea mediante `001_esquema.sql` y la API no recibe permisos sobre ella.

## 3. Comparación del mapeo de la jerarquía Cliente

| Alternativa del material | Ventajas | Desventajas en este caso |
|---|---|---|
| Una sola tabla con discriminador | Lectura simple; una FK desde comprobante; totalidad visible en una fila | `zona_cobertura`, `nro_habilitacion` y `pais_destino_principal` quedarían nulos según el tipo; se necesitan `CHECK` condicionales y se mezclan conceptos no aplicables. |
| Sólo una tabla por subtipo | No hay nulos inaplicables; el tipo surge de la tabla | Duplica nombre, documento, dirección, localidad y alta; comprobante necesitaría tres FKs alternativas o una abstracción artificial; actualizar datos comunes genera anomalías. Sólo es razonable para una jerarquía total/exclusiva con poco comportamiento común, que no es este caso. |
| Supertipo más una tabla por subtipo | Datos comunes una vez; atributos específicos sin nulos; FKs uniformes hacia `CLIENTE`; permisos referencian exactamente a `EXPORTADOR` | Inserta en dos tablas y las FKs ordinarias no pueden exigir por sí solas “exactamente una tabla hija”. Requiere una operación atómica y un constraint trigger diferido para la totalidad. |

Se elige supertipo más subtipos. `CLIENTE.tipo` se conserva como discriminador porque RN-06 y las consultas agrupan por tipo.

La regla “exactamente un subtipo” se divide en dos partes con mecanismos distintos:

- **Exclusividad y coincidencia (a lo sumo un subtipo, el declarado):** se protege ya, de forma declarativa. Cada subtipo tiene `tipo` constante (`CHECK` y `DEFAULT`) y una FK compuesta `(id_cliente, tipo) -> CLIENTE(id_cliente, tipo)`. Un socio no puede insertarse como exportador, un cliente no puede estar en dos subtipos y `CLIENTE.tipo` no puede cambiar mientras exista la fila del subtipo (`ON UPDATE RESTRICT`).
- **Totalidad (al menos un subtipo):** una FK sólo puede exigir que exista el padre, no el hijo. Queda pendiente para un constraint trigger `DEFERRABLE INITIALLY DEFERRED` en la Etapa 2, que se verifique al confirmar la transacción que inserta cliente y subtipo.

**Alternativa descartada para la exclusividad:** un trigger en cada subtipo que consulte `CLIENTE.tipo` y las otras dos tablas. Se prefirió el mecanismo declarativo porque PostgreSQL lo verifica en todos los accesos, incluso durante una carga masiva que deshabilite los triggers de usuario (`DISABLE TRIGGER USER`); además no depende de código procedural ni de su orden de ejecución, no tiene condiciones de carrera entre sesiones concurrentes que inserten el mismo cliente en dos subtipos, y el catálogo lo documenta por sí solo. Su costo es una columna constante por subtipo y una superclave `UNIQUE` adicional en `CLIENTE`.

## 4. Restricciones relacionales relevantes

### 4.1 Claves candidatas adicionales

Además de todas las PK, el SQL implementa once `UNIQUE`. Diez son claves candidatas alternativas:

1. departamento `(nombre, provincia)`;
2. localidad `(provincia, nombre, codigo_postal)`;
3. sala `(id_localidad, calle, numero)`;
4. cepa `nombre`;
5. lote `(id_finca, nro_parcela, campania)`;
6. vino `(cuit_bodega, nombre, anada, volumen_ml)`;
7. maridaje `nombre`;
8. cliente `(tipo_documento, nro_documento)`;
9. distribuidor `nro_habilitacion`;
10. transportista `cuit`.

La undécima, `uq_cliente_id_tipo (id_cliente, tipo)`, es una superclave, no una candidata: existe sólo como destino de las FK compuestas de los subtipos.

Todos sus componentes son `NOT NULL`, de modo que en PostgreSQL representan candidatas efectivas y no permiten duplicados a través de valores nulos.

### 4.2 Dominios, controles y valores iniciales

- `cuit_dom` exige exactamente once dígitos.
- `estado_documento` admite `en_confeccion`, `terminado`, `procesado`.
- `tipo_cliente` admite `socio`, `distribuidor`, `exportador`; en cada subtipo, `tipo` admite un único valor.
- Superficies, kilos, cantidades de movimiento, salarios y precios son positivos; stocks e importes agregados pueden ser cero.
- Graduación está entre 5 y 20; porcentaje de composición en `(0,100]`; descuento histórico en `[0,100]`.
- La campaña coincide con el año de cosecha y el permiso vence después de su emisión.
- Estado inicial de ingreso/transferencia: `en_confeccion`; alta/confección usan fecha actual; eventos usan instante actual; stocks e importes de cabecera empiezan en cero.

Hay más de los mínimos exigidos. Conteo obtenido de `pg_constraint` y `pg_attrdef` sobre el esquema `bodegas`: 11 `UNIQUE`, 36 `CHECK` (34 de negocio, 1 de la tabla técnica y 1 del dominio `cuit_dom`) y 16 columnas con `DEFAULT`.

## 5. Acciones referenciales

La política general es:

- `RESTRICT` en maestros con historia, movimientos, stock o auditoría;
- `CASCADE` al borrar una cabecera hacia renglones que no tienen significado independiente, una especialización hacia sus datos propios y una entidad hacia asociaciones puras;
- `ON UPDATE CASCADE` sólo cuando una clave natural o compuesta puede corregirse; los IDs generados no se actualizan.

| FK | `ON UPDATE` | `ON DELETE` | Motivo |
|---|---|---|---|
| sala → localidad | `RESTRICT` | `RESTRICT` | Sala requiere localidad; no borrar territorio utilizado. |
| empleado → sala | `RESTRICT` | `RESTRICT` | Evita dejar o borrar personal silenciosamente. |
| finca → departamento | `RESTRICT` | `RESTRICT` | Catálogo territorial utilizado. |
| parcela → finca | `CASCADE` | `CASCADE` | La parcela es débil y su identidad incluye la finca. Un lote que la referencia puede bloquear la cascada. |
| parcela → cepa | `RESTRICT` | `RESTRICT` | D2 sólo permite borrar cepas no usadas. |
| lote → parcela | `CASCADE` | `RESTRICT` | Una corrección de la clave débil se propaga; la cosecha histórica impide borrar parcela. |
| lote → bodega | `CASCADE` | `RESTRICT` | CUIT natural corregible; RN-14 impide borrar bodega con movimientos. |
| análisis → lote | `CASCADE` | `CASCADE` | Medición dependiente del lote. |
| vino → bodega | `CASCADE` | `RESTRICT` | CUIT natural corregible; conserva elaboradora usada. |
| composición → vino | `RESTRICT` | `CASCADE` | Asociación dependiente del vino. |
| composición → cepa | `RESTRICT` | `RESTRICT` | Impide borrar una cepa que compone vinos. |
| vino-maridaje → vino | `RESTRICT` | `CASCADE` | Asociación pura dependiente. |
| vino-maridaje → maridaje | `RESTRICT` | `CASCADE` | Borrar catálogo retira sus asociaciones. |
| cliente → localidad | `RESTRICT` | `RESTRICT` | No deja clientes sin localidad. |
| cada subtipo `(id_cliente, tipo)` → cliente `(id_cliente, tipo)` | `RESTRICT` | `CASCADE` | Datos de especialización sin vida independiente. `RESTRICT` impide cambiar `cliente.tipo` dejando un subtipo incoherente; un cambio de tipo debe borrar la fila vieja y crear la nueva en la misma operación. |
| permiso → exportador | `RESTRICT` | `CASCADE` | Permiso dependiente del exportador. |
| comprobante → cliente/sala | `RESTRICT` | `RESTRICT` | Preserva la venta; D4/D6 sólo borran clientes sin compras. |
| renglón comprobante → cabecera | `RESTRICT` | `CASCADE` | D1 borra cabecera e hijos como unidad histórica. |
| renglón comprobante → vino | `RESTRICT` | `RESTRICT` | RN-14 conserva vino vendido. |
| cobertura → transportista/localidad | `RESTRICT` | `CASCADE` | Asociación N:M sin significado independiente. |
| ingreso → transportista | `RESTRICT` | `RESTRICT` | RN-14 conserva transportista con movimientos. |
| ingreso → bodega | `CASCADE` | `RESTRICT` | Propaga corrección de CUIT y conserva origen histórico. |
| renglón ingreso → ingreso | `RESTRICT` | `CASCADE` | D5 borra ingreso procesado y sus renglones. |
| renglón ingreso → vino | `RESTRICT` | `RESTRICT` | RN-14 conserva vino con movimientos. |
| transferencia → sala | `RESTRICT` | `RESTRICT` | Conserva solicitudes históricas. |
| renglón transferencia → transferencia | `RESTRICT` | `CASCADE` | Dependencia de cabecera. |
| renglón transferencia → vino | `RESTRICT` | `RESTRICT` | RN-14 conserva vino con movimientos. |
| stock sala → sala/vino | `RESTRICT` | `RESTRICT` | No descarta existencias por borrar un maestro. |
| stock depósito → vino | `RESTRICT` | `RESTRICT` | No descarta existencia central. |
| auditoría → vino | `RESTRICT` | `RESTRICT` | No pierde historial de precio. |

No se usa `SET NULL`: todas estas relaciones son obligatorias y un nulo transformaría una fila válida en información incompleta.

## 6. Restricciones entre filas y tablas (Etapa 2)

El esquema relacional básico no alcanza para las reglas que dependen de otras filas o tablas: suma de composición, totalidad de la jerarquía de cliente, descuento efectivo, totales agregados, stock suficiente, transiciones, bloqueo de renglones, procesamiento atómico, fecha inmutable y auditoría automática. La Etapa 2 las implementa con funciones, procedimientos y triggers (migraciones 003 a 007). La relación de cada regla con su objeto y su prueba está en `docs/trazabilidad.md`.
