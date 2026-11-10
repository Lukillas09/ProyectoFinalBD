// Pantalla 2: alta y edición de vino (issue #52, boceto docs/bocetos/b2-vino.png).
//
// Un solo módulo para #/vinos/nuevo y #/vinos/{cod}/editar. El cuerpo es
// VinoEntrada (api/app/esquemas.py) y la edición es un reemplazo completo
// (PUT): siempre viajan todos los campos, composición y maridajes incluidos.
//
// La composición NO se suma, no se muestra un total ni se valida "suma 100"
// en el navegador: es la regla RN-05 y la verifica PostgreSQL con un
// constraint trigger diferido al confirmar la transacción. Si no suma 100, la
// API responde 409 P0001 con el mensaje de la base y no queda nada guardado.
// Tampoco se filtran cepas repetidas ni se exige al menos una fila: esas
// formas las rechaza la API con 422 "validacion" y se muestra su mensaje.

import { api } from "../api.js";
import { crear, mostrarError } from "../ui.js";

// Los enteros pasan por Number(); un campo vacío viaja como null para que la
// API responda "falta" en lugar de recibir un 0 que el usuario no escribió.
function entero(valor) {
  const texto = valor.trim();
  return texto === "" ? null : Number(texto);
}

// Precio, graduación y porcentaje viajan como string, tal como se escribieron:
// nunca pasan por un número de punto flotante. Sólo se acepta la coma decimal
// cambiándola por punto ("4500,50" -> "4500.50").
function decimal(valor) {
  return valor.trim().replace(",", ".");
}

function campo(etiqueta, control) {
  return crear("label", {}, etiqueta, control);
}

function opcionVacia(texto) {
  return crear("option", { value: "" }, texto);
}

// --- Composición -------------------------------------------------------------

function armarComposicion(cepas) {
  const filas = crear("div", { className: "composicion__filas" });

  // El número de fila es sólo la etiqueta accesible de cada control y la
  // posición que usa la API en body.composicion.N.
  function renumerar() {
    [...filas.children].forEach((fila, indice) => {
      const n = indice + 1;
      fila.querySelector("select").setAttribute("aria-label", `Cepa ${n}`);
      fila.querySelector("input").setAttribute("aria-label", `Porcentaje de la cepa ${n}`);
      fila.querySelector("button").setAttribute("aria-label", `Quitar la cepa ${n}`);
    });
  }

  function agregar({ id_cepa = "", porcentaje = "" } = {}) {
    const selector = crear(
      "select",
      { name: "id_cepa" },
      opcionVacia("Elegí una cepa"),
      cepas.map((c) => crear("option", { value: String(c.id_cepa) }, `${c.nombre} (${c.tipo})`)),
    );
    selector.value = String(id_cepa);
    const fila = crear(
      "div",
      { className: "fila-cepa" },
      selector,
      crear("input", { type: "text", name: "porcentaje", inputMode: "decimal", value: porcentaje }),
      crear("span", { "aria-hidden": "true" }, "%"),
      crear("button", {
        type: "button",
        className: "boton boton--secundario boton--compacto",
        onclick: () => {
          fila.remove();
          renumerar();
        },
      }, "✕"),
    );
    filas.append(fila);
    renumerar();
    return fila;
  }

  const botonAgregar = crear("button", {
    type: "button",
    className: "boton boton--secundario",
    onclick: () => agregar().querySelector("select").focus(),
  }, "+ Agregar cepa");

  const seccion = crear(
    "fieldset",
    { className: "composicion" },
    crear("legend", {}, "Composición de cepas"),
    filas,
    crear("div", { className: "acciones" }, botonAgregar),
    crear(
      "p",
      { className: "nota" },
      "La suma de los porcentajes la verifica la base al guardar (RN-05).",
    ),
  );

  return {
    seccion,
    agregar,
    // En el orden de las filas: el índice coincide con body.composicion.N.
    leer: () => [...filas.children].map((fila) => ({
      id_cepa: entero(fila.querySelector("select").value),
      porcentaje: decimal(fila.querySelector("input").value),
    })),
    fila: (indice) => filas.children[indice] ?? null,
  };
}

