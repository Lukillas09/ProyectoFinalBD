-- =============================================================================
-- PLANTILLA COMÚN PARA CONSULTAS SQL - ETAPA 5
-- Bodegas del Atuel - Trabajo Práctico Integrador BD 2026
-- =============================================================================
--
-- Esta plantilla sirve de base estructurada y documentada para las consultas
-- requeridas en la Etapa 5: INSERT, UPDATE, SELECT y DELETE.
--
-- Cada consulta individual debe copiar esta plantilla, completando todas las
-- secciones marcadas con [COMPLETAR]. Los archivos finales se entregan como:
--   consultas/insert.sql
--   consultas/update.sql
--   consultas/delete.sql
--   consultas/select.sql
--
-- Convenciones:
-- - SQL en minúsculas para palabras clave, mayúsculas para nombres de objetos
--   cuando se desee resaltar (opcional, pero consistente).
-- - Comentarios explicativos con -- para cada paso lógico.
-- - Parámetros de ejemplo usan la sintaxis de psql: :parametro
-- - Valores concretos del dataset de prueba (Etapa 3) se indican en la sección
--   correspondiente.
--
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS DE LA CONSULTA
-- -----------------------------------------------------------------------------
-- Código:           [COMPLETAR: ej. U1, I3, D2, S5]
-- Tipo:             [COMPLETAR: UPDATE | INSERT | DELETE | SELECT]
-- Enunciado:        [COMPLETAR: descripción breve del requerimiento]
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       [COMPLETAR: sección del PDF o requisito, ej. "3.7 Tabla Consultas SQL"]
-- Dataset:          [COMPLETAR: SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1]
-- -----------------------------------------------------------------------------

-- =============================================================================
-- 1. ANÁLISIS Y ESTRATEGIA
-- =============================================================================
--
-- Describir aquí la estrategia de resolución:
-- - Qué tablas intervienen y por qué.
-- - Qué joins, subconsultas, CTEs o funciones de ventana se usan.
-- - Cómo se calculan períodos relativos (usar CURRENT_DATE, no fechas fijas).
-- - Qué funciones, procedimientos o triggers del modelo se invocan/activan.
-- - Consideraciones de rendimiento (índices relevantes, selectividad).
-- - Para modificaciones: qué constraints/CHECKs/FOREIGN KEYs/TRIGGERS se
--   disparan o podrían violarse.
--
-- [COMPLETAR: estrategia detallada]
--
-- Ejemplo para U1 (Recalcular totales con descuento por tipo de cliente):
--   Se usa fn_recalcular_comprobante(comprobante) que a su vez invoca
--   fn_descuento_cliente(id_cliente) y fn_total_comprobante(nro_comprobante).
--   El trigger trg_comprobante_recalcular_total (AFTER UPDATE OF descuento
--   ON comprobante) recalcula el total. La PK de comprobante y la FK a cliente
--   garantizan integridad referencial. RN-06 y RN-08 son las reglas de negocio
--   involucradas.
--

-- =============================================================================
-- 2. VALORES CONCRETOS DEL DATASET (ETAPA 3)
-- -----------------------------------------------------------------------------
--
-- Indicar aquí valores reales del dataset generado con la semilla de referencia
-- que sirvan para probar y demostrar la consulta. Estos valores provienen de
-- la carga masiva reproducible (SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27,
-- ESCALA=1).
--
-- Para obtener valores reales, ejecutar consultas de exploración como:
--   SELECT * FROM bodegas.comprobante ORDER BY fecha DESC LIMIT 5;
--   SELECT * FROM bodegas.cliente WHERE tipo = 'socio' LIMIT 5;
--   SELECT * FROM bodegas.vino WHERE graduacion >= 14 AND tipo = 'tinto' LIMIT 5;
--
-- [COMPLETAR: valores concretos relevantes]
--
-- Ejemplo para I3 (Crear comprobante con 3 renglones):
--   Cliente: id_cliente = 12345 (socio, descuento 10%)
--   Sala: id_sala = 1
--   Vinos: cod_vino = 'V001' (precio 1500), 'V002' (precio 2200), 'V003' (precio 1800)
--   Cantidades: 2, 1, 3 respectivamente
--   Fecha: CURRENT_DATE (hoy en la base cargada)
--

