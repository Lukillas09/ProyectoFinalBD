# Normalización hasta tercera forma normal

## 1. Método aplicado

Se sigue el orden del material de la cátedra para **cada relación resultante**, no para la entidad conceptual ni para un listado de columnas previo:

1. definir qué representa una fila;
2. enumerar todas las claves candidatas conocidas;
3. clasificar como primos los atributos que pertenecen a alguna candidata y como no primos los restantes;
4. escribir las dependencias funcionales (DF) relevantes;
5. verificar 1FN: un valor atómico del dominio por celda y ausencia de grupos repetidos;
6. verificar 2FN: estando en 1FN, ningún atributo no primo depende de una parte propia de una clave candidata compuesta;
7. verificar 3FN: estando en 2FN, para toda DF no trivial `X -> A`, `X` es superclave o `A` es primo. En términos prácticos, se buscan dependencias transitivas entre atributos no clave.

Un ID generado no demuestra ninguna forma normal. Sólo se elige como identificador cuando las claves naturales serían inestables, desconocidas o demasiado anchas; las demás dependencias continúan analizándose.

## 2. Significado de fila, claves y atributos primos

`K1`, `K2`, etc. son claves candidatas completas. Los atributos separados por `+` forman una clave compuesta.

| Relación | Una fila representa | Claves candidatas | Atributos primos | Atributos no primos |
|---|---|---|---|---|
| `departamento` | Un departamento dentro de una provincia | K1 `id_departamento`; K2 `nombre + provincia` | id, nombre, provincia | — |
| `localidad` | Una localidad postal/comercial | K1 `id_localidad`; K2 `provincia + nombre + codigo_postal` | id, provincia, nombre, código postal | encargado regional |
| `sala_venta` | Un local físico | K1 `id_sala`; K2 `id_localidad + calle + numero` | id, localidad, calle, número | día de cierre |
| `empleado` | Un empleado asignado a una sala | K1 `cuit` | CUIT | nombre, ingreso, salario, sala |
| `finca` | Una finca agrícola | K1 `id_finca` | id | nombre, superficie, departamento |
| `cepa` | Una variedad de uva | K1 `id_cepa`; K2 `nombre` | id, nombre | tipo |
| `parcela` | La parcela numerada dentro de una finca | K1 `id_finca + nro_parcela` | finca, número | superficie, año plantación, cepa |
| `bodega` | Una bodega elaboradora | K1 `cuit` | CUIT | razón social, domicilio |
| `lote_uva` | La cosecha de una parcela en una campaña | K1 `nro_lote`; K2 `id_finca + nro_parcela + campania` | lote, finca, parcela, campaña | fecha cosecha, kilos, bodega |
| `analisis_calidad` | Una medición de calidad de un lote | K1 `id_analisis` | id | lote, fecha, Brix, pH, acidez |
| `vino` | Un producto/presentación elaborado por una bodega | K1 `cod_vino`; K2 `cuit_bodega + nombre + anada + volumen_ml` | código, bodega, nombre, añada, volumen | tipo, graduación, precio actual |
| `composicion_vino` | La proporción de una cepa en un vino | K1 `cod_vino + id_cepa` | vino, cepa | porcentaje |
| `maridaje` | Una recomendación y su temperatura | K1 `id_maridaje`; K2 `nombre` | id, nombre | temperatura |
| `vino_maridaje` | Una recomendación asociada a un vino | K1 `cod_vino + id_maridaje` | todos | — |
| `cliente` | Los datos comunes de un comprador | K1 `id_cliente`; K2 `tipo_documento + nro_documento` | id, tipo documento, número | nombre/razón social, dirección, localidad, alta, tipo cliente, excepción descuento |
| `socio_club` | La pertenencia del cliente al subtipo socio | K1 `id_cliente` | id | tipo (constante `socio`) |
| `distribuidor` | Los datos específicos de un distribuidor | K1 `id_cliente`; K2 `nro_habilitacion` | cliente, habilitación | tipo (constante `distribuidor`), zona de cobertura |
| `exportador` | Los datos específicos de un exportador | K1 `id_cliente` | cliente | tipo (constante `exportador`), país principal |
| `permiso_exportacion` | Un permiso de un exportador | K1 `codigo_permiso` | código | exportador, emisión, vencimiento |
| `comprobante` | La cabecera de una venta | K1 `nro_comprobante` | número | fecha, cliente, sala, subtotal, descuento, total |
| `renglon_comprobante` | La aparición de un vino en una venta | K1 `nro_comprobante + cod_vino` | comprobante, vino | cantidad, precio histórico, descuento histórico, subtotal neto |
| `transportista` | Una empresa transportista | K1 `cod_transportista`; K2 `cuit` | código, CUIT | razón social, email, teléfono, domicilio |
| `transportista_localidad` | Una cobertura territorial | K1 `cod_transportista + id_localidad` | todos | — |
| `ingreso` | Un documento de entrada al depósito | K1 `cod_ingreso` | código | fecha, estado, transportista, bodega |
| `renglon_ingreso` | Un vino incluido en un ingreso | K1 `cod_ingreso + cod_vino` | ingreso, vino | cantidad |
| `transferencia` | Una solicitud del depósito a una sala | K1 `nro_transferencia` | número | sala, fecha, estado |
| `renglon_transferencia` | Un vino solicitado en una transferencia | K1 `nro_transferencia + cod_vino` | transferencia, vino | cantidad |
| `stock_sala` | La existencia actual de un vino en una sala | K1 `id_sala + cod_vino` | sala, vino | cantidad |
| `stock_deposito` | La existencia central actual de un vino | K1 `cod_vino` | vino | cantidad |
| `auditoria_precio` | Un evento de modificación de precio | K1 `id_auditoria` | id | vino, precios, fecha-hora, usuario |
| `schema_migration` | La aplicación de un archivo de migración | K1 `archivo` | archivo | checksum, instante aplicado |

