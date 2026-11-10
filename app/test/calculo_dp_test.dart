// Mesmos casos de analysis/tests/test_calculo.py.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pupilometro/medicao/calculo_dp.dart';
import 'package:pupilometro/medicao/registro.dart';

List<Ponto> rostoSintetico({
  Ponto centroA = const Ponto(400, 500),
  Ponto centroB = const Ponto(700, 500),
  double raioIris = 30,
  Ponto? nariz,
  double rotacaoGraus = 0,
}) {
  final pts = List<Ponto>.filled(478, const Ponto(0, 0), growable: false);
  final meio = Ponto((centroA.x + centroB.x) / 2, (centroA.y + centroB.y) / 2);
  pts[1] = nariz ?? Ponto(meio.x, meio.y + 120);
  pts[33] = Ponto(centroA.x - 70, centroA.y);
  pts[263] = Ponto(centroB.x + 70, centroB.y);
  for (final (c, ic, contorno) in [(centroA, 468, irisAContorno), (centroB, 473, irisBContorno)]) {
    pts[ic] = c;
    for (var k = 0; k < 4; k++) {
      final ang = math.pi / 2 * k;
      pts[contorno[k]] = Ponto(c.x + raioIris * math.cos(ang), c.y + raioIris * math.sin(ang));
    }
  }
  if (rotacaoGraus != 0) {
    final t = rotacaoGraus * math.pi / 180;
    for (var i = 0; i < pts.length; i++) {
      final x = pts[i].x - meio.x, y = pts[i].y - meio.y;
      pts[i] = Ponto(meio.x + x * math.cos(t) - y * math.sin(t), meio.y + x * math.sin(t) + y * math.cos(t));
    }
  }
  return pts;
}

Marcador marcadorQuadrado({double x = 500, double y = 200, double lado = 100, int id = 0, double deformacao = 0}) =>
    Marcador(id, [
      x, y,
      x + lado, y + deformacao * lado / 2,
      x + lado, y + lado - deformacao * lado / 2,
      x, y + lado,
    ]);

void main() {
  test('caso básico: DP de 63 mm', () {
    final r = calcularDp(
      pontos: rostoSintetico(centroA: const Ponto(400, 500), centroB: const Ponto(557.5, 500), raioIris: 23),
      marcadores: [marcadorQuadrado(lado: 100)],
      nitidez: 100,
    );
    expect(r.dpMarcadorMm, closeTo(63.0, 1e-9));
    expect(r.escalaMmPorPx, closeTo(0.4, 1e-12));
    expect(r.erros, isEmpty);
    expect(r.avisos, isEmpty);
    expect(r.aprovada, isTrue);
  });

  test('DP pela íris', () {
    final r = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200)]);
    expect(r.dpIrisMm, closeTo(300 * 11.7 / 60, 1e-9));
    expect(r.dpMarcadorMm, closeTo(60, 1e-9));
  });

  test('ordem das íris não importa', () {
    final a = calcularDp(
        pontos: rostoSintetico(centroA: const Ponto(700, 500), centroB: const Ponto(400, 500)),
        marcadores: [marcadorQuadrado(lado: 200)]);
    expect(a.dpMarcadorMm, closeTo(60, 1e-9));
    expect(a.centroA!.x < a.centroB!.x, isTrue);
  });

  test('modo ponto e contorno iguais em íris circular', () {
    final c = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200)]);
    final p = calcularDp(
        pontos: rostoSintetico(),
        marcadores: [marcadorQuadrado(lado: 200)],
        cfg: const ConfiguracaoCalculo(modoCentro: ModoCentro.ponto));
    expect(c.dpMarcadorMm, closeTo(p.dpMarcadorMm!, 1e-9));
  });

  test('rotação preserva a distância e gera aviso', () {
    final r = calcularDp(pontos: rostoSintetico(rotacaoGraus: 5), marcadores: [marcadorQuadrado(lado: 200)]);
    expect(r.distanciaPx, closeTo(300, 1e-9));
    expect(r.rolagemGraus, closeTo(5, 1e-9));
    expect(r.avisos.any((a) => a.contains('inclinada')), isTrue);
    expect(r.aprovada, isFalse);
  });

  test('rosto virado', () {
    final r = calcularDp(pontos: rostoSintetico(nariz: const Ponto(600, 620)), marcadores: [marcadorQuadrado(lado: 200)]);
    expect(r.avisos.any((a) => a.contains('virado')), isTrue);
  });

  test('sem marcador é erro, mas DP pela íris continua', () {
    final r = calcularDp(pontos: rostoSintetico(), marcadores: []);
    expect(r.dpMarcadorMm, isNull);
    expect(r.erros.any((e) => e.contains('Marcador')), isTrue);
    expect(r.dpIrisMm, isNotNull);
  });

  test('marcador com id errado é ignorado; duplicado é erro', () {
    expect(calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200, id: 7)]).dpMarcadorMm, isNull);
    final dup = calcularDp(
        pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200), marcadorQuadrado(x: 900, lado: 200)]);
    expect(dup.erros.any((e) => e.contains('mesmo código')), isTrue);
  });

  test('marcador inclinado, pequeno e foto tremida', () {
    final r1 = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200, deformacao: 0.2)]);
    expect(r1.assimetriaMarcador! > 0.05, isTrue);
    expect(r1.avisos.any((a) => a.contains('Marcador inclinado')), isTrue);
    final r2 = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 60)], nitidez: 5);
    expect(r2.avisos.any((a) => a.contains('pequeno')), isTrue);
    expect(r2.avisos.any((a) => a.contains('tremida')), isTrue);
  });

  test('nenhum rosto e dois rostos', () {
    expect(calcularDp(pontos: [], marcadores: [marcadorQuadrado()], quantidadeRostos: 0).aprovada, isFalse);
    final r = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200)], quantidadeRostos: 2);
    expect(r.erros.any((e) => e.contains('Mais de um rosto')), isTrue);
  });

  test('DP implausível gera aviso', () {
    final r = calcularDp(
        pontos: rostoSintetico(centroA: const Ponto(100, 500), centroB: const Ponto(700, 500)),
        marcadores: [marcadorQuadrado(lado: 200)]);
    expect(r.avisos.any((a) => a.contains('faixa esperada')), isTrue);
  });

  test('diâmetro usa o par horizontal mesmo rotacionado', () {
    final r = calcularDp(pontos: rostoSintetico(raioIris: 25, rotacaoGraus: 30), marcadores: [marcadorQuadrado(lado: 200)]);
    expect(r.diametroIrisPx, closeTo(50, 1e-9));
  });

  test('CSV com cabeçalho e campos escapados', () {
    final res = calcularDp(pontos: rostoSintetico(), marcadores: [marcadorQuadrado(lado: 200)]);
    final reg = novoRegistro(
      id: '1',
      codigoParticipante: 'P001',
      repeticao: 1,
      condicao: 'luz, fraca',
      resultado: res,
      nitidez: 100,
      tempoTotalMs: 300,
      cfg: const ConfiguracaoCalculo(),
      caminhoImagem: '/x/1.jpg',
      dpPupilometroMm: 60.5,
    );
    final linhas = gerarCsv([reg]).trim().split('\n');
    expect(linhas.first.split(',').length, RegistroMedicao.colunasCsv.length);
    expect(linhas[1], contains('"luz, fraca"'));
    expect(linhas[1], contains('60.5000'));
  });
}
