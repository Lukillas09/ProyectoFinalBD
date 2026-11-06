-- =============================================================================
-- CONSULTAS INSERT - ETAPA 5
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
--   docker compose exec db /opt/bodegas/consultas/ejecutar.sh insert.sql
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
-- Cada uno tiene un valor por omisión que se reemplaza desde la línea de
-- comandos, por ejemplo: ejecutar.sh insert.sql -v id_cliente=7
-- Los valores son identificadores de catálogo de la carga (no dependen de
-- FECHA_REFERENCIA) o datos nuevos que no existen en ella.
-- =============================================================================

-- I3: cliente, tres vinos y cantidades de la venta en la sala 1.
-- El cliente es el primer socio. Los tipos de cliente dependen de la historia
-- simulada (con FECHA_REFERENCIA=2026-10-27 es el cliente 1; con 2026-11-05,
-- el 2), así que se elige al ejecutar, como en db/seed/post_carga.sql.
\if :{?id_cliente}
\else
  SELECT min(id_cliente) AS id_cliente FROM bodegas.cliente WHERE tipo = 'socio'
  \gset
\endif
-- Los vinos dependen del stock actual de la sala 1, así que se eligen al
-- ejecutar (como db/seed/post_carga.sql): los tres con más stock, todos con al
-- menos 3 botellas. controles.sql garantiza que existen.
\if :{?vino1}
\else
  SELECT max(cod_vino) FILTER (WHERE n = 1) AS vino1,
         max(cod_vino) FILTER (WHERE n = 2) AS vino2,
         max(cod_vino) FILTER (WHERE n = 3) AS vino3
    FROM (SELECT cod_vino, row_number() OVER (ORDER BY cantidad DESC, cod_vino) AS n
            FROM bodegas.stock_sala
           WHERE id_sala = 1 AND cantidad >= 3) AS candidatos
   WHERE n <= 3
  \gset
\endif
\if :{?cant1}
\else
  \set cant1 1
\endif
\if :{?cant2}
\else
  \set cant2 2
\endif
\if :{?cant3}
\else
  \set cant3 3
\endif

-- I4: bodega nueva. CUIT con dígito verificador válido (la función cuit() de
-- db/seed/generar_datos.py) que no existe en la carga:
--   SELECT count(*) FROM bodegas.bodega WHERE cuit = '30712345671';  -- 0
\if :{?cuit_bodega_nueva}
\else
  \set cuit_bodega_nueva 30712345671
\endif
\if :{?razon_social}
\else
  \set razon_social 'Bodega Atuel Prueba S.A.'
\endif
\if :{?domicilio}
\else
  \set domicilio 'Ruta 143 km 5, San Rafael'
\endif

-- I5: sala nueva en Villa Atuel (id_localidad 19), una localidad sin salas:
--   SELECT id_localidad, nombre FROM bodegas.localidad l
--    WHERE NOT EXISTS (SELECT 1 FROM bodegas.sala_venta s WHERE s.id_localidad = l.id_localidad);
\if :{?id_localidad}
\else
  \set id_localidad 19
\endif
\if :{?calle}
\else
  \set calle 'Av. Mitre'
\endif
\if :{?numero}
\else
  \set numero 1500
\endif
\if :{?dia_cierre}
\else
  \set dia_cierre 'lunes'
\endif

-- I6: vino 4 ("Malbec Reserva" 750 ml, el caso que garantiza controles.sql),
-- su bodega y el transportista 1.
--   SELECT cod_vino, cuit_bodega FROM bodegas.vino
--    WHERE nombre = 'Malbec Reserva' AND volumen_ml = 750 ORDER BY cod_vino LIMIT 1;
\if :{?cod_vino}
\else
  \set cod_vino 4
\endif
\if :{?cuit_bodega}
\else
  \set cuit_bodega 30571896822
\endif
\if :{?cod_transportista}
\else
  \set cod_transportista 1
\endif

