# Pruebas de base de datos

Las pruebas tienen momentos de ejecución distintos:

1. `001_infraestructura.sql` se ejecuta como la API inmediatamente después de un bootstrap limpio y **antes** de migrar. Comprueba separación de cuentas, propiedad, privilegios cerrados y ausencia inicial de objetos. Después de migrar debe fallar en la última comprobación: eso evita confundir un bootstrap con un esquema ya instalado.
2. `002_esquema_y_restricciones.sql` se ejecuta como propietario después de `db/migrate.sh`. Inserta datos mínimos dentro de una transacción, comprueba éxitos y rechazos por SQLSTATE/nombre de constraint, y termina con `ROLLBACK`.
3. `003_privilegios_api.sql` se ejecuta como la API después de migrar. Confirma que las 31 tablas existen, pero que la cuenta conserva sólo `CONNECT`/`USAGE`, sin DDL, DML ni acceso a secuencias.

Los comandos reproducibles están en el README principal. Estas pruebas no implementan todavía RN-05, RN-06, RN-08 a RN-13 ni las participaciones mínimas que requieren lógica entre filas o tablas.
