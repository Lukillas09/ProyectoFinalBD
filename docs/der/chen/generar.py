"""Genera el DER de Bodegas del Atuel en notación de Chen (Graphviz).

Fuente única del DER conceptual: las entidades, atributos, relaciones y
cardinalidades se declaran una sola vez en este archivo y de acá salen todas
las vistas, así no pueden contradecirse entre sí.

Uso (requiere Graphviz):
    python3 docs/der/chen/generar.py

Escribe en esta misma carpeta, para cada vista, el .dot (fuente editable) y su
.png y .svg, y une todas las vistas en der_chen.pdf.

Notación (la de los apuntes de la cátedra, "BD - Modelo conceptual"):
- rectángulo: entidad; rectángulo doble: entidad débil;
- rombo: relación; rombo doble: relación identificadora de la débil;
- elipse: atributo; subrayado: clave primaria; elipse punteada: derivado;
- elipse con elipses hijas: atributo compuesto;
- triángulo "ES UN": jerarquía, con línea doble si es total;
- (mín,máx) junto a cada entidad: en cuántas ocurrencias de la relación
  participa cada ocurrencia de esa entidad.
Las claves foráneas NO se dibujan: en el modelo conceptual las representan las
relaciones; aparecen recién en el esquema relacional.
"""

import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

CARPETA = Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# Modelo
# ---------------------------------------------------------------------------

@dataclass
class Atributo:
    nombre: str
    clave: bool = False          # clave primaria (subrayado)
    parcial: bool = False        # clave parcial de una entidad débil
    derivado: bool = False       # se calcula a partir de otros datos
    partes: list[str] = field(default_factory=list)  # atributo compuesto
    nota: str = ""


@dataclass
class Entidad:
    nombre: str
    atributos: list[Atributo]
    debil: bool = False


@dataclass
class Relacion:
    nombre: str
    extremos: list[tuple[str, str]]   # (entidad, "(mín,máx)")
    atributos: list[Atributo] = field(default_factory=list)
    identificadora: bool = False


A = Atributo

ENTIDADES = {e.nombre: e for e in [
    Entidad("Departamento", [A("id_departamento", clave=True), A("nombre"), A("provincia")]),
    Entidad("Localidad", [A("id_localidad", clave=True), A("codigo_postal"), A("nombre"),
                          A("provincia"), A("encargado_regional")]),
    Entidad("Sala de venta", [A("id_sala", clave=True),
                              A("direccion", partes=["calle", "numero"]), A("dia_cierre")]),
    Entidad("Empleado", [A("cuit", clave=True), A("nombre"), A("fecha_ingreso"), A("salario"),
                         A("antiguedad", derivado=True)]),
    Entidad("Finca", [A("id_finca", clave=True), A("nombre"), A("superficie_ha")]),
    Entidad("Parcela", [A("nro_parcela", parcial=True), A("superficie_ha"),
                        A("anio_plantacion")], debil=True),
    Entidad("Cepa", [A("id_cepa", clave=True), A("nombre"), A("tipo")]),
    Entidad("Lote de uva", [A("nro_lote", clave=True), A("campania"), A("fecha_cosecha"),
                            A("kilos")]),
    Entidad("Análisis de calidad", [A("id_analisis", clave=True), A("fecha_analisis"),
                                    A("grado_brix"), A("ph"), A("acidez_total")]),
    Entidad("Bodega", [A("cuit", clave=True), A("razon_social"), A("domicilio")]),
    Entidad("Vino", [A("cod_vino", clave=True), A("nombre"), A("tipo"), A("anada"),
                     A("volumen_ml"), A("graduacion"), A("precio"),
                     A("stock_deposito", nota="depósito único")]),
    Entidad("Maridaje", [A("id_maridaje", clave=True), A("nombre"),
                         A("temperatura_servicio_c")]),
    Entidad("Cliente", [A("id_cliente", clave=True), A("nombre_razon_social"),
                        A("documento", partes=["tipo_documento", "nro_documento"]),
                        A("direccion"), A("fecha_alta"), A("tipo", nota="discriminador"),
                        A("descuento_excepcion"), A("descuento", derivado=True)]),
    Entidad("Socio del club", []),
    Entidad("Distribuidor", [A("zona_cobertura"), A("nro_habilitacion")]),
    Entidad("Exportador", [A("pais_destino_principal")]),
    Entidad("Permiso de exportación", [A("codigo_permiso", clave=True), A("fecha_emision"),
                                       A("fecha_vencimiento")]),
    Entidad("Comprobante", [A("nro_comprobante", clave=True), A("fecha"),
                            A("subtotal", derivado=True), A("descuento", derivado=True),
                            A("total", derivado=True)]),
    Entidad("Transportista", [A("cod_transportista", clave=True), A("razon_social"), A("cuit"),
                              A("email"), A("telefono"), A("domicilio")]),
    Entidad("Ingreso", [A("cod_ingreso", clave=True), A("fecha"), A("estado")]),
    Entidad("Transferencia", [A("nro_transferencia", clave=True), A("fecha_confeccion"),
                              A("estado")]),
    Entidad("Auditoría de precio", [A("id_auditoria", clave=True), A("precio_anterior"),
                                    A("precio_nuevo"), A("fecha_hora"), A("usuario_bd")]),
]}