-- =============================================================================
-- I1: Vincular General Alvear con el transportista que realizó menos envíos
--     (ingresos trasladados) en el último trimestre
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I1
-- Tipo:             INSERT
-- Enunciado:        Vincular General Alvear con el transportista que realizó menos envíos en el último trimestre
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se debe insertar una fila en transportista_localidad vinculando la localidad
-- "General Alvear" (provincia Mendoza) con el transportista que tenga menos
-- ingresos (transportista.cobertura implica que puede operar en la localidad).
-- Período: "último trimestre" = CURRENT_DATE - INTERVAL '3 months'.
-- Se cuenta ingresos (cabeceras) por transportista donde el ingreso tenga fecha
-- en el último trimestre. Se elige el de menor cantidad (empate: menor cod_transportista).
-- NOT EXISTS evita duplicados si ya existe la vinculación.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver General Alvear:
-- SELECT id_localidad, nombre, provincia FROM bodegas.localidad WHERE nombre ILIKE 'General Alvear';
-- Ejecutar para ver transportistas con ingresos en último trimestre:
-- SELECT i.cod_transportista, t.razon_social, count(*) AS num_ingresos
--   FROM bodegas.ingreso i
--   JOIN bodegas.transportista t ON t.cod_transportista = i.cod_transportista
--  WHERE i.fecha >= CURRENT_DATE - INTERVAL '3 months'
--  GROUP BY i.cod_transportista, t.razon_social
--  ORDER BY num_ingresos ASC, i.cod_transportista;
-- Valores típicos: id_localidad de General Alvear ~ 50-100, transportistas 5-20.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I1'
BEGIN;

-- Control previo: verificar si ya existe la vinculación
SELECT tl.cod_transportista, t.razon_social, l.nombre AS localidad
  FROM bodegas.transportista_localidad tl
  JOIN bodegas.transportista t ON t.cod_transportista = tl.cod_transportista
  JOIN bodegas.localidad l ON l.id_localidad = tl.id_localidad
 WHERE l.nombre ILIKE 'General Alvear';

-- Control previo: transportista con menos ingresos en último trimestre
SELECT i.cod_transportista, t.razon_social, count(*) AS num_ingresos
  FROM bodegas.ingreso i
  JOIN bodegas.transportista t ON t.cod_transportista = i.cod_transportista
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY i.cod_transportista, t.razon_social
 ORDER BY num_ingresos ASC, i.cod_transportista
 LIMIT 1;

-- Sentencia principal: insertar vinculación si no existe
WITH transportista_menos AS (
  SELECT i.cod_transportista
    FROM bodegas.ingreso i
   WHERE i.fecha >= CURRENT_DATE - INTERVAL '3 months'
   GROUP BY i.cod_transportista
   ORDER BY count(*) ASC, i.cod_transportista
   LIMIT 1
),
localidad_alvear AS (
  SELECT id_localidad
    FROM bodegas.localidad
   WHERE nombre ILIKE 'General Alvear'
     AND provincia ILIKE 'Mendoza'
   LIMIT 1
)
INSERT INTO bodegas.transportista_localidad (cod_transportista, id_localidad)
SELECT tm.cod_transportista, la.id_localidad
  FROM transportista_menos tm
  CROSS JOIN localidad_alvear la
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.transportista_localidad tl
    WHERE tl.cod_transportista = tm.cod_transportista
      AND tl.id_localidad = la.id_localidad
 );
\echo 'Filas afectadas (I1):' :ROW_COUNT

-- Control posterior
SELECT tl.cod_transportista, t.razon_social, l.nombre AS localidad
  FROM bodegas.transportista_localidad tl
  JOIN bodegas.transportista t ON t.cod_transportista = tl.cod_transportista
  JOIN bodegas.localidad l ON l.id_localidad = tl.id_localidad
 WHERE l.nombre ILIKE 'General Alvear';

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints: ninguno directo en transportista_localidad
-- FOREIGN KEY constraints:
--   fk_transportista_localidad_transportista (cod_transportista -> transportista)
--   fk_transportista_localidad_localidad (id_localidad -> localidad)
--   Ambos ON UPDATE RESTRICT, ON DELETE CASCADE
-- Reglas de negocio: RN-02 (sala en una localidad, encargado regional único) - no afectado
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
WITH transportista_menos AS (
  SELECT i.cod_transportista
    FROM bodegas.ingreso i
   WHERE i.fecha >= CURRENT_DATE - INTERVAL '3 months'
   GROUP BY i.cod_transportista
   ORDER BY count(*) ASC, i.cod_transportista
   LIMIT 1
),
localidad_alvear AS (
  SELECT id_localidad
    FROM bodegas.localidad
   WHERE nombre ILIKE 'General Alvear'
     AND provincia ILIKE 'Mendoza'
   LIMIT 1
)
INSERT INTO bodegas.transportista_localidad (cod_transportista, id_localidad)
SELECT tm.cod_transportista, la.id_localidad
  FROM transportista_menos tm
  CROSS JOIN localidad_alvear la
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.transportista_localidad tl
    WHERE tl.cod_transportista = tm.cod_transportista
      AND tl.id_localidad = la.id_localidad
 );
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: localidad "General Alvear" no existe
-- La CTE localidad_alvear devuelve 0 filas -> INSERT no inserta nada (0 filas afectadas)

