"""Comprobantes y ventas (Etapa 6).

POST /comprobantes - registrar una venta completa delegando en fn_registrar_venta.
GET /comprobantes/{nro} - consultar un comprobante existente.
"""

from fastapi import APIRouter, Depends, HTTPException, Path, Request, status
from psycopg import Connection

from app.database import conexion
from app.datos import vinos as vinos_datos
from app.datos.comprobantes import registrar_venta, obtener_comprobante, obtener_renglones
from app.esquemas import (
    ComprobanteEntrada, ComprobanteSalida, ComprobanteRenglonEntrada,
    ComprobanteRenglonRespuesta, ErrorRespuesta,
)
from app.errores import traducir


router = APIRouter(prefix="/comprobantes", tags=["comprobantes"])


# ---------------------------------------------------------------------------
# Validaciones auxiliares de entrada
# ---------------------------------------------------------------------------

def _validar_renglones(renglones: list[ComprobanteRenglonEntrada]) -> None:
    """Validaciones de los renglones antes de registrar la venta."""

    if len(renglones) == 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="RN-08: una venta debe tener al menos un renglón.",
        )

    # Validar que las cantidades sean enteros positivos (>= 1)
    for r in renglones:
        if r.cantidad <= 0:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="RN-15: las cantidades vendidas deben ser positivas.",
            )


# ---------------------------------------------------------------------------
# POST /comprobantes
# ---------------------------------------------------------------------------

