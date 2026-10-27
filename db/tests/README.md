# Pruebas de base de datos

`run_all.sh` ejecuta las pruebas en orden, cada una con su rol, y termina con código distinto de cero si alguna falla:

1. `001_infraestructura.sql` (rol API): separación de cuentas, propietario no administrativo, propiedad de base y esquema, privilegios cerrados y que todo objeto de `bodegas` pertenezca al propietario. Es válida antes y después de migrar; informa cuántas tablas hay sin fallar por ello.
2. `002_esquema_y_restricciones.sql` (propietario, después de migrar): inserta datos mínimos dentro de una transacción, comprueba éxitos y rechazos por SQLSTATE y nombre de constraint, y termina con `ROLLBACK`.
3. `003_privilegios_api.sql` (rol API, después de migrar): confirma que existen las 31 tablas y que la cuenta conserva sólo `CONNECT`/`USAGE`, sin DDL, DML ni acceso a secuencias.

Cada aserción falsa ejecuta `RAISE EXCEPTION`. No se usa `\quit 1`: psql ignora ese argumento y sale con código 0, de modo que una prueba fallida parecería exitosa. Con `ON_ERROR_STOP`, el error hace que psql termine con código 3.

Estas pruebas no implementan todavía RN-05, RN-06, RN-08 a RN-13 ni las participaciones mínimas que requieren lógica entre filas o tablas.
