# Bodegas del Atuel

Repositorio ejecutable del Trabajo Práctico Integrador de Bases de Datos 2026. Un solo `docker compose up` levanta la base, aplica las migraciones SQL como propietario y arranca la API y el front:

```text
Navegador http://localhost:8080
        |
        v
Nginx (front) -- /api/* --> FastAPI (api) --> Psycopg 3 pool --> PostgreSQL 16
                                      SELECT 1              rol limitado

migrate (tarea única, propietario) -- db/migrate.sh --> 001_esquema ... 007_roles
```

El navegador nunca usa nombres internos de Docker: solicita `/api/salud` al mismo origen y Nginx lo reenvía a `api:8000` dentro de la red de Compose. FastAPI se conecta a `db:5432` con la cuenta limitada, no con el propietario.

## Alcance actual

Incluye:

- PostgreSQL 16 persistente con cuentas separadas de bootstrap, propietario, API y reportes;
- FastAPI con pool Psycopg 3 y `GET /salud` mediante `SELECT 1`;
- front mínimo que muestra el estado real a través del proxy Nginx;
- modelo conceptual y relacional completo, normalización y diccionario (Etapa 1);
- 30 tablas de negocio y una tabla técnica de migraciones;
- 31 PK y 35 FK (varias compuestas), `NOT NULL`, 11 `UNIQUE`, 36 `CHECK` contando el dominio, 17 columnas con `DEFAULT`, dos ENUM y un DOMAIN;
- lógica de negocio en la base (Etapa 2):
  - 7 funciones (4 de cálculo pedidas por la consigna y `fn_registrar_venta`, único camino de venta de la API);
  - 4 procedimientos de ingresos y transferencias;
  - 20 triggers (10 BEFORE, 2 AFTER, 8 constraint triggers diferidos);
  - 4 vistas;
  - privilegios mínimos para la API (`bodegas_rw`) y para reportes (`bodegas_ro`);