No se declaran como candidatas combinaciones “probablemente únicas” sin respaldo. Por ejemplo, `finca.nombre`, `bodega.razon_social`, email y teléfono pueden repetirse o cambiar.

## 3. Dependencias funcionales relevantes

La forma abreviada `K -> resto` significa que cada candidata de la fila anterior determina todos los atributos de su relación.

| Relación o grupo | Dependencias funcionales no triviales relevantes |
|---|---|
| `departamento` | `id_departamento -> nombre, provincia`; `(nombre, provincia) -> id_departamento` |
| `localidad` | `id_localidad -> provincia, nombre, codigo_postal, encargado_regional`; `(provincia, nombre, codigo_postal) -> id_localidad, encargado_regional`. **No** se supone `codigo_postal -> localidad` ni `nombre -> localidad`. |
| `sala_venta` | `id_sala -> id_localidad, calle, numero, dia_cierre`; `(id_localidad, calle, numero) -> id_sala, dia_cierre` |
| `cepa` | `id_cepa -> nombre, tipo`; `nombre -> id_cepa, tipo` |
| `parcela` | `(id_finca, nro_parcela) -> superficie_ha, anio_plantacion, id_cepa` |
| `lote_uva` | `nro_lote -> parcela, campania, fecha, kilos, bodega`; `(parcela, campania) -> nro_lote, fecha, kilos, bodega`; además `fecha_cosecha -> campania` por la decisión de representar la campaña como el año de esa fecha. |
| `vino` | `cod_vino -> cuit_bodega, nombre, anada, volumen_ml, tipo, graduacion, precio`; `(cuit_bodega, nombre, anada, volumen_ml) -> cod_vino, tipo, graduacion, precio` |
| `composicion_vino` | `(cod_vino, id_cepa) -> porcentaje` |
| `maridaje` | `id_maridaje -> nombre, temperatura`; `nombre -> id_maridaje, temperatura` |
| `cliente` | `id_cliente ->` todos los datos comunes; `(tipo_documento, nro_documento) ->` todos los datos comunes. No se guarda una columna de descuento base, por lo que no aparece `tipo -> descuento_base` dentro de la relación. |
| `distribuidor` | `id_cliente -> tipo, zona, habilitacion`; `nro_habilitacion -> id_cliente, tipo, zona` |
| Subtipos de cliente | `id_cliente -> tipo` en `socio_club`, `distribuidor` y `exportador`. Como el `CHECK` fija un único valor, también vale la DF degenerada `∅ -> tipo` (el valor no depende de nada). `(id_cliente, tipo)` es superclave, no candidata. Ver 6.3. |
| `comprobante` | `nro_comprobante -> fecha, cliente, sala, subtotal, descuento, total`; adicionalmente `(subtotal, descuento) -> total` por la fórmula almacenada. |
| `renglon_comprobante` | `(nro_comprobante, cod_vino) -> cantidad, precio_unitario, descuento_porcentaje, subtotal`; además `(cantidad, precio_unitario, descuento_porcentaje) -> subtotal` por la fórmula. |
| `transportista` | `cod_transportista -> cuit, razon_social, email, telefono, domicilio`; `cuit -> cod_transportista, razon_social, email, telefono, domicilio` |
| Asociativas y renglones restantes | Su PK compuesta determina el atributo `cantidad` cuando existe; las tablas sin atributos no primos sólo tienen la dependencia de identidad. |
| Entidades con una candidata simple | En `empleado`, `finca`, `bodega`, `analisis_calidad`, `exportador`, `permiso_exportacion`, `ingreso`, `transferencia`, `stock_deposito`, `auditoria_precio` y `schema_migration`, la candidata indicada determina todos los no primos y no se conoce otra DF de negocio interna. |

