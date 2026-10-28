\set ON_ERROR_STOP on
\pset pager off

-- Consultas de control de la carga masiva (Etapa 3, paso 7).
-- Ejecutar como propietario, indicando la fecha de referencia de la carga:
--   psql ... -v fecha_referencia=2026-10-27 -f controles.sql
-- Cada control cuenta violaciones; se informan todos y, si alguno encuentra
-- inconsistencias, el archivo termina con RAISE EXCEPTION (psql sale con
-- código 3). No modifica datos: todo ocurre en una transacción revertida.
-- Los controles cubren justamente lo que ningún trigger validó durante la
-- carga histórica (ver docs/carga_masiva.md).

\if :{?fecha_referencia}
\else
  \echo 'Falta -v fecha_referencia=AAAA-MM-DD (la misma FECHA_REFERENCIA de la carga).'
  \quit
\endif

-- Mínimo de la tabla más grande: 100.000 según la consigna. Para la carga
-- reducida de la nube (Etapa 8) se acepta -v minimo_mayor=10000.
\if :{?minimo_mayor}
\else
  \set minimo_mayor 100000
\endif

SET search_path TO bodegas, pg_catalog;
BEGIN;
-- Sólo se muestra el resultado final; los pasos intermedios no imprimen.
\o /dev/null
SELECT set_config('control.fecha_ref', :'fecha_referencia', true);

CREATE TEMP TABLE resultado_control (
  orden SERIAL,
  grupo TEXT,
  control TEXT,
  violaciones BIGINT
) ON COMMIT DROP;

