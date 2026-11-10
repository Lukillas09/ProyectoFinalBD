// Pantalla 4: transferencias (issue #54, boceto docs/bocetos/b4-transferencias.png).
//
// #/transferencias permite crear una transferencia (sala) o abrir una por su
// número; #/transferencias/{nro} muestra su ficha: estado, renglones y las tres
// operaciones. Cada operación de la API devuelve la transferencia completa y la
// ficha se redibuja con ESA respuesta: el estado nunca se cambia a mano acá.
//
// Los botones se habilitan según el `estado` que devolvió la API. Es sólo una
// ayuda visual: la transición la decide PostgreSQL (RN-11 en
// sp_terminar_transferencia, sp_procesar_transferencia y trg_transferencia_estado;
// RN-12 en trg_renglon_transferencia_bloqueo). Si alguien fuerza la llamada, la
// base la rechaza y el error se muestra tal cual. Tampoco se calcula stock ni se
// suman cantidades: se muestran las que informa la API.

import { api } from "../api.js";
import { crear, formatoFecha, mostrarError } from "../ui.js";

// Los valores de estado_documento (001_esquema.sql) y su texto para mostrar.
const ETAPAS = [
  ["en_confeccion", "en confección"],
  ["terminado", "terminado"],
  ["procesado", "procesado"],
];

const textoEstado = (estado) => ETAPAS.find(([valor]) => valor === estado)?.[1] ?? estado;

// Las salas casi no cambian: quedan en el módulo para no pedirlas de nuevo cada
// vez que un cambio de hash vuelve a montar la pantalla. Una lista que falló no
// se guarda, así que se reintenta en el próximo montaje.
let salas = null;

// mostrarError no muestra la restricción violada ni admite líneas propias: se
// agregan dentro del mismo recuadro, con lo que informó la API.
function mostrarErrorConNotas(zona, error, ...notas) {
  mostrarError(zona, error);
  const caja = zona.firstElementChild;
  if (error.restriccion) caja?.append(crear("p", {}, `Restricción: ${error.restriccion}`));
  for (const nota of notas) caja?.append(crear("p", {}, nota));
}

// --- Crear -------------------------------------------------------------------

function armarCreacion() {
  const mensajes = crear("div", { "aria-live": "polite" });
  const selector = crear(
    "select",
    { id: "transf-sala", name: "id_sala", required: true, disabled: true },
    crear("option", { value: "", selected: true, disabled: true }, "Cargando salas…"),
  );
  const boton = crear(
    "button",
    { type: "submit", className: "boton", disabled: true },
    "Crear transferencia",
  );
  let creando = false;

  const formulario = crear(
    "form",
    {
      className: "acciones",
      onsubmit: async (evento) => {
        evento.preventDefault();
        if (creando) return;
        creando = true;
        boton.disabled = true;
        boton.textContent = "Creando…";
        mensajes.replaceChildren();
        try {
          const creada = await api.crearTransferencia(Number(selector.value));
          // El cambio de hash vuelve a montar la pantalla con la ficha nueva.
          window.location.hash = `#/transferencias/${encodeURIComponent(creada.nro_transferencia)}`;
        } catch (error) {
          mostrarErrorConNotas(mensajes, error);
          creando = false;
          boton.disabled = false;
          boton.textContent = "Crear transferencia";
        }
      },
    },
    crear("label", { htmlFor: "transf-sala" }, "Sala", selector),
    boton,
  );

  async function cargar() {
    try {
      salas ??= await api.salas();
      // replaceChildren no aplana arrays (crear sí): por eso el spread.
      selector.replaceChildren(
        crear("option", { value: "", selected: true, disabled: true }, "Elegí una sala"),
        ...salas.map((sala) => crear(
          "option",
          { value: String(sala.id_sala) },
          `${sala.id_sala} · ${sala.calle} ${sala.numero} (${sala.localidad})`,
        )),
      );
      selector.disabled = false;
      boton.disabled = false;
    } catch (error) {
      selector.replaceChildren(
        crear("option", { value: "", selected: true }, "No se pudieron cargar las salas"),
      );
      mostrarError(mensajes, error);
    }
  }

  return { formulario, mensajes, cargar };
}

// --- Abrir -------------------------------------------------------------------