-- Caso: transportista ya vinculado a esa localidad
-- NOT EXISTS evita el INSERT -> 0 filas afectadas, sin error

-- Caso: transportista inexistente (no puede ocurrir por FK en la subconsulta)
-- La subconsulta solo usa transportistas que tienen ingresos, que por FK existen
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- "Último trimestre" se calcula relativo a CURRENT_DATE, no con fecha fija.
-- El NOT EXISTS hace la consulta re-ejecutable (idempotente).
-- Se usa ILIKE para búsqueda case-insensitive de "General Alvear".


-- =============================================================================
-- I2: Si existe un tinto de al menos 14°, crear 'cordero al disco' y asociarlo
--     a todos los que cumplen
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I2
-- Tipo:             INSERT
-- Enunciado:        Si existe un tinto de al menos 14°, crear 'cordero al disco' y asociarlo a todos los que cumplen
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se verifica si existe al menos un vino tipo 'tinto' con graduacion >= 14.
-- Si existe, se inserta un maridaje 'cordero al disco' (si no existe ya) y
-- se asocian en vino_maridaje todos los vinos tintos con graduacion >= 14.
-- Se usa INSERT ... SELECT con NOT EXISTS para evitar duplicados.
-- Temperatura de servicio: se usa un valor típico para cordero al disco (ej. 18°C).
-- Transacción única para atomicidad.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver vinos tintos >= 14°:
-- SELECT cod_vino, nombre, graduacion FROM bodegas.vino WHERE tipo = 'tinto' AND graduacion >= 14 ORDER BY graduacion DESC;
-- Ejecutar para ver si 'cordero al disco' ya existe:
-- SELECT * FROM bodegas.maridaje WHERE nombre ILIKE 'cordero al disco';
-- Valores típicos: varios tintos 13.5-15.5°, maridajes 10-20 existentes.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I2'
BEGIN;

-- Control previo: vinos tintos >= 14°
SELECT cod_vino, nombre, graduacion
  FROM bodegas.vino
 WHERE tipo = 'tinto'
   AND graduacion >= 14
 ORDER BY graduacion DESC;

-- Control previo: maridaje 'cordero al disco' existente
SELECT id_maridaje, nombre, temperatura_servicio_c
  FROM bodegas.maridaje
 WHERE nombre ILIKE 'cordero al disco';

-- Sentencia principal: CTEs para insertar maridaje y asociaciones
WITH vinos_calificados AS (
  SELECT cod_vino
    FROM bodegas.vino
   WHERE tipo = 'tinto'
     AND graduacion >= 14
),
maridaje_nuevo AS (
  INSERT INTO bodegas.maridaje (nombre, temperatura_servicio_c)
  SELECT 'cordero al disco', 18.0
  WHERE NOT EXISTS (
    SELECT 1 FROM bodegas.maridaje WHERE nombre ILIKE 'cordero al disco'
  )
  RETURNING id_maridaje
),
maridaje_id AS (
  SELECT id_maridaje FROM maridaje_nuevo
  UNION ALL
  SELECT id_maridaje FROM bodegas.maridaje WHERE nombre ILIKE 'cordero al disco'
  LIMIT 1
)
INSERT INTO bodegas.vino_maridaje (cod_vino, id_maridaje)
SELECT vc.cod_vino, mi.id_maridaje
  FROM vinos_calificados vc
  CROSS JOIN maridaje_id mi
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.vino_maridaje vm
    WHERE vm.cod_vino = vc.cod_vino
      AND vm.id_maridaje = mi.id_maridaje
 );
\echo 'Filas afectadas (I2):' :ROW_COUNT

-- Control posterior: asociaciones creadas
SELECT v.cod_vino, v.nombre, v.graduacion, m.nombre AS maridaje, m.temperatura_servicio_c
  FROM bodegas.vino v
  JOIN bodegas.vino_maridaje vm ON vm.cod_vino = v.cod_vino
  JOIN bodegas.maridaje m ON m.id_maridaje = vm.id_maridaje
 WHERE v.tipo = 'tinto'
   AND v.graduacion >= 14
   AND m.nombre ILIKE 'cordero al disco'
 ORDER BY v.graduacion DESC;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints:
