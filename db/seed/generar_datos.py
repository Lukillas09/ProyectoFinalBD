"""Carga masiva reproducible de Bodegas del Atuel (Etapa 3).

Uso (dentro del servicio seed de Docker Compose):
    python generar_datos.py cargar   # genera y carga en una base sin datos
    python generar_datos.py medir    # compara fila por fila, lotes y COPY

Parámetros por variable de entorno:
    SEMILLA            entero; misma semilla => mismos datos (por omisión 20260427)
    FECHA_REFERENCIA   AAAA-MM-DD; "hoy" de la historia simulada (por omisión 2026-10-27)
    ESCALA             factor de volumen de las tablas grandes, 0 < ESCALA <= 6

"Mismos datos" significa misma SEMILLA, FECHA_REFERENCIA y ESCALA, y las mismas
versiones de Python, psycopg y Faker (ver Dockerfile y requirements.txt).

Decisiones (detalle en docs/carga_masiva.md):
- Python sólo simula la historia: fechas, quién compra qué y cuánto, cuándo se
  repone. Así el stock nunca baja de 0 en ningún momento. Precios
  históricos, descuentos, subtotales, importes de comprobante y stocks finales
  los calcula PostgreSQL al cargar (regla del proyecto: esos cálculos
  pertenecen a la base).
- Claves explícitas: las pruebas consumen valores IDENTITY aunque terminen en
  ROLLBACK; con claves explícitas los datos no dependen del estado de las
  secuencias. Al final se ajusta cada secuencia con setval.
- Toda la carga es una transacción. Se deshabilitan sólo los triggers que
  chocan con una historia (TRIGGERS_HISTORICOS); los demás, incluidos los
  constraint triggers diferidos, validan los datos al confirmar.
  ALTER TABLE ... DISABLE TRIGGER es transaccional: si algo falla, el ROLLBACK
  los vuelve a habilitar.
"""

import argparse
import csv
import os
import random
import sys
import time
from bisect import bisect_right
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from itertools import accumulate
from pathlib import Path

import psycopg
from faker import Faker

CATALOGOS = Path(__file__).resolve().parent / "catalogos"
# Argentina no usa horario de verano desde 2009: UTC-3 fijo, sin depender de
# la base tzdata del contenedor.
TZ = timezone(timedelta(hours=-3))
ESCALA_MAXIMA = 6  # por encima, los IDs alcanzarían el rango 910001 de las pruebas
USUARIO_CARGA = "carga_historica"

# Triggers que chocan con una carga histórica (decisión a′). Los demás quedan
# activos durante la carga.
TRIGGERS_HISTORICOS = [
    ("renglon_comprobante", "trg_renglon_comprobante_completar"),  # precio y descuento actuales, stock de hoy, RN-12
    ("renglon_comprobante", "trg_renglon_comprobante_impactar"),   # stock e importes fila por fila
    ("ingreso", "trg_ingreso_estado"),                             # sólo admite altas en confección
    ("transferencia", "trg_transferencia_estado"),
    ("renglon_ingreso", "trg_renglon_ingreso_bloqueo"),            # renglones sólo en confección
    ("renglon_transferencia", "trg_renglon_transferencia_bloqueo"),
    ("transferencia", "trg_transferencia_fecha"),                  # fuerza la fecha de hoy
]

TABLAS_NEGOCIO = [
    "departamento", "localidad", "sala_venta", "empleado", "finca", "cepa",
    "parcela", "bodega", "lote_uva", "analisis_calidad", "vino",
    "composicion_vino", "maridaje", "vino_maridaje", "auditoria_precio",
    "cliente", "socio_club", "distribuidor", "exportador",
    "permiso_exportacion", "transportista", "transportista_localidad",
    "ingreso", "renglon_ingreso", "transferencia", "renglon_transferencia",
    "comprobante", "renglon_comprobante", "stock_deposito", "stock_sala",
]

PAISES_EXPORTACION = [
    "Brasil", "Chile", "Estados Unidos", "China", "Reino Unido", "Canadá",
    "México", "Países Bajos", "Alemania", "Japón", "Paraguay", "Uruguay",
]
LINEAS_VINO = ["Joven", "Roble", "Clásico", "Reserva", "Gran Reserva", "Selección", "Icono"]
DIAS_CIERRE = ["lunes", "miercoles", "lunes", "miercoles", "martes", "jueves", "domingo"]


@dataclass(frozen=True)
class Parametros:
    semilla: int
    fecha_ref: date
    escala: float

    @property
    def inicio_comercio(self) -> date:
        return restar_anios(self.fecha_ref, 6)


def restar_anios(fecha: date, anios: int) -> date:
    try:
        return fecha.replace(year=fecha.year - anios)
    except ValueError:  # 29 de febrero
        return fecha.replace(year=fecha.year - anios, day=28)


def leer_parametros() -> Parametros:
    semilla = int(os.environ.get("SEMILLA", "20260427"))
    fecha_ref = date.fromisoformat(os.environ.get("FECHA_REFERENCIA", "2026-10-27"))
    escala = float(os.environ.get("ESCALA", "1"))
    if not 0 < escala <= ESCALA_MAXIMA:
        sys.exit(f"ESCALA debe estar entre 0 y {ESCALA_MAXIMA} (recibido {escala}).")
    return Parametros(semilla, fecha_ref, escala)


def leer_csv(nombre: str) -> list[dict]:
    with open(CATALOGOS / nombre, encoding="utf-8", newline="") as archivo:
        return list(csv.DictReader(archivo))


def cuit(prefijo: int, numero: int) -> str | None:
    """CUIT con dígito verificador. None si el verificador sería 10."""
    base = f"{prefijo:02d}{numero:08d}"
    suma = sum(int(d) * p for d, p in zip(base, [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]))
    resto = 11 - suma % 11
    if resto == 10:
        return None
    return base + str(0 if resto == 11 else resto)


def cuits_unicos(rng: random.Random, prefijos: list[int], desde: int, hasta: int, cantidad: int) -> list[str]:
    """CUIT distintos con número entre desde y hasta (rango ajeno a las pruebas)."""
    resultado, usados = [], set()
    while len(resultado) < cantidad:
        valor = cuit(rng.choice(prefijos), rng.randint(desde, hasta))
        if valor and valor not in usados:
            usados.add(valor)
            resultado.append(valor)
    return resultado


