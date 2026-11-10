// Pantalla 1: catálogo de vinos (issue #51, boceto docs/bocetos/b1-catalogo.png).
//
// El estado vive en el hash (#/vinos?tipo=tinto&id_cepa=1&pagina=2&ver=12):
// filtrar, paginar, Ver y Cerrar sólo cambian location.hash y el router vuelve
// a montar la pantalla. Así Atrás y recargar conservan filtros, página y ficha.
// Precio, graduación, porcentajes y stock se muestran tal cual llegan de la
// API; sólo el precio pasa por formatoMoneda.

import { api } from "../api.js";
import { crear, formatoMoneda, mostrarAviso, mostrarError } from "../ui.js";

const LIMITE = 20;

// Catálogos ya obtenidos. Sobreviven a los remontajes por cambio de hash, así
// no se piden de nuevo en cada página. Un catálogo que falló no se guarda: se
// vuelve a intentar en el próximo montaje.
const catalogos = {};

// El aviso de "Vino eliminado." se muestra después del remontaje que provoca
// quitar `ver` del hash; el router limpia la vista antes de montar.
let avisoPendiente = null;

const ENTERO = /^-?\d+$/;
const ENTERO_POSITIVO = /^[1-9]\d*$/;
const CUIT = /^\d{11}$/;

// Lo que llega por URL se valida antes de usarlo; lo inválido se ignora. Los
// códigos quedan como texto: un BIGINT no entra entero en un Number.
function leerEstado(consulta) {
  const pagina = Number(consulta.pagina);
  return {
    tipo: consulta.tipo || "",
    id_cepa: ENTERO_POSITIVO.test(consulta.id_cepa ?? "") ? consulta.id_cepa : "",
    cuit_bodega: CUIT.test(consulta.cuit_bodega ?? "") ? consulta.cuit_bodega : "",
    anada: ENTERO.test(consulta.anada ?? "") ? consulta.anada : "",
    pagina: Number.isSafeInteger(pagina) && pagina >= 1 ? pagina : 1,
    ver: ENTERO_POSITIVO.test(consulta.ver ?? "") ? consulta.ver : "",
  };
}

function hashDe(estado) {
  const parametros = new URLSearchParams();
  for (const nombre of ["tipo", "id_cepa", "cuit_bodega", "anada"]) {
    if (estado[nombre]) parametros.set(nombre, estado[nombre]);
  }
  if (estado.pagina > 1) parametros.set("pagina", estado.pagina);
  if (estado.ver) parametros.set("ver", estado.ver);

  const cadena = parametros.toString();
  return cadena ? `#/vinos?${cadena}` : "#/vinos";
}

// Si el hash no cambia (por ejemplo, Filtrar con los mismos valores), el
// navegador no emite hashchange y la pantalla queda como está.
function irA(estado) {
  window.location.hash = hashDe(estado);
}

async function obtenerCatalogo(nombre, pedir) {
  if (!(nombre in catalogos)) catalogos[nombre] = await pedir();
  return catalogos[nombre];
}

// --- Filtros ------------------------------------------------------------------

function selector(nombre, textoVacio) {
  return crear("select", { name: nombre }, crear("option", { value: "" }, textoVacio));
}

function llenarSelector(select, opciones, valorActual) {
  for (const { valor, texto } of opciones) {
    select.append(crear("option", { value: valor }, texto));
  }
  // Un valor de la URL que no está en la lista (o la lista no cargó) se
  // conserva visible: el filtro se está aplicando aunque no tenga nombre.
  if (valorActual && !opciones.some((opcion) => opcion.valor === valorActual)) {
    select.append(crear("option", { value: valorActual }, `${valorActual} (no está en la lista)`));
  }
  select.value = valorActual;
}

async function cargarSelector(select, mensajes, { nombre, pedir, opcion, valorActual, etiqueta }) {
  let opciones = [];
  try {
    opciones = (await obtenerCatalogo(nombre, pedir)).map(opcion);
  } catch (error) {
    // Cada catálogo tiene su propio contenedor: mostrarError reemplaza el contenido.
    const zona = crear("div", { "aria-label": `Error al cargar ${etiqueta}` });
    mensajes.append(zona);
    mostrarError(zona, error);
  }
  llenarSelector(select, opciones, valorActual);
}

