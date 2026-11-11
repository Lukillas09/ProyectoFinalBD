# Informe de cierre de la Etapa 8 — Despliegue en la nube (Render)

Fecha: 2026-11-10
Rama: `etapa-8-final`
Commit base: `2d0f0ff` (Merge PR #74)

Este informe cierra la Etapa 8: el sistema está desplegado en Render y los catorce requisitos de la consigna están verificados con evidencia. Las salidas completas de cada paso están en `db/nube/salida/` (no se versiona) y se resumen en [`nube.md`](nube.md) §6, sin secretos.

**Versión pública:** front <https://bodegas-front-cq6q.onrender.com> · API y Swagger <https://bodegas-api-srvr.onrender.com/docs>.

---

## 1. Estado de los issues y los PRs (#66 a #71)

| Issue | Descripción | PR | Estado |
|-------|-------------|----|--------|
| #66 | Código para la nube: `DB_SSLMODE`, `CORS_ORIGINS`, `config.js` generado y `render.yaml` | #72 | Cerrado |
| #67 | Base en Render: PostgreSQL 16, roles, migraciones en orden y carga | este PR | Cumplido (sección 3) |
| #68 | API y front en Render con HTTPS y secretos del proveedor | este PR | Cumplido |
| #69 | Seguridad en la nube: SSL, acceso rechazado, CORS, privilegios y regla por trigger | este PR | Cumplido |
| #70 | Backup y restauración con conteos | este PR | Cumplido |
| #71 | Cierre: este informe, README con URLs y pasos | este PR | Cumplido |

Los PRs #73 y #74 registraron antes el estado intermedio del despliegue: lo que faltaba y que las URLs que figuraban en el README no eran de este proyecto.

**Cómo se operó.** Lucas autorizó a un agente a ejecutar los pasos de `db/nube/render.sh` con su `db/nube/render.env` y a integrar el PR; los clics en el dashboard de Render (servicios, variables, lista de IPs y deploys) los hizo él. La clave de la API de Render nunca se usó.

---

## 2. Verificación de base sobre `main`

La Etapa 8 no cambió la API ni el front: sólo documentación y `db/nube/render.sh`. Antes de desplegar se corrieron las dos suites sobre `main`, desde un volumen vacío:

| Suite | Resultado |
|---|---|
| `api/tests/ejecutar.sh` | **272 passed** (incluye las 11 de `api/tests/test_nube.py` sobre `DB_SSLMODE` y CORS) |
| `front/tests/ejecutar.sh` | **33 passed** |

---

## 3. Requisitos R1 a R14 (`docs/nube.md` §1)

| # | Requisito | Estado | Evidencia |
|---|-----------|--------|-----------|
| R1 | PostgreSQL en la nube | ✅ | `bodegas-db` en Render: PostgreSQL 16.15, región Virginia (`verificar-admin`) |
| R2 | API y front con URL pública y HTTPS | ✅ | Front y API en `https://…onrender.com`, con certificado de Render. Front 200 (es el de este proyecto); API 200 en `/salud`, `/docs` y `/vinos`. Capturas en `docs/img/nube/` |
| R3 | Migraciones aplicadas en orden desde los SQL del repositorio | ✅ | `db/migrate.sh` como `bodegas_owner`: las 10 (001 a 010), con checksums; `schema_migration` tiene 10 filas |
| R4 | Conexión cifrada (`sslmode=require`) | ✅ | Sesión de `bodegas_api`: `ssl = t`, TLS 1.3. `render.sh sin-ssl` falla con `SSL/TLS required`. *Salvedad:* la sesión de la propia API no se puede ver en `pg_stat_ssl` desde nuestras cuentas; `DB_SSLMODE=require` está declarado en `render.yaml` |
| R5 | Puerto de la base no expuesto a todo internet | ✅ | Lista de IPs vacía: `render.sh tamano` falla al conectar y la API sigue en 200 por la red privada |
| R6 | Secretos en variables de entorno del proveedor | ✅ | `DB_PASSWORD`, `CORS_ORIGINS` y `API_BASE_URL` cargadas en el dashboard (`sync: false`); la API y el front funcionan con ellas. El historial del repositorio (172 commits) no contiene contraseñas, claves ni URLs de conexión con credenciales |
| R7 | La API usa el rol de privilegios mínimos | ✅ | `render.yaml` fija `DB_USER=bodegas_api`. Después del bootstrap el administrador no puede conectarse a la base (`User does not have CONNECT privilege`), así que la API no puede estar usándolo |
| R8 | Backup y restauración probados con conteos | ✅ | `pg_dump -Fc` de 1,3 MB; restauración en una base nueva con **conteos idénticos en las 31 tablas** y **huellas de contenido idénticas** en las 30 con huella |
| R9 | Datos cargados (reducida: más de 10.000 filas) | ✅ | `ESCALA=0.1`: 15.044 comprobantes y 54.218 renglones (los mismos que en local); 24 MB de 1 GB |
| R10 | Comparar dos proveedores y justificar uno | ✅ | `docs/nube.md` §2: Render y Azure for Students; Neon y Oracle descartados |
| R11 | CORS limitado al origen público | ✅ | Origen ajeno y origen `http`: 400 sin `access-control-allow-origin`. Origen del front: 200 con la cabecera. Salida: `db/nube/salida/08b_cors_final.txt` |
| R12 | Rechazo comprobado de una conexión no autorizada | ✅ | Conexión externa con la lista vacía: cortada. Sin TLS: rechazada. `bodegas_api`: `CREATE TABLE`, `UPDATE stock_sala` y `CREATE ROLE` con *permission denied* |
| R13 | Repetir en la nube una regla ejecutada por trigger | ✅ | RN-09 desde el front público: `409 · RN-09: stock insuficiente del vino 12 en la sala 1.` y *No se registró ningún comprobante*; conteos de las 31 tablas idénticos antes y después. Captura: `docs/img/nube/venta_sin_stock_rn09.png` |
| R14 | README con URL pública y pasos para reproducir | ✅ | README: URLs reales y los pasos 1 a 6, ajustados con lo aprendido; `db/nube/README.md` con una sección "Si algo falla" |

**Resumen: 14 de 14 cumplidos.** El de menor certeza es R4: el cifrado se comprobó en la sesión de `bodegas_api` abierta desde la PC y en el rechazo de conexiones sin TLS, y para la sesión de la propia API se apoya en `DB_SSLMODE=require` de `render.yaml`.

---

## 4. Evidencia resumida

| Paso | Resultado |
|---|---|
| `verificar-admin` | `rolcreaterole = t`, `rolsuper = f`, PostgreSQL 16.15, `ssl = t` TLS 1.3 |
| `bootstrap` | Roles, grupos y esquema; el administrador queda sin acceso a los datos |
| `migrar` | Las 10 migraciones |
| `cargar` | 1 min 12 s por internet; 31 tablas |
| `controles` | Pasan `controles.sql` y `post_carga.sql` (RN-09, RN-10, RN-11, RN-12 y RN-13) |
| `tamano` | 24 MB |
| API pública | `/salud`, `/docs`, `/vinos?limite=1` (600 vinos), `/catalogos/salas` y `/reportes/top-vinos`: 200 |
| Front público | Catálogo con 600 vinos, indicador "Sistema disponible"; sólo llama a la API real, sin errores de CORS |
| `backup` y `restaurar` | "Conteos IDÉNTICOS"; huellas idénticas |

**Lista de IPs de la base** (horas aproximadas, de Argentina): vacía al principio; `132.255.114.196/32` antes de las 23:01; `132.255.114.0/24` hacia las 23:21; vacía de nuevo antes de las 23:49. Detalle en `nube.md` §6.6.

---

## 5. Incidencias y cómo se resolvieron

- **La clave de la API no existía.** La operación por API necesitaba `RENDER_API_KEY`, y no estaba en la PC. No se buscó por otros medios. Se resolvió ejecutando `render.sh` con las credenciales de la base que Lucas cargó en `render.env`.
- **Las URLs del README no eran de este proyecto.** `bodegas-front.onrender.com` y `bodegas-api.onrender.com` pertenecen a otras cuentas (el nombre de un servicio de Render es único). Se tomaron las URLs reales del dashboard (`-cq6q` y `-srvr`).
- **La IP de la PC cambia por conexión.** El proveedor de internet reparte la salida entre varias IPs: en pocos segundos la misma PC se vio como `132.255.114.196`, `.82`, `.168`, `.108` y `.142`. Con una regla `/32`, Render cortaba el TLS (`SSL connection has been closed unexpectedly`). Se resolvió con el bloque `/24`, temporal. Se diagnosticó con una prueba sin credenciales: sin SNI, Render responde `No SNI information found`; con `sslmode=disable`, `SSL/TLS required`; TLS 1.2 y 1.3 daban lo mismo.
- **Contraseña del administrador.** La primera era un valor de 10 caracteres y fue rechazada; la del dashboard tiene 32.
- **Las variables nuevas necesitan un deploy.** El `config.js` del front se genera al construirlo y el CORS de la API se lee al arrancar: con los valores viejos, el front apuntaba a una API ajena y la API rechazaba el origen del front real. Se corrigió cargando `API_BASE_URL` y `CORS_ORIGINS` y redesplegando.
- **Bug en `render.sh restaurar`.** Con `--clean`, `pg_restore` intenta desarmar la vista `v_documentos_pendientes` antes de crear el tipo `estado_documento` y falla; el error era inofensivo pero cortaba el script antes de comparar. Ahora borra el esquema vacío y restaura con `--exit-on-error`, que es más estricto. Se probó de punta a punta.
- **`pg_stat_ssl` y la sesión de la API.** Ni el rol de reportes ni el administrador (que no es `pg_monitor`) pueden ver sesiones ajenas, así que la sesión de la API no se pudo observar.

---

## 6. Decisiones para defender

- **Render y no una VM.** Cumple todos los requisitos con mecanismos del propio proveedor (PostgreSQL gestionado, TLS obligatorio, lista de IPs, HTTPS automático) y separa la base de la aplicación con la red privada; Azure for Students pedía administrar un servidor, Neon no restringe el puerto por IP en el plan gratis y Oracle pide tarjeta.
- **Un bootstrap distinto del local.** El administrador de Render no es superusuario: `bootstrap_render.sh` reordena los pasos para PostgreSQL 16 (membresía `SET`, traspaso de la base, permisos dados por el nuevo dueño) y al final le quita al administrador el acceso a los datos. Los roles y permisos resultantes son los mismos que en local.
- **Carga reducida.** `ESCALA=0.1` (más de 10.000 filas) por plazo: la carga por internet tarda más que en local. La completa (unos 34 MB) entraría en el 1 GB del plan, y el volumen completo se mantiene en local.
- **La API entra por la red privada.** La lista de IPs de la base queda vacía; sólo se abre la IP de quien ejecuta, durante el paso que la necesita.
- **Los cálculos siguen siendo de PostgreSQL.** La regla RN-09 se comprobó en la nube con el mismo mensaje y sin datos a medias.

---

## 7. Pendientes y limitaciones

| Tema | Estado |
|---|---|
| **Revisión cruzada** | Los PRs #72, #73 y #74 se integraron sin ninguna revisión registrada, y este PR también, por la entrega y con autorización de Lucas. La revisión de 21dai, solicitada en cada uno, sigue pendiente. `AGENTS.md` exige un PR revisado por otro integrante |
| Cifrado de la sesión de la API | No observable en `pg_stat_ssl` (ver R4). Conviene confirmar en el dashboard que `bodegas-api` tenga `DB_SSLMODE=require` |
| Vencimiento de la base | La base gratis vence a los 30 días (alrededor del 10/12/2026): hay que recrearla con los mismos scripts antes de esa fecha si se necesita |
| API gratuita | Se duerme a los 15 minutos sin uso: el primer pedido puede tardar cerca de un minuto |
| Carga reducida | `ESCALA=0.1`; la completa sólo está en local |
| Zona horaria | La base corre en UTC: decisión pendiente, no se resolvió en esta etapa |
| Sin autenticación | Las escrituras de la API no piden credenciales (extra opcional según el PDF) |
| Preguntas abiertas a la cátedra | Alcance de la trazabilidad y `POST /ingresos/{cod}/terminar` (`docs/api.md` §6) |
| Demo y defensa | Etapa 9: la demo se hace sobre esta versión |

---

## 8. Conclusión

**La Etapa 8 (nube) está completa y verificada.** El sistema funciona en Render con HTTPS, conexión cifrada, la base sin acceso externo, CORS limitado al front, una regla de trigger comprobada desde el front público y un backup restaurado con conteos y huellas idénticos. Queda pendiente la revisión cruzada de los PRs de esta etapa.
