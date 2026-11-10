"""Geração e detecção do marcador ArUco de calibração.

Uso para gerar o arquivo de impressão:
    python -m pupilometro.marcador --tamanho-mm 40 --id 0 --saida marcador_40mm.pdf

Imprima em 100% (sem "ajustar à página") e confira a régua de 50 mm com uma régua real.
"""
from __future__ import annotations

import argparse

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

DICIONARIOS = {
    "DICT_4X4_50": cv2.aruco.DICT_4X4_50,
    "DICT_4X4_100": cv2.aruco.DICT_4X4_100,
    "DICT_5X5_50": cv2.aruco.DICT_5X5_50,
    "DICT_5X5_100": cv2.aruco.DICT_5X5_100,
    "DICT_6X6_50": cv2.aruco.DICT_6X6_50,
}


def imagem_marcador(id_: int, lado_px: int, dicionario: str = "DICT_4X4_50") -> np.ndarray:
    d = cv2.aruco.getPredefinedDictionary(DICIONARIOS[dicionario])
    return cv2.aruco.generateImageMarker(d, id_, lado_px)


def detectar(cinza: np.ndarray, dicionario: str = "DICT_4X4_50") -> list[dict]:
    """Mesma configuração usada no Android (AnalisadorImagem.kt)."""
    d = cv2.aruco.getPredefinedDictionary(DICIONARIOS[dicionario])
    p = cv2.aruco.DetectorParameters()
    p.cornerRefinementMethod = cv2.aruco.CORNER_REFINE_SUBPIX
    cantos, ids, _ = cv2.aruco.ArucoDetector(d, p).detectMarkers(cinza)
    if ids is None:
        return []
    return [{"id": int(i), "cantos": c.reshape(-1).astype(float).tolist()} for c, i in zip(cantos, ids.ravel())]


def gerar_pdf(saida: str, tamanho_mm: float = 40.0, id_: int = 0, dicionario: str = "DICT_4X4_50",
              dpi: int = 600) -> None:
    mm = dpi / 25.4
    pagina = Image.new("L", (round(210 * mm), round(297 * mm)), 255)  # A4
    lado = round(tamanho_mm * mm)
    marc = Image.fromarray(imagem_marcador(id_, lado, dicionario))
    x0, y0 = round(30 * mm), round(40 * mm)
    # Margem branca de 1 módulo em volta ajuda a detecção.
    pagina.paste(marc, (x0, y0))

    desenho = ImageDraw.Draw(pagina)
    try:
        fonte = ImageFont.truetype("DejaVuSans.ttf", round(4 * mm))
    except OSError:
        fonte = ImageFont.load_default()

    desenho.text((x0, round(15 * mm)), f"Marcador de calibração — {tamanho_mm:g} mm — {dicionario} id {id_}",
                 fill=0, font=fonte)
    # Régua de conferência de 50 mm
    ry = y0 + lado + round(25 * mm)
    desenho.line((x0, ry, x0 + round(50 * mm), ry), fill=0, width=max(2, round(0.3 * mm)))
    for k in range(0, 51, 10):
        x = x0 + round(k * mm)
        desenho.line((x, ry - round(3 * mm), x, ry + round(3 * mm)), fill=0, width=max(2, round(0.3 * mm)))
    desenho.text((x0, ry + round(5 * mm)), "Régua de conferência: deve medir exatamente 50 mm.",
                 fill=0, font=fonte)
    desenho.text((x0, ry + round(11 * mm)), "Imprima em 100% (tamanho real), sem ajustar à página.",
                 fill=0, font=fonte)
    desenho.text((x0, ry + round(17 * mm)),
                 f"O lado do quadrado preto externo deve medir {tamanho_mm:g} mm.", fill=0, font=fonte)
    pagina.save(saida, "PDF", resolution=dpi)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tamanho-mm", type=float, default=40.0)
    ap.add_argument("--id", type=int, default=0)
    ap.add_argument("--dicionario", default="DICT_4X4_50", choices=sorted(DICIONARIOS))
    ap.add_argument("--saida", default="marcador.pdf")
    a = ap.parse_args()
    gerar_pdf(a.saida, a.tamanho_mm, a.id, a.dicionario)
    print(f"Gerado: {a.saida}")


if __name__ == "__main__":
    main()