-- =============================================================================
-- 3. PROTOCOLO DE EJECUCIÓN (PARA MODIFICACIONES: INSERT/UPDATE/DELETE)
-- -----------------------------------------------------------------------------
--
-- Las consultas de modificación DEBEN seguir este protocolo obligatorio:
--
--   BEGIN;
--   -- Control previo: estado ANTES de la modificación
--   [CONSULTA DE CONTROL PREVIO]
--   -- Sentencia principal
--   [SENTENCIA INSERT/UPDATE/DELETE]
--   -- Control posterior: estado DESPUÉS de la modificación
--   [CONSULTA DE CONTROL POSTERIOR]
--   -- Verificar filas afectadas
--   GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
--   RAISE NOTICE 'Filas afectadas: %', filas_afectadas;
--   ROLLBACK;  -- Siempre ROLLBACK en pruebas; COMMIT solo en producción real
--
-- Para SELECT no aplica transacción, pero se documenta la consulta de control.
--
-- IMPORTANTE: En los archivos finales (insert.sql, update.sql, delete.sql)
-- cada consulta individual se ejecuta en su propio bloque BEGIN...ROLLBACK.
-- No anidar transacciones.
--

-- =============================================================================
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO INVOLUCRADOS (SOLO MODIFICACIONES)
-- -----------------------------------------------------------------------------
--
-- Listar explícitamente qué mecanismos de PostgreSQL se disparan o validan:
--
-- Triggers BEFORE:
--   [COMPLETAR: ej. trg_renglon_comprobante_validar_stock (RN-09)]
-- Triggers AFTER:
--   [COMPLETAR: ej. trg_comprobante_recalcular_total (RN-08)]
-- Constraint triggers (DEFERRABLE):
--   [COMPLETAR: ej. trg_composicion_vino_suma_100 (RN-05)]
-- CHECK constraints:
--   [COMPLETAR: ej. ck_renglon_cantidad_positiva, ck_comprobante_total_positivo]
-- FOREIGN KEY constraints:
--   [COMPLETAR: ej. fk_comprobante_id_cliente, fk_renglon_comprobante_cod_vino]
-- Reglas de negocio (RN-XX):
--   [COMPLETAR: ej. RN-06, RN-08, RN-09, RN-12, RN-13]
--
-- Para cada uno, indicar si se espera éxito o rechazo controlado en el caso
-- de prueba negativo.
--

-- =============================================================================
-- 5. CONSULTA SQL PRINCIPAL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- OPCIÓN A: UPDATE
-- -----------------------------------------------------------------------------
/*
UPDATE bodegas.[tabla]
   SET [columna1] = [expresion1],
       [columna2] = [expresion2],
       ...
 WHERE [condicion]
   AND [condicion_adicional];
   -- Usar parámetros: WHERE id = :id_valor
   -- Para UPDATE masivos con JOIN/CTE:
   -- UPDATE bodegas.tabla t
   --    SET col = subquery.valor
   --   FROM (SELECT ...) subquery
   --  WHERE t.id = subquery.id;
*/

-- -----------------------------------------------------------------------------
-- OPCIÓN B: INSERT
-- -----------------------------------------------------------------------------
/*
-- INSERT simple (una fila)
INSERT INTO bodegas.[tabla] (columna1, columna2, columna3, ...)
VALUES (:valor1, :valor2, :valor3, ...);

-- INSERT con SELECT (varias filas)
INSERT INTO bodegas.[tabla] (columna1, columna2, columna3, ...)
SELECT [expresion1], [expresion2], [expresion3], ...
  FROM [origen]
 WHERE [condicion]
   AND NOT EXISTS (SELECT 1 FROM bodegas.[tabla] t WHERE t.pk = origen.pk);
   -- El NOT EXISTS evita duplicados si la consulta es re-ejecutable

-- INSERT multi-tabla con CTE (para comprobante + renglones)
WITH nueva_cabecera AS (
  INSERT INTO bodegas.comprobante (fecha, id_cliente, id_sala, subtotal, descuento, total)
  VALUES (CURRENT_DATE, :id_cliente, :id_sala, 0, 0, 0)
  RETURNING nro_comprobante
),
nuevos_renglones AS (
  INSERT INTO bodegas.renglon_comprobante (nro_comprobante, cod_vino, cantidad, precio_unitario, descuento, subtotal)
  SELECT nc.nro_comprobante, v.cod_vino, v.cantidad, v.precio, v.descuento, v.subtotal
    FROM (VALUES
      (:cod_vino_1, :cant_1, :precio_1, :desc_1, :subtotal_1),
      (:cod_vino_2, :cant_2, :precio_2, :desc_2, :subtotal_2),
      (:cod_vino_3, :cant_3, :precio_3, :desc_3, :subtotal_3)
    ) AS v(cod_vino, cantidad, precio, descuento, subtotal)
    CROSS JOIN nueva_cabecera nc
  RETURNING nro_comprobante, cod_vino
)
SELECT * FROM nueva_cabecera;
*/

