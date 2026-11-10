import { ErrorApi, api } from "./api.js";
import { iniciarRouter } from "./router.js";

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
    "Consultando PostgreSQL.",
  );

  try {
    await api.salud();
    mostrarEstado(
      "disponible",
      "Sistema disponible",
      "La API y PostgreSQL respondieron correctamente.",
    );
  } catch (error) {
    if (!(error instanceof ErrorApi)) {
      console.error(error);
    }

    mostrarEstado(
      "no-disponible",
      "Sistema no disponible",
      error instanceof ErrorApi
        ? `${error.status} · ${error.codigo} — ${error.detail}`
        : "Ocurrió un error inesperado al comprobar la conexión.",
    );
  } finally {
    estado.setAttribute("aria-busy", "false");
    botonReintentar.disabled = false;
    registrarHora();
  }
}

botonReintentar.addEventListener("click", comprobarSalud);
iniciarRouter();
void comprobarSalud();