Las FKs no implican que los atributos descriptivos del padre deban copiarse. Por ejemplo, `id_departamento -> provincia` se resuelve en `DEPARTAMENTO`; provincia no se repite en `FINCA`.

## 4. Primera forma normal

Todas las relaciones físicas están en 1FN:

- cada columna usa un dominio escalar (`DATE`, `TIMESTAMPTZ`, `NUMERIC`, texto, ENUM o DOMAIN);
- no se guardan listas de cepas, maridajes, permisos, vinos o localidades dentro de una celda;
- los grupos repetidos se transformaron en `composicion_vino`, `vino_maridaje`, `permiso_exportacion`, renglones y `transportista_localidad`;
- dirección y nombre/razón social son textos atómicos para las operaciones requeridas. Separarlos sin necesidad de consulta no aportaría una dependencia nueva y sí inventaría estructura.

Un porcentaje por composición y una cantidad por renglón son atributos de relaciones asociativas, no arreglos multivaluados.

## 5. Segunda forma normal

Las relaciones con clave candidata sólo simple satisfacen 2FN automáticamente una vez comprobada 1FN. Para las compuestas se revisó cada parte:

- `parcela`: superficie, año y cepa describen la parcela completa, no a toda la finca ni al número aislado;
- `lote_uva`: fecha, kilos y bodega dependen de `(parcela, campaña)` completo; no se copiaron datos de finca o parcela;
- `composicion_vino`: el porcentaje pertenece al par vino–cepa; nombre/tipo de cepa y datos del vino quedan en sus tablas;
- `renglon_comprobante`: cantidad, precio y descuento históricos pertenecen a ese vino **en ese comprobante**, no al comprobante solo ni al vino actual;
- `renglon_ingreso` y `renglon_transferencia`: la cantidad pertenece al par documento–vino;
- `stock_sala`: la cantidad pertenece al par sala–vino;
- `transportista_localidad` y `vino_maridaje`: no tienen atributos no primos que puedan depender parcialmente.

`lote_uva` también tiene la candidata simple `nro_lote`; la revisión se hace contra todas las candidatas, incluida la compuesta. No se concluye 2FN sólo por haber elegido el número como PK.

Resultado: todas las relaciones físicas alcanzan 2FN.

## 6. Tercera forma normal y descomposiciones

### 6.1 Dependencias transitivas eliminadas

