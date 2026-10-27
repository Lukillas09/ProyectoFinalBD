# Bodegas del Atuel

Repositorio ejecutable del Trabajo Práctico Integrador de Bases de Datos 2026. Un solo `docker compose up` levanta la base, aplica las migraciones SQL como propietario y arranca la API y el front:

```text
Navegador http://localhost:8080
        |
        v
Nginx (front) -- /api/* --> FastAPI (api) --> Psycopg 3 pool --> PostgreSQL 16
                                      SELECT 1              rol limitado

migrate (tarea única, propietario) -- db/migrate.sh --> 001_esquema.sql --> 002_constraints.sql
```

El navegador nunca usa nombres internos de Docker: solicita `/api/salud` al mismo origen y Nginx lo reenvía a `api:8000` dentro de la red de Compose. FastAPI se conecta a `db:5432` con la cuenta limitada, no con el propietario.

## Alcance actual

Incluye:

- PostgreSQL 16 persistente con cuentas separadas de bootstrap, propietario y API;
- FastAPI con pool Psycopg 3 y `GET /salud` mediante `SELECT 1`;
- front mínimo que muestra el estado real a través del proxy Nginx;
- modelo conceptual y relacional completo, normalización y diccionario;
- 30 tablas de negocio y una tabla técnica de migraciones;
- PK/FK compuestas, `NOT NULL`, 10 `UNIQUE`, 33 `CHECK` contando el dominio, `DEFAULT`, dos ENUM y un DOMAIN;
- runner de migraciones con transacción, registro y SHA-256, ejecutado por el servicio de única ejecución `migrate`;
- pruebas SQL de estructura, constraints y privilegios.

No incluye todavía CRUD, funciones de negocio, procedimientos, triggers, vistas, índices de rendimiento, carga masiva, reportes, pantallas nuevas ni despliegue. En particular, las columnas para totales, descuentos, estados, stock y auditoría no sustituyen la lógica pendiente.

Documentos académicos:

- [Requisitos y trazabilidad](docs/requisitos.md)
- [Modelo conceptual y DER](docs/modelo_conceptual.md)
- [Modelo relacional](docs/modelo_relacional.md)
- [Normalización](docs/normalizacion.md)
- [Diccionario de datos](docs/diccionario_datos.md)

La consigna y los apuntes de la cátedra se guardan en `material/`, pero esa carpeta está ignorada por Git: es material docente y no se publica. Cada integrante debe copiar los PDF localmente.

## Requisitos

- Docker Engine o Docker Desktop en ejecución.
- Docker Compose v2, invocado como `docker compose`.
- Puertos 8000 y 8080 libres, o valores alternativos en `.env`.

No hace falta instalar Python, PostgreSQL ni `psql` en el host.

## Configuración

1. Crear el archivo local a partir del ejemplo.

   PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

   Bash:

   ```bash
   cp .env.example .env
   ```

2. Reemplazar las tres contraseñas de ejemplo por valores diferentes y robustos:

   - `POSTGRES_BOOTSTRAP_PASSWORD`: inicialización administrativa del contenedor;
   - `DB_OWNER_PASSWORD`: propietario que aplica migraciones;
   - `DB_APP_PASSWORD`: única contraseña entregada a la API.

   `.env` está ignorado por Git. No copiar secretos reales a `.env.example`, documentación, capturas o historial.

3. Validar la configuración resuelta:

   ```bash
   docker compose config
   ```

## Iniciar el entorno

Desde la raíz:

```bash
docker compose up --build -d
docker compose ps
```

El orden de arranque es:

1. `db`: el primer arranque de un volumen ejecuta el bootstrap, que crea los roles y el esquema vacío `bodegas`;
2. `migrate`: cuando `db` está saludable, aplica las migraciones como `DB_OWNER_USER` y termina. Sólo recibe las credenciales del propietario, nunca las de bootstrap ni las de la API, y sólo está en la red interna `datos`;
3. `api`: arranca sólo si `migrate` terminó con código 0;
4. `front`.

En `docker compose ps -a`, `migrate` aparece como `Exited (0)`: es lo esperado. En arranques posteriores vuelve a ejecutarse, omite las migraciones ya registradas y termina. Si una migración falla, `api` no arranca; ver el motivo con `docker compose logs migrate`.

Los servicios pueden aparecer temporalmente como `starting`; los healthchecks reintentan mientras PostgreSQL inicia.

## Migraciones: funcionamiento y ejecución manual (opcional)

Normalmente no hace falta aplicarlas a mano: lo hace el servicio `migrate`. Para diagnóstico se puede ejecutar el mismo runner dentro de `db`:

```bash
docker compose exec db /opt/bodegas/db/migrate.sh
```

El script:

1. ordena archivos `NNN_*.sql`;
2. se conecta por TCP como `DB_OWNER_USER` a `DB_HOST` (`db` desde el servicio `migrate`, `127.0.0.1` por defecto dentro de `db`);
3. usa `ON_ERROR_STOP` y una transacción por archivo;
4. registra nombre, SHA-256 e instante en `bodegas.schema_migration`;
5. omite una migración ya aplicada sin cambios;
6. falla si el checksum registrado no coincide.

Nunca modificar una migración aplicada en un entorno compartido: agregar otra con el siguiente prefijo. No ejecutar el runner con la API ni con el superusuario de bootstrap.

El Dockerfile copia los SQL dentro de la imagen. Al agregar una migración, reconstruir para que `migrate` la vea:

```bash
docker compose up -d --build
```

Si el runner informa que el checksum de una migración aplicada cambió, el volumen tiene una versión anterior de ese archivo. En un entorno compartido corresponde una migración correctiva nueva. En un entorno local descartable se puede recrear el volumen con `docker compose down -v`, que borra todos los datos.

