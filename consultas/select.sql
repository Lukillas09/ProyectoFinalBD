-- =============================================================================
-- CONSULTAS SELECT - ETAPA 5
-- Bodegas del Atuel - Trabajo Práctico Integrador BD 2026
-- =============================================================================
--
-- Consultas S1 a S12 según especificación.
-- S9-S12 requieren EXPLAIN (ANALYZE, BUFFERS) obligatorio.
-- Períodos relativos usan CURRENT_DATE, no fechas fijas.
--
-- Ejecución (como propietario, corta en el primer error):
--   docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
-- Cada consulta se precede de \echo '>>> Sn' (y '>>> PLAN Sn' para los
-- EXPLAIN) para poder leer la salida.
-- =============================================================================

-- =============================================================================
-- PARÁMETROS
-- Cada uno tiene un valor por omisión que se reemplaza desde la línea de
-- comandos, por ejemplo: ejecutar.sh select.sql -v id_sala=3 -v cod_vino=2
-- Los valores son identificadores de catálogo de la carga (no dependen de
-- FECHA_REFERENCIA) elegidos entre los casos que db/seed/controles.sql
-- garantiza (docs/carga_masiva.md, sección 4.4).
-- =============================================================================

-- id_sala (S3, S6). Sala 1: controles.sql garantiza vinos sin stock en la sala
-- 1 y con stock en depósito (S6); tiene ventas todas las semanas (S3).
--   SELECT id_sala, count(*) FROM bodegas.comprobante
--    WHERE fecha >= CURRENT_DATE - 7 GROUP BY id_sala ORDER BY id_sala;
\if :{?id_sala}
\else
  \set id_sala 1
\endif

-- cod_vino (S9). Vino 1, "Malbec Clásico".
\if :{?cod_vino}
\else
  \set cod_vino 1
\endif

-- cod_vino_transferido (S4). Qué vino se transfirió a más salas en los últimos
-- 15 días depende de la historia simulada: con FECHA_REFERENCIA=2026-10-27 es
-- el vino 1 (15 salas), con otra fecha puede ser otro. Por eso se elige al
-- ejecutar, entre los que controles.sql garantiza (5 salas o más).
\if :{?cod_vino_transferido}
\else
  SELECT r.cod_vino AS cod_vino_transferido
    FROM bodegas.transferencia AS t
    JOIN bodegas.renglon_transferencia AS r USING (nro_transferencia)
   WHERE t.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
   GROUP BY r.cod_vino
   ORDER BY count(DISTINCT t.id_sala) DESC, r.cod_vino
   LIMIT 1
  \gset
\endif

-- cuit_bodega (S12 A). Bodega Lopez S.R.L., la única bodega chica (3 vinos):
-- controles.sql garantiza clientes que compraron sus tres vinos.
--   SELECT cuit_bodega, count(*) FROM bodegas.vino GROUP BY cuit_bodega ORDER BY 2 LIMIT 1;
\if :{?cuit_bodega}
\else
  \set cuit_bodega 30555408710
\endif

-- =============================================================================
-- S1: Ranking de los diez vinos con más botellas vendidas
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S1
-- Tipo:             SELECT
-- Enunciado:        Ranking de los diez vinos con más botellas vendidas
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se agregan las cantidades de renglon_comprobante por vino.
-- Se une con vino para obtener nombre, tipo, precio, bodega.
-- Orden descendente por total de botellas, límite 10.
-- Índice relevante: idx_renglon_comprobante_cod_vino (FK) creado en 008_indices.sql.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver top 10:
-- SELECT v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social AS bodega,
--        SUM(rc.cantidad) AS total_botellas
--   FROM bodegas.renglon_comprobante rc
--   JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
--   JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
--  GROUP BY v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social
--  ORDER BY total_botellas DESC
--  LIMIT 10;
-- Valores típicos: top vinos con miles de botellas vendidas.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S1'
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.precio,
       b.razon_social AS bodega,
       SUM(rc.cantidad) AS total_botellas
  FROM bodegas.renglon_comprobante rc
  JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 GROUP BY v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social
 ORDER BY total_botellas DESC
 LIMIT 10;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE (OBLIGATORIO PARA S9-S12, OPCIONAL PARA S1-S8)
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.precio,
       b.razon_social AS bodega,
       SUM(rc.cantidad) AS total_botellas
  FROM bodegas.renglon_comprobante rc
  JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 GROUP BY v.cod_vino, v.nombre, v.tipo, v.precio, b.razon_social
 ORDER BY total_botellas DESC
 LIMIT 10;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- Consulta directa de agregación. El índice idx_renglon_comprobante_cod_vino
