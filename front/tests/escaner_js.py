"""Escáner mínimo de JavaScript para la prueba estática de "sin cálculos".

No es un parser: sólo lo necesario para mirar el CÓDIGO del front sin falsos
positivos. `limpiar` devuelve el mismo texto con los comentarios quitados, el
contenido de los strings vaciado (queda ""), el texto de las plantillas
vaciado (se conservan las expresiones ${...}) y los literales de regex
reemplazados por REGEX. Conserva los saltos de línea: la línea N del resultado
es la línea N del archivo.
"""

import re

# Un "/" abre un literal de regex (y no es una división) cuando lo precede uno
# de estos caracteres o una de estas palabras.
_ANTES_DE_REGEX = "(,=:[!&|?{};"
_PALABRAS_ANTES_DE_REGEX = ("return", "typeof")


def limpiar(fuente: str) -> str:
    salida: list[str] = []
    i, n = 0, len(fuente)

    def ultimo_caracter() -> str:
        for caracter in reversed("".join(salida)):
            if not caracter.isspace():
                return caracter
        return ""

    def ultima_palabra() -> str:
        encontrada = re.search(r"([A-Za-z_$][\w$]*)\s*$", "".join(salida))
        return encontrada.group(1) if encontrada else ""

    def plantilla(desde: int) -> tuple[str, int]:
        """Desde justo después de la ` de apertura: vacía el texto y limpia cada ${...}."""

        partes, j = ["`"], desde
        while j < n:
            c = fuente[j]
            if c == "\\":
                j += 2
            elif c == "`":
                partes.append("`")
                return "".join(partes), j + 1
            elif c == "$" and fuente[j + 1 : j + 2] == "{":
                nivel, k = 1, j + 2
                while k < n and nivel:
                    nivel += {"{": 1, "}": -1}.get(fuente[k], 0)
                    k += 1
                partes.append("${" + limpiar(fuente[j + 2 : k - 1]) + "}")
                j = k
            else:
                if c == "\n":
                    partes.append("\n")
                j += 1
        return "".join(partes), j

    while i < n:
        c, siguiente = fuente[i], fuente[i + 1 : i + 2]
        if c == "/" and siguiente == "/":
            while i < n and fuente[i] != "\n":
                i += 1
        elif c == "/" and siguiente == "*":
            fin = fuente.index("*/", i + 2)
            salida.append("\n" * fuente[i : fin + 2].count("\n"))
            i = fin + 2
        elif c in "\"'":
            i += 1
            while i < n and fuente[i] != c:
                i += 2 if fuente[i] == "\\" else 1
            i += 1
            salida.append(c + c)
        elif c == "`":
            texto, i = plantilla(i + 1)
            salida.append(texto)
        elif c == "/" and (
            ultimo_caracter() == "" or ultimo_caracter() in _ANTES_DE_REGEX
            or ultima_palabra() in _PALABRAS_ANTES_DE_REGEX
        ):
            j, en_clase = i + 1, False
            while j < n:
                if fuente[j] == "\\":
                    j += 2
                    continue
                if fuente[j] == "[":
                    en_clase = True
                elif fuente[j] == "]":
                    en_clase = False
                elif fuente[j] == "/" and not en_clase:
                    break
                j += 1
            j += 1
            while j < n and fuente[j].isalpha():  # banderas: g, i, ...
                j += 1
            salida.append("REGEX")
            i = j
        else:
            salida.append(c)
            i += 1
    return "".join(salida)


# Operadores aritméticos binarios, compuestos, de incremento y el menos unario.
# En el código ya limpio, un "*" o un "/" sólo pueden ser operadores.
OPERADOR_ARITMETICO = re.compile(r"(?<![-+*/=<>!&|?.])(\*\*=?|\+\+|--|[-+*/%]=?)(?![-+*/=>])")
OPERADOR_MULTIPLICATIVO = re.compile(r"[*/]")

# Identificadores de importes, porcentajes y stock (y de la cantidad de botellas).
PALABRA_DE_NEGOCIO = re.compile(
    r"\b\w*(?:precio|subtotal|descuento|total|porcentaje|stock|cantidad|importe|botellas)\w*\b",
    re.IGNORECASE,
)


def lineas_con_aritmetica(fuente: str) -> list[tuple[int, str, str]]:
    """(número de línea, línea original, línea limpia) de cada línea con un operador aritmético."""

    originales = fuente.splitlines()
    encontradas = []
    for numero, limpia in enumerate(limpiar(fuente).splitlines(), start=1):
        if OPERADOR_ARITMETICO.search(limpia):
            encontradas.append((numero, " ".join(originales[numero - 1].split()), limpia))
    return encontradas