--   ck_vino_tipo (tipo IN ('tinto','blanco','rosado','espumante')) - valida 'tinto'
--   ck_vino_graduacion (graduacion BETWEEN 5 AND 20) - valida >= 14
-- FOREIGN KEY constraints:
--   fk_vino_maridaje_vino (cod_vino -> vino) ON DELETE CASCADE
--   fk_vino_maridaje_maridaje (id_maridaje -> maridaje) ON DELETE CASCADE
-- UNIQUE constraints:
--   uq_maridaje_nombre - evita maridajes duplicados
--   pk_vino_maridaje (cod_vino, id_maridaje) - evita asociaciones duplicadas
-- Reglas de negocio: Ninguna RN directa
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
WITH vinos_calificados AS (
  SELECT cod_vino
    FROM bodegas.vino
   WHERE tipo = 'tinto'
     AND graduacion >= 14
),
maridaje_nuevo AS (
  INSERT INTO bodegas.maridaje (nombre, temperatura_servicio_c)
  SELECT 'cordero al disco', 18.0
  WHERE NOT EXISTS (
    SELECT 1 FROM bodegas.maridaje WHERE nombre ILIKE 'cordero al disco'
  )
  RETURNING id_maridaje
),
maridaje_id AS (
  SELECT id_maridaje FROM maridaje_nuevo
  UNION ALL
  SELECT id_maridaje FROM bodegas.maridaje WHERE nombre ILIKE 'cordero al disco'
  LIMIT 1
)
INSERT INTO bodegas.vino_maridaje (cod_vino, id_maridaje)
SELECT vc.cod_vino, mi.id_maridaje
  FROM vinos_calificados vc
  CROSS JOIN maridaje_id mi
 WHERE NOT EXISTS (
   SELECT 1 FROM bodegas.vino_maridaje vm
    WHERE vm.cod_vino = vc.cod_vino
      AND vm.id_maridaje = mi.id_maridaje
 );
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: no existe ningún tinto >= 14°
-- vinos_calificados devuelve 0 filas -> INSERT en vino_maridaje inserta 0 filas
-- El maridaje 'cordero al disco' SÍ se crea (según enunciado: "Si existe... crear")
-- Para no crearlo si no hay vinos, mover la condición a un DO block condicional.

-- Caso: maridaje ya existe y todas las asociaciones ya existen
-- NOT EXISTS evita duplicados -> 0 filas afectadas en ambas inserciones
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El enunciado dice "Si existe un tinto... crear... y asociarlo".
-- La implementación crea el maridaje aunque no haya vinos (comportamiento literal).
-- Temperatura 18°C es típica para carnes rojas; ajustar según catálogo real.
-- La CTE maridaje_id maneja ambos casos: maridaje nuevo o existente.


-- =============================================================================
-- I3: Crear comprobante con tres renglones, cliente dado y sala 1,
--     dentro de una transacción y usando funciones de cálculo
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I3
-- Tipo:             INSERT
-- Enunciado:        Crear comprobante con tres renglones, cliente dado y sala 1, dentro de una transacción y usando funciones de cálculo
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se usa la función fn_registrar_venta que encapsula toda la lógica de venta
-- (RN-08, RN-09, RN-12, RN-13) en una sola llamada atómica. La función:
-- - Crea la cabecera comprobante con subtotal=0, descuento=0, total=0
-- - Inserta los renglones completando precio_unitario (precio vigente del vino),
--   descuento_porcentaje (fn_descuento_cliente), subtotal (cálculo)
-- - Descuenta stock_sala y recalcula importes de la cabecera
-- - Es SECURITY DEFINER y bloquea stock_sala FOR UPDATE en orden de cod_vino
-- Parámetros: p_id_cliente, p_id_sala=1, arrays p_vinos y p_cantidades.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver clientes y sus descuentos:
-- SELECT id_cliente, nombre_razon_social, tipo, descuento_excepcion,
--        bodegas.fn_descuento_cliente(id_cliente) AS desc_efectivo
--   FROM bodegas.cliente
--  WHERE tipo = 'socio'
--  LIMIT 10;
-- Ejecutar para ver vinos con stock en sala 1:
-- SELECT v.cod_vino, v.nombre, v.precio, s.cantidad AS stock_sala1
--   FROM bodegas.vino v
--   JOIN bodegas.stock_sala s ON s.cod_vino = v.cod_vino
--  WHERE s.id_sala = 1
--    AND s.cantidad > 0
--  ORDER BY v.cod_vino
--  LIMIT 10;
-- Valores típicos: id_cliente 1-20000, cod_vino 1-1000, stock >0 en sala 1.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I3'
BEGIN;