- Si la sala almacenara el encargado, aparecería `id_sala -> id_localidad -> encargado_regional`. El encargado queda únicamente en `localidad`.
- Si finca almacenara nombre de departamento y provincia junto con la FK, aparecería `id_finca -> id_departamento -> nombre, provincia`. Los datos territoriales quedan en `departamento`.
- Datos de bodega, cepa, localidad, sala, vino, transportista y cliente no se duplican en movimientos o renglones: las FKs llevan a la relación que los determina.
- Zona/habilitación y país principal no quedan en `cliente`; se ubican en los subtipos a los que corresponden.
- Los descuentos base 10/20/30 no se repiten por cliente. `tipo` los determinará mediante una función; sólo se almacena una excepción individual, que no queda determinada por el tipo porque puede ser nula o 35 dentro de exportadores.

### 6.2 Precio actual frente a precio histórico

`vino.precio` significa **precio vigente** y cumple `cod_vino -> precio_actual`. Puede cambiar.

`renglon_comprobante.precio_unitario` significa **precio congelado al momento de esa venta**. La DF correcta es `(nro_comprobante, cod_vino) -> precio_unitario`; no se afirma `cod_vino -> precio_unitario_historico`, porque un mismo vino puede venderse a precios distintos en fechas diferentes. Guardarlo no es una duplicación accidental del precio actual, sino el dato histórico necesario para reconstruir el comprobante.

Lo mismo vale para `descuento_porcentaje`: depende de la venta y conserva el resultado histórico aunque después cambie el cliente o la política.

### 6.3 Redundancias derivadas declaradas

Dos relaciones **no están en 3FN estricta** por una decisión física exigida y controlada:

1. En `renglon_comprobante`, `(cantidad, precio_unitario, descuento_porcentaje) -> subtotal`. El determinante no es superclave y el subtotal no es primo. Es una dependencia transitiva desde la PK y una desnormalización. Se conserva porque la consigna exige el subtotal histórico; `ck_renglon_comprobante_subtotal` ya impide que contradiga la fórmula.
2. En `comprobante`, `(subtotal, descuento) -> total`, y los tres importes también son agregados derivables de los renglones. Se conservan porque la consigna y las consultas los requieren. `ck_comprobante_importes` protege la aritmética interna, pero un trigger futuro deberá recalcularlos desde todos los renglones para evitar una cabecera desfasada.

Por eso no se afirma que **todo el esquema físico** esté sin excepciones en 3FN. El modelo relacional base está descompuesto hasta 3FN y esas dos desnormalizaciones monetarias quedan identificadas, acotadas y con un mecanismo de consistencia previsto. Los tres subtipos de cliente tienen además el discriminador constante analizado al final de esta sección.

También hay redundancias que cruzan relaciones y no se explican sólo mediante la definición clásica de 3FN:

- `cliente.tipo` y la presencia en una tabla de subtipo expresan la misma clasificación. Se conserva el discriminador para RN-06 y consultas. La coincidencia y la exclusividad ya las garantiza la FK compuesta descripta abajo; la totalidad quedará a cargo de un constraint trigger diferido.

#### Discriminador constante en los subtipos

`socio_club`, `distribuidor` y `exportador` tienen una columna `tipo` cuyo valor fija un `CHECK`. Su análisis se presenta en dos niveles:

**(a) Definición de la cátedra: ningún atributo no clave depende de otro atributo no clave.** `tipo` depende directamente de la PK `id_cliente` (`id_cliente -> tipo`). No hay un atributo no clave intermedio, así que no hay dependencia transitiva y la tabla está en 3FN.

**(b) Definición formal: para toda DF no trivial `X -> A`, `X` es superclave o `A` es primo.** El `CHECK (tipo = '...')` hace que `tipo` tome siempre el mismo valor, lo que introduce la DF degenerada `∅ -> tipo`. El conjunto vacío no es superclave y `tipo` no es primo, de modo que esa DF **no cumple** la condición formal.

Se declara como **redundancia controlada**:

- es un discriminador constante, no un dato que el usuario cargue o modifique: lo completa el `DEFAULT` y el `CHECK` rechaza cualquier otro valor;
- no puede producir anomalías de inserción, actualización ni borrado, porque no existe ningún valor alternativo que pueda quedar desactualizado o contradecir a otra fila;
- existe sólo para que la FK compuesta `(id_cliente, tipo) -> cliente(id_cliente, tipo)` garantice la exclusividad: un cliente sólo puede tener la fila del subtipo que declara.