function armarApertura(nroActual, recargar) {
  const entrada = crear("input", {
    id: "transf-nro",
    name: "nro",
    type: "number",
    step: 1,
    required: true,
    inputMode: "numeric",
    value: nroActual ?? "",
  });

  const formulario = crear(
    "form",
    {
      className: "acciones",
      onsubmit: (evento) => {
        evento.preventDefault();
        const nro = String(Number(entrada.value));
        // Con el mismo número el hash no cambia, no hay remontaje y no pasaría
        // nada: se vuelve a pedir la ficha, que puede haber cambiado en la base.
        if (nro === nroActual) recargar();
        else window.location.hash = `#/transferencias/${encodeURIComponent(nro)}`;
      },
    },
    crear("label", { htmlFor: "transf-nro" }, "Número", entrada),
    crear("button", { type: "submit", className: "boton boton--secundario" }, "Abrir"),
  );

  return { formulario };
}

// --- Ficha -------------------------------------------------------------------

function armarFicha(nro) {
  // Lo que se redibuja con cada respuesta: la zona principal y el panel de
  // estado. Los mensajes quedan afuera, para que un error sobreviva al redibujo
  // con la transferencia que se volvió a pedir.
  const principal = crear("div", { className: "transferencia__principal" });
  const panelEstado = crear("section", { className: "panel", "aria-labelledby": "titulo-estado" });
  const mensajes = crear("div", { "aria-live": "polite" });
  const cuadricula = crear(
    "div",
    { className: "transferencia" },
    principal,
    crear("div", { className: "transferencia__lateral" }, panelEstado, mensajes),
  );
  const zona = crear("div");

  let actual = null;
  let ocupado = false;
  let controles = null;

  // Ayuda visual (ver el comentario del módulo): la base decide la transición.
  function aplicarPermisos() {
    const enConfeccion = actual.estado === "en_confeccion";
    controles.vino.disabled = !enConfeccion;
    controles.cantidad.disabled = !enConfeccion;
    controles.agregar.disabled = !enConfeccion;
    controles.terminar.disabled = !enConfeccion;
    controles.procesar.disabled = actual.estado !== "terminado";
  }

  // Una operación a la vez: la guarda sincrónica cubre también un doble clic
  // ya encolado, además de los botones deshabilitados.
  async function ejecutar({ boton, espera, operacion, procesando = false }) {
    if (ocupado) return;
    ocupado = true;
    const textoOriginal = boton.textContent;
    for (const control of Object.values(controles)) control.disabled = true;
    boton.textContent = espera;
    mensajes.replaceChildren();

    try {
      dibujar(await operacion());
    } catch (error) {
      // Un P0001 es una regla de estado (RN-11, RN-12): la ficha pudo quedar
      // desactualizada (por ejemplo, otra pestaña ya la procesó). Se vuelve a
      // pedir para mostrar el estado real. Los demás errores no cambian la
      // transferencia, y redibujar borraría lo que se escribió.
      let real = null;
      if (error.codigo === "P0001") {
        try {
          real = await api.obtenerTransferencia(actual.nro_transferencia);
        } catch {
          // Si tampoco se puede leer, queda el error original.
        }
      }
      if (real) {
        dibujar(real);
      } else {
        boton.textContent = textoOriginal;
        aplicarPermisos();
      }
      // La aclaración sólo vale si la transferencia sigue terminada: P0001 también
      // es "ya procesada" o "todavía en confección", y ahí sería falsa.
      const sigueTerminada = procesando && real?.estado === "terminado";
      mostrarErrorConNotas(
        mensajes,
        error,
        ...(sigueTerminada ? ["La transferencia sigue terminada; no se movió stock."] : []),
      );
    } finally {
      ocupado = false;
    }
  }

  function dibujar(transferencia) {
    actual = transferencia;
    const { nro_transferencia: numero } = transferencia;

    const vino = crear("input", {
      id: "transf-vino", name: "cod_vino", type: "number", step: 1,
      required: true, inputMode: "numeric", autocomplete: "off",
    });
    // Sin min: un 0 o un negativo llegan a la base, que responde 422 (CHECK de
    // cantidad positiva) y se muestra tal cual.
    const cantidad = crear("input", {
      id: "transf-cantidad", name: "cantidad", type: "number", step: 1,
      required: true, inputMode: "numeric", autocomplete: "off",
    });
    const agregar = crear("button", { type: "submit", className: "boton" }, "Agregar renglón");
    const terminar = crear("button", {
      type: "button",
      className: "boton",
      onclick: () => ejecutar({
        boton: terminar, espera: "Terminando…", operacion: () => api.terminarTransferencia(numero),
      }),
    }, "Terminar");
    const procesar = crear("button", {
      type: "button",
      className: "boton",
      onclick: () => ejecutar({
        boton: procesar, espera: "Procesando…", procesando: true,
        operacion: () => api.procesarTransferencia(numero),
      }),
    }, "Procesar");
    controles = { vino, cantidad, agregar, terminar, procesar };

    const formularioRenglon = crear(
      "form",
      {
        className: "acciones",
        "aria-label": "Agregar renglón",
        onsubmit: (evento) => {
          evento.preventDefault();
          const cod_vino = Number(vino.value);
          const cant = Number(cantidad.value);
          ejecutar({
            boton: agregar,
            espera: "Agregando…",
            operacion: async () => {
              // Se confirma el vino antes de enviar: un 404 se muestra y no se
              // manda el renglón.
              await api.obtenerVino(cod_vino);
              return api.agregarRenglonTransferencia(numero, { cod_vino, cantidad: cant });
            },
          });
        },
      },
      crear("label", { htmlFor: "transf-vino" }, "Cód. vino", vino),
      crear("label", { htmlFor: "transf-cantidad" }, "Cantidad", cantidad),
      agregar,
    );

    const filas = transferencia.renglones.length === 0
      ? [crear("tr", {}, crear("td", { colSpan: 3 }, "Todavía no tiene renglones."))]
      : transferencia.renglones.map((renglon) => crear(
        "tr",
        {},
        crear("td", {}, renglon.cod_vino),
        crear("td", {}, renglon.nombre_vino),
        crear("td", { className: "numero" }, renglon.cantidad),
      ));

    principal.replaceChildren(
      crear(
        "div",
        { className: "transferencia__titulo" },
        crear(
          "h2",
          { id: "titulo-transferencia" },
          `Transferencia Nº ${numero} · depósito → sala ${transferencia.id_sala} · ${formatoFecha(transferencia.fecha_confeccion)}`,
        ),
        crear(
          "span",
          { className: `insignia insignia--${transferencia.estado}` },
          textoEstado(transferencia.estado),
        ),
      ),
      crear(
        "div",
        { className: "tabla-contenedor" },
        crear(
          "table",
          {},
          crear("caption", { className: "solo-lectores" }, "Renglones de la transferencia"),
          crear(
            "thead",
            {},
            crear(
              "tr",
              {},
              crear("th", { scope: "col" }, "Cód."),
              crear("th", { scope: "col" }, "Vino"),
              crear("th", { scope: "col", className: "numero" }, "Cantidad"),
            ),
          ),
          crear("tbody", {}, filas),
        ),
      ),
      formularioRenglon,
    );

    panelEstado.replaceChildren(
      crear("h2", { id: "titulo-estado" }, "Estado"),
      crear(
        "ol",
        { className: "estados", "aria-label": "Estados de la transferencia" },
        ETAPAS.flatMap(([valor, texto], indice) => [
          indice > 0 ? crear("li", { className: "estados__flecha", "aria-hidden": "true" }, "→") : null,
          crear(
            "li",
            {
              className: valor === transferencia.estado ? "estados__paso estados__paso--actual" : "estados__paso",
              "aria-current": valor === transferencia.estado ? "step" : null,
            },
            texto,
          ),
        ]),
      ),
      crear("div", { className: "acciones" }, terminar, procesar),
      crear(
        "p",
        { className: "nota" },
        "Los botones sólo reflejan el estado que devolvió la API. Quien decide la transición es la base (RN-11 y RN-12).",
      ),
    );

    aplicarPermisos();
  }

  async function cargar() {
    zona.replaceChildren(crear("p", { "aria-busy": "true" }, "Cargando…"));
    mensajes.replaceChildren();
    try {
      const transferencia = await api.obtenerTransferencia(nro);
      zona.replaceChildren(cuadricula);
      dibujar(transferencia);
    } catch (error) {
      // Un 404 (o cualquier error) se muestra tal cual en lugar de la ficha.
      mostrarError(zona, error);
    }
  }

  if (nro === null) {
    zona.append(crear("p", { className: "nota" }, "Creá una transferencia o abrí una por su número."));
  }

  return { zona, cargar };
}

// --- Montaje -----------------------------------------------------------------

export async function montar(contenedor, { parametros }) {
  const nro = parametros.nro ?? null;
  const creacion = armarCreacion();
  const ficha = armarFicha(nro);
  const apertura = armarApertura(nro, ficha.cargar);

  contenedor.append(
    crear(
      "section",
      { className: "transferencias" },
      crear("h1", {}, "Transferencias"),
      crear(
        "section",
        { className: "panel", "aria-label": "Crear o abrir una transferencia" },
        crear(
          "div",
          { className: "rejilla" },
          crear("div", {}, crear("h2", {}, "Nueva transferencia"), creacion.formulario, creacion.mensajes),
          crear("div", {}, crear("h2", {}, "Abrir por número"), apertura.formulario),
        ),
      ),
      ficha.zona,
    ),
  );

  await Promise.all([creacion.cargar(), nro === null ? null : ficha.cargar()]);
}
