# Etapa 8 · Despliegue en la nube

Plan, comparación de proveedores y diseño del despliegue. Las evidencias (capturas, conteos, comandos) se agregan en cada issue y se resumen en `docs/cierre_etapa8.md`.

> **Autorización.** `AGENTS.md` exige una instrucción explícita para desplegar. El 10/11/2026 Lucas pidió empezar la Etapa 8 y eligió Render. Cada paso que crea o cambia recursos en Render lo ejecuta él desde su cuenta. Las credenciales nunca pasan por el repositorio.

> **Operación por API, autorizada sólo el 10/11/2026.** Ese día, y hasta las 23:59 (hora de Argentina), Lucas autorizó a un agente a operar Render por su API con la clave de `db/nube/render.env` (`RENDER_API_KEY`), en lugar de ejecutar él cada paso. **No se llegó a usar**: ese archivo no existía en la PC (sección 6). Si la clave se usa, se recomienda **revocarla** (Account Settings → API Keys) al terminar la entrega.

## 1. Qué pide la consigna

> Objetivo: que el sistema funcione en un servidor que no es la computadora del grupo, con las medidas básicas de seguridad y operación que se esperan de cualquier sistema real.

| # | Requisito | Cómo se cumple (sección 3) | Issue |
|---|---|---|---|
| R1 | PostgreSQL en la nube (gestionado o contenedor en un servidor virtual) | Render Postgres **16**, gestionado | #67 |
| R2 | API y front con URL pública y HTTPS | API: web service Docker. Front: static site. Los dos con certificado TLS de Render | #68 |
| R3 | Migraciones aplicadas desde los archivos SQL del repositorio, en orden | `db/migrate.sh` contra la base de Render, como propietario, con la tabla de control y los checksums | #67 |
| R4 | Conexión cifrada (`sslmode=require`) | La API se conecta con `DB_SSLMODE=require`; se verifica con `pg_stat_ssl` | #66, #69 |
| R5 | Puerto de la base no expuesto a todo internet | Lista de IPs vacía en la base: sin acceso externo. La API entra por la red privada de Render (URL interna) | #68, #69 |
| R6 | Secretos en variables de entorno del proveedor | Variables de Render marcadas como secretas (`sync: false` en el blueprint). Nada en el repositorio | #66, #68 |
| R7 | La API usa el rol de privilegios mínimos | `bodegas_api`, creado por el bootstrap, nunca el usuario administrador de Render | #67 |
| R8 | Backup y restauración probados con conteos | `pg_dump -Fc` desde Render, restauración en una base nueva y comparación con `db/seed/hashes.sql` | #70 |
| R9 | Datos cargados (reducida: ≥ 10.000 filas, justificada) | Carga **reducida** `ESCALA=0.1`, con unos 15.000 comprobantes y unos 54.000 renglones (supera las 10.000 filas). La completa (unos 34 MB) entraría en el 1 GB, pero se reduce por **plazo**: la carga a través de internet tarda bastante más que en local, y la entrega es el mismo día. El volumen completo se mantiene en la versión local | #67 |
| R10 | Comparar dos proveedores y justificar uno | Sección 2 de este documento | #71 |
| R11 | CORS limitado al origen público (`docs/requisitos.md` §3.9) | `CORS_ORIGINS` con la URL del front, y nada más | #66, #69 |
| R12 | Rechazo comprobado de una conexión no autorizada | Conexión externa rechazada; `bodegas_api` sin permiso para crear tablas ni tocar stock | #69 |
| R13 | Repetir en la nube una regla ejecutada por trigger | Venta sin stock (RN-09) desde el front público, con captura | #69 |
| R14 | README con URL pública y pasos para reproducir | `render.yaml` (blueprint) más una guía paso a paso | #71 |

Rúbrica: **10 puntos**, *"Despliegue, HTTPS, conexión cifrada, acceso restringido, …"*. La demo final de la Etapa 9 se hace sobre esta versión.

