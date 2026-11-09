"""Reportes de sólo lectura: S1, S8, S6 y S7 de la Etapa 5 (issue #31) y la
trazabilidad de un vino (issue #32).

Los parámetros se validan con el dominio de cada columna (422 "validacion").
Lo que depende de los datos (una sala inexistente, un período invertido una
vez resueltos los valores por omisión) lo decide el endpoint. El SQL está en
app/datos/reportes.py.
"""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from psycopg import Connection

from app.database import conexion
from app.datos import reportes as datos
from app.esquemas import (
    MAX_BIGINT, MAX_INTEGER, ErrorRespuesta, ReporteTopVinos, ReporteTransportistaActivo,
    ReporteTrazabilidad, ReporteVentasPorSala, ReporteVinosSinStock,
)


router = APIRouter(prefix="/reportes", tags=["reportes"])

INVALIDO: dict[int | str, dict] = {422: {"model": ErrorRespuesta, "description": "Parámetro inválido."}}


@router.get("/top-vinos", summary="Vinos con más botellas vendidas (S1)", responses=INVALIDO)
def top_vinos(
    limite: int = Query(10, ge=1, le=100, description="Cantidad de vinos (1 a 100)."),
    conn: Connection = Depends(conexion),
) -> ReporteTopVinos:
    """Ranking de toda la historia de ventas. A igual cantidad, por código de vino."""

    return ReporteTopVinos(limite=limite, items=datos.top_vinos(conn, limite))


@router.get(
    "/ventas-por-sala",
    summary="Ventas por sala en un período (S8)",
    responses={422: {"model": ErrorRespuesta,
                     "description": "Fecha inválida, o `desde` posterior a `hasta`."}},
)
def ventas_por_sala(
    desde: date | None = Query(None, description="Primer día. Por omisión, hace tres meses."),
    hasta: date | None = Query(None, description="Último día, incluido. Por omisión, hoy."),
    conn: Connection = Depends(conexion),
) -> ReporteVentasPorSala:
    """Comprobantes, importe bruto, descuento y total de cada sala con ventas en el período.

    Sin parámetros es el último trimestre, como S8. Los días son los de la
    base, que corre en UTC.
    """

    # Se valida después de resolver las omisiones: hasta=2020-01-01 solo
    # también deja el período invertido.
    inicio, fin = datos.periodo_ventas(conn, desde, hasta)
    if inicio > fin:
        raise HTTPException(422, f"El período es inválido: desde ({inicio}) es posterior a hasta ({fin}).")
    return ReporteVentasPorSala(desde=inicio, hasta=fin, items=datos.ventas_por_sala(conn, inicio, fin))


@router.get(
    "/vinos-sin-stock",
    summary="Vinos sin stock en una sala y con stock en el depósito (S6)",
    responses={404: {"model": ErrorRespuesta, "description": "La sala no existe."}, **INVALIDO},
)
def vinos_sin_stock(
    id_sala: int = Query(ge=1, le=MAX_INTEGER, description="Sala (obligatoria)."),
    conn: Connection = Depends(conexion),
) -> ReporteVinosSinStock:
    """Los vinos que la sala no tiene y el depósito sí: los que puede pedir en una transferencia."""

    if not datos.sala_existe(conn, id_sala):
        raise HTTPException(404, f"La sala {id_sala} no existe.")
    return ReporteVinosSinStock(id_sala=id_sala, items=datos.vinos_sin_stock(conn, id_sala))


@router.get(
    "/transportista-activo",
    summary="Transportista con más ingresos en los últimos días (S7)",
    responses=INVALIDO,
)
def transportista_activo(
    dias: int = Query(30, ge=1, le=3650, description="Días hacia atrás desde hoy (1 a 3650)."),
    conn: Connection = Depends(conexion),
) -> ReporteTransportistaActivo:
    """El transportista con más ingresos; si varios empatan, todos. Vacío si no hubo ingresos."""

    return ReporteTransportistaActivo(dias=dias, items=datos.transportista_activo(conn, dias))


@router.get(
    "/trazabilidad/{cod_vino}",
    summary="Lotes de uva que pudieron originar un vino (supuesto)",
    responses={404: {"model": ErrorRespuesta, "description": "El vino no existe."}, **INVALIDO},
)
def trazabilidad(
    cod_vino: int = Path(ge=1, le=MAX_BIGINT, description="Código del vino."),
    conn: Connection = Depends(conexion),
) -> ReporteTrazabilidad:
    """El vino, su corte y los lotes de uva compatibles, con finca, parcela y análisis.

    **Es una aproximación.** El modelo no registra con qué lotes se elaboró
    cada vino. Se muestran los lotes que la bodega del vino recibió en la
    campaña de su añada, de parcelas de las cepas de su corte (supuesto de
    `docs/requisitos.md`, a la espera de la respuesta de la cátedra). Sin
    lotes compatibles, `lotes` es `[]`.
    """

    reporte = datos.trazabilidad(conn, cod_vino)
    if reporte is None:
        raise HTTPException(404, f"El vino {cod_vino} no existe.")
    return ReporteTrazabilidad(**reporte)
