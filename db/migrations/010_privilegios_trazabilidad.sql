-- Bodegas del Atuel - privilegios de lectura para el reporte de trazabilidad
-- (issue #32, Etapa 6).
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- GET /reportes/trazabilidad/{cod} muestra, para un vino, los lotes de uva
-- de su bodega, de la campaña de su añada y de las cepas de su corte, con su
-- finca, departamento, parcela y análisis de calidad. Es un supuesto
-- documentado en docs/requisitos.md: el modelo no vincula un vino con lotes
-- concretos, y la cátedra todavía no respondió qué alcance espera.
--
-- 007_roles.sql no le dio a la API la producción de uva porque ningún
-- endpoint la usaba (privilegios mínimos). Este reporte es el primero: recibe
-- SELECT y nada más. La API sigue sin poder escribir esas tablas, y sigue sin
-- leer empleado, que ningún endpoint usa.

SET search_path TO bodegas, pg_catalog;

GRANT SELECT ON
  departamento, finca, parcela, lote_uva, analisis_calidad
TO bodegas_rw;
