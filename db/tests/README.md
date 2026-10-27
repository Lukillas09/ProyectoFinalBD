# Pruebas de base de datos

`run_all.sh` ejecuta las pruebas en orden, cada una con su rol, y termina con código distinto de cero si alguna falla:

1. `001_infraestructura.sql` (cuenta de la API): separación de cuentas, propietario no administrativo, membresías de los grupos `bodegas_rw` y `bodegas_ro`, privilegios cerrados y que todo objeto de `bodegas` pertenezca al propietario. Es válida antes y después de migrar.
2. `002_esquema_y_restricciones.sql` (propietario): PK/FK, UNIQUE, NOT NULL, CHECK, DOMAIN y exclusividad de subtipos.
3. `003_privilegios_api.sql` (cuenta de la API): matriz exacta de privilegios de tablas, columnas, rutinas y secuencias.
4. `004_reglas_negocio.sql` (propietario): un caso que funciona y uno que falla por cada RN-01 a RN-15, U6, totalidad de clientes y funciones.
5. `005_roles.sql` (propietario con `SET LOCAL ROLE` a cada grupo): operaciones reales de la API y de reportes; lo prohibido debe dar 42501. También verifica las funciones `SECURITY DEFINER`.
6. `006_conexion_reportes.sql` (cuenta de reportes): sólo lectura efectiva.

`ayudantes.sql` define `esperar_error` y `afirmar` en `pg_temp`; las pruebas lo incluyen con `\ir`. `esperar_error` exige el SQLSTATE y, si se indican, la constraint y un patrón del mensaje. Falla si la sentencia es aceptada.

Las pruebas que escriben datos lo hacen dentro de una transacción que termina en `ROLLBACK`. Las reglas diferidas (constraint triggers) se verifican con `SET CONSTRAINTS ALL IMMEDIATE` dentro de un `SAVEPOINT`.

Cada aserción falsa ejecuta `RAISE EXCEPTION`. No se usa `\quit 1`: psql ignora ese argumento y sale con código 0, de modo que una prueba fallida parecería exitosa. Con `ON_ERROR_STOP`, el error hace que psql termine con código 3.

La correspondencia regla → caso está en `docs/trazabilidad.md`. La concurrencia se demuestra a mano con dos sesiones (`docs/concurrencia.md`).