def momento(dia: date, rng: random.Random, desde_hora: int, hasta_hora: int) -> datetime:
    return datetime(dia.year, dia.month, dia.day,
                    rng.randint(desde_hora, hasta_hora), rng.randint(0, 59), rng.randint(0, 59),
                    tzinfo=TZ)


def fecha_entre(rng: random.Random, desde: date, hasta: date) -> date:
    return desde + timedelta(days=rng.randint(0, (hasta - desde).days))


class Datos:
    """Filas a cargar, por tabla, en el orden de las columnas declaradas."""

    COLUMNAS = {
        "departamento": ["id_departamento", "nombre", "provincia"],
        "localidad": ["id_localidad", "codigo_postal", "nombre", "provincia", "encargado_regional"],
        "sala_venta": ["id_sala", "calle", "numero", "dia_cierre", "id_localidad"],
        "empleado": ["cuit", "nombre", "fecha_ingreso", "salario", "id_sala"],
        "finca": ["id_finca", "nombre", "superficie_ha", "id_departamento"],
        "cepa": ["id_cepa", "nombre", "tipo"],
        "parcela": ["id_finca", "nro_parcela", "superficie_ha", "anio_plantacion", "id_cepa"],
        "bodega": ["cuit", "razon_social", "domicilio"],
        "lote_uva": ["nro_lote", "id_finca", "nro_parcela", "campania", "fecha_cosecha", "kilos", "cuit_bodega"],
        "analisis_calidad": ["id_analisis", "nro_lote", "fecha_analisis", "grado_brix", "ph", "acidez_total"],
        "vino": ["cod_vino", "nombre", "tipo", "anada", "volumen_ml", "graduacion", "precio", "cuit_bodega"],
        "composicion_vino": ["cod_vino", "id_cepa", "porcentaje"],
        "maridaje": ["id_maridaje", "nombre", "temperatura_servicio_c"],
        "vino_maridaje": ["cod_vino", "id_maridaje"],
        "auditoria_precio": ["id_auditoria", "cod_vino", "precio_anterior", "precio_nuevo", "fecha_hora", "usuario_bd"],
        "cliente": ["id_cliente", "nombre_razon_social", "tipo_documento", "nro_documento",
                    "direccion", "id_localidad", "fecha_alta", "tipo"],
        "socio_club": ["id_cliente"],
        "distribuidor": ["id_cliente", "zona_cobertura", "nro_habilitacion"],
        "exportador": ["id_cliente", "pais_destino_principal"],
        "permiso_exportacion": ["codigo_permiso", "id_exportador", "fecha_emision", "fecha_vencimiento"],
        "transportista": ["cod_transportista", "razon_social", "cuit", "email", "telefono", "domicilio"],
        "transportista_localidad": ["cod_transportista", "id_localidad"],
        "ingreso": ["cod_ingreso", "fecha", "estado", "cod_transportista", "cuit_bodega"],
        "renglon_ingreso": ["cod_ingreso", "cod_vino", "cantidad"],
        "transferencia": ["nro_transferencia", "id_sala", "fecha_confeccion", "estado"],
        "renglon_transferencia": ["nro_transferencia", "cod_vino", "cantidad"],
        "comprobante": ["nro_comprobante", "fecha", "id_cliente", "id_sala"],
        # Sólo lo que decide la historia; precio, descuento y subtotal los
        # calcula PostgreSQL al pasar a renglon_comprobante.
        "stg_renglon": ["nro_comprobante", "cod_vino", "cantidad"],
    }

    def __init__(self) -> None:
        self.filas = {tabla: [] for tabla in self.COLUMNAS}


# ---------------------------------------------------------------------------
# Generación de entidades
# ---------------------------------------------------------------------------