-- acelera el JOIN y la agrupación.


-- =============================================================================
-- S2: Vinos vendidos en todas las salas, mediante división relacional
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S2
-- Tipo:             SELECT
-- Enunciado:        Vinos vendidos en todas las salas, mediante división relacional
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- División relacional: vinos para los que NO EXISTE una sala donde NO SE HAYA VENDIDO.
-- Patrón estándar: doble NOT EXISTS.
-- Período: "vendidos" = todo el historial (no período relativo según enunciado).
-- Se une comprobante -> renglon_comprobante para obtener sala y vino.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver vinos vendidos en todas las salas:
-- SELECT v.cod_vino, v.nombre
--   FROM bodegas.vino v
--  WHERE NOT EXISTS (
--     SELECT 1 FROM bodegas.sala_venta s
--      WHERE NOT EXISTS (
--        SELECT 1 FROM bodegas.comprobante c
--        JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
--         WHERE c.id_sala = s.id_sala
--           AND rc.cod_vino = v.cod_vino
--      )
--  );
-- Valores típicos: pocos vinos (o ninguno) vendidos en TODAS las salas.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S2'
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.sala_venta s
    WHERE NOT EXISTS (
      SELECT 1 FROM bodegas.comprobante c
      JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
       WHERE c.id_sala = s.id_sala
         AND rc.cod_vino = v.cod_vino
    )
 );

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT v.cod_vino, v.nombre, v.tipo, v.graduacion, v.precio, b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.sala_venta s
    WHERE NOT EXISTS (
      SELECT 1 FROM bodegas.comprobante c
      JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
       WHERE c.id_sala = s.id_sala
         AND rc.cod_vino = v.cod_vino
    )
 );
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- División relacional con doble NOT EXISTS, patrón estándar para "todos los valores de un conjunto".
-- El índice idx_comprobante_id_sala_fecha (id_sala, fecha) ayuda en el subquery correlacionado.


-- =============================================================================
-- S3: Cantidad de clientes de cada tipo que compraron en una sala durante la última semana
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S3
-- Tipo:             SELECT
-- Enunciado:        Cantidad de clientes de cada tipo que compraron en una sala durante la última semana
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Filtro: comprobantes de la última semana (fecha >= CURRENT_DATE - INTERVAL '7 days')
-- y de una sala específica (:id_sala).
-- Agrupar por tipo de cliente (socio, distribuidor, exportador) y contar DISTINCT id_cliente.
-- Índice: idx_comprobante_id_sala_fecha (id_sala, fecha) y idx_comprobante_id_cliente.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para sala 1, última semana:
-- SELECT cl.tipo, count(DISTINCT c.id_cliente) AS num_clientes
--   FROM bodegas.comprobante c
--   JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
--  WHERE c.id_sala = 1
--    AND c.fecha >= CURRENT_DATE - INTERVAL '7 days'
--  GROUP BY cl.tipo;
-- Valores típicos: decenas de clientes por tipo en una semana.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S3'
SELECT cl.tipo,
       count(DISTINCT c.id_cliente) AS cantidad_clientes
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = :id_sala
   AND c.fecha >= CURRENT_DATE - INTERVAL '7 days'
 GROUP BY cl.tipo
 ORDER BY cl.tipo;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT cl.tipo, count(DISTINCT c.id_cliente) AS cantidad_clientes
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.id_sala = 1
   AND c.fecha >= CURRENT_DATE - INTERVAL '7 days'
 GROUP BY cl.tipo;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Última semana" = CURRENT_DATE - INTERVAL '7 days' (relativo).
-- count(DISTINCT) evita contar duplicados si un cliente compró varias veces.
-- El parámetro :id_sala permite consultar cualquier sala.


