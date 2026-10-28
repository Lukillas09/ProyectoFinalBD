# Requisitos y trazabilidad académica

## 1. Alcance de este documento

Este documento separa cuatro cosas que no deben confundirse:

- los requisitos completos del PDF del Trabajo Práctico Integrador;
- los conceptos que los respaldan en el material teórico;
- la aclaración posterior del profesor sobre temas aún no vistos;
  - el alcance incremental de cada etapa implementada.

La infraestructura inicial conecta PostgreSQL 16 -> FastAPI -> front. La Etapa 1 agregó el modelo conceptual y relacional, la normalización, el diccionario y el esquema físico con constraints. La Etapa 2 agrega la lógica de negocio dentro de la base: funciones, procedimientos, triggers, vistas y roles con privilegios mínimos (secciones 9 y `docs/trazabilidad.md`). La Etapa 3 agrega la carga masiva reproducible (sección 10 y `docs/carga_masiva.md`). Todavía no se implementan el CRUD de la API, índices de rendimiento, consultas de la Etapa 5 ni pantallas nuevas.

## 2. Fuentes revisadas

Se pudieron abrir y leer los 16 PDF de `material/` (214 páginas en total). Ninguno está cifrado ni dañado. Las páginas 10 a 12 del material de modelo E-R extendido no tienen capa de texto; se revisaron visualmente y muestran ejemplos de jerarquía total exclusiva, total con solapamiento y parcial con solapamiento.

| Fuente | Aporte principal al proyecto |
|---|---|
| `TPI_Bodegas_del_Atuel.pdf` | Escenario, RN-01 a RN-15, entidades mínimas, nueve etapas, mínimos cuantitativos, consultas, rúbrica y estructura de entrega. |
| `Programa BD 2026.pdf` | Contenidos curriculares: SGBD, MER/ERE, modelo relacional, normalización, integridad, SQL, transacciones, índices, vistas y seguridad. |
| `BASE-DE-DATOS.pdf` | Persistencia, integridad, consistencia, seguridad, concurrencia y arquitectura cliente-servidor de tres capas. |
| `BD - MODELO CONCEPTUAL 2026.pdf` | Entidades fuertes y débiles, atributos, dominios, relaciones, cardinalidad y tipos de clave. |
| `Modelo-Entidad-Relacion-Extendido-Modelando-la-Complejidad-Real.pdf` | Especialización, generalización, herencia, totalidad/parcialidad y exclusividad/solapamiento. |
| `BD - MODELO RELACIONAL.pdf` | Paso de MER a relaciones, entidad débil, atributos compuestos y multivaluados, N:M y alternativas de mapeo de jerarquías. |
| `Normalización de BD.pdf` | Dependencias funcionales, parciales y transitivas; objetivos de 1FN, 2FN y 3FN. |
| `Metodologia Normalizacion hasta 3FN.pdf` | Método ordenado: atomicidad, claves candidatas, atributos primos, dependencias, descomposición y claves resultantes. |
| `Reglas de integridad.pdf` | Integridad de entidad, referencial, de dominio y de usuario; PK, UNIQUE, FK, CHECK, NOT NULL, DEFAULT y acciones referenciales. |
| `Lenguajes BD (1).pdf` | DDL y DML, creación y modificación de objetos y administración básica. |
| `JOIN,GROUP BY, HAVING, SUBCONSULTAS (1).pdf` | Joins, agrupaciones, conjuntos y subconsultas escalares, correlacionadas, de existencia y cuantificadas. |
| `Funciones, Procedimientos y Triggers.pdf` | Funciones, procedimientos, triggers, automatización, integridad y auditoría en PostgreSQL. |
| `Introduccion a vistas PostgreSQL (1).pdf` | Vistas estándar y materializadas, simplificación, seguridad y necesidad de refresco. |
| `Indices-en-PostgreSQL.pdf` | Costos y beneficios de índices, selectividad, índices parciales/compuestos y B-tree, Hash, GiST, GIN y BRIN. |
| `Bases de Datos - Esquemas, Roles y Permisos.pdf` | Esquemas, roles, granularidad de permisos y principio de menor privilegio. |
| `Roles de usuarios - SQL.pdf` | `CREATE ROLE`, `GRANT`, `REVOKE`, pertenencia, modificación y eliminación de roles. |

### Cautelas detectadas en el material

Los apuntes son una guía docente, pero algunos ejemplos tienen simplificaciones o inconsistencias que no deben copiarse sin análisis:

- El ejemplo de 3FN de `Normalización de BD.pdf` alterna las dependencias entre ciudad y código postal y repite una dependencia como directa y transitiva. Para Bodegas del Atuel se derivarán las dependencias funcionales desde el dominio y las claves candidatas reales.
- El material de vistas sugiere una mejora de rendimiento para vistas en general. En PostgreSQL una vista estándar no materializa ni cachea resultados por sí misma; una mejora deberá demostrarse y, si corresponde, asociarse a una vista materializada, índices o una consulta mejor planteada.
- El material de funciones y triggers contiene ejemplos con erratas y afirmaciones simplificadas. La sintaxis se validará contra PostgreSQL 16 y mediante pruebas ejecutables.
- El material conceptual a veces describe la cardinalidad máxima sin separar claramente la participación mínima. El DER del proyecto deberá expresar ambos límites en cada extremo.
- El mismo material primero presenta un atributo en una relación como señal de una entidad faltante y luego admite atributos descriptivos en relaciones. Para composición, renglones y demás asociaciones con datos propios se justificará explícitamente si corresponde una relación asociativa y cómo se transforma en tabla.
- En PostgreSQL 16, un `UNIQUE` admite varios valores `NULL` por defecto y un `CHECK` no rechaza el resultado lógico desconocido. Cuando el atributo sea obligatorio se combinará la regla con `NOT NULL`; si los nulos deben considerarse iguales se evaluará `NULLS NOT DISTINCT`.
- `RESTRICT` y `NO ACTION` no son intercambiables en todos los casos: una comprobación `NO ACTION` sólo puede diferirse si la restricción fue declarada diferible y se difiere efectivamente.
- Los ejemplos que usan `SERIAL` son válidos, pero se compararán con `GENERATED ... AS IDENTITY`, disponible y más explícito en PostgreSQL 16.

