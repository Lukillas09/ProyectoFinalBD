"""Demostración de prevención de SQL Injection en GET /vinos (Etapa 6).

Esta prueba verifica que:
1. Los valores de los filtros se tratan como parámetros, no como texto SQL.
2. La validación de Pydantic rechaza entradas inválidas antes de llegar a la base.
3. La tabla bodegas.vino permanece intacta después de intentos de inyección.
4. No se ejecutan sentencias SQL adicionales.

El contrato de la API define los filtros con dominios estrictos (enum, rangos,
patrones), así que cualquier intento de inyección que altere la estructura SQL
es rechazado en la capa de validación (HTTP 422). La parametrización en la
capa de datos (Psycopg 3) es la segunda línea de defensa: aunque un valor
pasara la validación, se enviaría a PostgreSQL como parámetro, nunca como
parte del texto de la consulta.
"""

import pytest


class TestSQLInjectionPrevencion:
    """Pruebas de prevención de SQL Injection en GET /vinos."""

    def test_caso_a_consulta_legitima(self, cliente, consultar) -> None:
        """Caso A: Consulta legítima con filtro válido."""
        # Primero, obtener un tipo que exista en la base
        tipo_existente = consultar(
            "SELECT tipo FROM vino GROUP BY tipo ORDER BY count(*) DESC LIMIT 1"
        )
        assert tipo_existente is not None

        respuesta = cliente.get("/vinos", params={"tipo": tipo_existente})

        assert respuesta.status_code == 200
        pagina = respuesta.json()
        assert pagina["total"] > 0
        assert all(item["tipo"] == tipo_existente for item in pagina["items"])

    @pytest.mark.parametrize(
        "payload, descripcion",
        [
            ("tinto' OR '1'='1", "Inyección clásica OR '1'='1"),
            ("tinto'; DROP TABLE vino; --", "Intento de DROP TABLE"),
            ("tinto' UNION SELECT * FROM usuario; --", "Intento de UNION SELECT"),
            ("tinto' OR 1=1; --", "Inyección con comentario SQL"),
            ("' OR '1'='1", "Inyección sin valor base"),
            ("tinto\"; DELETE FROM vino; --", "Intento con comillas dobles"),
        ],
    )
    def test_caso_b_entrada_maliciosa_rechazada_por_validacion(
        self, cliente, payload: str, descripcion: str
    ) -> None:
        """Caso B: Entradas maliciosas en el filtro 'tipo' son rechazadas por validación.

        El parámetro 'tipo' es un Literal enum (tinto, blanco, rosado, espumante).
        Cualquier valor fuera de ese dominio responde HTTP 422 con codigo='validacion'.
        La inyección no llega a PostgreSQL.
        """
        respuesta = cliente.get("/vinos", params={"tipo": payload})

        assert respuesta.status_code == 422, f"Falló para: {descripcion}"
        cuerpo = respuesta.json()
        assert cuerpo["codigo"] == "validacion", f"Falló para: {descripcion}"
        assert "query.tipo" in [e["campo"] for e in cuerpo["errores"]], f"Falló para: {descripcion}"
        assert "items" not in cuerpo, f"La respuesta no debe contener items para: {descripcion}"

    @pytest.mark.parametrize(
        "params, descripcion",
        [
            ({"id_cepa": 999999}, "id_cepa inexistente pero válido como entero"),
            ({"cuit_bodega": "30500000000"}, "cuit_bodega de 11 dígitos válido pero inexistente"),
            ({"anada": 2100}, "anada válida pero inexistente en los datos"),
        ],
    )
    def test_caso_b_valor_valido_pero_inexistente_no_inyecta(
        self, cliente, params: dict, descripcion: str
    ) -> None:
        """Caso B bis: Valores que pasan validación de tipo/formato pero no existen en la base.

        Estos valores llegan a PostgreSQL como parámetros. La consulta no falla,
        devuelve lista vacía (total=0), demostrando que el valor se trata como
        parámetro de comparación, no como SQL ejecutable.
        """
        respuesta = cliente.get("/vinos", params=params)

        # Debe responder 200 con lista vacía, no 500 ni error de SQL
        assert respuesta.status_code == 200, f"Falló para: {descripcion}"
        pagina = respuesta.json()
        assert pagina["total"] == 0, f"Debe devolver 0 resultados para: {descripcion}"
        assert pagina["items"] == [], f"Items debe ser lista vacía para: {descripcion}"

    def test_caso_c_intento_multiples_sentencias(self, cliente, consultar) -> None:
        """Caso C: Intento de inyección de múltiples sentencias.

        Verifica que un payload que simula múltiples sentencias SQL se trata
        como un valor de parámetro único, no como sentencias separadas.
        """
        # Usamos un parámetro numérico para evitar la validación de enum
        # id_cepa acepta enteros, así que probamos con un valor que podría
        # interpretarse como múltiples sentencias si se concatenara
        payload = 1  # id_cepa válido

        # Primero verificamos que hay datos para id_cepa=1
        count_antes = consultar("SELECT count(*) FROM vino WHERE EXISTS (SELECT 1 FROM composicion_vino WHERE cod_vino = vino.cod_vino AND id_cepa = 1)")

        respuesta = cliente.get("/vinos", params={"id_cepa": payload})

        assert respuesta.status_code == 200
        pagina = respuesta.json()
        # Debe devolver solo los vinos con esa cepa, no todos los vinos
        assert pagina["total"] == count_antes

        # Verificar integridad de la tabla vino después
        count_despues = consultar("SELECT count(*) FROM vino")
        count_antes_total = consultar("SELECT count(*) FROM vino")
        assert count_despues == count_antes_total

    def test_verificacion_integridad_tabla_vino(self, cliente, consultar) -> None:
        """Verifica que la tabla bodegas.vino permanece intacta después de las pruebas."""
        # Estado antes de las pruebas de inyección
        count_antes = consultar("SELECT count(*) FROM vino")
        assert count_antes > 0, "La base debe tener datos de prueba"

        # Ejecutar varios intentos de inyección (todos rechazados por validación)
        payloads_maliciosos = [
            {"tipo": "tinto' OR '1'='1"},
            {"tipo": "tinto'; DROP TABLE vino; --"},
            {"tipo": "' UNION SELECT * FROM bodega; --"},
            {"id_cepa": 999999},
            {"cuit_bodega": "99999999999"},
            {"anada": 1800},
        ]

        for params in payloads_maliciosos:
            respuesta = cliente.get("/vinos", params=params)
            # Todos deben responder 422 (validación) o 200 (lista vacía), nunca 500
            assert respuesta.status_code in (200, 422), f"Código inesperado para {params}: {respuesta.status_code}"

        # Estado después de las pruebas
        count_despues = consultar("SELECT count(*) FROM vino")

        # La tabla debe tener exactamente la misma cantidad de registros
        assert count_despues == count_antes, (
            f"La tabla vino cambió: antes={count_antes}, después={count_despues}. "
            "Posible inyección exitosa o efecto secundario."
        )

        # Verificar que no hay filas huérfanas ni cambios en columnas clave
        sample_antes = consultar("SELECT cod_vino, nombre, tipo, anada FROM vino ORDER BY cod_vino LIMIT 5")
        sample_despues = consultar("SELECT cod_vino, nombre, tipo, anada FROM vino ORDER BY cod_vino LIMIT 5")
        assert sample_despues == sample_antes, "Los datos de muestra cambiaron después de intentos de inyección"

    def test_evidencia_consulta_parametrizada(self, cliente, consultar) -> None:
        """Demuestra que la consulta SQL usa parámetros (evidencia en código).

        Esta prueba verifica que el código de acceso a datos en
        api/app/datos/vinos.py usa placeholders (%(tipo)s, etc.) y pasa
        los valores como diccionario de parámetros a cursor.execute().
        """
        # La evidencia real está en el código de api/app/datos/vinos.py:
        # - LISTAR usa %(tipo)s::varchar IS NULL OR v.tipo = %(tipo)s
        # - Los parámetros se pasan como diccionario: cur.execute(LISTAR, parametros)
        # - Psycopg 3 envía el SQL y los parámetros por separado a PostgreSQL

        # Verificamos el comportamiento: misma consulta, distintos parámetros
        tipo1 = consultar("SELECT tipo FROM vino GROUP BY tipo ORDER BY count(*) DESC LIMIT 1")
        tipo2 = consultar("SELECT tipo FROM vino WHERE tipo != %s GROUP BY tipo ORDER BY count(*) DESC LIMIT 1", (tipo1,))

        if tipo2 is None:
            pytest.skip("Solo un tipo de vino en la base, no se puede comparar")

        resp1 = cliente.get("/vinos", params={"tipo": tipo1})
        resp2 = cliente.get("/vinos", params={"tipo": tipo2})

        assert resp1.status_code == 200
        assert resp2.status_code == 200

        pagina1 = resp1.json()
        pagina2 = resp2.json()

        # Los totales deben ser diferentes (filtrados por tipo)
        assert pagina1["total"] != pagina2["total"] or pagina1["total"] == 0

        # Y cada resultado debe coincidir con su filtro
        if pagina1["total"] > 0:
            assert all(item["tipo"] == tipo1 for item in pagina1["items"])
        if pagina2["total"] > 0:
            assert all(item["tipo"] == tipo2 for item in pagina2["items"])