-- =============================================================================
-- S4: Cinco salas que más solicitaron un vino en transferencias de los últimos quince días
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S4
-- Tipo:             SELECT
-- Enunciado:        Cinco salas que más solicitaron un vino en transferencias de los últimos quince días
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Filtro: transferencias de los últimos 15 días (fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days')
-- y un vino específico (:cod_vino_transferido).
-- Agrupar por sala, sumar cantidades de renglon_transferencia.
-- Orden descendente por total solicitado, límite 5.
-- Índice: idx_transferencia_pendientes (id_sala WHERE estado <> 'procesado') parcialmente relevante.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para vino 100, últimos 15 días:
-- SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
--        SUM(rt.cantidad) AS total_solicitado
--   FROM bodegas.transferencia t
--   JOIN bodegas.renglon_transferencia rt ON rt.nro_transferencia = t.nro_transferencia
--   JOIN bodegas.sala_venta s ON s.id_sala = t.id_sala
--   JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
--  WHERE t.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
--    AND rt.cod_vino = 100
--  GROUP BY s.id_sala, s.calle, s.numero, l.nombre
--  ORDER BY total_solicitado DESC
--  LIMIT 5;
-- Valores típicos: cantidades 10-500 botellas por transferencia.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S4'
SELECT s.id_sala,
       s.calle,
       s.numero,
       l.nombre AS localidad,
       SUM(rt.cantidad) AS total_solicitado
  FROM bodegas.transferencia t
  JOIN bodegas.renglon_transferencia rt ON rt.nro_transferencia = t.nro_transferencia
  JOIN bodegas.sala_venta s ON s.id_sala = t.id_sala
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
 WHERE t.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
   AND rt.cod_vino = :cod_vino_transferido
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_solicitado DESC
 LIMIT 5;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
       SUM(rt.cantidad) AS total_solicitado
  FROM bodegas.transferencia t
  JOIN bodegas.renglon_transferencia rt ON rt.nro_transferencia = t.nro_transferencia
  JOIN bodegas.sala_venta s ON s.id_sala = t.id_sala
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
 WHERE t.fecha_confeccion >= CURRENT_DATE - INTERVAL '15 days'
   AND rt.cod_vino = 100
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_solicitado DESC
 LIMIT 5;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Últimos quince días" se calcula relativo a CURRENT_DATE sobre fecha_confeccion (DATE).
-- Incluye transferencias en cualquier estado (confección, terminado, procesado).
-- El parámetro :cod_vino_transferido permite consultar cualquier vino.


-- =============================================================================
-- S5: Salas con menor cantidad de transferencias pendientes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S5
-- Tipo:             SELECT
-- Enunciado:        Salas con menor cantidad de transferencias pendientes
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- "Pendientes" = estado <> 'procesado' (en_confeccion o terminado).
-- Contar transferencias por sala donde estado <> 'procesado'.
-- Orden ascendente por cantidad (menor primero).
-- Mostrar todas las salas, incluso con 0 (LEFT JOIN).
-- Índice: idx_transferencia_pendientes (id_sala WHERE estado <> 'procesado') - parcial ideal.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar:
-- SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
--        count(t.nro_transferencia) AS transferencias_pendientes
--   FROM bodegas.sala_venta s
--   JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
--   LEFT JOIN bodegas.transferencia t
--     ON t.id_sala = s.id_sala
--    AND t.estado <> 'procesado'
--  GROUP BY s.id_sala, s.calle, s.numero, l.nombre
--  ORDER BY transferencias_pendientes ASC, s.id_sala;
-- Valores típicos: muchas salas con 0-5 pendientes.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S5'
SELECT s.id_sala,
       s.calle,
       s.numero,
       l.nombre AS localidad,
       count(t.nro_transferencia) AS transferencias_pendientes
  FROM bodegas.sala_venta s
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
  LEFT JOIN bodegas.transferencia t
    ON t.id_sala = s.id_sala
   AND t.estado <> 'procesado'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY transferencias_pendientes ASC, s.id_sala;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
       count(t.nro_transferencia) AS transferencias_pendientes
  FROM bodegas.sala_venta s
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
  LEFT JOIN bodegas.transferencia t
    ON t.id_sala = s.id_sala
   AND t.estado <> 'procesado'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY transferencias_pendientes ASC, s.id_sala;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- LEFT JOIN asegura que salas sin transferencias pendientes aparezcan con 0.
-- El índice parcial idx_transferencia_pendientes cubre exactamente el filtro estado <> 'procesado'.


-- =============================================================================
-- S6: Para una sala, vinos sin stock local pero disponibles en depósito
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S6
-- Tipo:             SELECT
-- Enunciado:        Para una sala, vinos sin stock local pero disponibles en depósito
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Para una sala dada (:id_sala), buscar vinos donde:
-- - stock_sala.cantidad = 0 o no existe fila (COALESCE a 0)
-- - stock_deposito.cantidad > 0
-- Usar la vista v_stock_total_vino o JOIN directo a stock_sala y stock_deposito.
-- Filtrar vinos que existan en stock_deposito con cantidad > 0.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para sala 1:
-- SELECT v.cod_vino, v.nombre, v.tipo, v.precio,
--        COALESCE(s.cantidad, 0) AS stock_sala,
--        COALESCE(d.cantidad, 0) AS stock_deposito
--   FROM bodegas.vino v
--   LEFT JOIN bodegas.stock_sala s ON s.id_sala = 1 AND s.cod_vino = v.cod_vino
--   LEFT JOIN bodegas.stock_deposito d ON d.cod_vino = v.cod_vino
--  WHERE COALESCE(s.cantidad, 0) = 0
--    AND COALESCE(d.cantidad, 0) > 0
--  ORDER BY v.nombre;
-- Valores típicos: varios vinos con stock en depósito pero no en sala específica.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S6'
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.graduacion,
       v.precio,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0) AS stock_deposito
  FROM bodegas.vino v
  LEFT JOIN bodegas.stock_sala s
    ON s.id_sala = :id_sala
   AND s.cod_vino = v.cod_vino
  LEFT JOIN bodegas.stock_deposito d
    ON d.cod_vino = v.cod_vino
 WHERE COALESCE(s.cantidad, 0) = 0
   AND COALESCE(d.cantidad, 0) > 0
 ORDER BY v.nombre;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT v.cod_vino, v.nombre, v.tipo, v.graduacion, v.precio,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0) AS stock_deposito
  FROM bodegas.vino v
  LEFT JOIN bodegas.stock_sala s
    ON s.id_sala = 1
   AND s.cod_vino = v.cod_vino
  LEFT JOIN bodegas.stock_deposito d
    ON d.cod_vino = v.cod_vino
 WHERE COALESCE(s.cantidad, 0) = 0
   AND COALESCE(d.cantidad, 0) > 0
 ORDER BY v.nombre;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- COALESCE(s.cantidad, 0) trata "sin fila" como stock 0.
