# Bodegas del Atuel - reglas del proyecto

## Propósito

Este repositorio corresponde al Trabajo Práctico Integrador de Bases de Datos 2026 de la UTN Facultad Regional San Rafael. La prioridad académica es que cada decisión de datos pueda explicarse y defenderse, no solamente que el sistema funcione.

Antes de modificar el alcance, consultar `docs/requisitos.md` y la consigna original en `material/TPI_Bodegas_del_Atuel.pdf`. Las aclaraciones posteriores de la cátedra se registran en `docs/requisitos.md`; no se eliminan requisitos del PDF de manera silenciosa.

## Reglas técnicas obligatorias

- Usar PostgreSQL 16.
- Implementar la API con Python, FastAPI y Psycopg 3 con pool de conexiones.
- Escribir SQL directo y parametrizado. No usar ORM ni query builders que oculten SQL.
- Usar HTML, CSS y JavaScript sin frameworks para el front. Cambiar esta tecnología requiere una decisión explícita del usuario o de la cátedra; documentarlo por sí solo no autoriza el cambio.
- Mantener PostgreSQL, API y front ejecutables mediante Docker Compose.
- Leer credenciales y configuración desde variables de entorno. Nunca versionar `.env`, contraseñas reales, cadenas de conexión privadas, dumps con secretos ni tokens.
- La API debe usar `bodegas_api`, o el nombre configurado equivalente, nunca la cuenta propietaria ni la cuenta de inicialización.
- El rol de la API no puede ser superusuario ni crear bases, roles, esquemas o tablas.
- Totales, descuentos y stock pertenecen a PostgreSQL. La API y el front sólo invocan o presentan esos resultados.
- Los nombres de servicios de Docker, como `api` y `db`, son internos. El JavaScript del navegador debe llamar rutas públicas o del mismo origen, actualmente `/api/*` a través de Nginx.

## Reglas de modelado y documentación

Para cada entidad del modelo, documentar:

1. Qué representa y por qué es una entidad independiente.
2. Todas sus claves candidatas y la clave primaria elegida.
3. Si el identificador es natural o subrogado, con ventajas, riesgos y alternativa descartada.
4. Relaciones, roles, participación opcional u obligatoria y cardinalidades mínima y máxima en ambos extremos.
5. Claves foráneas y acciones `ON UPDATE`/`ON DELETE`, con justificación.
6. Dependencias funcionales relevantes que afectan su transformación al modelo relacional.
7. Nulabilidad, dominios y reglas de integridad.

La verificación de 1FN, 2FN y 3FN se realiza sobre cada relación o tabla resultante, considerando todas sus claves candidatas, atributos primos y dependencias funcionales; no sobre la entidad conceptual aislada.

Toda regla de negocio debe poder trazarse como:

`regla -> mecanismo PostgreSQL -> caso de prueba`

Elegir el mecanismo más simple que proteja la regla en todos los accesos:

- `PRIMARY KEY`, `UNIQUE`, `NOT NULL`, `CHECK`, `DEFAULT` o `DOMAIN` para reglas de fila y dominio.
- `FOREIGN KEY` para existencia e integridad referencial.
- Función para cálculos reutilizables.
- Trigger para reglas automáticas que dependen de otras filas, tablas o del momento actual.
- Procedimiento para operaciones de varios pasos cuando corresponda.

No usar `FLOAT` para dinero. Usar `NUMERIC(p,s)`. No modelar estados como texto libre cuando corresponde un `ENUM` o catálogo controlado. No usar funciones no determinísticas, como `CURRENT_DATE`, dentro de un `CHECK`.

## Migraciones y permisos