Las tres últimas precisiones son validaciones técnicas externas al material de cátedra, contrastadas con el [manual de constraints de PostgreSQL 16](https://www.postgresql.org/docs/16/ddl-constraints.html) y el [manual de columnas identity](https://www.postgresql.org/docs/16/ddl-identity-columns.html); no se atribuyen a los PDF.

## 3. Requisitos completos de la consigna

### 3.1 Tecnologías y arquitectura

- PostgreSQL 14 o superior en el PDF; este proyecto fija PostgreSQL 16.
- SQL directo mediante driver nativo. ORM y query builders que oculten SQL están prohibidos.
- API REST JSON documentada con OpenAPI/Swagger o colección Postman.
- Front que consuma únicamente la API.
- Docker y Docker Compose; un solo comando debe levantar base, API y front.
- Git en GitHub o GitLab, con participación de todos los integrantes.
- Trabajo grupal de tres a cuatro integrantes, con roles de Datos, API, Front/Integración e Infraestructura que rotan por etapa. El rol organiza, pero todos deben poder explicar y modificar cualquier parte en vivo durante la defensa.
- Se recomienda una rama por etapa y revisión cruzada antes de integrar.
- Datos masivos reproducibles mediante Python, Faker/random o equivalente, con semilla fija y catálogos reales.
- Secretos fuera del repositorio y rol de API distinto del propietario.
- Totales, descuentos y stock resueltos en PostgreSQL, no en API ni front.
- No se exige diseño visual sofisticado ni autenticación compleja; la autenticación es un extra opcional.

Decisiones fijadas adicionalmente para este proyecto: Python + FastAPI, Psycopg 3 con pool, HTML/CSS/JavaScript y PostgreSQL 16.

### 3.2 Modelado y normalización

El modelo implementado incluye, como mínimo: localidad, sala de venta, empleado, finca, parcela débil, cepa, lote de uva, análisis de calidad, bodega, vino, composición vino-cepa, maridaje, vino-maridaje, cliente y sus tres subtipos, permiso de exportación, comprobante y renglón, transportista y cobertura, ingreso y renglón, transferencia y renglón, stock por sala, stock del depósito y auditoría de precio. También separa `departamento` para evitar repetir su provincia y agrega sólo la relación técnica `schema_migration`.

Los atributos e identificadores siguientes son la guía mínima del PDF. Las claves candidatas y decisiones finales están desarrolladas en `modelo_conceptual.md`, `modelo_relacional.md` y `normalizacion.md`:

| Entidad o relación | Identificador/atributos guía |
|---|---|
| Localidad | Código postal; nombre, provincia y encargado regional. |
| Sala de venta | ID; calle, número, día de cierre y localidad. |
| Empleado | CUIT; nombre, fecha de ingreso, salario y sala. |
| Finca | ID; nombre, superficie, departamento y provincia. |
| Parcela | Clave débil `(finca, nro_parcela)`; superficie, año de plantación y cepa. |
| Cepa | ID; nombre y tipo tinta/blanca. |
| Lote de uva | Número de lote; parcela, campaña, fecha, kg y bodega destino; una cosecha por parcela/campaña. |
| Análisis de calidad | ID; lote, fecha, Brix, pH y acidez total. |
| Bodega | CUIT; razón social y domicilio. |
| Vino | Código; nombre, tipo, añada, volumen, graduación, precio y bodega. |
| Composición | Clave vino-cepa y porcentaje; N:M con atributo y suma 100 % por vino. |
| Maridaje / vino-maridaje | Maridaje: ID, nombre y temperatura; asociación N:M identificada por vino-maridaje. |
| Cliente | ID; nombre/razón social, tipo y número de documento, dirección, localidad, alta y descuento; supertipo de tres subtipos. |
| Socio, distribuidor y exportador | Datos propios; distribuidor con zona/habilitación y exportador con país principal. |
| Permiso de exportación | Código y exportador; emisión y vencimiento. |
| Comprobante | Número; fecha, cliente, sala, subtotal, descuento y total. |
| Renglón de comprobante | Clave `(comprobante, vino)`; cantidad, precio unitario, descuento y subtotal. |
| Transportista / cobertura | Código, razón social, CUIT, email, teléfono y domicilio; cobertura N:M con localidad. |
| Ingreso / renglón | Código, fecha, estado, transportista y bodega; renglón con vino y cantidad. |
| Transferencia / renglón | Número, sala, fecha y estado; renglón con vino y cantidad. |
| Stock de sala | Clave `(sala, vino)` y cantidad no negativa. |
| Stock de depósito | Vino y cantidad no negativa para un único depósito central. |
| Auditoría de precio | ID; vino, precios anterior/nuevo, fecha-hora y usuario. |

La entrega de modelado exige:

- DER en imagen o PDF y su archivo fuente, con entidades, atributos, identificadores y cardinalidades mínima/máxima;
- representación de la entidad débil `Parcela`, la jerarquía de clientes y las relaciones N:M con atributos;
- esquema relacional con PK y FK;
- claves naturales frente a subrogadas justificadas caso por caso;
- dependencias funcionales relevantes y demostración de 1FN, 2FN y 3FN;
- diccionario de datos coherente con el DDL que indique, para cada tabla y columna, tipo, nulabilidad, restricciones y descripción;
- decisiones sobre atributos derivados y acciones `ON DELETE`/`ON UPDATE`;
- DDL reproducible desde una base vacía, comenzando por `db/migrations/001_esquema.sql`.

### 3.3 Reglas de negocio mínimas

Las quince reglas del PDF deben conservar trazabilidad hacia un mecanismo PostgreSQL y una prueba:

| Regla | Resumen | Mecanismo orientativo del PDF |
|---|---|---|
| RN-01 | Precio único en la red y positivo. | Atributo en vino + `CHECK`. |
| RN-02 | Sala en una localidad; un encargado regional por localidad. | FK + diseño en 3FN. |
| RN-03 | Empleado en una sola sala. | FK `NOT NULL`. |
| RN-04 | Una cepa por parcela y una cosecha máxima por campaña. | FK + `UNIQUE`. |
| RN-05 | El corte de un vino suma 100 %. | Constraint trigger diferido. |
| RN-06 | Descuento según tipo de cliente. | Función + `CHECK`. |
| RN-07 | Permisos múltiples del exportador y vencimiento posterior. | Tabla + `CHECK` entre columnas. |
| RN-08 | Total derivado de renglones y descuento. | Función + trigger. |
| RN-09 | Venta limitada por stock de sala; stock no negativo. | Trigger + `CHECK`. |
| RN-10 | Ingreso: flujo de estados sin retroceso e impacto único. | `ENUM` + trigger + procedimiento. |
| RN-11 | Transferencia: mismo flujo; fecha actual inmutable. | Triggers + procedimiento. |
| RN-12 | Documento no editable fuera de confección. | Trigger en renglones. |
| RN-13 | Todo cambio de precio queda auditado. | Trigger `AFTER UPDATE`. |
| RN-14 | No borrar vino, bodega o transportista con movimientos. | FK `ON DELETE RESTRICT`. |
| RN-15 | Cantidades, superficies, kilos y precios positivos; graduación 5 a 20. | `CHECK`. |

### 3.4 Mínimos cuantitativos de integridad y lógica

- PK en todas las tablas y FK en todas las relaciones, con acciones referenciales justificadas.
- `NOT NULL` en atributos obligatorios.
- Cuatro `UNIQUE` adicionales a las PK.
- Ocho `CHECK`, incluido al menos uno entre columnas.
- Tres `DEFAULT`.
- Un `ENUM` y un `DOMAIN`.
- Cuatro funciones: total de comprobante, stock de sala, descuento de cliente y antigüedad.
- Dos procedimientos para procesar ingresos y transferencias.
- Seis triggers con propósitos distintos, incluidos `BEFORE`, `AFTER` y constraint trigger diferido.
- Tres vistas, una opcionalmente materializada.
- Tres roles: propietario, API lectura/escritura y reportes de solo lectura.
- Al menos un caso de prueba por cada RN-01 a RN-15.
- Migraciones esperadas por el PDF: `001_esquema.sql`, `002_constraints.sql`, `003_funciones.sql`, `004_procedimientos.sql`, `005_triggers.sql`, `006_vistas.sql`, `007_roles.sql` y `008_indices.sql`.
- Cada función debe comentar propósito, parámetros y volatilidad; cada trigger debe citar la RN que protege. Las pruebas negativas deben indicar el error esperado.
- La etapa 2 entrega la tabla `regla -> mecanismo -> caso de prueba` y una demostración documentada con dos sesiones. Las transacciones quedan sujetas a la aclaración de la sección 4; concurrencia sigue siendo requisito del PDF salvo confirmación adicional de la cátedra.

### 3.5 Carga masiva

Todas las tablas deben tener al menos una fila, tres deben superar 10.000 filas y una debe superar 100.000. Volúmenes orientativos del PDF:

| Grupo de tablas | Filas recomendadas |
|---|---:|
| Localidad, cepa, maridaje, bodega, transportista y cobertura | 10 a 60, con catálogos reales |
| Sala, finca y empleado | 15 a 150 |
| Parcela, vino, composición, vino-maridaje y stock de depósito | 300 a 1.000 |
| Ingreso, transferencia y stock de sala | 500 a 5.000 |
| Renglones de ingreso/transferencia, lote y análisis | 3.000 a 15.000 |
| Cliente | 20.000 |
| Comprobante | 150.000 |
| Renglón de comprobante | 500.000 o más |

Los CSV deben contener catálogos reales de cepas, maridajes, departamentos/localidades de Mendoza y tipos de vino; no deben generarse al azar. El Anexo B sugiere campañas de los últimos cinco años y cosechas entre febrero y abril; se toma como referencia, no como obligación textual. El orden de carga según FK debe diagramarse.

El script futuro usará Python, Psycopg, `random` y Faker o equivalente con semilla fija; generará fechas, composiciones, importes y stock coherentes. Debe documentar cómo trata los triggers históricos y sus riesgos, comparar carga fila a fila contra lotes o `COPY`, y medir tiempos. Los controles incluyen conteos, huérfanos, stock negativo y comprobantes cuyo total no coincide con sus renglones. Se entrega `db/seed/`, reporte de resultados y `dump_completo.sql.gz` o instrucciones para generarlo.

### 3.6 Índices y rendimiento

- Crear al menos cinco índices propios en `008_indices.sql`: uno compuesto, uno parcial, uno sobre FK y uno de otro tipo o variante —expresión, BRIN o `INCLUDE`—, todos justificados.
- Medir al menos tres consultas candidatas con `EXPLAIN (ANALYZE, BUFFERS)` antes y después, ejecutando `ANALYZE`; la línea base conserva únicamente los índices creados por PK y `UNIQUE`. Los planes completos quedan como anexo.
- Comparar tiempos, tipo de recorrido y filas leídas; justificar el orden de un índice compuesto.
- Documentar un índice evaluado y descartado, un caso donde el planificador no usa un índice existente y el costo de escritura, cronometrando la carga de una tabla grande con y sin esos índices.

### 3.7 Consultas SQL requeridas

Se entregan `consultas/update.sql`, `insert.sql`, `delete.sql` y `select.sql`. Cada consigna lleva código, enunciado, SQL comentado, estrategia y valores concretos del dataset. Los períodos relativos se calculan desde `CURRENT_DATE`. Cada modificación debe documentar los triggers o constraints que activa o viola, además de `BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK` y cantidad de filas afectadas; este protocolo queda alcanzado por la aclaración sobre transacciones de la sección 4.

| Código | Requisito |
|---|---|
| U1 | Recalcular todos los totales de comprobantes aplicando el descuento del tipo de cliente. |
| U2 | Aumentar 20 % el salario de empleados con más de cinco años de antigüedad. |
| U3 | Aumentar 13 % el precio de vinos de una bodega elegida. |
| U4 | Intercambiar lunes y miércoles como día de cierre, en una sola sentencia. |
| U5 | Aplicar 15 % de rebaja a los diez vinos menos vendidos de la red. |
| U6 | Elevar a 35 % el descuento de exportadores con más de tres permisos. |
| I1 | Vincular General Alvear con el transportista que realizó menos envíos —ingresos trasladados— en el último trimestre. |
| I2 | Si existe un tinto de al menos 14°, crear `cordero al disco` y asociarlo a todos los que cumplen. |
| I3 | Crear comprobante con tres renglones, cliente dado y sala 1, dentro de una transacción y usando funciones de cálculo. |
| I4 | Insertar una bodega. |
| I5 | Insertar una sala de venta. |
| I6 | Crear ingreso en confección de 120 botellas de un vino, bodega y transportista dados. |
| D1 | Borrar comprobantes de más de cinco años de socios. |
| D2 | Eliminar cepas que no componen vinos ni están plantadas. |
| D3 | Eliminar empleados con menos de dos años de una sala dada de baja. |
| D4 | Borrar socios sin compras dados de alta hace más de cinco años. |
| D5 | Eliminar ingresos procesados de más de 365 días. |
| D6 | Borrar socios sin compras de una localidad específica. |
| S1 | Ranking de los diez vinos con más botellas vendidas. |
| S2 | Vinos vendidos en todas las salas, mediante división relacional. |
| S3 | Cantidad de clientes de cada tipo que compraron en una sala durante la última semana. |
| S4 | Cinco salas que más solicitaron un vino en transferencias de los últimos quince días. |
| S5 | Salas con menor cantidad de transferencias pendientes. |
| S6 | Para una sala, vinos sin stock local pero disponibles en depósito. |
| S7 | Transportista con mayor actividad en el último mes. |
| S8 | Ventas por sala del último trimestre, en orden descendente. |
| S9 | Ficha de vino con corte, bodega, maridajes y stock total, usando joins, agregación y vista. |
| S10 | Rendimiento kg/ha por parcela/campaña y parcelas bajo el promedio de su finca, con CTE y subconsulta correlacionada. |
| S11 | Ranking de vinos dentro de cada sala por botellas vendidas y ventas acumuladas mensuales por sala, con `RANK()` particionado y suma de ventana. |
| S12 | Clientes que compraron todos los vinos de una bodega y quienes nunca compraron tintos, con `NOT EXISTS` y anti-join. |

Las consultas candidatas de rendimiento y S9-S12 también requieren `EXPLAIN (ANALYZE)`.

### 3.8 API REST completa

La etapa final de API exige driver nativo, SQL parametrizado, una capa de acceso con una función por consulta, pool, paginación y filtros del catálogo por tipo, cepa, bodega y añada. Las operaciones de varias sentencias usan transacciones explícitas según la aclaración de la sección 4. OpenAPI/Swagger o Postman debe coincidir con las rutas reales.

| Recurso | Métodos y rutas mínimas |
|---|---|
| Vinos | `GET /vinos`, `GET /vinos/{cod}`, `POST /vinos`, `PUT /vinos/{cod}`, `DELETE /vinos/{cod}`; detalle con corte y maridajes. |
| Clientes | CRUD `GET`, `POST`, `PUT`, `DELETE` sobre `/clientes`, contemplando tres subtipos. |
| Comprobantes | `POST /comprobantes`, `GET /comprobantes/{nro}`; venta completa sin datos parciales. |
| Transferencias | `POST /transferencias`, `POST /transferencias/{nro}/renglones`, `/terminar` y `/procesar`. |
| Ingresos | `POST /ingresos`, `POST /ingresos/{cod}/renglones` y `/procesar`. |
| Reportes | `GET /reportes/top-vinos`, `/ventas-por-sala`, `/vinos-sin-stock`, `/transportista-activo`, `/trazabilidad/{cod}`. |
| Salud | `GET /salud`, con comprobación real de acceso a PostgreSQL. |

Traducción sugerida del PDF: `23505 -> 409`; `23503 -> 409 o 422`; `23514` y `23502 -> 422`; `P0001 -> 409` con mensaje de regla; `22P02 -> 400`; `40001` y `40P01 -> 503` sugiriendo reintento. Deben existir al menos ocho pruebas automáticas, tres que violen reglas. También se documenta un intento de inyección tratado como texto por la parametrización. Vender sin stock debe devolver 409 claro y no dejar cambios parciales.

### 3.9 Front, nube, documentación y evaluación

El front final tiene cinco pantallas mínimas:

- catálogo paginado con filtros por tipo, cepa, bodega y añada, y detalle con composición/maridajes;
- alta/edición de vino con composición y error si no suma 100 %;
- venta con cliente, sala, vinos, total de backend y error de stock;
- transferencias con renglones y botones habilitados según estado;
- tablero con top diez, ventas trimestrales por sala en gráfico y vinos sin stock en una sala.

Antes de implementarlas deben realizarse bocetos simples de las cinco pantallas. El front debe centralizar llamadas a la API, usar URL base configurable, mostrar los mensajes reales de las reglas y no calcular importes ni stock.

La nube exige comparar dos proveedores, justificar uno, crear propietario/API/reportes, aplicar migraciones en orden, HTTPS, conexión PostgreSQL cifrada, puerto restringido, secretos externos, CORS limitado al origen público, rechazo comprobado de una conexión no autorizada y backup/restauración con conteos. Si el plan limita espacio, se acepta carga reducida con al menos 10.000 filas en una tabla, manteniendo el volumen local. Debe repetirse en nube una regla ejecutada por trigger.

La entrega final incluye README reproducible, URL pública, informe, trazabilidad, demo de 10 a 15 minutos sobre la versión en nube y defensa individual. La demo debe recorrer una venta, mostrar su rechazo por falta de stock, procesar una transferencia y exhibir una consulta con su plan de ejecución. El informe sigue: alcance; modelo/3FN/diccionario; integridad/lógica/concurrencia; carga; índices; consultas; API/front e inyección fallida; nube/seguridad/backup; conclusiones. El PDF menciona un Anexo C de preguntas, pero el archivo disponible termina en la página 29 con el Anexo B.

La rúbrica suma 100 puntos y la capa de datos representa 70 %:

| Criterio | Puntos |
|---|---:|
| Modelado | 15 |
| Constraints | 8 |
| Funciones, procedimientos, triggers y transacciones | 17 |
| Carga masiva | 8 |
| Índices y rendimiento | 10 |
| Consultas SQL | 12 |
| API | 10 |
| Front | 5 |
| Nube y seguridad | 10 |
| Documentación, Git y demo | 5 |

Descuentan puntos: ORM/generadores que oculten SQL, secretos incluso en el historial, base no reproducible desde cero, API conectada como propietario/superusuario, cálculos de totales/descuentos/stock fuera de PostgreSQL e historial Git de una sola persona. La nota grupal se pondera por defensa individual, pero el coeficiente o mecanismo figura pendiente de definición en el PDF.

## 4. Diferencia entre el PDF y la aclaración docente

La aclaración recibida indica que los temas no vistos, como transacciones, son opcionales. Esto modifica la obligatoriedad académica, pero no borra lo escrito en la consigna.

El PDF presenta transacciones y concurrencia como obligatorias en varios lugares:

- objetivo de aprendizaje de manejo de transacciones y concurrencia;
- dos procedimientos "transaccionales" y una demostración de dos sesiones en la etapa 2;
- aceptación de que una transferencia fallida no deje cambios parciales;
- pruebas de modificaciones dentro de `BEGIN`/`ROLLBACK` en la etapa 5;
- manejo explícito de transacciones y venta completa en una transacción en la API;
- rúbrica de funciones, procedimientos, triggers y transacciones;
- ejemplo de concurrencia con `SELECT ... FOR UPDATE` en el anexo;
- inclusión de transacciones y acceso concurrente en `Programa BD 2026.pdf`.

Decisión actual: las transacciones siguen clasificadas como tema no visto y opcional según la aclaración, pero **se implementan igual desde la Etapa 2**, porque la rúbrica las puntúa y porque reglas de la consigna dependen de ellas. Por ejemplo, una transferencia sin stock no debe dejar cambios a medias. Los procedimientos no hacen `COMMIT` y se ejecutan dentro de la transacción de quien los llama; las reglas diferidas se verifican al confirmar. La concurrencia sigue tratándose como requisito del PDF y se demuestra con dos sesiones en `docs/concurrencia.md` (escenarios con y sin `FOR UPDATE`, y `REPEATABLE READ`).

## 5. Infraestructura base implementada

| Requisito | Resolución de esta etapa |
|---|---|
| Estructura solicitada | Directorios reales; los reservados para etapas futuras llevan README explicativo, no archivos vacíos. |
| PostgreSQL 16 persistente | Imagen `postgres:16-alpine` y volumen nombrado. |
| Un solo comando levanta base, API y front | `docker compose up` arranca `db`, ejecuta la tarea única `migrate` y recién después `api` y `front`. |
| Healthchecks | PostgreSQL con `pg_isready`, API llamando `/salud` y front comprobando Nginx. |
| Propietario separado de API | Bootstrap crea cuenta de inicialización, propietario del proyecto, cuenta de la API y cuenta de reportes, más los grupos `bodegas_rw` y `bodegas_ro`. |
| API sin DDL ni superusuario | `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, sin `CREATE` en base o esquema. |
| Credenciales externas | `.env.example` sólo contiene valores de ejemplo; `.env` queda ignorado. |
| `GET /salud` real | Adquiere una conexión del pool y ejecuta `SELECT 1`; 200/503 sin detalles internos. |
| Estado visible en navegador | El front consulta `/api/salud` y muestra éxito o indisponibilidad. |
| Sin nombres internos en el navegador | Nginx recibe `/api/*` y lo reenvía a `api:8000` dentro de Docker. |
| Documentación operativa | README con configuración, arranque, verificación, parada y borrado explícito del volumen. |
| Separación por etapas | El bootstrap sólo crea roles y esquema; las migraciones las aplica el servicio `migrate` como propietario, en un contenedor aparte que sólo recibe las credenciales del propietario. La lógica de negocio está en las migraciones 003 a 007; el CRUD de la API y la carga masiva siguen pendientes. |
| Flujo Git | Según `AGENTS.md`: una rama por etapa creada desde `main` (esta etapa: `etapa-1-modelado`), commits pequeños y descriptivos, sin `.env` ni secretos, e integración por PR revisado por otro integrante antes del merge. No se commitea directamente sobre `main`. Los despliegues a la nube requieren instrucción explícita. |

El rol de reportes de solo lectura existe desde la Etapa 2: la cuenta `DB_REPORT_USER` hereda `bodegas_ro`, que sólo lee tablas de negocio y vistas.

## 6. Ambigüedades resueltas y supuestos revisables del modelo

Las ambigüedades se resolvieron de forma conservadora para poder avanzar. No se presentan como texto explícito de la consigna:

1. **Localidad:** ID subrogado y candidata `(provincia, nombre, codigo_postal)`; ni nombre ni CP son únicos por separado.
2. **Encargado regional:** atributo obligatorio de localidad. No se inventa relación laboral con empleado ni entidad sin identificador; se revisará si la cátedra aporta datos propios.
3. **Departamento:** catálogo separado para finca; localidad conserva la provincia pedida y no recibe un departamento no exigido.
4. **Lote:** se supone número global y se agrega candidata `(finca, parcela, campaña)`.
5. **Vino:** candidata `(bodega, nombre, añada, volumen)` para permitir igual nombre comercial en elaboradoras diferentes.
6. **Clientes:** supertipo más subtipos, jerarquía conceptual total/exclusiva. La exclusividad se protege de forma declarativa con discriminador constante y FK compuesta `(id_cliente, tipo)`; la totalidad queda para un constraint trigger diferido en la Etapa 2.
7. **Documento:** candidata `(tipo_documento, nro_documento)`; no se cierra un catálogo de tipos no definido.
8. **Descuento:** base calculable por tipo; excepción nullable de 35 % sólo para exportador. La condición “más de tres permisos” requiere lógica posterior.
9. **Comprobante:** número global generado; subtotal de cabecera bruto, descuento monetario y total neto. Es un supuesto revisable si aparecen serie/punto de venta.
10. **Permiso:** código global natural como supuesto revisable.
11. **Depósito:** singleton implícito mediante una fila por vino, sin tabla sin atributos.
12. **Tiempo:** eventos operativos/auditoría con `TIMESTAMPTZ`; conceptos por día con `DATE`.
13. **Trazabilidad:** no se inventa una relación lote-vino; necesitaría una extensión explícita de elaboración.
14. **Borrados históricos:** D1/D5 eliminan cabecera y renglones; no revierten stock porque son depuración histórica, no anulación operativa.
15. **Permisos API:** desde la Etapa 2, `bodegas_rw` recibe exactamente lo que necesitan los endpoints de la Etapa 6. No tiene DML sobre stock, auditoría, importes ni estados: esos cambios ocurren sólo por triggers y procedimientos `SECURITY DEFINER` (`007_roles.sql`).
16. **Temas no vistos:** las transacciones se implementan aunque sean opcionales (sección 4). Sigue pendiente confirmar con la cátedra si concurrencia también queda exceptuada; mientras tanto se trata como obligatoria.
17. **Ubicación de pruebas:** se adopta `db/tests/`.
18. **Anexo C ausente:** sigue pendiente solicitar las preguntas de defensa mencionadas pero no incluidas en el PDF.

La temperatura de servicio no queda pendiente: el PDF la asigna al catálogo `Maridaje`; `Vino-maridaje` sólo vincula ambos. Moverla a la asociación sería una alternativa deliberada que deberá explicitar que se aparta de la guía.

## 7. Decisiones de infraestructura ya tomadas

- El navegador entra por el front en `localhost:8080`; JavaScript usa una ruta relativa del mismo origen.
- Nginx traduce `/api/salud` a `http://api:8000/salud` dentro de la red de Compose.
- La API también se publica en `localhost:8000` para `/salud` y `/docs` durante desarrollo.
- PostgreSQL no publica el puerto 5432 al host en esta etapa; se accede desde la red interna o con `docker compose exec`.
- El bootstrap crea un esquema vacío `bodegas`, propiedad del rol del proyecto. Las tablas aparecen cuando el servicio `migrate` ejecuta `db/migrate.sh` como propietario. Ese servicio depende de `db` saludable, y `api` depende de que `migrate` termine con código 0, de modo que la API nunca arranca contra un esquema a medio crear.
- `db/migrate.sh` aplica archivos numerados, falla con `ON_ERROR_STOP`, usa una transacción por archivo, registra SHA-256, omite reaplicaciones idénticas y rechaza cambios en archivos ya registrados.
- La API no recibe privilegios por la mera existencia de las tablas: `007_roles.sql` los otorga por objeto y por columna al grupo `bodegas_rw`, y `003_privilegios_api.sql` compara la matriz efectiva contra la esperada.
- Los scripts de inicialización de PostgreSQL sólo corren con un volumen vacío; cualquier cambio de roles debe hacerse mediante una migración administrativa o una reinicialización explícita y consciente del volumen.

## 8. Estado de la etapa de modelado y esquema inicial

### 8.1 Entregables implementados

- DER Mermaid editable, entidades, atributos, identificadores y cardinalidades en `docs/modelo_conceptual.md`; fuente `.mmd` e imágenes PNG en `docs/der/`.
- Relaciones, PK, candidatas, FK, jerarquía y acciones referenciales en `docs/modelo_relacional.md`.
- Metodología de 1FN/2FN/3FN y desnormalizaciones declaradas en `docs/normalizacion.md`.
- Diccionario en `docs/diccionario_datos.md`, contrastado contra el catálogo de PostgreSQL: coinciden tablas, columnas, tipos, nulabilidad, defaults y el nombre de cada constraint en las columnas que abarca.
- `001_esquema.sql`: dos tipos `ENUM`, un `DOMAIN` con su `CHECK`, 30 tablas de negocio, una tabla técnica, 31 PK, 35 FK, `NOT NULL` y la superclave `uq_cliente_id_tipo` que necesitan las FK de subtipos.
- `002_constraints.sql`: 10 `UNIQUE` (claves candidatas), 35 `CHECK` (34 de negocio y 1 de la tabla técnica) y 16 columnas con `DEFAULT`.
- Totales del esquema, consultados en `pg_constraint` y `pg_attrdef`: 31 PK, 35 FK, 11 `UNIQUE`, 36 `CHECK` contando el dominio y 16 `DEFAULT` al cerrar la Etapa 1 (17 desde la Etapa 2, por `comprobante.xact_alta`). Superan los mínimos del PDF: 4 `UNIQUE`, 8 `CHECK` y 3 `DEFAULT`.
- Servicio `migrate` que aplica las migraciones en cada `docker compose up`, y pruebas SQL aisladas con `ROLLBACK` ejecutables con `db/tests/run_all.sh`.

### 8.2 Cobertura de RN después de la Etapa 2

La columna "Etapa 1" registra lo que ya protegía el esquema; "Etapa 2" agrega la lógica. El detalle de objetos y casos de prueba está en `docs/trazabilidad.md`.

| Regla | Etapa 1 (estructura) | Etapa 2 (lógica) | Pendiente |
|---|---|---|---|
| RN-01 | Precio único en `vino` y `CHECK > 0` | Auditoría de cambios (RN-13) | — |
| RN-02 | FK sala-localidad; encargado una vez en localidad | — | Mínimo de salas por localidad: no lo exige la consigna. |
| RN-03 | FK `NOT NULL` de empleado a una sala | — | Mínimo de empleados por sala: no lo exige una RN. |
| RN-04 | FK de cepa en parcela; `UNIQUE (parcela, campaña)` | — | — |
| RN-05 | Porcentaje `(0,100]` | Suma exactamente 100 y al menos una cepa: constraint trigger diferido | — |
| RN-06 | ENUM de tipo; excepción sólo 35/exportador; subtipo exclusivo | `fn_descuento_cliente`; descuento copiado al renglón; U6 exige más de 3 permisos; totalidad de subtipo | — |
| RN-07 | Tabla 1:N y `vencimiento > emisión` | — | — |
| RN-08 | Fórmula del renglón y aritmética de cabecera | Precio y descuento completados por trigger; cabecera recalculada desde renglones; importes no editables; comprobante con al menos un renglón; la API vende sólo con `fn_registrar_venta` (todo o nada) | — |
| RN-09 | Stocks `>= 0` | Trigger BEFORE con `FOR UPDATE` que rechaza sin stock; AFTER que descuenta | — |
| RN-10 | ENUM y estado inicial | Transiciones sin retroceso; terminar exige renglones; procesar sólo por `sp_procesar_ingreso`, impacto único | — |
| RN-11 | ENUM, estado inicial, fecha por defecto | Fecha forzada e inmutable; transiciones; `sp_procesar_transferencia` atómico y con verificación por renglón | — |
| RN-12 | — | Bloqueo de renglones fuera de confección; D5 permitido por cascada; extendida a comprobantes: una venta confirmada no admite renglones nuevos (`xact_alta`) | — |
| RN-13 | Tabla de auditoría con valores válidos | Trigger `AFTER UPDATE OF precio` con `session_user` | — |
| RN-14 | `RESTRICT` desde movimientos, stock y auditoría | — | — |
| RN-15 | `CHECK` de cantidades, superficies, kilos, precios y graduación | — | — |
| Jerarquía de clientes | Exclusividad por FK compuesta y `ck_*_tipo` | Totalidad por constraint triggers diferidos | — |

Todas las reglas RN-01 a RN-15 tienen mecanismo y caso de prueba. Quedan como participaciones mínimas no exigidas por una RN: al menos un maridaje por vino, un análisis por lote y un empleado por sala.

## 9. Estado de la Etapa 2: integridad y lógica

### 9.1 Entregables

- `db/migrations/003_funciones.sql` a `007_roles.sql` (la consigna incluye `002_constraints.sql`, que ya estaba completo y no se modificó).
- Pruebas en `db/tests/` (equivalente a `tests/db_tests.sql` de la consigna), ejecutables con `run_all.sh`.
- `docs/trazabilidad.md`: tabla regla → mecanismo → caso de prueba y la guía "¿Dónde va cada regla?".
- `docs/concurrencia.md`: guion de la demostración con dos sesiones, con lugares para las capturas.

### 9.2 Mínimos de la consigna, contados en el catálogo

Valores obtenidos con consultas a `pg_proc`, `pg_trigger`, `pg_views`, `pg_roles`, `pg_type`, `pg_constraint` y `pg_attrdef` sobre una base creada desde cero.

| Elemento | Mínimo | Real |
|---|---:|---|
| Funciones | 4 | 7: `fn_descuento_cliente`, `fn_stock_sala`, `fn_total_comprobante`, `fn_antiguedad_anios`, `fn_recalcular_comprobante`, `fn_registrar_venta`, `fn_validar_transicion_estado`; además 16 funciones de trigger |
| Procedimientos | 2 | 4: `sp_terminar_ingreso`, `sp_procesar_ingreso`, `sp_terminar_transferencia`, `sp_procesar_transferencia` |
| Triggers | 6, con BEFORE, AFTER y constraint diferido | 20: 10 BEFORE, 2 AFTER, 8 `CONSTRAINT … DEFERRABLE INITIALLY DEFERRED` |
| Vistas | 3 | 4: `v_stock_total_vino`, `v_ventas_mensuales_sala`, `v_documentos_pendientes`, `v_ficha_vino` (ninguna materializada; ver `006_vistas.sql`) |
| Roles | 3 | Propietario, `bodegas_rw` (API) y `bodegas_ro` (reportes), con sus cuentas `DB_APP_USER` y `DB_REPORT_USER` |
| ENUM / DOMAIN | 1 / 1 | 2 / 1 |
| UNIQUE | 4 | 11 |
| CHECK | 8 (uno entre columnas) | 36 contando el dominio; varios entre columnas |
| DEFAULT | 3 | 17 columnas |
| PK / FK | todas | 31 / 35 |

## 10. Estado de la Etapa 3: carga masiva

### 10.1 Entregables

- `db/seed/`: catálogos CSV con fuentes, `generar_datos.py`, `requirements.txt` y `Dockerfile` con versiones exactas, `controles.sql`, `post_carga.sql`, `hashes.sql` y README con los pasos.
- Servicio `seed` en `docker-compose.yml` (perfil `seed`, red `datos`, sólo credenciales del propietario, después de `migrate`).
- `docs/carga_masiva.md`, el reporte de la etapa:
  - catálogos y fuentes;
  - orden de carga según las FK;
  - estrategia frente a los triggers y sus riesgos;
  - conteos;
  - tiempos fila por fila, por lotes y con `COPY`;
  - controles;
  - reproducibilidad;
  - volcado.
- `dump_completo.sql.gz`: **no se versiona**, porque `.gitignore` excluye `*.sql.gz` (7,8 MB). El README de `db/seed` explica cómo generarlo y restaurarlo.

No se agregaron migraciones: la carga usa los objetos de 001 a 007.

### 10.2 Criterios de aceptación

| Criterio | Evidencia |
|---|---|
| Se cumplen los mínimos de volumen | Las 30 tablas tienen filas. Seis superan las 10.000 filas. `renglon_comprobante` tiene 538.306 y `comprobante` 150.125. Control de volumen de `controles.sql` sin violaciones. |
| Dos ejecuciones con la misma semilla producen los mismos datos | Tres cargas desde volúmenes vacíos (una de ellas con las secuencias ya consumidas por las pruebas) dieron las mismas huellas md5 en las 30 tablas. La tabla está en `docs/carga_masiva.md`, sección 8. |
| Las consultas de control no encuentran inconsistencias | `controles.sql`: 55 controles y 35 FK revisadas, 0 violaciones. Una alteración provocada se detecta con código 3. |
| El informe compara la carga fila por fila con la carga por lotes | `docs/carga_masiva.md`, sección 7.2: fila por fila con y sin `COMMIT` por fila, `executemany` y `COPY`. |
| Está documentado cómo se manejaron los triggers | `docs/carga_masiva.md`, sección 3: se deshabilitan sólo 7 triggers por nombre, en una transacción. Están verificadas las FK activas, la rehabilitación por `ROLLBACK` y el control de `tgenabled`; se documentan los riesgos y cómo se compensan. |

Después de la carga, `db/tests/run_all.sh` sigue pasando completo, y `post_carga.sql` demuestra las reglas activas por el camino normal.