-- El parámetro :id_sala permite consultar cualquier sala.
-- Útil para decidir transferencias desde depósito (I6, sp_procesar_transferencia).


-- =============================================================================
-- S7: Transportista con mayor actividad en el último mes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S7
-- Tipo:             SELECT
-- Enunciado:        Transportista con mayor actividad en el último mes
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- "Actividad" = cantidad de ingresos (cabeceras) en el último mes
-- (fecha >= CURRENT_DATE - INTERVAL '1 month').
-- Agrupar por transportista, ordenar descendente, límite 1.
-- Mostrar datos del transportista y conteo.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar:
-- SELECT t.cod_transportista, t.razon_social, t.cuit, t.email,
--        count(i.cod_ingreso) AS num_ingresos
--   FROM bodegas.transportista t
--   JOIN bodegas.ingreso i ON i.cod_transportista = t.cod_transportista
--  WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
--  GROUP BY t.cod_transportista, t.razon_social, t.cuit, t.email
--  ORDER BY num_ingresos DESC
--  LIMIT 1;
-- Valores típicos: transportista top con 10-50 ingresos/mes.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S7'
SELECT t.cod_transportista,
       t.razon_social,
       t.cuit,
       t.email,
       t.telefono,
       t.domicilio,
       count(i.cod_ingreso) AS ingresos_ultimo_mes
  FROM bodegas.transportista t
  JOIN bodegas.ingreso i ON i.cod_transportista = t.cod_transportista
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
 GROUP BY t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio
 ORDER BY ingresos_ultimo_mes DESC
 LIMIT 1;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio,
       count(i.cod_ingreso) AS ingresos_ultimo_mes
  FROM bodegas.transportista t
  JOIN bodegas.ingreso i ON i.cod_transportista = t.cod_transportista
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
 GROUP BY t.cod_transportista, t.razon_social, t.cuit, t.email, t.telefono, t.domicilio
 ORDER BY ingresos_ultimo_mes DESC
 LIMIT 1;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Último mes" = CURRENT_DATE - INTERVAL '1 month' (relativo).
-- Solo considera ingresos (no transferencias).
-- Si hay empate, LIMIT 1 devuelve uno arbitrario (estable con ORDER BY secundario).