# Cardinalidades de docs/modelo_conceptual.md, sección 5.
RELACIONES = [
    Relacion("se ubica en", [("Sala de venta", "(1,1)"), ("Localidad", "(0,N)")]),
    Relacion("trabaja en", [("Empleado", "(1,1)"), ("Sala de venta", "(1,N)")]),
    Relacion("pertenece a", [("Finca", "(1,1)"), ("Departamento", "(0,N)")]),
    Relacion("se divide en", [("Finca", "(1,N)"), ("Parcela", "(1,1)")], identificadora=True),
    Relacion("está plantada con", [("Parcela", "(1,1)"), ("Cepa", "(0,N)")]),
    Relacion("produce", [("Parcela", "(0,N)"), ("Lote de uva", "(1,1)")]),
    Relacion("se entrega a", [("Lote de uva", "(1,1)"), ("Bodega", "(0,N)")]),
    Relacion("se analiza en", [("Lote de uva", "(1,N)"), ("Análisis de calidad", "(1,1)")]),
    Relacion("elabora", [("Bodega", "(1,N)"), ("Vino", "(1,1)")]),
    Relacion("se compone de", [("Vino", "(1,N)"), ("Cepa", "(0,N)")],
             [A("porcentaje")]),
    Relacion("marida con", [("Vino", "(1,N)"), ("Maridaje", "(0,N)")]),
    Relacion("reside en", [("Cliente", "(1,1)"), ("Localidad", "(0,N)")]),
    Relacion("posee", [("Exportador", "(0,N)"), ("Permiso de exportación", "(1,1)")]),
    Relacion("realiza", [("Cliente", "(0,N)"), ("Comprobante", "(1,1)")]),
    Relacion("se emite en", [("Comprobante", "(1,1)"), ("Sala de venta", "(0,N)")]),
    Relacion("incluye", [("Comprobante", "(1,N)"), ("Vino", "(0,N)")],
             [A("cantidad"), A("precio_unitario"), A("descuento_porcentaje"),
              A("subtotal", derivado=True)]),
    Relacion("cubre", [("Transportista", "(0,N)"), ("Localidad", "(0,N)")]),
    Relacion("transporta", [("Transportista", "(0,N)"), ("Ingreso", "(1,1)")]),
    Relacion("envía", [("Bodega", "(0,N)"), ("Ingreso", "(1,1)")]),
    Relacion("ingresa", [("Ingreso", "(0,N)*"), ("Vino", "(0,N)")], [A("cantidad")]),
    Relacion("solicita", [("Sala de venta", "(0,N)"), ("Transferencia", "(1,1)")]),
    Relacion("transfiere", [("Transferencia", "(0,N)*"), ("Vino", "(0,N)")], [A("cantidad")]),
    Relacion("tiene en stock", [("Sala de venta", "(0,N)"), ("Vino", "(0,N)")], [A("cantidad")]),
    Relacion("registra", [("Vino", "(0,N)"), ("Auditoría de precio", "(1,1)")]),
]

JERARQUIA = ("Cliente", ["Socio del club", "Distribuidor", "Exportador"], "total, exclusiva")

# Vistas: la general (sólo claves) y una por área con todos los atributos.
# Las entidades de "referencia" se detallan en otra vista: se dibujan en gris
# y sólo con su clave, para mostrar la relación sin repetir atributos. Una
# relación entre dos referencias pertenece a otra vista, salvo que se pida
# explícitamente (último elemento opcional de la vista).
VISTAS = [
    ("00_der_general", "DER general (sólo claves)", list(ENTIDADES), [], True),
    ("01_produccion_y_red_comercial", "Producción de uva y red comercial",
     ["Departamento", "Finca", "Parcela", "Cepa", "Lote de uva", "Análisis de calidad",
      "Localidad", "Sala de venta", "Empleado"], ["Bodega"], False),
    ("02_vinos", "Vinos, composición, maridajes y auditoría",
     ["Bodega", "Vino", "Cepa", "Maridaje", "Auditoría de precio"], [], False),
    ("03_clientes_y_ventas", "Clientes y ventas",
     ["Cliente", "Socio del club", "Distribuidor", "Exportador", "Permiso de exportación",
      "Comprobante"], ["Localidad", "Sala de venta", "Vino"], False),
    ("04_logistica_y_stock", "Logística y stock",
     ["Transportista", "Ingreso", "Transferencia"],
     ["Localidad", "Bodega", "Vino", "Sala de venta"], False, ["tiene en stock"]),
]


