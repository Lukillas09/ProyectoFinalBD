# Planes de ejecución - Consultas avanzadas S9 a S12 (Etapa 5)

## Cómo se obtuvieron

Los planes de `docs/consultas/planes/` son la salida de los `EXPLAIN (ANALYZE, BUFFERS)` que contiene `consultas/select.sql`, ejecutado con:

```bash
docker compose exec db /opt/bodegas/consultas/ejecutar.sh select.sql
```

En la salida, cada plan va después de una marca `>>> PLAN Sn`. Condiciones de la medición, el 2026-11-05:

- carga completa: `SEMILLA=20260427`, `ESCALA=1`, `FECHA_REFERENCIA=2026-11-05` (la fecha del día, como para la demo). Son 150.338 comprobantes, 539.933 renglones y 20.000 clientes;
- índices de `008_indices.sql`;
- parámetros por omisión del archivo: `cod_vino = 1` y `cuit_bodega = '30555408710'`;
- una sola ejecución de cada plan, con la caché ya caliente por las consultas anteriores del archivo.

Los planes anteriores de esta carpeta se habían medido sobre datos mínimos de validación (2 clientes, 2 vinos y `lote_uva` vacía) y no representaban el volumen de la Etapa 3. Se reemplazaron.

| Consulta | Filas devueltas | Execution Time | Nodo dominante |
|---|---:|---:|---|
| S9 | 1 | 0,343 ms | `Index Scan` por PK en cada tabla de la vista |
| S10 | 1.597 | 568,6 ms | Subconsulta correlacionada sobre el CTE (3.201 ejecuciones) |
| S11 | 5.434 | 117,8 ms | Agregación paralela + dos `WindowAgg` |
| S12A | 2.663 | 358,0 ms | `Nested Loop Anti Join` con `SubPlan` (30.138 ejecuciones) |
| S12B | 7.170 | 159,7 ms | `Hash Right Anti Join` |

---

## S9 — Ficha completa de un vino

**Archivo del plan:** `docs/consultas/planes/S9_plan.txt`

- **Objetivo:** ficha del vino `:cod_vino`, con bodega, corte (cepas y porcentajes), maridajes y stock total, a través de la vista `v_ficha_vino`.
- **Recorrido:** el filtro `cod_vino = 1` llega hasta las tablas base, y cada una se lee por su clave primaria: `Index Scan using pk_vino`, `pk_bodega`, `pk_stock_deposito`, `pk_composicion_vino`, `pk_cepa` y `Index Only Scan using pk_vino_maridaje`.
- **Única excepción:** `stock_sala` se recorre completa (`Seq Scan`, 4.000 filas, 3.960 descartadas por el filtro) para sumar el stock del vino en las 40 salas. Con 4.000 filas tarda 0,11 ms.
- **Interpretación:** corte y maridajes se agregan en `GroupAggregate` separados, antes de unirse a la fila del vino. Por eso no se multiplica el stock (no hay producto cartesiano entre cepas y maridajes).
- **Tiempo:** 0,343 ms para 1 fila. No hace falta ningún índice.

---

## S10 — Rendimiento por parcela y campaña

**Archivo del plan:** `docs/consultas/planes/S10_plan.txt`

- **Objetivo:** rendimiento en kg/ha de cada parcela por campaña, y las parcelas por debajo del promedio de su finca en esa campaña.
- **Herramientas SQL:** CTE `rendimiento_parcela` y subconsulta correlacionada (`AVG(rp2.kg_ha)` de la misma finca y campaña), usada en el `SELECT` y en el `WHERE`.
- **Recorrido:**
  - el CTE se calcula una vez: `Seq Scan on parcela` (682 filas) y, por cada parcela, `Index Scan using uq_lote_uva_parcela_campania`, con `HashAggregate` de 3.201 filas en 5,4 ms;
  - el filtro `kg_ha < (SubPlan 3)` ejecuta la subconsulta **3.201 veces**, y cada una recorre el CTE completo (3.179 filas descartadas por vez): unos 380 ms;
  - `SubPlan 2`, el promedio mostrado en el `SELECT`, se ejecuta otras 1.597 veces, una por fila que pasa el filtro.
- **Interpretación:** el costo está en la subconsulta correlacionada sobre un CTE materializado, que no tiene índices: 3.201 × 3.201 + 1.597 × 3.201 ≈ 15,4 millones de filas recorridas para un CTE de 3.201 filas. Es el ejemplo medido de por qué una subconsulta correlacionada escala de forma cuadrática.
- **Alternativa no aplicada:** `AVG(kg_ha) OVER (PARTITION BY id_finca, campania)` calcularía el promedio en una sola pasada. Se mantiene la subconsulta correlacionada porque la consigna pide mostrar ese recurso. Con 568 ms no justifica cambiar el enunciado ni agregar un índice.

