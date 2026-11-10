"""Verifica se a detecção ArUco com refinamento subpixel estima bem o lado do marcador."""
import cv2
import numpy as np
import pytest

from pupilometro.calculo import medidas_marcador
from pupilometro.marcador import detectar, gerar_pdf, imagem_marcador


def cena_com_marcador(lado_px: float, desfoque: float = 0.0, ruido: float = 0.0, seed: int = 0):
    """Desenha o marcador com lado não inteiro via transformação afim (testa precisão subpixel)."""
    rng = np.random.default_rng(seed)
    base = 400
    marc = imagem_marcador(0, base)
    escala = lado_px / base
    m = np.float32([[escala, 0, 300.37], [0, escala, 250.81]])
    fundo = np.full((900, 1200), 200, np.uint8)
    cena = cv2.warpAffine(marc, m, (1200, 900), dst=fundo.copy(), flags=cv2.INTER_AREA,
                          borderMode=cv2.BORDER_TRANSPARENT)
    if desfoque:
        cena = cv2.GaussianBlur(cena, (0, 0), desfoque)
    if ruido:
        cena = np.clip(cena + rng.normal(0, ruido, cena.shape), 0, 255).astype(np.uint8)
    return cena


@pytest.mark.parametrize("lado", [90.4, 137.25, 211.9])
def test_lado_estimado_com_erro_menor_que_meio_por_cento(lado):
    cena = cena_com_marcador(lado, desfoque=1.0, ruido=3.0)
    marcs = detectar(cena)
    assert len(marcs) == 1 and marcs[0]["id"] == 0
    estimado, assim = medidas_marcador(marcs[0]["cantos"])
    assert abs(estimado - lado) / lado < 0.005
    assert assim < 0.01


def test_sem_marcador():
    assert detectar(np.full((480, 640), 128, np.uint8)) == []


def test_pdf_gerado(tmp_path):
    saida = tmp_path / "m.pdf"
    gerar_pdf(str(saida), 40, 0)
    assert saida.stat().st_size > 1000
