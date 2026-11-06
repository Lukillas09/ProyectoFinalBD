-- =============================================================================
-- CONSULTAS UPDATE - ETAPA 5
-- Bodegas del Atuel - Trabajo Práctico Integrador BD 2026
-- =============================================================================
--
-- Cada consulta de modificación sigue el protocolo:
--   \echo '>>> Xn'                       (marca para leer la salida)
--   BEGIN;
--   -- Control previo
--   -- Sentencia principal
--   \echo 'Filas afectadas (Xn):' :ROW_COUNT
--   -- Control posterior
--   ROLLBACK;
-- Cada consulta está en su propia transacción revertida: el archivo no deja
-- cambios en la base (se verifica con db/seed/hashes.sql antes y después).
--
-- Ejecución (como propietario, corta en el primer error):
--   docker compose exec db /opt/bodegas/consultas/ejecutar.sh update.sql
--
-- Convenciones:
-- - Palabras clave de SQL en mayúsculas.
-- - Parámetros de psql: :nombre para números, :'nombre' para texto.
-- - Datos: carga de la Etapa 3 con SEMILLA=20260427 y ESCALA=1. Los períodos
--   relativos usan CURRENT_DATE: para obtener filas, cargar con
--   FECHA_REFERENCIA igual a la fecha del día (README de db/seed).
-- =============================================================================

-- =============================================================================
-- PARÁMETROS
-- Valor por omisión reemplazable desde la línea de comandos, por ejemplo:
--   ejecutar.sh update.sql -v cuit_bodega=33532580264
-- =============================================================================

-- cuit_bodega (U3). Bodega Lopez S.R.L., 3 vinos: el control muestra todos.
--   SELECT cuit_bodega, count(*) FROM bodegas.vino GROUP BY cuit_bodega ORDER BY 2 LIMIT 1;
\if :{?cuit_bodega}
\else
  \set cuit_bodega 30555408710
\endif

-- =============================================================================
-- U1: Recalcular todos los totales de comprobantes aplicando el descuento del tipo de cliente
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U1
-- Tipo:             UPDATE
-- Enunciado:        Recalcular todos los totales de comprobantes aplicando el descuento del tipo de cliente
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Los importes de un comprobante (subtotal bruto, descuento y total neto) se
-- derivan de sus renglones (RN-08). El único camino de escritura es
-- fn_recalcular_comprobante(nro): suma cantidad * precio_unitario (bruto) y
-- los subtotales de los renglones (neto), y actualiza la cabecera con la marca
-- de transacción bodegas.recalculo_importes, que trg_comprobante_importes exige.
-- Por eso U1 NO hace un UPDATE directo de importes: el trigger lo rechaza con
-- P0001 "RN-08: un comprobante emitido no se modifica." (la versión anterior de
-- esta consulta fallaba así). Tampoco se duplica la aritmética fuera de la
-- función: se la invoca una vez por comprobante, para todos (150.125, ~16 s).
-- "Aplicando el descuento del tipo de cliente": el descuento de cada renglón
-- es el porcentaje vigente al vender (fn_descuento_cliente, RN-06), guardado en
-- renglon_comprobante.descuento_porcentaje. El recálculo usa ese porcentaje
-- congelado; un cambio posterior del tipo o la excepción del cliente no
-- modifica ventas ya emitidas (RN-12).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Todos los comprobantes: 150.125 con ESCALA=1. Si la carga es consistente
-- (controles.sql = 0), el recálculo no cambia ningún importe: el control
-- posterior debe informar 0 comprobantes con importes distintos.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U1'
BEGIN;

-- Control previo: cantidad, suma de totales y comprobantes cuyos importes no
-- coinciden con sus renglones (se espera 0).
CREATE TEMP TABLE u1_antes ON COMMIT DROP AS
SELECT nro_comprobante, subtotal, descuento, total FROM bodegas.comprobante;

SELECT count(*) AS comprobantes, sum(total) AS suma_total_antes
  FROM u1_antes;

