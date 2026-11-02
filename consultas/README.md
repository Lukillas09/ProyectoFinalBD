# Consultas SQL - Etapa 5

Este directorio contiene las consultas SQL requeridas por la Etapa 5 del Trabajo Práctico Integrador.

## Archivos

| Archivo | Consultas | Descripción |
|---------|-----------|-------------|
| `update.sql` | U1 a U6 | Actualizaciones masivas y recálculos |
| `insert.sql` | I1 a I6 | Inserciones de datos nuevos |
| `delete.sql` | D1 a D6 | Eliminaciones controladas |
| `select.sql` | S1 a S12 | Consultas de análisis y reportes |

## Estructura común

Cada consulta sigue la plantilla definida en `plantilla_consultas.sql` y debe incluir:

1. **Metadatos**: código, tipo, enunciado, autor, fecha, referencia, dataset
2. **Estrategia**: análisis de tablas, joins, funciones, triggers involucrados
3. **Valores concretos**: datos reales del dataset de la Etapa 3 (SEMILLA=20260427)
4. **Protocolo de ejecución**: `BEGIN` → control previo → sentencia → control posterior → `ROLLBACK`
5. **Triggers/Constraints/RN**: mecanismos que se disparan o validan (solo modificaciones)
6. **SQL principal**: comentado, parametrizado, con columnas explícitas
7. **Controles**: consultas de verificación antes y después
8. **Filas afectadas**: medición con `ROW_COUNT`
9. **EXPLAIN ANALYZE**: obligatorio para S9-S12 y consultas de rendimiento
10. **Casos negativos**: rechazos esperados con SQLSTATE y constraint
11. **Observaciones**: decisiones de diseño, alternativas, limitaciones

## Períodos relativos

Todas las consultas que usen períodos ("última semana", "último trimestre", "últimos 5 años")
**deben calcularse desde `CURRENT_DATE`**, nunca con fechas fijas. El dataset de la Etapa 3
se regenera antes de la demo con `FECHA_REFERENCIA=$(date +%F)` para que `CURRENT_DATE`
coincida con el final de la historia generada.

## Ejecución

Cada consulta individual se ejecuta en su propio bloque transaccional:

```bash
# Desde el contenedor de la base de datos, como propietario
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -f /opt/bodegas/consultas/update.sql'
```

Los scripts terminan en `ROLLBACK` para no modificar la base de datos de prueba.
Para producción real, cambiar `ROLLBACK` por `COMMIT` en el bloque correspondiente.

## Requisitos de la consigna (sección 3.7)

- Código, enunciado, SQL comentado, estrategia y valores concretos del dataset
- Períodos relativos desde `CURRENT_DATE`
- Modificaciones: triggers/constraints activados/violados + protocolo BEGIN→control→sentencia→control→ROLLBACK + filas afectadas
- S9-S12 requieren `EXPLAIN (ANALYZE)` adjunto

## Plantilla

Ver `plantilla_consultas.sql` para la estructura base documentada.