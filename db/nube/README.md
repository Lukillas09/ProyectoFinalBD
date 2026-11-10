# db/nube — preparar la base de Render (Etapa 8)

Herramientas para crear los roles, aplicar las migraciones, cargar los datos y hacer el backup de la base de Render **desde la PC**. Diseño y requisitos: [`docs/nube.md`](../../docs/nube.md).

| Archivo | Para qué |
|---|---|
| `render.sh` | Punto de entrada: un paso por comando |
| `paso.sh` | Lo que corre dentro del contenedor de herramientas (imagen de `db`: psql, pg_dump, migraciones) |
| `bootstrap_render.sh` | Roles, grupos y esquema, ejecutado por el administrador de Render, que no es superusuario |
| `conteos.sql` | Filas por tabla del esquema `bodegas`, para comparar Render con la base restaurada |
| `compose.render.yml` | Herramientas con salida a internet: la red `datos` del compose principal es interna |
| `render.env.example` | Plantilla de credenciales. La copia `render.env` **no se versiona** |

## Por qué un bootstrap distinto del local

El de `db/bootstrap/` lo ejecuta el superusuario de la imagen de Docker. En Render, el administrador sólo tiene `CREATEROLE` y `CREATEDB`, y en PostgreSQL 16 eso obliga a cambiar el orden:
1. Para traspasar la base a `bodegas_owner`, el administrador necesita poder hacer `SET ROLE` a ese rol.
2. Los permisos sobre la base y los esquemas los da el nuevo dueño.
3. Al final se le revoca al administrador esa membresía.

Los roles, atributos y permisos resultantes son los mismos que en local.

**Probado el 10/11/2026** en un PostgreSQL 16 con un administrador de ese mismo perfil:
- bootstrap, las 10 migraciones y la carga `ESCALA=0.1` (15.044 comprobantes) corren sin errores;
- `controles.sql` y `post_carga.sql` pasan;
- `bodegas_api` no puede crear tablas, actualizar stock directamente ni crear roles;
- el administrador termina sin `SET` ni herencia sobre `bodegas_owner`;
- 261 pruebas de la API pasan contra esa base. Fallan sólo las 11 que necesitan los contenedores o nginx.

## Orden de uso

Antes de empezar:
- copiá `render.env.example` como `render.env` y completalo;
- en Render, `bodegas-db` → **Networking** → agregá tu IP como `x.x.x.x/32`.

```bash
db/nube/render.sh verificar-admin   # rolcreaterole y rolcreatedb deben ser true; ssl = t
db/nube/render.sh bootstrap
db/nube/render.sh migrar            # 001..010 en orden, con checksums
db/nube/render.sh cargar            # ESCALA de render.env
db/nube/render.sh controles
db/nube/render.sh huellas           # comparar con la misma carga en local
db/nube/render.sh tamano
db/nube/render.sh backup            # db/nube/salida/*.dump (no se versiona)
db/nube/render.sh restaurar db/nube/salida/<archivo>.dump   # base NUEVA local + conteos
```

Al terminar, **quitá tu IP** de la lista: la base vuelve a quedar sin acceso externo.

Pruebas de seguridad (#69):

```bash
db/nube/render.sh psql-api -c "CREATE TABLE x (i int)"     # debe fallar: permission denied
db/nube/render.sh sin-ssl                                   # debe fallar: Render exige TLS
# con la IP quitada, cualquier paso debe fallar al conectar
```
