// Pantalla 3: nueva venta (issue #53, boceto docs/bocetos/b3-venta.png).
//
// Antes de vender no se muestra ningún importe: el cliente se confirma por
// código, la sala sale del catálogo y cada vino se confirma por código. Al
// registrar, fn_registrar_venta (POST /comprobantes) valida stock, precios y
// descuentos en una sola transacción; la pantalla muestra el comprobante que
// devuelve la base o su error tal cual, sin datos a medias.
// Iniciada por Codex y terminada por Claude Code.

import { api } from "../api.js";
import {
  crear,
  formatoFechaHora,
  formatoMoneda,
  limpiarMensajes,
  mostrarAviso,
  mostrarError,
} from "../ui.js";

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

// cliente y sala son los textos que se confirmaron en la pantalla; los
// importes, la fecha y los renglones salen sólo de la respuesta.
function mostrarComprobante(contenedor, comprobante, { cliente, sala }) {
  const mensajes = crear("div");
  mostrarAviso(
    mensajes,
    `Comprobante Nº ${comprobante.nro_comprobante} registrado.`,
  );

  const cuerpo = crear(
    "tbody",
    {},
    comprobante.renglones.map((renglon) =>
      crear(
        "tr",
        {},
        crear("td", {}, renglon.nombre_vino),
        crear("td", { className: "numero" }, renglon.cantidad),
        crear(
          "td",
          { className: "numero" },
          formatoMoneda(renglon.precio_unitario),
        ),
        crear(
          "td",
          { className: "numero" },
          `${renglon.descuento_porcentaje} %`,
        ),
        crear(
          "td",
          { className: "numero" },
          formatoMoneda(renglon.total_parcial),
        ),
      ),
    ),
  );

  // El front no multiplica ni suma: fn_registrar_venta guardó todos los
  // importes del comprobante y sus renglones en PostgreSQL (RN-08).
  const totales = crear(
    "dl",
    { className: "venta__totales" },
    crear("dt", {}, "Subtotal"),
    crear("dd", {}, formatoMoneda(comprobante.subtotal)),
    crear("dt", {}, "Descuento"),
    crear("dd", {}, formatoMoneda(comprobante.descuento)),
    crear("dt", { className: "venta__total" }, "Total"),
    crear(
      "dd",
      { className: "venta__total" },
      formatoMoneda(comprobante.total),
    ),
  );

  const botonNuevaVenta = crear(
    "button",
    {
      type: "button",
      className: "boton",
      onclick: () => {
        void montar(contenedor);
      },
    },
    "Nueva venta",
  );

  contenedor.replaceChildren(
    crear(
      "section",
      { className: "venta venta--comprobante" },
      crear("h1", {}, "Nueva venta"),
      crear(
        "div",
        { className: "panel venta__comprobante" },
        crear("h2", {}, "Comprobante emitido"),
        mensajes,
        crear(
          "p",
          {},
          `${formatoFechaHora(comprobante.fecha)} · Sala ${sala}`,
        ),
        crear("p", {}, `Cliente ${comprobante.id_cliente}: ${cliente}`),
        crear(
          "div",
          { className: "tabla-contenedor" },
          crear(
            "table",
            {},
            encabezadoTabla("Vino", "#Cant.", "#P. unit.", "#Desc. %", "#Parcial"),
            cuerpo,
          ),
        ),
        totales,
        crear("div", { className: "acciones" }, botonNuevaVenta),
      ),
    ),
  );
}

