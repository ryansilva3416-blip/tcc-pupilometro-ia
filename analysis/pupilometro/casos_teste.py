"""Gera pontos sintéticos de rosto para testes (usado em Python e copiado para os testes Dart)."""
from __future__ import annotations

import math


def rosto_sintetico(centro_a=(400.0, 500.0), centro_b=(700.0, 500.0), raio_iris=30.0,
                    nariz=None, canto_a=None, canto_b=None, rotacao_graus=0.0):
    """478 pontos (x, y, 0) com íris circulares e pontos de pose coerentes.

    O contorno de cada íris segue a ordem 0°, 90°, 180°, 270° (direita, baixo, esquerda, cima),
    e o ponto central é o centro exato.
    """
    pts = [[0.0, 0.0, 0.0] for _ in range(478)]
    meio = ((centro_a[0] + centro_b[0]) / 2, (centro_a[1] + centro_b[1]) / 2)
    nariz = nariz or (meio[0], meio[1] + 120)
    canto_a = canto_a or (centro_a[0] - 70, centro_a[1])
    canto_b = canto_b or (centro_b[0] + 70, centro_b[1])

    def colocar(i, p):
        pts[i] = [float(p[0]), float(p[1]), 0.0]

    for centro, ic, contorno in ((centro_a, 468, (469, 470, 471, 472)),
                                 (centro_b, 473, (474, 475, 476, 477))):
        colocar(ic, centro)
        for k, idx in enumerate(contorno):
            ang = math.radians(90 * k)
            colocar(idx, (centro[0] + raio_iris * math.cos(ang), centro[1] + raio_iris * math.sin(ang)))
    colocar(1, nariz)
    colocar(33, canto_a)
    colocar(263, canto_b)

    if rotacao_graus:
        t = math.radians(rotacao_graus)
        for p in pts:
            x, y = p[0] - meio[0], p[1] - meio[1]
            p[0] = meio[0] + x * math.cos(t) - y * math.sin(t)
            p[1] = meio[1] + x * math.sin(t) + y * math.cos(t)
    return pts


def marcador_quadrado(x=500.0, y=200.0, lado=100.0, id_=0, deformacao=0.0):
    """Cantos na ordem do OpenCV: sup-esq, sup-dir, inf-dir, inf-esq.

    deformacao > 0 encurta o lado direito (simula marcador inclinado).
    """
    return {
        "id": id_,
        "cantos": [x, y,
                   x + lado, y + deformacao * lado / 2,
                   x + lado, y + lado - deformacao * lado / 2,
                   x, y + lado],
    }
