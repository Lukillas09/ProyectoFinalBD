# Carga masiva de datos (Etapa 3)

## Catálogos reales

Los catálogos no se generan al azar (paso 1 de la Etapa 3). Están en `catalogos/`, en CSV UTF-8 con encabezado.

| Archivo | Filas | Contenido | Fuente |
|---|---:|---|---|
| `cepas.csv` | 15 | Nombre, tipo (`tinta`/`blanca`) y uso | Las 12 cepas del Anexo B de la consigna (`uso = cultivo`). Se agregan 3 variedades reales que se cultivan en Argentina y que el generador **no usa** en ningún vino ni parcela (`uso = sin_uso`): Petit Verdot, Viognier y Pedro Giménez. Existen para que D2 ("cepas que no componen ningún vino ni están plantadas") tenga resultado. |
| `maridajes.csv` | 8 | Nombre y temperatura de servicio (°C) | Anexo B. Las temperaturas son orientativas, como aclara la consigna. No incluye "cordero al disco", porque lo crea la consulta I2. |
| `departamentos.csv` | 18 | Los 18 departamentos de Mendoza | Anexo B (B.3). |
| `localidades.csv` | 37 | Nombre, provincia y código postal de cuatro dígitos | Ver abajo. |
| `tipos_vino.csv` | 4 | tinto, blanco, rosado, espumante | Anexo B (B.4) y `ck_vino_tipo`. |
| `presentaciones.csv` | 5 | 187, 375, 750, 1500 (magnum) y 3000 ml | Anexo B (B.4). |

### Localidades y códigos postales

Cada código se tomó del directorio [codigo-postal.ar: Mendoza](https://codigo-postal.ar/provincia/mendoza), consultado el 27/10/2026, que lista los códigos de cuatro dígitos por localidad. Los de San Rafael (5600), General Alvear (5620), Malargüe (5613) y Tunuyán (5560) se confirmaron además con otras fuentes:

- [codigo-postal.com.ar: San Rafael](https://www.codigo-postal.com.ar/mendoza/san-rafael/);
- [Wikipedia: General Alvear, Mendoza](https://en.wikipedia.org/wiki/General_Alvear,_Mendoza) (CPA M5620);
- [codigo-postal.co: Tunuyán](https://codigo-postal.co/en-us/argentina/mendoza/tunuyan/).

El buscador oficial de Correo Argentino no pudo consultarse de forma automatizada. Ante una duda, prevalece esa fuente.

Se usa el código de cuatro dígitos, no el CPA alfanumérico, que identifica caras de manzana y no localidades. Varias localidades comparten código (5603, 5569): por eso la clave candidata de `localidad` es `(provincia, nombre, codigo_postal)` y no el código solo.

**No se incluyeron por no poder confirmarlas con la fuente:**

- **Cuadro Benegas:** no figura. Sólo aparecen "Cuadro Bombal", "Cuadro Nacional" y "Gobernador Benegas", que son otras localidades.
- **Junín:** no figura con ese nombre. Se incluye "Villa de Junín" (5573), tal como aparece.

General Alvear existe porque la consulta I1 la usa.

`encargado_regional` no es un dato real: lo genera Faker con semilla, igual que los nombres de bodegas, fincas, clientes, empleados y transportistas.
