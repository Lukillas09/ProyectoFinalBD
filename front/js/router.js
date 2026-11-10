import { crear, mostrarError } from "./ui.js";

// Cada pantalla exporta montar(contenedor, { parametros, consulta }). El router
// limpia #vista antes de invocarla y entrega los parámetros de ruta y del hash.
export const RUTAS = [
  {
    patron: /^\/vinos$/,
    titulo: "Catálogo de vinos",
    issue: 51,
    cargar: () => import("./pantallas/catalogo.js"),
  },
  {
    patron: /^\/vinos\/nuevo$/,
    titulo: "Nuevo vino",
    issue: 52,
    cargar: null,
  },
  {
    patron: /^\/vinos\/(?<cod>[^/]+)\/editar$/,
    titulo: "Editar vino",
    issue: 52,
    cargar: null,
  },
  {
    patron: /^\/venta$/,
    titulo: "Nueva venta",
    issue: 53,
    cargar: () => import("./pantallas/venta.js"),
  },
  {
    patron: /^\/transferencias$/,
    titulo: "Transferencias",
    issue: 54,
    cargar: null,
  },
  {
    patron: /^\/transferencias\/(?<nro>[^/]+)$/,
    titulo: "Transferencia",
    issue: 54,
    cargar: null,
  },
  {
    patron: /^\/tablero$/,
    titulo: "Tablero",
    issue: 55,
    cargar: null,
  },
];

let iniciado = false;
let versionNavegacion = 0;

function leerHash() {
  const fragmento = window.location.hash.slice(1) || "/vinos";
  const separador = fragmento.indexOf("?");
  const ruta = separador === -1 ? fragmento : fragmento.slice(0, separador);
  const cadenaConsulta = separador === -1 ? "" : fragmento.slice(separador + 1);

  return {
    ruta: ruta || "/vinos",
    consulta: Object.fromEntries(new URLSearchParams(cadenaConsulta)),
  };
}

function decodificarParametros(coincidencia) {
  return Object.fromEntries(
    Object.entries(coincidencia.groups ?? {}).map(([nombre, valor]) => [
      nombre,
      decodeURIComponent(valor),
    ]),
  );
}

function rutaDeNavegacion(ruta) {
  if (ruta === "/vinos/nuevo" || /^\/vinos\/[^/]+\/editar$/.test(ruta)) {
    return "/vinos/nuevo";
  }
  if (/^\/transferencias(?:\/[^/]+)?$/.test(ruta)) return "/transferencias";
  return ruta;
}

function marcarNavegacion(ruta) {
  const activa = rutaDeNavegacion(ruta);
  for (const enlace of document.querySelectorAll("nav [data-ruta]")) {
    if (enlace.dataset.ruta === activa) {
      enlace.setAttribute("aria-current", "page");
    } else {
      enlace.removeAttribute("aria-current");
    }
  }
}

function mostrarPendiente(contenedor, ruta) {
  contenedor.append(
    crear(
      "section",
      { className: "vista-pendiente" },
      crear("h2", {}, ruta.titulo),
      crear("p", {}, `Pantalla pendiente — issue #${ruta.issue}`),
    ),
  );
}

async function resolverRuta() {
  const contenedor = document.querySelector("#vista");
  if (!contenedor) return;

  const navegacionActual = ++versionNavegacion;
  let { ruta, consulta } = leerHash();
  let encontrada;
  let coincidencia;

  for (const candidata of RUTAS) {
    const resultado = ruta.match(candidata.patron);
    if (resultado) {
      encontrada = candidata;
      coincidencia = resultado;
      break;
    }
  }

  if (!encontrada) {
    ruta = "/vinos";
    consulta = {};
    encontrada = RUTAS[0];
    coincidencia = ruta.match(encontrada.patron);
  }

  marcarNavegacion(ruta);
  document.title = `${encontrada.titulo} · Bodegas del Atuel`;
  contenedor.replaceChildren();

  if (encontrada.cargar === null) {
    mostrarPendiente(contenedor, encontrada);
    return;
  }

  try {
    const pantalla = await encontrada.cargar();
    if (navegacionActual !== versionNavegacion) return;
    contenedor.replaceChildren();
    await pantalla.montar(contenedor, {
      parametros: decodificarParametros(coincidencia),
      consulta,
    });
  } catch (error) {
    if (navegacionActual === versionNavegacion) mostrarError(contenedor, error);
  }
}

export function iniciarRouter() {
  if (iniciado) return;
  iniciado = true;

  window.addEventListener("hashchange", resolverRuta);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", resolverRuta, { once: true });
  } else {
    resolverRuta();
  }
}
