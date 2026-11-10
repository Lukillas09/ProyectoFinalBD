# Pruebas de punta a punta del front (Etapa 7): Playwright para Python.
# La imagen trae Chromium instalado; su versión (v1.49.1) tiene que ser la misma
# que la del paquete `playwright` de requirements.txt, o el navegador no coincide.
FROM mcr.microsoft.com/playwright/python:v1.49.1-noble

WORKDIR /tests

COPY requirements.txt .
# La imagen es de Ubuntu 24.04, cuyo Python está marcado como "externally managed"
# (PEP 668) y rechaza pip sin esta opción. Es una imagen descartable de pruebas:
# instalar en el sistema es aceptable.
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY . .
