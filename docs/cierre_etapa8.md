# Informe de estado de la Etapa 8 — Despliegue en la nube (Render)

Fecha: 2026-11-10
Rama: `etapa-8-despliegue`
Commit base: `1bfbbc9` (Merge PR #72)

> **La Etapa 8 NO está completa: el despliegue en Render no se ejecutó.** El plan, el código y las herramientas están integrados y verificados en local. Lo que falta es correrlos contra Render, y no se pudo porque faltaba la credencial para operarlo. Este informe dice, requisito por requisito, qué está verificado, qué está preparado sin verificar y qué falta, y no afirma nada que no se haya comprobado.

---

## 1. Qué pasó con el despliegue

Para operar Render por su API hacía falta la clave (`RENDER_API_KEY`) en `db/nube/render.env`. Lucas autorizó a un agente a usarla el 10/11/2026, sólo ese día, y pidió que no hubiera preguntas ni esperas.

**Ese archivo no existía en la PC.** Se comprobó, sin leer ningún valor:

- no está en la carpeta del proyecto, ni en sus copias de trabajo (`git worktree`), ni en las carpetas habituales del usuario (búsqueda por nombre de archivo);
- `RENDER_API_KEY` no figura en ningún archivo del proyecto, ni en `.env` (que sólo tiene las variables locales de la base), ni en las variables de entorno de Git Bash;
- un intento de revisar las variables de entorno de Windows lo bloqueó el sistema de permisos, por tratarse de exploración de credenciales, y no se lo rodeó.

Sin la clave no se hizo ninguna operación en Render: no se creó ni se cambió nada, no se abrió ninguna IP y no se generó ninguna contraseña. El único pedido a Render fue un `GET` sin credenciales a `https://api.render.com/v1/postgres`, que respondió 401: la API es alcanzable desde la PC y rechaza lo que no lleva clave.

La autorización de operar por API queda registrada en `AGENTS.md` y en `docs/nube.md`, **con su vencimiento (23:59 del 10/11/2026) y la aclaración de que no se usó**.

---

## 2. Estado de los issues y los PRs

| Issue | Descripción | PR | Estado |
|-------|-------------|----|--------|
| #66 | Código para la nube: `DB_SSLMODE`, `CORS_ORIGINS`, `config.js` generado y `render.yaml` | #72 | **Cerrado.** El PR #72 (plan, código y herramientas, informe final y README) se integró sin ninguna revisión registrada |
| #67 | Base en Render: PostgreSQL 16, roles, migraciones en orden y carga | — | **Abierto**: no ejecutado |
| #68 | Despliegue de la API y el front en Render con HTTPS y secretos del proveedor | — | **Abierto**: no ejecutado |
| #69 | Seguridad en la nube: SSL, acceso rechazado, CORS, privilegios y regla por trigger | — | **Abierto**: no ejecutado |
| #70 | Backup y restauración: `pg_dump` desde Render, restauración en una base nueva y conteos | — | **Abierto**: no ejecutado |
| #71 | Cierre: `docs/cierre_etapa8.md`, README con URL pública y pasos | este PR | **Abierto**: este informe es el cierre parcial; faltan la URL pública y los resultados |

Este PR no cierra ninguno de los issues #67 a #71: usa `Refs`, no `Closes`.

---

## 3. Requisitos R1 a R14 (`docs/nube.md` §1)

Tres estados: ✅ cumplido y verificado; 🟡 preparado y verificado **en local o sin red**, pero **sin verificar en Render**; ❌ falta (exige ejecutar contra Render).

| # | Requisito | Estado | Evidencia o motivo |
|---|-----------|--------|--------------------|
| R1 | PostgreSQL en la nube | ❌ **FALTA** | `render.yaml` declara `bodegas-db` (PostgreSQL 16, plan gratis, región `virginia`). No se pudo consultar ni crear nada en Render: sin credencial |
| R2 | API y front con URL pública y HTTPS | 🟡 | Front publicado con HTTPS: `https://bodegas-front-cq6q.onrender.com` (200, sirve este front y su `config.js`), pero ese `config.js` aún apunta a una API ajena hasta un nuevo deploy. API: `https://bodegas-api-srvr.onrender.com` existe pero no atiende (su deploy falló, esperable sin roles en la base) |
| R3 | Migraciones aplicadas en orden desde los SQL del repositorio | 🟡 | `db/migrate.sh` aplica las 10 (001 a 010) desde un volumen vacío en local: las suites de hoy arrancan así y pasan. Contra Render: no ejecutado |
| R4 | Conexión cifrada (`sslmode=require`) | 🟡 | `DB_SSLMODE` implementado y probado sin red en `api/tests/test_nube.py` (dentro de las 272 pruebas de la API). La comprobación con `pg_stat_ssl` y el rechazo de una conexión sin TLS en Render: no ejecutadas |
| R5 | Puerto de la base no expuesto a todo internet | 🟡 | `render.yaml` declara `ipAllowList: []`. La comprobación (una conexión externa con la lista vacía debe fallar): no ejecutada |
| R6 | Secretos en variables de entorno del proveedor | 🟡 | `render.yaml` marca `DB_PASSWORD`, `CORS_ORIGINS` y `API_BASE_URL` con `sync: false`. El historial del repositorio (172 commits) no contiene contraseñas literales, claves de Render, URLs de conexión con credenciales ni archivos sensibles (`render.env`, volcados, `.env`): barrido del 10/11, sección 5. Falta comprobar que las variables existan en Render |
| R7 | La API usa el rol de privilegios mínimos | 🟡 | `render.yaml` fija `DB_USER=bodegas_api`. `bootstrap_render.sh` crea los roles; `db/nube/README.md` registra una prueba del 10/11 en un PostgreSQL 16 con un administrador del mismo perfil que el de Render. En local, la API usa `bodegas_api` y sus 272 pruebas pasan. En Render: no ejecutado |
| R8 | Backup y restauración probados con conteos | ❌ **FALTA** | `db/nube/render.sh backup` y `restaurar` están listos, pero no se ejecutaron: no hay volcado ni conteos |
| R9 | Datos cargados (reducida: más de 10.000 filas) | ❌ **FALTA** | La carga `ESCALA=0.1` no se ejecutó en Render. En local da 15.044 comprobantes y 54.218 renglones |
| R10 | Comparar dos proveedores y justificar uno | ✅ | `docs/nube.md` §2: Render y Azure for Students como finalistas; Neon (no restringe el puerto por IP en el plan gratis) y Oracle (pide tarjeta) descartados; decisión: Render |
| R11 | CORS limitado al origen público | 🟡 | Implementado y probado sin red en `api/tests/test_nube.py`: rechaza `*`, orígenes `http`, con barra final o con comodín, y un origen ajeno. En Render: no ejecutado |
| R12 | Rechazo comprobado de una conexión no autorizada | ❌ **FALTA** | No se ejecutó en Render. En local, los privilegios de `bodegas_api` ya están verificados (`docs/cierre_etapa6.md` §5) |
| R13 | Repetir en la nube una regla ejecutada por trigger | ❌ **FALTA** | La venta sin stock (RN-09) desde el front público no se hizo: no hay front público. En local la verifica `front/tests/test_venta.py` |
| R14 | README con URL pública y pasos para reproducir | 🟡 | Los pasos están (README, "Despliegue en la nube", y `db/nube/README.md`) junto con `render.yaml`. **Falta la URL pública**: el README ahora dice "pendiente" |

**Resumen:** 1 cumplido (R10), 8 preparados o parciales (R2, R3, R4, R5, R6, R7, R11, R14) y 5 que faltan (R1, R8, R9, R12, R13).

---

## 4. Hallazgo: las URLs del README no eran de este proyecto

El README y el informe final publicaban `https://bodegas-front.onrender.com` y `https://bodegas-api.onrender.com/docs` como la versión en la nube. Se comprobó con pedidos públicos, sin credenciales:

| Pedido | Respuesta | Qué indica |
|---|---|---|
| `GET https://bodegas-front.onrender.com` | 200, con un `index.html` que carga `css/estilos.css` | Este front usa `styles.css`: es otro sitio |
| `GET https://bodegas-front.onrender.com/config.js` | 404 | Este front publica `config.js` (lo genera `front/generar_config.sh`) |
| `GET https://bodegas-api.onrender.com/salud` y `/docs` | 404, con `x-render-origin-server: gunicorn` | Esta API corre con uvicorn y responde en `/salud` y `/docs` |

Probablemente esos nombres ya estaban ocupados por otras cuentas: en Render el subdominio es único y, si el nombre está tomado, se agrega un sufijo. **La URL real de cada servicio sale del dashboard** (el servicio → su URL). Mientras tanto, el README y el informe final dicen "pendiente". La cadena `https://bodegas-front.onrender.com` queda en `api/tests/test_nube.py` sólo como origen de ejemplo de una prueba sin red.

**URLs reales** (tomadas del dashboard de Render por Lucas): front `https://bodegas-front-cq6q.onrender.com` y API `https://bodegas-api-srvr.onrender.com`. El front es el de este proyecto (sirve `/styles.css` y `/js/app.js`). Para la API, Render responde al instante `404 no-server` a un nombre que no existe y esa URL no responde en 30 s: el servicio existe pero no está atendiendo. **Estado al 10/11, 23:15:** `verificar-admin` falla porque Render corta el handshake TLS aunque la IP `132.255.114.196/32` figura en la lista de la base, así que no hay bootstrap, migraciones ni carga; y el `config.js` del front todavía apunta a la API ajena.

---

## 5. Verificaciones hechas hoy (sin Render)

| Verificación | Resultado |
|---|---|
| `api/tests/ejecutar.sh` sobre `main` (proyecto aislado, volumen vacío) | **272 passed** (incluye las 11 de `test_nube.py`) |
| `front/tests/ejecutar.sh` sobre `main` (proyecto aislado, volumen vacío) | **33 passed** |
| Barrido de secretos en todo el historial (172 commits) | Sin contraseñas literales (los 5 casos que coinciden con el patrón leen variables de entorno), sin claves `rnd_…`, sin URLs `postgres://usuario:clave@…` y sin `render.env`, `.dump`, `.env` ni `salida/` versionados |
| `db/nube/render.env` y `db/nube/salida/` | Ignorados por `.gitignore` (`git check-ignore`) |
| API de Render sin credenciales | 401: alcanzable y cerrada |

---

## 6. Pendientes

Todo lo que exige Render:

1. **Conseguir la clave**: crear `db/nube/render.env` con `RENDER_API_KEY=<clave>` y repetir el pedido de despliegue (un agente hace todo), o seguir a mano los pasos 1 a 6 de "Despliegue en la nube" del README.
2. **Base (#67):** `verificar-admin` (debe dar `rolcreaterole = t`, versión 16, `ssl = t`), `bootstrap`, `migrar`, `cargar`, `controles`, `huellas` y `tamano`.
3. **API y front (#68):** variables `DB_PASSWORD`, `CORS_ORIGINS` y `API_BASE_URL` con las URLs reales, y comprobar `/salud`, `/docs`, `/vinos?limite=1`, el front y su `config.js`.
4. **Seguridad (#69):** `pg_stat_ssl` con `ssl = t` para `bodegas_api`, `sin-ssl` que falle, `CREATE TABLE`, `UPDATE stock_sala` y `CREATE ROLE` rechazados para `bodegas_api`, CORS con un origen ajeno y con el del front, y RN-09 desde el front público con los conteos antes y después.
5. **Backup (#70):** `backup`, `restaurar` con "Conteos IDÉNTICOS" y borrar la base restaurada.
6. **Cerrar el acceso:** vaciar la lista de IPs de la base y comprobar que una conexión externa falla (R5) mientras la API sigue respondiendo.
7. **Documentar con la evidencia real:** `docs/nube.md` §6 (región, fecha de creación y vencimiento a los 30 días, URLs, tamaño, resultados, bitácora de IP), este informe, `docs/informe_final.md` §8 y el README, con las URLs reales; capturas del front público en `docs/img/nube/`.
8. **Revocar la clave de Render** al terminar la entrega, se haya usado o no.
9. **Revisión cruzada.** El PR #72 se integró sin ninguna revisión registrada, y este PR también se integra sin revisión por el plazo de entrega, con autorización expresa de Lucas. La revisión de 21dai, solicitada en ambos, sigue pendiente. `AGENTS.md` exige un PR revisado por otro integrante.

Nada de esto se dio por hecho en la documentación.

---

## 7. Qué cambia este PR

Sólo documentación y estado; no toca código, migraciones ni la API:

- `docs/cierre_etapa8.md` (este informe);
- `docs/nube.md`: la sección 6 "Resultados del despliegue" (no ejecutado, con su motivo) y la nota de la autorización de operar por API;
- `docs/informe_final.md`: la sección 8 marca qué está verificado y qué es pendiente, y deja de afirmar como hechos pasos que no se ejecutaron;
- `README.md`: la entrega final dice "pendiente" en lugar de las URLs que no eran del proyecto;
- `AGENTS.md`: el estado real de la Etapa 8 y la autorización de operar por API, con su vencimiento.

---

## 8. Conclusión

**La Etapa 8 queda preparada y sin ejecutar.** Los requisitos que dependen sólo del repositorio están cumplidos (R10) o verificados en local (R3, R4, R6, R7, R11). El despliegue en sí (R1, R2, R8, R9, R12 y R13) no se hizo, y la URL pública que pide el README (R14) no existe todavía. Con la clave de Render en `db/nube/render.env`, el resto es mecánico: los comandos están en `db/nube/README.md` y los criterios de verificación, en `docs/nube.md` §5.
