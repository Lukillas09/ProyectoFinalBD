# Bootstrap de PostgreSQL

El `db/Dockerfile` copia `001_roles_y_esquema.sh` a `/docker-entrypoint-initdb.d`. La imagen oficial lo ejecuta únicamente al crear un volumen de PostgreSQL vacío. Al copiarlo dentro de la imagen se evitan problemas de bind mounts en carpetas sincronizadas de Windows.

El script usa la cuenta superusuaria de bootstrap para:

- crear un propietario del proyecto sin privilegios administrativos globales;
- crear el rol de la API sin permisos DDL;
- transferir la propiedad de la base al propietario;
- cerrar privilegios públicos;
- crear el esquema vacío `bodegas`;
- cerrar los privilegios predeterminados públicos de futuras tablas, secuencias, rutinas, tipos y dominios creados por el propietario.

La API no recibe DML ni ejecución de rutinas por anticipado. Las migraciones actuales crean el modelo sin ampliar esos permisos; una migración operativa posterior deberá conceder privilegios explícitos por objeto u operación y agregar su prueba correspondiente.

También crea la cuenta de reportes (`DB_REPORT_USER`) y los roles de grupo `bodegas_rw` y `bodegas_ro`, sin inicio de sesión. La API hereda `bodegas_rw`, reportes hereda `bodegas_ro`, y el propietario puede hacer `SET ROLE` a ambos sin heredarlos. Las cuentas deben ser cuatro, con contraseñas distintas; si no, el script se detiene.

El bootstrap no crea tablas de negocio. El servicio `migrate` ejecuta `db/migrate.sh` con `DB_OWNER_USER`, nunca con `POSTGRES_BOOTSTRAP_USER` ni con `DB_APP_USER`.

Cambiar `.env` no modifica un volumen ya inicializado. Ver `README.md` antes de eliminar el volumen, porque esa operación borra todos los datos.
