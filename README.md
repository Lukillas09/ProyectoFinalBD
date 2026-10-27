# Bodegas del Atuel

Repositorio ejecutable del Trabajo Práctico Integrador de Bases de Datos 2026. La infraestructura conecta tres servicios reales y el esquema de negocio se instala mediante migraciones SQL manuales:

```text
Navegador http://localhost:8080
        |
        v
Nginx (front) -- /api/* --> FastAPI (api) --> Psycopg 3 pool --> PostgreSQL 16
                                      SELECT 1              rol limitado

Propietario -- db/migrate.sh --> 001_esquema.sql --> 002_constraints.sql
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
- runner de migraciones con transacción, registro y SHA-256;
- pruebas SQL de estructura, constraints y privilegios.

No incluye todavía CRUD, funciones de negocio, procedimientos, triggers, vistas, índices de rendimiento, carga masiva, reportes, pantallas nuevas ni despliegue. En particular, las columnas para totales, descuentos, estados, stock y auditoría no sustituyen la lógica pendiente.

Documentos académicos:

- [Requisitos y trazabilidad](docs/requisitos.md)
- [Modelo conceptual y DER](docs/modelo_conceptual.md)
- [Modelo relacional](docs/modelo_relacional.md)
- [Normalización](docs/normalizacion.md)
- [Diccionario de datos](docs/diccionario_datos.md)

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

## Iniciar los tres servicios

Desde la raíz:

```bash
docker compose up --build -d
docker compose ps
```

El primer arranque de un volumen crea roles y el esquema vacío `bodegas`. Las migraciones no se ejecutan dentro del bootstrap: esa separación permite probar primero los permisos y obliga a aplicarlas conscientemente como propietario.

Los servicios pueden aparecer temporalmente como `starting`; los healthchecks reintentan mientras PostgreSQL inicia.

## Aplicar migraciones

Con `db` iniciado y saludable:

```bash
docker compose exec db /opt/bodegas/db/migrate.sh
```

El script:

1. ordena archivos `NNN_*.sql`;
2. se conecta por TCP como `DB_OWNER_USER`;
3. usa `ON_ERROR_STOP` y una transacción por archivo;
4. registra nombre, SHA-256 e instante en `bodegas.schema_migration`;
5. omite una migración ya aplicada sin cambios;
6. falla si el checksum registrado no coincide.

Nunca modificar una migración aplicada en un entorno compartido: agregar otra con el siguiente prefijo. No ejecutar el runner con la API ni con el superusuario de bootstrap.

El Dockerfile copia los SQL dentro de la imagen. Si se agrega una migración a un contenedor ya creado, reconstruir `db` antes de ejecutar el runner:

```bash
docker compose up -d --build db
docker compose exec db /opt/bodegas/db/migrate.sh
```

## Ejecutar pruebas de base

### 1. Bootstrap vacío, antes de migrar

Sólo corresponde inmediatamente después de inicializar un volumen nuevo:

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_APP_PASSWORD" psql -h 127.0.0.1 -U "$DB_APP_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/001_infraestructura.sql'
```

Comprueba cuentas separadas, propietario limitado, permisos cerrados y ausencia inicial de objetos. Después de migrar, su última aserción debe fallar por diseño.

### 2. Esquema y restricciones, después de migrar

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
- CUIT que viola el DOMAIN.

El archivo abre una transacción y termina con `ROLLBACK`: no deja filas de prueba ni borra datos existentes.

### 3. Privilegios de API, después de migrar

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
docker compose --env-file .env.example -p bda_etapa2_prueba up -d --build db
docker compose --env-file .env.example -p bda_etapa2_prueba exec db /opt/bodegas/db/migrate.sh
```

Luego ejecutar las pruebas posmigración agregando los mismos `--env-file` y `-p` a los comandos anteriores. Los valores de `.env.example` sirven sólo para este entorno local descartable, no para uso real.

Antes de eliminarlo, verificar que el nombre sea exactamente el aislado:

```bash
docker compose --env-file .env.example -p bda_etapa2_prueba ps
docker volume ls --filter label=com.docker.compose.project=bda_etapa2_prueba
docker compose --env-file .env.example -p bda_etapa2_prueba down -v
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

`down -v` es destructivo. El siguiente arranque ejecutará nuevamente el bootstrap y será necesario volver a aplicar migraciones.

## Roles y persistencia

- `POSTGRES_BOOTSTRAP_USER`: superusuario técnico de la imagen oficial; no lo usa la aplicación.
- `DB_OWNER_USER`: dueño no administrativo de la base/esquema y único ejecutor de migraciones.
- `DB_APP_USER`: puede conectar y usar el esquema, pero no crear objetos ni manipular tablas en esta etapa.

PostgreSQL guarda datos en el volumen `postgres_data`. Las variables de inicialización y el bootstrap sólo se aplican cuando el volumen está vacío. Cambiar usuarios o contraseñas en `.env` después del primer arranque no modifica roles existentes.

## Reglas pendientes de la próxima etapa

- suma diferida de composición igual a 100 % y participación mínima;
- totalidad/exclusividad y correspondencia de subtipos de cliente;
- descuento base 10/20/30, excepción U6 y copia histórica;
- cálculo agregado de comprobantes;
- venta con validación y descuento de stock;
- transiciones, bloqueo de renglones e impacto único de ingresos/transferencias;
- fecha de transferencia inmutable;
- auditoría automática de precio;
- funciones, procedimientos, triggers, vistas y permisos operativos mínimos.

La diferencia entre las obligaciones del PDF y la aclaración docente sobre temas no vistos —transacciones como ejemplo opcional— permanece registrada en [docs/requisitos.md](docs/requisitos.md); no se eliminó ningún requisito silenciosamente.