-- Control previo: stock en sala 1 para los vinos a vender
-- (Ejemplo con parámetros: :id_cliente, :vino1, :cant1, :vino2, :cant2, :vino3, :cant3)
SELECT v.cod_vino, v.nombre, v.precio, s.cantidad AS stock_sala_antes
  FROM bodegas.stock_sala s
  JOIN bodegas.vino v ON v.cod_vino = s.cod_vino
 WHERE s.id_sala = 1
   AND v.cod_vino IN (:vino1, :vino2, :vino3);

-- Control previo: cliente y descuento efectivo
SELECT id_cliente, nombre_razon_social, tipo,
       bodegas.fn_descuento_cliente(id_cliente) AS desc_efectivo
  FROM bodegas.cliente
 WHERE id_cliente = :id_cliente;

-- Sentencia principal: usar fn_registrar_venta
SELECT bodegas.fn_registrar_venta(
         :id_cliente,      -- p_id_cliente
         1,                -- p_id_sala (sala 1 fija)
         ARRAY[:vino1, :vino2, :vino3]::BIGINT[],
         ARRAY[:cant1, :cant2, :cant3]::INTEGER[]
       ) AS nro_comprobante_creado;
\echo 'Filas afectadas (I3): 1 comprobante (el número devuelto) y 3 renglones con' :cant1 '+' :cant2 '+' :cant3 'botellas; ver el control posterior'

-- Control posterior: comprobante creado y renglones
SELECT c.nro_comprobante, c.fecha, c.id_cliente, c.id_sala,
       c.subtotal, c.descuento, c.total,
       rc.cod_vino, rc.cantidad, rc.precio_unitario, rc.descuento_porcentaje, rc.subtotal
  FROM bodegas.comprobante c
  JOIN bodegas.renglon_comprobante rc ON rc.nro_comprobante = c.nro_comprobante
 WHERE c.nro_comprobante = (
   SELECT max(nro_comprobante) FROM bodegas.comprobante
 );

-- Control posterior: stock en sala 1 después
SELECT v.cod_vino, v.nombre, s.cantidad AS stock_sala_despues
  FROM bodegas.stock_sala s
  JOIN bodegas.vino v ON v.cod_vino = s.cod_vino
 WHERE s.id_sala = 1
   AND v.cod_vino IN (:vino1, :vino2, :vino3);

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE (en renglon_comprobante, disparados por fn_registrar_venta):
--   trg_renglon_comprobante_completar (RN-08/09/12):
--     - Rechaza si comprobante ya emitido (xact_alta != actual)
--     - Completa precio_unitario, descuento_porcentaje (fn_descuento_cliente), subtotal
--     - Rechaza si stock_sala insuficiente (FOR UPDATE)
-- Triggers AFTER (en renglon_comprobante):
--   trg_renglon_comprobante_impactar (RN-08/09):
--     - Descuenta stock_sala
--     - Invoca fn_recalcular_comprobante (recalcula subtotal, descuento, total)
-- Triggers BEFORE (en comprobante):
--   trg_comprobante_importes (RN-08): exige importes 0 al insertar, permite UPDATE solo con marca
--   trg_comprobante_alta (RN-12): fija xact_alta = pg_current_xact_id()
-- Constraint triggers DEFERRABLE:
--   ctrg_comprobante_con_renglones (RN-08): al confirmar, exige al menos 1 renglón
-- CHECK constraints:
--   ck_renglon_comprobante_cantidad_positiva, ck_renglon_comprobante_precio_positivo, ck_renglon_comprobante_descuento, ck_renglon_comprobante_subtotal
--   ck_comprobante_importes (total = subtotal - descuento)
-- FOREIGN KEY:
--   fk_comprobante_cliente, fk_comprobante_sala_venta
--   fk_renglon_comprobante_comprobante, fk_renglon_comprobante_vino
-- Reglas de negocio: RN-06 (descuento tipo cliente), RN-08 (total derivado), RN-09 (stock), RN-12 (inmutabilidad), RN-13 (auditoría precio si cambia)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
SELECT bodegas.fn_registrar_venta(
         :id_cliente,
         1,
         ARRAY[:vino1, :vino2, :vino3]::BIGINT[],
         ARRAY[:cant1, :cant2, :cant3]::INTEGER[]
       );
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: cliente inexistente
-- SELECT fn_registrar_venta(999999, 1, ARRAY[1,2,3], ARRAY[1,1,1]);
-- Esperado: SQLSTATE P0002 del trigger (FK fk_comprobante_cliente) o de fn_descuento_cliente

-- Caso: vino sin stock en sala 1
-- SELECT fn_registrar_venta(:cliente_con_stock, 1, ARRAY[:vino_sin_stock], ARRAY[5]);
-- Esperado: SQLSTATE P0001 del trigger trg_renglon_comprobante_completar
--   "RN-09: stock insuficiente del vino % en la sala %."

