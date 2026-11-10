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
- front de la Etapa 7: cinco pantallas (catálogo, alta y edición de vino, nueva venta, transferencias y tablero) con URL de API configurable, capa HTTP única, ruteo por hash y estado real a través del proxy Nginx; ver [Front — Etapa 7](#front--etapa-7);
- modelo conceptual y relacional completo, normalización y diccionario (Etapa 1);
- 30 tablas de negocio y una tabla técnica de migraciones;
- 31 PK y 35 FK (varias compuestas), `NOT NULL`, 11 `UNIQUE`, 36 `CHECK` contando el dominio, 17 columnas con `DEFAULT`, dos ENUM y un DOMAIN;
- lógica de negocio en la base (Etapa 2):
  - 7 funciones (4 de cálculo pedidas por la consigna y `fn_registrar_venta`, único camino de venta de la API);
  - 4 procedimientos de ingresos y transferencias;
  - 21 triggers (11 BEFORE, 2 AFTER, 8 constraint triggers diferidos), uno de ellos agregado en la Etapa 6 por `009_ingreso_bodega.sql` (RN-16);
  - 4 vistas;
  - privilegios mínimos para la API (`bodegas_rw`) y para reportes (`bodegas_ro`);
- runner de migraciones con transacción, registro y SHA-256, ejecutado por el servicio de única ejecución `migrate`;
- pruebas SQL de estructura, reglas RN-01 a RN-16, privilegios y roles;
- carga masiva reproducible (Etapa 3): 6 años de historia, más de 150.000 ventas y 530.000 renglones, con catálogos reales, consultas de control y volcado; ver [Carga masiva](#carga-masiva-etapa-3);
- índices y rendimiento (Etapa 4): 6 índices en `008_indices.sql` (48 en total en el esquema, contando los de PK y `UNIQUE`), medidos antes y después con `EXPLAIN (ANALYZE, BUFFERS)`; ver [Medir el rendimiento](#medir-el-rendimiento-etapa-4);
- consultas SQL requeridas (Etapa 5): S1-S12, U1-U6, I1-I6 y D1-D6 en `consultas/`, ejecutables con `consultas/ejecutar.sh`, verificadas en `docs/consultas.md` y planes en `docs/consultas/planes/`;
- **API REST completa (Etapa 6):** catálogo y ABM de vinos, CRUD de clientes (3 subtipos), venta y consulta de comprobantes, circuitos de transferencias e ingresos, reportes de solo lectura (S1, S8, S6, S7) y trazabilidad como supuesto, más las rutas `GET /catalogos/*` de la Etapa 7; 261 pruebas automatizadas en entorno aislado; ver [API REST — Etapa 6](#api-rest--etapa-6).
- **Front completo (Etapa 7):** las tres condiciones de la consigna están probadas con 33 pruebas (25 de punta a punta con Playwright y 8 estáticas), desde un volumen vacío: las cinco pantallas contra la API real, una venta sin stock que muestra RN-09 y no deja datos a medias, y un front sin cálculos de importes ni stock; ver [Usar el front](#usar-el-front), [Ejecutar las pruebas del front](#ejecutar-las-pruebas-del-front) y el [informe de cierre](docs/cierre_etapa7.md).

Todos los conteos se tomaron del catálogo (`pg_constraint`, `pg_attrdef`, `pg_proc`, `pg_trigger`, `pg_views`, `pg_indexes`).

Documentos académicos:

- [Requisitos y alcance](docs/requisitos.md)
- [Modelo conceptual y DER](docs/modelo_conceptual.md)
- [Modelo relacional](docs/modelo_relacional.md)
- [Normalización](docs/normalizacion.md)
- [Diccionario de datos](docs/diccionario_datos.md)
- [Trazabilidad regla → mecanismo → prueba](docs/trazabilidad.md)
- [Concurrencia: la última botella](docs/concurrencia.md)
- [Carga masiva: informe de la Etapa 3](docs/carga_masiva.md)
- [Índices y rendimiento: informe de la Etapa 4](docs/rendimiento.md)
- [Consultas SQL: informe de la Etapa 5](docs/consultas.md)
- [Contrato de la API REST (Etapa 6)](docs/api.md)
- [Informe de cierre de la Etapa 6](docs/cierre_etapa6.md)
- [Front: plan, pantallas y contrato (Etapa 7)](docs/front.md)
- [Informe de cierre de la Etapa 7](docs/cierre_etapa7.md)

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
| `008_ingreso_bodega.sql` | propietario | RN-16 (`009`): un ingreso sólo admite vinos de su bodega de origen. |

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
- OpenAPI/Swagger: directo en <http://localhost:8000/docs> o por el proxy en <http://localhost:8080/api/docs> ("Try it out" llama a `/api/...`).

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

## Front — Etapa 7

El front usa HTML, CSS y módulos JavaScript nativos, sin frameworks, npm ni paso de compilación. Su estructura común es:

```text
front/
├── config.js       única URL base de la API
├── index.html      encabezado, navegación, salud y contenedor de vistas
├── styles.css
└── js/
    ├── api.js      única capa que realiza pedidos HTTP
    ├── app.js      punto de entrada e indicador de salud
    ├── ui.js       mensajes, formatos y helpers del DOM
    ├── router.js   ruteo por hash y contrato de las pantallas
    └── pantallas/  catalogo.js, vino.js, venta.js, transferencias.js y tablero.js
```

### Usar el front

Con el entorno levantado (`docker compose up -d --build --wait`), abrir <http://localhost:8080>. Ese es el puerto por omisión; si está ocupado, `FRONT_PORT` en `.env` lo cambia. La barra de navegación tiene las cinco pantallas:

| Pantalla | Ruta | Qué permite |
|---|---|---|
| Catálogo | `#/vinos` | Filtrar por tipo, cepa, bodega y añada, paginar, ver el detalle (composición, maridajes y stock total) y eliminar un vino |
| Nuevo vino | `#/vinos/nuevo` y `#/vinos/{cod}/editar` | Alta y edición de un vino con su composición de cepas y sus maridajes |
| Nueva venta | `#/venta` | Elegir cliente (por código), sala y vinos, y registrar la venta |
| Transferencias | `#/transferencias` y `#/transferencias/{nro}` | Crear una transferencia a una sala, cargar renglones, terminarla y procesarla |
| Tablero | `#/tablero` | Top 10 de vinos, ventas por sala del último trimestre (gráfico) y vinos sin stock en una sala |

Los filtros, la página y el vino abierto del catálogo viven en la URL, así que *Atrás* y *recargar* funcionan. Los importes, descuentos y stock que se ven los calcula PostgreSQL, y las reglas de negocio se muestran con el mensaje que devuelve la API (por ejemplo, RN-05 si la composición no suma 100 %, o RN-09 si no hay stock).

Estas pantallas **escriben** (altas, ventas, transferencias). Para probarlas sin tocar los datos de trabajo, usar un proyecto de Compose aparte, como hace `front/tests/ejecutar.sh`.

La URL se cambia en un solo lugar, [`front/config.js`](front/config.js):

```js
window.BODEGAS_CONFIG = { apiBase: "/api" };
```

`index.html` carga ese archivo antes de los módulos. En local se conserva `/api` para que Nginx reenvíe los pedidos al servicio interno sin exponer su nombre ni requerir CORS.

Las pantallas no usan `fetch` directamente: invocan las funciones de [`front/js/api.js`](front/js/api.js). Esa capa arma las rutas, conserva los importes decimales como strings y traduce las respuestas fallidas a `ErrorApi`; la interfaz muestra el `detail` y el `codigo` recibidos sin reemplazarlos.

## Ejecutar las pruebas de la API

```bash
api/tests/ejecutar.sh
```

Levanta un proyecto de Compose aislado (`bodegas_pruebas`) desde un volumen vacío, lo carga con `ESCALA=0.1`, corre pytest como `bodegas_api` y lo baja con `down -v`. Tarda alrededor de 60 s y no toca el entorno habitual. Opciones y reglas para escribir pruebas: [api/README.md](api/README.md#pruebas).

## Ejecutar las pruebas del front

```bash
front/tests/ejecutar.sh                 # todas: 33 casos, 26 funciones
front/tests/ejecutar.sh -k venta        # los argumentos van a pytest
MANTENER=1 front/tests/ejecutar.sh      # deja el proyecto arriba para depurar
```

Es el mismo patrón que la API: levanta un proyecto de Compose aislado (`bodegas_front_pruebas`, puertos 18900 y 18980) desde un volumen vacío, lo carga con `ESCALA=0.1`, corre pytest con Playwright para Python y lo baja con `down -v`. Tarda alrededor de 70 s y **nunca toca el entorno habitual**: las pruebas crean vinos, ventas y transferencias.

- El navegador (Chromium, en la imagen oficial de Playwright con versión fija) corre dentro de la red de Compose, abre `http://front` y llama a `/api` por nginx, como en producción. No depende del navegador instalado en el equipo.
- La base se verifica con el rol de reportes, de sólo lectura. Las escrituras pasan por el front y la API.
- Incluye una prueba estática de que `front/js` no calcula importes ni stock (`test_sin_calculos.py`).
- Las capturas de las pruebas que fallan quedan en `front/tests/salida/`, que no se versiona.
- La primera vez descarga la imagen de Playwright, que es grande (su capa principal pesa unos 750 MB).

Detalle de cada prueba, evidencia de los tres criterios de la consigna y pendientes: [docs/cierre_etapa7.md](docs/cierre_etapa7.md).

## API REST — Etapa 6

### Objetivo y alcance

La Etapa 6 implementa la API REST completa según la consigna del TPI (páginas 16-17 del PDF). La API expone los recursos del dominio vinícola delegando todas las reglas de negocio, cálculos de importes, descuentos, stock y cambios de estado a PostgreSQL mediante funciones, procedimientos y triggers. La API se limita a validar la forma de los datos (Pydantic), invocar los objetos de la base y traducir los errores por SQLSTATE.

**Principios de diseño:**

- **Driver nativo y SQL parametrizado:** FastAPI + Psycopg 3 con pool de conexiones. Sin ORM ni query builders.
- **Capa de acceso a datos:** Una función por consulta en `api/app/datos/` (`vinos.py`, `clientes.py`, `comprobantes.py`, `reportes.py`, `documentos.py`).
- **Transacciones explícitas:** Operaciones de varias sentencias usan `with conn.transaction():` en los endpoints.
- **Reglas en la base:** Totales, descuentos, stock, estados y auditoría los resuelve PostgreSQL (`fn_registrar_venta`, `sp_terminar_*`, `sp_procesar_*`, triggers).
- **Privilegios mínimos:** La API conecta como `bodegas_api` (grupo `bodegas_rw`), sin permisos de DDL ni escritura directa sobre columnas de stock, importes, auditoría o estados.
- **Traducción de errores:** `api/app/errores.py` mapea SQLSTATE a códigos HTTP (23505→409, 23503→409/422, 23514→422, P0001→409, P0002→404, 40001/40P01→503 con Retry-After, 42501→500, validación→422).

### Arquitectura

```
Navegador → Nginx (front, puerto 8080) → /api/* → FastAPI (api, puerto 8000) → Psycopg 3 pool → PostgreSQL 16 (db)
                                                         ↑
                                                  rol bodegas_api (bodegas_rw)
```

- El navegador usa únicamente rutas públicas (`/api/salud`, `/api/vinos`, etc.).
- Nginx reenvía `/api/*` a `api:8000` dentro de la red Docker `datos`.
- FastAPI abre el pool al arrancar y lo cierra al terminar (`lifespan` en `api/app/main.py`).
- Healthchecks: `db` con `pg_isready`, `api` llamando `GET /salud`, `front` comprobando Nginx.

### Organización de `api/app/`

```
api/app/
├── config.py          # Lectura y validación de variables de entorno
├── database.py        # Pool Psycopg 3, dependencia `conexion`, healthcheck `SELECT 1`
├── errores.py         # Traducción SQLSTATE → HTTP + ErrorRespuesta
├── esquemas.py        # Modelos Pydantic (entrada/salida, paginación, filtros)
├── main.py            # FastAPI app, lifespan, middleware prefix /api, routers
├── datos/             # Capa de acceso a datos (SQL parametrizado)
│   ├── vinos.py       # Catálogo + ABM vinos (composición, maridajes)
│   ├── clientes.py    # CRUD clientes (socio, distribuidor, exportador)
│   ├── comprobantes.py# Venta (fn_registrar_venta) y consulta
│   ├── reportes.py    # Reportes S1, S8, S6, S7 + trazabilidad
│   └── documentos.py  # Transferencias e ingresos (cabecera, renglones, terminar, procesar)
└── routers/           # Endpoints HTTP
    ├── vinos.py
    ├── clientes.py
    ├── comprobantes.py
    ├── transferencias.py
    ├── ingresos.py
    └── reportes.py
```

### Levantar el proyecto

```bash
# 1. Configurar
cp .env.example .env
# Editar .env con 4 contraseñas DISTINTAS y robustas

# 2. Validar
docker compose config

# 3. Levantar (primera vez: bootstrap + migraciones + carga)
docker compose up --build -d
docker compose ps

# 4. Cargar datos (base sin datos de negocio)
docker compose --profile seed run --rm seed

# 5. Verificar
curl http://localhost:8000/salud
curl http://localhost:8080/api/salud
```

El orden de arranque: `db` (bootstrap) → `migrate` (001-010 como propietario) → `api` → `front`. `migrate` sale con `Exited (0)`.

### Migraciones y carga inicial

- **Migraciones** (`db/migrations/001_esquema.sql` a `010_privilegios_trazabilidad.sql`): las aplica el servicio `migrate` como `DB_OWNER_USER` al hacer `docker compose up`. Para ejecutar manualmente:
  ```bash
  docker compose exec db /opt/bodegas/db/migrate.sh
  ```
- **Carga masiva** (`db/seed/`, perfil `seed`): solo con base vacía, credenciales de propietario.
  ```bash
  docker compose --profile seed run --rm -e ESCALA=0.1 seed
  ```
  Parámetros: `SEMILLA` (dft 20260427), `FECHA_REFERENCIA` (dft 2026-10-27), `ESCALA` (dft 1). Misma semilla/fecha/escala → mismos datos (ver `db/seed/hashes.sql`).

### Swagger y OpenAPI

- **Directo (desarrollo):** <http://localhost:8000/docs>
- **Por proxy Nginx (producción):** <http://localhost:8080/api/docs> ("Try it out" llama a `/api/...`)
- **OpenAPI JSON:** <http://localhost:8000/openapi.json> o <http://localhost:8080/api/openapi.json>
- Middleware `PrefijoDelProxy` en `main.py` detecta `X-Forwarded-Prefix: /api` y ajusta `root_path` para que Swagger genere URLs correctas.

### Resumen de endpoints

| Recurso | Endpoints | Detalle |
|---------|-----------|---------|
| **Salud** | `GET /salud` | `SELECT 1` → 200/503 |
| **Vinos** | `GET /vinos`, `GET /vinos/{cod}`, `POST /vinos`, `PUT /vinos/{cod}`, `DELETE /vinos/{cod}` | Catálogo con filtros (tipo, cepa, bodega, añada) y paginación; ficha con composición, maridajes, stock; ABM en transacción |
| **Clientes** | `GET /clientes`, `GET /clientes/{id}`, `POST /clientes`, `PUT /clientes/{id}`, `DELETE /clientes/{id}` | 3 subtipos (socio, distribuidor, exportador); descuento calculado por `fn_descuento_cliente`; permisos exportador |
| **Comprobantes** | `POST /comprobantes`, `GET /comprobantes/{nro}` | Venta completa vía `fn_registrar_venta`; importes y stock en la base |
| **Transferencias** | `POST /transferencias`, `GET /transferencias/{nro}`, `POST /transferencias/{nro}/renglones`, `POST /transferencias/{nro}/terminar`, `POST /transferencias/{nro}/procesar` | Circuito `en_confeccion → terminado → procesado`; stock movido por `sp_procesar_transferencia` |
| **Ingresos** | `POST /ingresos`, `GET /ingresos/{cod}`, `POST /ingresos/{cod}/renglones`, `POST /ingresos/{cod}/terminar`, `POST /ingresos/{cod}/procesar` | Mismo circuito; RN-16: solo vinos de la bodega de origen; stock sumado por `sp_procesar_ingreso` |
| **Reportes** | `GET /reportes/top-vinos`, `/ventas-por-sala`, `/vinos-sin-stock`, `/transportista-activo`, `/trazabilidad/{cod}` | S1, S8, S6, S7 parametrizados; trazabilidad como supuesto documentado |

### Gestión de vinos y clientes

**Vinos (`/vinos`):**
- **Catálogo:** `GET /vinos?tipo=tinto&anada=2023&limite=10&desplazamiento=0` → `Pagina[VinoResumen]`
- **Ficha:** `GET /vinos/{cod}` → `VinoDetalle` (composición, maridajes, stock total `v_stock_total_vino`)
- **Alta:** `POST /vinos` con `VinoEntrada` (nombre, tipo, añada, volumen, graduación, precio, CUIT bodega, composición `[{id_cepa, porcentaje}]`, maridajes `[id]`) → 201 + `Location` + ficha
- **Modificación:** `PUT /vinos/{cod}` reemplaza todo (incluye composición y maridajes) en transacción; auditoría de precio automática (RN-13)
- **Baja:** `DELETE /vinos/{cod}` → 204; 409 si tiene historia (ventas, ingresos, transferencias, auditoría de precio)

**Clientes (`/clientes`):**
- **Listado:** `GET /clientes?tipo=exportador&id_localidad=5` → `Pagina[ClienteResumen]`
- **Ficha:** `GET /clientes/{id}` → `ClienteDetalle` (datos comunes, subtipo, permisos, descuento de `fn_descuento_cliente`)
- **Alta:** `POST /clientes` con `ClienteEntrada` (discriminador `tipo`); transacción única (cliente + subtipo + permisos)
- **Modificación:** `PUT /clientes/{id}` reemplaza datos comunes y subtipo; `tipo` inmutable (FK compuesta lo impide)
- **Baja:** `DELETE /clientes/{id}` → 204; 409 si tiene comprobantes

### Registro y consulta de comprobantes

- **Venta:** `POST /comprobantes` con `{id_cliente, id_sala, renglones: [{cod_vino, cantidad}]}`
  - Llama a `fn_registrar_venta(id_cliente, id_sala, vinos[], cantidades[])` en una transacción
  - Valida vinos inexistentes antes (422 con códigos); stock, vino repetido, cantidad ≤ 0, sin renglones → 409 (P0001)
  - Cliente/sala inexistente → 422 (23503)
  - Devuelve 201 con comprobante completo (cabecera con importes guardados + renglones con precio/descuento congelados)
- **Consulta:** `GET /comprobantes/{nro}` → cabecera + renglones tal como quedaron en la base

### Funciones y reglas de negocio delegadas a PostgreSQL

| Regla | Mecanismo en BD | Invocación API |
|-------|-----------------|----------------|
| RN-05: composición suma 100% | Constraint trigger diferido | Verificado en COMMIT de alta/modificación vino |
| RN-06: descuento por tipo/cliente | `fn_descuento_cliente` + `trg_cliente_excepcion` | Leído en ficha cliente; copiado a renglón al vender |
| RN-08: totales derivados | `fn_total_comprobante` + triggers | `fn_registrar_venta` crea cabecera y renglones atómicos |
| RN-09: stock no negativo | Trigger BEFORE + AFTER `renglon_comprobante` | Validado en `fn_registrar_venta` con `FOR UPDATE` |
| RN-10: ingreso estados + impacto único | ENUM + `sp_terminar_ingreso`/`sp_procesar_ingreso` | API llama procedimientos; no toca `estado` ni `stock` |
| RN-11: transferencia estados + fecha inmutable | ENUM + triggers + `sp_procesar_transferencia` | API llama procedimientos; no toca `estado` ni `stock` |
| RN-12: documentos solo editables en confección | Triggers `renglon_*` + `xact_alta` en comprobante | API solo inserta renglones; base rechaza si no es confección |
| RN-13: auditoría de precio | `trg_vino_auditoria_precio` AFTER UPDATE | Automática al cambiar precio en PUT vino |
| RN-14: no borrar con historia | FK `ON DELETE RESTRICT` | DELETE vino/cliente → 409 si hay dependientes |
| RN-16: ingreso solo vinos de su bodega | `trg_renglon_ingreso_bodega` (009) | API inserta renglón; base valida `cuit_bodega` |

La API **nunca** calcula importes, descuentos ni stock; no hace `UPDATE` directo sobre `stock_sala`, `stock_deposito`, `comprobante`, `auditoria_precio`, `ingreso.estado`, `transferencia.estado`.

### Manejo de errores HTTP

Todos los errores responden con `ErrorRespuesta`:
```json
{"detail": "RN-09: stock insuficiente del vino 1 en la sala 1.", "codigo": "P0001"}
{"detail": "Datos de entrada inválidos.", "codigo": "validacion", "errores": [{"campo": "query.limite", "mensaje": "Input should be less than or equal to 100"}]}
```

| SQLSTATE / Origen | HTTP | `codigo` | Cuándo |
|-------------------|------|----------|--------|
| 23505 (UNIQUE/PK) | 409 | `23505` | Vino/cliente/permiso repetido |
| 23503 (FK dato faltante) | 422 | `23503` | Cliente/sala/bodega/cepa inexistente |
| 23503 (FK con dependientes) | 409 | `23503` | Borrar vino/cliente con historia |
| 23514 (CHECK) | 422 | `23514` | Precio ≤ 0, graduación fuera de rango, % inválido |
| 23502 (NOT NULL) | 422 | `23502` | Campo obligatorio faltante (`columna`) |
| P0001 (RAISE EXCEPTION RN) | 409 | `P0001` | Reglas de negocio (stock, estados, composición, etc.) |
| P0002 (procedimiento no halla fila) | 404 | `P0002` | Terminar/procesar documento inexistente |
| 40001, 40P01 (serialización/deadlock) | 503 | `40001`/`40P01` | Concurrencia → `Retry-After: 1` |
| 42501 (permission denied) | 500 | `interno` | Bug de privilegios; se loguea sin detalles |
| 08xxx, PoolTimeout | 503 | `no_disponible` | Base no responde |
| Validación FastAPI/Pydantic | 422 | `validacion` | Parámetros/cuerpo inválidos (`errores[]`) |

### Autenticación y permisos

- **Autenticación:** No implementada (extra opcional según PDF). Todas las escrituras son públicas.
- **Permisos a nivel BD:** La API conecta como `bodegas_api` (hereda `bodegas_rw`). Ver matriz en `db/migrations/007_roles.sql` y prueba `db/tests/003_privilegios_api.sql`.
- **Lo que la API PUEDE:** SELECT catálogos, CRUD vinos/clientes, `fn_registrar_venta`, INSERT cabecera/renglones ingresos/transferencias, CALL procedimientos, SELECT vistas/reportes.
- **Lo que la API NO PUEDE:** INSERT/UPDATE/DELETE directo sobre `comprobante`, `renglon_comprobante`, `stock_*`, `auditoria_precio`, `ingreso.estado`, `transferencia.estado`, secuencias, `empleado`.

### Consultas SQL parametrizadas

Todas las consultas en `api/app/datos/` usan placeholders y parámetros separados:
```python
# Ejemplo en vinos.py
LISTAR = """
SELECT ... FROM vino v JOIN bodega b ON ...
WHERE (%(tipo)s::varchar IS NULL OR v.tipo = %(tipo)s)
  AND (%(cuit_bodega)s::varchar IS NULL OR v.cuit_bodega = %(cuit_bodega)s)
...
"""
parametros = {"tipo": filtros.tipo, "cuit_bodega": filtros.cuit_bodega, ...}
filas = cur.execute(LISTAR, parametros).fetchall()
```

- Psycopg 3 envía SQL y parámetros por separado (protocolo extendido).
- Sin f-strings, concatenación ni interpolación de valores de usuario.
- Identificadores dinámicos no se usan; SQL es estático y legible en el código.

### Prevención de SQL Injection

- **Capa 1 (Pydantic):** Filtros tipados (`Literal["tinto","blanco","rosado","espumante"]`, rangos, regex CUIT). Entrada maliciosa → 422 `validacion` antes de llegar a BD.
- **Capa 2 (Psycopg 3):** Valores viajan como parámetros; PostgreSQL los trata como datos literales.
- **Pruebas automatizadas:** `api/tests/test_sql_injection.py` (14 casos):
  - Consulta legítima (`tipo=tinto`) → 200
  - Payloads `OR '1'='1`, `DROP TABLE`, `UNION SELECT`, comentarios SQL → 422 `validacion`
  - Valores válidos inexistentes → 200 lista vacía (sin inyección)
  - Verificación `count(*)` antes/después → idéntico (tabla intacta)
- Ejecutar: `api/tests/ejecutar.sh -k "test_sql_injection"`

### Ejecución de pruebas automatizadas

```bash
# Suite completa (entorno aislado, volumen vacío, ESCALA=0.1)
api/tests/ejecutar.sh

# Solo las 3 pruebas que nombra la consigna (stock, estado, CHECK)
api/tests/ejecutar.sh -m consigna

# Solo prevención de inyección SQL
api/tests/ejecutar.sh -k "test_sql_injection"
```

- **261 pruebas** (161 funciones, 261 casos con parametrización; las 9 últimas son de las rutas de catálogo de la Etapa 7).
- **49 pruebas** provocan errores reales de PostgreSQL y verifican "sin datos a medias".
- **3 pruebas `consigna`** obligatorias: RN-09 stock (409), RN-11 estado (409), CHECK precio (422).
- **14 pruebas SQL Injection** (todas pasadas).
- Pruebas de base: `docker compose exec db /opt/bodegas/db/tests/run_all.sh` (8/8 pasadas).

### Enlaces de referencia

- **Contrato completo:** [docs/api.md](docs/api.md) — Endpoints, esquemas, códigos HTTP, traducción SQLSTATE, ejemplos reales, preguntas abiertas.
- **Informe de cierre:** [docs/cierre_etapa6.md](docs/cierre_etapa6.md) — Verificación integral, checklist 5 criterios, tabla PRs/revisiones, evidencias.
- **Requisitos y trazabilidad:** [docs/requisitos.md](docs/requisitos.md) — Sección 3.8 (API REST), 5 criterios oficiales, diferencias PDF/aclaración.
- **Reglas de Git:** [AGENTS.md](AGENTS.md) — Rama por etapa, commits pequeños, PR con revisión cruzada, sin secretos.

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

## Medir el rendimiento (Etapa 4)

Con el entorno levantado y la base cargada, desde la raíz del repositorio (en Windows, con Git Bash):

```bash
REPETICIONES=5 db/perf/medir.sh despues   # o "antes", sin los índices de 008
db/perf/experimentos.sh                   # todos; "db/perf/experimentos.sh 04" corre sólo el 04
```

- `medir.sh` ejecuta `ANALYZE` y mide cada consulta de `db/perf/consultas_candidatas.sql` con `EXPLAIN (ANALYZE, BUFFERS)`: una ejecución inicial y `REPETICIONES` más, informando la mediana. Guarda los planes en `docs/rendimiento/planes/<consulta>_<etiqueta>.txt`, las métricas en `resultados_<etiqueta>.csv` y la configuración en `contexto_<etiqueta>.txt`. Las sentencias que modifican datos se revierten.
- `experimentos.sh` corre los experimentos de `db/perf/experimentos/`, todos dentro de `BEGIN … ROLLBACK`, y guarda la salida en `docs/rendimiento/experimentos/`. Al terminar muestra el conteo de índices, para confirmar que no quedó ninguno de prueba.
- Los tiempos dependen de la máquina y de la fecha de carga: comparar sólo mediciones tomadas en el mismo entorno.
- La línea base "antes" se tomó sin `008_indices.sql`. Para repetirla hay que usar una base migrada hasta 007, por ejemplo en un proyecto aislado (`-p`).

Resultados y decisiones: [docs/rendimiento.md](docs/rendimiento.md).

## Consultas SQL (Etapa 5)

Las consultas de la Etapa 5 están implementadas en `consultas/`:

- `consultas/select.sql`: S1 a S12 (consultas de análisis y reportes; S9-S12 con `EXPLAIN (ANALYZE, BUFFERS)` y planes en `docs/consultas/planes/`).
- `consultas/insert.sql`: I1 a I6 (inserciones en transacción con `ROLLBACK`).
- `consultas/update.sql`: U1 a U6 (actualizaciones en transacción con `ROLLBACK`).
- `consultas/delete.sql`: D1 a D6 (eliminaciones controladas en transacción con `ROLLBACK`).
- `consultas/ejecutar.sh`: ejecuta un archivo como propietario con `ON_ERROR_STOP=1`; si falla, termina con código distinto de 0.
- `consultas/plantilla_consultas.sql`: plantilla de documentación, no ejecutable.

Con la base cargada, cada archivo se ejecuta dentro del contenedor `db`:

```bash
docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
docker compose exec db /opt/bodegas/consultas/ejecutar.sh update.sql -v cuit_bodega=33532580264
```

Cada archivo define sus parámetros con valores por omisión de la carga, y cualquiera se reemplaza con `-v`. Cada modificación está en su propio `BEGIN … ROLLBACK`, así que el archivo no deja cambios. Los períodos usan `CURRENT_DATE`: para que S3 y las demás consultas por período devuelvan filas, conviene cargar con `FECHA_REFERENCIA` igual a la fecha del día. Al cambiar un `.sql`, reconstruir la imagen con `docker compose up -d --build db`.

Detalle de parámetros: [consultas/README.md](consultas/README.md). El informe, la verificación con las filas de cada consulta y el checklist de aceptación están en [docs/consultas.md](docs/consultas.md). Los planes de rendimiento se miden con `db/perf/medir.sh` y se documentan en [docs/rendimiento.md](docs/rendimiento.md); la demostración de concurrencia en [docs/concurrencia.md](docs/concurrencia.md).

## Pendientes para las próximas etapas

### Pendientes reales (Etapa 7 - Front)
- Pantallas mínimas: catálogo paginado con filtros, alta/edición de vino, venta con error de stock, transferencias con botones según estado, tablero (top 10, gráfico ventas trimestrales, vinos sin stock).
- Centralizar llamadas a la API, URL base configurable, mostrar mensajes reales de reglas, no calcular importes ni stock en el front.

### Pendientes reales (Etapa 8 - Nube)
- Comparar dos proveedores, justificar uno, crear cuentas propietario/API/reportes, aplicar migraciones, HTTPS, PostgreSQL cifrado, puerto restringido, secretos externos, CORS limitado, rechazo comprobado de conexión no autorizada, backup/restauración con conteos.
- Demo de 10-15 minutos en nube: venta, rechazo por stock, procesar transferencia, consulta con plan de ejecución.

### Decisiones de diseño documentadas (no obligatorias, pero registradas)
- **U1 (recalcular comprobantes):** se resolvió con `fn_recalcular_comprobante` y descuento congelado en cada renglón (RN-12). Reaplicar descuento actual a ventas históricas contradiría RN-12. Ver `consultas/update.sql` y `docs/consultas.md`.
- **Trazabilidad (`/reportes/trazabilidad/{cod}`):** el modelo no vincula vino-lotes; se implementó como supuesto (lotes de la bodega, campaña=añada, cepas del corte). Pendiente respuesta de cátedra. Ver `docs/api.md` sección 6 y `docs/requisitos.md` 3.8.
- **`POST /ingresos/{cod}/terminar`:** no listado en PDF pero RN-10 exige estado `terminado`; implementado para que ingresos creados por API puedan procesarse. Pendiente confirmación. Ver `docs/api.md` sección 6.
- **Zona horaria:** fechas en UTC (`CURRENT_DATE`/`CURRENT_TIMESTAMP` del servidor BD). Corregir exige fijar `timezone` de la base; decisión pendiente para Etapa 8.

### Aclaraciones académicas
- La diferencia entre obligaciones del PDF y aclaración docente sobre temas no vistos (transacciones como ejemplo opcional) permanece registrada en [docs/requisitos.md](docs/requisitos.md) §4; no se eliminó ningún requisito silenciosamente.
- Participaciones mínimas no exigidas por una RN: al menos un maridaje por vino, un análisis por lote, un empleado por sala.
- Anexo C de preguntas de defensa mencionado en PDF pero no disponible en el material entregado.
