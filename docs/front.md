# Etapa 7 · Front

Plan de trabajo y contrato de la etapa. Los bocetos (paso 1 de la consigna) están en [`docs/bocetos/`](bocetos/); cada uno anota en rojo la ruta de la API que alimenta cada parte y los mensajes reales que devuelve la base.

## 1. Qué pide la consigna

> Objetivo: ver cómo el dato viaja desde la base hasta la pantalla y cómo las reglas de la base se perciben desde el usuario. El foco no es el diseño visual.

Pasos:

1. Boceto de cada pantalla.
2. Estructura en `front/` y una capa que concentre las llamadas a la API, con la URL base configurable.
3. Implementar las pantallas, del catálogo al tablero.
4. Mostrar los errores de las reglas **tal como los devuelve la API**.
5. Verificar que el front no calcula totales, descuentos ni stock.
6. Front en `docker-compose.yml`. Ya está desde la Etapa 0 (servicio `front`, Nginx con `/api/*` hacia la API).

Criterios de aceptación:

- [x] Las cinco pantallas funcionan contra la API real.
- [x] Una venta sin stock muestra el mensaje de la regla y no deja datos a medias.
- [x] El front no contiene lógica de cálculo de importes ni de stock.

Verificados con pruebas automáticas y con su evidencia en el [informe de cierre](cierre_etapa7.md).

Rúbrica: 5 puntos. *Pantallas mínimas funcionando, errores de reglas visibles, sin lógica de cálculo en el cliente.*

## 2. Pantallas, rutas de la API y errores esperados

| Pantalla (boceto) | Ruta del front | Lee | Escribe | Errores que debe mostrar |
|---|---|---|---|---|
| [Catálogo](bocetos/b1-catalogo.png) | `#/vinos` | `GET /vinos` (filtros y paginación), `GET /vinos/{cod}`, catálogos | `DELETE /vinos/{cod}` | 409 `23503` al borrar un vino con ventas o historia de precios; 404 |
| [Alta y edición de vino](bocetos/b2-vino.png) | `#/vinos/nuevo`, `#/vinos/{cod}/editar` | `GET /vinos/{cod}`, catálogos | `POST /vinos`, `PUT /vinos/{cod}` | 409 `P0001` RN-05 (la composición no suma 100); 422 `23514` (precio, graduación, volumen); 409 `23505` (vino repetido); 422 `validacion` |
| [Nueva venta](bocetos/b3-venta.png) | `#/venta` | `GET /clientes/{id}`, `GET /vinos/{cod}`, `GET /catalogos/salas` | `POST /comprobantes` | 409 `P0001` RN-09 (stock insuficiente), RN-08 (vino repetido, sin renglones); 422 `dato_invalido` (vino inexistente); 422 `23503` (cliente o sala) |
| [Transferencias](bocetos/b4-transferencias.png) | `#/transferencias`, `#/transferencias/{nro}` | `GET /transferencias/{nro}`, `GET /catalogos/salas`, `GET /vinos/{cod}` | `POST /transferencias`, `…/renglones`, `…/terminar`, `…/procesar` | 409 `P0001` RN-11 (sin renglones, sin stock en el depósito), RN-12 (ya no está en confección); 409 `23505` (vino repetido) |
| [Tablero](bocetos/b5-tablero.png) | `#/tablero` | `GET /reportes/top-vinos?limite=10`, `GET /reportes/ventas-por-sala`, `GET /reportes/vinos-sin-stock?id_sala=`, `GET /catalogos/salas` | — | 404 sala inexistente; 503 si la base no responde |

Todas las respuestas de error tienen la forma `{detail, codigo, restriccion?}` (`docs/api.md` §3). El front muestra `detail` sin reescribirlo, junto con el código HTTP y `codigo`.

## 3. Hueco en la API: catálogos para los selectores

Los filtros del catálogo, la composición del vino, los maridajes y la elección de sala necesitan listas de cepas, bodegas, maridajes y salas. La API de la Etapa 6 no las expone, y el front no debe tener IDs fijos en el código. Se agregan rutas de **sólo lectura**:

| Ruta | Respuesta |
|---|---|
| `GET /catalogos/tipos-vino` | `["tinto", "blanco", "rosado", "espumante"]`, desde `TipoVino` de `api/app/esquemas.py`, que replica el `CHECK` de `vino.tipo` |
| `GET /catalogos/cepas` | `[{id_cepa, nombre, tipo}]` por nombre |
| `GET /catalogos/bodegas` | `[{cuit, razon_social}]` por razón social |
| `GET /catalogos/maridajes` | `[{id_maridaje, nombre, temperatura_servicio_c}]` por nombre |
| `GET /catalogos/salas` | `[{id_sala, calle, numero, localidad}]` por `id_sala` |

No hace falta paginarlas: son tablas de referencia chicas (15 cepas, 20 bodegas, 8 maridajes, 40 salas en la carga completa).

**No requieren migración**: `007_roles.sql` ya otorga a `bodegas_rw` `SELECT` sobre `cepa`, `bodega`, `maridaje`, `sala_venta` y `localidad`. La próxima migración sigue siendo `011` y no se necesita.

