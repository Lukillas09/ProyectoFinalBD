# Versión exacta de Python: junto con requirements.txt fija el comportamiento
# de random y Faker, del que depende la reproducibilidad de los datos.
FROM python:3.12.7-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONHASHSEED=0

WORKDIR /seed

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt

RUN addgroup --system seed \
    && adduser --system --ingroup seed --home /home/seed seed

COPY --chown=seed:seed catalogos ./catalogos
COPY --chown=seed:seed generar_datos.py ./generar_datos.py

USER seed

ENTRYPOINT ["python", "generar_datos.py"]
CMD ["cargar"]