-- Ejecuta una consulta que devuelve la cantidad de violaciones y la registra.
CREATE FUNCTION pg_temp.control(p_grupo TEXT, p_control TEXT, p_consulta TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v BIGINT;
BEGIN
  EXECUTE p_consulta INTO v;
  INSERT INTO resultado_control (grupo, control, violaciones) VALUES (p_grupo, p_control, v);
END;
$$;

CREATE FUNCTION pg_temp.fref() RETURNS DATE LANGUAGE sql STABLE
AS $$ SELECT current_setting('control.fecha_ref')::DATE $$;

-- Fecha local (la empresa opera en America/Argentina/Buenos_Aires).
CREATE FUNCTION pg_temp.dia(p TIMESTAMPTZ) RETURNS DATE LANGUAGE sql STABLE
AS $$ SELECT (p AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE $$;

-------------------------------------------------------------------------------
-- 1. Volumen
-------------------------------------------------------------------------------
CREATE TEMP TABLE conteo ON COMMIT DROP AS
SELECT c.relname AS tabla,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM bodegas.%I', c.relname), false, true, '')))[1]::TEXT::BIGINT AS filas
FROM pg_class AS c
WHERE c.relnamespace = 'bodegas'::regnamespace AND c.relkind = 'r' AND c.relname <> 'schema_migration';

SELECT pg_temp.control('volumen', 'tablas sin filas', 'SELECT count(*) FROM conteo WHERE filas = 0');
SELECT pg_temp.control('volumen', 'menos de 3 tablas con más de 10.000 filas',
  'SELECT GREATEST(0, 3 - count(*)) FROM conteo WHERE filas > 10000');
SELECT pg_temp.control('volumen', format('ninguna tabla con más de %s filas', :'minimo_mayor'),
  format('SELECT GREATEST(0, 1 - count(*)) FROM conteo WHERE filas > %s', :'minimo_mayor'::BIGINT));

-------------------------------------------------------------------------------
-- 2. Integridad referencial: huérfanos en cada FK del esquema, aunque las FK
--    existan (se demuestra recorriendo pg_constraint, no se supone).
-------------------------------------------------------------------------------
DO $$
DECLARE
  fk RECORD;
BEGIN
  FOR fk IN
    SELECT k.conname, k.conrelid::regclass AS hija, k.confrelid::regclass AS padre,
           (SELECT string_agg(format('h.%I = p.%I', a.attname, b.attname), ' AND ')
            FROM unnest(k.conkey, k.confkey) AS u(ch, cp)
            JOIN pg_attribute AS a ON a.attrelid = k.conrelid AND a.attnum = u.ch
            JOIN pg_attribute AS b ON b.attrelid = k.confrelid AND b.attnum = u.cp) AS condicion
    FROM pg_constraint AS k
    WHERE k.connamespace = 'bodegas'::regnamespace AND k.contype = 'f'
    ORDER BY k.conname
  LOOP
    PERFORM pg_temp.control('huérfanos', fk.conname,
      format('SELECT count(*) FROM %s AS h WHERE NOT EXISTS (SELECT 1 FROM %s AS p WHERE %s)',
             fk.hija, fk.padre, fk.condicion));
  END LOOP;
END;
$$;

-------------------------------------------------------------------------------
-- 3. Stock
-------------------------------------------------------------------------------
SELECT pg_temp.control('stock', 'stock de sala negativo', 'SELECT count(*) FROM stock_sala WHERE cantidad < 0');
SELECT pg_temp.control('stock', 'stock de depósito negativo', 'SELECT count(*) FROM stock_deposito WHERE cantidad < 0');

SELECT pg_temp.control('stock', 'stock de depósito distinto de los movimientos procesados', $q$
  SELECT count(*)
  FROM vino AS v
  LEFT JOIN stock_deposito AS d ON d.cod_vino = v.cod_vino
  WHERE COALESCE(d.cantidad, 0) <>
        COALESCE((SELECT SUM(ri.cantidad) FROM renglon_ingreso AS ri JOIN ingreso AS i USING (cod_ingreso)
                  WHERE i.estado = 'procesado' AND ri.cod_vino = v.cod_vino), 0)
      - COALESCE((SELECT SUM(rt.cantidad) FROM renglon_transferencia AS rt JOIN transferencia AS t USING (nro_transferencia)
                  WHERE t.estado = 'procesado' AND rt.cod_vino = v.cod_vino), 0)
$q$);

SELECT pg_temp.control('stock', 'stock de sala distinto de los movimientos procesados', $q$
  WITH mov AS (
    SELECT t.id_sala, rt.cod_vino, rt.cantidad AS delta
    FROM transferencia AS t JOIN renglon_transferencia AS rt USING (nro_transferencia)
    WHERE t.estado = 'procesado'
    UNION ALL
    SELECT c.id_sala, r.cod_vino, -r.cantidad
    FROM comprobante AS c JOIN renglon_comprobante AS r USING (nro_comprobante)
  ), saldo AS (SELECT id_sala, cod_vino, SUM(delta) AS cantidad FROM mov GROUP BY id_sala, cod_vino)
  SELECT count(*)
  FROM saldo FULL JOIN stock_sala AS s USING (id_sala, cod_vino)
  WHERE COALESCE(saldo.cantidad, 0) <> COALESCE(s.cantidad, 0)
$q$);

-- El stock no sólo termina en >= 0: nunca fue negativo en ningún momento.
-- Orden de cada día: ingresos, transferencias y ventas.
SELECT pg_temp.control('stock', 'depósito con saldo negativo en algún momento', $q$
  WITH mov AS (
    SELECT ri.cod_vino, pg_temp.dia(i.fecha) AS fecha, 0 AS orden, i.cod_ingreso AS doc, ri.cantidad AS delta
    FROM ingreso AS i JOIN renglon_ingreso AS ri USING (cod_ingreso) WHERE i.estado = 'procesado'
    UNION ALL
    SELECT rt.cod_vino, t.fecha_confeccion, 1, t.nro_transferencia, -rt.cantidad
    FROM transferencia AS t JOIN renglon_transferencia AS rt USING (nro_transferencia) WHERE t.estado = 'procesado'
  )
  SELECT count(*) FROM (
    SELECT SUM(delta) OVER (PARTITION BY cod_vino ORDER BY fecha, orden, doc
                            ROWS UNBOUNDED PRECEDING) AS saldo
    FROM mov) AS x
  WHERE saldo < 0
$q$);

SELECT pg_temp.control('stock', 'sala con saldo negativo en algún momento', $q$
  WITH mov AS (
    SELECT t.id_sala, rt.cod_vino, t.fecha_confeccion AS fecha, 0 AS orden, t.nro_transferencia AS doc, rt.cantidad AS delta
    FROM transferencia AS t JOIN renglon_transferencia AS rt USING (nro_transferencia) WHERE t.estado = 'procesado'
    UNION ALL
    SELECT c.id_sala, r.cod_vino, pg_temp.dia(c.fecha), 1, c.nro_comprobante, -r.cantidad
    FROM comprobante AS c JOIN renglon_comprobante AS r USING (nro_comprobante)
  )
  SELECT count(*) FROM (
    SELECT SUM(delta) OVER (PARTITION BY id_sala, cod_vino ORDER BY fecha, orden, doc
                            ROWS UNBOUNDED PRECEDING) AS saldo
    FROM mov) AS x
  WHERE saldo < 0
$q$);

-------------------------------------------------------------------------------
-- 4. Ventas: importes, precios y descuentos
-------------------------------------------------------------------------------
SELECT pg_temp.control('ventas', 'total distinto de fn_total_comprobante / suma de renglones', $q$
  SELECT count(*)
  FROM comprobante AS c
  JOIN (SELECT nro_comprobante, SUM(cantidad * precio_unitario) AS bruto, SUM(subtotal) AS neto
        FROM renglon_comprobante GROUP BY nro_comprobante) AS r USING (nro_comprobante)
  WHERE c.total <> r.neto OR c.subtotal <> r.bruto OR c.descuento <> r.bruto - r.neto
     OR c.total <> fn_total_comprobante(c.nro_comprobante)
$q$);

SELECT pg_temp.control('ventas', 'comprobantes sin renglones',
  'SELECT count(*) FROM comprobante AS c WHERE NOT EXISTS (SELECT 1 FROM renglon_comprobante AS r WHERE r.nro_comprobante = c.nro_comprobante)');

SELECT pg_temp.control('ventas', 'descuento del renglón distinto del vigente para el cliente', $q$
  SELECT count(*)
  FROM renglon_comprobante AS r JOIN comprobante AS c USING (nro_comprobante)
  JOIN (SELECT id_cliente, fn_descuento_cliente(id_cliente) AS d FROM cliente) AS x USING (id_cliente)
  WHERE r.descuento_porcentaje <> x.d
$q$);

-- Precio vigente según la auditoría (misma deducción que el generador).
CREATE TEMP TABLE intervalo_precio ON COMMIT DROP AS
WITH cambios AS (
  SELECT cod_vino, fecha_hora, precio_anterior, precio_nuevo,
         LEAD(fecha_hora) OVER w AS siguiente, ROW_NUMBER() OVER w AS n
  FROM auditoria_precio WINDOW w AS (PARTITION BY cod_vino ORDER BY fecha_hora)
)
SELECT cod_vino, '-infinity'::TIMESTAMPTZ AS desde, fecha_hora AS hasta, precio_anterior AS precio FROM cambios WHERE n = 1
UNION ALL
SELECT cod_vino, fecha_hora, COALESCE(siguiente, 'infinity'), precio_nuevo FROM cambios
UNION ALL
SELECT v.cod_vino, '-infinity', 'infinity', v.precio FROM vino AS v
WHERE NOT EXISTS (SELECT 1 FROM auditoria_precio AS a WHERE a.cod_vino = v.cod_vino);
CREATE INDEX ON intervalo_precio (cod_vino);
ANALYZE intervalo_precio;

SELECT pg_temp.control('ventas', 'precio del renglón distinto del vigente en la fecha de venta', $q$
  SELECT count(*)
  FROM renglon_comprobante AS r JOIN comprobante AS c USING (nro_comprobante)
  WHERE (SELECT count(*) FROM intervalo_precio AS p
         WHERE p.cod_vino = r.cod_vino AND c.fecha >= p.desde AND c.fecha < p.hasta
           AND p.precio = r.precio_unitario) <> 1
$q$);

SELECT pg_temp.control('ventas', 'auditoría de precio no encadenada', $q$
  SELECT count(*) FROM (
    SELECT precio_anterior, LAG(precio_nuevo) OVER (PARTITION BY cod_vino ORDER BY fecha_hora) AS previo
    FROM auditoria_precio) AS x
  WHERE previo IS NOT NULL AND previo <> precio_anterior
$q$);

SELECT pg_temp.control('ventas', 'precio actual distinto del último cambio auditado', $q$
  SELECT count(*) FROM vino AS v
  JOIN LATERAL (SELECT precio_nuevo FROM auditoria_precio AS a WHERE a.cod_vino = v.cod_vino
                ORDER BY fecha_hora DESC LIMIT 1) AS u ON true
  WHERE u.precio_nuevo <> v.precio
$q$);

-------------------------------------------------------------------------------
-- 5. Modelo: composición, jerarquía, documentos, producción
-------------------------------------------------------------------------------
SELECT pg_temp.control('modelo', 'composición que no suma 100 o vino sin cepas', $q$
  SELECT count(*) FROM vino AS v
  LEFT JOIN (SELECT cod_vino, SUM(porcentaje) AS s FROM composicion_vino GROUP BY cod_vino) AS c USING (cod_vino)
  WHERE c.s IS DISTINCT FROM 100
$q$);

SELECT pg_temp.control('modelo', 'cliente sin su subtipo o en un subtipo incorrecto', $q$
  SELECT count(*) FROM cliente AS c
  WHERE (c.tipo = 'socio') <> EXISTS (SELECT 1 FROM socio_club AS s WHERE s.id_cliente = c.id_cliente)
     OR (c.tipo = 'distribuidor') <> EXISTS (SELECT 1 FROM distribuidor AS d WHERE d.id_cliente = c.id_cliente)
     OR (c.tipo = 'exportador') <> EXISTS (SELECT 1 FROM exportador AS e WHERE e.id_cliente = c.id_cliente)
$q$);

SELECT pg_temp.control('modelo', 'ingresos terminados o procesados sin renglones', $q$
  SELECT count(*) FROM ingreso AS i WHERE i.estado <> 'en_confeccion'
    AND NOT EXISTS (SELECT 1 FROM renglon_ingreso AS r WHERE r.cod_ingreso = i.cod_ingreso)
$q$);

SELECT pg_temp.control('modelo', 'transferencias terminadas o procesadas sin renglones', $q$
  SELECT count(*) FROM transferencia AS t WHERE t.estado <> 'en_confeccion'
    AND NOT EXISTS (SELECT 1 FROM renglon_transferencia AS r WHERE r.nro_transferencia = t.nro_transferencia)
$q$);

SELECT pg_temp.control('modelo', 'cosechas fuera de febrero a abril',
  'SELECT count(*) FROM lote_uva WHERE EXTRACT(MONTH FROM fecha_cosecha) NOT BETWEEN 2 AND 4');

SELECT pg_temp.control('modelo', 'excepciones de descuento cargadas (las asigna U6)',
  'SELECT count(*) FROM cliente WHERE descuento_excepcion IS NOT NULL');

-------------------------------------------------------------------------------
-- 6. Reglas de coherencia temporal y de negocio que ningún trigger valida
-------------------------------------------------------------------------------
SELECT pg_temp.control('coherencia', 'R1 comprobante anterior al alta del cliente', $q$
  SELECT count(*) FROM comprobante AS c JOIN cliente AS cl USING (id_cliente)
  WHERE pg_temp.dia(c.fecha) < cl.fecha_alta
$q$);

-- Margen: un vino se mueve desde el 1/1 del año siguiente a su añada.
SELECT pg_temp.control('coherencia', 'R2 ingreso de un vino antes de su añada + 1', $q$
  SELECT count(*) FROM renglon_ingreso AS r JOIN ingreso AS i USING (cod_ingreso) JOIN vino AS v USING (cod_vino)
  WHERE pg_temp.dia(i.fecha) < make_date(v.anada + 1, 1, 1)
$q$);
SELECT pg_temp.control('coherencia', 'R2 transferencia de un vino antes de su añada + 1', $q$
  SELECT count(*) FROM renglon_transferencia AS r JOIN transferencia AS t USING (nro_transferencia) JOIN vino AS v USING (cod_vino)
  WHERE t.fecha_confeccion < make_date(v.anada + 1, 1, 1)
$q$);
SELECT pg_temp.control('coherencia', 'R2 venta de un vino antes de su añada + 1', $q$
  SELECT count(*) FROM renglon_comprobante AS r JOIN comprobante AS c USING (nro_comprobante) JOIN vino AS v USING (cod_vino)
  WHERE pg_temp.dia(c.fecha) < make_date(v.anada + 1, 1, 1)
$q$);

SELECT pg_temp.control('coherencia', 'R3 renglón de ingreso con vino de otra bodega', $q$
  SELECT count(*) FROM renglon_ingreso AS r JOIN ingreso AS i USING (cod_ingreso) JOIN vino AS v USING (cod_vino)
  WHERE v.cuit_bodega <> i.cuit_bodega
$q$);

SELECT pg_temp.control('coherencia', 'R4 análisis anterior a la cosecha de su lote', $q$
  SELECT count(*) FROM analisis_calidad AS a JOIN lote_uva AS l USING (nro_lote)
  WHERE a.fecha_analisis < l.fecha_cosecha
$q$);

SELECT pg_temp.control('coherencia', 'R5 fechas posteriores a FECHA_REFERENCIA', $q$
  SELECT (SELECT count(*) FROM cliente WHERE fecha_alta > pg_temp.fref())
       + (SELECT count(*) FROM empleado WHERE fecha_ingreso > pg_temp.fref())
       + (SELECT count(*) FROM permiso_exportacion WHERE fecha_emision > pg_temp.fref())
       + (SELECT count(*) FROM auditoria_precio WHERE pg_temp.dia(fecha_hora) > pg_temp.fref())
       + (SELECT count(*) FROM comprobante WHERE pg_temp.dia(fecha) > pg_temp.fref())
       + (SELECT count(*) FROM ingreso WHERE pg_temp.dia(fecha) > pg_temp.fref())
       + (SELECT count(*) FROM transferencia WHERE fecha_confeccion > pg_temp.fref())
       + (SELECT count(*) FROM lote_uva WHERE fecha_cosecha > pg_temp.fref())
       + (SELECT count(*) FROM analisis_calidad WHERE fecha_analisis > pg_temp.fref())
$q$);

SELECT pg_temp.control('coherencia', 'R6 vinos de añada futura',
  'SELECT count(*) FROM vino WHERE anada > EXTRACT(YEAR FROM pg_temp.fref())');

SELECT pg_temp.control('coherencia', 'R7 faltan permisos vigentes',
  'SELECT CASE WHEN EXISTS (SELECT 1 FROM permiso_exportacion WHERE fecha_vencimiento >= pg_temp.fref()) THEN 0 ELSE 1 END');
SELECT pg_temp.control('coherencia', 'R7 faltan permisos vencidos',
  'SELECT CASE WHEN EXISTS (SELECT 1 FROM permiso_exportacion WHERE fecha_vencimiento < pg_temp.fref()) THEN 0 ELSE 1 END');

-------------------------------------------------------------------------------
-- 7. Triggers: ninguno quedó deshabilitado después de la carga
-------------------------------------------------------------------------------
SELECT pg_temp.control('triggers', 'triggers deshabilitados (tgenabled = D)', $q$
  SELECT count(*) FROM pg_trigger AS t JOIN pg_class AS c ON c.oid = t.tgrelid
  WHERE c.relnamespace = 'bodegas'::regnamespace AND t.tgenabled = 'D'
$q$);

-------------------------------------------------------------------------------
-- 8. Cobertura para las consultas de la Etapa 5 (relativa a FECHA_REFERENCIA;
--    en la Etapa 5 las consultas usan CURRENT_DATE: regenerar con la fecha
--    del día antes de la demo).
-------------------------------------------------------------------------------
CREATE FUNCTION pg_temp.falta(p_existe BOOLEAN) RETURNS BIGINT LANGUAGE sql
AS $$ SELECT CASE WHEN p_existe THEN 0 ELSE 1 END $$;

SELECT pg_temp.control('cobertura', 'U2 empleados con más de 5 años',
  'SELECT pg_temp.falta(EXISTS (SELECT 1 FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso, pg_temp.fref()) > 5))');
SELECT pg_temp.control('cobertura', 'U4 salas que cierran lunes y salas que cierran miércoles',
  $q$SELECT pg_temp.falta(EXISTS (SELECT 1 FROM sala_venta WHERE dia_cierre = 'lunes')
                          AND EXISTS (SELECT 1 FROM sala_venta WHERE dia_cierre = 'miercoles'))$q$);
SELECT pg_temp.control('cobertura', 'U6 exportadores con más de 3 permisos',
  'SELECT pg_temp.falta(EXISTS (SELECT 1 FROM permiso_exportacion GROUP BY id_exportador HAVING count(*) > 3))');
SELECT pg_temp.control('cobertura', 'I1 General Alvear y un transportista con mínimo único en el trimestre que no la cubre', $q$
  WITH envios AS (
    SELECT t.cod_transportista, count(i.cod_ingreso) AS n
    FROM transportista AS t
    LEFT JOIN ingreso AS i ON i.cod_transportista = t.cod_transportista
     AND pg_temp.dia(i.fecha) > pg_temp.fref() - INTERVAL '3 months'
    GROUP BY t.cod_transportista
  ), minimo AS (SELECT * FROM envios WHERE n = (SELECT min(n) FROM envios))
  SELECT pg_temp.falta(
    EXISTS (SELECT 1 FROM localidad WHERE nombre = 'General Alvear')
    AND (SELECT count(*) FROM minimo) = 1
    AND NOT EXISTS (SELECT 1 FROM minimo JOIN transportista_localidad AS tl USING (cod_transportista)
                    JOIN localidad AS l USING (id_localidad) WHERE l.nombre = 'General Alvear'))
$q$);
SELECT pg_temp.control('cobertura', 'I2 tintos de 14° o más',
  $q$SELECT pg_temp.falta(EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14))$q$);
SELECT pg_temp.control('cobertura', 'I3 sala 1 con stock de al menos 3 vinos',
  'SELECT pg_temp.falta((SELECT count(*) FROM stock_sala WHERE id_sala = 1 AND cantidad > 0) >= 3)');
SELECT pg_temp.control('cobertura', 'I6 Malbec Reserva de 750 ml',
  $q$SELECT pg_temp.falta(EXISTS (SELECT 1 FROM vino WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750))$q$);
SELECT pg_temp.control('cobertura', 'D1 comprobantes de socios de más de 5 años', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM comprobante AS c JOIN cliente AS cl USING (id_cliente)
    WHERE cl.tipo = 'socio' AND pg_temp.dia(c.fecha) < pg_temp.fref() - INTERVAL '5 years'))
