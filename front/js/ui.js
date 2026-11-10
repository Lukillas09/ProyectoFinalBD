import { ErrorApi } from "./api.js";

const MONEDA = new Intl.NumberFormat("es-AR", {
  style: "currency",
  currency: "ARS",
});

const FECHA = new Intl.DateTimeFormat("es-AR", { dateStyle: "short" });
const FECHA_HORA = new Intl.DateTimeFormat("es-AR", {
  dateStyle: "short",
  timeStyle: "short",
});

export function crear(etiqueta, atributos = {}, ...hijos) {
  const elemento = document.createElement(etiqueta);

  for (const [nombre, valor] of Object.entries(atributos ?? {})) {
    if (valor === null || valor === undefined || valor === false) continue;

    if (nombre === "className") {
      elemento.className = valor;
    } else if (nombre === "textContent") {
      elemento.textContent = valor;
    } else if (nombre.startsWith("on") && typeof valor === "function") {
      elemento.addEventListener(nombre.slice(2).toLowerCase(), valor);
    } else if (nombre in elemento) {
      elemento[nombre] = valor;
    } else {
      elemento.setAttribute(nombre, valor === true ? "" : String(valor));
    }
  }

  for (const hijo of hijos.flat(Infinity)) {
    if (hijo === null || hijo === undefined || hijo === false) continue;
    elemento.append(hijo instanceof Node ? hijo : document.createTextNode(String(hijo)));
  }

  return elemento;
}

export function limpiarMensajes(contenedor) {
  contenedor.replaceChildren();
}

export function mostrarError(contenedor, error) {
  const caja = crear("div", {
    className: "mensaje mensaje--error",
    role: "alert",
  });

  if (!(error instanceof ErrorApi)) {
    console.error(error);
    caja.append(
      crear("strong", {}, "Error inesperado"),
      crear("p", {}, "Ocurrió un error inesperado."),
    );
    contenedor.replaceChildren(caja);
    return;
  }

  caja.append(
    crear("strong", {}, `${error.status} · ${error.codigo}`),
    crear("p", {}, error.detail),
  );

  if (Array.isArray(error.errores) && error.errores.length > 0) {
    const lista = crear("ul");
    for (const { campo, mensaje } of error.errores) {
      lista.append(crear("li", {}, `${campo}: ${mensaje}`));
    }
    caja.append(lista);
  }

  contenedor.replaceChildren(caja);
}

export function mostrarAviso(contenedor, texto) {
  contenedor.replaceChildren(
    crear("div", { className: "mensaje mensaje--aviso", role: "status" }, texto),
  );
}

export function formatoMoneda(valor) {
  // La conversión a Number es sólo para presentar el valor: nunca se opera con él.
  return MONEDA.format(Number(valor));
}

function aFecha(iso) {
  const valor = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso}T00:00:00` : iso;
  return new Date(valor);
}

export function formatoFecha(iso) {
  return FECHA.format(aFecha(iso));
}

export function formatoFechaHora(iso) {
  return FECHA_HORA.format(aFecha(iso));
}