# ---------------------------------------------------------------------------
# Generación de DOT
# ---------------------------------------------------------------------------

def _id(*partes: str) -> str:
    return '"' + "__".join(partes).replace('"', "") + '"'


def _esc(texto: str) -> str:
    return texto.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _atributo(dot: list[str], dueño: str, atr: Atributo, gris: bool = False) -> None:
    nodo = _id(dueño, atr.nombre)
    texto = _esc(atr.nombre)
    if atr.clave or atr.parcial:
        texto = f"<U>{texto}</U>"
    if atr.parcial:
        texto += '<BR/><FONT POINT-SIZE="8">clave parcial</FONT>'
    if atr.nota:
        texto += f'<BR/><FONT POINT-SIZE="8">{_esc(atr.nota)}</FONT>'
    estilo = "dashed" if atr.derivado else "solid"
    color = "gray55" if gris else "black"
    dot.append(f'  {nodo} [shape=ellipse, style="{estilo}", color={color}, '
               f'fontcolor={color}, label=<{texto}>];')
    dot.append(f'  {_id(dueño)} -- {nodo} [color={color}, len=0.9];')
    for parte in atr.partes:
        hijo = _id(dueño, atr.nombre, parte)
        dot.append(f'  {hijo} [shape=ellipse, label="{_esc(parte)}"];')
        dot.append(f'  {nodo} -- {hijo} [len=0.8];')


def vista_dot(titulo: str, propias: list[str], referencias: list[str], solo_claves: bool,
              extra: tuple[str, ...] = ()) -> str:
    visibles = set(propias) | set(referencias)
    dot = [
        "graph DER {",
        '  graph [layout=neato, overlap=false, sep="+10", splines=true, esep="+6",',
        f'         fontname="DejaVu Sans", fontsize=20, labelloc=t, label="{titulo}", pad=0.4];',
        '  node [fontname="DejaVu Sans", fontsize=11, margin="0.08,0.04"];',
        '  edge [fontname="DejaVu Sans", fontsize=10, len=1.3];',
    ]
    for nombre in propias + referencias:
        entidad = ENTIDADES[nombre]
        gris = nombre in referencias
        estilo = 'style=filled, fillcolor="#eeeeee", color=gray55, fontcolor=gray35' if gris \
            else 'style=filled, fillcolor="#dde6f7", penwidth=1.6'
        doble = ", peripheries=2" if entidad.debil else ""
        dot.append(f'  {_id(nombre)} [shape=box, label="{_esc(nombre)}", '
                   f'fontsize=13, {estilo}{doble}];')
        atributos = entidad.atributos
        if solo_claves or gris:
            atributos = [a for a in atributos if a.clave or a.parcial]
        for atr in atributos:
            _atributo(dot, nombre, atr, gris)

    for rel in RELACIONES:
        entidades_rel = [e for e, _ in rel.extremos]
        if not all(e in visibles for e in entidades_rel):
            continue
        # Una relación entre dos entidades de referencia es de otra vista.
        if all(e in referencias for e in entidades_rel) and rel.nombre not in extra:
            continue
        nodo = _id("rel", rel.nombre, *entidades_rel)
        doble = ", peripheries=2" if rel.identificadora else ""
        dot.append(f'  {nodo} [shape=diamond, style=filled, fillcolor="#fbeccf", '
                   f'label="{_esc(rel.nombre)}", fontsize=10, margin="0.02,0.02"{doble}];')
        for entidad, card in rel.extremos:
            # Línea doble: participación total de la débil en su relación identificadora.
            color = '"black:invis:black"' if rel.identificadora and card == "(1,1)" else "black"
            dot.append(f'  {_id(entidad)} -- {nodo} [taillabel=<<B>{card}</B>>, labeldistance=2.2, '
                       f'labelangle=25, labelfontsize=12, labelfontcolor="#8b1a1a", '
                       f'color={color}, len=1.6];')
        if not solo_claves:
            for atr in rel.atributos:
                _atributo(dot, "rel " + rel.nombre + " " + "-".join(entidades_rel), atr)
                # _atributo dibuja la arista desde _id(dueño); la redirijo al rombo.
                dot[-1] = dot[-1].replace(
                    _id("rel " + rel.nombre + " " + "-".join(entidades_rel)), nodo, 1)

    supertipo, subtipos, tipo = JERARQUIA
    if supertipo in visibles and all(s in visibles for s in subtipos):
        isa = _id("isa", supertipo)
        dot.append(f'  {isa} [shape=triangle, style=filled, fillcolor="#e3f1df", '
                   f'label=<ES UN<BR/><FONT POINT-SIZE="8">{tipo}</FONT>>, fontsize=10];')
        dot.append(f'  {_id(supertipo)} -- {isa} [color="black:invis:black", len=1.0];')
        for sub in subtipos:
            dot.append(f'  {isa} -- {_id(sub)} [len=1.2];')

    dot.append("}")
    return "\n".join(dot) + "\n"


