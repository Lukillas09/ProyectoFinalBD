-- Bodegas del Atuel - índices de rendimiento (Etapa 4)
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Cada índice responde a un plan medido con EXPLAIN (ANALYZE, BUFFERS) sobre
-- la carga de la Etapa 3 (ESCALA=1). Las mediciones antes y después, y los
-- índices evaluados y descartados, están en docs/rendimiento.md. El tamaño y
-- el tiempo de creación de cada comentario se midieron sobre esa carga
-- (150.125 comprobantes y 538.306 renglones).
--
-- CREATE INDEX y no CREATE INDEX CONCURRENTLY: CONCURRENTLY no puede
-- ejecutarse dentro de un bloque de transacción, y el runner aplica cada
-- migración en una. CREATE INDEX bloquea las escrituras sobre la tabla (no las
-- lecturas) mientras construye el índice, lo que aquí dura décimas de segundo.
-- En una base productiva con escrituras continuas se crearía con
-- CONCURRENTLY, fuera del runner.

SET search_path TO bodegas, pg_catalog;

-- 1. Compuesto: ventas de una sala en un período (S3, S11).
-- Orden (id_sala, fecha): la igualdad va primero y el rango después. El índice
-- ubica el tramo de una sala y lo recorre ya ordenado por fecha, sin descartar
-- filas de otras salas. Con el orden inverso (fecha, id_sala), la consulta
-- tendría que recorrer todo el rango de fechas de las 40 salas y filtrar
-- id_sala dentro del índice (comparación medida en docs/rendimiento.md).
-- Tamaño: 4,6 MB. Creación: 65 ms.
CREATE INDEX idx_comprobante_id_sala_fecha
  ON comprobante (id_sala, fecha);

-- 2. Variante con INCLUDE: ventas de todas las salas en un rango de fechas
-- (S8, v_ventas_mensuales_sala por períodos). El índice 1 no sirve cuando no
-- hay una sala fija. INCLUDE agrega id_sala y total sólo en las hojas: no
-- forman parte de la clave, pero permiten resolver S8 con un Index Only Scan,
-- sin leer la tabla (si el visibility map está al día).
-- Tamaño: 6,0 MB. Creación: 59 ms.
CREATE INDEX idx_comprobante_fecha
  ON comprobante (fecha) INCLUDE (id_sala, total);

-- 3. Clave foránea comprobante.id_cliente -> cliente. PostgreSQL no indexa las
-- FK automáticamente. Sin este índice, borrar un cliente (D4, D6) obliga al
-- control de fk_comprobante_cliente a recorrer los 150.125 comprobantes por
-- cada cliente borrado. También lo usan los anti-joins "clientes sin compras"
-- (D4, D6, S12).
-- Tamaño: 1,3 MB. Creación: 48 ms.
CREATE INDEX idx_comprobante_id_cliente
  ON comprobante (id_cliente);

-- 4. Clave foránea renglon_comprobante.cod_vino -> vino. cod_vino es la
-- segunda columna de la PK (nro_comprobante, cod_vino), así que la PK no
-- sirve para buscar por vino. Acelera las ventas de un vino (S9, S12) y el
-- control de RESTRICT al borrar o cambiar un vino.
-- Tamaño: 3,7 MB. Creación: 112 ms.
CREATE INDEX idx_renglon_comprobante_cod_vino
  ON renglon_comprobante (cod_vino);

-- 5. Parcial: transferencias pendientes por sala (S5, v_documentos_pendientes).
-- Indexa sólo las no procesadas (7 de 5.088 en la carga), que son las que
-- interesan; las procesadas, la gran mayoría, no ocupan lugar. El
-- planificador lo usa cuando puede probar que el filtro de la consulta
-- implica el del índice: la consulta tiene que incluir
-- estado <> 'procesado' (u otra condición que lo implique).
-- Tamaño: 16 kB. Creación: 4 ms.
CREATE INDEX idx_transferencia_pendientes
  ON transferencia (id_sala)
  WHERE estado <> 'procesado';

-- 6. Compuesto: precio vigente de un vino en un momento (control de la carga,
-- base de U1): WHERE cod_vino = ? AND fecha_hora <= ? ORDER BY fecha_hora
-- DESC LIMIT 1. Igualdad por vino primero y orden por fecha después: el
-- índice llega al último cambio anterior a la fecha sin recorrer la auditoría.
-- Tamaño: 128 kB. Creación: 3 ms.
CREATE INDEX idx_auditoria_precio_cod_vino_fecha
  ON auditoria_precio (cod_vino, fecha_hora);
