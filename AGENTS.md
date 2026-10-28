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

La infraestructura PostgreSQL -> API -> front, el modelo (Etapa 1), la lógica de negocio en la base (Etapa 2: migraciones 003 a 007) y la carga masiva reproducible (Etapa 3: `db/seed/`, servicio `seed` con perfil propio) ya existen. `001` a `007` están en `main`: cualquier corrección va en una migración nueva. No implementar todavía CRUD en la API, índices de rendimiento (`008_indices.sql`, Etapa 4), consultas de la Etapa 5 ni pantallas nuevas.

La carga masiva se conecta como propietario y deshabilita sólo los triggers que chocan con una historia, dentro de una única transacción. Cualquier cambio en el generador debe mantener la reproducibilidad (misma `SEMILLA`, `FECHA_REFERENCIA` y `ESCALA` producen las mismas huellas de `hashes.sql`) y hacer pasar `controles.sql`. No versionar datos generados ni volcados.

Las escrituras de stock, importes, estados y auditoría pertenecen a triggers y procedimientos. Una etapa posterior no debe otorgar a la API privilegios directos sobre esas columnas ni duplicar esos cálculos fuera de PostgreSQL.

Actualizar `README.md` y `docs/requisitos.md` cuando una decisión cambie el modo de ejecutar el proyecto, el alcance académico o una alternativa de diseño.