## 2. Comparación de proveedores

Condiciones consultadas el **10/11/2026** en los sitios de cada proveedor. Los planes gratuitos cambian seguido, como advierte la consigna.

### 2.1 Filtros previos

| Requisito del proyecto | Por qué filtra |
|---|---|
| PostgreSQL **16** | Regla de `AGENTS.md`; las migraciones y las pruebas se escribieron sobre 16 |
| Poder **restringir el puerto** (IP o red privada) | R5 de la consigna |
| **Crear nuestros roles** (propietario, API, reportes) | R7; la seguridad del proyecto se apoya en esos roles |
| Gratis, idealmente **sin tarjeta** | Trabajo académico |

Descartados:

- **Neon.** Plan gratis con 1 GB por proyecto y suspensión a los 5 minutos de inactividad, pero **IP Allow sólo está en el plan Scale**, que es pago. Con el plan gratis, el puerto queda abierto a internet, protegido sólo por la contraseña: no cumple R5.
- **Oracle Cloud Always Free.** VM Arm gratis, pero **pide tarjeta de crédito** para verificar la identidad (rechaza prepagas y virtuales). Además es frecuente el error "out of host capacity" en la región elegida.

### 2.2 Los dos finalistas

| Criterio | **Render (plan gratis)** | **Azure for Students (VM con Docker Compose)** |
|---|---|---|
| Costo y tarjeta | Gratis, sin tarjeta | US$ 100 de crédito por 12 meses, sin tarjeta, con mail de estudiante |
| PostgreSQL 16 | Sí, versión elegible (13 a 18) | Sí, la misma imagen `postgres:16` que en local |
| Tipo | Servicio gestionado | Servidor virtual que administramos nosotros (B1s/B2ats: 1 GB de RAM) |
| Almacenamiento | 1 GB | Disco de la VM; también hay Flexible Server B1MS con 32 GB |
| Vencimiento | **La base gratis vence a los 30 días** (más 14 de gracia) | 12 meses de crédito |
| Restricción del puerto | Lista de IPs de la base: se puede cerrar todo acceso externo; los servicios de la misma región usan la URL interna | Grupo de seguridad de red: sólo 80 y 443; la base no se publica fuera de la red de Docker |
| TLS hacia la base | Externa: siempre TLS, rechaza `sslmode=disable`. Interna: TLS opcional, se fuerza con `sslmode=require` | Hay que configurar SSL en el contenedor de PostgreSQL (certificado propio) |
| HTTPS de la API y el front | Automático | Hay que instalar Caddy o nginx con Let's Encrypt y un nombre DNS |
| Disponibilidad | La API gratis **se duerme a los 15 minutos** sin tráfico y tarda un minuto en despertar. El static site no se duerme | Siempre encendida |
| Backups | El plan gratis no tiene backups: los hacemos con `pg_dump` (R8 lo pide igual) | Los hacemos con `pg_dump` |
| Esfuerzo de operación | Bajo: no hay servidor que mantener | Alto: actualizaciones, firewall, certificados y memoria escasa |
| Riesgo principal | Que el usuario administrador no tenga permisos para crear roles o traspasar el dueño (se verifica primero, #67) | Elegibilidad del mail y RAM justa para PostgreSQL, la API, nginx y Caddy |

### 2.3 Decisión: Render

1. **Cumple todos los requisitos con mecanismos del proveedor**, no con configuración nuestra:
   - TLS de la base y HTTPS ya resueltos;
   - acceso externo cerrado con una lista de IPs vacía.

   Hay menos piezas que pueden fallar o configurarse mal.
2. **Separa la base de la aplicación** como en un sistema real: la API llega por la red privada y nadie más.
3. **Esfuerzo acotado a lo que evalúa la materia:** roles, privilegios, migraciones, TLS, backup. No se nos va el tiempo en administrar un servidor Linux.
4. **Sus límites no afectan esta entrega:**
   - el vencimiento a los 30 días queda fuera del plazo, porque la entrega es en menos de un mes; la base se crea con fecha anotada y, si hiciera falta, se recrea con los mismos scripts, que es justamente lo que demuestra R3;
   - el 1 GB alcanza para la carga completa;
   - que la API se duerma se resuelve despertándola antes de la demo.

Alternativa de respaldo: Azure for Students con la VM, si Render no permitiera crear los roles (#67).

## 3. Diseño del despliegue

```text
Navegador ──HTTPS──▶ Static site (front)          https://<front>.onrender.com
    │                 config.js → apiBase = URL pública de la API
    └──HTTPS + CORS──▶ Web service (API, Docker)    https://<api>.onrender.com
                         │  rol bodegas_api, sslmode=require
                         └──red privada de Render──▶ Render Postgres 16
                                                    lista de IPs vacía: sin acceso externo
```

- **Región:** la misma para los tres servicios (por ejemplo Virginia), porque la URL interna sólo funciona dentro de una región. Un web service gratis puede *enviar* tráfico privado hacia una base, aunque no recibirlo.
- **Front como static site**, no como el contenedor nginx de local:
  - no se duerme;
  - lo sirve el CDN de Render con HTTPS;
  - `config.js` se genera en el build con la URL pública de la API (`front/config.js` ya se diseñó para eso en la Etapa 7).

  Como el front y la API quedan en dominios distintos, el navegador aplica CORS. La API sólo acepta el origen del front (R11).
- **Roles:**
  - el usuario administrador que crea Render sólo se usa para el bootstrap (crear las tres cuentas, los roles de grupo y el esquema);
  - después, las migraciones y la carga corren como `bodegas_owner`;
  - la API usa `bodegas_api`;
  - las consultas de reportes usan `bodegas_ro`.

  Es la misma separación que en local.
- **Acceso externo temporal:**
  - para el bootstrap, las migraciones y la carga se habilita sólo la IP de quien las ejecuta, con una entrada `/32`;
  - al terminar, la lista vuelve a quedar vacía;
  - el backup de R8 vuelve a abrir esa IP mientras dura y la cierra después.

  Cada apertura y cierre queda en la bitácora del cierre.
- **Secretos:** contraseñas de las cuentas y de los roles generadas al azar, guardadas sólo en las variables de entorno de Render y en el `.env` local de quien despliega, que no se versiona.

## 4. Cambios de código necesarios (#66)

| Cambio | Por qué | Efecto en local |
|---|---|---|
| `DB_SSLMODE` en `api/app/config.py` (valores de libpq, por omisión `prefer`) | R4: en Render se fija `require` | Ninguno: el contenedor local no tiene SSL y `prefer` sigue funcionando |
| `CORS_ORIGINS` en la API (lista separada por comas; vacía = sin CORS) | R11 | Ninguno: en local el front y la API comparten origen por nginx |
| `front/generar_config.sh` que escribe `config.js` desde `API_BASE_URL` | El static site necesita la URL pública de la API | Ninguno: en local se sigue usando el `config.js` versionado (`/api`) |
| `render.yaml` (blueprint) | R14: despliegue reproducible y declarativo | — |
| `db/nube/`: bootstrap adaptado a Render, si el de Docker no corre tal cual | R7 | — |

Ninguno requiere una migración nueva.

## 5. Verificaciones planificadas

Ver los issues #69 (seguridad y regla en la nube) y #70 (backup y restauración). Cada una deja un comando, su resultado y, cuando corresponde, una captura en `docs/img/nube/`.

## 6. Resultados del despliegue

**Estado al 10/11/2026 (alrededor de las 20:40, hora de Argentina): el despliegue en Render NO se ejecutó.** El plan, el código y las herramientas están integrados (#66, PR #72); lo que falta es correrlos contra Render.

**Motivo.** La operación por API necesitaba la clave de Render en `db/nube/render.env`, y ese archivo no existía en la PC: no está en la carpeta del proyecto ni en sus copias de trabajo, y `RENDER_API_KEY` no figura en ningún archivo del proyecto ni en `.env`. No se buscó la clave por otros medios. Sin ella no se creó ni se cambió nada en Render: el único pedido fue un `GET` sin credenciales a la API, que respondió 401.

| Dato | Estado |
|---|---|
| Región y fecha de creación de la base (y su vencimiento a los 30 días) | Sin dato: no se pudo consultar Render. `render.yaml` declara la región `virginia` |
| URLs públicas | Front: `https://bodegas-front-cq6q.onrender.com` (publicado: responde 200 y publica su `config.js`). API: `https://bodegas-api-srvr.onrender.com` (el servicio existe pero no atiende: su único deploy falló, esperable sin los roles en la base) |
| Tamaño usado | Sin dato: no se cargó nada |
| Verificaciones de la base, de seguridad y de backup (secciones 2, 4 y 5 del plan) | **No ejecutadas** |
| Bitácora de aperturas y cierres de IP | **Ninguna**: no se abrió ninguna IP ni se tocó la lista de acceso |
| Operación por la API de Render | Autorizada y **no usada** |

**Hallazgo: las URLs que figuraban en el README no son de este proyecto.** Se comprobó con pedidos públicos sin credenciales:
- `https://bodegas-front.onrender.com` responde, pero sirve otro `index.html` (con `css/estilos.css`; este front usa `styles.css`) y no tiene `config.js` (404), que este front sí publica;
- `https://bodegas-api.onrender.com/salud` y `/docs` dan 404, y la respuesta viene de gunicorn; esta API corre con uvicorn.

Probablemente esos nombres ya estaban ocupados: en Render el subdominio es único y, si el nombre está tomado, se agrega un sufijo. La URL real de cada servicio sale del dashboard (el servicio → su URL). Hasta entonces, el README y el informe final dicen "pendiente" en lugar de esas URLs.

**Actualización (10/11, 23:15).** Lucas completó `render.env`, habilitó su IP y cargó las variables en Render, y autorizó a un agente a ejecutar los pasos de `render.sh`. `verificar-admin` **falla**: Render corta el handshake TLS (con `sslmode=disable` responde `SSL/TLS required` y sin SNI, `No SNI information found`), aunque la IP de salida de la PC, `132.255.114.196/32`, figura en la lista de la base. Sin conexión no hay bootstrap, migraciones ni carga. Además, el `config.js` del front todavía apunta a la API ajena (`bodegas-api.onrender.com`) porque se generó antes de cargar `API_BASE_URL`: hace falta un Manual Deploy del front.

**Cómo completarlo.**
- *Con un agente:* crear `db/nube/render.env` con una sola línea, `RENDER_API_KEY=<clave>`, y repetir el pedido de despliegue.
- *A mano:* los pasos 1 a 6 de "Despliegue en la nube" del README y el "Orden de uso" de `db/nube/README.md`.

Al terminar, cada resultado de esta sección se reemplaza por su evidencia (sin secretos: el host se escribe `dpg-…render.com`).

## Fuentes

- [Render: Deploy for Free (límites del plan gratis)](https://render.com/docs/free)
- [Render: Create and Connect to Render Postgres (versiones, IP rules, TLS)](https://render.com/docs/postgresql-creating-connecting)
- [Render: cambios de planes de agosto de 2026 (reseña)](https://jwatte.com/blog/render-com-platform-review/)
- [Neon: límites del plan gratis](https://neon.com/faqs/free-plan-limits-and-quotas)
- [Neon: IP Allow (plan Scale)](https://neon.com/docs/introduction/ip-allow)
- [Azure for Students](https://azure.microsoft.com/en-us/free/students)
- [Oracle Cloud Always Free: límites 2026](https://space-node.net/blog/oracle-cloud-always-free-limits-2026)