-- Caso: vino repetido en la venta
-- SELECT fn_registrar_venta(:cliente, 1, ARRAY[1,1,2], ARRAY[1,2,1]);
-- Esperado: SQLSTATE P0001 de fn_registrar_venta
--   "RN-08: un vino no puede repetirse en la misma venta."

-- Caso: cantidad <= 0
-- SELECT fn_registrar_venta(:cliente, 1, ARRAY[1], ARRAY[0]);
-- Esperado: SQLSTATE P0001 de fn_registrar_venta
--   "RN-15: las cantidades vendidas deben ser positivas."
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- Se usa fn_registrar_venta en lugar de INSERT directo porque encapsula
-- la lógica de RN-08, RN-09, RN-12 y RN-13 en una sola transacción atómica.
-- La API no tiene INSERT sobre comprobante ni renglon_comprobante;
-- este es el único camino de venta válido.
-- Los arrays BIGINT[] e INTEGER[] se pasan desde la aplicación (Psycopg convierte lista Python).


-- =============================================================================
-- I4: Insertar una bodega
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I4
-- Tipo:             INSERT
-- Enunciado:        Insertar una bodega
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- INSERT simple en tabla bodega con CUIT, razón social y domicilio.
-- CUIT usa dominio cuit_dom (VARCHAR(11) con CHECK formato 11 dígitos).
-- PK: cuit. UNIQUE implícito por PK.
-- No hay triggers sobre bodega.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver bodegas existentes:
-- SELECT cuit, razon_social, domicilio FROM bodegas.bodega ORDER BY razon_social;
-- Valores: cuit de 11 dígitos; el parámetro por omisión (30712345671) no existe en la carga.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I4'
BEGIN;

-- Control previo: verificar que CUIT no existe
SELECT cuit, razon_social FROM bodegas.bodega WHERE cuit = :'cuit_bodega_nueva';

-- Sentencia principal
INSERT INTO bodegas.bodega (cuit, razon_social, domicilio)
VALUES (:'cuit_bodega_nueva', :'razon_social', :'domicilio');
\echo 'Filas afectadas (I4):' :ROW_COUNT

-- Control posterior
SELECT cuit, razon_social, domicilio FROM bodegas.bodega WHERE cuit = :'cuit_bodega_nueva';

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints:
--   ck_cuit_dom_formato (cuit ~ '^[0-9]{11}$') - dominio cuit_dom
-- PRIMARY KEY:
--   pk_bodega (cuit) - UNIQUE implícito
-- Reglas de negocio: RN-14 (no borrar bodega con movimientos) - no afectado en INSERT
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
INSERT INTO bodegas.bodega (cuit, razon_social, domicilio)
VALUES (:'cuit_bodega_nueva', :'razon_social', :'domicilio');
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: CUIT duplicado
-- INSERT ... VALUES ('30555408710', 'Nueva', 'Dir');  -- CUIT de Bodega Lopez S.R.L.
-- Esperado: SQLSTATE 23505 (unique_violation), constraint pk_bodega

-- Caso: CUIT formato inválido (no 11 dígitos)
-- INSERT ... VALUES ('123', 'Nueva', 'Dir');
-- Esperado: SQLSTATE 23514 (check_violation), constraint ck_cuit_dom_formato
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El dominio cuit_dom centraliza la validación de formato.
-- No se usa ON CONFLICT porque el requisito es INSERT simple; si existe, debe fallar.


-- =============================================================================
-- I5: Insertar una sala de venta
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I5
-- Tipo:             INSERT
-- Enunciado:        Insertar una sala de venta
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- INSERT en sala_venta con calle, número, dia_cierre, id_localidad.
-- id_sala es IDENTITY. dia_cierre tiene CHECK (lista de 7 días).
-- UNIQUE: uq_sala_venta_direccion (id_localidad, calle, numero).
-- FK: fk_sala_venta_localidad (id_localidad -> localidad) ON UPDATE/DELETE RESTRICT.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver localidades:
-- SELECT id_localidad, nombre, provincia FROM bodegas.localidad ORDER BY provincia, nombre LIMIT 20;
-- Ejecutar para ver salas existentes:
-- SELECT id_sala, calle, numero, dia_cierre, l.nombre AS localidad
--   FROM bodegas.sala_venta sv
--   JOIN bodegas.localidad l ON l.id_localidad = sv.id_localidad
--  ORDER BY l.nombre, sv.calle, sv.numero;
-- Valores típicos: id_localidad 1-100, dia_cierre en lista válida.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I5'
BEGIN;

