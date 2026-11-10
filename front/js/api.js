"use strict";

export class ErrorApi extends Error {
  constructor({ status, codigo, detail, restriccion, errores }) {
    super(detail);
    this.name = "ErrorApi";
    this.status = status;
    this.codigo = codigo;
    this.detail = detail;
    this.restriccion = restriccion;
    this.errores = errores;
  }
}

function armarUrl(ruta, parametros) {
  const baseConfigurada = window.BODEGAS_CONFIG.apiBase;
  const baseConBarra = baseConfigurada.endsWith("/")
    ? baseConfigurada
    : `${baseConfigurada}/`;
  const url = new URL(ruta.replace(/^\/+/, ""), new URL(baseConBarra, window.location.origin));

  for (const [nombre, valor] of Object.entries(parametros ?? {})) {
    if (valor !== "" && valor !== null && valor !== undefined) {
      url.searchParams.set(nombre, valor);
    }
  }

  return url;
}

function errorHttp(status) {
  return new ErrorApi({
    status,
    codigo: `http_${status}`,
    detail: `La API respondió con estado HTTP ${status}.`,
  });
}

async function pedir(metodo, ruta, { cuerpo, parametros } = {}) {
  const url = armarUrl(ruta, parametros);
  const opciones = {
    method: metodo,
    headers: { Accept: "application/json" },
  };

  if (cuerpo !== undefined) {
    opciones.headers["Content-Type"] = "application/json";
    opciones.body = JSON.stringify(cuerpo);
  }

  let respuesta;
  try {
    respuesta = await fetch(url, opciones);
  } catch {
    throw new ErrorApi({
      status: 0,
      codigo: "sin_conexion",
      detail: "No se pudo conectar con la API.",
    });
  }

  if (respuesta.status === 204) {
    return null;
  }

  let datos;
  try {
    datos = await respuesta.json();
  } catch {
    throw errorHttp(respuesta.status);
  }

  if (!respuesta.ok) {
    throw new ErrorApi({
      status: respuesta.status,
      codigo: datos?.codigo ?? `http_${respuesta.status}`,
      detail: datos?.detail ?? `La API respondió con estado HTTP ${respuesta.status}.`,
      restriccion: datos?.restriccion,
      errores: datos?.errores,
    });
  }

  return datos;
}

export const api = {
  salud() {
    return pedir("GET", "/salud");
  },

  listarVinos(filtros = {}) {
    return pedir("GET", "/vinos", { parametros: filtros });
  },

  obtenerVino(cod) {
    return pedir("GET", `/vinos/${encodeURIComponent(cod)}`);
  },

  crearVino(datos) {
    return pedir("POST", "/vinos", { cuerpo: datos });
  },

  modificarVino(cod, datos) {
    return pedir("PUT", `/vinos/${encodeURIComponent(cod)}`, { cuerpo: datos });
  },

  eliminarVino(cod) {
    return pedir("DELETE", `/vinos/${encodeURIComponent(cod)}`);
  },

  obtenerCliente(id) {
    return pedir("GET", `/clientes/${encodeURIComponent(id)}`);
  },

  registrarVenta({ id_cliente, id_sala, renglones }) {
    return pedir("POST", "/comprobantes", {
      cuerpo: { id_cliente, id_sala, renglones },
    });
  },

  obtenerComprobante(nro) {
    return pedir("GET", `/comprobantes/${encodeURIComponent(nro)}`);
  },

  crearTransferencia(idSala) {
    return pedir("POST", "/transferencias", { cuerpo: { id_sala: idSala } });
  },

  obtenerTransferencia(nro) {
    return pedir("GET", `/transferencias/${encodeURIComponent(nro)}`);
  },

  agregarRenglonTransferencia(nro, { cod_vino, cantidad }) {
    return pedir("POST", `/transferencias/${encodeURIComponent(nro)}/renglones`, {
      cuerpo: { cod_vino, cantidad },
    });
  },

  terminarTransferencia(nro) {
    return pedir("POST", `/transferencias/${encodeURIComponent(nro)}/terminar`);
  },

  procesarTransferencia(nro) {
    return pedir("POST", `/transferencias/${encodeURIComponent(nro)}/procesar`);
  },

  topVinos(limite) {
    return pedir("GET", "/reportes/top-vinos", { parametros: { limite } });
  },

  ventasPorSala({ desde, hasta } = {}) {
    return pedir("GET", "/reportes/ventas-por-sala", {
      parametros: { desde, hasta },
    });
  },

  vinosSinStock(idSala) {
    return pedir("GET", "/reportes/vinos-sin-stock", {
      parametros: { id_sala: idSala },
    });
  },

  tiposVino() {
    return pedir("GET", "/catalogos/tipos-vino");
  },

  cepas() {
    return pedir("GET", "/catalogos/cepas");
  },

  bodegas() {
    return pedir("GET", "/catalogos/bodegas");
  },

  maridajes() {
    return pedir("GET", "/catalogos/maridajes");
  },

  salas() {
    return pedir("GET", "/catalogos/salas");
  },
};