- Guardar las migraciones en `db/migrations/` con prefijos numéricos consecutivos.
- Ejecutarlas con el rol propietario del proyecto, no con el rol de la API ni con el superusuario de bootstrap.
- No modificar una migración ya aplicada en un entorno compartido; crear una nueva migración correctiva.
- Mantener los objetos del negocio en el esquema `bodegas`, salvo una decisión posterior justificada.
- Probar periódicamente la creación desde una base y un volumen vacíos.
- Nombrar restricciones e índices de forma estable y legible.
- Revisar privilegios sobre tablas, secuencias y rutinas cada vez que se agreguen objetos. El rol de la API recibe únicamente los privilegios necesarios.

## SQL y API

- Concentrar el acceso SQL en módulos dedicados; no dispersar consultas en controladores.
- Parametrizar todos los valores externos con las capacidades de Psycopg. Nunca interpolar ni concatenar entrada del usuario en SQL.
- Seleccionar columnas explícitamente en código de aplicación; evitar `SELECT *`.
- Traducir errores de PostgreSQL por `SQLSTATE` cuando se implementen operaciones de negocio, sin filtrar detalles internos ni credenciales.
- Mantener contratos HTTP pequeños y claros. `/salud` ejecuta `SELECT 1`, devuelve 200 si PostgreSQL responde y 503 en caso contrario.
- Las transacciones y la concurrencia figuran como obligatorias en el PDF. La aclaración docente declara opcionales los temas no vistos y menciona transacciones como ejemplo; no extender esa excepción a concurrencia sin confirmación. Mantener la diferencia visible y, si se implementan, hacerlo de forma explícita, justificada y probada.

## Código y pruebas

- Favorecer código corto, legible y comprensible para estudiantes.
- Comentar decisiones o motivos; no describir línea por línea lo que el código ya expresa.
- No agregar funcionalidades simuladas, archivos vacíos ni estructuras anticipadas sin propósito.
- Los directorios reservados para etapas futuras deben contener un README que explique alcance y criterio de incorporación.
- Las pruebas de base van en `db/tests/` y deben incluir éxitos y rechazos esperados.
- Antes de cerrar una etapa, verificar configuración, arranque, healthchecks y el circuito real desde el front hasta PostgreSQL siempre que el entorno lo permita.
- Si una herramienta necesaria no está disponible, informar exactamente qué comprobación no pudo ejecutarse; no reemplazarla por una afirmación simulada.

## Flujo de trabajo con Git

- Trabajar en una rama por etapa creada desde `main`. No commitear directamente sobre `main`.
- Hacer commits frecuentes, pequeños y con mensajes descriptivos.
- Integrar cada etapa mediante un PR revisado por otro integrante antes del merge (revisión cruzada).
- Antes de cada commit, verificar que no se incluyan `.env`, secretos ni dumps con datos sensibles; un secreto commiteado queda en el historial aunque luego se borre.
- Los despliegues a la nube requieren instrucción explícita del usuario.

## Alcance de la etapa actual

Ya existen:
- la infraestructura PostgreSQL -> API -> front;
- el modelo (Etapa 1);
- la lógica de negocio en la base (Etapa 2: migraciones 003 a 007);
- la carga masiva reproducible (Etapa 3: `db/seed/`, servicio `seed` con perfil propio);
- los índices de rendimiento (Etapa 4: `008_indices.sql`, medición en `db/perf/`, informe en `docs/rendimiento.md`);
- las consultas de la Etapa 5, cerrada: S1-S12, U1-U6, I1-I6 y D1-D6 en `consultas/`, informe en `docs/consultas.md` y planes en `docs/consultas/planes/`;
- **la API REST completa (Etapa 6): catálogo y ABM de vinos, CRUD de clientes (3 subtipos), venta y consulta de comprobantes, circuitos de transferencias e ingresos, reportes de solo lectura (S1, S8, S6, S7) y trazabilidad como supuesto; 252 pruebas automatizadas en entorno aislado; ver `docs/api.md` y `docs/cierre_etapa6.md`.**
- **el front completo (Etapa 7): cinco pantallas (catálogo, alta y edición de vino, nueva venta, transferencias y tablero) en `front/`, con rutas `GET /catalogos/*` de sólo lectura en la API (261 pruebas de la API); 33 pruebas en `front/tests/` (25 de punta a punta con Playwright y 8 estáticas); ver `docs/front.md` y `docs/cierre_etapa7.md`.**