-- =============================================================================
-- S8: Ventas por sala del último trimestre, en orden descendente
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S8
-- Tipo:             SELECT
-- Enunciado:        Ventas por sala del último trimestre, en orden descendente
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- "Último trimestre" = 3 meses = CURRENT_DATE - INTERVAL '3 months'.
-- Agrupar comprobantes por sala, sumar total (importe neto).
-- Unir con sala_venta y localidad para nombre legible.
-- Orden descendente por monto total.
-- Vista v_ventas_mensuales_sala existe pero es por mes; aquí se quiere trimestre completo.
-- Índice: idx_comprobante_id_sala_fecha (id_sala, fecha) y idx_comprobante_fecha INCLUDE (id_sala, total).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar:
-- SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
--        count(*) AS num_comprobantes,
--        SUM(c.total) AS total_ventas
--   FROM bodegas.comprobante c
--   JOIN bodegas.sala_venta s ON s.id_sala = c.id_sala
--   JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
--  WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
--  GROUP BY s.id_sala, s.calle, s.numero, l.nombre
--  ORDER BY total_ventas DESC;
-- Valores típicos: salas con miles de comprobantes, millones en ventas.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S8'
SELECT s.id_sala,
       s.calle,
       s.numero,
       l.nombre AS localidad,
       count(*) AS num_comprobantes,
       SUM(c.subtotal) AS importe_bruto,
       SUM(c.descuento) AS total_descuento,
       SUM(c.total) AS total_ventas
  FROM bodegas.comprobante c
  JOIN bodegas.sala_venta s ON s.id_sala = c.id_sala
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_ventas DESC;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE
-- -----------------------------------------------------------------------------
/*
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT s.id_sala, s.calle, s.numero, l.nombre AS localidad,
       count(*) AS num_comprobantes,
       SUM(c.total) AS total_ventas
  FROM bodegas.comprobante c
  JOIN bodegas.sala_venta s ON s.id_sala = c.id_sala
  JOIN bodegas.localidad l ON l.id_localidad = s.id_localidad
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero, l.nombre
 ORDER BY total_ventas DESC;
*/

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- Incluye subtotal bruto, descuento total y total neto para análisis completo.
-- El índice INCLUDE (id_sala, total) en idx_comprobante_fecha permite index-only scan.


-- =============================================================================
-- S9: Ficha de vino con corte, bodega, maridajes y stock total, usando joins, agregación y vista
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S9
-- Tipo:             SELECT
-- Enunciado:        Ficha de vino con corte, bodega, maridajes y stock total, usando joins, agregación y vista
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Usar la vista v_ficha_vino creada en 006_vistas.sql que ya une:
-- - vino + bodega (razon_social)
-- - v_stock_total_vino (stock_deposito, stock_salas, stock_total)
-- - composicion_vino + cepa agregado como string_agg (corte)
-- - vino_maridaje + maridaje agregado como string_agg (maridajes)
-- Filtrar por un vino específico (:cod_vino) o listar todos.
-- La vista ya hace las agregaciones de corte y maridajes en subconsultas separadas
-- para no multiplicar filas (producto cartesiano).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para vino 100:
-- SELECT * FROM bodegas.v_ficha_vino WHERE cod_vino = 100;
-- Ejecutar top 10:
-- SELECT * FROM bodegas.v_ficha_vino ORDER BY cod_vino LIMIT 10;
-- Valores: corte ej. "Malbec 85%, Cabernet Sauvignon 15%", maridajes ej. "Carnes rojas (18.0 °C), Quesos duros (16.0 °C)"
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S9'
SELECT cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio,
       cuit_bodega, bodega, corte, maridajes, stock_total
  FROM bodegas.v_ficha_vino
 WHERE cod_vino = :cod_vino;

-- Alternativa: listar todos con paginación
/*
SELECT cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio,
       cuit_bodega, bodega, corte, maridajes, stock_total
  FROM bodegas.v_ficha_vino
 ORDER BY cod_vino
 LIMIT 20 OFFSET 0;
*/

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE (OBLIGATORIO PARA S9)
-- -----------------------------------------------------------------------------
\echo '>>> PLAN S9'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT cod_vino, nombre, tipo, anada, volumen_ml, graduacion, precio,
       cuit_bodega, bodega, corte, maridajes, stock_total
  FROM bodegas.v_ficha_vino
 WHERE cod_vino = :cod_vino;

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- La vista v_ficha_vino encapsula toda la lógica compleja (corte, maridajes, stock).
-- Usar la vista simplifica la consulta y centraliza la definición.
-- El filtro WHERE cod_vino = :cod_vino se aplica después de la vista (no se puede empujar
-- fácilmente a las subconsultas de string_agg, pero el planificador lo optimiza).