---

## S11 — Ranking de vinos y ventas acumuladas

**Archivo del plan:** `docs/consultas/planes/S11_plan.txt`

- **Objetivo:** ranking de vinos dentro de cada sala y mes por botellas vendidas (`RANK()`), y ventas acumuladas de la sala (`SUM() OVER (... ROWS UNBOUNDED PRECEDING)`).
- **Recorrido:**
  - el período (`fecha >= CURRENT_DATE - 1 year`) se resuelve con `Parallel Index Scan using idx_comprobante_fecha`, el índice con `INCLUDE` de la Etapa 4;
  - después, `Parallel Hash Join` con `Parallel Seq Scan on renglon_comprobante`, 2 workers;
  - `Partial GroupAggregate` y `Finalize GroupAggregate`: 32.103 filas por sala, mes y vino.
- **Funciones de ventana:** dos `WindowAgg` encadenados. El filtro `rnk_mes <= 10` descarta 26.669 filas y deja 5.434.
- **Tiempo:** 117,8 ms. La mayor parte (≈ 90 ms) es la agregación base; las ventanas suman ≈ 25 ms.

---

## S12 — División relacional y anti-join

### S12A — Clientes que compraron todos los vinos de una bodega

**Archivo del plan:** `docs/consultas/planes/S12A_plan.txt`

- **Objetivo:** clientes que compraron todos los vinos de `:cuit_bodega`, por defecto Bodega Lopez S.R.L. (3 vinos). Se resuelve con doble `NOT EXISTS` (división relacional).
- **Recorrido:**
  - los 3 vinos de la bodega se obtienen una vez (`Bitmap Index Scan on uq_vino_identidad_comercial`) y se materializan;
  - para cada uno de los 20.000 clientes, `Nested Loop Anti Join` contra esos vinos;
  - la condición interna (`SubPlan 1`: ¿el cliente compró este vino?) se ejecuta **30.138 veces**, con `Bitmap Index Scan on idx_comprobante_id_cliente` y `Index Only Scan using pk_renglon_comprobante`.
- **Interpretación:** el anti-join corta en el primer vino no comprado, por eso son 30.138 evaluaciones y no 60.000. Los índices de la Etapa 4 sobre `comprobante.id_cliente` y la PK de renglones hacen que cada evaluación cueste unos 9 µs.
- **Lectura del tiempo:** de los 358 ms, 79 ms corresponden a leer las 3 filas de `vino` en el `Bitmap Heap Scan`. Es una lectura de disco en frío, no un costo del algoritmo.
- **Resultado:** 2.663 clientes compraron los tres vinos.

### S12B — Clientes que nunca compraron vinos tintos

**Archivo del plan:** `docs/consultas/planes/S12B_plan.txt`

- **Objetivo:** clientes sin ninguna compra de un vino `tinto`, con `NOT EXISTS` (anti-join).
- **Recorrido:**
  - el planificador decorrelaciona el `NOT EXISTS`: arma una sola vez el conjunto de compras de tintos (`Hash Join` de `renglon_comprobante`, los 310 vinos tintos y `comprobante`, 275.483 filas);
  - después aplica `Hash Right Anti Join` contra los 20.000 clientes.
- **Interpretación:** a diferencia de S12A, acá conviene un solo recorrido completo de las tablas de ventas en lugar de una búsqueda por cliente, porque más de la mitad de los renglones son de tintos.
- **Resultado:** 7.170 clientes. Incluye 4.715 clientes sin ninguna compra; los que compraron algo pero nunca un tinto son 2.455. Si el enunciado se interpreta como "clientes con compras", hace falta agregar `EXISTS (compra)`. Queda como observación para la defensa.

---

## Costo estimado y tiempo real

- **Costo estimado (`cost=`):** unidad arbitraria del planificador, calculada con las estadísticas.
- **Tiempo real (`actual time`, `Execution Time`):** milisegundos medidos al ejecutar.

No son comparables entre sí. Lo que sí se compara son las **filas estimadas y las reales**:

- S12A estima 10.488 clientes y devuelve 2.663;
- S12B estima 10.319 y devuelve 7.170.

En las dos el error no cambió la elección del plan.

---

## Archivos de planes

| Consulta | Archivo |
|----------|---------|
| S9 | `docs/consultas/planes/S9_plan.txt` |
| S10 | `docs/consultas/planes/S10_plan.txt` |
| S11 | `docs/consultas/planes/S11_plan.txt` |
| S12A | `docs/consultas/planes/S12A_plan.txt` |
| S12B | `docs/consultas/planes/S12B_plan.txt` |

S12 tiene dos partes, A y B, unidas con `UNION ALL` en la consulta principal. Para medir cada estrategia por separado, `select.sql` ejecuta un `EXPLAIN` por parte.
