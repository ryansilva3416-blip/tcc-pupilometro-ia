"""Cálculo da distância interpupilar (DP) — implementação de referência.

Este módulo é a especificação executável do cálculo. O app Flutter
(app/lib/medicao/calculo_dp.dart) implementa exatamente as mesmas regras e
os testes dos dois lados usam os mesmos casos. Qualquer mudança aqui deve ser
replicada lá (e vice-versa), com a versão do algoritmo incrementada.

Entradas (em pixels da imagem já normalizada pelo EXIF):
  pontos     -> sequência de 478 pontos (x, y) ou (x, y, z) do MediaPipe Face Landmarker
  marcadores -> lista de dicts {"id": int, "cantos": [x0, y0, x1, y1, x2, y2, x3, y3]}

Duas estimativas são produzidas:
  dp_marcador_mm -> escala pelo marcador ArUco de tamanho conhecido (método principal)
  dp_iris_mm     -> escala pelo diâmetro médio da íris humana (comparação; ver Vakunov e Lagun, 2020)
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

VERSAO_ALGORITMO = "1.0.0"

# Índices do modelo de 478 pontos do MediaPipe Face Landmarker.
IRIS_A_CENTRO, IRIS_A_CONTORNO = 468, (469, 470, 471, 472)
IRIS_B_CENTRO, IRIS_B_CONTORNO = 473, (474, 475, 476, 477)
PONTA_NARIZ = 1
CANTO_EXTERNO_A = 33
CANTO_EXTERNO_B = 263


@dataclass
class Configuracao:
    tamanho_marcador_mm: float = 40.0
    id_marcador: int = 0
    diametro_iris_mm: float = 11.7
    # "contorno": centro = média dos 4 pontos do contorno da íris
    # "ponto":    centro = ponto central fornecido pelo modelo (468/473)
    modo_centro: str = "contorno"
    # Limites iniciais; devem ser revistos após o piloto.
    max_rolagem_graus: float = 2.0
    max_assimetria_rosto: float = 0.06
    max_assimetria_marcador: float = 0.05
    min_lado_marcador_px: float = 80.0
    min_diametro_iris_px: float = 20.0
    min_nitidez: float = 40.0
    dp_plausivel_mm: tuple[float, float] = (45.0, 80.0)


@dataclass
class Resultado:
    aprovada: bool
    dp_marcador_mm: float | None
    dp_iris_mm: float | None
    distancia_px: float | None
    escala_mm_por_px: float | None
    lado_marcador_px: float | None
    assimetria_marcador: float | None
    diametro_iris_px: float | None
    rolagem_graus: float | None
    assimetria_rosto: float | None
    centro_a: tuple[float, float] | None
    centro_b: tuple[float, float] | None
    erros: list[str] = field(default_factory=list)   # impedem o resultado
    avisos: list[str] = field(default_factory=list)  # resultado existe, mas a captura é suspeita
    versao_algoritmo: str = VERSAO_ALGORITMO


def _xy(pontos, i):
    p = pontos[i]
    return float(p[0]), float(p[1])


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def centro_iris(pontos, centro: int, contorno, modo: str):
    if modo == "ponto":
        return _xy(pontos, centro)
    if modo == "contorno":
        xs = [_xy(pontos, i)[0] for i in contorno]
        ys = [_xy(pontos, i)[1] for i in contorno]
        return sum(xs) / len(xs), sum(ys) / len(ys)
    raise ValueError(f"modo_centro inválido: {modo}")


def diametro_horizontal_iris(pontos, contorno) -> float:
    """Diâmetro pelo par de pontos opostos mais horizontal (pálpebras cobrem o eixo vertical)."""
    p = [_xy(pontos, i) for i in contorno]
    pares = [(p[0], p[2]), (p[1], p[3])]
    a, b = max(pares, key=lambda par: abs(par[0][0] - par[1][0]))
    return _dist(a, b)


def medidas_marcador(cantos) -> tuple[float, float]:
    """Retorna (lado médio em px, assimetria entre lados opostos)."""
    c = [(cantos[2 * i], cantos[2 * i + 1]) for i in range(4)]
    lados = [_dist(c[i], c[(i + 1) % 4]) for i in range(4)]
    medio = sum(lados) / 4.0

    def rel(x, y):
        return abs(x - y) / ((x + y) / 2.0)

    assimetria = max(rel(lados[0], lados[2]), rel(lados[1], lados[3]))
    return medio, assimetria


def calcular(pontos, marcadores, cfg: Configuracao | None = None,
             quantidade_rostos: int = 1, nitidez: float | None = None) -> Resultado:
    cfg = cfg or Configuracao()
    erros: list[str] = []
    avisos: list[str] = []

    r = dict(dp_marcador_mm=None, dp_iris_mm=None, distancia_px=None, escala_mm_por_px=None,
             lado_marcador_px=None, assimetria_marcador=None, diametro_iris_px=None,
             rolagem_graus=None, assimetria_rosto=None, centro_a=None, centro_b=None)

    if quantidade_rostos == 0 or not pontos or len(pontos) < 478:
        erros.append("Nenhum rosto com pontos da íris foi detectado.")
        return Resultado(aprovada=False, erros=erros, avisos=avisos, **r)
    if quantidade_rostos > 1:
        erros.append("Mais de um rosto na foto.")

    # Centros das íris, ordenados da esquerda para a direita na imagem.
    ca = centro_iris(pontos, IRIS_A_CENTRO, IRIS_A_CONTORNO, cfg.modo_centro)
    cb = centro_iris(pontos, IRIS_B_CENTRO, IRIS_B_CONTORNO, cfg.modo_centro)
    if cb[0] < ca[0]:
        ca, cb = cb, ca
    d_px = _dist(ca, cb)
    r.update(centro_a=ca, centro_b=cb, distancia_px=d_px)

    rolagem = math.degrees(math.atan2(cb[1] - ca[1], cb[0] - ca[0]))
    r["rolagem_graus"] = rolagem
    if abs(rolagem) > cfg.max_rolagem_graus:
        avisos.append(f"Cabeça inclinada ({rolagem:.1f}°).")

    nariz = _xy(pontos, PONTA_NARIZ)
    e1, e2 = _xy(pontos, CANTO_EXTERNO_A), _xy(pontos, CANTO_EXTERNO_B)
    d1, d2 = abs(nariz[0] - e1[0]), abs(e2[0] - nariz[0])
    assim_rosto = (d1 - d2) / (d1 + d2) if (d1 + d2) > 0 else 0.0
    r["assimetria_rosto"] = assim_rosto
    if abs(assim_rosto) > cfg.max_assimetria_rosto:
        avisos.append("Rosto virado para o lado.")

    diam = (diametro_horizontal_iris(pontos, IRIS_A_CONTORNO)
            + diametro_horizontal_iris(pontos, IRIS_B_CONTORNO)) / 2.0
    r["diametro_iris_px"] = diam
    if diam < cfg.min_diametro_iris_px:
        avisos.append("Rosto muito distante: íris pequena na imagem.")
    if diam > 0:
        r["dp_iris_mm"] = d_px * cfg.diametro_iris_mm / diam

    alvo = [m for m in marcadores if int(m["id"]) == cfg.id_marcador]
    if not alvo:
        erros.append("Marcador de calibração não encontrado.")
    elif len(alvo) > 1:
        erros.append("Mais de um marcador de calibração com o mesmo código.")
    else:
        lado, assim = medidas_marcador(alvo[0]["cantos"])
        escala = cfg.tamanho_marcador_mm / lado
        r.update(lado_marcador_px=lado, assimetria_marcador=assim, escala_mm_por_px=escala,
                 dp_marcador_mm=escala * d_px)
        if lado < cfg.min_lado_marcador_px:
            avisos.append("Marcador pequeno na imagem: aproxime o celular.")
        if assim > cfg.max_assimetria_marcador:
            avisos.append("Marcador inclinado em relação à câmera.")

    if nitidez is not None and nitidez < cfg.min_nitidez:
        avisos.append("Foto possivelmente tremida ou desfocada.")

    dp = r["dp_marcador_mm"]
    if dp is not None and not (cfg.dp_plausivel_mm[0] <= dp <= cfg.dp_plausivel_mm[1]):
        avisos.append(f"DP fora da faixa esperada para adultos ({dp:.1f} mm).")

    return Resultado(aprovada=not erros and not avisos, erros=erros, avisos=avisos, **r)
