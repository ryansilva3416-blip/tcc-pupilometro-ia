import math

import pytest

from pupilometro import Configuracao, calcular
from pupilometro.casos_teste import marcador_quadrado, rosto_sintetico


def test_caso_basico_dp_63mm():
    # Marcador de 40 mm com 100 px de lado -> 0,4 mm/px. Íris a 157,5 px -> 63 mm.
    pts = rosto_sintetico(centro_a=(400, 500), centro_b=(557.5, 500), raio_iris=23.0)
    r = calcular(pts, [marcador_quadrado(lado=100)], quantidade_rostos=1, nitidez=100)
    assert r.dp_marcador_mm == pytest.approx(63.0, abs=1e-9)
    assert r.escala_mm_por_px == pytest.approx(0.4)
    assert r.erros == [] and r.avisos == []
    assert r.aprovada


def test_dp_pela_iris():
    # Diâmetro 2*30 = 60 px corresponde a 11,7 mm. 300 px -> 58,5 mm.
    pts = rosto_sintetico(centro_a=(400, 500), centro_b=(700, 500), raio_iris=30.0)
    r = calcular(pts, [marcador_quadrado(lado=200)])
    assert r.dp_iris_mm == pytest.approx(300 * 11.7 / 60)
    assert r.dp_marcador_mm == pytest.approx(300 * 40 / 200)


def test_ordem_das_iris_nao_importa():
    a = calcular(rosto_sintetico(centro_a=(700, 500), centro_b=(400, 500)), [marcador_quadrado(lado=200)])
    b = calcular(rosto_sintetico(centro_a=(400, 500), centro_b=(700, 500)), [marcador_quadrado(lado=200)])
    assert a.dp_marcador_mm == pytest.approx(b.dp_marcador_mm)
    assert a.centro_a[0] < a.centro_b[0]


def test_modo_ponto_vs_contorno_iguais_em_iris_circular():
    pts = rosto_sintetico()
    c = calcular(pts, [marcador_quadrado(lado=200)], Configuracao(modo_centro="contorno"))
    p = calcular(pts, [marcador_quadrado(lado=200)], Configuracao(modo_centro="ponto"))
    assert c.dp_marcador_mm == pytest.approx(p.dp_marcador_mm)


def test_rotacao_preserva_distancia_e_gera_aviso():
    pts = rosto_sintetico(rotacao_graus=5.0)
    r = calcular(pts, [marcador_quadrado(lado=200)])
    assert r.distancia_px == pytest.approx(300.0)
    assert r.rolagem_graus == pytest.approx(5.0)
    assert any("inclinada" in a for a in r.avisos)
    assert not r.aprovada


def test_rosto_virado():
    pts = rosto_sintetico(nariz=(600, 620))  # nariz deslocado para um lado
    r = calcular(pts, [marcador_quadrado(lado=200)])
    assert any("virado" in a for a in r.avisos)


def test_sem_marcador_e_erro():
    r = calcular(rosto_sintetico(), [])
    assert r.dp_marcador_mm is None
    assert any("Marcador" in e for e in r.erros)
    assert r.dp_iris_mm is not None  # a estimativa pela íris continua disponível


def test_marcador_com_id_errado_e_ignorado():
    r = calcular(rosto_sintetico(), [marcador_quadrado(lado=200, id_=7)])
    assert r.dp_marcador_mm is None


def test_marcador_duplicado_e_erro():
    r = calcular(rosto_sintetico(), [marcador_quadrado(lado=200), marcador_quadrado(x=900, lado=200)])
    assert any("mesmo código" in e for e in r.erros)


def test_marcador_inclinado_gera_aviso():
    r = calcular(rosto_sintetico(), [marcador_quadrado(lado=200, deformacao=0.2)])
    assert r.assimetria_marcador > 0.05
    assert any("Marcador inclinado" in a for a in r.avisos)


def test_marcador_pequeno_e_foto_tremida():
    r = calcular(rosto_sintetico(), [marcador_quadrado(lado=60)], nitidez=5)
    assert any("pequeno" in a for a in r.avisos)
    assert any("tremida" in a for a in r.avisos)


def test_nenhum_rosto():
    r = calcular([], [marcador_quadrado()], quantidade_rostos=0)
    assert not r.aprovada and r.dp_marcador_mm is None


def test_dois_rostos_e_erro():
    r = calcular(rosto_sintetico(), [marcador_quadrado(lado=200)], quantidade_rostos=2)
    assert any("Mais de um rosto" in e for e in r.erros)


def test_dp_implausivel_gera_aviso():
    pts = rosto_sintetico(centro_a=(100, 500), centro_b=(700, 500))  # 600 px * 0,2 = 120 mm
    r = calcular(pts, [marcador_quadrado(lado=200)])
    assert any("faixa esperada" in a for a in r.avisos)


def test_diametro_usa_par_horizontal_mesmo_rotacionado():
    pts = rosto_sintetico(raio_iris=25, rotacao_graus=30)
    r = calcular(pts, [marcador_quadrado(lado=200)])
    assert r.diametro_iris_px == pytest.approx(50.0)
    assert math.isfinite(r.dp_iris_mm)
