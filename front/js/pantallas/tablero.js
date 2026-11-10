// Pantalla 5: tablero (issue #55, boceto docs/bocetos/b5-tablero.png).
//
// Sólo lee: muestra los reportes S1, S8 y S6 tal como los devuelve la API.
// Cada sección se carga por su cuenta y atrapa sus propios errores, así que una
// que falle no impide ver las otras (y nunca llega un error al router, que
// reemplazaría toda la vista).

import { api } from "../api.js";
import {
  crear,
  formatoFecha,
  formatoMoneda,
  limpiarMensajes,
  mostrarError,
} from "../ui.js";

const SVG_NS = "http://www.w3.org/2000/svg";

// Medidas del gráfico en unidades del viewBox; el SVG se escala al ancho del
// panel con CSS. Todo lo que se dibuja sale de estas constantes.
const ANCHO_SVG = 720;
const X_BARRAS = 240; // las barras arrancan después de la etiqueta
const ANCHO_ESCALA = 300; // largo de la barra más larga
const ALTO_FILA = 30;
const ALTO_BARRA = 18;
const Y_BARRA = 6; // la barra queda centrada en la fila
const Y_CENTRO = 15; // alto de la fila / 2: línea de centrado del texto

// crear() de ui.js arma elementos HTML y asigna propiedades del DOM; un SVG
// necesita el espacio de nombres propio y atributos (x, width, … son de sólo
// lectura como propiedades). Los nodos SVG sí se pueden pasar como hijos de crear().
function crearSvg(etiqueta, atributos = {}, ...hijos) {
  const elemento = document.createElementNS(SVG_NS, etiqueta);
  for (const [nombre, valor] of Object.entries(atributos)) {
    elemento.setAttribute(nombre, String(valor));
  }
  for (const hijo of hijos) {
    elemento.append(hijo instanceof Node ? hijo : document.createTextNode(String(hijo)));
  }
  return elemento;
}

// Un título que empieza con "#" es una columna numérica, alineada a la derecha.
function encabezadoTabla(...titulos) {
  return crear(
    "thead",
    {},
    crear(
      "tr",
      {},
      titulos.map((titulo) => titulo.startsWith("#")
        ? crear("th", { scope: "col", className: "numero" }, titulo.slice(1))
        : crear("th", { scope: "col" }, titulo)),
    ),
  );
}

function tabla(descripcion, titulos, filas) {
  return crear(
    "table",
    {},
    crear("caption", { className: "solo-lectores" }, descripcion),
    encabezadoTabla(...titulos),
    crear("tbody", {}, filas),
  );
}

// Esqueleto común de una sección: título, aviso de carga y zona de errores
// propia. mostrarError reemplaza el contenido de `mensajes`, por eso cada
// sección (y cada causa de error dentro de una sección) tiene el suyo.
function armarSeccion(idTitulo, titulo) {
  const mensajes = crear("div", { "aria-live": "polite" });
  const cargando = crear("p", { "aria-busy": "true" }, "Cargando…");
  const contenido = crear("div", { className: "tablero__contenido" });
  const seccion = crear(
    "section",
    { className: "panel tablero__seccion", "aria-labelledby": idTitulo },
    crear("h2", { id: idTitulo }, titulo),
    cargando,
    mensajes,
    contenido,
  );
  return { seccion, mensajes, cargando, contenido };
}

// --- 1. Top 10 vinos más vendidos (S1) ---------------------------------------

async function cargarTopVinos({ mensajes, cargando, contenido }) {
  try {
    const { items } = await api.topVinos(10);
    if (items.length === 0) {
      contenido.replaceChildren(crear("p", {}, "Todavía no hay ventas registradas."));
      return;
    }
    const filas = items.map((vino, indice) => crear(
      "tr",
      {},
      // La posición es el lugar en la lista que ordenó la base, no un dato de negocio.
      crear("td", { className: "numero" }, indice + 1),
      crear("td", {}, vino.nombre),
      crear("td", {}, vino.tipo),
      crear("td", {}, vino.bodega),
      crear("td", { className: "numero" }, formatoMoneda(vino.precio)),
      crear("td", { className: "numero" }, vino.total_botellas),
    ));
    contenido.replaceChildren(crear(
      "div",
      { className: "tabla-contenedor" },
      tabla(
        "Los 10 vinos con más botellas vendidas",
        ["##", "Vino", "Tipo", "Bodega", "#Precio", "#Botellas"],
        filas,
      ),
    ));
  } catch (error) {
    mostrarError(mensajes, error);
  } finally {
    cargando.remove();
  }
}

