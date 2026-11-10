# Informe de cierre de la Etapa 7 — Front

Fecha: 2026-11-10
Rama: `feat/56-cierre-etapa7`
Commit base: `eedad26` (Merge PR #63)

Este informe cierra la Etapa 7 con los tres criterios de la consigna probados con evidencia reproducible. No agrega funcionalidades al front: convierte la verificación manual de cada pantalla en pruebas automáticas, audita que no haya cálculos de negocio y documenta lo que quedó pendiente.

---

## 1. Estado de los issues y los PRs (#49 a #56)

| Issue | Descripción | PR | Estado | Hecho por (según el PR y los `Co-Authored-By` de sus commits) |
|-------|-------------|----|--------|------------------------------------------------------------------|
| — | Preparación: bocetos y plan (`docs/front.md`) | #57 | Integrado | Lucas, con Claude Opus 5.5 |
| #49 | API: rutas `GET /catalogos/*` de sólo lectura | #58 | Integrado | Lucas, con Claude Opus 5.5 |
| #50 | Base del front: `api.js`, URL configurable, ruteo y errores | #59 | Integrado | Lucas (los commits no registran coautor) |
| #51 | Pantalla 1: catálogo de vinos | #60 | Integrado | Lucas, con Claude Opus 5.5 |
| #52 | Pantalla 2: alta y edición de vino | #61 | Integrado | Lucas, con Claude Opus 5.5 |
| #53 | Pantalla 3: nueva venta | #62 | Integrado | Iniciada con Codex y terminada con Claude Opus 5.5 (lo dice el cuerpo del PR) |
| #54 | Pantalla 4: transferencias | #64 | Integrado | Lucas, con Claude Sonnet 5.5 |
| #55 | Pantalla 5: tablero | #63 | Integrado | Lucas, con Claude Sonnet 5.5 |
| #56 | Verificación y cierre (este informe) | #65 | En revisión | Lucas, con Claude Sonnet 5.5 |

Los issues #49 a #55 están cerrados. El #56 se cierra con el PR de este informe (`Closes #56`). Todos los commits están a nombre del usuario git `Lucas`: la columna "hecho por" sólo registra lo que consta en los PRs y en los trailers.

---

## 2. Los tres criterios de la consigna

| # | Criterio (`docs/front.md` §1) | Estado | Evidencia |
|---|-------------------------------|--------|-----------|
| 1 | Las cinco pantallas funcionan contra la API real | ✅ | 25 pruebas con Playwright en el navegador (sección 3) que recorren las cinco pantallas, contra la API real a través de nginx, en un proyecto aislado desde un volumen vacío |
| 2 | Una venta sin stock muestra el mensaje de la regla y no deja datos a medias | ✅ | `test_venta.py::test_una_venta_sin_stock_muestra_rn09_y_no_deja_datos_a_medias` (conteos abajo) |
| 3 | El front no contiene lógica de cálculo de importes ni de stock | ✅ | `test_sin_calculos.py` (8 casos) y la auditoría de la sección 4 |

### Criterio 2: conteos antes y después de la venta sin stock

La prueba arma una venta con un vino con stock (2 botellas) **primero** y uno sin stock en la sala después, y la registra desde la pantalla. El renglón con stock se procesa antes del que falla: su descuento de stock también tiene que revertirse. Las lecturas son `SELECT` con el rol de reportes.

| | Antes | Después |
|---|---|---|
| `count(*)` de `comprobante` | 15045 | **15045** |
| `count(*)` de `renglon_comprobante` | 54219 | **54219** |
| `stock_sala` del vino 1 en la sala 1 | 23 | **23** |

La pantalla mostró `409 · P0001` con *"RN-09: stock insuficiente del vino N en la sala 1."* y *"No se registró ningún comprobante."*, y la lista de renglones quedó cargada. Los valores salen de la última corrida de `front/tests/ejecutar.sh` desde un volumen vacío; los números absolutos dependen de la carga, la igualdad no. Captura: `docs/img/front/venta-sin-stock.png`.

---

## 3. Pruebas automáticas del front

**Cómo se corren:** `front/tests/ejecutar.sh`. Crea un proyecto de Compose aislado (`bodegas_front_pruebas`, puertos 18900 y 18980) desde un volumen vacío, lo carga con `ESCALA=0.1`, corre `docker compose --profile test run --build --rm front-test` y lo baja con `down -v`. Nunca toca el entorno por defecto: las pruebas crean vinos, ventas y transferencias.

**Cómo están armadas:**

- **Navegador dentro de la red.** El servicio `front-test` usa la imagen oficial `mcr.microsoft.com/playwright/python:v1.49.1-noble` (Chromium incluido; el paquete `playwright` tiene la misma versión) y abre `http://front`. Llama a `/api` por el mismo origen, a través de nginx, como en producción.
- **Diferencia con el issue.** El issue #56 decía "abren `http://localhost:<puerto>`". Se eligió el navegador dentro de la red porque no depende del navegador ni de los puertos del equipo de cada integrante: Edge 157 dejó de arrancar con `playwright-core` en la máquina donde se desarrolló el #54, y estas pruebas no se ven afectadas.
- **Verificación en la base con un rol de sólo lectura.** El servicio usa `DB_REPORT_USER` (grupo `bodegas_ro`), nunca el propietario ni la cuenta de inicialización; la sesión además abre con `default_transaction_read_only`. No hizo falta cambiar privilegios ni crear una migración. Toda escritura pasa por el front y la API.
- **Datos buscados con `SELECT`.** Cliente, sala, vino con stock, vino sin stock en la sala, vino de corte y depósito chico se buscan en la carga, nunca con ids fijos (la carga cambia con `FECHA_REFERENCIA`). Las pruebas que modifican stock los buscan dentro de la propia prueba, así que no dependen del orden: también pasan con los archivos en orden inverso y repetidas sobre la misma base.
- **Capturas ante una falla** en `front/tests/salida/`, que está en `.gitignore`. Se comprobó con una prueba temporal que falla a propósito (no versionada): dejó `test-failed-1.png`, una captura real de la pantalla, en `front/tests/salida/resultados/` del equipo.

| Archivo | Pruebas | Qué verifica |
|---|---|---|
| `test_navegacion.py` | 3 funciones, 7 casos | Las cinco pestañas cargan su pantalla y ninguna dice "pendiente"; `aria-current` sólo en la activa; el indicador de salud dice "disponible"; con un 503 simulado en `/api/salud` pasa a "no disponible" y se recupera con *Reintentar* |
| `test_catalogo.py` | 6 | Filtro por cepa y combinado (tipo + cepa) con el mismo `total` que `GET /api/vinos`; filtro sin resultados; la paginación llega a la última página sin repetir vinos; el detalle de un vino de corte muestra sus cepas y porcentajes; `ver=999999` muestra el 404 y deja el listado |
| `test_vino.py` | 3 | **Alta con 85 % + 5 %: muestra RN-05 y el vino no existe** (`SELECT` por nombre único); alta 60 + 40 con dos maridajes que lleva a la ficha; editar sólo el precio: la ficha muestra el precio nuevo y `auditoria_precio` pasa de 0 a 1 fila (RN-13) |
| `test_venta.py` | 2 | Venta válida: renglones y totales de la pantalla iguales a `GET /api/comprobantes/{nro}` y a la base; **venta sin stock** (RN-09), con los conteos de la sección 2 |
| `test_transferencias.py` | 3 | Recorrido `en_confeccion → terminado → procesado` con los botones habilitados de cada estado; al procesar, `stock_sala` sube y `stock_deposito` baja 5; procesar con más botellas que el depósito: RN-11, sigue terminada y el stock no cambia; terminar sin renglones: RN-11 |
| `test_tablero.py` | 4 | Top 10 igual a `reportes/top-vinos`; una barra por sala, la primera es la de `items[0]` y la de mayor ancho; vinos sin stock de una sala con las filas de la API; un 503 en `top-vinos` deja visibles las otras dos secciones |
| `test_sin_calculos.py` | 5 funciones, 8 casos | Prueba estática del criterio 3 (sección 4) |
| **Total** | **26 funciones, 33 casos** | 25 casos en el navegador (Playwright) y 8 de la prueba estática |

**Resultados** (desde un volumen vacío):

| Suite | Resultado | Duración |
|---|---|---|
| `front/tests/ejecutar.sh` | **33 passed** (25 en el navegador y 8 estáticas) | 1 min 10 s (pytest: 11 s) |
| `api/tests/ejecutar.sh` | **261 passed** | 1 min 5 s |

La suite de la API sigue completa: eran 252 al cerrar la Etapa 6 y 261 desde el issue #49 (las rutas de catálogo).

**Las pruebas pueden fallar.** Se probó con una mutación: se agregó a `venta.js` `const subtotal = renglon.precio_unitario * renglon.cantidad;`, un `parseFloat` y un `innerHTML`. La prueba estática falló en cuatro casos, y el archivo se revirtió.

**No se encontró ningún bug en las pantallas.** Los fallos de la primera corrida fueron de los selectores de las propias pruebas (el `aria-label` del logo coincide con "Bodega" y el texto de una fila no lleva espacios entre celdas).

---

## 4. Auditoría "sin cálculos" (criterio 3)

La prueba `test_sin_calculos.py` analiza `front/js` (montado en sólo lectura) **sin comentarios ni textos**, así que una fórmula escrita en un comentario no cuenta. Aplica dos reglas con una lista explícita de excepciones:

1. **`fetch(` sólo en `api.js`**, y ningún `innerHTML`, `alert(`, `confirm(` ni `parseFloat` en `front/js`.
2. **Toda operación aritmética está listada con su motivo.** Si aparece una nueva, la prueba falla hasta que alguien la justifique; si una listada desaparece, también falla. Una segunda regla impide que una línea que nombre precio, subtotal, descuento, total, porcentaje, stock, cantidad, importe o botellas opere sobre ellos, salvo dos justificadas.

**Resultado:** el front tiene 17 líneas con operadores aritméticos. Ninguna calcula un importe, un descuento, un porcentaje ni el stock.

| Archivo | Operación | Motivo |
|---|---|---|
| `catalogo.js` | `(estado.pagina - 1) * LIMITE` | Paginación: de número de página a filas que se saltean |
| `catalogo.js` | `Math.ceil(total / limite)` | Paginación. `total` es la **cantidad de vinos** que devuelve la API, no un importe. **Nombra "total"**, por eso está además en la lista de la segunda regla |
| `catalogo.js` | `pagina - 1`, `pagina + 1` | Botones Anterior y Siguiente |
| `catalogo.js` | `COLUMNAS.length + 1` | Ancho de la fila de aviso (cantidad de columnas de la tabla) |
| `tablero.js` | `Number(sala.total_ventas) / maximo * ANCHO_ESCALA` | **Escala visual del gráfico**: cuántos píxeles mide la barra. El importe que se lee es el string que guardó la base. **Nombra "total"** y está en la lista de la segunda regla |
| `tablero.js` | `indice * ALTO_FILA`, `items.length * ALTO_FILA` | Geometría del gráfico: altura de cada fila y alto del `viewBox` |
| `tablero.js` | `indice + 1` | Posición en el ranking que ordenó la base |
| `tablero.js` | `+ "en el último trimestre…"` | Concatenación de dos textos del `aria-label` del gráfico |
| `tablero.js`, `venta.js`, `router.js` | `++solicitud`, `solicitudCliente += 1`, `++solicitudCliente`, `++versionNavegacion` | Contadores para descartar respuestas viejas |
| `vino.js` | `indice + 1` | Número de fila de la composición, para sus etiquetas accesibles ("Cepa 1") |
| `router.js` | `separador === -1`, `slice(separador + 1)` | Separar la ruta de la consulta del hash |

**Contraste con la auditoría previa** (hecha sobre `main` antes de este issue):

- Se confirmaron las líneas de `catalogo.js` (228 y 246), de `tablero.js` (138, 143 y 164) y de `venta.js` (308).
- `ui.js` línea 85, `MONEDA.format(Number(valor))`, **no contiene ninguna operación**: sólo convierte para formatear, y el valor no se opera.
- La tabla previa no incluía las demás líneas (posiciones, contadores, `pagina ± 1`, `colSpan`, el hash). No tocan importes ni stock.
- `Number(input.value)` aparece en varias pantallas para convertir códigos y cantidades ingresados a enteros del cuerpo JSON: es una conversión, no una operación. Los importes, graduaciones y porcentajes viajan como string, tal como se escribieron.

**Límite de la prueba:** la regla por palabras clave mira los identificadores. Una cuenta sobre una variable de nombre genérico (por ejemplo `valor + 1`) sólo se detecta porque la regla 2 exige justificar **toda** operación aritmética, no sólo las que nombran importes. Por eso la lista incluye también las inofensivas.

---

## 5. Pantalla → rutas de la API → reglas de la base que se ven

| Pantalla | Lee | Escribe | Reglas de la base que se ven en pantalla |
|---|---|---|---|
| Catálogo `#/vinos` | `GET /vinos`, `GET /vinos/{cod}`, `GET /catalogos/*` | `DELETE /vinos/{cod}` | RN-14: un vino con ventas o historia de precios no se borra (409 `23503`, mostrado tal cual) |
| Alta y edición `#/vinos/nuevo`, `#/vinos/{cod}/editar` | `GET /vinos/{cod}`, `GET /catalogos/*` | `POST /vinos`, `PUT /vinos/{cod}` | **RN-05** (la composición suma 100 %), **RN-13** (auditoría del precio), `23514` (precio, graduación, volumen), `23505` (vino repetido) |
| Nueva venta `#/venta` | `GET /clientes/{id}`, `GET /vinos/{cod}`, `GET /catalogos/salas` | `POST /comprobantes` | RN-06 (el descuento que calcula `fn_descuento_cliente`), **RN-08** (vino repetido, sin renglones), **RN-09** (stock insuficiente) |
| Transferencias `#/transferencias`, `#/transferencias/{nro}` | `GET /transferencias/{nro}`, `GET /vinos/{cod}`, `GET /catalogos/salas` | `POST /transferencias`, `…/renglones`, `…/terminar`, `…/procesar` | **RN-11** (terminar sin renglones, procesar sin stock en el depósito), **RN-12** (la transferencia ya no está en confección), `23505` (vino repetido) |
| Tablero `#/tablero` | `GET /reportes/top-vinos`, `/ventas-por-sala`, `/vinos-sin-stock`, `GET /catalogos/salas` | — | 404 (sala inexistente), 503 (la base no responde) |

**Qué reglas cubre una prueba automática y cuáles se verificaron a mano:**

| Regla | Cubierta por | 
|---|---|
| RN-05 | `test_vino.py` (automática) |
| RN-13 | `test_vino.py` (automática) |
| RN-09 | `test_venta.py` (automática) |
| RN-11 | `test_transferencias.py` (automática: terminar sin renglones y procesar sin stock) |
| RN-08 | Verificada a mano en el PR #62; **no tiene prueba automática en el front** (sí en `api/tests`) |
| RN-12 | Verificada a mano en el PR #64, con dos pestañas; **no tiene prueba automática en el front** (sí en `api/tests`) |
| RN-14 (409 al eliminar) | Verificada a mano en el PR #60; **no tiene prueba automática en el front** (sí en `api/tests`) |

---

## 6. Verificación de arranque desde un volumen vacío

`AGENTS.md` pide verificar configuración, arranque y healthchecks antes de cerrar una etapa. Se levantó un proyecto aislado nuevo (`-p bodegas_cierre`, puertos 19000 y 19080), con `down -v` antes y después:

```bash
docker compose --project-directory <repo> --env-file .env.example -p bodegas_cierre up -d --build --wait
```

| Servicio | Estado |
|---|---|
| `db` | Up, healthy |
| `migrate` | Exited (0) |
| `api` | Up, healthy |
| `front` | Up, healthy |

- **Migraciones:** 10 aplicadas (001 a 010).
- **`GET /salud`:** `{"estado":"ok","base_de_datos":"disponible"}`, 200, tanto directo (puerto 19000) como por el proxy (`/api/salud`, puerto 19080).
- **Front:** `GET /` y los módulos de las pantallas responden 200.

---

## 7. Capturas

En `docs/img/front/`: las cinco pantallas, los tres errores de regla que pide el plan (RN-05, RN-09 y RN-11) y las variantes angostas.

| Captura | Qué muestra |
|---|---|
| `catalogo.png`, `catalogo-409.png`, `catalogo-angosta.png` | Ficha de un vino de corte; el 409 `23503` al eliminar un vino con ventas; la vista a 390 px |
| `vino-rn05.png`, `vino-edicion.png`, `vino-angosta.png` | **El error RN-05** al guardar 85 % + 5 %; la edición precargada; la vista a 390 px |
| `venta.png`, `venta-sin-stock.png` | El comprobante con los importes de la base; **el error RN-09** |
| `transferencias.png`, `transferencias-sin-stock.png`, `transferencias-angosta.png` | La ficha en confección; **el error RN-11** al procesar sin stock; la vista a 390 px |
| `tablero.png` | Las tres secciones del tablero |

Se revisó que cada captura sea igual o posterior al último cambio de su pantalla. **Sólo `tablero.png` estaba vieja** (mostraba el encabezado "N.º", que cambió después) y se regeneró en un proyecto aislado.

---

## 8. Decisiones para defender

- **Ruteo por hash.** Las cinco pantallas son vistas del mismo `index.html`: Nginx no necesita reglas nuevas ni un servidor de aplicaciones, y *Atrás*, *Adelante* y *recargar* funcionan porque filtros, página y ficha abierta viven en la URL.
- **Una sola capa `api.js`.** Es la única que usa `fetch`: la URL base sale de `config.js`, los decimales se conservan como string y todo error se traduce a un `ErrorApi`, de modo que ninguna pantalla puede inventar su propio mensaje. La prueba estática lo verifica.
- **Clientes y vinos se cargan por código.** Son 20.000 clientes y 600 vinos: un selector con todos no es usable. Se confirman con `GET /clientes/{id}` o `GET /vinos/{cod}`, que muestran nombre y datos. Un buscador por nombre sería una mejora, no un requisito.
- **Los botones según el estado no reemplazan a la base.** Habilitar o deshabilitar es una ayuda visual a partir del `estado` que devolvió la API. La transición la decide PostgreSQL (RN-11 y RN-12, en `sp_terminar_transferencia`, `sp_procesar_transferencia` y los triggers de estado y de renglones). Si alguien fuerza la llamada, la base la rechaza y el error se muestra tal cual; es lo que prueba el caso de las dos pestañas del PR #64.
- **La escala del gráfico no es un cálculo de negocio.** `Number(total_ventas) / maximo * ANCHO_ESCALA` sólo decide cuántos píxeles mide la barra, para que la más larga ocupe un ancho fijo. El importe que se lee es el string que guardó la base, formateado sin operar, y el máximo es `items[0]` porque la API ordena de mayor a menor (la prueba lo comprueba contra la API).
- **Las rutas de catálogo no necesitaron una migración.** `007_roles.sql` ya otorgaba `SELECT` a `bodegas_rw` sobre `cepa`, `bodega`, `maridaje`, `sala_venta` y `localidad`. Los tipos de vino salen de `TipoVino`, que replica `CHECK (tipo IN …)`, para que el front no escriba la lista a mano. Las listas no se paginan: son tablas de referencia de tamaño fijo.
- **Los cálculos de dinero y stock son de PostgreSQL.** El front muestra `fn_registrar_venta`, `fn_descuento_cliente` y `sp_procesar_transferencia`; no los repite. Por eso la prueba estática exige justificar toda operación aritmética.

---

## 9. Incidencias del proceso

- **Finales de línea CRLF en el #53.** El trabajo en curso de la pantalla de venta apareció en la copia local con CRLF por `core.autocrlf=true`, y el `git diff` parecía mostrar cientos de líneas cambiadas. Dentro del repositorio todo estaba en LF (`git ls-files --eol`), así que no hizo falta reescribir archivos. Se agregó a `.gitattributes` `eol=lf` para `*.js`, `*.css`, `*.html`, `*.md` y `*.py`, y `git add --renormalize .` no cambió ningún otro archivo.
- **Bug de las salas en el #53.** `replaceChildren` no aplana arrays, a diferencia de `crear()`: las salas llegaban como el texto `[object HTMLOptionElement],…` y no se podía elegir ninguna, así que tampoco vender. Lo encontró la verificación en un navegador real. Desde entonces las pantallas usan spread (`...lista`).
- **Flechas de estado en el #54.** La revisión de las capturas mostró que los tres pasos no entraban en una fila y la flecha quedaba sola al final. Se corrigió antes del PR.
- **Edge 157 no arranca con `playwright-core`** (1.48 y 1.52, con las variantes sin ventana probadas) en la máquina de desarrollo. La causa no se investigó. Las verificaciones del #51 al #53 se hicieron en Edge y las del #54 en Chrome; las pruebas de este issue usan el Chromium de la imagen de Playwright.
- **Una captura vieja** (`tablero.png`) detectada en la revisión de este issue.

---

## 10. Pendientes y limitaciones conocidas

| Tema | Estado |
|---|---|
| **Revisión cruzada** | **No registrada en GitHub.** En los PRs #57 a #64 se pidió revisión a 21dai y sigue pendiente: ninguno tiene una revisión ni comentarios, y los integró su autor (Lukillas09). `AGENTS.md` exige "un PR revisado por otro integrante antes del merge". No se fabrican revisiones retroactivas: queda por hacer que 21dai revise el código ya integrado, o registrar dónde se hizo la revisión. Este PR también la pide |
| Sin buscador por nombre | Clientes y vinos se cargan por código. Mejora posible, no requisito |
| `vinos-sin-stock` no se pagina | La API devuelve todas las filas (unas 500 para la sala 1 en la carga completa) y el tablero las muestra en un contenedor con scroll. Si hiciera falta, se agregaría `limite`/`desplazamiento` |
| Criterio de `min` en la cantidad | La venta (#53) usa `min="1"`; las transferencias (#54) no, para que el 422 `23514` llegue a la base. Es una decisión abierta entre las dos pantallas |
| Pruebas con un solo navegador | Las pruebas corren en Chromium. No se probó con un lector de pantalla real ni en Firefox o Safari |
| Reglas sin prueba automática en el front | RN-08, RN-12 y RN-14 se verificaron a mano en sus PRs (sección 5); tienen prueba en `api/tests` |
| Fechas en UTC | La base corre en UTC: una transferencia o un comprobante creado después de las 21 h de Argentina muestra la fecha del día siguiente. Decisión pendiente para la Etapa 8 |
| Sin autenticación | Las escrituras de la API no piden credenciales (extra opcional según el PDF). Hay que resolverlo antes de publicar la API |
| Preguntas abiertas a la cátedra | Alcance de la trazabilidad y `POST /ingresos/{cod}/terminar` (`docs/api.md` §6) |
| Despliegue en la nube (Etapa 8) | **No iniciado.** Requiere instrucción explícita |

---

## 11. Documentación actualizada en este issue

- `docs/front.md`: los tres criterios de §1 marcados, con enlace a este informe, y una nota en §6 sobre el navegador dentro de la red.
- `README.md`: cómo usar el front, cómo correr `front/tests/ejecutar.sh` y el conteo de pruebas.
- `docs/requisitos.md` §3.9: la Etapa 7 pasa a completada.
- `AGENTS.md`, "Alcance de la etapa actual": la Etapa 7 está completada; se mantienen sus reglas como reglas vigentes del front.

---

## 12. Conclusión

**La Etapa 7 (front) está completa y verificada.**

- Las cinco pantallas funcionan contra la API real: 25 pruebas de punta a punta en el navegador, en un proyecto aislado desde un volumen vacío (más 8 estáticas: 33 en total).
- Una venta sin stock muestra RN-09 y no deja datos a medias: 15045 → 15045 comprobantes, 54219 → 54219 renglones y el stock del vino sin cambios.
- El front no calcula importes ni stock: toda operación aritmética está justificada y una prueba falla si aparece una nueva.
- La API sigue completa: 261 pruebas.
- Queda pendiente la revisión cruzada de 21dai sobre los PRs ya integrados (sección 10). La Etapa 8 (nube) no se empezó.