SELECT count(*) AS importes_distintos_de_renglones_antes
  FROM bodegas.comprobante AS c
  JOIN (SELECT nro_comprobante,
               sum(cantidad * precio_unitario) AS bruto,
               sum(subtotal) AS neto
          FROM bodegas.renglon_comprobante
         GROUP BY nro_comprobante) AS r USING (nro_comprobante)
 WHERE (c.subtotal, c.descuento, c.total) IS DISTINCT FROM (r.bruto, r.bruto - r.neto, r.neto);

-- Sentencia principal: una llamada a fn_recalcular_comprobante por comprobante.
-- La función devuelve VOID; se cuentan las llamadas.
SELECT count(*) AS comprobantes_recalculados
  FROM (SELECT bodegas.fn_recalcular_comprobante(nro_comprobante)
          FROM bodegas.comprobante) AS recalculo;
\echo 'Filas afectadas (U1): una actualización de cabecera por comprobante recalculado (columna anterior)'

-- Control posterior: suma de totales e importes que cambiaron.
SELECT count(*) AS comprobantes, sum(total) AS suma_total_despues
  FROM bodegas.comprobante;

SELECT count(*) AS comprobantes_con_importes_cambiados
  FROM bodegas.comprobante AS c
  JOIN u1_antes AS a USING (nro_comprobante)
 WHERE (c.subtotal, c.descuento, c.total) IS DISTINCT FROM (a.subtotal, a.descuento, a.total);

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO INVOLUCRADOS
-- -----------------------------------------------------------------------------
-- Triggers BEFORE UPDATE en comprobante:
--   trg_comprobante_importes (RN-08): acepta el UPDATE sólo con la marca
--   bodegas.recalculo_importes = 'on' (la enciende fn_recalcular_comprobante)
--   y si no cambian número, fecha, cliente, sala ni xact_alta.
-- CHECK constraints:
--   ck_comprobante_importes: subtotal >= 0, descuento >= 0,
--   descuento <= subtotal, total = subtotal - descuento.
-- FOREIGN KEY constraints (no se modifican sus columnas):
--   fk_comprobante_cliente, fk_comprobante_sala_venta.
-- Reglas de negocio:
--   RN-06 (descuento según tipo de cliente, congelado en el renglón),
--   RN-08 (importes derivados de los renglones), RN-12 (venta emitida inmutable).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL (versión para un solo comprobante)
-- -----------------------------------------------------------------------------
/*
SELECT bodegas.fn_recalcular_comprobante(:nro_comprobante);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: UPDATE directo de importes (lo que hacía la versión anterior de U1)
-- UPDATE bodegas.comprobante SET subtotal = 0, descuento = 0, total = 0;
-- Esperado: SQLSTATE P0001 de trg_comprobante_importes,
--   "RN-08: un comprobante emitido no se modifica."

-- Caso: comprobante inexistente
-- SELECT bodegas.fn_recalcular_comprobante(999999999);
-- Esperado: SQLSTATE P0002, "El comprobante 999999999 no existe."
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES Y DECISIONES DE DISEÑO
-- -----------------------------------------------------------------------------
-- La función se invoca desde un SELECT sobre comprobante (una fila por
-- llamada), sin bloque DO ni bucle: es la forma más corta de aplicar una
-- función que modifica datos a un conjunto de filas.
-- Recalcular todos cuesta ~16 s porque cada llamada hace su propio UPDATE; no
-- se espera que un índice lo cambie (docs/rendimiento.md).


-- =============================================================================
-- U2: Aumentar 20 % el salario de empleados con más de cinco años de antigüedad
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U2
-- Tipo:             UPDATE
-- Enunciado:        Aumentar 20 % el salario de empleados con más de cinco años de antigüedad
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se usa la función fn_antiguedad_anios(fecha_ingreso, CURRENT_DATE) para calcular
-- los años completos de antigüedad. Se actualiza salario = salario * 1.20
-- donde fn_antiguedad_anios(fecha_ingreso) > 5.
-- fn_antiguedad_anios es IMMUTABLE, por lo que el planificador puede evaluarla
-- en la llamada. No hay triggers sobre empleado.salario.
-- CHECK constraint: ck_empleado_salario_positivo (salario > 0) - siempre se cumple al aumentar.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver empleados con >5 años:
-- SELECT cuit, nombre, fecha_ingreso, salario, bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios
--   FROM bodegas.empleado
--  WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
--  ORDER BY anios DESC;
-- Valores típicos: fecha_ingreso entre 2010-2024, salario 50000-500000.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U2'
BEGIN;

-- Control previo
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY anios_antiguedad DESC;

-- Sentencia principal
UPDATE bodegas.empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5;
\echo 'Filas afectadas (U2):' :ROW_COUNT

-- Control posterior
SELECT cuit, nombre, fecha_ingreso, salario,
       bodegas.fn_antiguedad_anios(fecha_ingreso) AS anios_antiguedad
  FROM bodegas.empleado
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5
 ORDER BY anios_antiguedad DESC;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints: ck_empleado_salario_positivo (salario > 0) - se cumple al aumentar
-- FOREIGN KEY: fk_empleado_sala_venta (id_sala)
-- Reglas de negocio: Ninguna RN directa; U2 es una consulta de mantenimiento
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE bodegas.fn_antiguedad_anios(fecha_ingreso) > 5;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sin empleados con >5 años (dataset pequeño)
-- UPDATE ... WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
-- Esperado: 0 filas afectadas, sin error
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- fn_antiguedad_anios usa CURRENT_DATE como DEFAULT, que se evalúa en la llamada.
-- El ROUND a 2 decimales mantiene la precisión de NUMERIC(14,2).


-- =============================================================================
-- U3: Aumentar 13 % el precio de vinos de una bodega elegida
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U3
-- Tipo:             UPDATE
-- Enunciado:        Aumentar 13 % el precio de vinos de una bodega elegida
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se actualiza vino.precio = ROUND(precio * 1.13, 2) para vinos de una bodega
-- identificada por CUIT o razón social. El trigger trg_vino_auditoria_precio
-- (AFTER UPDATE OF precio) registra automáticamente el cambio en auditoria_precio
-- con precio_anterior, precio_nuevo, fecha_hora y session_user (RN-13).
-- CHECK constraints: ck_vino_precio_positivo (precio > 0) - se cumple al aumentar.
-- FK: fk_vino_bodega (cuit_bodega)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver bodegas y sus vinos:
-- SELECT b.cuit, b.razon_social, v.cod_vino, v.nombre, v.precio
--   FROM bodegas.bodega b
--   JOIN bodegas.vino v ON v.cuit_bodega = b.cuit
--  ORDER BY b.razon_social, v.cod_vino
--  LIMIT 20;
-- Valores típicos: precio 500-10000, cuit_bodega 11 dígitos.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U3'
BEGIN;

-- Control previo: precios antes del aumento
SELECT v.cod_vino, v.nombre, v.precio AS precio_antes,
       b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.cuit = :'cuit_bodega'
 ORDER BY v.cod_vino;

-- Sentencia principal
UPDATE bodegas.vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = :'cuit_bodega';
\echo 'Filas afectadas (U3):' :ROW_COUNT

-- Control posterior: precios después del aumento
SELECT v.cod_vino, v.nombre, v.precio AS precio_despues,
       ROUND(v.precio / NULLIF(v.precio / 1.13, 0) * 100 - 100, 2) AS pct_cambio_calculado,
       b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.cuit = :'cuit_bodega'
 ORDER BY v.cod_vino;

-- Verificar auditoría (RN-13)
SELECT ap.cod_vino, v.nombre, ap.precio_anterior, ap.precio_nuevo,
       ap.fecha_hora, ap.usuario_bd
  FROM bodegas.auditoria_precio ap
  JOIN bodegas.vino v ON v.cod_vino = ap.cod_vino
 WHERE ap.fecha_hora >= (SELECT max(fecha_hora) FROM bodegas.auditoria_precio) - INTERVAL '1 minute'
   AND v.cuit_bodega = :'cuit_bodega'
 ORDER BY ap.fecha_hora DESC;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers AFTER:
--   trg_vino_auditoria_precio (RN-13): registra cambio de precio en auditoria_precio
-- CHECK constraints:
--   ck_vino_precio_positivo (precio > 0) - siempre se cumple al aumentar 13%
--   ck_vino_graduacion, ck_vino_tipo, ck_vino_volumen_positivo, etc. - no afectados
-- FOREIGN KEY:
--   fk_vino_bodega (cuit_bodega) - valida existencia de la bodega
-- Reglas de negocio:
--   RN-01 (precio único y positivo), RN-13 (auditoría de cambios de precio)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = :'cuit_bodega';
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: bodega inexistente
-- UPDATE bodegas.vino SET precio = precio * 1.13 WHERE cuit_bodega = '99999999999';
-- Esperado: 0 filas afectadas (no error, solo no hace nada por FK que no encuentra coincidencias)

-- Caso: precio resultante violaría CHECK - imposible al aumentar un precio > 0
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El trigger de auditoría usa session_user, que en la API será la cuenta de la API.
-- La auditoría es automática e inmutable (no se puede evitar sin desactivar el trigger).


-- =============================================================================
-- U4: Intercambiar lunes y miércoles como día de cierre, en una sola sentencia
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U4
-- Tipo:             UPDATE
-- Enunciado:        Intercambiar lunes y miércoles como día de cierre, en una sola sentencia
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se debe intercambiar los valores 'lunes' <-> 'miercoles' en sala_venta.dia_cierre
-- en una sola sentencia UPDATE. Se usa CASE WHEN para hacer el intercambio atómico.
-- CHECK constraint: ck_sala_venta_dia_cierre valida valores en la lista de 7 días.
-- No hay triggers sobre dia_cierre.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver distribución actual:
-- SELECT dia_cierre, count(*) AS cantidad
--   FROM bodegas.sala_venta
--  GROUP BY dia_cierre
--  ORDER BY cantidad DESC;
-- Valores: 'lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U4'
BEGIN;

-- Control previo
SELECT dia_cierre, count(*) AS cantidad
  FROM bodegas.sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

-- Sentencia principal: intercambio atómico en una sola sentencia
UPDATE bodegas.sala_venta
   SET dia_cierre = CASE
                      WHEN dia_cierre = 'lunes' THEN 'miercoles'
                      WHEN dia_cierre = 'miercoles' THEN 'lunes'
                      ELSE dia_cierre
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');
\echo 'Filas afectadas (U4):' :ROW_COUNT

-- Control posterior
SELECT dia_cierre, count(*) AS cantidad
  FROM bodegas.sala_venta
 GROUP BY dia_cierre
 ORDER BY dia_cierre;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints:
--   ck_sala_venta_dia_cierre (dia_cierre IN ('lunes','martes','miercoles','jueves','viernes','sabado','domingo'))
--   Los valores destino están en la lista, por lo que siempre pasa.
-- Reglas de negocio: RN-02 (sala en una localidad) - no afectado
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.sala_venta
   SET dia_cierre = CASE
                      WHEN dia_cierre = 'lunes' THEN 'miercoles'
                      WHEN dia_cierre = 'miercoles' THEN 'lunes'
                      ELSE dia_cierre
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: sin salas con lunes o miércoles
-- UPDATE ... WHERE dia_cierre IN ('lunes', 'miercoles');
-- Esperado: 0 filas afectadas, sin error
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El CASE WHEN evalúa el valor original de cada fila antes de cualquier asignación,
-- garantizando el intercambio atómico sin necesidad de columna temporal ni transacción.


-- =============================================================================
-- U5: Aplicar 15 % de rebaja a los diez vinos menos vendidos de la red
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U5
-- Tipo:             UPDATE
-- Enunciado:        Aplicar 15 % de rebaja a los diez vinos menos vendidos de la red
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se identifican los 10 vinos con menos botellas vendidas (suma de cantidad en
-- renglon_comprobante). Se aplica descuento: precio = ROUND(precio * 0.85, 2).
-- El trigger trg_vino_auditoria_precio registra cada cambio (RN-13).
-- CHECK: ck_vino_precio_positivo - precio > 0, al reducir 15% se mantiene >0 si precio original > 0.
-- Período: "de la red" implica todo el historial, no un período relativo.
-- Se usa CTE con LIMIT 10 para seleccionar los vinos.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver ranking de ventas:
-- SELECT v.cod_vino, v.nombre, COALESCE(SUM(rc.cantidad), 0) AS total_vendido
--   FROM bodegas.vino v
--   LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
--  GROUP BY v.cod_vino, v.nombre
--  ORDER BY total_vendido ASC, v.cod_vino
--  LIMIT 15;
-- Valores típicos: muchos vinos con 0 ventas, otros con pocas unidades.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U5'
BEGIN;

-- Control previo: los 10 menos vendidos antes
WITH ventas AS (
  SELECT v.cod_vino, v.nombre, v.precio AS precio_antes,
         COALESCE(SUM(rc.cantidad), 0) AS total_vendido
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino, v.nombre, v.precio
)
SELECT cod_vino, nombre, precio_antes, total_vendido
  FROM ventas
 ORDER BY total_vendido ASC, cod_vino
 LIMIT 10;

-- Sentencia principal
WITH menos_vendidos AS (
  SELECT v.cod_vino
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
   LIMIT 10
)
UPDATE bodegas.vino v
   SET precio = ROUND(v.precio * 0.85, 2)
  FROM menos_vendidos mv
 WHERE v.cod_vino = mv.cod_vino;
\echo 'Filas afectadas (U5):' :ROW_COUNT

-- Control posterior: los 10 menos vendidos después
WITH ventas AS (
  SELECT v.cod_vino, v.nombre, v.precio AS precio_despues,
         COALESCE(SUM(rc.cantidad), 0) AS total_vendido
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino, v.nombre, v.precio
)
SELECT cod_vino, nombre, precio_despues, total_vendido,
       ROUND(precio_despues / NULLIF(precio_despues / 0.85, 0) * 100 - 100, 2) AS pct_cambio
  FROM ventas
 ORDER BY total_vendido ASC, cod_vino
 LIMIT 10;

-- Verificar auditoría
SELECT ap.cod_vino, v.nombre, ap.precio_anterior, ap.precio_nuevo,
       ap.fecha_hora, ap.usuario_bd
  FROM bodegas.auditoria_precio ap
  JOIN bodegas.vino v ON v.cod_vino = ap.cod_vino
 WHERE ap.fecha_hora >= (SELECT max(fecha_hora) FROM bodegas.auditoria_precio) - INTERVAL '1 minute'
 ORDER BY ap.fecha_hora DESC;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers AFTER:
--   trg_vino_auditoria_precio (RN-13): registra cada cambio de precio
-- CHECK constraints:
--   ck_vino_precio_positivo (precio > 0) - al reducir 15% de un precio > 0, el resultado sigue > 0
-- Reglas de negocio: RN-01 (precio único y positivo), RN-13 (auditoría)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
WITH menos_vendidos AS (
  SELECT v.cod_vino
    FROM bodegas.vino v
    LEFT JOIN bodegas.renglon_comprobante rc ON rc.cod_vino = v.cod_vino
   GROUP BY v.cod_vino
   ORDER BY COALESCE(SUM(rc.cantidad), 0) ASC, v.cod_vino
   LIMIT 10
)
UPDATE bodegas.vino v
   SET precio = ROUND(v.precio * 0.85, 2)
  FROM menos_vendidos mv
 WHERE v.cod_vino = mv.cod_vino;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: menos de 10 vinos en la base
-- El LIMIT 10 devuelve los que hay; UPDATE afecta solo esos.
-- Esperado: filas afectadas = total de vinos (si < 10)

-- Caso: empate en ventas (mismo total_vendido)
-- El ORDER BY cod_vino desempata determinísticamente.
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "De la red" = todas las salas, todo el historial (no período relativo).
-- El LEFT JOIN incluye vinos sin ventas (total_vendido = 0), que son los primeros candidatos.
-- La auditoría registra cada cambio individual con session_user.


-- =============================================================================
-- U6: Elevar a 35 % el descuento de exportadores con más de tres permisos
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           U6
-- Tipo:             UPDATE
-- Enunciado:        Elevar a 35 % el descuento de exportadores con más de tres permisos
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se actualiza cliente.descuento_excepcion = 35.00 para exportadores que tengan
-- más de 3 permisos en permiso_exportacion. El trigger BEFORE trg_cliente_excepcion
-- valida que el exportador tenga >3 permisos al asignar la excepción (RN-06/U6).
-- El constraint trigger diferido ctrg_permiso_excepcion verifica al confirmar
-- que no quede una excepción sin respaldo.
-- CHECK: ck_cliente_descuento_excepcion exige tipo='exportador' y valor=35.00.
-- FK: fk_permiso_exportacion_exportador (id_exportador -> exportador.id_cliente)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver exportadores y sus permisos:
-- SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion,
--        count(pe.codigo_permiso) AS num_permisos
--   FROM bodegas.cliente c
--   JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
--   LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
--  WHERE c.tipo = 'exportador'
--  GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
--  ORDER BY num_permisos DESC;
-- Valores típicos: exportadores con 1-10 permisos, descuento_excepcion NULL o 35.00.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> U6'
BEGIN;

-- Control previo: exportadores con >3 permisos y su descuento actual
SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion AS desc_antes,
       count(pe.codigo_permiso) AS num_permisos
  FROM bodegas.cliente c
  JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
 WHERE c.tipo = 'exportador'
 GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
 HAVING count(pe.codigo_permiso) > 3
 ORDER BY num_permisos DESC;

-- Sentencia principal
UPDATE bodegas.cliente c
   SET descuento_excepcion = 35.00
  FROM (
    SELECT e.id_cliente
      FROM bodegas.exportador e
      JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
     GROUP BY e.id_cliente
     HAVING count(pe.codigo_permiso) > 3
  ) AS sub
 WHERE c.id_cliente = sub.id_cliente
   AND (c.descuento_excepcion IS NULL OR c.descuento_excepcion <> 35.00);
\echo 'Filas afectadas (U6):' :ROW_COUNT

-- Control posterior
SELECT c.id_cliente, c.nombre_razon_social, c.descuento_excepcion AS desc_despues,
       count(pe.codigo_permiso) AS num_permisos
  FROM bodegas.cliente c
  JOIN bodegas.exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
 WHERE c.tipo = 'exportador'
 GROUP BY c.id_cliente, c.nombre_razon_social, c.descuento_excepcion
 HAVING count(pe.codigo_permiso) > 3
 ORDER BY num_permisos DESC;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE:
--   trg_cliente_excepcion (RN-06/U6): valida >3 permisos al asignar descuento_excepcion
-- Constraint triggers DEFERRABLE:
--   ctrg_permiso_excepcion (RN-06/U6): al confirmar, valida que no quede excepción sin >3 permisos
-- CHECK constraints:
--   ck_cliente_descuento_excepcion (tipo='exportador' AND descuento_excepcion=35.00)
--   ck_exportador_tipo (tipo = 'exportador')
-- FOREIGN KEY:
--   fk_cliente_localidad, fk_exportador_cliente, fk_permiso_exportacion_exportador
-- Reglas de negocio: RN-06 (descuento según tipo + excepción exportador >3 permisos)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.cliente c
   SET descuento_excepcion = 35.00
  FROM (
    SELECT e.id_cliente
      FROM bodegas.exportador e
      JOIN bodegas.permiso_exportacion pe ON pe.id_exportador = e.id_cliente
     GROUP BY e.id_cliente
     HAVING count(pe.codigo_permiso) > 3
  ) AS sub
 WHERE c.id_cliente = sub.id_cliente
   AND (c.descuento_excepcion IS NULL OR c.descuento_excepcion <> 35.00);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: exportador con exactamente 3 permisos (no califica)
-- UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = :id_exp_3_permisos;
-- Esperado: SQLSTATE P0001 del trigger trg_cliente_excepcion
--   "RN-06: la excepción del 35% sólo corresponde a exportadores con más de tres permisos."

-- Caso: cliente no exportador (tipo socio/distribuidor)
-- UPDATE cliente SET descuento_excepcion = 35 WHERE id_cliente = :id_socio;
-- Esperado: SQLSTATE 23514 (check_violation), constraint ck_cliente_descuento_excepcion
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- La validación ocurre en dos niveles: BEFORE (inmediata) y DEFERRABLE (al commit).
-- Esto permite quitar permisos y la excepción en la misma transacción.
-- Se filtra WHERE descuento_excepcion IS NULL OR <> 35.00 para evitar UPDATE innecesarios.