Clientes (20.000) y vinos (600) no entran en un selector. En la venta y en las transferencias se cargan **por código** y se confirman con `GET /clientes/{id}` o `GET /vinos/{cod}`, que muestran nombre y datos. Un buscador por nombre sería una mejora, no un requisito, y se descarta para esta etapa.

## 4. Estructura del front

```text
front/
├── index.html          estructura común: navegación, indicador de salud y <main> donde se dibuja cada pantalla
├── config.js           window.BODEGAS_CONFIG = { apiBase: "/api" } — única URL base, reemplazable al desplegar
├── styles.css
├── js/
│   ├── api.js          ÚNICA capa con fetch(): una función por ruta, ErrorApi {status, codigo, detail, restriccion}
│   ├── ui.js           mostrar errores y avisos, formato de moneda y fecha (Intl), helpers del DOM
│   ├── router.js       ruteo por hash (#/vinos, #/venta, …): sin servidor ni frameworks
│   └── pantallas/      catalogo.js, vino.js, venta.js, transferencias.js, tablero.js
├── nginx.conf          ya existe: sirve los estáticos y reenvía /api/* a la API
└── Dockerfile          copiar también config.js y js/
```

Decisiones:

- **HTML, CSS y JavaScript sin frameworks** (regla de `AGENTS.md`), con módulos ES nativos (`<script type="module">`). No hay build ni dependencias de npm.
- **Ruteo por hash.** Las pantallas son vistas del mismo `index.html` y Nginx no necesita reglas nuevas. Los filtros y la página del catálogo quedan en la URL, así que *Atrás* y *recargar* funcionan.
- **URL base configurable** en `config.js`. En local es `/api`, el mismo origen a través de Nginx, sin CORS. En la Etapa 8 el contenedor puede generar ese archivo desde una variable de entorno.
- **Gráfico del tablero en SVG propio**, sin librerías. El largo de cada barra es una escala visual del total que manda la base, no un cálculo de negocio.

## 5. Lo que el front no hace

Regla de la consigna y de `AGENTS.md`: totales, descuentos y stock pertenecen a PostgreSQL.

| No hace | En su lugar |
|---|---|
| Sumar los porcentajes de la composición ni avisar antes de enviar | Muestra el error RN-05 que devuelve la base (trigger diferido) |
| Multiplicar precio × cantidad, aplicar descuentos ni sumar renglones | Antes de vender no muestra importes. Después muestra los de la respuesta de `POST /comprobantes`, guardados por `fn_registrar_venta` |
| Calcular o restar stock | Muestra `stock_total`, `stock_sala` o `stock_deposito` tal cual llegan |
| Decidir si una transición de estado es válida | Habilita botones según el `estado` recibido, como ayuda visual. Si se fuerza la llamada, la base la rechaza (RN-11, RN-12) y se muestra el mensaje |
| Convertir importes para operar | `precio` y los importes llegan como string decimal y sólo se formatean para mostrarlos |

Verificación: revisión del código buscando operaciones aritméticas sobre importes o stock (por ejemplo `grep -nE "[*+-] *(precio|cantidad|stock|total)" front/js`) y la prueba de venta sin stock de la sección 6.

## 6. Verificación de la etapa

- Pruebas de punta a punta con Playwright para Python contra un proyecto de Compose aislado, como `api/tests/ejecutar.sh`: volumen vacío, `ESCALA=0.1`, `down -v` al terminar. **Nunca contra el entorno por defecto.** Se corren con `front/tests/ejecutar.sh`. El navegador corre dentro de la red de Compose y abre `http://front`, en lugar de `http://localhost:<puerto>`: no depende del navegador ni de los puertos de cada equipo.
- Un recorrido por pantalla. Como mínimo:
  - el catálogo filtra y pagina;
  - alta con composición al 90 % muestra RN-05 y no crea el vino;
  - venta exitosa muestra los importes de la base;
  - **venta sin stock** muestra RN-09, y el número de comprobantes y el stock de esa sala no cambian;
  - transferencia recorre `en_confeccion → terminado → procesado`;
  - el tablero muestra las tres secciones.
- Capturas de cada pantalla para el informe, en `docs/img/front/`.
- Cierre en `docs/cierre_etapa7.md` con los tres criterios de la consigna marcados y su evidencia.

## 7. Issues

Una rama por issue desde `main` y un PR revisado por el otro integrante, como en la Etapa 6. Etiqueta `etapa-7`.

| Orden | Issue | Asignado | Depende de |
|---|---|---|---|
| 1 | #49 API: rutas de catálogo de sólo lectura | Lucas | — |
| 1 | #50 Base del front: estructura, `api.js`, URL configurable, ruteo y errores | Lucas | — |
| 2 | #51 Pantalla 1: catálogo de vinos | Dai | #49, #50 |
| 2 | #52 Pantalla 2: alta y edición de vino | Lucas | #49, #50 (mejor después de #51) |
| 2 | #53 Pantalla 3: nueva venta | Dai | #49, #50 |
| 2 | #54 Pantalla 4: transferencias | Lucas | #49, #50 |
| 2 | #55 Pantalla 5: tablero | Dai | #49, #50 |
| 3 | #56 Verificación y cierre | Dai | #51 a #55 |

#49 y #50 se pueden hacer en paralelo. Las cinco pantallas, también, una vez integrados esos dos.