function armarFiltros(estado) {
  const tipo = selector("tipo", "Todos");
  const cepa = selector("id_cepa", "Todas");
  const bodega = selector("cuit_bodega", "Todas");
  const anada = crear("input", {
    type: "number", name: "anada", step: 1, inputMode: "numeric", value: estado.anada,
  });
  const mensajes = crear("div");

  const formulario = crear(
    "form",
    {
      className: "filtros rejilla",
      "aria-label": "Filtros del catálogo",
      onsubmit: (evento) => {
        evento.preventDefault();
        // Un filtro nuevo vuelve a la primera página; la ficha abierta se conserva.
        irA({
          tipo: tipo.value, id_cepa: cepa.value, cuit_bodega: bodega.value,
          anada: anada.value.trim(), pagina: 1, ver: estado.ver,
        });
      },
    },
    crear("label", {}, "Tipo", tipo),
    crear("label", {}, "Cepa", cepa),
    crear("label", {}, "Bodega", bodega),
    crear("label", {}, "Añada", anada),
    crear(
      "div",
      { className: "acciones" },
      crear("button", { type: "submit", className: "boton" }, "Filtrar"),
      crear("button", {
        type: "button",
        className: "boton boton--secundario",
        onclick: () => irA({ pagina: 1, ver: estado.ver }),
      }, "Limpiar"),
    ),
  );

  const cargar = () => Promise.all([
    cargarSelector(tipo, mensajes, {
      nombre: "tipos", pedir: () => api.tiposVino(), etiqueta: "los tipos",
      opcion: (valor) => ({ valor, texto: valor }), valorActual: estado.tipo,
    }),
    cargarSelector(cepa, mensajes, {
      nombre: "cepas", pedir: () => api.cepas(), etiqueta: "las cepas",
      opcion: (c) => ({ valor: String(c.id_cepa), texto: c.nombre }), valorActual: estado.id_cepa,
    }),
    cargarSelector(bodega, mensajes, {
      nombre: "bodegas", pedir: () => api.bodegas(), etiqueta: "las bodegas",
      opcion: (b) => ({ valor: b.cuit, texto: b.razon_social }), valorActual: estado.cuit_bodega,
    }),
  ]);

  const seccion = crear(
    "section",
    { className: "panel", "aria-labelledby": "titulo-filtros" },
    crear("h2", { id: "titulo-filtros" }, "Filtros"),
    formulario,
    mensajes,
  );
  return { seccion, cargar };
}

// --- Listado ------------------------------------------------------------------

const COLUMNAS = [
  ["Cód.", true], ["Nombre", false], ["Tipo", false], ["Añada", true],
  ["Vol. (ml)", true], ["Grad. (%)", true], ["Precio", true], ["Bodega", false],
];

function filaDeVino(vino, estado) {
  const seleccionado = String(vino.cod_vino) === estado.ver;
  return crear(
    "tr",
    { className: seleccionado ? "fila--seleccionada" : null },
    crear("td", { className: "numero" }, vino.cod_vino),
    crear("td", {}, vino.nombre),
    crear("td", {}, vino.tipo),
    crear("td", { className: "numero" }, vino.anada),
    crear("td", { className: "numero" }, vino.volumen_ml),
    crear("td", { className: "numero" }, vino.graduacion),
    crear("td", { className: "numero" }, formatoMoneda(vino.precio)),
    crear("td", {}, vino.bodega),
    crear(
      "td",
      {},
      crear("button", {
        type: "button",
        className: "boton boton--secundario boton--compacto",
        "aria-label": `Ver ${vino.nombre} (código ${vino.cod_vino})`,
        "aria-pressed": seleccionado ? "true" : "false",
        onclick: () => irA({ ...estado, ver: String(vino.cod_vino) }),
      }, "Ver"),
    ),
  );
}

function filaUnica(texto) {
  return crear("tr", {}, crear("td", { colSpan: COLUMNAS.length + 1 }, texto));
}

