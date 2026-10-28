# Carga masiva de datos (Etapa 3)

Genera y carga un historial de 6 años (más de 150.000 ventas y 530.000 renglones) que cumple todas las reglas del modelo y permite resolver las consultas de la Etapa 5. El informe con decisiones, tiempos y resultados está en [docs/carga_masiva.md](../../docs/carga_masiva.md).

| Archivo | Para qué |
|---|---|
| `catalogos/*.csv` | Catálogos reales (ver abajo). |
| `generar_datos.py` | Simula la historia y la carga como propietario (`cargar`), o compara métodos de carga (`medir`). |
| `requirements.txt`, `Dockerfile` | Imagen del servicio `seed`, con versiones exactas. |
| `controles.sql` | Consultas de control: termina con código distinto de 0 si encuentra inconsistencias. |
| `post_carga.sql` | Operaciones nuevas por el camino normal sobre la base cargada; termina en `ROLLBACK`. |
| `hashes.sql` | Huella md5 por tabla, para comprobar la reproducibilidad. |

## Ejecutar

Requiere una base **sin datos de negocio**: si encuentra datos, el script se detiene sin cargar nada. Para recargar, recrear el volumen con `docker compose down -v`, que borra todos los datos.

```bash
docker compose up -d --build
docker compose --profile seed run --rm seed
```

El servicio `seed` tiene el perfil `seed`, así que no corre con un `up` normal. Espera a que `migrate` termine bien, se conecta a `db` por la red interna `datos` y recibe sólo las credenciales del propietario.

Después de la carga:

```bash
# Controles (FECHA_REFERENCIA debe ser la misma de la carga)
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v fecha_referencia=2026-10-27 -f /opt/bodegas/db/seed/controles.sql'

# Las reglas siguen activas sobre la base cargada
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -f /opt/bodegas/db/seed/post_carga.sql'

# Pruebas del proyecto (siguen pasando con la base llena)
docker compose exec db /opt/bodegas/db/tests/run_all.sh

# Huellas para comparar dos cargas
docker compose exec db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -At -F "|" -f /opt/bodegas/db/seed/hashes.sql'

# Comparación fila por fila / lotes / COPY (no modifica la base)
docker compose --profile seed run --rm seed medir
```

Desde Git Bash en Windows, anteponer `MSYS_NO_PATHCONV=1` a los comandos con rutas del contenedor.

### Parámetros

Se definen como variables de entorno al invocar `docker compose` (o en `.env`):

| Variable | Por omisión | Significado |
|---|---|---|
| `SEMILLA` | `20260427` | Semilla de `random` y Faker. |
| `FECHA_REFERENCIA` | `2026-10-27` | "Hoy" de la historia: no hay ninguna fecha posterior. |
| `ESCALA` | `1` | Factor de las tablas grandes (clientes, ventas). Entre 0 y 6. `0.1` da unos 15.000 comprobantes y 54.000 renglones: sirve para pruebas rápidas y para la nube de la Etapa 8. Por encima de 6, los identificadores alcanzarían el rango que usan las pruebas (900001 en adelante). |

Ejemplo: `ESCALA=0.1 docker compose --profile seed run --rm seed`.

Con una escala reducida, ninguna tabla supera las 100.000 filas que exige la consigna, así que el control de volumen falla, como corresponde. Para validar la carga reducida de la nube, que acepta como mínimo 10.000 filas en una tabla, agregar `-v minimo_mayor=10000` al comando de `controles.sql`.

### Antes de la demo: regenerar con la fecha del día

Las consultas de la Etapa 5 usan `CURRENT_DATE` ("la última semana", "el último trimestre"). Para que den resultados, la historia tiene que terminar el día de la demo:

```bash
docker compose down -v
docker compose up -d --build
FECHA_REFERENCIA=$(date +%F) docker compose --profile seed run --rm seed
```

En PowerShell: `$env:FECHA_REFERENCIA = (Get-Date -Format yyyy-MM-dd); docker compose --profile seed run --rm seed`.

### Reproducibilidad

"Mismos datos" significa **misma `SEMILLA`, misma `FECHA_REFERENCIA` y misma `ESCALA`**, con las **mismas versiones**:
- imagen `python:3.12.7-slim-bookworm`;
- `psycopg[binary]==3.2.3`;
- `Faker==33.1.0`.

Otra versión de Faker genera otros nombres, y otra de Python puede cambiar la secuencia de `random`.

Dos cargas desde volúmenes vacíos producen las mismas huellas por tabla (`hashes.sql`), aunque las pruebas hayan consumido valores de las secuencias entre medio. Las claves se insertan explícitamente y las secuencias se ajustan con `setval` al terminar. La única columna excluida de la huella es `comprobante.xact_alta`, el identificador de la transacción de carga, que no puede repetirse.

