"use strict";

const RUTA_SALUD = "/api/salud";

const estado = document.querySelector("#estado");
const estadoTexto = document.querySelector("#estado-texto");
const estadoDetalle = document.querySelector("#estado-detalle");
const horaComprobacion = document.querySelector("#hora-comprobacion");
const botonReintentar = document.querySelector("#reintentar");

function mostrarEstado(tipo, titulo, detalle) {
  estado.className = `estado estado--${tipo}`;
  estadoTexto.textContent = titulo;
  estadoDetalle.textContent = detalle;
}

function registrarHora() {
  const ahora = new Date();
  horaComprobacion.dateTime = ahora.toISOString();
  horaComprobacion.textContent = new Intl.DateTimeFormat("es-AR", {
    dateStyle: "short",
    timeStyle: "medium",
  }).format(ahora);
}

async function comprobarSalud() {
  botonReintentar.disabled = true;
  estado.setAttribute("aria-busy", "true");
  mostrarEstado(
    "comprobando",
    "Comprobando conexión…",
    "Consultando el estado real de PostgreSQL.",
  );

  try {
    const respuesta = await fetch(RUTA_SALUD, {
      headers: { Accept: "application/json" },
      cache: "no-store",
    });

    if (respuesta.ok) {
      mostrarEstado(
        "disponible",
        "Base de datos disponible",
        "La API respondió correctamente después de consultar PostgreSQL.",
      );
    } else {
      mostrarEstado(
        "no-disponible",
        "Base de datos no disponible",
        "La comprobación no respondió correctamente. Podés volver a intentarlo.",
      );
    }
  } catch {
    mostrarEstado(
      "no-disponible",
      "No fue posible comprobar la conexión",
      "La API no está disponible en este momento. Podés volver a intentarlo.",
    );
  } finally {
    estado.setAttribute("aria-busy", "false");
    botonReintentar.disabled = false;
    registrarHora();
  }
}

botonReintentar.addEventListener("click", comprobarSalud);
comprobarSalud();
