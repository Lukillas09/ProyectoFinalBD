# Comentario de revisión — PR #4

**PR:** #4 — Etapa 3: carga masiva reproducible  
**Rama:** `etapa-3-carga` → `main` (mergeado)  
**Estado:** cerrado y mergeado  
**Enlace:** https://github.com/Lukillas09/ProyectoFinalBD/pull/4

## Parte del código revisada

Carga masiva: `db/seed/generar_datos.py`, `db/seed/catalogos/*.csv` (cepas, departamentos, localidades, maridajes, presentaciones, tipos_vino), `db/seed/controles.sql`, `db/seed/hashes.sql`, `db/seed/post_carga.sql`, `db/seed/Dockerfile`, `db/seed/.dockerignore`, `db/seed/README.md`, `db/seed/requirements.txt`; servicio `seed` con perfil propio en `docker-compose.yml`; documentación `docs/carga_masiva.md`; cambios menores en `README.md`, `AGENTS.md`, `requisitos.md`.

## Qué se verificó

- **No agrega migraciones ni modifica 001 a 007:** cumple el requisito de no tocar el esquema ya aplicado. Solo añade objetos bajo `db/seed/` y el servicio de Compose.
- **Reproducibilidad:** misma `SEMILLA`, `FECHA_REFERENCIA` y `ESCALA` producen las mismas huellas en `db/seed/hashes.sql`; `controles.sql` verifica integridad post-carga (55 controles, 0 violaciones sobre la carga documentada).
- **Volumen documentado:** 6 años de historia, más de 150.000 ventas y 538.306 renglones (realmente 150.125 comprobantes y 538.306 renglones según `docs/rendimiento.md`). Catálogos reales del Anexo B y 37 localidades de Mendoza.
- **Carga controlada:** se conecta como propietario, deshabilita solo los triggers que chocan con la historia, dentro de una única transacción. `post_carga.sql` calcula los importes (mediante `UPDATE` posterior, anotado como mejora pendiente en `docs/rendimiento.md` 6.1).
- **Perfil de Compose:** el servicio `seed` tiene el perfil `seed` y no corre con un `up` normal (`docker compose --profile seed run --rm seed`). Solo recibe credenciales del propietario y está en la red interna `datos`.
- **Verificación documentada:** `run_all.sh` 7 de 7, `controles.sql` con `fecha_referencia=2026-10-27` y `post_carga.sql` pasan sobre la base con `008` aplicada; también se probó desde cero en proyecto aislado `bda_etapa4_prueba` con `ESCALA=0.1` (`docs/rendimiento.md` sección 10).

## Decisiones técnicas importantes

- **Reproducibilidad sobre aleatoriedad:** el generador usa una semilla fija para que cualquier integrante regenere idénticos datos y huellas. Esto es clave para la defensa: cualquier integrante puede recargar y obtener los mismos resultados.
- **`FECHA_REFERENCIA` y `CURRENT_DATE`:** antes de la demo hay que regenerar con la fecha del día, porque varias consultas (y la vista `v_ventas_mensuales_sala` por períodos relativos) usan `CURRENT_DATE`. Es una dependencia temporal que debe mencionarse en la defensa.
- **Importes en `UPDATE` posterior:** el generador inserta primero y calcula importes después con un `UPDATE` de todas las filas. Esto desordena `comprobante`, deja páginas vacías y hace que `BRIN` sobre `fecha` no sea viable (correlación −0,005, `docs/rendimiento.md` 6.1). Está identificado como mejora opcional para una etapa posterior (calcular importes en el mismo `INSERT`), que requiere recargar y volver a medir.

## Dudas o mejoras detectadas

- Ningún error funcional. Observación de diseño: la carga usa `UPDATE` posterior para importes, lo que deja la tabla `comprobante` con ~1.400 páginas vacías (3.060 páginas totales, 1.657 con filas vivas). Esto afecta el modelo de costos del planificador (`docs/rendimiento.md` 8.1, caso D/E). No es un bloqueo, pero un integrante debería saberlo si se le pide explicar por qué un índice no se usa en algún caso.
- El servicio `seed` no se levanta con `docker compose up` (tiene perfil `seed`); hay que invocarlo explícitamente. No es un error, pero cabe recordarlo en la defensa si se le pregunta cómo cargar datos.

## Aspectos que debe poder explicar cada integrante en la defensa

1. Cómo se carga la base desde cero y cuál es el orden: `db` (bootstrap) → `migrate` (001 a 008) → `seed` (solo con perfil `seed`).
2. Qué garantiza la reproducibilidad (misma `SEMILLA`, `FECHA_REFERENCIA`, `ESCALA` → mismas huellas en `hashes.sql`).
3. Dónde están los controles de integridad post-carga (`db/seed/controles.sql`) y qué verifican (55 controles, 0 violaciones).
4. Por qué el servicio `seed` no corre con `up` normal y cómo se invoca.
5. Qué volumen de datos genera la carga (150.125 comprobantes, 538.306 renglones, 6 años).
6. Por qué los importes se calculan en un `UPDATE` posterior y qué implicancia tiene en rendimiento y en la viabilidad de `BRIN`.

Archivos para comprobar: `db/seed/generar_datos.py`, `db/seed/controles.sql`, `db/seed/hashes.sql`, `db/seed/post_carga.sql`, `docs/carga_masiva.md`, `docker-compose.yml` (servicio `seed`), `docs/rendimiento.md` (secciones 6.1 y 10).