-- -----------------------------------------------------------------------------
-- OPCIÓN C: DELETE
-- -----------------------------------------------------------------------------
/*
-- DELETE simple
DELETE FROM bodegas.[tabla]
 WHERE [condicion]
   AND [condicion_adicional];

-- DELETE con subconsulta / EXISTS (para integridad referencial)
DELETE FROM bodegas.[tabla_padre]
 WHERE EXISTS (
   SELECT 1 FROM bodegas.[tabla_hija] h
    WHERE h.fk = tabla_padre.pk
      AND [condicion_hija]
 );

-- DELETE en cascada controlada (cabecera + renglones en una transacción)
-- Nota: las FK tienen ON DELETE RESTRICT (RN-14), así que se debe borrar
-- primero los renglones y luego la cabecera, o usar una CTE:
WITH renglones_borrados AS (
  DELETE FROM bodegas.renglon_comprobante
   WHERE nro_comprobante IN (SELECT nro_comprobante FROM bodegas.comprobante WHERE [condicion])
   RETURNING nro_comprobante
),
cabeceras_borradas AS (
  DELETE FROM bodegas.comprobante
   WHERE [condicion]
   RETURNING nro_comprobante
)
SELECT count(*) AS comprobantes_borrados, 
       (SELECT count(*) FROM renglones_borrados) AS renglones_borrados
  FROM cabeceras_borradas;
*/

-- -----------------------------------------------------------------------------
-- OPCIÓN D: SELECT
-- -----------------------------------------------------------------------------
/*
-- SELECT simple con filtros y joins
SELECT [columnas_explicitas]
  FROM bodegas.[tabla_principal] t
  JOIN bodegas.[tabla_relacionada] r ON t.fk = r.pk
 WHERE [condicion]
   AND t.fecha >= CURRENT_DATE - INTERVAL '7 days'  -- períodos relativos
 ORDER BY [columna_orden]
 LIMIT [n];

-- SELECT con agregación y GROUP BY / HAVING
SELECT t.id_sala, count(*) AS total_ventas, sum(t.total) AS monto_total
  FROM bodegas.comprobante t
 WHERE t.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.id_sala
 HAVING count(*) > 10
 ORDER BY monto_total DESC;

-- SELECT con división relacional (ej. S2: vinos vendidos en TODAS las salas)
SELECT v.cod_vino, v.nombre
  FROM bodegas.vino v
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.sala s
    WHERE NOT EXISTS (
      SELECT 1 FROM bodegas.comprobante c
      JOIN bodegas.renglon_comprobante rc ON c.nro_comprobante = rc.nro_comprobante
       WHERE c.id_sala = s.id_sala
         AND rc.cod_vino = v.cod_vino
         AND c.fecha >= CURRENT_DATE - INTERVAL '1 year'
    )
 );

-- SELECT con funciones de ventana (ej. S11: ranking por sala)
SELECT *
  FROM (
    SELECT s.nombre AS sala, v.nombre AS vino, sum(rc.cantidad) AS botellas,
           RANK() OVER (PARTITION BY s.id_sala ORDER BY sum(rc.cantidad) DESC) AS rnk
      FROM bodegas.sala s
      JOIN bodegas.comprobante c ON c.id_sala = s.id_sala
      JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
      JOIN bodegas.vino v ON v.cod_vino = rc.cod_vino
     WHERE c.fecha >= CURRENT_DATE - INTERVAL '1 year'
     GROUP BY s.id_sala, s.nombre, v.cod_vino, v.nombre
  ) ranked
 WHERE rnk <= 10
 ORDER BY sala, rnk;

-- SELECT con CTEs para consultas complejas (ej. S10: rendimiento kg/ha)
WITH rendimiento_parcela AS (
  SELECT l.finca, l.nro_parcela, l.campana,
         sum(l.kg) / NULLIF(sum(p.superficie), 0) AS kg_ha
    FROM bodegas.lote l
    JOIN bodegas.parcela p ON p.finca = l.finca AND p.nro_parcela = l.nro_parcela
   GROUP BY l.finca, l.nro_parcela, l.campana
),
promedio_finca AS (
  SELECT finca, campana, avg(kg_ha) AS prom_kg_ha
    FROM rendimiento_parcela
   GROUP BY finca, campana
)
SELECT rp.finca, rp.nro_parcela, rp.campana, rp.kg_ha, pf.prom_kg_ha
  FROM rendimiento_parcela rp
  JOIN promedio_finca pf ON pf.finca = rp.finca AND pf.campana = rp.campana
 WHERE rp.kg_ha < pf.prom_kg_ha
 ORDER BY rp.finca, rp.nro_parcela, rp.campana;
*/