$q$);
SELECT pg_temp.control('cobertura', 'D2 cepas sin vinos ni parcelas', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM cepa AS c
    WHERE NOT EXISTS (SELECT 1 FROM composicion_vino AS v WHERE v.id_cepa = c.id_cepa)
      AND NOT EXISTS (SELECT 1 FROM parcela AS p WHERE p.id_cepa = c.id_cepa)))
$q$);
SELECT pg_temp.control('cobertura', 'D3 sala con empleados de menos de 2 años',
  'SELECT pg_temp.falta(EXISTS (SELECT 1 FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso, pg_temp.fref()) < 2))');
SELECT pg_temp.control('cobertura', 'D4 socios sin compras con alta de más de 5 años', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM cliente AS c WHERE c.tipo = 'socio'
    AND c.fecha_alta < pg_temp.fref() - INTERVAL '5 years'
    AND NOT EXISTS (SELECT 1 FROM comprobante AS x WHERE x.id_cliente = c.id_cliente)))
$q$);
SELECT pg_temp.control('cobertura', 'D6 socios sin compras en más de una localidad', $q$
  SELECT pg_temp.falta((SELECT count(DISTINCT c.id_localidad) FROM cliente AS c WHERE c.tipo = 'socio'
    AND NOT EXISTS (SELECT 1 FROM comprobante AS x WHERE x.id_cliente = c.id_cliente)) > 1)
$q$);
SELECT pg_temp.control('cobertura', 'D5 ingresos procesados de más de 365 días', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM ingreso WHERE estado = 'procesado'
    AND pg_temp.dia(fecha) < pg_temp.fref() - 365))