-- =============================================================================
-- S10: Rendimiento kg/ha por parcela/campaña y parcelas bajo el promedio de su finca,
--      con CTE y subconsulta correlacionada
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S10
-- Tipo:             SELECT
-- Enunciado:        Rendimiento kg/ha por parcela/campaña y parcelas bajo el promedio de su finca, con CTE y subconsulta correlacionada
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- CTE 1 (rendimiento_parcela): calcular kg/ha por parcela/campaña
--   SUM(l.kilos) / SUM(p.superficie_ha) agrupado por finca, parcela, campaña
-- CTE 2 (promedio_finca): promedio de kg/ha por finca/campaña
-- Consulta final: parcelas donde kg_ha < promedio de su finca en esa campaña
-- Subconsulta correlacionada alternativa: calcular promedio en WHERE.
-- Usar NULLIF para evitar división por cero.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar:
-- WITH rendimiento_parcela AS (
--   SELECT l.id_finca, l.nro_parcela, l.campana,
--          SUM(l.kilos) / NULLIF(SUM(p.superficie_ha), 0) AS kg_ha
--     FROM bodegas.lote_uva l
--     JOIN bodegas.parcela p ON p.id_finca = l.id_finca AND p.nro_parcela = l.nro_parcela
--    GROUP BY l.id_finca, l.nro_parcela, l.campana
-- ),
-- promedio_finca AS (
--   SELECT id_finca, campana, AVG(kg_ha) AS prom_kg_ha
--     FROM rendimiento_parcela
--    GROUP BY id_finca, campana
-- )
-- SELECT rp.id_finca, rp.nro_parcela, rp.campana, rp.kg_ha, pf.prom_kg_ha,
--        f.nombre AS finca
--   FROM rendimiento_parcela rp
--   JOIN promedio_finca pf ON pf.id_finca = rp.id_finca AND pf.campana = rp.campana
--   JOIN bodegas.finca f ON f.id_finca = rp.id_finca
--  WHERE rp.kg_ha < pf.prom_kg_ha
--  ORDER BY rp.id_finca, rp.nro_parcela, rp.campana;
-- Valores: kg_ha típicos 5000-20000, varias parcelas bajo promedio por finca.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S10'
WITH rendimiento_parcela AS (
  SELECT l.id_finca,
         l.nro_parcela,
         l.campania,
         SUM(l.kilos) / NULLIF(SUM(p.superficie_ha), 0) AS kg_ha
    FROM bodegas.lote_uva l
    JOIN bodegas.parcela p
      ON p.id_finca = l.id_finca
     AND p.nro_parcela = l.nro_parcela
   GROUP BY l.id_finca, l.nro_parcela, l.campania
)
SELECT rp.id_finca,
       rp.nro_parcela,
       rp.campania,
       rp.kg_ha,
       (SELECT AVG(rp2.kg_ha)
          FROM rendimiento_parcela rp2
         WHERE rp2.id_finca = rp.id_finca
           AND rp2.campania = rp.campania) AS prom_kg_ha,
       f.nombre AS finca
  FROM rendimiento_parcela rp
  JOIN bodegas.finca f
    ON f.id_finca = rp.id_finca
 WHERE rp.kg_ha < (
   SELECT AVG(rp2.kg_ha)
     FROM rendimiento_parcela rp2
    WHERE rp2.id_finca = rp.id_finca
      AND rp2.campania = rp.campania
 )
 ORDER BY rp.id_finca, rp.nro_parcela, rp.campania;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE (OBLIGATORIO PARA S10)
-- -----------------------------------------------------------------------------
\echo '>>> PLAN S10'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH rendimiento_parcela AS (
  SELECT l.id_finca,
         l.nro_parcela,
         l.campania,
         SUM(l.kilos) / NULLIF(SUM(p.superficie_ha), 0) AS kg_ha
    FROM bodegas.lote_uva l
    JOIN bodegas.parcela p
      ON p.id_finca = l.id_finca
     AND p.nro_parcela = l.nro_parcela
   GROUP BY l.id_finca, l.nro_parcela, l.campania
)
SELECT rp.id_finca,
       rp.nro_parcela,
       rp.campania,
       rp.kg_ha,
       (SELECT AVG(rp2.kg_ha)
          FROM rendimiento_parcela rp2
         WHERE rp2.id_finca = rp.id_finca
           AND rp2.campania = rp.campania) AS prom_kg_ha,
       f.nombre AS finca
  FROM rendimiento_parcela rp
  JOIN bodegas.finca f
    ON f.id_finca = rp.id_finca
 WHERE rp.kg_ha < (
   SELECT AVG(rp2.kg_ha)
     FROM rendimiento_parcela rp2
    WHERE rp2.id_finca = rp.id_finca
      AND rp2.campania = rp.campania
 )
 ORDER BY rp.id_finca, rp.nro_parcela, rp.campania;

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- NULLIF evita división por cero si superficie_ha es 0 (no debería ocurrir por CHECK).
-- CTE rendimiento_parcela calcula kg/ha por parcela/campaña.
-- La subconsulta correlacionada (referencia rp.id_finca y rp.campana del nivel
-- externo) calcula el promedio de kg/ha de cada finca en la misma campaña y la
-- usa tanto para mostrarlo como para filtrar parcelas por debajo de ese promedio.


