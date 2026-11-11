# Etapa 8 · Despliegue en la nube

Plan, comparación de proveedores y diseño del despliegue. Las evidencias (capturas, conteos, comandos) se agregan en cada issue y se resumen en `docs/cierre_etapa8.md`.

> **Autorización.** `AGENTS.md` exige una instrucción explícita para desplegar. El 10/11/2026 Lucas pidió empezar la Etapa 8 y eligió Render. Cada paso que crea o cambia recursos en Render lo ejecuta él desde su cuenta. Las credenciales nunca pasan por el repositorio.

> **Cómo se operó.** El 10/11/2026 Lucas autorizó a un agente a ejecutar los pasos de `db/nube/render.sh` con su `db/nube/render.env` y a integrar el PR de cierre; los clics en el dashboard de Render (servicios, variables, lista de IPs y deploys) los hizo él. Esa autorización venció ese día. La clave de la API de Render (`RENDER_API_KEY`) **nunca se usó**: no se llegó a crear.

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

**Estado al 10/11/2026 (23:50, hora de Argentina): desplegado y verificado.** Las salidas completas de cada paso están en `db/nube/salida/` (no se versiona). Acá se resumen sin secretos: el host de la base se escribe `dpg-…render.com`.

### 6.1 Recursos

| Recurso | Dato |
|---|---|
| Proveedor y plan | Render, plan gratis |
| Base | `bodegas-db`, PostgreSQL 16.15, región Virginia (EE. UU. este). Creada el 10/11/2026 (alrededor de las 21:00, según el dashboard). **La base gratis vence a los 30 días** (alrededor del 10/12/2026; la fecha exacta está en el dashboard): se puede recrear con los mismos scripts |
| Front | `https://bodegas-front-cq6q.onrender.com` (static site, HTTPS) |
| API | `https://bodegas-api-srvr.onrender.com` (web service Docker, HTTPS; Swagger en `/docs`) |
| Tamaño usado | 24 MB de 1 GB |
| Datos | Carga reducida `ESCALA=0.1` (R9): 15.044 comprobantes y 54.218 renglones, los mismos de la carga local |

### 6.2 Base (#67)

| Paso | Resultado |
|---|---|
| `verificar-admin` | `bodegas_admin`: `rolcreaterole = t`, `rolsuper = f`; PostgreSQL 16.15; `ssl = t`, TLS 1.3 |
| `bootstrap` | Roles, grupos y esquema creados; el administrador queda sin `CONNECT` a la base (traspaso a `bodegas_owner`) |
| `migrar` | Las 10 migraciones (001 a 010), en orden y con checksums |
| `cargar` | 1 min 12 s por internet. 31 tablas; `comprobante` 15.044 y `renglon_comprobante` 54.218 |
| `controles` | Pasan `controles.sql` y `post_carga.sql`: RN-09, RN-10, RN-11, RN-12 y RN-13 funcionan en la base real, y las verificaciones se revierten |
| `huellas` | 30 tablas con huella de contenido (se comparan con la base restaurada en 6.5) |
| `tamano` | 24 MB |

### 6.3 API y front (#68)

- `GET /salud` → 200 `{"estado":"ok","base_de_datos":"disponible"}`; `/docs`, `/vinos?limite=1` (600 vinos), `/catalogos/salas` y `/reportes/top-vinos` → 200.
- El front responde 200, es el de este proyecto (`/styles.css`, `/js/app.js`) y su `config.js` apunta a la API real: `apiBase: "https://bodegas-api-srvr.onrender.com"`.
- En un navegador real (Chrome, `docs/img/nube/`): el catálogo carga los 600 vinos, el indicador dice "Sistema disponible" y el front sólo llama a `bodegas-api-srvr.onrender.com`, sin errores de CORS en la consola. En las capturas se anota la URL `https://bodegas-front-cq6q.onrender.com/` (HTTPS), porque un navegador sin ventana no dibuja la barra de direcciones.

### 6.4 Seguridad (#69)

