# Consultas SQL - Etapa 5

Este directorio contiene las consultas SQL de la Etapa 5 del Trabajo Práctico Integrador (sección 3.7 de la consigna).

## Archivos

| Archivo | Consultas | Descripción |
|---------|-----------|-------------|
| `select.sql` | S1 a S12 | Consultas de análisis y reportes; S9 a S12 con `EXPLAIN (ANALYZE, BUFFERS)` |
| `insert.sql` | I1 a I6 | Inserciones de datos nuevos |
| `update.sql` | U1 a U6 | Actualizaciones masivas y recálculos |
| `delete.sql` | D1 a D6 | Eliminaciones controladas |
| `ejecutar.sh` | — | Ejecuta un archivo como propietario y falla si falla alguna sentencia |
| `plantilla_consultas.sql` | — | Plantilla de documentación. **No es ejecutable** y no se copia a la imagen |

## Ejecución

Con la base levantada y cargada (`docker compose --profile seed run --rm seed`):

```bash
docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
docker compose exec db /opt/bodegas/consultas/ejecutar.sh insert.sql
docker compose exec db /opt/bodegas/consultas/ejecutar.sh update.sql
docker compose exec db /opt/bodegas/consultas/ejecutar.sh delete.sql
```

`ejecutar.sh` corre el archivo como propietario (`DB_OWNER_USER`), con `ON_ERROR_STOP=1`:

- si una sentencia falla, corta ahí, imprime `=== FALLA: archivo (código 3)` y devuelve 3;
- si todo pasa, imprime `=== OK: archivo` y devuelve 0.

Los archivos llegan a `/opt/bodegas/consultas/` en la imagen de `db` como contexto de build adicional (`additional_contexts` en `docker-compose.yml`). Al modificar un `.sql` hay que reconstruir la imagen: `docker compose up -d --build db`. La base conserva sus datos, porque están en el volumen.

En la salida, cada consulta va precedida de `>>> S1`, `>>> I3`, etc., y cada plan de `>>> PLAN S9`. Las modificaciones informan `Filas afectadas (Xn): N`.

## Parámetros

Cada archivo define al comienzo todos los parámetros que usa, con un valor por omisión tomado de la base cargada. El comentario de cada uno incluye la consulta de donde sale. Se reemplazan con `-v`:

```bash
docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql -v id_sala=3 -v cuit_bodega=33532580264
```

| Archivo | Parámetro | Por omisión | Por qué |
|---|---|---|---|
| select | `id_sala` (S3, S6) | 1 | `controles.sql` garantiza el caso de S6 en la sala 1 |
| select | `cod_vino` (S9) | 1 | Malbec Clásico |
| select | `cod_vino_transferido` (S4) | se elige al ejecutar (`\gset`) | el vino transferido a más salas en los últimos 15 días |
| select | `cuit_bodega` (S12) | 30555408710 | Bodega Lopez S.R.L., la única bodega de 3 vinos |
| insert | `id_cliente` (I3) | se elige al ejecutar | el primer socio |
| insert | `vino1`..`vino3`, `cant1`..`cant3` (I3) | se eligen al ejecutar; 1, 2, 3 | los tres vinos con más stock en la sala 1 |
| insert | `cuit_bodega_nueva`, `razon_social`, `domicilio` (I4) | 30712345671, … | CUIT válido que no existe en la carga |
| insert | `id_localidad`, `calle`, `numero`, `dia_cierre` (I5) | 19, Av. Mitre, 1500, lunes | Villa Atuel no tiene salas |
| insert | `cod_vino`, `cuit_bodega`, `cod_transportista` (I6) | 4, 30571896822, 1 | Malbec Reserva 750 ml y su bodega |
| update | `cuit_bodega` (U3) | 30555408710 | 3 vinos |
| delete | `id_sala` (D3) | 2 | garantizada con empleados de menos de 2 años |
| delete | `id_localidad` (D6) | 29 | Eugenio Bustos, la localidad con más socios sin compras |

Los valores fijos son identificadores de catálogo que no dependen de `FECHA_REFERENCIA`. Lo que depende de la historia simulada se elige con `\gset`: tipo de cliente, stock actual y transferencias recientes. Con `FECHA_REFERENCIA=2026-10-27`, por ejemplo, el cliente 1 es socio; con 2026-11-05, es distribuidor.

## Protocolo de las modificaciones

```
\echo '>>> Xn'
BEGIN;
-- control previo
-- sentencia principal
\echo 'Filas afectadas (Xn):' :ROW_COUNT
-- control posterior
ROLLBACK;
```

Cada modificación está en su propia transacción y termina en `ROLLBACK`, así que el archivo no deja cambios. Para comprobarlo, comparar `db/seed/hashes.sql` antes y después de ejecutarlo.

Las escrituras de importes, stock y estados no se hacen con `UPDATE` directos: van por las funciones y procedimientos de la base. Por ejemplo, U1 recalcula con `fn_recalcular_comprobante` e I3 vende con `fn_registrar_venta`.

## Períodos relativos

Los períodos ("última semana", "último trimestre", "últimos 5 años") se calculan desde `CURRENT_DATE`, nunca con fechas fijas. Para que devuelvan filas, la carga debe terminar en la fecha del día: antes de la demo se regenera con `FECHA_REFERENCIA=$(date +%F)` (ver `db/seed/README.md`). Con una carga más vieja, S3 (última semana) puede devolver 0 filas.

## Requisitos de la consigna (sección 3.7)

- Código, enunciado, SQL comentado, estrategia y valores concretos del dataset.
- Períodos relativos desde `CURRENT_DATE`.
- Modificaciones: triggers o constraints activados o violados, protocolo `BEGIN → control → sentencia → control → ROLLBACK` y filas afectadas.
- S9-S12 con `EXPLAIN (ANALYZE)` adjunto: `docs/consultas/planes/` y `docs/consultas/planes_etapa5.md`.

Resultados de la última verificación: `docs/consultas.md`, sección 4.