Una vez integradas en `main`, las migraciones no se modifican: cualquier corrección va en una migración nueva. La Etapa 6 agregó `009_ingreso_bodega.sql` (RN-16, issue #30) y `010_privilegios_trazabilidad.sql` (lectura de la producción de uva, issue #32). La próxima migración es `011`; sólo se crea con una necesidad justificada y aprobada. El alcance de la trazabilidad es un supuesto documentado en `docs/requisitos.md` (sección 3.8) hasta que responda la cátedra.

**La Etapa 6 (API REST) está completada y verificada.** El contrato definitivo está en `docs/api.md`, la organización del código en `api/README.md`, y el informe de cierre en `docs/cierre_etapa6.md`. Cada endpoint tiene su función de acceso a datos en `api/app/datos/` y su prueba en `api/tests/`. Las pantallas del front son de la Etapa 7.

**La Etapa 7 (front) está completada y verificada.** Plan, contrato pantalla por pantalla y estructura en `docs/front.md`; bocetos en `docs/bocetos/`; informe de cierre con los tres criterios de la consigna y su evidencia en `docs/cierre_etapa7.md`. Las reglas de la etapa siguen vigentes para cualquier cambio del front:
- Toda llamada HTTP pasa por `front/js/api.js`, con la URL base de `front/config.js`; las pantallas no usan `fetch` directamente.
- Los errores se muestran con el `detail` y el `codigo` que devuelve la API, sin reemplazarlos por mensajes genéricos.
- El front no suma porcentajes, no multiplica precio por cantidad, no aplica descuentos ni calcula stock: muestra lo que devuelve la base. Los botones habilitados según el estado son ayuda visual; la transición la decide PostgreSQL.
- Los selectores se alimentan de `GET /catalogos/*` (sólo lectura, sin migración nueva); clientes y vinos se cargan por código.
- Las pruebas de punta a punta corren en un proyecto de Compose aislado, nunca contra el entorno por defecto: `front/tests/ejecutar.sh`.
- Toda operación aritmética nueva en `front/js` se justifica en `front/tests/test_sin_calculos.py`; esa prueba falla si aparece una sin listar.

**La Etapa 8 (nube) está en curso: el plan, el código y las herramientas están integrados (#66, PR #72), pero el despliegue en Render NO se ejecutó** (issues #67 a #71 abiertos; ver `docs/cierre_etapa8.md`). El usuario la autorizó explícitamente el 10/11/2026 y eligió **Render** (plan gratis). Comparación de proveedores, diseño y requisitos R1–R14 en `docs/nube.md`; issues con la etiqueta `etapa-8` (#66 a #71). Reglas de la etapa:
- Cada paso que crea o modifica recursos en Render lo ejecuta el usuario desde su cuenta. Los agentes preparan código, scripts e instrucciones y nunca reciben ni escriben credenciales del administrador.
  - **Excepción, sólo el 10/11/2026 hasta las 23:59 (hora de Argentina):** Lucas autorizó a un agente a operar Render por su API con la clave de `db/nube/render.env` (`RENDER_API_KEY`, no versionado). Eso incluye leer por la API la contraseña del administrador y escribirla únicamente en `render.env`. **No se usó**: ese archivo no existía en la PC. La excepción vence a esa hora; si se usó, hay que revocar la clave de Render al terminar la entrega.
- Ningún secreto en el repositorio: ni contraseñas, ni URLs de conexión, ni hosts completos de la base en capturas, ni volcados. `render.yaml` declara los secretos como `sync: false`.
- El usuario administrador de Render sólo se usa para el bootstrap de roles. Las migraciones y la carga corren como propietario; la API, como `bodegas_api` con `sslmode=require`; las verificaciones de lectura, con el rol de reportes.
- La base queda sin acceso externo (lista de IPs vacía). Se abre sólo la IP de quien ejecuta (`/32`), durante el paso que lo necesita; cada apertura y cierre se anota en `docs/nube.md`.
- El entorno local no cambia: `DB_SSLMODE` y `CORS_ORIGINS` son opcionales y sus valores por omisión dejan todo como antes.

Convenciones de las consultas (Etapa 5):
- Se ejecutan con `docker compose exec db /opt/bodegas/consultas/ejecutar.sh <archivo>.sql` (propietario, `ON_ERROR_STOP=1`). Los `.sql` llegan a la imagen de `db` como contexto adicional: al cambiarlos, reconstruir con `docker compose up -d --build db`.
- Cada archivo define sus parámetros al comienzo (`\if :{?x} \else \set x … \endif`), con valores de la carga. Lo que depende de la historia simulada (tipos de cliente, stock, transferencias recientes) se elige con `\gset`: cambia con `FECHA_REFERENCIA`.
- Cada modificación está en su propio `BEGIN … ROLLBACK` e informa `:ROW_COUNT`. El archivo no deja cambios: se verifica con `db/seed/hashes.sql` antes y después.
- Las escrituras de stock, importes, estados y auditoría van por funciones y procedimientos (por ejemplo U1 usa `fn_recalcular_comprobante`), nunca por `UPDATE` directos.

Un índice nuevo se justifica con una consulta medida antes y después con `db/perf/medir.sh`, y su costo de escritura se considera, como en `docs/rendimiento.md`. Los experimentos que crean índices o cambian datos van dentro de `BEGIN … ROLLBACK` o en un proyecto de Compose aislado.

La carga masiva se conecta como propietario y deshabilita sólo los triggers que chocan con una historia, dentro de una única transacción. Cualquier cambio en el generador debe mantener la reproducibilidad (misma `SEMILLA`, `FECHA_REFERENCIA` y `ESCALA` producen las mismas huellas de `hashes.sql`) y hacer pasar `controles.sql` y `post_carga.sql`. Debe probarse con una carga completa desde un volumen vacío antes de integrarlo: el PR #22 se integró sin haber completado una carga (`docs/carga_masiva.md`, sección 11). No versionar datos generados ni volcados.

La API se prueba con `api/tests/ejecutar.sh`: proyecto de Compose aislado desde un volumen vacío, carga `ESCALA=0.1`, pytest con el rol de la API y `down -v`. Las pruebas no se corren contra el entorno por defecto, porque las que escriben modificarían sus datos. Los errores de PostgreSQL los traduce sólo `api/app/errores.py`; los endpoints no los capturan. Las operaciones de varias sentencias usan `with conn.transaction():` dentro del endpoint. Las versiones de `api/requirements*.txt` se fijan con `==`.

El front se prueba con `front/tests/ejecutar.sh`, con el mismo patrón: proyecto aislado (`bodegas_front_pruebas`) desde un volumen vacío, carga `ESCALA=0.1` y `down -v`. Usa Playwright para Python en la imagen oficial de Playwright (versión fija); el navegador corre dentro de la red, abre `http://front` y llama a `/api` por nginx. La base se verifica con el rol de reportes (sólo lectura): las escrituras de las pruebas pasan por el front y la API. Los datos de prueba se buscan con `SELECT`, nunca con ids fijos. Las versiones de `front/tests/requirements.txt` se fijan con `==`.

Las escrituras de stock, importes, estados y auditoría pertenecen a triggers y procedimientos. Una etapa posterior no debe otorgar a la API privilegios directos sobre esas columnas ni duplicar esos cálculos fuera de PostgreSQL.

Actualizar `README.md` y `docs/requisitos.md` cuando una decisión cambie el modo de ejecutar el proyecto, el alcance académico o una alternativa de diseño.