## Volcado y restauración

```bash
# Generar (como propietario, desde el contenedor). Git lo ignora (*.sql.gz).
docker compose exec -T db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" pg_dump -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" --schema=bodegas | gzip -9' > dump_completo.sql.gz
```

Para restaurar en una base nueva, en un volumen vacío:

1. Levantar **sólo** `db`. El bootstrap crea los roles y el esquema vacío.

   ```bash
   docker compose up -d --wait db
   ```

2. Reemplazar el esquema por el del volcado, en una sola transacción:

   ```bash
   { echo 'DROP SCHEMA bodegas CASCADE;'; gunzip -c dump_completo.sql.gz; } | docker compose exec -T db sh -c 'PGPASSWORD="$DB_OWNER_PASSWORD" psql -h 127.0.0.1 -U "$DB_OWNER_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 --single-transaction'
   ```

3. Levantar el resto. `migrate` omite las 7 migraciones, porque `schema_migration` viene en el volcado con los mismos checksums.

   ```bash
   docker compose up -d
   ```

Verificación: las huellas de `hashes.sql` y las de la base original coinciden.

El volcado no incluye contraseñas ni roles: `pg_dump` exporta sólo el esquema `bodegas`, y los roles los crea el bootstrap. No se usa `--clean`, porque su limpieza referencia tipos del esquema que en una base recién inicializada todavía no existen.

## Catálogos reales

Los catálogos no se generan al azar (paso 1 de la Etapa 3). Están en `catalogos/`, en CSV UTF-8 con encabezado.

| Archivo | Filas | Contenido | Fuente |
|---|---:|---|---|
| `cepas.csv` | 15 | Nombre, tipo (`tinta`/`blanca`) y uso | Las 12 cepas del Anexo B de la consigna (`uso = cultivo`). Se agregan 3 variedades reales que se cultivan en Argentina y que el generador **no usa** en ningún vino ni parcela (`uso = sin_uso`): Petit Verdot, Viognier y Pedro Giménez. Existen para que D2 ("cepas que no componen ningún vino ni están plantadas") tenga resultado. |
| `maridajes.csv` | 8 | Nombre y temperatura de servicio (°C) | Anexo B. Las temperaturas son orientativas, como aclara la consigna. No incluye "cordero al disco", porque lo crea la consulta I2. |
| `departamentos.csv` | 18 | Los 18 departamentos de Mendoza | Anexo B (B.3). |
| `localidades.csv` | 37 | Nombre, provincia y código postal de cuatro dígitos | Ver abajo. |
| `tipos_vino.csv` | 4 | tinto, blanco, rosado, espumante | Anexo B (B.4) y `ck_vino_tipo`. |
| `presentaciones.csv` | 5 | 187, 375, 750, 1500 (magnum) y 3000 ml | Anexo B (B.4). |

### Localidades y códigos postales

Cada código se tomó del directorio [codigo-postal.ar: Mendoza](https://codigo-postal.ar/provincia/mendoza), consultado el 27/10/2026, que lista los códigos de cuatro dígitos por localidad. Los de San Rafael (5600), General Alvear (5620), Malargüe (5613) y Tunuyán (5560) se confirmaron además con otras fuentes:

- [codigo-postal.com.ar: San Rafael](https://www.codigo-postal.com.ar/mendoza/san-rafael/);
- [Wikipedia: General Alvear, Mendoza](https://en.wikipedia.org/wiki/General_Alvear,_Mendoza) (CPA M5620);
- [codigo-postal.co: Tunuyán](https://codigo-postal.co/en-us/argentina/mendoza/tunuyan/).

El buscador oficial de Correo Argentino no pudo consultarse de forma automatizada. Ante una duda, prevalece esa fuente.

Se usa el código de cuatro dígitos, no el CPA alfanumérico, que identifica caras de manzana y no localidades. Varias localidades comparten código (5603, 5569): por eso la clave candidata de `localidad` es `(provincia, nombre, codigo_postal)` y no el código solo.

**No se incluyeron por no poder confirmarlas con la fuente:**

- **Cuadro Benegas:** no figura. Sólo aparecen "Cuadro Bombal", "Cuadro Nacional" y "Gobernador Benegas", que son otras localidades.
- **Junín:** no figura con ese nombre. Se incluye "Villa de Junín" (5573), tal como aparece.

General Alvear existe porque la consulta I1 la usa.

`encargado_regional` no es un dato real: lo genera Faker con semilla, igual que los nombres de bodegas, fincas, clientes, empleados y transportistas.
