FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir --requirement requirements.txt

RUN addgroup --system app \
    && adduser --system --ingroup app --home /home/app app

COPY --chown=app:app app ./app

# Pruebas automáticas (servicio api-test, perfil "test"). Las dependencias de
# desarrollo y las pruebas quedan sólo en esta etapa, no en la imagen que corre.
FROM base AS test
COPY requirements-dev.txt ./requirements-dev.txt
RUN pip install --no-cache-dir --requirement requirements-dev.txt
COPY --chown=app:app tests ./tests
USER app
# python -m agrega /app al path, para que las pruebas importen el paquete app.
# Sin caché de pytest: el usuario app no escribe en /app.
CMD ["python", "-m", "pytest", "-v", "-p", "no:cacheprovider", "tests"]

# Imagen de ejecución: es la última etapa, la que construye `docker compose up`.
FROM base AS runtime
USER app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