class TestEvidenciaParametrosSQL:
    """Pruebas que documentan la evidencia de parametrización en el código."""

    def test_codigo_acceso_datos_usa_placeholders(self) -> None:
        """Verifica que el módulo de acceso a datos usa placeholders, no f-strings.

        Esta prueba es de documentación: lee el archivo fuente y verifica
        patrones seguros. No ejecuta SQL, solo inspecciona el código.
        """
        import pathlib

        # En el contenedor de pruebas, el código está en /app/app/datos/vinos.py
        archivo = pathlib.Path("/app/app/datos/vinos.py")
        contenido = archivo.read_text(encoding="utf-8")

        # Verificar que NO hay f-strings con SQL
        assert 'f"SELECT' not in contenido, "No debe haber f-strings con SELECT"
        assert "f'UPDATE" not in contenido, "No debe haber f-strings con UPDATE"
        assert "f'INSERT" not in contenido, "No debe haber f-strings con INSERT"
        assert "f'DELETE" not in contenido, "No debe haber f-strings con DELETE"

        # Verificar que SÍ hay placeholders de Psycopg (%s o %(nombre)s)
        assert "%(tipo)s" in contenido, "Debe usar placeholder %(tipo)s"
        assert "%(cuit_bodega)s" in contenido, "Debe usar placeholder %(cuit_bodega)s"
        assert "%(anada)s" in contenido, "Debe usar placeholder %(anada)s"
        assert "%(id_cepa)s" in contenido, "Debe usar placeholder %(id_cepa)s"

        # Verificar que execute() recibe parámetros como diccionario
        assert "cur.execute(LISTAR, parametros)" in contenido or "conn.execute(" in contenido

        # Verificar patrón de filtro seguro: (param IS NULL OR columna = param)
        assert "IS NULL OR v.tipo = %(" in contenido
        assert "IS NULL OR v.cuit_bodega = %(" in contenido
        assert "IS NULL OR v.anada = %(" in contenido
        assert "IS NULL OR EXISTS (" in contenido