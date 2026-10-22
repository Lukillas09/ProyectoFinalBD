# Pruebas de base de datos

`001_infraestructura.sql` comprueba desde la propia cuenta de la API que la conexión funciona, que el rol no tiene atributos administrativos, membresías, permisos para crear objetos ni privilegios predeterminados futuros, y que el propietario limitado es dueño de la base y del esquema. También confirma el invariante temporal de que `bodegas` no contiene todavía relaciones de negocio.

Las pruebas de restricciones y reglas del negocio se agregarán cuando se implemente el esquema. Cada regla RN-01 a RN-15 deberá tener al menos un caso válido y uno de rechazo cuando corresponda, con el resultado esperado documentado.
