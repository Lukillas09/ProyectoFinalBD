# Bodegas del Atuel

Base ejecutable para el Trabajo Práctico Integrador de Bases de Datos 2026. Esta primera etapa conecta tres servicios reales:

```text
Navegador http://localhost:8080
        |
        v
Nginx (front) -- /api/* --> FastAPI (api) --> Psycopg 3 pool --> PostgreSQL 16
                                      SELECT 1              rol limitado
```

El front no conoce nombres internos de Docker. Solicita `/api/salud` al mismo origen y Nginx reenvía esa ruta a la API dentro de la red de Compose.

## Alcance actual

Incluye PostgreSQL 16 persistente, cuentas separadas de bootstrap/propietario/API, FastAPI con pool Psycopg, `GET /salud`, un front mínimo y healthchecks.

Todavía no incluye tablas de negocio, CRUD, triggers, carga masiva, reportes ni cálculos de totales, descuentos o stock. El análisis de la consigna, sus mínimos y las decisiones pendientes está en [docs/requisitos.md](docs/requisitos.md).

## Requisitos

- Docker Engine o Docker Desktop en ejecución.
- Docker Compose v2, invocado como `docker compose`.
- Puertos 8000 y 8080 libres, o valores alternativos en `.env`.

No hace falta instalar Python ni PostgreSQL en el host.

## Configuración

1. Crear el archivo local de variables a partir del ejemplo.

   PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

   Bash:

   ```bash
   cp .env.example .env
   ```

2. Editar `.env` y reemplazar las tres contraseñas de ejemplo por valores diferentes y robustos:

   - `POSTGRES_BOOTSTRAP_PASSWORD`: inicialización administrativa del contenedor;
   - `DB_OWNER_PASSWORD`: propietario que ejecutará futuras migraciones;
   - `DB_APP_PASSWORD`: única contraseña entregada a la API.

   `.env` está ignorado por Git. No copiar secretos reales a `.env.example` ni a documentación, capturas o historial.

3. Validar la configuración resuelta:

   ```bash
   docker compose config
   ```

## Iniciar

Desde la raíz del proyecto:

```bash
docker compose up --build
```

También se puede iniciar en segundo plano:

```bash
docker compose up --build -d
docker compose ps
```

El primer arranque crea el volumen, los roles y el esquema vacío `bodegas`. Los servicios pueden aparecer temporalmente como `starting` o `unhealthy` mientras PostgreSQL termina el bootstrap; el pool vuelve a intentar la conexión.

## Verificar

Abrir:

- Front: <http://localhost:8080>
- Estado a través del proxy del front: <http://localhost:8080/api/salud>
- Estado directo de la API: <http://localhost:8000/salud>
- OpenAPI/Swagger de FastAPI: <http://localhost:8000/docs>

Respuesta esperada con la base disponible:

```json
{"estado":"ok","base_de_datos":"disponible"}
```

Comandos útiles:

```bash
curl --fail http://localhost:8000/salud
curl --fail http://localhost:8080/api/salud
docker compose ps
docker compose logs api db front
```

En PowerShell también puede usarse:

```powershell
Invoke-RestMethod http://localhost:8000/salud
Invoke-RestMethod http://localhost:8080/api/salud
```

Para comprobar la conexión con el mismo rol limitado que usa la API:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -U "$DB_APP_USER" -d "$POSTGRES_DB" -c "SELECT current_user, current_database(), 1 AS conexion"'
```

Para ejecutar la prueba reproducible de separación de cuentas, propiedad, atributos y privilegios:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -U "$DB_APP_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/001_infraestructura.sql'
```

La prueba termina con código distinto de cero si la cuenta posee atributos administrativos o capacidad de crear objetos.

### Comprobar el 503 real

Con el entorno iniciado:

```bash
docker compose stop db
curl -i http://localhost:8000/salud
```

La API debe seguir atendiendo y responder `503` sin credenciales ni detalles internos. El front debe mostrar que PostgreSQL no está disponible. Para recuperar el servicio:

```bash
docker compose start db
```

El pool reintenta conexiones y `/salud` debe volver a 200 cuando la base acepte conexiones.

## Detener o borrar

Detener los contenedores sin eliminarlos:

```bash
docker compose stop
```

Eliminar contenedores y redes del proyecto, conservando los datos del volumen:

```bash
docker compose down
```

Eliminar también el volumen y todos los datos de PostgreSQL:

```bash
docker compose down -v
```

El último comando es destructivo. En el siguiente arranque se ejecutará nuevamente `db/bootstrap/001_roles_y_esquema.sh`.

## Roles y persistencia

- `POSTGRES_BOOTSTRAP_USER` es el superusuario técnico creado por la imagen oficial. No lo usa la API.
- `DB_OWNER_USER` es dueño de la base y del esquema `bodegas`, pero no es superusuario ni puede crear bases o roles.
- `DB_APP_USER` puede conectarse y usar el esquema, pero no crear bases, roles, esquemas ni tablas. Tampoco recibe DML ni ejecución de rutinas por anticipado; las futuras migraciones deberán conceder sólo lo necesario por objeto u operación.

PostgreSQL guarda sus datos en el volumen nombrado `postgres_data`. Las variables `POSTGRES_*` y el bootstrap sólo se aplican cuando ese volumen está vacío. Cambiar nombres o contraseñas en `.env` después del primer arranque no actualiza automáticamente los roles existentes.

## Próximas etapas

Antes de agregar tablas se deben resolver las ambigüedades de [docs/requisitos.md](docs/requisitos.md), construir el DER, definir claves candidatas/PK/FK, documentar dependencias funcionales y demostrar normalización hasta 3FN. Las migraciones irán en `db/migrations/` y se ejecutarán con el rol propietario.