-- Control previo: verificar localidad existe
SELECT id_localidad, nombre, provincia FROM bodegas.localidad WHERE id_localidad = :id_localidad;

-- Control previo: verificar que no existe misma dirección en esa localidad
SELECT id_sala FROM bodegas.sala_venta
 WHERE id_localidad = :id_localidad
   AND calle = :'calle'
   AND numero = :'numero';

-- Sentencia principal
INSERT INTO bodegas.sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES (:'calle', :'numero', :'dia_cierre', :id_localidad);
\echo 'Filas afectadas (I5):' :ROW_COUNT

-- Control posterior
SELECT sv.id_sala, sv.calle, sv.numero, sv.dia_cierre, l.nombre AS localidad
  FROM bodegas.sala_venta sv
  JOIN bodegas.localidad l ON l.id_localidad = sv.id_localidad
 WHERE sv.id_sala = (SELECT max(id_sala) FROM bodegas.sala_venta);

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- CHECK constraints:
--   ck_sala_venta_dia_cierre (dia_cierre IN ('lunes','martes','miercoles','jueves','viernes','sabado','domingo'))
-- UNIQUE constraints:
--   uq_sala_venta_direccion (id_localidad, calle, numero)
-- FOREIGN KEY:
--   fk_sala_venta_localidad (id_localidad -> localidad) ON UPDATE RESTRICT ON DELETE RESTRICT
-- Reglas de negocio: RN-02 (sala en una localidad) - FK garantiza existencia
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
INSERT INTO bodegas.sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES (:'calle', :'numero', :'dia_cierre', :id_localidad);
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: localidad inexistente
-- INSERT ... id_localidad = 99999;
-- Esperado: SQLSTATE 23503 (foreign_key_violation), constraint fk_sala_venta_localidad

-- Caso: día de cierre inválido
-- INSERT ... dia_cierre = 'festivo';
-- Esperado: SQLSTATE 23514 (check_violation), constraint ck_sala_venta_dia_cierre

-- Caso: dirección duplicada en misma localidad
-- INSERT ... misma (id_localidad, calle, numero);
-- Esperado: SQLSTATE 23505 (unique_violation), constraint uq_sala_venta_direccion
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- dia_cierre usa nombres en español (no abreviados).
-- La UNIQUE en (id_localidad, calle, numero) evita dos salas en la misma dirección.


-- =============================================================================
-- I6: Crear ingreso en confección de 120 botellas de un vino, bodega y transportista dados
-- =============================================================================

-- -----------------------------------------------------------------------------
-- METADATOS
-- -----------------------------------------------------------------------------
-- Código:           I6
-- Tipo:             INSERT
-- Enunciado:        Crear ingreso en confección de 120 botellas de un vino, bodega y transportista dados
-- Autor:            [COMPLETAR: nombre/legajo]
-- Fecha:            [COMPLETAR: YYYY-MM-DD]
-- Referencia:       Sección 3.7 Tabla Consultas SQL
-- Dataset:          SEMILLA=20260427, FECHA_REFERENCIA=2026-10-27, ESCALA=1
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. ANÁLISIS Y ESTRATEGIA
-- -----------------------------------------------------------------------------
-- Se crea un ingreso (cabecera) en estado 'en_confeccion' (DEFAULT) y su renglón
-- con 120 botellas del vino indicado. El ingreso debe referenciar bodega y transportista.
-- El trigger trg_ingreso_estado valida estado inicial 'en_confeccion'.
-- El trigger trg_renglon_ingreso_bloqueo permite insertar renglones en confección.
-- No hay trigger que complete precio ni descuento en renglon_ingreso (solo cantidad).
-- Luego se usaría sp_terminar_ingreso y sp_procesar_ingreso para impactar stock.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 2. VALORES CONCRETOS DEL DATASET
-- -----------------------------------------------------------------------------
-- Ejecutar para ver vinos, bodegas, transportistas:
-- SELECT v.cod_vino, v.nombre, b.razon_social AS bodega
--   FROM bodegas.vino v JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
--  ORDER BY v.cod_vino LIMIT 10;
-- SELECT cod_transportista, razon_social FROM bodegas.transportista ORDER BY cod_transportista LIMIT 10;
-- Valores típicos: cod_vino 1-1000, cuit_bodega válido, cod_transportista 1-20.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 3. PROTOCOLO DE EJECUCIÓN
-- -----------------------------------------------------------------------------
\echo '>>> I6'
BEGIN;