function armarListado(estado) {
  const mensajes = crear("div");
  const cuerpo = crear("tbody", {}, filaUnica("Cargando…"));
  const tabla = crear(
    "table",
    { "aria-busy": "true" },
    crear("caption", { className: "solo-lectores" }, "Vinos del catálogo"),
    crear(
      "thead",
      {},
      crear(
        "tr",
        {},
        COLUMNAS.map(([titulo, numerica]) =>
          crear("th", { scope: "col", className: numerica ? "numero" : null }, titulo)),
        crear("th", { scope: "col" }, crear("span", { className: "solo-lectores" }, "Acciones")),
      ),
    ),
    cuerpo,
  );
  const paginador = crear("div", { className: "acciones paginador" });

  async function cargar() {
    try {
      const pagina = await api.listarVinos({
        tipo: estado.tipo,
        id_cepa: estado.id_cepa,
        cuit_bodega: estado.cuit_bodega,
        anada: estado.anada,
        limite: LIMITE,
        // Paginación, no un cálculo de negocio: de número de página a filas a saltear.
        desplazamiento: (estado.pagina - 1) * LIMITE,
      });
      mostrarPagina(pagina);
    } catch (error) {
      cuerpo.replaceChildren(filaUnica("No se pudo cargar el listado."));
      mostrarError(mensajes, error);
    } finally {
      tabla.setAttribute("aria-busy", "false");
    }
  }

  function mostrarPagina({ items, limite, total }) {
    if (total === 0) {
      cuerpo.replaceChildren(filaUnica("No hay vinos con esos filtros."));
      return;
    }

    // Cantidad de páginas a partir del total y el límite que devolvió la API.
    const paginas = Math.ceil(total / limite);

    if (items.length === 0) {
      cuerpo.replaceChildren(filaUnica(`La página ${estado.pagina} no existe: hay ${paginas}.`));
      paginador.replaceChildren(
        crear("a", { href: hashDe({ ...estado, pagina: 1 }) }, "Ir a la página 1"),
      );
      return;
    }

    cuerpo.replaceChildren(...items.map((vino) => filaDeVino(vino, estado)));
    paginador.replaceChildren(
      crear("button", {
        type: "button",
        className: "boton boton--secundario",
        disabled: estado.pagina <= 1,
        onclick: () => irA({ ...estado, pagina: estado.pagina - 1 }),
      }, "« Anterior"),
      crear("span", {}, `Página ${estado.pagina} de ${paginas} · ${total} vinos`),
      crear("button", {
        type: "button",
        className: "boton boton--secundario",
        disabled: estado.pagina >= paginas,
        onclick: () => irA({ ...estado, pagina: estado.pagina + 1 }),
      }, "Siguiente »"),
    );
  }

  const seccion = crear(
    "section",
    { className: "catalogo__listado", "aria-label": "Listado de vinos" },
    mensajes,
    crear("div", { className: "tabla-contenedor" }, tabla),
    paginador,
  );
  return { seccion, mensajes, cargar };
}

// --- Detalle ------------------------------------------------------------------

function fichaDeVino(vino) {
  const composicion = crear(
    "div",
    { className: "tabla-contenedor" },
    crear(
      "table",
      {},
      crear(
        "thead",
        {},
        crear(
          "tr",
          {},
          crear("th", { scope: "col" }, "Cepa"),
          crear("th", { scope: "col", className: "numero" }, "%"),
        ),
      ),
      crear(
        "tbody",
        {},
        // En el orden que trae la API: por porcentaje, de mayor a menor.
        vino.composicion.map((c) => crear(
          "tr",
          {},
          crear("td", {}, `${c.cepa} (${c.tipo_cepa})`),
          crear("td", { className: "numero" }, c.porcentaje),
        )),
      ),
    ),
  );

  const maridajes = vino.maridajes.length === 0
    ? crear("p", {}, "Sin maridajes sugeridos.")
    : crear(
      "ul",
      {},
      vino.maridajes.map((m) => crear("li", {}, `${m.nombre} · ${m.temperatura_servicio_c} °C`)),
    );

  return [
    crear("h2", { id: "titulo-detalle" }, `${vino.nombre} · ${vino.anada}`),
    crear("p", {}, `${vino.bodega} · ${vino.tipo} · ${vino.volumen_ml} ml · ${vino.graduacion} %`),
    crear(
      "p",
      {},
      "Precio: ", crear("strong", {}, formatoMoneda(vino.precio)),
      " · Stock total: ", crear("strong", {}, vino.stock_total),
    ),
    crear("h3", {}, "Composición"),
    composicion,
    crear("h3", {}, "Maridajes"),
    maridajes,
  ];
}