-- =============================================================================
-- S11: Ranking de vinos dentro de cada sala por botellas vendidas y ventas acumuladas
--      mensuales por sala, con RANK() particionado y suma de ventana
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S11
-- Tipo:             SELECT
-- Enunciado:        Ranking de vinos dentro de cada sala por botellas vendidas y ventas acumuladas mensuales por sala, con RANK() particionado y suma de ventana
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Período: último año (CURRENT_DATE - INTERVAL '1 year') para tener datos mensuales.
-- Paso 1: Agregar botellas por sala, vino, mes (usando date_trunc en fecha TIMESTAMPTZ).
-- Paso 2: Calcular RANK() OVER (PARTITION BY sala ORDER BY botellas DESC) por mes.
-- Paso 3: Calcular suma acumulada mensual por sala: SUM(botellas) OVER (PARTITION BY sala ORDER BY mes ROWS UNBOUNDED PRECEDING).
-- Filtrar rank <= 10 (top 10 por sala).
-- Vista v_ventas_mensuales_sala existe pero es solo por sala/mes, no por vino.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar:
-- WITH ventas_mensuales_vino AS (
--   SELECT c.id_sala,
--          date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS mes,
--          rc.cod_vino,
--          v.nombre AS vino,
--          SUM(rc.cantidad) AS botellas
--     FROM bodegas.comprobante c
--     JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
--     JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
--    WHERE c.fecha >= CURRENT_DATE - INTERVAL '1 year'
--    GROUP BY c.id_sala, date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'), rc.cod_vino, v.nombre
-- ),
-- ranked AS (
--   SELECT *,
--          RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC) AS rnk_mes,
--          SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes
--                              ROWS UNBOUNDED PRECEDING) AS ventas_acumuladas_sala
--     FROM ventas_mensuales_vino
-- )
-- SELECT id_sala, mes, cod_vino, vino, botellas, rnk_mes, ventas_acumuladas_sala
--   FROM ranked
--  WHERE rnk_mes <= 10
--  ORDER BY id_sala, mes, rnk_mes;
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S11'
WITH ventas_mensuales_vino AS (
  SELECT c.id_sala,
         date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS mes,
         rc.cod_vino,
         v.nombre AS vino,
         SUM(rc.cantidad) AS botellas
    FROM bodegas.comprobante c
    JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
    JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
   WHERE c.fecha >= CURRENT_DATE - INTERVAL '1 year'
   GROUP BY c.id_sala,
            date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'),
            rc.cod_vino,
            v.nombre
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC) AS rnk_mes,
         SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes
                             ROWS UNBOUNDED PRECEDING) AS ventas_acumuladas_sala
    FROM ventas_mensuales_vino
)
SELECT id_sala,
       mes,
       cod_vino,
       vino,
       botellas,
       rnk_mes,
       ventas_acumuladas_sala
  FROM ranked
 WHERE rnk_mes <= 10
 ORDER BY id_sala, mes, rnk_mes;

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE (OBLIGATORIO PARA S11)
-- -----------------------------------------------------------------------------
\echo '>>> PLAN S11'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH ventas_mensuales_vino AS (
  SELECT c.id_sala,
         date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS mes,
         rc.cod_vino,
         v.nombre AS vino,
         SUM(rc.cantidad) AS botellas
    FROM bodegas.comprobante c
    JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
    JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
   WHERE c.fecha >= CURRENT_DATE - INTERVAL '1 year'
   GROUP BY c.id_sala,
            date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'),
            rc.cod_vino,
            v.nombre
),
ranked AS (
  SELECT *,
         RANK() OVER (PARTITION BY id_sala, mes ORDER BY botellas DESC) AS rnk_mes,
         SUM(botellas) OVER (PARTITION BY id_sala ORDER BY mes
                             ROWS UNBOUNDED PRECEDING) AS ventas_acumuladas_sala
    FROM ventas_mensuales_vino
)
SELECT id_sala, mes, cod_vino, vino, botellas, rnk_mes, ventas_acumuladas_sala
  FROM ranked
 WHERE rnk_mes <= 10
 ORDER BY id_sala, mes, rnk_mes;

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- RANK() particionado por (id_sala, mes) da ranking de vinos dentro de cada sala/mes.
-- SUM() OVER con ROWS UNBOUNDED PRECEDING da ventas acumuladas de la sala mes a mes.
-- La zona horaria 'America/Argentina/Buenos_Aires' asegura consistencia con v_ventas_mensuales_sala.
-- "Último año" = CURRENT_DATE - INTERVAL '1 year' (relativo).


