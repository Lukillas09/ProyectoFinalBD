-- Consultas candidatas para la Etapa 4 (índices y rendimiento).
-- Base de consultas/select.sql de la Etapa 5.
--
-- Formato: cada consulta empieza con una línea "-- @consulta CODIGO", que usa
-- db/perf/medir.sh para separarlas. Las sentencias que modifican datos se
-- miden dentro de un bloque que se revierte: nunca cambian la base.
--
-- Períodos relativos: se calculan desde CURRENT_DATE en la hora local de la
-- empresa, aplicando AT TIME ZONE a la constante y no a la columna:
--   fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
-- La columna queda "desnuda", así que la condición puede usar un índice sobre
-- fecha. Escribir (fecha AT TIME ZONE ...)::date >= ... obligaría a calcular la
-- expresión en cada fila.
--
-- Valores concretos del dataset (SEMILLA 20260427, FECHA_REFERENCIA 2026-10-27):
--   sala 2 = San Rafael; vino 4 = "Malbec Reserva" 750 ml.

-- @consulta C1_S8
-- S8. Monto total de ventas por sala en el último trimestre, en orden descendente.
-- Parámetro: último trimestre = desde CURRENT_DATE - 3 meses.
SELECT s.id_sala, l.nombre AS localidad, s.calle, s.numero,
       count(*) AS comprobantes,
       sum(c.total) AS monto_total
FROM comprobante AS c
JOIN sala_venta AS s ON s.id_sala = c.id_sala
JOIN localidad AS l ON l.id_localidad = s.id_localidad
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '3 months') AT TIME ZONE 'America/Argentina/Buenos_Aires'
GROUP BY s.id_sala, l.nombre, s.calle, s.numero
ORDER BY monto_total DESC;

-- @consulta C2_S3
-- S3. Cantidad de clientes de cada tipo que compraron en una sala determinada
-- en la última semana. Se listan los tres tipos, aunque alguno tenga 0.
-- Parámetros: sala 2 (San Rafael); última semana = desde CURRENT_DATE - 7 días.
SELECT t.tipo, count(DISTINCT x.id_cliente) AS clientes
FROM unnest(enum_range(NULL::tipo_cliente)) AS t(tipo)
LEFT JOIN (
  SELECT c.id_cliente, cl.tipo
  FROM comprobante AS c
  JOIN cliente AS cl ON cl.id_cliente = c.id_cliente
  WHERE c.id_sala = 2
    AND c.fecha >= (CURRENT_DATE - INTERVAL '7 days') AT TIME ZONE 'America/Argentina/Buenos_Aires'
) AS x ON x.tipo = t.tipo
GROUP BY t.tipo
ORDER BY t.tipo;

-- @consulta C3_S5
-- S5. Salas con menor cantidad de transferencias pendientes (no procesadas).
-- Devuelve todas las salas empatadas en el mínimo.
SELECT s.id_sala, l.nombre AS localidad, count(t.nro_transferencia) AS pendientes
FROM sala_venta AS s
JOIN localidad AS l ON l.id_localidad = s.id_localidad
LEFT JOIN transferencia AS t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
GROUP BY s.id_sala, l.nombre
ORDER BY pendientes
FETCH FIRST 1 ROWS WITH TIES;

-- @consulta C4_D4
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta hace
-- más de 5 años. Cada cliente borrado dispara el control de la FK
-- fk_comprobante_cliente (RESTRICT): PostgreSQL busca comprobantes de ese
-- cliente. Se mide dentro de un bloque que se revierte.
DELETE FROM cliente AS c
WHERE c.tipo = 'socio'
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante AS x WHERE x.id_cliente = c.id_cliente);

-- @consulta C5_VENTAS_VINO
-- Ventas de un vino por sala: base de S9 (ficha de vino) y S12 (división por
-- vino). Hace la misma búsqueda que el control de RESTRICT al borrar un vino.
-- cod_vino es la segunda columna de la PK (nro_comprobante, cod_vino), así
-- que la PK no sirve para buscar por vino.
-- Parámetro: vino 4, "Malbec Reserva" 750 ml.
SELECT c.id_sala, count(*) AS renglones, sum(r.cantidad) AS botellas, sum(r.subtotal) AS importe
FROM renglon_comprobante AS r
JOIN comprobante AS c ON c.nro_comprobante = r.nro_comprobante
WHERE r.cod_vino = 4
GROUP BY c.id_sala
ORDER BY botellas DESC;

-- @consulta C6_PRECIO_VIGENTE
-- Precio vigente de cada renglón vendido en el último mes, según la auditoría
-- de precios (control de la carga y base de U1): el último precio nuevo
-- auditado antes de la venta. Cuenta los renglones cuyo precio histórico
-- difiere del vigente (debe dar 0 en los distintos).
SELECT count(*) AS renglones,
       count(*) FILTER (WHERE p.precio IS DISTINCT FROM r.precio_unitario) AS distintos
FROM comprobante AS c
JOIN renglon_comprobante AS r ON r.nro_comprobante = c.nro_comprobante
LEFT JOIN LATERAL (
  SELECT a.precio_nuevo AS precio
  FROM auditoria_precio AS a
  WHERE a.cod_vino = r.cod_vino
    AND a.fecha_hora <= c.fecha
  ORDER BY a.fecha_hora DESC
  LIMIT 1
) AS p ON true
WHERE c.fecha >= (CURRENT_DATE - INTERVAL '1 month') AT TIME ZONE 'America/Argentina/Buenos_Aires';

-- @consulta C7_S1
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en toda
-- la red. Agrega todo el historial: se espera que ningún índice la mejore.
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, b.razon_social AS bodega,
       sum(r.cantidad) AS botellas
FROM renglon_comprobante AS r
JOIN vino AS v ON v.cod_vino = r.cod_vino
JOIN bodega AS b ON b.cuit = v.cuit_bodega
GROUP BY v.cod_vino, v.nombre, v.anada, v.volumen_ml, b.razon_social
ORDER BY botellas DESC
LIMIT 10;