def leyenda_dot() -> str:
    return """graph Leyenda {
  graph [layout=dot, rankdir=LR, fontname="DejaVu Sans", fontsize=20, labelloc=t,
         label="Notación (Chen, apuntes de la cátedra)", pad=0.4, nodesep=0.35];
  node [fontname="DejaVu Sans", fontsize=11];
  edge [fontname="DejaVu Sans", fontsize=10];
  subgraph c1 { rank=same;
    e  [shape=box, style=filled, fillcolor="#dde6f7", penwidth=1.6, label="Entidad"];
    d  [shape=box, style=filled, fillcolor="#dde6f7", penwidth=1.6, peripheries=2, label="Entidad débil"];
    r  [shape=diamond, style=filled, fillcolor="#fbeccf", label="Relación"];
    ri [shape=diamond, style=filled, fillcolor="#fbeccf", peripheries=2, label="Relación\\nidentificadora"];
    h  [shape=triangle, style=filled, fillcolor="#e3f1df", label=<ES UN<BR/><FONT POINT-SIZE="8">total, exclusiva</FONT>>];
  }
  subgraph c2 { rank=same;
    a  [shape=ellipse, label="atributo"];
    k  [shape=ellipse, label=<<U>clave primaria</U>>];
    p  [shape=ellipse, label=<<U>clave parcial</U><BR/><FONT POINT-SIZE="8">de la entidad débil</FONT>>];
    v  [shape=ellipse, style=dashed, label="derivado"];
    c  [shape=ellipse, label="compuesto"];
  }
  ref [shape=box, style=filled, fillcolor="#eeeeee", color=gray55, fontcolor=gray35,
       label="Entidad detallada en otra vista"];
  card [shape=plaintext, label=<<B>(mín,máx)</B> junto a una entidad: en cuántas ocurrencias de la relación<BR/>participa cada ocurrencia de esa entidad. N = muchos.<BR/><B>(0,N)*</B>: un ingreso o transferencia en confección puede no tener renglones;<BR/>para terminarlo necesita al menos uno, (1,N) (RN-10, RN-11).<BR/><B>Línea doble</B>: participación total (débil en su identificadora; jerarquía total).<BR/>Las claves foráneas no se dibujan: las representan las relaciones.>];
  e -- a [style=invis]; d -- p [style=invis]; r -- v [style=invis];
  h -- c [style=invis]; ri -- k [style=invis];
  c1 [shape=ellipse, label="parte 1"]; c2 [shape=ellipse, label="parte 2"];
  c -- c1; c -- c2;
  k -- ref [style=invis]; ref -- card [style=invis];
}
"""


def main() -> None:
    if shutil.which("dot") is None:
        raise SystemExit("Falta Graphviz (comando 'dot').")
    pdfs = []
    salidas = [("99_leyenda", leyenda_dot())] + [
        (vista[0], vista_dot(*vista[1:]))
        for vista in VISTAS
    ]
    for archivo, texto in salidas:
        fuente = CARPETA / f"{archivo}.dot"
        fuente.write_text(texto, encoding="utf-8")
        for formato in ("png", "svg", "pdf"):
            destino = CARPETA / f"{archivo}.{formato}"
            opciones = ["-Gdpi=130"] if formato == "png" else []
            subprocess.run(["dot", *opciones, f"-T{formato}", str(fuente), "-o", str(destino)],
                           check=True)
        pdfs.append(CARPETA / f"{archivo}.pdf")
    # Un solo PDF para el informe: leyenda primero, después la general y las áreas.
    orden = [pdfs[0]] + pdfs[1:]
    subprocess.run(["pdfunite", *map(str, orden), str(CARPETA / "der_chen.pdf")], check=True)
    for pdf in pdfs:
        pdf.unlink()
    print("Generado:", ", ".join(a for a, _ in salidas), "+ der_chen.pdf")


if __name__ == "__main__":
    main()