-- Control previo: verificar que vino, bodega y transportista existen
SELECT v.cod_vino, v.nombre, v.cuit_bodega, b.razon_social AS bodega
  FROM bodegas.vino v
  JOIN bodegas.bodega b ON b.cuit = v.cuit_bodega
 WHERE v.cod_vino = :cod_vino;

SELECT cod_transportista, razon_social
  FROM bodegas.transportista
 WHERE cod_transportista = :cod_transportista;

-- Sentencia principal: CTE para insertar cabecera y renglón
WITH nuevo_ingreso AS (
  INSERT INTO bodegas.ingreso (cod_transportista, cuit_bodega)
  VALUES (:cod_transportista, :'cuit_bodega')
  RETURNING cod_ingreso
)
INSERT INTO bodegas.renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT ni.cod_ingreso, :cod_vino, 120
  FROM nuevo_ingreso ni;
\echo 'Filas afectadas (I6):' :ROW_COUNT

-- Control posterior: ingreso creado con renglón
SELECT i.cod_ingreso, i.fecha, i.estado, i.cod_transportista, i.cuit_bodega,
       ri.cod_vino, ri.cantidad, v.nombre AS vino
  FROM bodegas.ingreso i
  JOIN bodegas.renglon_ingreso ri ON ri.cod_ingreso = i.cod_ingreso
  JOIN bodegas.vino v ON v.cod_vino = ri.cod_vino
 WHERE i.cod_ingreso = (SELECT max(cod_ingreso) FROM bodegas.ingreso);

ROLLBACK;

-- -----------------------------------------------------------------------------
-- 4. TRIGGERS, CONSTRAINTS Y REGLAS DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Triggers BEFORE (en ingreso):
--   trg_ingreso_estado (RN-10): valida estado inicial 'en_confeccion' (DEFAULT)
-- Triggers BEFORE (en renglon_ingreso):
--   trg_renglon_ingreso_bloqueo (RN-12): permite INSERT si ingreso en 'en_confeccion'
-- CHECK constraints:
--   ck_renglon_ingreso_cantidad_positiva (cantidad > 0) - 120 > 0 OK
-- FOREIGN KEY:
--   fk_ingreso_transportista (cod_transportista) ON UPDATE RESTRICT ON DELETE RESTRICT
--   fk_ingreso_bodega (cuit_bodega -> bodega) ON UPDATE CASCADE ON DELETE RESTRICT
--   fk_renglon_ingreso_ingreso (cod_ingreso -> ingreso) ON DELETE CASCADE
--   fk_renglon_ingreso_vino (cod_vino -> vino) ON UPDATE RESTRICT ON DELETE RESTRICT
-- Reglas de negocio: RN-10 (flujo estados ingreso), RN-12 (renglones solo en confección)
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 5. CONSULTA SQL PRINCIPAL
-- -----------------------------------------------------------------------------
/*
WITH nuevo_ingreso AS (
  INSERT INTO bodegas.ingreso (cod_transportista, cuit_bodega)
  VALUES (:cod_transportista, :'cuit_bodega')
  RETURNING cod_ingreso
)
INSERT INTO bodegas.renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT ni.cod_ingreso, :cod_vino, 120
  FROM nuevo_ingreso ni;
*/

-- -----------------------------------------------------------------------------
-- 6. CASOS DE PRUEBA NEGATIVOS
-- -----------------------------------------------------------------------------
/*
-- Caso: transportista inexistente
-- INSERT ingreso con cod_transportista = 99999;
-- Esperado: SQLSTATE 23503, constraint fk_ingreso_transportista

-- Caso: bodega inexistente
-- INSERT ingreso con cuit_bodega = '99999999999';
-- Esperado: SQLSTATE 23503, constraint fk_ingreso_bodega

-- Caso: vino inexistente
-- INSERT renglon con cod_vino = 999999;
-- Esperado: SQLSTATE 23503, constraint fk_renglon_ingreso_vino

-- Caso: cantidad <= 0 (ej. 0)
-- INSERT renglon ... cantidad = 0;
-- Esperado: SQLSTATE 23514, constraint ck_renglon_ingreso_cantidad_positiva
*/

-- -----------------------------------------------------------------------------
-- 7. OBSERVACIONES
-- -----------------------------------------------------------------------------
-- El ingreso queda en 'en_confeccion'; para impactar stock se debe llamar
-- sp_terminar_ingreso(cod_ingreso) y luego sp_procesar_ingreso(cod_ingreso).
-- La fecha se asigna por DEFAULT (CURRENT_TIMESTAMP).
-- El estado 'en_confeccion' es obligatorio por el trigger y el DEFAULT.