function armarDetalle(estado) {
  const contenido = crear("div", {}, crear("p", { "aria-busy": "true" }, "Cargando…"));
  const mensajes = crear("div");
  const confirmacion = crear("div");
  const seccion = crear(
    "aside",
    { className: "panel detalle-vino", "aria-labelledby": "titulo-detalle" },
    crear(
      "div",
      { className: "detalle-vino__cerrar" },
      crear("button", {
        type: "button",
        className: "boton boton--secundario boton--compacto",
        onclick: () => irA({ ...estado, ver: "" }),
      }, "Cerrar"),
    ),
    contenido,
    confirmacion,
    mensajes,
  );

  function pedirConfirmacion(vino, botonEliminar) {
    botonEliminar.disabled = true;
    const cancelar = () => {
      confirmacion.replaceChildren();
      botonEliminar.disabled = false;
      botonEliminar.focus();
    };
    const botonConfirmar = crear("button", {
      type: "button",
      className: "boton",
      onclick: async () => {
        botonConfirmar.disabled = true;
        botonCancelar.disabled = true;
        try {
          await api.eliminarVino(vino.cod_vino);
          avisoPendiente = "Vino eliminado.";
          irA({ ...estado, ver: "" });
        } catch (error) {
          // El 409 23503 (ventas o historia de precios) se muestra tal como llega.
          cancelar();
          mostrarError(mensajes, error);
        }
      },
    }, "Confirmar");
    const botonCancelar = crear("button", {
      type: "button", className: "boton boton--secundario", onclick: cancelar,
    }, "Cancelar");

    confirmacion.replaceChildren(crear(
      "div",
      { className: "mensaje mensaje--confirmacion", role: "alertdialog", "aria-label": "Confirmar eliminación" },
      crear("p", {}, `¿Eliminar el vino ${vino.nombre}? Esta acción no se puede deshacer.`),
      crear("div", { className: "acciones" }, botonConfirmar, botonCancelar),
    ));
    botonConfirmar.focus();
  }

  async function cargar() {
    let vino;
    try {
      vino = await api.obtenerVino(estado.ver);
    } catch (error) {
      // Un 404 (o cualquier error) queda en el panel; el listado sigue visible.
      contenido.replaceChildren(crear("h2", { id: "titulo-detalle" }, `Vino ${estado.ver}`));
      mostrarError(mensajes, error);
      return;
    }

    const botonEliminar = crear("button", {
      type: "button",
      className: "boton boton--secundario",
      onclick: () => {
        mensajes.replaceChildren();
        pedirConfirmacion(vino, botonEliminar);
      },
    }, "Eliminar");

    contenido.replaceChildren(
      ...fichaDeVino(vino),
      crear(
        "div",
        { className: "acciones" },
        crear("a", {
          className: "boton",
          href: `#/vinos/${encodeURIComponent(vino.cod_vino)}/editar`,
        }, "Editar"),
        botonEliminar,
      ),
    );
  }

  return { seccion, cargar };
}

// --- Montaje ------------------------------------------------------------------

export async function montar(contenedor, { consulta }) {
  const estado = leerEstado(consulta);
  const filtros = armarFiltros(estado);
  const listado = armarListado(estado);
  const detalle = estado.ver ? armarDetalle(estado) : null;

  if (avisoPendiente) {
    mostrarAviso(listado.mensajes, avisoPendiente);
    avisoPendiente = null;
  }

  contenedor.append(
    crear("h1", {}, "Catálogo de vinos"),
    crear(
      "div",
      { className: detalle ? "catalogo catalogo--con-detalle" : "catalogo" },
      crear("div", { className: "catalogo__principal" }, filtros.seccion, listado.seccion),
      detalle?.seccion,
    ),
  );

  await Promise.all([filtros.cargar(), listado.cargar(), detalle?.cargar()]);
}