## Ejecutar pruebas de base

Todas juntas, en orden y con el rol correcto para cada archivo:

```bash
docker compose exec db /opt/bodegas/db/tests/run_all.sh
```

El script termina con código distinto de cero si alguna prueba falla. Desde Git Bash en Windows, anteponer `MSYS_NO_PATHCONV=1` para que no reescriba la ruta del contenedor.

Cada archivo también puede ejecutarse por separado, como se indica a continuación. Toda aserción falsa ejecuta `RAISE EXCEPTION`, así que psql termina con código 3.

### 1. Infraestructura (rol API)

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -h 127.0.0.1 -U "$DB_APP_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/001_infraestructura.sql'
```

Comprueba cuentas separadas, propietario limitado, permisos cerrados y que todos los objetos de `bodegas` pertenezcan al propietario. Vale antes y después de migrar; informa la cantidad de tablas.

### 2. Esquema y restricciones, después de migrar (propietario)

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/002_esquema_y_restricciones.sql'
```

Prueba datos mínimos válidos y rechazos por:

- PK y FK compuestas;
- `UNIQUE` y FK simple;
- `NOT NULL`;
- superficie, importe, cantidad, graduación y stock inválidos;
- permiso con fechas inválidas;
- segunda cosecha de una parcela en la misma campaña;
- CUIT que viola el DOMAIN;
- socio insertado como exportador, cliente en dos subtipos y cambio de tipo de un cliente con subtipo.

El archivo abre una transacción y termina con `ROLLBACK`: no deja filas de prueba ni borra datos existentes.

### 3. Privilegios de API, después de migrar (rol API)

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -h 127.0.0.1 -U "$DB_APP_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/003_privilegios_api.sql'
```

Confirma que existen 31 tablas y que la API sigue sin atributos administrativos, DDL, DML ni acceso a secuencias. Es intencional: los permisos de escritura se otorgarán por operación cuando exista la lógica de negocio que deba protegerlos.

## Verificar el circuito web

Abrir:

- front: <http://localhost:8080>;
- salud a través del front: <http://localhost:8080/api/salud>;
- salud directa de API: <http://localhost:8000/salud>;
- OpenAPI/Swagger: <http://localhost:8000/docs>.

Respuesta esperada:

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

PowerShell:

```powershell
Invoke-RestMethod http://localhost:8000/salud
Invoke-RestMethod http://localhost:8080/api/salud
```

### Comprobar el 503 real

```bash
docker compose stop db
curl -i http://localhost:8000/salud
docker compose start db
```

Mientras la base está detenida, la API debe responder `503` sin credenciales ni detalles internos y el front debe mostrar indisponibilidad. El pool reintenta y vuelve a 200 cuando PostgreSQL acepta conexiones.

## Verificación aislada desde cero

Para no tocar el volumen habitual se puede usar un nombre de proyecto diferente:

```bash
docker compose --env-file .env.example -p bda_etapa1_prueba up -d --build --wait
docker compose --env-file .env.example -p bda_etapa1_prueba ps -a
docker compose --env-file .env.example -p bda_etapa1_prueba exec db /opt/bodegas/db/tests/run_all.sh
```

`--wait` termina con error si algún servicio no queda saludable o si `migrate` falla. Los valores de `.env.example` sirven sólo para este entorno local descartable, no para uso real. Si los puertos 8000/8080 están ocupados, definir antes `API_PORT` y `FRONT_PORT` en la shell; esas variables tienen prioridad sobre `--env-file`.

Antes de eliminarlo, verificar que el nombre sea exactamente el aislado:

```bash
docker compose --env-file .env.example -p bda_etapa1_prueba ps
docker volume ls --filter label=com.docker.compose.project=bda_etapa1_prueba
docker compose --env-file .env.example -p bda_etapa1_prueba down -v
```

El último comando borra únicamente el volumen del proyecto de prueba indicado.

## Detener o borrar el entorno habitual

Detener contenedores, conservándolos y conservando datos:

```bash
docker compose stop
```

Eliminar contenedores y redes, conservando el volumen:

```bash
docker compose down
```

Eliminar además el volumen y todos los datos de PostgreSQL:

```bash
docker compose down -v
```

`down -v` es destructivo. El siguiente `up` ejecutará nuevamente el bootstrap y el servicio `migrate` volverá a aplicar todas las migraciones.

## Roles y persistencia

- `POSTGRES_BOOTSTRAP_USER`: superusuario técnico de la imagen oficial; no lo usa la aplicación.
- `DB_OWNER_USER`: dueño no administrativo de la base/esquema y único ejecutor de migraciones (servicio `migrate`).
- `DB_APP_USER`: puede conectar y usar el esquema, pero no crear objetos ni manipular tablas en esta etapa.

PostgreSQL guarda datos en el volumen `postgres_data`. Las variables de inicialización y el bootstrap sólo se aplican cuando el volumen está vacío. Cambiar usuarios o contraseñas en `.env` después del primer arranque no modifica roles existentes.

## Reglas pendientes de la próxima etapa

- suma diferida de composición igual a 100 % y participación mínima;
- totalidad de la jerarquía de clientes (la exclusividad ya está protegida por FK compuesta);
- descuento base 10/20/30, excepción U6 y copia histórica;
- cálculo agregado de comprobantes;
- venta con validación y descuento de stock;
- transiciones, bloqueo de renglones e impacto único de ingresos/transferencias;
- fecha de transferencia inmutable;
- auditoría automática de precio;
- funciones, procedimientos, triggers, vistas y permisos operativos mínimos.

La diferencia entre las obligaciones del PDF y la aclaración docente sobre temas no vistos —transacciones como ejemplo opcional— permanece registrada en [docs/requisitos.md](docs/requisitos.md); no se eliminó ningún requisito silenciosamente.