// --- Maridajes ---------------------------------------------------------------

function armarMaridajes(maridajes, marcados) {
  const casillas = maridajes.map((m) => crear(
    "label",
    { className: "casilla" },
    crear("input", {
      type: "checkbox",
      name: "maridajes",
      value: String(m.id_maridaje),
      checked: marcados.has(m.id_maridaje),
    }),
    `${m.nombre} (${m.temperatura_servicio_c} °C)`,
  ));

  const seccion = crear(
    "section",
    { className: "panel", "aria-labelledby": "titulo-maridajes" },
    crear("h2", { id: "titulo-maridajes" }, "Maridajes"),
    crear(
      "fieldset",
      { className: "casillas" },
      crear("legend", { className: "solo-lectores" }, "Maridajes sugeridos"),
      casillas.length ? casillas : crear("p", {}, "No hay maridajes para elegir."),
    ),
  );

  return {
    seccion,
    leer: () => casillas
      .map((casilla) => casilla.querySelector("input"))
      .filter((casilla) => casilla.checked)
      .map((casilla) => Number(casilla.value)),
  };
}

// --- Errores de forma ----------------------------------------------------------

// Marca el control que nombra cada error de validación de FastAPI:
// body.precio -> precio; body.composicion.0.porcentaje -> porcentaje de la
// fila 1. Lo que no se puede ubicar (body.composicion, body) queda sólo en la
// lista que arma mostrarError.
function marcarInvalidos(formulario, composicion, errores) {
  for (const { campo: ruta } of errores ?? []) {
    const partes = ruta.split(".");
    if (partes[0] !== "body") continue;

    let control = null;
    if (partes[1] === "composicion" && partes.length === 4) {
      const nombre = partes[3] === "id_cepa" ? "select" : "input";
      control = composicion.fila(Number(partes[2]))?.querySelector(nombre);
    } else if (partes.length === 2 && partes[1] !== "composicion" && partes[1] !== "maridajes") {
      control = formulario.elements.namedItem(partes[1]);
    }
    control?.setAttribute("aria-invalid", "true");
  }
}

function mostrarErrorDeGuardado(zona, error) {
  mostrarError(zona, error);
  // mostrarError no muestra la restricción violada (23514, 23505, 23503). Se
  // agrega dentro del mismo recuadro: es el nombre estable que manda la API.
  if (error.restriccion) {
    zona.firstElementChild?.append(crear("p", {}, `Restricción: ${error.restriccion}`));
  }
}

// --- Montaje -----------------------------------------------------------------

