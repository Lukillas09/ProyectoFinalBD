"""Genera un PNG por boceto a partir de bocetos.html.

Uso: python3 docs/bocetos/generar.py   (requiere Playwright para Python con Chromium)
"""

from pathlib import Path

from playwright.sync_api import sync_playwright

AQUI = Path(__file__).resolve().parent


def main() -> None:
    with sync_playwright() as p:
        navegador = p.chromium.launch()
        pagina = navegador.new_page(viewport={"width": 1240, "height": 900}, device_scale_factor=1.5)
        pagina.goto((AQUI / "bocetos.html").as_uri())
        for seccion in pagina.locator("section.boceto").all():
            nombre = seccion.get_attribute("id")
            seccion.screenshot(path=str(AQUI / f"{nombre}.png"))
            print(f"{nombre}.png")
        navegador.close()


if __name__ == "__main__":
    main()