// --- 2. Ventas por sala del último trimestre (S8) ----------------------------

// Gráfico de barras horizontales: una fila por sala, en el orden de la API.
function graficoDeVentas(items) {
  // La API devuelve las salas de mayor a menor total_ventas (contrato de
  // ReporteVentasPorSala), así que la primera tiene el máximo: no se recorre
  // ni se suma nada para encontrarlo.
  const maximo = Number(items[0].total_ventas);

  const filas = items.map((sala, indice) => {
    const etiqueta = `Sala ${sala.id_sala} · ${sala.localidad}`;
    const importe = formatoMoneda(sala.total_ventas);
    // ESCALA VISUAL, no un dato de negocio: Number(total)/máximo*ANCHO_ESCALA sólo
    // decide cuántos píxeles mide la barra para que la más larga ocupe
    // ANCHO_ESCALA. El importe que se lee es el string que guardó la base,
    // formateado sin operar. Con máximo 0 (o no numérico) las barras miden 0.
    const largo = maximo > 0 ? (Number(sala.total_ventas) / maximo) * ANCHO_ESCALA : 0;

    return crearSvg(
      "g",
      // La fila se desplaza a su altura; dentro de ella todo usa coordenadas fijas.
      { transform: `translate(0 ${indice * ALTO_FILA})` },
      crearSvg("text", {
        class: "tablero__etiqueta", x: 0, y: Y_CENTRO, "dominant-baseline": "central",
      }, etiqueta),
      crearSvg(
        "rect",
        { class: "tablero__barra", x: X_BARRAS, y: Y_BARRA, width: largo, height: ALTO_BARRA },
        // Tooltip nativo y accesible con el importe exacto de la base.
        crearSvg("title", {}, `${etiqueta}: ${importe}`),
      ),
      crearSvg("text", {
        class: "tablero__importe", x: ANCHO_SVG, y: Y_CENTRO,
        "text-anchor": "end", "dominant-baseline": "central",
      }, importe),
    );
  });

  return crearSvg(
    "svg",
    {
      class: "tablero__grafico",
      viewBox: `0 0 ${ANCHO_SVG} ${items.length * ALTO_FILA}`,
      role: "img",
      "aria-label": "Gráfico de barras horizontales con el total de ventas de cada sala "
        + "en el último trimestre, de mayor a menor. Los importes exactos están en la tabla siguiente.",
    },
    ...filas,
  );
}

function tablaDeVentas(items) {
  const filas = items.map((sala) => crear(
    "tr",
    {},
    crear("td", { className: "numero" }, sala.id_sala),
    crear("td", {}, sala.localidad),
    crear("td", { className: "numero" }, sala.num_comprobantes),
    crear("td", { className: "numero" }, formatoMoneda(sala.importe_bruto)),
    crear("td", { className: "numero" }, formatoMoneda(sala.total_descuento)),
    crear("td", { className: "numero" }, formatoMoneda(sala.total_ventas)),
  ));
  return crear(
    "div",
    { className: "tabla-contenedor" },
    tabla(
      "Ventas por sala en el período, con los importes guardados",
      ["#Sala", "Localidad", "#Comprobantes", "#Bruto", "#Descuento", "#Total"],
      filas,
    ),
  );
}

async function cargarVentasPorSala({ mensajes, cargando, contenido }) {
  try {
    // Sin parámetros: el período (último trimestre) lo resuelve la base y viene en la respuesta.
    const { desde, hasta, items } = await api.ventasPorSala();
    const periodo = crear(
      "p",
      { className: "tablero__subtitulo" },
      `Período: ${formatoFecha(desde)} – ${formatoFecha(hasta)}`,
    );
    if (items.length === 0) {
      contenido.replaceChildren(periodo, crear("p", {}, "No hubo ventas en el período."));
      return;
    }
    contenido.replaceChildren(periodo, graficoDeVentas(items), tablaDeVentas(items));
  } catch (error) {
    mostrarError(mensajes, error);
  } finally {
    cargando.remove();
  }
}

// --- 3. Vinos sin stock en una sala (S6) -------------------------------------