export async function montar(contenedor, { parametros }) {
  const cod = parametros.cod ?? null;
  const titulo = crear("h1", {}, cod ? `Editar vino Nº ${cod}` : "Nuevo vino");
  const mensajesCarga = crear("div");
  const cargando = crear("p", { "aria-busy": "true" }, "Cargando…");
  contenedor.append(titulo, mensajesCarga, cargando);

  const [tipos, bodegas, cepas, maridajes, vino] = await Promise.allSettled([
    api.tiposVino(),
    api.bodegas(),
    api.cepas(),
    api.maridajes(),
    cod ? api.obtenerVino(cod) : Promise.resolve(null),
  ]);
  cargando.remove();

  if (vino.status === "rejected") {
    mostrarError(mensajesCarga, vino.reason);
    contenedor.append(crear("p", {}, crear("a", { href: "#/vinos" }, "Volver al catálogo")));
    return;
  }

  // Sin un catálogo no se puede armar un cuerpo válido: se muestra cada error
  // en su propio contenedor (mostrarError reemplaza el contenido) y Guardar
  // queda deshabilitado.
  const catalogos = [tipos, bodegas, cepas, maridajes];
  for (const resultado of catalogos.filter((r) => r.status === "rejected")) {
    const zona = crear("div");
    mensajesCarga.append(zona);
    mostrarError(zona, resultado.reason);
  }
  const faltaCatalogo = catalogos.some((r) => r.status === "rejected");
  const lista = (resultado) => (resultado.status === "fulfilled" ? resultado.value : []);

  const actual = vino.value;
  if (actual) titulo.textContent = `Editar vino Nº ${actual.cod_vino} · ${actual.nombre}`;

  // Los valores se precargan tal como vienen de la API: "4500.00", "13.50".
  const nombre = crear("input", {
    type: "text", name: "nombre", maxLength: 100, required: true, value: actual?.nombre ?? "",
  });
  const tipo = crear(
    "select",
    { name: "tipo" },
    opcionVacia("Elegí un tipo"),
    lista(tipos).map((t) => crear("option", { value: t }, t)),
  );
  tipo.value = actual?.tipo ?? "";
  const anada = crear("input", { type: "number", name: "anada", step: 1, value: actual?.anada ?? "" });
  const volumen = crear("input", {
    type: "number", name: "volumen_ml", step: 1, value: actual?.volumen_ml ?? "",
  });
  const graduacion = crear("input", {
    type: "text", name: "graduacion", inputMode: "decimal", value: actual?.graduacion ?? "",
  });
  const precio = crear("input", {
    type: "text", name: "precio", inputMode: "decimal", value: actual?.precio ?? "",
  });
  const bodega = crear(
    "select",
    { name: "cuit_bodega" },
    opcionVacia("Elegí una bodega"),
    lista(bodegas).map((b) => crear("option", { value: b.cuit }, b.razon_social)),
  );
  bodega.value = actual?.cuit_bodega ?? "";

  const composicion = armarComposicion(lista(cepas));
  if (actual) {
    for (const { id_cepa, porcentaje } of actual.composicion) composicion.agregar({ id_cepa, porcentaje });
  } else {
    composicion.agregar();
  }
  const panelMaridajes = armarMaridajes(
    lista(maridajes),
    new Set((actual?.maridajes ?? []).map((m) => m.id_maridaje)),
  );

  const errores = crear("div");
  const guardar = crear("button", { type: "submit", className: "boton", disabled: faltaCatalogo }, "Guardar");
  const cancelar = crear("a", {
    className: "boton boton--secundario",
    href: actual ? `#/vinos?ver=${encodeURIComponent(actual.cod_vino)}` : "#/vinos",
  }, "Cancelar");

  const formulario = crear(
    "form",
    {
      className: "vino-formulario",
      noValidate: true,
      onsubmit: async (evento) => {
        evento.preventDefault();
        for (const marcado of formulario.querySelectorAll("[aria-invalid]")) {
          marcado.removeAttribute("aria-invalid");
        }
        errores.replaceChildren();

        const cuerpo = {
          nombre: nombre.value,
          tipo: tipo.value,
          anada: entero(anada.value),
          volumen_ml: entero(volumen.value),
          graduacion: decimal(graduacion.value),
          precio: decimal(precio.value),
          cuit_bodega: bodega.value,
          composicion: composicion.leer(),
          maridajes: panelMaridajes.leer(),
        };

        guardar.disabled = true;
        guardar.textContent = "Guardando…";
        try {
          const guardado = actual
            ? await api.modificarVino(actual.cod_vino, cuerpo)
            : await api.crearVino(cuerpo);
          window.location.hash = `#/vinos?ver=${encodeURIComponent(guardado.cod_vino)}`;
        } catch (error) {
          // Lo escrito queda en el formulario para corregirlo y volver a enviar.
          mostrarErrorDeGuardado(errores, error);
          marcarInvalidos(formulario, composicion, error.errores);
          guardar.disabled = false;
          guardar.textContent = "Guardar";
        }
      },
    },
    crear(
      "section",
      { className: "panel", "aria-labelledby": "titulo-datos" },
      crear("h2", { id: "titulo-datos" }, "Datos del vino"),
      crear(
        "div",
        { className: "rejilla" },
        campo("Nombre", nombre),
        campo("Tipo", tipo),
        campo("Añada", anada),
        campo("Volumen (ml)", volumen),
        campo("Graduación (%)", graduacion),
        campo("Precio", precio),
        campo("Bodega", bodega),
      ),
      composicion.seccion,
      errores,
      crear("div", { className: "acciones" }, guardar, cancelar),
    ),
    panelMaridajes.seccion,
  );

  contenedor.append(formulario);
}