class Generador:
    def __init__(self, p: Parametros) -> None:
        self.p = p
        self.rng = random.Random(p.semilla)
        self.fake = Faker("es_AR")
        self.fake.seed_instance(p.semilla)
        self.d = Datos()

    # -- territorio, red comercial y personal ------------------------------
    def territorio(self) -> None:
        fake, d = self.fake, self.d
        for i, fila in enumerate(leer_csv("departamentos.csv"), start=1):
            d.filas["departamento"].append((i, fila["nombre"], fila["provincia"]))
        self.localidades = []
        for i, fila in enumerate(leer_csv("localidades.csv"), start=1):
            d.filas["localidad"].append((i, fila["codigo_postal"], fila["nombre"], fila["provincia"], fake.name()))
            self.localidades.append((i, fila["nombre"]))
        self.id_localidad = {nombre: i for i, nombre in self.localidades}

    def salas_y_empleados(self) -> None:
        rng, fake, d, ref = self.rng, self.fake, self.d, self.p.fecha_ref
        # Las ciudades grandes reciben más salas; la sala 1 queda en San Rafael (I3).
        principales = ["San Rafael", "Mendoza", "Godoy Cruz", "Maipú", "Luján de Cuyo",
                       "General Alvear", "Guaymallén"]
        ubicaciones = ["San Rafael"] + principales * 3 + [n for _, n in self.localidades]
        ubicaciones = ubicaciones[:40]
        direcciones = set()
        self.salas = []
        for id_sala, nombre_loc in enumerate(ubicaciones, start=1):
            id_loc = self.id_localidad.get(nombre_loc, 1)
            while True:
                calle, numero = fake.street_name(), str(rng.randint(10, 3500))
                if (id_loc, calle, numero) not in direcciones:
                    direcciones.add((id_loc, calle, numero))
                    break
            d.filas["sala_venta"].append((id_sala, calle, numero, DIAS_CIERRE[id_sala % len(DIAS_CIERRE)], id_loc))
            self.salas.append(id_sala)

        # D3: la sala 2 (San Rafael) tiene empleados con menos de dos años.
        cuits = cuits_unicos(rng, [20, 27], 10_000_000, 45_000_000, 5 * len(self.salas))
        empleados = 0
        for id_sala in self.salas:
            for _ in range(rng.randint(3, 5)):
                if id_sala == 2 and empleados % 2 == 0:
                    ingreso = fecha_entre(rng, ref - timedelta(days=700), ref - timedelta(days=30))
                else:
                    ingreso = fecha_entre(rng, restar_anios(ref, 15), ref - timedelta(days=30))
                salario = rng.randrange(800_000, 2_600_000, 1000)
                d.filas["empleado"].append((cuits[empleados], fake.name(), ingreso, salario, id_sala))
                empleados += 1

    # -- cepas ---------------------------------------------------------------
    def cepas_catalogo(self) -> None:
        self.cepas = []  # (id, nombre, tipo, en_uso)
        for i, fila in enumerate(leer_csv("cepas.csv"), start=1):
            self.d.filas["cepa"].append((i, fila["nombre"], fila["tipo"]))
            self.cepas.append((i, fila["nombre"], fila["tipo"], fila["uso"] == "cultivo"))

    # -- producción de uva -------------------------------------------------
    def produccion(self) -> None:
        rng, fake, d, ref = self.rng, self.fake, self.d, self.p.fecha_ref
        # Las cepas "sin_uso" no se plantan ni componen vinos (D2).
        cultivo = [c for c in self.cepas if c[3]]

        regiones = [1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 9]  # ids de departamentos vitivinícolas
        parcelas = []
        for id_finca in range(1, 31):
            superficie = rng.randrange(80, 400)
            d.filas["finca"].append((id_finca, f"Finca {fake.last_name()}", superficie, regiones[id_finca % len(regiones)]))
            disponible = superficie * 0.9
            nro = 0
            while nro < 24:
                sup = round(rng.uniform(1.5, 12.0), 2)
                if sup > disponible:
                    break
                disponible -= sup
                nro += 1
                cepa = rng.choice(cultivo)[0]
                d.filas["parcela"].append((id_finca, nro, sup, rng.randint(1975, ref.year - 4), cepa))
                parcelas.append((id_finca, nro, sup))

        # Cinco campañas completas: la última es el año actual si la cosecha
        # (febrero a abril) ya terminó.
        ultima = ref.year if ref >= date(ref.year, 5, 1) else ref.year - 1
        self.campanias = list(range(ultima - 4, ultima + 1))
        id_analisis = 0
        for campania in self.campanias:
            secuencia = 0
            for id_finca, nro, sup in parcelas:
                if rng.random() < 0.06:
                    continue  # algunas parcelas no se cosechan ese año
                secuencia += 1
                nro_lote = campania * 100_000 + secuencia
                cosecha = fecha_entre(rng, date(campania, 2, 1), date(campania, 4, 30))
                kilos = round(sup * rng.uniform(5500, 14500), 2)
                bodega = self.bodegas[rng.randrange(len(self.bodegas))]
                d.filas["lote_uva"].append((nro_lote, id_finca, nro, campania, cosecha, kilos, bodega))
                for _ in range(rng.randint(1, 3)):
                    id_analisis += 1
                    fecha = min(cosecha + timedelta(days=rng.randint(0, 20)), ref)
                    d.filas["analisis_calidad"].append((
                        id_analisis, nro_lote, fecha, round(rng.uniform(20.0, 27.0), 2),
                        round(rng.uniform(3.1, 3.9), 2), round(rng.uniform(4.5, 8.5), 2)))

    # -- bodegas, vinos, precios -------------------------------------------
    def bodegas_y_vinos(self) -> None:
        rng, fake, d, ref = self.rng, self.fake, self.d, self.p.fecha_ref
        self.bodegas = cuits_unicos(rng, [30, 33], 50_000_000, 59_999_999, 20)
        for b in self.bodegas:
            d.filas["bodega"].append((b, f"Bodega {fake.last_name()} {rng.choice(['S.A.', 'S.R.L.', 'Hnos.'])}",
                                      f"{fake.street_name()} {rng.randint(10, 5000)}, Mendoza"))

        tintas = [c for c in self.cepas if c[3] and c[2] == "tinta"]
        blancas = [c for c in self.cepas if c[3] and c[2] == "blanca"]
        presentaciones = [int(f["volumen_ml"]) for f in leer_csv("presentaciones.csv")]
        pesos_vol = {187: 7, 375: 10, 750: 70, 1500: 8, 3000: 5}
        maridajes = leer_csv("maridajes.csv")
        for i, fila in enumerate(maridajes, start=1):
            d.filas["maridaje"].append((i, fila["nombre"], int(fila["temperatura_servicio_c"])))
        maridajes_por_tipo = {"tinto": [1, 2, 3, 7], "blanco": [4, 5, 6, 7], "rosado": [4, 6, 7], "espumante": [6, 7, 8]}

        self.vinos = []  # dicts con lo que necesita la simulación
        claves = set()
        inicio = self.p.inicio_comercio

        def nuevo_vino(bodega: str, tipo: str, nombre: str, anada: int, volumen: int, cepas_pct: list) -> None:
            cod = len(self.vinos) + 1
            if tipo == "tinto":
                graduacion = rng.choice([13.0, 13.5, 14.0, 14.5, 15.0, 15.5])
            else:
                graduacion = rng.choice([11.5, 12.0, 12.5, 13.0])
            base = {"tinto": 3200, "blanco": 2600, "rosado": 2400, "espumante": 3600}[tipo]
            precio_inicial = round(base * volumen / 750 * rng.uniform(0.8, 2.5), -1)
            d.filas["composicion_vino"].extend((cod, id_cepa, pct) for id_cepa, pct in cepas_pct)
            for id_maridaje in rng.sample(maridajes_por_tipo[tipo], rng.randint(1, 3)):
                d.filas["vino_maridaje"].append((cod, id_maridaje))
            self.vinos.append({
                "cod": cod, "bodega": bodega, "tipo": tipo, "nombre": nombre, "anada": anada,
                "volumen": volumen, "graduacion": graduacion, "precio_inicial": precio_inicial,
                # Regla 2: se mueve desde el 1/1 del año siguiente a su añada.
                "desde": date(anada + 1, 1, 1),
            })

        def receta(tipo: str) -> tuple[str, list]:
            """Nombre de la cepa principal y composición que suma 100."""
            pool = tintas if tipo in ("tinto", "rosado") else blancas
            if tipo == "espumante":
                pool = [c for c in self.cepas if c[1] in ("Chardonnay", "Pinot Noir")]
            if tipo in ("rosado", "espumante") or rng.random() < 0.6:
                principal = rng.choice(pool)
                return principal[1], [(principal[0], 100)]
            elegidas = rng.sample(pool, rng.randint(2, min(3, len(pool))))
            restante, pcts = 100, []
            for _ in elegidas[:-1]:
                pct = rng.randrange(10, restante - 10 * (len(elegidas) - len(pcts) - 1), 5)
                pcts.append(pct)
                restante -= pct
            pcts.append(restante)
            orden = sorted(zip(pcts, elegidas), key=lambda x: (-x[0], x[1][0]))
            return orden[0][1][1], [(c[0], pct) for pct, c in orden]

        def agregar(bodega: str, tipo: str, anada: int | None = None, volumen: int | None = None,
                    nombre: str | None = None, receta_fija: list | None = None) -> None:
            while True:
                principal, cepas_pct = receta(tipo) if receta_fija is None else (None, receta_fija)
                n = nombre or f"{principal} {rng.choice(LINEAS_VINO)}"
                a = anada or rng.randint(ref.year - 10, ref.year - 1)
                v = volumen or rng.choices(presentaciones, weights=[pesos_vol[x] for x in presentaciones])[0]
                if (bodega, n, a, v) not in claves:
                    claves.add((bodega, n, a, v))
                    nuevo_vino(bodega, tipo, n, a, v, cepas_pct)
                    return

        # Bodega chica con tres vinos (S12: clientes que compraron todos sus vinos).
        self.bodega_chica = self.bodegas[-1]
        anada_vieja = inicio.year - 2
        id_malbec = next(c[0] for c in self.cepas if c[1] == "Malbec")
        id_chardonnay = next(c[0] for c in self.cepas if c[1] == "Chardonnay")
        agregar(self.bodega_chica, "tinto", anada_vieja, 750, "Malbec Clásico", [(id_malbec, 100)])
        agregar(self.bodega_chica, "blanco", anada_vieja, 750, "Chardonnay Joven", [(id_chardonnay, 100)])
        agregar(self.bodega_chica, "rosado", anada_vieja, 750, "Malbec Rosé", [(id_malbec, 100)])
        # I6: existe "Malbec Reserva" de 750 ml.
        agregar(self.bodegas[0], "tinto", anada_vieja, 750, "Malbec Reserva", [(id_malbec, 100)])

        tipos = ["tinto"] * 55 + ["blanco"] * 25 + ["rosado"] * 10 + ["espumante"] * 10
        while len(self.vinos) < 600:
            agregar(self.bodegas[len(self.vinos) % 19], rng.choice(tipos))

        # Ajustes anuales de precio (inflación): la auditoría queda encadenada
        # (precio anterior = precio nuevo del cambio previo) y el precio vigente
        # del vino es el último precio nuevo.
        id_auditoria = 0
        for v in self.vinos:
            precio = v["precio_inicial"]
            for anio in range(inicio.year, ref.year + 1):
                cambio = fecha_entre(rng, date(anio, 1, 1), date(anio, 12, 31))
                if not (inicio < cambio < ref):
                    continue
                nuevo = round(precio * rng.uniform(1.15, 1.60), -1)
                id_auditoria += 1
                d.filas["auditoria_precio"].append((id_auditoria, v["cod"], precio, nuevo,
                                                    momento(cambio, rng, 8, 9), USUARIO_CARGA))
                precio = nuevo
            d.filas["vino"].append((v["cod"], v["nombre"], v["tipo"], v["anada"], v["volumen"],
                                    v["graduacion"], precio, v["bodega"]))

    # -- clientes ----------------------------------------------------------
    def clientes(self) -> None:
        rng, fake, d, ref, p = self.rng, self.fake, self.d, self.p.fecha_ref, self.p
        total = round(20_000 * p.escala)
        dnis = rng.sample(range(10_000_000, 49_999_999), total)
        cuits = cuits_unicos(rng, [30, 33], 60_000_000, 79_999_999, total)
        self.clientes_info = []  # (id, tipo, alta, compra, toma_tintos, peso)
        departamentos = [f["nombre"] for f in leer_csv("departamentos.csv")]
        n_habilitacion = n_permiso = 0
        for id_cliente in range(1, total + 1):
            r = rng.random()
            tipo = "socio" if r < 0.70 else "distribuidor" if r < 0.90 else "exportador"
            alta = fecha_entre(rng, restar_anios(ref, 8), ref - timedelta(days=15))
            if tipo == "socio":
                nombre, doc_tipo, doc = fake.name(), "DNI", str(dnis[id_cliente - 1])
            else:
                nombre, doc_tipo, doc = fake.company(), "CUIT", cuits[id_cliente - 1]
            id_loc = self.localidades[rng.randrange(len(self.localidades))][0]
            d.filas["cliente"].append((id_cliente, nombre, doc_tipo, doc,
                                       f"{fake.street_name()} {rng.randint(1, 4000)}", id_loc, alta, tipo))
            if tipo == "socio":
                d.filas["socio_club"].append((id_cliente,))
            elif tipo == "distribuidor":
                n_habilitacion += 1
                d.filas["distribuidor"].append((id_cliente, f"Zona {rng.choice(departamentos)}",
                                                f"HAB-{n_habilitacion:06d}"))
            else:
                d.filas["exportador"].append((id_cliente, rng.choice(PAISES_EXPORTACION)))
                # Regla 7: permisos emitidos hasta la fecha de referencia;
                # unos vigentes y otros vencidos.
                for _ in range(rng.randint(1, 6)):
                    n_permiso += 1
                    emision = fecha_entre(rng, max(alta, restar_anios(ref, 6)), ref)
                    vencimiento = emision + timedelta(days=rng.randint(365, 3 * 365))
                    d.filas["permiso_exportacion"].append((f"PE-{n_permiso:07d}", id_cliente, emision, vencimiento))
            # D4/D6: algunos socios nunca compran. Un 15 % no compra tintos (S12).
            compra = not (tipo == "socio" and rng.random() < 0.08)
            peso = rng.lognormvariate(0, 1) * (2.5 if tipo != "socio" else 1)
            self.clientes_info.append((id_cliente, tipo, alta, compra, rng.random() >= 0.15, peso))

    # -- transportistas ----------------------------------------------------
    def transportistas(self) -> None:
        rng, fake, d = self.rng, self.fake, self.d
        self.transportistas_ids = list(range(1, 16))
        cuits = cuits_unicos(rng, [30, 33], 80_000_000, 89_999_999, 15)
        for cod in self.transportistas_ids:
            empresa = f"Transportes {fake.last_name()}"
            d.filas["transportista"].append((cod, empresa, cuits[cod - 1], f"contacto{cod}@transportes.example",
                                             f"260{rng.randint(4000000, 4999999)}",
                                             f"{fake.street_name()} {rng.randint(10, 3000)}"))
        alvear = self.id_localidad["General Alvear"]
        for cod in self.transportistas_ids:
            ids = rng.sample([i for i, _ in self.localidades], rng.randint(2, 5))
            if cod == self.transportistas_ids[-1]:
                ids = [i for i in ids if i != alvear]  # I1: el menos activo no cubre General Alvear
            for id_loc in sorted(ids):
                d.filas["transportista_localidad"].append((cod, id_loc))

    # ---------------------------------------------------------------------
    # Simulación cronológica de ingresos, transferencias y ventas
    # ---------------------------------------------------------------------
    def simular(self) -> None:
        rng, d, p = self.rng, self.d, self.p
        ref, inicio = p.fecha_ref, p.inicio_comercio
        vinos = self.vinos
        tipo_vino = {v["cod"]: v["tipo"] for v in vinos}
        desde = {v["cod"]: v["desde"] for v in vinos}
        por_bodega = {}
        for v in vinos:
            por_bodega.setdefault(v["bodega"], []).append(v["cod"])

        # Vinos de línea: disponibles desde el inicio y en todas las salas (S2).
        antiguos = [v["cod"] for v in vinos if v["desde"] <= inicio]
        chica = por_bodega[self.bodega_chica]
        linea = chica + [c for c in antiguos if c not in chica][:17]
        surtido = {}
        otros = [v["cod"] for v in vinos if v["cod"] not in linea]
        for s in self.salas:
            surtido[s] = linea + sorted(rng.sample(otros, 80))
        portadores = {v["cod"]: 0 for v in vinos}
        for s in self.salas:
            for c in surtido[s]:
                portadores[c] += 1
        popularidad = {v["cod"]: (6.0 if v["cod"] in linea else rng.uniform(0.3, 2.0)) for v in vinos}

        # Política de reposición, ajustada a los volúmenes recomendados:
        # cada sala repone un vino hasta `nivel` cuando baja de nivel/5, y el
        # depósito recibe lotes cuando baja de la mitad de lo que necesitan
        # las salas que lo venden.
        nivel = max(12, round(300 * p.escala))
        # Los lotes escalan con la demanda (múltiplos de 12): con ESCALA chica
        # sigue habiendo ingresos frecuentes para I1 y S7. Con ESCALA=1 son
        # 120, 240, 360, 480 y 600.
        lotes = [max(12, round(lote * p.escala / 12) * 12) for lote in (120, 240, 360, 480, 600)]
        stock_dep = {v["cod"]: 0 for v in vinos}
        stock_sala = {(s, c): 0 for s in self.salas for c in surtido[s]}

        # Clientes elegibles por fecha de alta (regla 1), con peso de actividad.
        compradores = sorted((c for c in self.clientes_info if c[3]), key=lambda c: (c[2], c[0]))
        altas = [c[2] for c in compradores]
        acumulado = list(accumulate(c[5] for c in compradores))
        peso_sala = [rng.uniform(0.5, 2.0) for _ in self.salas]
        acumulado_sala = list(accumulate(peso_sala))

        dias = (ref - inicio).days + 1
        # Algo más que 150.000: algunas ventas no se concretan por falta de stock.
        base_diaria = 156_000 * p.escala / dias
        ingresos, transferencias = [], []
        n_comprobante = n_ingreso = n_transferencia = 0
        cliente_s12 = [compradores[0][0], compradores[1][0]]
        pendientes_s12 = list(cliente_s12)

        def estado_documento(dia: date, ventana: int) -> str:
            if (ref - dia).days >= ventana:
                return "procesado"
            return rng.choices(["procesado", "terminado", "en_confeccion"], weights=[5, 3, 2])[0]

        for offset in range(dias):
            dia = inicio + timedelta(days=offset)

            # 1. Ingresos: cada bodega revisa su stock cada 10 días; el día 0
            #    todas cargan el depósito inicial. Regla 3: sólo vinos propios.
            for i, bodega in enumerate(self.bodegas):
                if offset != 0 and offset % 10 != i % 10:
                    continue
                renglones = []
                for c in por_bodega[bodega]:
                    if desde[c] > dia or portadores[c] == 0:
                        continue
                    necesidad = portadores[c] * nivel
                    if offset == 0:
                        renglones.append((c, necesidad))  # carga inicial del depósito
                    elif stock_dep[c] < necesidad // 2:
                        renglones.append((c, rng.choice(lotes)))
                if not renglones:
                    continue
                n_ingreso += 1
                estado = estado_documento(dia, 10)
                ingresos.append([n_ingreso, momento(dia, rng, 7, 11), estado, None, bodega, renglones])
                if estado == "procesado":
                    for c, cant in renglones:
                        stock_dep[c] += cant

            # 2. Transferencias: cada sala revisa cada 14 días; el día 0 todas.
            for i, sala in enumerate(self.salas):
                if offset != 0 and offset % 14 != i % 14:
                    continue
                renglones = []
                for c in surtido[sala]:
                    actual = stock_sala[(sala, c)]
                    # S4: en los últimos 15 días el primer vino de línea se
                    # repone siempre, para que varias salas lo pidan.
                    forzar = c == linea[0] and (ref - dia).days < 15 and actual < nivel
                    if desde[c] > dia or (actual >= nivel // 5 and not forzar):
                        continue
                    cant = min(nivel - actual, stock_dep[c])
                    if cant > 0:
                        renglones.append((c, cant))
                if not renglones:
                    continue
                n_transferencia += 1
                estado = estado_documento(dia, 7)
                transferencias.append([n_transferencia, sala, dia, estado, renglones])
                if estado == "procesado":
                    for c, cant in renglones:
                        stock_dep[c] -= cant
                        stock_sala[(sala, c)] += cant

            # 3. Ventas del día.
            factor = 0.6 if dia.weekday() == 6 else 1.15 if dia.weekday() == 5 else 1.0
            cantidad = max(1, round(base_diaria * factor * rng.uniform(0.85, 1.15)))
            hasta = bisect_right(altas, dia)
            if hasta == 0:
                continue
            for _ in range(cantidad):
                cliente = compradores[bisect_right(acumulado, rng.random() * acumulado[hasta - 1], hi=hasta - 1)]
                sala = self.salas[bisect_right(acumulado_sala, rng.random() * acumulado_sala[-1])]
                elegidos = self._elegir_vinos(sala, cliente, surtido, stock_sala, tipo_vino, popularidad)
                if not elegidos:
                    continue
                n_comprobante += 1
                d.filas["comprobante"].append((n_comprobante, momento(dia, rng, 10, 20), cliente[0], sala))
                for c in elegidos:
                    cant = min(self._cantidad(cliente[1]), stock_sala[(sala, c)])
                    stock_sala[(sala, c)] -= cant
                    d.filas["stg_renglon"].append((n_comprobante, c, cant))

            # S12: en la mitad del período, dos clientes compran los tres
            # vinos de la bodega chica (se reintenta hasta que haya stock).
            if pendientes_s12 and offset >= dias // 2:
                for sala in self.salas:
                    if not pendientes_s12:
                        break
                    if all(stock_sala.get((sala, c), 0) >= 1 for c in chica):
                        id_cliente = pendientes_s12.pop(0)
                        n_comprobante += 1
                        d.filas["comprobante"].append((n_comprobante, momento(dia, rng, 10, 20), id_cliente, sala))
                        for c in chica:
                            stock_sala[(sala, c)] -= 1
                            d.filas["stg_renglon"].append((n_comprobante, c, 1))

        if pendientes_s12:
            raise RuntimeError("No se pudo generar la venta de S12 (bodega chica).")
        self._asignar_transportistas(ingresos)

        for cod, fecha, estado, transp, bodega, renglones in ingresos:
            d.filas["ingreso"].append((cod, fecha, estado, transp, bodega))
            d.filas["renglon_ingreso"].extend((cod, c, cant) for c, cant in renglones)
        for nro, sala, fecha, estado, renglones in transferencias:
            d.filas["transferencia"].append((nro, sala, fecha, estado))
            d.filas["renglon_transferencia"].extend((nro, c, cant) for c, cant in renglones)

    def _elegir_vinos(self, sala, cliente, surtido, stock_sala, tipo_vino, popularidad):
        rng = self.rng
        candidatos = [c for c in surtido[sala]
                      if stock_sala[(sala, c)] > 0 and (cliente[4] or tipo_vino[c] != "tinto")]
        if not candidatos:
            return []
        k = min(rng.choices([1, 2, 3, 4, 5, 6], weights=[8, 17, 24, 22, 17, 12])[0], len(candidatos))
        elegidos = []
        pesos = [popularidad[c] for c in candidatos]
        while len(elegidos) < k:
            c = rng.choices(candidatos, weights=pesos)[0]
            if c not in elegidos:
                elegidos.append(c)
        return elegidos

    def _cantidad(self, tipo_cliente: str) -> int:
        rng = self.rng
        if tipo_cliente == "socio":
            return rng.choices([1, 2, 3], weights=[50, 35, 15])[0]
        if tipo_cliente == "distribuidor":
            return rng.randint(3, 12)
        return rng.randint(6, 18)

    def _asignar_transportistas(self, ingresos: list) -> None:
        """Asigna transportistas garantizando I1 y S7.

        - Último mes: el transportista 1 es claramente el más activo (S7).
        - Último trimestre: todos tienen ingresos y el 15 tiene exactamente uno,
          el mínimo único (I1).
        """
        rng, ref = self.rng, self.p.fecha_ref
        resto = self.transportistas_ids[:-1]
        menor = self.transportistas_ids[-1]
        trimestre = [ing for ing in ingresos if (ref - ing[1].date()).days < 90]
        if len(trimestre) < 2 * len(self.transportistas_ids):
            raise RuntimeError("Muy pocos ingresos en el último trimestre para garantizar I1 y S7; aumente ESCALA.")
        for ing in ingresos:
            dias = (ref - ing[1].date()).days
            pesos = [8 if (t == 1 and dias < 30) else 1 for t in resto]
            ing[3] = rng.choices(resto, weights=pesos)[0]
        # Dos ingresos del trimestre para cada transportista del resto y uno
        # para el menor, elegidos entre los más antiguos del trimestre.
        for i, t in enumerate(resto):
            trimestre[2 * i][3] = t
            trimestre[2 * i + 1][3] = t
        trimestre[2 * len(resto)][3] = menor
        # Fuera del trimestre el menor también trabaja (historia normal).
        for ing in ingresos[: len(ingresos) // 2: 15]:
            ing[3] = menor

    def generar(self) -> Datos:
        # El orden es parte de la reproducibilidad: cada paso consume la misma
        # secuencia de números aleatorios en cada ejecución.
        self.territorio()
        self.salas_y_empleados()
        self.cepas_catalogo()
        self.bodegas_y_vinos()
        self.produccion()  # los lotes necesitan las bodegas
        self.clientes()
        self.transportistas()
        self.simular()
        return self.d


# ---------------------------------------------------------------------------
# Carga en PostgreSQL
# ---------------------------------------------------------------------------

# Precio vigente de cada vino en cada momento, deducido de la auditoría: antes
# del primer cambio rige el precio anterior de ese cambio; después de cada
# cambio, su precio nuevo; un vino sin cambios tuvo siempre su precio actual.
SQL_INTERVALOS_PRECIO = """
WITH cambios AS (
  SELECT cod_vino, fecha_hora, precio_anterior, precio_nuevo,
         LEAD(fecha_hora) OVER w AS siguiente,
         ROW_NUMBER() OVER w AS n
  FROM auditoria_precio
  WINDOW w AS (PARTITION BY cod_vino ORDER BY fecha_hora)
)
SELECT cod_vino, '-infinity'::timestamptz AS desde, fecha_hora AS hasta, precio_anterior AS precio
FROM cambios WHERE n = 1
UNION ALL
SELECT cod_vino, fecha_hora, COALESCE(siguiente, 'infinity'), precio_nuevo
FROM cambios
UNION ALL
SELECT v.cod_vino, '-infinity', 'infinity', v.precio
FROM vino AS v
WHERE NOT EXISTS (SELECT 1 FROM auditoria_precio AS a WHERE a.cod_vino = v.cod_vino)
"""

SQL_RENGLONES = f"""
INSERT INTO renglon_comprobante (
  nro_comprobante, cod_vino, cantidad, precio_unitario, descuento_porcentaje, subtotal
)
SELECT s.nro_comprobante, s.cod_vino, s.cantidad, p.precio, d.descuento,
       ROUND(s.cantidad * p.precio * (1 - d.descuento / 100), 2)
FROM stg_renglon AS s
JOIN comprobante AS c ON c.nro_comprobante = s.nro_comprobante
JOIN (SELECT id_cliente, fn_descuento_cliente(id_cliente) AS descuento FROM cliente) AS d
  ON d.id_cliente = c.id_cliente
JOIN ({SQL_INTERVALOS_PRECIO}) AS p
  ON p.cod_vino = s.cod_vino AND c.fecha >= p.desde AND c.fecha < p.hasta
"""

# Misma aritmética que fn_recalcular_comprobante, por conjuntos. La marca de
# recálculo es el camino que trg_comprobante_importes (activo) acepta.
SQL_IMPORTES = """
UPDATE comprobante AS c
SET subtotal = r.bruto, descuento = r.bruto - r.neto, total = r.neto
FROM (
  SELECT nro_comprobante, SUM(cantidad * precio_unitario) AS bruto, SUM(subtotal) AS neto
  FROM renglon_comprobante
  GROUP BY nro_comprobante
) AS r
WHERE r.nro_comprobante = c.nro_comprobante
"""

# Stocks finales a partir de los movimientos procesados.
SQL_STOCK_DEPOSITO = """
INSERT INTO stock_deposito (cod_vino, cantidad)
SELECT v.cod_vino, COALESCE(e.entradas, 0) - COALESCE(s.salidas, 0)
FROM vino AS v
LEFT JOIN (SELECT ri.cod_vino, SUM(ri.cantidad) AS entradas
           FROM renglon_ingreso AS ri JOIN ingreso AS i ON i.cod_ingreso = ri.cod_ingreso
           WHERE i.estado = 'procesado' GROUP BY ri.cod_vino) AS e ON e.cod_vino = v.cod_vino
LEFT JOIN (SELECT rt.cod_vino, SUM(rt.cantidad) AS salidas
           FROM renglon_transferencia AS rt JOIN transferencia AS t ON t.nro_transferencia = rt.nro_transferencia
           WHERE t.estado = 'procesado' GROUP BY rt.cod_vino) AS s ON s.cod_vino = v.cod_vino
"""

SQL_STOCK_SALA = """
INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
SELECT e.id_sala, e.cod_vino, e.entradas - COALESCE(s.salidas, 0)
FROM (SELECT t.id_sala, rt.cod_vino, SUM(rt.cantidad) AS entradas
      FROM transferencia AS t JOIN renglon_transferencia AS rt ON rt.nro_transferencia = t.nro_transferencia
      WHERE t.estado = 'procesado' GROUP BY t.id_sala, rt.cod_vino) AS e
LEFT JOIN (SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS salidas
           FROM comprobante AS c JOIN renglon_comprobante AS r ON r.nro_comprobante = c.nro_comprobante
           GROUP BY c.id_sala, r.cod_vino) AS s ON s.id_sala = e.id_sala AND s.cod_vino = e.cod_vino
"""

# Columnas IDENTITY cuyas secuencias se ajustan después de la carga.
IDENTIDADES = [
    ("departamento", "id_departamento"), ("localidad", "id_localidad"), ("sala_venta", "id_sala"),
    ("finca", "id_finca"), ("cepa", "id_cepa"), ("analisis_calidad", "id_analisis"),
    ("vino", "cod_vino"), ("maridaje", "id_maridaje"), ("auditoria_precio", "id_auditoria"),
    ("cliente", "id_cliente"), ("transportista", "cod_transportista"), ("ingreso", "cod_ingreso"),
    ("transferencia", "nro_transferencia"), ("comprobante", "nro_comprobante"),
]


def conectar() -> psycopg.Connection:
    return psycopg.connect(
        host=os.environ.get("DB_HOST", "db"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["DB_OWNER_USER"],
        password=os.environ["DB_OWNER_PASSWORD"],
        options="-c search_path=bodegas,pg_catalog",
    )


class Cronometro:
    def __init__(self) -> None:
        self.tiempos = []

    def medir(self, etiqueta: str, funcion):
        inicio = time.perf_counter()
        resultado = funcion()
        segundos = time.perf_counter() - inicio
        self.tiempos.append((etiqueta, segundos))
        print(f"  {etiqueta:<48} {segundos:8.2f} s", flush=True)
        return resultado


def copiar(cur: psycopg.Cursor, tabla: str, columnas: list[str], filas: list) -> None:
    with cur.copy(f"COPY {tabla} ({', '.join(columnas)}) FROM STDIN") as copia:
        for fila in filas:
            copia.write_row(fila)


def exigir_base_vacia(conn: psycopg.Connection) -> None:
    con_datos = [t for t in TABLAS_NEGOCIO
                 if conn.execute(f"SELECT EXISTS (SELECT 1 FROM {t})").fetchone()[0]]
    if con_datos:
        sys.exit("La base ya tiene datos de negocio en: " + ", ".join(con_datos) + ".\n"
                 "La carga no duplica ni mezcla datos. Para recargar, recrear el volumen "
                 "(docker compose down -v) y volver a ejecutar.")


def triggers_deshabilitados(conn: psycopg.Connection) -> list[str]:
    return [f"{t}.{n}" for t, n in conn.execute("""
        SELECT c.relname, t.tgname
        FROM pg_trigger AS t JOIN pg_class AS c ON c.oid = t.tgrelid
        WHERE c.relnamespace = 'bodegas'::regnamespace AND t.tgenabled = 'D'
        ORDER BY 1, 2""").fetchall()]


def cargar(p: Parametros) -> None:
    print(f"Parámetros: SEMILLA={p.semilla} FECHA_REFERENCIA={p.fecha_ref} ESCALA={p.escala}")
    reloj = Cronometro()
    with conectar() as conn:
        exigir_base_vacia(conn)

    print("Generación en memoria:")
    datos = reloj.medir("simulación de la historia", lambda: Generador(p).generar())

    print("Carga (una sola transacción):")
    conn = conectar()
    try:
        with conn.cursor() as cur:
            for tabla, trigger in TRIGGERS_HISTORICOS:
                cur.execute(f"ALTER TABLE {tabla} DISABLE TRIGGER {trigger}")
            cur.execute("CREATE TEMP TABLE stg_renglon (nro_comprobante BIGINT, cod_vino BIGINT, cantidad INTEGER) ON COMMIT DROP")

            for tabla in TABLAS_NEGOCIO:
                if tabla == "renglon_comprobante":
                    reloj.medir("COPY stg_renglon (staging de renglones)",
                                lambda: copiar(cur, "stg_renglon", Datos.COLUMNAS["stg_renglon"], datos.filas["stg_renglon"]))
                    reloj.medir("renglon_comprobante: precio, descuento y subtotal en SQL",
                                lambda: cur.execute(SQL_RENGLONES))
                    if cur.rowcount != len(datos.filas["stg_renglon"]):
                        raise RuntimeError(f"Se insertaron {cur.rowcount} renglones de {len(datos.filas['stg_renglon'])}: "
                                           "algún renglón no encontró un precio vigente.")
                    cur.execute("SELECT set_config('bodegas.recalculo_importes', 'on', true)")
                    reloj.medir("comprobante: importes agregados en SQL", lambda: cur.execute(SQL_IMPORTES))
                    cur.execute("SELECT set_config('bodegas.recalculo_importes', 'off', true)")
                elif tabla == "stock_deposito":
                    reloj.medir("stock_deposito desde movimientos", lambda: cur.execute(SQL_STOCK_DEPOSITO))
                elif tabla == "stock_sala":
                    reloj.medir("stock_sala desde movimientos", lambda: cur.execute(SQL_STOCK_SALA))
                else:
                    reloj.medir(f"COPY {tabla} ({len(datos.filas[tabla])} filas)",
                                lambda t=tabla: copiar(cur, t, Datos.COLUMNAS[t], datos.filas[t]))

            # Las FK son triggers internos y siguen activas: un huérfano falla.
            cur.execute("SAVEPOINT prueba_fk")
            try:
                cur.execute("INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad) VALUES (-1, 1, 1)")
                raise RuntimeError("Un renglón huérfano fue aceptado: las FK no están activas.")
            except psycopg.errors.ForeignKeyViolation:
                cur.execute("ROLLBACK TO SAVEPOINT prueba_fk")
                print("  FK activas durante la carga: un renglón huérfano fue rechazado (23503).")

            for tabla, columna in IDENTIDADES:
                cur.execute(f"SELECT setval(pg_get_serial_sequence('bodegas.{tabla}', '{columna}'), "
                            f"(SELECT max({columna}) FROM {tabla}))")
            for tabla, trigger in TRIGGERS_HISTORICOS:
                cur.execute(f"ALTER TABLE {tabla} ENABLE TRIGGER {trigger}")

        # Los constraint triggers diferidos (composición, totalidad de
        # clientes, comprobantes con renglones) validan todo al confirmar.
        reloj.medir("COMMIT (incluye los constraint triggers diferidos)", conn.commit)
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()
        with conectar() as verificacion:
            pendientes = triggers_deshabilitados(verificacion)
        if pendientes:
            print("ATENCIÓN: quedaron triggers deshabilitados: " + ", ".join(pendientes), file=sys.stderr)
            sys.exit(1)
        print("Triggers: ninguno quedó deshabilitado.")

    total = sum(s for _, s in reloj.tiempos)
    print(f"Tiempo total: {total:.1f} s")
    with conectar() as conn:
        print("Filas por tabla:")
        for tabla in TABLAS_NEGOCIO:
            print(f"  {tabla:<24} {conn.execute(f'SELECT count(*) FROM {tabla}').fetchone()[0]:>10}")


def medir(p: Parametros, muestra_fila: int) -> None:
    """Paso 6: misma tabla cargada fila por fila, por lotes y con COPY.

    Mide la transferencia desde Python de los renglones de venta (lo que el
    script envía a la base) a una tabla temporal con su clave primaria. La
    transformación posterior en SQL es igual para todos los métodos y se informa
    aparte en la carga. Fila por fila se mide sobre una muestra y se extrapola:
    con un COMMIT por fila (lo ingenuo) y con un solo COMMIT al final.
    """
    print(f"Parámetros: SEMILLA={p.semilla} FECHA_REFERENCIA={p.fecha_ref} ESCALA={p.escala}")
    filas = Generador(p).generar().filas["stg_renglon"]
    total = len(filas)
    print(f"Renglones generados: {total}")
    sql_insert = "INSERT INTO medicion (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, %s)"
    resultados = []
    with conectar() as conn:
        conn.execute("CREATE TEMP TABLE medicion (nro_comprobante BIGINT, cod_vino BIGINT, cantidad INTEGER, "
                     "PRIMARY KEY (nro_comprobante, cod_vino))")

        def tanda(nombre: str, n: int, funcion) -> None:
            conn.execute("TRUNCATE medicion")
            conn.commit()
            inicio = time.perf_counter()
            with conn.cursor() as cur:
                funcion(cur, filas[:n])
            conn.commit()
            segundos = time.perf_counter() - inicio
            resultados.append((nombre, n, segundos, n / segundos))

        def una_transaccion_por_fila(cur, f):
            for fila in f:
                cur.execute(sql_insert, fila)
                conn.commit()

        tanda("fila por fila, COMMIT por fila", min(muestra_fila // 4, total), una_transaccion_por_fila)
        tanda("fila por fila (execute)", min(muestra_fila, total),
              lambda cur, f: [cur.execute(sql_insert, fila) for fila in f])
        tanda("por lotes (executemany)", total, lambda cur, f: cur.executemany(sql_insert, f))
        tanda("COPY", total, lambda cur, f: copiar(cur, "medicion", Datos.COLUMNAS["stg_renglon"], f))

    print(f"{'método':<26}{'filas':>10}{'segundos':>11}{'filas/s':>11}{'estimado total':>16}")
    for nombre, n, segundos, tasa in resultados:
        estimado = total / tasa
        nota = "" if n == total else " (extrapolado)"
        print(f"{nombre:<26}{n:>10}{segundos:>11.2f}{tasa:>11.0f}{estimado:>13.1f} s{nota}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Carga masiva reproducible de Bodegas del Atuel.")
    parser.add_argument("accion", choices=["cargar", "medir"])
    parser.add_argument("--muestra-fila", type=int, default=20_000,
                        help="filas para la medición fila por fila (se extrapola)")
    args = parser.parse_args()
    p = leer_parametros()
    if args.accion == "cargar":
        cargar(p)
    else:
        medir(p, args.muestra_fila)


if __name__ == "__main__":
    main()