- runner de migraciones con transacción, registro y SHA-256, ejecutado por el servicio de única ejecución `migrate`;
- pruebas SQL de estructura, reglas RN-01 a RN-15, privilegios y roles;
- carga masiva reproducible (Etapa 3): 6 años de historia, más de 150.000 ventas y 530.000 renglones, con catálogos reales, consultas de control y volcado; ver [Carga masiva](#carga-masiva-etapa-3).

Todos los conteos se tomaron del catálogo (`pg_constraint`, `pg_attrdef`, `pg_proc`, `pg_trigger`, `pg_views`).

No incluye todavía CRUD en la API, índices de rendimiento, consultas de la Etapa 5, pantallas nuevas ni despliegue.

Documentos académicos:

- [Requisitos y alcance](docs/requisitos.md)
- [Modelo conceptual y DER](docs/modelo_conceptual.md)
- [Modelo relacional](docs/modelo_relacional.md)
- [Normalización](docs/normalizacion.md)
- [Diccionario de datos](docs/diccionario_datos.md)
- [Trazabilidad regla → mecanismo → prueba](docs/trazabilidad.md)
- [Concurrencia: la última botella](docs/concurrencia.md)
- [Carga masiva: informe de la Etapa 3](docs/carga_masiva.md)

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

2. Reemplazar las cuatro contraseñas de ejemplo por valores diferentes y robustos. El bootstrap rechaza cuentas o contraseñas repetidas:

   - `POSTGRES_BOOTSTRAP_PASSWORD`: inicialización administrativa del contenedor;
   - `DB_OWNER_PASSWORD`: propietario que aplica migraciones;
   - `DB_APP_PASSWORD`: única contraseña entregada a la API;
   - `DB_REPORT_PASSWORD`: cuenta de solo lectura para reportes (`DB_REPORT_USER`).

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

| Archivo | Rol | Qué prueba |
|---|---|---|
| `001_infraestructura.sql` | API | Cuentas, propietario, membresías de grupo, permisos cerrados, propiedad de objetos. |
| `002_esquema_y_restricciones.sql` | propietario | PK/FK, UNIQUE, NOT NULL, CHECK, DOMAIN y exclusividad de subtipos. |
| `003_privilegios_api.sql` | API | Matriz exacta de privilegios de tablas, columnas y rutinas heredados de `bodegas_rw`. |
| `004_reglas_negocio.sql` | propietario | Éxito y rechazo por cada RN-01 a RN-15, U6, totalidad de clientes y funciones. |
| `005_roles.sql` | propietario con `SET ROLE` | Operaciones reales de la API y de reportes: lo permitido funciona y lo prohibido da 42501. |
| `006_conexion_reportes.sql` | reportes | La cuenta de reportes sólo lee. |
| `007_comprobante_emitido.sql` | propietario | Un comprobante confirmado no admite renglones nuevos, aun como propietario; U1 sigue funcionando. Usa varias transacciones y limpia sus datos. |

Las pruebas de propietario terminan en `ROLLBACK`, salvo `007`, que necesita una venta confirmada y la borra al terminar. La correspondencia de cada regla con su caso está en [docs/trazabilidad.md](docs/trazabilidad.md).

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

Compara los privilegios efectivos de la cuenta de la API contra la matriz esperada de `007_roles.sql` y nombra lo que sobre o falte. La API puede leer catálogos, hacer el CRUD de vinos y clientes, vender con `fn_registrar_venta`, insertar ingresos y transferencias y llamar a los procedimientos. No puede insertar comprobantes ni renglones directamente, ni escribir stock, auditoría, importes ni estados, ni tiene privilegios sobre secuencias (no los necesita para columnas IDENTITY).

### 4 a 6. Reglas de negocio y roles

```bash
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/004_reglas_negocio.sql'
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/005_roles.sql'
docker compose exec db sh -c 'PGPASSWORD="$DB_REPORT_PASSWORD" psql -h 127.0.0.1 -U "$DB_REPORT_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/tests/006_conexion_reportes.sql'
```

La demostración de concurrencia con dos sesiones no es automática; su guion está en [docs/concurrencia.md](docs/concurrencia.md).

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
- `DB_APP_USER`: cuenta de la API. Puede conectar y usar el esquema, no crear objetos; sus privilegios de datos los hereda del grupo `bodegas_rw`.
- `DB_REPORT_USER`: cuenta de solo lectura; hereda los privilegios del grupo `bodegas_ro`.
- `bodegas_rw` y `bodegas_ro`: roles de grupo con nombre fijo y sin inicio de sesión. Las migraciones otorgan los privilegios sobre objetos a estos grupos, no a las cuentas, cuyos nombres son configurables. El propietario es miembro de ambos sin heredarlos, sólo para que las pruebas puedan ejecutar `SET ROLE` dentro de una transacción revertida.

PostgreSQL guarda datos en el volumen `postgres_data`. Las variables de inicialización y el bootstrap sólo se aplican cuando el volumen está vacío. Cambiar usuarios o contraseñas en `.env` después del primer arranque no modifica roles existentes.

**Cambio de la Etapa 2:** el bootstrap ahora crea la cuenta de reportes y los roles de grupo. Un volumen inicializado antes de este cambio no los tiene: agregar `DB_REPORT_USER` y `DB_REPORT_PASSWORD` al `.env` y recrear el volumen con `docker compose down -v` (borra los datos locales).

## Carga masiva (Etapa 3)

Con el entorno levantado y la base **sin datos de negocio**:

```bash
docker compose --profile seed run --rm seed
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v fecha_referencia=2026-10-27 -f /opt/bodegas/db/seed/controles.sql'
```

- El servicio `seed` tiene el perfil `seed` y no corre con un `up` normal. Recibe sólo las credenciales del propietario.
- La carga completa tarda alrededor de un minuto.
- Parámetros: `SEMILLA`, `FECHA_REFERENCIA` y `ESCALA`.
- **Antes de la demo hay que regenerar con la fecha del día**, porque las consultas usan `CURRENT_DATE`.

Pasos completos, reproducibilidad, volcado y restauración: [db/seed/README.md](db/seed/README.md). Decisiones y resultados: [docs/carga_masiva.md](docs/carga_masiva.md).

## Pendientes para las próximas etapas

- Índices (Etapa 4): medir con la base cargada las consultas candidatas de `docs/carga_masiva.md` (sección 10), y si `v_ventas_mensuales_sala` conviene materializada.
- U1 (Etapa 5): decidir si "aplicar el descuento del tipo de cliente" recalcula sólo cabeceras con `fn_recalcular_comprobante` o también reaplica el descuento en renglones históricos, que hoy son inmutables.
- Participaciones mínimas no exigidas por una RN: al menos un maridaje por vino, un análisis por lote y un empleado por sala.

La diferencia entre las obligaciones del PDF y la aclaración docente sobre temas no vistos —transacciones como ejemplo opcional— permanece registrada en [docs/requisitos.md](docs/requisitos.md); no se eliminó ningún requisito silenciosamente.