$q$);
SELECT pg_temp.control('cobertura', 'S2 vinos vendidos en todas las salas', $q$
  SELECT pg_temp.falta(EXISTS (
    SELECT r.cod_vino FROM renglon_comprobante AS r JOIN comprobante AS c USING (nro_comprobante)
    GROUP BY r.cod_vino HAVING count(DISTINCT c.id_sala) = (SELECT count(*) FROM sala_venta)))
$q$);
SELECT pg_temp.control('cobertura', 'S3 ventas de la última semana con los 3 tipos de cliente en una sala', $q$
  SELECT pg_temp.falta(EXISTS (
    SELECT c.id_sala FROM comprobante AS c JOIN cliente AS cl USING (id_cliente)
    WHERE pg_temp.dia(c.fecha) > pg_temp.fref() - 7
    GROUP BY c.id_sala HAVING count(DISTINCT cl.tipo) = 3))
$q$);
SELECT pg_temp.control('cobertura', 'S4 un vino transferido a 5 o más salas en los últimos 15 días', $q$
  SELECT pg_temp.falta(EXISTS (
    SELECT r.cod_vino FROM transferencia AS t JOIN renglon_transferencia AS r USING (nro_transferencia)
    WHERE t.fecha_confeccion > pg_temp.fref() - 15
    GROUP BY r.cod_vino HAVING count(DISTINCT t.id_sala) >= 5))
$q$);
SELECT pg_temp.control('cobertura', 'S5 transferencias pendientes en varias salas', $q$
  SELECT pg_temp.falta((SELECT count(DISTINCT id_sala) FROM transferencia WHERE estado <> 'procesado') > 1)
$q$);
SELECT pg_temp.control('cobertura', 'S6 vinos sin stock en una sala y con stock en depósito', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM stock_deposito AS d WHERE d.cantidad > 0
    AND NOT EXISTS (SELECT 1 FROM stock_sala AS s WHERE s.id_sala = 1 AND s.cod_vino = d.cod_vino AND s.cantidad > 0)))