-- =============================================================================
-- 6. CONTROLES PREVIO Y POSTERIOR (PARA MODIFICACIONES)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Control previo: estado ANTES de la modificación
-- -----------------------------------------------------------------------------
/*
-- Ejemplo para UPDATE de precios (U3):
SELECT v.cod_vino, v.nombre, v.precio AS precio_antes
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.razon_social = 'Bodega Ejemplo S.A.'
 ORDER BY v.cod_vino;

-- Ejemplo para DELETE de comprobantes antiguos (D1):
SELECT count(*) AS comprobantes_a_borrar,
       sum(total) AS monto_total_a_borrar
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND cl.tipo = 'socio';

-- Ejemplo para INSERT de comprobante (I3) - verificar stock previo:
SELECT v.cod_vino, v.nombre, s.cantidad AS stock_sala_antes
  FROM bodegas.stock_sala s
  JOIN bodegas.vino v ON v.cod_vino = s.cod_vino
 WHERE s.id_sala = 1
   AND v.cod_vino IN ('V001', 'V002', 'V003');
*/

-- -----------------------------------------------------------------------------
-- Control posterior: estado DESPUÉS de la modificación
-- -----------------------------------------------------------------------------
/*
-- Ejemplo para UPDATE de precios (U3):
SELECT v.cod_vino, v.nombre, v.precio AS precio_despues,
       round(v.precio / NULLIF(v.precio_original, 0) * 100 - 100, 2) AS pct_cambio
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE b.razon_social = 'Bodega Ejemplo S.A.'
 ORDER BY v.cod_vino;

-- Ejemplo para DELETE (D1) - verificar que no quedaron:
SELECT count(*) AS comprobantes_remanentes
  FROM bodegas.comprobante c
  JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
 WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years'
   AND cl.tipo = 'socio';

-- Ejemplo para INSERT (I3) - verificar comprobante creado y stock descontado:
SELECT c.nro_comprobante, c.fecha, c.id_cliente, c.id_sala,
       c.subtotal, c.descuento, c.total,
       rc.cod_vino, rc.cantidad, rc.precio_unitario, rc.descuento, rc.subtotal
  FROM bodegas.comprobante c
  JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
 WHERE c.nro_comprobante = (SELECT max(nro_comprobante) FROM bodegas.comprobante);

SELECT v.cod_vino, v.nombre, s.cantidad AS stock_sala_despues
  FROM bodegas.stock_sala s
  JOIN bodegas.vino v ON v.cod_vino = s.cod_vino
 WHERE s.id_sala = 1
   AND v.cod_vino IN ('V001', 'V002', 'V003');
*/

-- =============================================================================
-- 7. VERIFICACIÓN DE FILAS AFECTADAS
-- =============================================================================
/*
-- En psql / DO block:
GET DIAGNOSTICS filas_afectadas = ROW_COUNT;
RAISE NOTICE 'Filas afectadas: %', filas_afectadas;

-- En script SQL plano (psql imprime automáticamente el tag de la sentencia):
-- UPDATE 3
-- INSERT 0 1
-- DELETE 5
-- SELECT 10
*/

-- =============================================================================
-- 8. PLAN DE EJECUCIÓN (EXPLAIN ANALYZE) - OBLIGATORIO PARA S9-S12
-- =============================================================================
/*
-- Para consultas SELECT de la Etapa 5 (especialmente S9, S10, S11, S12)
-- y las consultas candidatas de rendimiento, se debe adjuntar el plan:

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
[CONSULTA SELECT COMPLETA];

-- Guardar la salida en docs/rendimiento/planes/[codigo]_[etiqueta].txt
-- donde etiqueta es "antes" o "despues" de índices, o "etapa5".
--
-- Analizar:
-- - Tipo de nodo (Seq Scan, Index Scan, Hash Join, etc.)
-- - Filas reales vs estimadas (rows= vs rows=)
-- - Bloques leídos (shared hit/read)
-- - Tiempo de ejecución (actual time=... ms)
-- - Si usa los índices creados en 008_indices.sql
*/