**Alternativa descartada:** omitir la columna y proteger la exclusividad con un trigger en cada subtipo que consulte `cliente.tipo` y las otras dos tablas. Se prefirió el mecanismo declarativo porque el motor lo aplica en todo acceso sin código procedural, sin depender del orden de triggers y sin condiciones de carrera entre sesiones concurrentes. Además, es visible en el catálogo y se prueba con un error de FK o `CHECK` identificable por nombre. La totalidad, que una FK no puede expresar, sí requerirá un constraint trigger diferido.
- `stock_sala.cantidad` y `stock_deposito.cantidad` son saldos materializados derivables de movimientos y ventas. Cada tabla, considerada aisladamente, cumple la DF `clave -> cantidad` y está en 3FN, pero puede sufrir anomalías si se actualiza fuera de los procedimientos/triggers. La siguiente etapa centralizará el impacto y bloqueará filas para mantenerlos consistentes.
- `lote_uva.campania` coincide con el año de `fecha_cosecha`. La DF `fecha_cosecha -> campania` tiene un atributo primo a la derecha, de modo que cumple la definición de 3FN aunque no BCNF. Se conserva para expresar directamente la candidata de RN-04; `ck_lote_uva_fecha_campania` evita divergencia.

### 6.4 Resultado por relación

| Grupo | 1FN | 2FN | 3FN | Observación |
|---|---:|---:|---:|---|
| Catálogos, maestros y permisos | Sí | Sí | Sí | No quedan atributos de otro determinante no clave. |
| Subtipos de cliente | Sí | Sí | Sí según la definición de la cátedra; **no estricta** según la formal | Discriminador constante `∅ -> tipo` declarado como redundancia controlada para la FK compuesta (6.3). |
| Parcela, lote y análisis | Sí | Sí | Sí | Lote conserva campaña derivada; cumple 3FN pero no BCNF por la DF señalada. |
| Composición y asociaciones N:M | Sí | Sí | Sí | La suma 100 es una restricción agregada, no una DF por fila. |
| Ingresos, transferencias y sus renglones | Sí | Sí | Sí | Estados y cantidades dependen de sus claves; reglas de transición son integridad de negocio. |
| Stock por sala y depósito | Sí | Sí | Sí | Saldos materializados con consistencia interrelacional pendiente. |
| Auditoría de precio | Sí | Sí | Sí | Cada fila es un evento independiente. |
| `renglon_comprobante` | Sí | Sí | **No estricta** | Subtotal derivado almacenado; `CHECK` de fórmula. |
| `comprobante` | Sí | Sí | **No estricta** | Importes agregados almacenados; sincronización por trigger pendiente. |
| `schema_migration` | Sí | Sí | Sí | Relación técnica, sin DF transitiva conocida. |

## 7. Consistencia de las redundancias declaradas (Etapa 2)

Las redundancias controladas de la sección 6.3 quedan protegidas dentro de PostgreSQL:

- `renglon_comprobante.subtotal`: el trigger `trg_renglon_comprobante_completar` lo calcula con la misma fórmula del `CHECK`, y el renglón no puede modificarse después.
- Importes de `comprobante`: sólo los escribe `fn_recalcular_comprobante`, invocada al insertar cada renglón; `trg_comprobante_importes` rechaza cualquier otra escritura.
- `comprobante.xact_alta` (columna técnica de la Etapa 2) depende sólo de la PK: `nro_comprobante -> xact_alta`. No introduce dependencias transitivas y no se modifica después del alta.
- Saldos de `stock_sala` y `stock_deposito`: sólo cambian por la venta y por los procedimientos de ingreso y transferencia, que bloquean las filas; la API no tiene `UPDATE` sobre ellos.
- `cliente.tipo` y subtipos: exclusividad por FK compuesta y totalidad por constraint triggers diferidos.

El detalle de cada mecanismo y su prueba está en `docs/trazabilidad.md`.