$q$);
SELECT pg_temp.control('cobertura', 'S7 ingresos del último mes con un transportista más activo único', $q$
  WITH n AS (SELECT cod_transportista, count(*) AS c FROM ingreso
             WHERE pg_temp.dia(fecha) > pg_temp.fref() - INTERVAL '1 month' GROUP BY cod_transportista)
  SELECT pg_temp.falta((SELECT count(*) FROM n WHERE c = (SELECT max(c) FROM n)) = 1)
$q$);
SELECT pg_temp.control('cobertura', 'S8 ventas en el último trimestre en todas las salas', $q$
  SELECT pg_temp.falta((SELECT count(DISTINCT id_sala) FROM comprobante
    WHERE pg_temp.dia(fecha) > pg_temp.fref() - INTERVAL '3 months') = (SELECT count(*) FROM sala_venta))
$q$);
SELECT pg_temp.control('cobertura', 'S10 parcelas con varias campañas', $q$
  SELECT pg_temp.falta(EXISTS (SELECT 1 FROM lote_uva GROUP BY id_finca, nro_parcela HAVING count(*) > 1))
$q$);
SELECT pg_temp.control('cobertura', 'S12 cliente que compró todos los vinos de una bodega', $q$
  SELECT pg_temp.falta(EXISTS (
    SELECT 1 FROM cliente AS cl CROSS JOIN bodega AS b
    WHERE NOT EXISTS (
      SELECT 1 FROM vino AS v WHERE v.cuit_bodega = b.cuit
        AND NOT EXISTS (SELECT 1 FROM comprobante AS c JOIN renglon_comprobante AS r USING (nro_comprobante)
                        WHERE c.id_cliente = cl.id_cliente AND r.cod_vino = v.cod_vino))))
$q$);
SELECT pg_temp.control('cobertura', 'S12 clientes con compras que nunca compraron tintos', $q$
  SELECT pg_temp.falta(EXISTS (
    SELECT 1 FROM cliente AS cl
    WHERE EXISTS (SELECT 1 FROM comprobante AS c WHERE c.id_cliente = cl.id_cliente)
      AND NOT EXISTS (SELECT 1 FROM comprobante AS c JOIN renglon_comprobante AS r USING (nro_comprobante)
                      JOIN vino AS v USING (cod_vino) WHERE c.id_cliente = cl.id_cliente AND v.tipo = 'tinto')))
$q$);

-------------------------------------------------------------------------------
-- Resultado
-------------------------------------------------------------------------------
\o
SELECT tabla, filas FROM conteo ORDER BY filas DESC, tabla;

SELECT grupo, control, violaciones,
       CASE WHEN violaciones = 0 THEN 'OK' ELSE 'FALLA' END AS resultado
FROM resultado_control
WHERE grupo <> 'huérfanos'
ORDER BY orden;

SELECT 'huérfanos' AS grupo, count(*) AS fk_revisadas, SUM(violaciones) AS violaciones
FROM resultado_control WHERE grupo = 'huérfanos';

DO $$
DECLARE
  v_fallas TEXT;
BEGIN
  SELECT string_agg(format('%s / %s: %s', grupo, control, violaciones), E'\n' ORDER BY orden)
  INTO v_fallas FROM resultado_control WHERE violaciones <> 0;
  IF v_fallas IS NOT NULL THEN
    RAISE EXCEPTION E'Controles con inconsistencias:\n%', v_fallas;
  END IF;
END;
$$;

ROLLBACK;
\echo 'OK: las consultas de control no encontraron inconsistencias.'