-- =============================================================================
-- 9. CASOS DE PRUEBA NEGATIVOS (RECHAZOS ESPERADOS)
-- =============================================================================
/*
-- Documentar aquí los casos que DEBEN fallar y por qué.
-- Cada caso indica el SQLSTATE esperado y, si aplica, la constraint.

-- Ejemplo para U3 (aumentar precio 13%):
-- Caso: bodega inexistente
-- UPDATE bodegas.vino SET precio = precio * 1.13 WHERE cuit_bodega = '99999999999';
-- Esperado: 0 filas afectadas (no error, solo no hace nada)

-- Caso: precio resultante violaría CHECK (precio > 0) - imposible al aumentar

-- Ejemplo para I3 (crear comprobante):
-- Caso: cliente inexistente
-- INSERT ... id_cliente = 999999;
-- Esperado: SQLSTATE 23503 (foreign_key_violation), constraint fk_comprobante_id_cliente

-- Caso: vino sin stock en sala
-- INSERT renglón con cod_vino que tiene stock 0 en la sala
-- Esperado: SQLSTATE P0001 (raise_exception) del trigger trg_renglon_comprobante_validar_stock (RN-09)
-- Mensaje: "Stock insuficiente en sala % para el vino %"

-- Caso: descuento de renglón no coincide con tipo de cliente
-- INSERT renglón con descuento distinto al que devuelve fn_descuento_cliente
-- Esperado: SQLSTATE 23514 (check_violation), constraint ck_renglon_descuento_tipo
*/

-- =============================================================================
-- 10. OBSERVACIONES Y DECISIONES DE DISEÑO
-- =============================================================================
--
-- [COMPLETAR: cualquier observación relevante, decisiones tomadas, alternativas
--  descartadas, limitaciones conocidas, dependencias de otras consultas, etc.]
--
-- Ejemplos:
-- - "Se usa fn_registrar_venta en lugar de INSERT directo porque encapsula
--   la lógica de RN-08, RN-09, RN-12 y RN-13 en una sola transacción atómica."
-- - "El período 'último trimestre' se calcula como CURRENT_DATE - INTERVAL '3 months'
--   según la definición de la consigna, no con fechas fijas."
-- - "Para U1 (recalcular totales) se usa fn_recalcular_comprobante que respeta
--   la inmutabilidad de renglones confirmados (RN-12 / columna xact_alta)."
-- - "La consulta S2 usa división relacional con doble NOT EXISTS, patrón estándar
--   para 'todos los valores de un conjunto'."
--

-- =============================================================================
-- FIN DE PLANTILLA
-- =============================================================================
--
-- Instrucciones para usar esta plantilla:
--
-- 1. Copiar este archivo al archivo correspondiente:
--    cp consultas/plantilla_consultas.sql consultas/update.sql
--    cp consultas/plantilla_consultas.sql consultas/insert.sql
--    cp consultas/plantilla_consultas.sql consultas/delete.sql
--    cp consultas/plantilla_consultas.sql consultas/select.sql
--
-- 2. En cada archivo, completar una sección por cada consulta del tipo
--    correspondiente (U1-U6, I1-I6, D1-D6, S1-S12).
--
-- 3. Mantener el orden numérico de los códigos dentro de cada archivo.
--
-- 4. Eliminar las secciones de OPCIÓN que no correspondan al tipo de consulta
--    del archivo (ej. en update.sql mantener solo OPCIÓN A).
--
-- 5. Verificar que cada consulta tenga:
--    [x] Código, Tipo, Enunciado, Autor, Fecha, Referencia, Dataset
--    [x] Estrategia clara y completa
--    [x] Valores concretos del dataset de referencia
--    [x] Protocolo BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK
--    [x] Triggers, constraints y RN involucrados (solo modificaciones)
--    [x] SQL principal comentado y parametrizado
--    [x] Controles previo y posterior con consultas reales
--    [x] Filas afectadas documentadas
--    [x] EXPLAIN ANALYZE para S9-S12 y consultas de rendimiento
--    [x] Casos de prueba negativos con SQLSTATE esperado
--    [x] Observaciones y decisiones de diseño
--
-- 6. Probar cada consulta en la base cargada (Etapa 3) ejecutando el bloque
--    completo con psql y verificando que los controles son consistentes.
--
-- 7. No commitear datos reales ni resultados de ejecución; solo el SQL
--    documentado y parametrizado.