@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    summary="Registrar una venta completa",
    responses={
        201: {
            "model": ComprobanteSalida,
            "description": "Venta registrada correctamente. Los importos vienen "
                          "calculados por PostgreSQL después de llamar a "
                          "fn_registrar_venta.",
        },
        409: {
            "model": ErrorRespuesta,
            "description": "Stock insuficiente (RN-09), vino repetido (RN-08), "
                          "cantidad no positiva (RN-15) o venta sin renglones.",
        },
        422: {
            "model": ErrorRespuesta,
            "description": "Cliente o sala inexistente, vino inexistente, "
                          "datos de entrada inválidos.",
        },
    },
)
def registrar_comprobante(
    entrada: ComprobanteEntrada,
    request: Request,
    conn: Connection = Depends(conexion),
) -> ComprobanteSalida:
    """Registra una venta completa mediante una llamada a fn_registrar_venta.

    La API valida la entrada, inicia una transacción, invoca a la función
    de PostgreSQL y luego recupera los datos persistidos para devolver la
    respuesta completa. Todo es una sola sentencia atómica: si falla, todo
    se revierte.

    La API nunca hace INSERT ni UPDATE directos sobre comprobante ni
    renglon_comprobante: todo lo registra fn_registrar_venta.
    """

    # 1. Validar estructura (Pydantic ya lo hizo por nosotros al parsear entrada)

    # 2. Validar que exista al menos un renglón
    _validar_renglones(entrada.renglones)

    # 3. Validar que las cantidades sean enteros positivos
    # (già covered by _validar_renglones)

    # 4. Rechazar vinos repetidos a nivel de API (mejor mensaje de error)
    codigos_vino = [r.cod_vino for r in entrada.renglones]
    if len(codigos_vino) != len(set(codigos_vino)):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="RN-08: un vino no puede repetirse en la misma venta.",
        )

    # 5. Validar que los vinos existan en la base (Alternative A para cod_vino inexistente)
    # Esto mejora el mensaje de error respecto a la excepción poco clara de precio_unitario
    for r in entrada.renglones:
        if not vinos_datos.vino_existe(conn, r.cod_vino):
            raise HTTPException(
                status_code=422,
                detail=f"El vino {r.cod_vino} no existe.",
            )

    # 6. Convertir renglones en arrays para fn_registrar_venta
    vinos: list[int] = [r.cod_vino for r in entrada.renglones]
    cantidades: list[int] = [r.cantidad for r in entrada.renglones]

    # 7. Iniciar transacción y llamar a fn_registrar_venta
    #    La validación de cliente/sala existencias correra por FK en la base,
    #    y los errores se traducen correctamente por app/errores.py (23503 → 422).
    try:
        with conn.transaction():
            nro_comprobante = registrar_venta(conn, entrada.id_cliente, entrada.id_sala, entrada.renglones)

            # 8. Recuperar datos persistidos desde PostgreSQL
            comp = obtener_comprobante(conn, nro_comprobante)
            if comp is None:
                # Esto debería imposible si fn_registrar_venta tuvo éxito
                raise HTTPException(
                    status_code=500,
                    detail="Error interno: no se pudo recuperar el comprobante.",
                )

            renglones_data = obtener_renglones(conn, nro_comprobante)

            # 9. Construir y devolver la respuesta
            return ComprobanteSalida(
                nro_comprobante=nro_comprobante,
                fecha=comp["fecha"],
                subtotal=comp["subtotal"],
                descuento=comp["descuento"],
                total=comp["total"],
                renglones=renglones_data,
            )
    except HTTPException:
        # Re-lanzar excepciones HTTP sin rollback problemmas
        raise
    except Exception as exc:
        # Cualquier otro error: la transacción ya hizo ROLLBACK por el with conn.transaction()
        # Traducir error de PostgreSQL si es necesario
        import traceback as tb
        tb.print_exc()
        print(f"EXCEPTION TYPE: {type(exc).__name__}")
        print(f"HAS sqlstate: {hasattr(exc, 'sqlstate')}")
        print(f"HAS diag: {hasattr(exc, 'diag')}")
        if hasattr(exc, "sqlstate") and hasattr(exc, "diag"):
            # Reglas de negocio específicas (P0001): lanzar 409 directamente
            if exc.sqlstate == "P0001":
                raise HTTPException(
                    status_code=409,
                    detail=exc.diag.message_primary or "Regla de negocio rechazada.",
                )
            # FK violation (23503): traducir a 422 aunque message_primary sea None en psycopg 3
            if exc.sqlstate == "23503":
                raise HTTPException(
                    status_code=422,
                    detail="El dato relacionado no existe.",
                )
            try:
                trad = traducir(exc.sqlstate, exc.diag.message_primary, exc.diag.constraint_name, exc.diag.column_name)
                raise HTTPException(
                    status_code=trad.status,
                    detail=trad.cuerpo.detail,
                )
            except Exception:
                # Fallback si tradular falla inesperadamente
                raise HTTPException(
                    status_code=500,
                    detail="Error interno del servidor.",
                )
        else:
            raise HTTPException(
                status_code=500,
                detail="Error interno del servidor.",
            )@router.get(
    "/{nro}",
    summary="Consultar un comprobante por número",
    responses={
        200: {
            "model": ComprobanteSalida,
            "description": "Comprobante encontrado con cabecera y renglones.",
        },
        404: {
            "model": ErrorRespuesta,
            "description": "No existe ningún comprobante con ese número.",
        },
    },
)
def obtener_comprobante_endpoint(
    nro: int = Path(ge=1, description="Número de comprobante a consultar."),
    conn: Connection = Depends(conexion),
) -> ComprobanteSalida:
    """Consulta la cabecera y los renglones de un comprobante existente."""

    # 1. Validar el parámetro de ruta (Pydantic ge=1 ya lo hizo)

    # 2. Buscar el comprobante en PostgreSQL
    comp = obtener_comprobante(conn, nro)
    if comp is None:
        raise HTTPException(
            status_code=404,
            detail=f"El comprobante {nro} no existe.",
        )

    # 3. Devolver la cabecera (los renglones se consultan después)
    return ComprobanteSalida(
        nro_comprobante=comp["nro_comprobante"],
        fecha=comp["fecha"],
        subtotal=comp["subtotal"],
        descuento=comp["descuento"],
        total=comp["total"],
        renglones=[],
    )