function tablaSinStock(items) {
  const filas = items.map((vino) => crear(
    "tr",
    {},
    crear("td", { className: "numero" }, vino.cod_vino),
    crear("td", {}, vino.nombre),
    crear("td", {}, vino.tipo),
    crear("td", { className: "numero" }, `${vino.graduacion} %`),
    crear("td", { className: "numero" }, formatoMoneda(vino.precio)),
    crear("td", { className: "numero" }, vino.stock_sala),
    crear("td", { className: "numero" }, vino.stock_deposito),
  ));
  // La API no pagina y una sala puede tener unos 500 vinos: la lista completa
  // queda en un contenedor con altura máxima y scroll, sin recortarla.
  return crear(
    "div",
    { className: "tabla-contenedor tablero__scroll" },
    tabla(
      "Vinos sin stock en la sala elegida",
      ["#Cód.", "Vino", "Tipo", "#Graduación", "#Precio", "#Stock sala", "#Stock depósito"],
      filas,
    ),
  );
}

async function cargarVinosSinStock({ mensajes, cargando, contenido }) {
  // Dos zonas de error: el de las salas (que deja el selector inutilizable) no
  // debe borrarse con el de una consulta, y al revés.
  const mensajesConsulta = crear("div", { "aria-live": "polite" });
  // El conteo (o el aviso de lista vacía) es la única región viva: anunciar la
  // tabla de unas 500 filas completa sería inutilizable con un lector de pantalla.
  const resumen = crear("div", { "aria-live": "polite" });
  const resultado = crear("div");
  let solicitud = 0;

  const selectorSala = crear(
    "select",
    { id: "tablero-sala", name: "id_sala", required: true, disabled: true },
    crear("option", { value: "", selected: true, disabled: true }, "Cargando salas…"),
  );
  const botonConsultar = crear(
    "button",
    { type: "submit", className: "boton", disabled: true },
    "Consultar",
  );
  const formulario = crear(
    "form",
    { className: "acciones" },
    crear("label", { htmlFor: "tablero-sala" }, "Sala", selectorSala),
    botonConsultar,
  );
  contenido.replaceChildren(formulario, mensajesConsulta, resumen, resultado);

  selectorSala.addEventListener("change", () => {
    botonConsultar.disabled = selectorSala.value === "";
  });

  formulario.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    if (selectorSala.value === "") return;

    // Si el usuario consulta otra sala antes de que llegue la respuesta, la
    // anterior queda obsoleta y no pisa a la nueva.
    const actual = ++solicitud;
    botonConsultar.disabled = true;
    botonConsultar.textContent = "Consultando…";
    limpiarMensajes(mensajesConsulta);
    resumen.replaceChildren();
    resultado.replaceChildren();

    try {
      const { items } = await api.vinosSinStock(Number(selectorSala.value));
      if (actual !== solicitud) return;

      if (items.length === 0) {
        resumen.replaceChildren(crear("p", {}, "No hay vinos sin stock en esta sala."));
        return;
      }
      resumen.replaceChildren(
        crear("p", {}, `${items.length} ${items.length === 1 ? "vino" : "vinos"}`),
      );
      resultado.replaceChildren(tablaSinStock(items));
    } catch (error) {
      if (actual !== solicitud) return;
      // El 404 de una sala inexistente se muestra tal como llega.
      mostrarError(mensajesConsulta, error);
    } finally {
      if (actual === solicitud) {
        botonConsultar.textContent = "Consultar";
        botonConsultar.disabled = selectorSala.value === "";
      }
    }
  });

  try {
    const salas = await api.salas();
    // replaceChildren no acepta arrays (a diferencia de crear): por eso el spread.
    selectorSala.replaceChildren(
      crear("option", { value: "", selected: true, disabled: true }, "Seleccione una sala"),
      ...salas.map((sala) => crear(
        "option",
        { value: String(sala.id_sala) },
        `${sala.id_sala} · ${sala.calle} ${sala.numero} (${sala.localidad})`,
      )),
    );
    selectorSala.disabled = false;
  } catch (error) {
    selectorSala.replaceChildren(
      crear("option", { value: "", selected: true }, "No se pudieron cargar las salas"),
    );
    mostrarError(mensajes, error);
  } finally {
    cargando.remove();
  }
}

// --- Montaje ------------------------------------------------------------------

export async function montar(contenedor) {
  const top = armarSeccion("titulo-top", "Top 10 vinos más vendidos");
  const ventas = armarSeccion("titulo-ventas", "Ventas por sala · último trimestre");
  const sinStock = armarSeccion("titulo-sin-stock", "Vinos sin stock en una sala");

  contenedor.append(
    crear("h1", {}, "Tablero"),
    crear("div", { className: "tablero" }, top.seccion, ventas.seccion, sinStock.seccion),
  );

  // Las tres cargas corren en paralelo y ninguna rechaza: cada una atrapa su error.
  await Promise.all([
    cargarTopVinos(top),
    cargarVentasPorSala(ventas),
    cargarVinosSinStock(sinStock),
  ]);
}