-- =============================================================================
-- S12: Clientes que compraron todos los vinos de una bodega y quienes nunca compraron tintos,
--      con NOT EXISTS y anti-join
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           S12
-- Tipo:             SELECT
-- Enunciado:        Clientes que compraron todos los vinos de una bodega y quienes nunca compraron tintos, con NOT EXISTS y anti-join
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Dos consultas separadas combinadas con UNION ALL (o dos result sets):
-- A) Clientes que compraron TODOS los vinos de una bodega (:'cuit_bodega')
--    División relacional: NOT EXISTS (vino de la bodega WHERE NOT EXISTS (compra del cliente))
-- B) Clientes que NUNCA compraron vinos tipo 'tinto'
--    Anti-join: NOT EXISTS (compra del cliente de vino tinto)
-- Ambas usan NOT EXISTS (patrón anti-join / división relacional).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar A) para la bodega del parámetro (por omisión 30555408710):
-- SELECT c.id_cliente, c.nombre_razon_social, c.tipo
--   FROM bodegas.cliente c
--  WHERE NOT EXISTS (
--     SELECT 1 FROM bodegas.vino v
--      WHERE v.cuit_bodega = '30555408710'
--        AND NOT EXISTS (
--          SELECT 1 FROM bodegas.comprobante cmp
--          JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
--           WHERE cmp.id_cliente = c.id_cliente
--             AND rc.cod_vino = v.cod_vino
--        )
--  );
-- Ejecutar B):
-- SELECT c.id_cliente, c.nombre_razon_social, c.tipo
--   FROM bodegas.cliente c
--  WHERE NOT EXISTS (
--     SELECT 1 FROM bodegas.comprobante cmp
--     JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
--     JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
--      WHERE cmp.id_cliente = c.id_cliente
--        AND v.tipo = 'tinto'
--  );
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
\echo '>>> S12'
-- A) Clientes que compraron TODOS los vinos de una bodega
SELECT c.id_cliente,
       c.nombre_razon_social,
       c.tipo,
       'compro_todos_vinos_bodega' AS criterio
  FROM bodegas.cliente c
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.vino v
    WHERE v.cuit_bodega = :'cuit_bodega'
      AND NOT EXISTS (
        SELECT 1 FROM bodegas.comprobante cmp
        JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
         WHERE cmp.id_cliente = c.id_cliente
           AND rc.cod_vino = v.cod_vino
      )
 )
UNION ALL
-- B) Clientes que NUNCA compraron tintos (anti-join)
SELECT c.id_cliente,
       c.nombre_razon_social,
       c.tipo,
       'nunca_compro_tintos' AS criterio
  FROM bodegas.cliente c
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.comprobante cmp
   JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
   JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
    WHERE cmp.id_cliente = c.id_cliente
      AND v.tipo = 'tinto'
 );

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ANALYZE (OBLIGATORIO PARA S12)
-- -----------------------------------------------------------------------------
-- Un plan por parte (docs/consultas/planes/S12A_plan.txt y S12B_plan.txt).
\echo '>>> PLAN S12A'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT c.id_cliente, c.nombre_razon_social, c.tipo, 'compro_todos_vinos_bodega' AS criterio
  FROM bodegas.cliente c
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.vino v
    WHERE v.cuit_bodega = :'cuit_bodega'
      AND NOT EXISTS (
        SELECT 1 FROM bodegas.comprobante cmp
        JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
         WHERE cmp.id_cliente = c.id_cliente
           AND rc.cod_vino = v.cod_vino
      )
 );

\echo '>>> PLAN S12B'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT c.id_cliente, c.nombre_razon_social, c.tipo, 'nunca_compro_tintos' AS criterio
  FROM bodegas.cliente c
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.comprobante cmp
   JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = cmp.nro_comprobante
   JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
    WHERE cmp.id_cliente = c.id_cliente
      AND v.tipo = 'tinto'
 );

-- -----------------------------------------------------------------------------
-- 5. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- Parte A: División relacional con doble NOT EXISTS para "todos los vinos de una bodega".
-- Parte B: Anti-join simple con NOT EXISTS para "nunca compraron tintos".
-- El UNION ALL combina ambos criterios con una columna 'criterio' que distingue el origen.
-- El parámetro :'cuit_bodega' permite consultar cualquier bodega.
-- Índices relevantes: idx_renglon_comprobante_cod_vino, idx_comprobante_id_cliente, uq_vino_identidad_comercial (empieza por cuit_bodega, así que también sirve para la FK).