| Verificación | Resultado |
|---|---|
| Conexión cifrada | Una sesión de `bodegas_api` desde la PC: `ssl = t`, TLS 1.3, `TLS_AES_256_GCM_SHA384`. La API se conecta con `DB_SSLMODE=require` (`render.yaml`). *Salvedad:* la sesión de la propia API no se puede observar en `pg_stat_ssl` desde ninguna de nuestras cuentas (ni el rol de reportes ni el administrador tienen permiso para ver sesiones ajenas) |
| Conexión sin TLS | `render.sh sin-ssl` **falla**: `FATAL: SSL/TLS required` |
| Privilegios de `bodegas_api` | `CREATE TABLE` → `permission denied for schema bodegas`; `UPDATE stock_sala` → `permission denied for table stock_sala`; `CREATE ROLE` → `permission denied to create role` |
| El administrador no entra a los datos | Después del bootstrap, `bodegas_admin` recibe `permission denied for database … User does not have CONNECT privilege` |
| CORS, origen ajeno (`https://ejemplo-malicioso.com`) | 400, sin `access-control-allow-origin` |
| CORS, origen del front | 200, con `access-control-allow-origin: https://bodegas-front-cq6q.onrender.com` |
| CORS, el mismo origen en `http` | 400 (se rechaza) |
| **RN-09 desde la API pública** | `POST /comprobantes` con un vino sin stock → `409 · RN-09: stock insuficiente del vino 12 en la sala 1.`; los conteos de las 31 tablas, antes y después, **idénticos** |
| **RN-09 desde el front público** (R13) | La pantalla de venta muestra `409 · P0001`, `RN-09: stock insuficiente del vino 12 en la sala 1.` y `No se registró ningún comprobante.`; conteos idénticos. Captura: `docs/img/nube/venta_sin_stock_rn09.png` |
| Acceso externo con la lista de IPs vacía (R5, R12) | `render.sh tamano` **falla** (`SSL connection has been closed unexpectedly`) y la API y el front siguen en 200: la API entra por la red privada |

### 6.5 Backup y restauración (#70)

- `render.sh backup`: `pg_dump -Fc` del esquema `bodegas`, 1,3 MB.
- `render.sh restaurar`: base nueva local con los mismos roles, `pg_restore` como propietario y comparación con Render: **"Conteos IDÉNTICOS" en las 31 tablas**. Además, las **huellas de contenido** de `db/seed/hashes.sql` son idénticas en las 30 tablas que tienen huella.

### 6.6 Bitácora de la lista de IPs de la base

La lista de IPs de `bodegas-db` empezó y terminó **vacía**. Horas aproximadas, de Argentina, del 10/11/2026:

| Hora | Acción |
|---|---|
| Antes de las 23:01 | Lucas agrega `132.255.114.196/32`, la IP que informa `ifconfig.me` |
| Alrededor de las 23:21 | Agrega `132.255.114.0/24` (ver 6.7): con la `/32` Render cortaba el handshake TLS |
| Antes de las 23:49 | Borra las dos reglas: la lista queda vacía. A las 23:49 `render.sh tamano` falla y la API y el front siguen respondiendo |

### 6.7 Qué se encontró y cómo se resolvió

- **La IP de la PC cambia por conexión.** El proveedor de internet reparte salida entre varias IPs públicas: en pocos segundos la misma PC se vio como `132.255.114.196`, `.82`, `.168`, `.108` y `.142`. Una regla `/32` casi nunca coincidía con la IP que veía Render, que cortaba el TLS. Se resolvió con el bloque `/24`, temporal. **Cómo notarlo:** `curl https://checkip.amazonaws.com` varias veces; Amazon es el proveedor de Render.
- **Nombre real de la base.** Render escribe `POSTGRES_DB` con un sufijo (`bodegas_xxxx`); `render.env` lleva el nombre que muestra Connections, no `bodegas`.
- **`RENDER_ADMIN_PASSWORD` es la contraseña del dashboard**, no la URL ni un valor propio. La primera era de 10 caracteres y fue rechazada; la de Render tiene 32.
- **Las variables nuevas necesitan un deploy.** El `config.js` del front se genera al construirlo, y el CORS de la API se lee al arrancar: tras cambiar `API_BASE_URL` y `CORS_ORIGINS` hubo que redesplegar los dos servicios.
- **Las URLs que publicaba el README no eran de este proyecto.** `bodegas-front.onrender.com` y `bodegas-api.onrender.com` pertenecen a otras cuentas: el nombre de un servicio de Render es único y, si está tomado, se agrega un sufijo. Las URLs reales salen del dashboard.
- **`render.sh restaurar` fallaba en una base nueva.** Con `--clean`, `pg_restore` intenta desarmar una vista antes de crear el tipo que usa (`estado_documento`) y falla. El error era inofensivo pero cortaba el script. Ahora borra el esquema vacío y restaura con `--exit-on-error`.

## Fuentes

- [Render: Deploy for Free (límites del plan gratis)](https://render.com/docs/free)
- [Render: Create and Connect to Render Postgres (versiones, IP rules, TLS)](https://render.com/docs/postgresql-creating-connecting)
- [Render: cambios de planes de agosto de 2026 (reseña)](https://jwatte.com/blog/render-com-platform-review/)
- [Neon: límites del plan gratis](https://neon.com/faqs/free-plan-limits-and-quotas)
- [Neon: IP Allow (plan Scale)](https://neon.com/docs/introduction/ip-allow)
- [Azure for Students](https://azure.microsoft.com/en-us/free/students)
- [Oracle Cloud Always Free: límites 2026](https://space-node.net/blog/oracle-cloud-always-free-limits-2026)
