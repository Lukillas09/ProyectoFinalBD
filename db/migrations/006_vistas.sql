-- Bodegas del Atuel - vistas de consulta (Etapa 2)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Una vista común guarda la consulta, no los datos: se ejecuta cada vez que se
-- consulta y no mejora por sí misma el rendimiento. Sirve para no repetir la
-- consulta y para dar acceso de lectura sin exponer las tablas base: la vista
-- se ejecuta con los privilegios de su dueño (el propietario), así que a un
-- rol le alcanza con SELECT sobre la vista.
--
-- Columnas explícitas y sin ORDER BY: el orden lo decide cada consulta.

SET search_path TO bodegas, pg_catalog;

-- Stock por vino: depósito central, suma de salas y total.
CREATE VIEW v_stock_total_vino AS
SELECT
  v.cod_vino,
  v.nombre,
  v.anada,
  v.volumen_ml,
  COALESCE(d.cantidad, 0) AS stock_deposito,
  COALESCE(s.stock_salas, 0) AS stock_salas,
  COALESCE(d.cantidad, 0) + COALESCE(s.stock_salas, 0) AS stock_total
FROM vino AS v
LEFT JOIN stock_deposito AS d ON d.cod_vino = v.cod_vino
LEFT JOIN (
  SELECT cod_vino, SUM(cantidad) AS stock_salas
  FROM stock_sala
  GROUP BY cod_vino
) AS s ON s.cod_vino = v.cod_vino;

COMMENT ON VIEW v_stock_total_vino IS
  'Stock de cada vino: depósito, suma de salas y total. Vinos sin stock aparecen con 0.';

-- Ventas por sala y mes.
-- El mes se calcula en la zona horaria de la empresa para que el resultado no
-- dependa del parámetro TimeZone de cada sesión (fecha es TIMESTAMPTZ).
-- No se materializa: cambia con cada venta y una copia quedaría desactualizada
-- entre refrescos; REFRESH exige ser propietario y CONCURRENTLY un índice
-- único. Si en la Etapa 4 EXPLAIN muestra que conviene, se materializará con
-- una estrategia de refresco documentada.
CREATE VIEW v_ventas_mensuales_sala AS
SELECT
  c.id_sala,
  date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS mes,
  count(*) AS comprobantes,
  SUM(c.subtotal) AS importe_bruto,
  SUM(c.descuento) AS descuento,
  SUM(c.total) AS importe_neto
FROM comprobante AS c
GROUP BY
  c.id_sala,
  date_trunc('month', c.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;

COMMENT ON VIEW v_ventas_mensuales_sala IS
  'Comprobantes e importes por sala y mes (zona America/Argentina/Buenos_Aires). Vista común, no materializada.';

-- Ingresos y transferencias que todavía no impactaron en el stock.
CREATE VIEW v_documentos_pendientes AS
SELECT
  'ingreso'::TEXT AS tipo_documento,
  i.cod_ingreso AS numero,
  i.estado,
  (i.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE AS fecha,
  NULL::INTEGER AS id_sala,
  i.cuit_bodega,
  i.cod_transportista,
  count(r.cod_vino) AS renglones,
  COALESCE(SUM(r.cantidad), 0) AS botellas
FROM ingreso AS i
LEFT JOIN renglon_ingreso AS r ON r.cod_ingreso = i.cod_ingreso
WHERE i.estado <> 'procesado'
GROUP BY i.cod_ingreso
UNION ALL
SELECT
  'transferencia'::TEXT,
  t.nro_transferencia,
  t.estado,
  t.fecha_confeccion,
  t.id_sala,
  NULL::cuit_dom,
  NULL::INTEGER,
  count(r.cod_vino),
  COALESCE(SUM(r.cantidad), 0)
FROM transferencia AS t
LEFT JOIN renglon_transferencia AS r ON r.nro_transferencia = t.nro_transferencia
WHERE t.estado <> 'procesado'
GROUP BY t.nro_transferencia;

COMMENT ON VIEW v_documentos_pendientes IS
  'Ingresos y transferencias en confección o terminados, con cantidad de renglones y botellas.';

-- Ficha de vino para la consulta S9: corte, bodega, maridajes y stock total.
-- Corte y maridajes se agregan en subconsultas propias para no multiplicar
-- filas al combinarlos.
CREATE VIEW v_ficha_vino AS
SELECT
  v.cod_vino,
  v.nombre,
  v.tipo,
  v.anada,
  v.volumen_ml,
  v.graduacion,
  v.precio,
  v.cuit_bodega,
  b.razon_social AS bodega,
  comp.corte,
  mar.maridajes,
  st.stock_total
FROM vino AS v
JOIN bodega AS b ON b.cuit = v.cuit_bodega
JOIN v_stock_total_vino AS st ON st.cod_vino = v.cod_vino
LEFT JOIN (
  SELECT
    c.cod_vino,
    string_agg(format('%s %s%%', ce.nombre, c.porcentaje), ', '
               ORDER BY c.porcentaje DESC, ce.nombre) AS corte
  FROM composicion_vino AS c
  JOIN cepa AS ce ON ce.id_cepa = c.id_cepa
  GROUP BY c.cod_vino
) AS comp ON comp.cod_vino = v.cod_vino
LEFT JOIN (
  SELECT
    vm.cod_vino,
    string_agg(format('%s (%s °C)', m.nombre, m.temperatura_servicio_c), ', '
               ORDER BY m.nombre) AS maridajes
  FROM vino_maridaje AS vm
  JOIN maridaje AS m ON m.id_maridaje = vm.id_maridaje
  GROUP BY vm.cod_vino
) AS mar ON mar.cod_vino = v.cod_vino;

COMMENT ON VIEW v_ficha_vino IS
  'S9: ficha de vino con bodega, corte, maridajes y stock total.';
