"""Comprobantes: venta completa y consulta (issue #28).

La API nunca inserta comprobantes ni renglones: toda venta pasa por
fn_registrar_venta, que valida, calcula los importes y descuenta el stock en una
sola operación. Los errores de PostgreSQL (RN-09 sin stock, RN-08 vino repetido,
RN-15 cantidad no positiva, cliente o sala inexistente) los traduce
app/errores.py; este módulo no los captura.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Response, status
from psycopg import Connection

from app.database import conexion
from app.datos import comprobantes as datos
from app.esquemas import MAX_BIGINT, ComprobanteEntrada, ComprobanteSalida, ErrorRespuesta


router = APIRouter(prefix="/comprobantes", tags=["comprobantes"])


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Registrar una venta completa",
    responses={
        409: {
            "model": ErrorRespuesta,
            "description": "Regla de negocio (P0001): sin stock (RN-09), sin renglones o "
                           "vino repetido (RN-08), cantidad no positiva (RN-15).",
        },
        422: {
            "model": ErrorRespuesta,
            "description": "Vino, cliente o sala inexistente, o cuerpo inválido.",
        },
    },
)
def registrar_comprobante(
    entrada: ComprobanteEntrada,
    response: Response,
    conn: Connection = Depends(conexion),
) -> ComprobanteSalida:
    """Registra la venta y devuelve el comprobante tal como quedó en la base."""

    vinos = [r.cod_vino for r in entrada.renglones]
    cantidades = [r.cantidad for r in entrada.renglones]

    # La venta y su lectura en la misma transacción: si algo falla, no queda
    # ni la cabecera ni el descuento de stock de los renglones anteriores.
    with conn.transaction():
        faltantes = datos.vinos_inexistentes(conn, vinos)
        if faltantes:
            raise HTTPException(
                422,
                f"No existen los vinos: {', '.join(map(str, faltantes))}.",
            )
        nro = datos.registrar_venta(conn, entrada.id_cliente, entrada.id_sala, vinos, cantidades)
        comprobante = datos.obtener(conn, nro)

    response.headers["Location"] = f"/comprobantes/{nro}"
    return ComprobanteSalida(**comprobante)


@router.get(
    "/{nro}",
    summary="Consultar un comprobante",
    responses={404: {"model": ErrorRespuesta, "description": "El comprobante no existe."}},
)
def obtener_comprobante(
    nro: int = Path(ge=1, le=MAX_BIGINT, description="Número de comprobante."),
    conn: Connection = Depends(conexion),
) -> ComprobanteSalida:
    """Cabecera con los importes guardados y sus renglones."""

    comprobante = datos.obtener(conn, nro)
    if comprobante is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"El comprobante {nro} no existe.")
    return ComprobanteSalida(**comprobante)