export async function montar(contenedor) {
  let clienteElegido = null;
  let salasDisponibles = false;
  let agregandoVino = false;
  let enviando = false;
  let solicitudCliente = 0;
  const renglones = [];

  // Cada zona tiene su propio contenedor porque los helpers reemplazan su
  // contenido: cliente/sala, vinos y envío no se pisan entre sí.
  const mensajesCliente = crear("div", { "aria-live": "polite" });
  // El error de las salas tiene su propio contenedor: una búsqueda de cliente
  // no debe borrarlo mientras Registrar sigue deshabilitado por esa causa.
  const mensajesSala = crear("div", { "aria-live": "polite" });
  const mensajesVinos = crear("div", { "aria-live": "polite" });
  const mensajesEnvio = crear("div", { "aria-live": "polite" });

  const resumenCliente = crear("div", { "aria-live": "polite" });

  const inputCliente = crear("input", {
    id: "venta-cliente",
    name: "id_cliente",
    type: "number",
    min: "1",
    step: "1",
    required: true,
    inputMode: "numeric",
    autocomplete: "off",
  });

  const botonBuscarCliente = crear(
    "button",
    { type: "submit", className: "boton boton--secundario" },
    "Buscar",
  );

  const formularioCliente = crear(
    "form",
    { className: "acciones" },
    crear(
      "label",
      { htmlFor: "venta-cliente" },
      "Cliente (cód.)",
      inputCliente,
    ),
    botonBuscarCliente,
  );

  const selectorSala = crear(
    "select",
    {
      id: "venta-sala",
      name: "id_sala",
      required: true,
      disabled: true,
    },
    crear(
      "option",
      { value: "", selected: true, disabled: true },
      "Cargando salas…",
    ),
  );

  const inputVino = crear("input", {
    id: "venta-vino",
    name: "cod_vino",
    type: "number",
    min: "1",
    step: "1",
    required: true,
    inputMode: "numeric",
    autocomplete: "off",
  });

  const inputCantidad = crear("input", {
    id: "venta-cantidad",
    name: "cantidad",
    type: "number",
    min: "1",
    step: "1",
    // defaultValue (y no value): formularioVino.reset() vuelve a 1 tras Agregar.
    defaultValue: "1",
    required: true,
    inputMode: "numeric",
    autocomplete: "off",
  });

  const botonAgregarVino = crear(
    "button",
    { type: "submit", className: "boton boton--secundario" },
    "Agregar",
  );

  const formularioVino = crear(
    "form",
    { className: "acciones" },
    crear("label", { htmlFor: "venta-vino" }, "Cód. vino", inputVino),
    crear(
      "label",
      { htmlFor: "venta-cantidad" },
      "Cantidad",
      inputCantidad,
    ),
    botonAgregarVino,
  );

  const cuerpoRenglones = crear("tbody");

  const botonRegistrar = crear(
    "button",
    { type: "button", className: "boton", disabled: true },
    "Registrar venta",
  );

  function actualizarRegistro() {
    botonRegistrar.disabled =
      enviando ||
      clienteElegido === null ||
      !salasDisponibles ||
      selectorSala.value === "" ||
      renglones.length === 0;
  }

  function dibujarRenglones() {
    cuerpoRenglones.replaceChildren();

    if (renglones.length === 0) {
      cuerpoRenglones.append(
        crear(
          "tr",
          {},
          crear(
            "td",
            { colSpan: 4 },
            "Todavía no se agregaron vinos a la venta.",
          ),
        ),
      );
      actualizarRegistro();
      return;
    }

    renglones.forEach((renglon, indice) => {
      const botonQuitar = crear(
        "button",
        {
          type: "button",
          className: "boton boton--secundario boton--compacto",
          "aria-label": `Quitar ${renglon.nombre}`,
          onclick: () => {
            renglones.splice(indice, 1);
            dibujarRenglones();
          },
        },
        "Quitar",
      );

      cuerpoRenglones.append(
        crear(
          "tr",
          {},
          crear("td", {}, renglon.cod_vino),
          crear("td", {}, renglon.nombre),
          crear("td", { className: "numero" }, renglon.cantidad),
          crear("td", {}, botonQuitar),
        ),
      );
    });

    actualizarRegistro();
  }

  inputCliente.addEventListener("input", () => {
    // Una ficha confirmada deja de corresponder al código apenas éste cambia.
    solicitudCliente += 1;
    clienteElegido = null;
    resumenCliente.replaceChildren();
    limpiarMensajes(mensajesCliente);
    botonBuscarCliente.disabled = false;
    botonBuscarCliente.textContent = "Buscar";
    actualizarRegistro();
  });

  formularioCliente.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    if (!formularioCliente.checkValidity()) {
      formularioCliente.reportValidity();
      return;
    }

    const idEscrito = Number(inputCliente.value);
    const solicitudActual = ++solicitudCliente;

    clienteElegido = null;
    resumenCliente.replaceChildren();
    limpiarMensajes(mensajesCliente);
    botonBuscarCliente.disabled = true;
    botonBuscarCliente.textContent = "Buscando…";
    actualizarRegistro();

    try {
      const cliente = await api.obtenerCliente(idEscrito);
      if (solicitudActual !== solicitudCliente) return;

      clienteElegido = cliente;

      // El descuento sólo se muestra: lo calcula fn_descuento_cliente (RN-06).
      resumenCliente.replaceChildren(
        crear(
          "p",
          { className: "venta__cliente-confirmado" },
          crear(
            "strong",
            {},
            `${cliente.nombre_razon_social} · ${cliente.tipo} · descuento ${cliente.descuento} %`,
          ),
        ),
      );
    } catch (error) {
      if (solicitudActual !== solicitudCliente) return;
      clienteElegido = null;
      resumenCliente.replaceChildren();
      mostrarError(mensajesCliente, error);
    } finally {
      if (solicitudActual === solicitudCliente) {
        botonBuscarCliente.disabled = false;
        botonBuscarCliente.textContent = "Buscar";
        actualizarRegistro();
      }
    }
  });

  selectorSala.addEventListener("change", actualizarRegistro);

  formularioVino.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    if (agregandoVino) return;
    if (!formularioVino.checkValidity()) {
      formularioVino.reportValidity();
      return;
    }

    const codVino = Number(inputVino.value);
    const cantidad = Number(inputCantidad.value);

    agregandoVino = true;
    inputVino.disabled = true;
    inputCantidad.disabled = true;
    botonAgregarVino.disabled = true;
    botonAgregarVino.textContent = "Agregando…";
    limpiarMensajes(mensajesVinos);

    try {
      const vino = await api.obtenerVino(codVino);

      // No se agrupan ni suman vinos repetidos: cada agregado conserva su
      // renglón y fn_registrar_venta aplica RN-08 al intentar vender.
      renglones.push({
        cod_vino: codVino,
        cantidad,
        nombre: `${vino.nombre} ${vino.anada}`,
      });

      dibujarRenglones();
      formularioVino.reset();
    } catch (error) {
      mostrarError(mensajesVinos, error);
    } finally {
      agregandoVino = false;
      inputVino.disabled = false;
      inputCantidad.disabled = false;
      botonAgregarVino.disabled = false;
      botonAgregarVino.textContent = "Agregar";
    }
  });

  botonRegistrar.addEventListener("click", async () => {
    // La guarda sincrónica cubre también dos eventos ya encolados por un
    // doble clic, además del disabled visual.
    if (enviando || botonRegistrar.disabled) return;

    enviando = true;
    botonRegistrar.disabled = true;
    botonRegistrar.textContent = "Registrando…";
    limpiarMensajes(mensajesEnvio);

    const pedido = {
      id_cliente: clienteElegido.id_cliente,
      id_sala: Number(selectorSala.value),
      renglones: renglones.map(({ cod_vino, cantidad }) => ({
        cod_vino,
        cantidad,
      })),
    };

    let registrada = false;

    try {
      const comprobante = await api.registrarVenta(pedido);
      registrada = true;
      mostrarComprobante(contenedor, comprobante, {
        cliente: clienteElegido.nombre_razon_social,
        sala: selectorSala.selectedOptions[0]?.textContent ?? "",
      });
    } catch (error) {
      mostrarError(mensajesEnvio, error);
      mensajesEnvio.firstElementChild?.append(
        crear("p", {}, "No se registró ningún comprobante."),
      );
    } finally {
      if (!registrada) {
        enviando = false;
        botonRegistrar.textContent = "Registrar venta";
        actualizarRegistro();
      }
    }
  });

  const pantalla = crear(
    "section",
    { className: "venta" },
    crear("h1", {}, "Nueva venta"),
    crear(
      "section",
      { className: "panel venta__seccion" },
      crear("h2", {}, "Cliente y sala"),
      formularioCliente,
      resumenCliente,
      mensajesCliente,
      crear("label", { htmlFor: "venta-sala" }, "Sala", selectorSala),
      mensajesSala,
    ),
    crear(
      "section",
      { className: "panel venta__seccion" },
      crear("h2", {}, "Vinos"),
      formularioVino,
      crear(
        "div",
        { className: "tabla-contenedor" },
        crear(
          "table",
          {},
          encabezadoTabla("Cód.", "Vino", "#Cantidad", "Quitar"),
          cuerpoRenglones,
        ),
      ),
      mensajesVinos,
    ),
    crear(
      "section",
      { className: "panel venta__seccion" },
      crear("div", { className: "acciones" }, botonRegistrar),
      mensajesEnvio,
    ),
  );

  contenedor.replaceChildren(pantalla);
  dibujarRenglones();

  try {
    const salas = await api.salas();

    // replaceChildren no aplana arrays (a diferencia de crear): por eso el spread.
    selectorSala.replaceChildren(
      crear(
        "option",
        { value: "", selected: true, disabled: true },
        "Seleccione una sala",
      ),
      ...salas.map((sala) =>
        crear(
          "option",
          { value: String(sala.id_sala) },
          `${sala.id_sala} · ${sala.calle} ${sala.numero} (${sala.localidad})`,
        ),
      ),
    );

    salasDisponibles = true;
    selectorSala.disabled = false;
  } catch (error) {
    salasDisponibles = false;
    selectorSala.disabled = true;
    selectorSala.replaceChildren(
      crear(
        "option",
        { value: "", selected: true },
        "No se pudieron cargar las salas",
      ),
    );
    mostrarError(mensajesSala, error);
  }

  actualizarRegistro();
}
