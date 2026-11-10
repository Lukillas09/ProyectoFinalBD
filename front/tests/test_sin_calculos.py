"""El front no calcula importes, descuentos, porcentajes ni stock (criterio 3 de la consigna).

Prueba estática sobre el código de front/js (montado en sólo lectura en
/front, ver docker-compose.yml). Se analiza el código SIN comentarios ni
textos: una fórmula escrita en un comentario no cuenta como operación.

Dos reglas, ambas con lista explícita de excepciones justificadas:

1. Toda operación aritmética del front está listada abajo con su motivo. Si
   aparece una nueva, la prueba falla hasta que alguien la justifique (o la
   quite). Si una listada desaparece, también falla, para que la lista no
   envejezca.
2. Ninguna línea que nombre precios, descuentos, totales, porcentajes, stock o
   cantidades opera sobre ellos, salvo las dos justificadas en
   SOBRE_PALABRAS_DE_NEGOCIO.

El criterio para identificar cada excepción es el archivo y un fragmento de la
línea (no el número de línea, que cambia con cualquier edición).
"""

import os
import re
from pathlib import Path

import pytest

from escaner_js import PALABRA_DE_NEGOCIO, lineas_con_aritmetica, limpiar

FRONT = Path(os.environ.get("FRONT_DIR", "/front"))
ARCHIVOS = sorted((FRONT / "js").rglob("*.js"))

# (archivo, fragmento de la línea, motivo). Ninguna opera sobre un importe, un
# descuento, un porcentaje ni el stock: son paginación, geometría del gráfico,
# contadores y posiciones.
OPERACIONES_PERMITIDAS = [
    ("catalogo.js", "colSpan: COLUMNAS.length + 1",
     "ancho de la fila de aviso: cantidad de columnas de la tabla"),
    ("catalogo.js", "(estado.pagina - 1) * LIMITE",
     "paginación: de número de página a filas que se saltean"),
    ("catalogo.js", "Math.ceil(total / limite)",
     "paginación: cantidad de páginas; `total` es la cantidad de vinos que devuelve la API, no un importe"),
    ("catalogo.js", "pagina: estado.pagina - 1", "paginación: página anterior"),
    ("catalogo.js", "pagina: estado.pagina + 1", "paginación: página siguiente"),
    ("tablero.js", "indice + 1", "posición en el ranking, que ordenó la base"),
    ("tablero.js", "Number(sala.total_ventas) / maximo",
     "ESCALA VISUAL del gráfico: cuántos píxeles mide la barra. El importe que se lee es el string de la base"),
    ("tablero.js", "indice * ALTO_FILA", "geometría del gráfico: altura de cada fila"),
    ("tablero.js", "items.length * ALTO_FILA", "geometría del gráfico: alto del viewBox"),
    ("tablero.js", '+ "en el último trimestre', "concatenación de dos textos del aria-label del gráfico"),
    ("tablero.js", "++solicitud", "contador de consultas en curso, para descartar respuestas viejas"),
    ("venta.js", "solicitudCliente += 1", "contador de búsquedas de cliente, para descartar respuestas viejas"),
    ("venta.js", "++solicitudCliente", "contador de búsquedas de cliente, para descartar respuestas viejas"),
    ("vino.js", "indice + 1", "número de fila de la composición, para sus etiquetas accesibles (Cepa 1, 2, …)"),
    ("router.js", "separador === -1", "separar la ruta de la consulta del hash: posición del '?'"),
    ("router.js", "++versionNavegacion", "contador de navegaciones, para descartar respuestas viejas"),
]

# Las únicas líneas que nombran importes o cantidades y tienen una operación.
SOBRE_PALABRAS_DE_NEGOCIO = [
    ("catalogo.js", "Math.ceil(total / limite)"),
    ("tablero.js", "Number(sala.total_ventas) / maximo"),
]


def _operaciones_encontradas() -> list[tuple[str, int, str, str]]:
    """(archivo, línea, texto original, texto limpio) de cada operación aritmética del front."""

    return [
        (archivo.name, numero, original, limpia)
        for archivo in ARCHIVOS
        for numero, original, limpia in lineas_con_aritmetica(archivo.read_text(encoding="utf-8"))
    ]


def test_se_encontraron_los_archivos_del_front() -> None:
    nombres = {archivo.name for archivo in ARCHIVOS}
    assert {"api.js", "ui.js", "router.js", "catalogo.js", "vino.js", "venta.js",
            "transferencias.js", "tablero.js"} <= nombres, f"no se leyó el front en {FRONT}"


def test_fetch_esta_solo_en_api_js() -> None:
    usan_fetch = {
        archivo.name for archivo in ARCHIVOS
        if re.search(r"\bfetch\s*\(", limpiar(archivo.read_text(encoding="utf-8")))
    }
    assert usan_fetch == {"api.js"}, f"fetch( fuera de la capa api.js: {usan_fetch - {'api.js'}}"


@pytest.mark.parametrize("prohibido", [r"\.innerHTML\b", r"\balert\s*\(", r"\bconfirm\s*\(", r"\bparseFloat\s*\("])
def test_no_hay_construcciones_prohibidas(prohibido: str) -> None:
    donde = [
        archivo.name for archivo in ARCHIVOS
        if re.search(prohibido, limpiar(archivo.read_text(encoding="utf-8")))
    ]
    assert not donde, f"{prohibido} aparece en {donde}"


def test_toda_operacion_aritmetica_esta_justificada() -> None:
    encontradas = _operaciones_encontradas()

    sin_justificar = [
        f"{archivo}:{numero}: {original}"
        for archivo, numero, original, _ in encontradas
        if not any(archivo == a and fragmento in original for a, fragmento, _ in OPERACIONES_PERMITIDAS)
    ]
    assert not sin_justificar, (
        "Operaciones aritméticas nuevas en el front. Si no operan sobre importes, descuentos, "
        "porcentajes ni stock, listalas en OPERACIONES_PERMITIDAS con su motivo; si sí, quitalas "
        "(esas cuentas son de PostgreSQL):\n" + "\n".join(sin_justificar)
    )

    sin_usar = [
        f"{a}: {fragmento}"
        for a, fragmento, _ in OPERACIONES_PERMITIDAS
        if not any(archivo == a and fragmento in original for archivo, _, original, _ in encontradas)
    ]
    assert not sin_usar, "Excepciones listadas que ya no aparecen (quitarlas):\n" + "\n".join(sin_usar)


def test_ninguna_operacion_toca_importes_ni_stock() -> None:
    sobre_negocio = [
        (archivo, original)
        for archivo, _, original, limpia in _operaciones_encontradas()
        if PALABRA_DE_NEGOCIO.search(limpia)
    ]

    nuevas = [
        f"{archivo}: {original}" for archivo, original in sobre_negocio
        if not any(archivo == a and fragmento in original for a, fragmento in SOBRE_PALABRAS_DE_NEGOCIO)
    ]
    assert not nuevas, (
        "Una operación aritmética nombra precio, descuento, total, porcentaje, stock o cantidad. "
        "El front no calcula esos valores:\n" + "\n".join(nuevas)
    )
    # Las dos justificadas existen todavía (la lista no envejece).
    assert len(sobre_negocio) == len(SOBRE_PALABRAS_DE_NEGOCIO), sobre_negocio
