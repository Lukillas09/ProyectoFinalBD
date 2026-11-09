-- Bodegas del Atuel - RN-16: los vinos de un ingreso son de su bodega de
-- origen (issue #30, Etapa 6).
-- Ejecutar con el rol propietario. Sin BEGIN/COMMIT: db/migrate.sh envuelve
-- cada archivo en su propia transacción.
--
-- Por qué. La consigna registra en cada ingreso la "bodega de origen", y cada
-- vino pertenece a una sola bodega (vino.cuit_bodega). Hasta esta migración
-- la coherencia entre las dos sólo la verificaba el control R3 de la carga
-- masiva (db/seed/controles.sql): la base aceptaba, desde la API o desde
-- psql, un renglón con un vino de otra bodega. RN-16 no figura en el PDF: es
-- una regla del proyecto, aprobada al implementar los ingresos en la API.
--
-- Por qué un trigger y no una FK compuesta. Una FK (cod_vino, cuit_bodega)
-- hacia vino obligaría a copiar cuit_bodega en renglon_ingreso, donde
-- repetiría el dato de la cabecera, y a agregar un UNIQUE redundante en vino.
-- La regla compara dos filas de otras tablas: va en un trigger
-- (docs/trazabilidad.md, sección 2).
--
-- Alcance. Se verifica al agregar un renglón o al cambiar su vino o su
-- ingreso. Cambiar después la bodega de un vino o de un ingreso no vuelve a
-- verificar los renglones existentes: la API no modifica ingresos, y la
-- bodega de un vino con movimientos es historia.
--
-- Orden. Los triggers BEFORE de una tabla se disparan por orden alfabético:
-- trg_renglon_ingreso_bloqueo (RN-12) va antes que trg_renglon_ingreso_bodega,
-- así un ingreso que ya no está en confección responde RN-12.

SET search_path TO bodegas, pg_catalog;

-- No es SECURITY DEFINER: sólo lee ingreso y vino, que el rol que inserta
-- renglones (propietario o bodegas_rw) ya puede leer. Sin ingreso o sin vino
-- no decide nada: la FK correspondiente informa el error (23503).
CREATE FUNCTION fn_trg_renglon_ingreso_bodega()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = bodegas, pg_temp
AS $$
DECLARE
  v_bodega_ingreso TEXT;
  v_bodega_vino TEXT;
BEGIN
  SELECT cuit_bodega INTO v_bodega_ingreso
  FROM ingreso
  WHERE cod_ingreso = NEW.cod_ingreso;

  SELECT cuit_bodega INTO v_bodega_vino
  FROM vino
  WHERE cod_vino = NEW.cod_vino;

  IF v_bodega_vino <> v_bodega_ingreso THEN
    RAISE EXCEPTION 'RN-16: el vino % es de la bodega %; el ingreso % es de la bodega %.',
      NEW.cod_vino, v_bodega_vino, NEW.cod_ingreso, v_bodega_ingreso
      USING ERRCODE = 'P0001',
            HINT = 'Un ingreso trae vinos de su bodega de origen: registre otro ingreso para esa bodega.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bodega
BEFORE INSERT OR UPDATE OF cod_ingreso, cod_vino ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_ingreso_bodega();

-- Como en 005_triggers.sql: PostgreSQL no verifica EXECUTE al disparar un
-- trigger, pero ninguna función queda expuesta a PUBLIC por omisión.
REVOKE ALL ON FUNCTION fn_trg_renglon_ingreso_bodega() FROM PUBLIC;

COMMENT ON TRIGGER trg_renglon_ingreso_bodega ON renglon_ingreso IS
  'RN-16: los vinos de un ingreso son de su bodega de origen.';
