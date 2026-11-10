// Cálculo da distância interpupilar (DP).
//
// Espelho exato de analysis/pupilometro/calculo.py (implementação de referência).
// Qualquer mudança aqui deve ser replicada lá, com VERSAO_ALGORITMO incrementada.
//
// Este arquivo é Dart puro (sem Flutter), para poder ser testado isoladamente.

import 'dart:math' as math;

const String versaoAlgoritmo = '1.0.0';

// Índices do modelo de 478 pontos do MediaPipe Face Landmarker.
const int irisACentro = 468;
const List<int> irisAContorno = [469, 470, 471, 472];
const int irisBCentro = 473;
const List<int> irisBContorno = [474, 475, 476, 477];
const int pontaNariz = 1;
const int cantoExternoA = 33;
const int cantoExternoB = 263;

class Ponto {
  final double x;
  final double y;
  const Ponto(this.x, this.y);

  double distancia(Ponto o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

class Marcador {
  final int id;

  /// [x0, y0, x1, y1, x2, y2, x3, y3] em pixels, ordem do OpenCV.
  final List<double> cantos;
  const Marcador(this.id, this.cantos);

  List<Ponto> get pontos => [for (var i = 0; i < 4; i++) Ponto(cantos[2 * i], cantos[2 * i + 1])];
}

enum ModoCentro { contorno, ponto }

class ConfiguracaoCalculo {
  final double tamanhoMarcadorMm;
  final int idMarcador;
  final double diametroIrisMm;
  final ModoCentro modoCentro;
  // Limites iniciais; devem ser revistos após o piloto.
  final double maxRolagemGraus;
  final double maxAssimetriaRosto;
  final double maxAssimetriaMarcador;
  final double minLadoMarcadorPx;
  final double minDiametroIrisPx;
  final double minNitidez;
  final double dpMinimaMm;
  final double dpMaximaMm;

  const ConfiguracaoCalculo({
    this.tamanhoMarcadorMm = 40.0,
    this.idMarcador = 0,
    this.diametroIrisMm = 11.7,
    this.modoCentro = ModoCentro.contorno,
    this.maxRolagemGraus = 2.0,
    this.maxAssimetriaRosto = 0.06,
    this.maxAssimetriaMarcador = 0.05,
    this.minLadoMarcadorPx = 80.0,
    this.minDiametroIrisPx = 20.0,
    this.minNitidez = 40.0,
    this.dpMinimaMm = 45.0,
    this.dpMaximaMm = 80.0,
  });
}

class ResultadoDp {
  final bool aprovada;
  final double? dpMarcadorMm;
  final double? dpIrisMm;
  final double? distanciaPx;
  final double? escalaMmPorPx;
  final double? ladoMarcadorPx;
  final double? assimetriaMarcador;
  final double? diametroIrisPx;
  final double? rolagemGraus;
  final double? assimetriaRosto;
  final Ponto? centroA;
  final Ponto? centroB;

  /// Impedem o resultado.
  final List<String> erros;

  /// O resultado existe, mas a captura é suspeita.
  final List<String> avisos;
  final String versao = versaoAlgoritmo;

  const ResultadoDp({
    required this.aprovada,
    this.dpMarcadorMm,
    this.dpIrisMm,
    this.distanciaPx,
    this.escalaMmPorPx,
    this.ladoMarcadorPx,
    this.assimetriaMarcador,
    this.diametroIrisPx,
    this.rolagemGraus,
    this.assimetriaRosto,
    this.centroA,
    this.centroB,
    this.erros = const [],
    this.avisos = const [],
  });
}

Ponto _xy(List<Ponto> pontos, int i) => pontos[i];

Ponto centroIris(List<Ponto> pontos, int centro, List<int> contorno, ModoCentro modo) {
  switch (modo) {
    case ModoCentro.ponto:
      return _xy(pontos, centro);
    case ModoCentro.contorno:
      var sx = 0.0, sy = 0.0;
      for (final i in contorno) {
        sx += pontos[i].x;
        sy += pontos[i].y;
      }
      return Ponto(sx / contorno.length, sy / contorno.length);
  }
}

/// Diâmetro pelo par de pontos opostos mais horizontal (pálpebras cobrem o eixo vertical).
double diametroHorizontalIris(List<Ponto> pontos, List<int> contorno) {
  final p = [for (final i in contorno) pontos[i]];
  final pares = [
    [p[0], p[2]],
    [p[1], p[3]],
  ];
  pares.sort((a, b) => (b[0].x - b[1].x).abs().compareTo((a[0].x - a[1].x).abs()));
  return pares.first[0].distancia(pares.first[1]);
}

/// Retorna (lado médio em px, assimetria entre lados opostos).
(double, double) medidasMarcador(List<double> cantos) {
  final c = Marcador(0, cantos).pontos;
  final lados = [for (var i = 0; i < 4; i++) c[i].distancia(c[(i + 1) % 4])];
  final medio = lados.reduce((a, b) => a + b) / 4.0;
  double rel(double x, double y) => (x - y).abs() / ((x + y) / 2.0);
  final assimetria = math.max(rel(lados[0], lados[2]), rel(lados[1], lados[3]));
  return (medio, assimetria);
}

String _f1(double v) => v.toStringAsFixed(1);

ResultadoDp calcularDp({
  required List<Ponto> pontos,
  required List<Marcador> marcadores,
  ConfiguracaoCalculo cfg = const ConfiguracaoCalculo(),
  int quantidadeRostos = 1,
  double? nitidez,
}) {
  final erros = <String>[];
  final avisos = <String>[];

  if (quantidadeRostos == 0 || pontos.length < 478) {
    erros.add('Nenhum rosto com pontos da íris foi detectado.');
    return ResultadoDp(aprovada: false, erros: erros, avisos: avisos);
  }
  if (quantidadeRostos > 1) erros.add('Mais de um rosto na foto.');

  // Centros das íris, ordenados da esquerda para a direita na imagem.
  var ca = centroIris(pontos, irisACentro, irisAContorno, cfg.modoCentro);
  var cb = centroIris(pontos, irisBCentro, irisBContorno, cfg.modoCentro);
  if (cb.x < ca.x) {
    final t = ca;
    ca = cb;
    cb = t;
  }
  final dPx = ca.distancia(cb);

  final rolagem = math.atan2(cb.y - ca.y, cb.x - ca.x) * 180.0 / math.pi;
  if (rolagem.abs() > cfg.maxRolagemGraus) avisos.add('Cabeça inclinada (${_f1(rolagem)}°).');

  final nariz = _xy(pontos, pontaNariz);
  final e1 = _xy(pontos, cantoExternoA), e2 = _xy(pontos, cantoExternoB);
  final d1 = (nariz.x - e1.x).abs(), d2 = (e2.x - nariz.x).abs();
  final assimRosto = (d1 + d2) > 0 ? (d1 - d2) / (d1 + d2) : 0.0;
  if (assimRosto.abs() > cfg.maxAssimetriaRosto) avisos.add('Rosto virado para o lado.');

  final diam = (diametroHorizontalIris(pontos, irisAContorno) +
          diametroHorizontalIris(pontos, irisBContorno)) /
      2.0;
  if (diam < cfg.minDiametroIrisPx) avisos.add('Rosto muito distante: íris pequena na imagem.');
  final double? dpIris = diam > 0 ? dPx * cfg.diametroIrisMm / diam : null;

  double? lado, assim, escala, dpMarcador;
  final alvo = marcadores.where((m) => m.id == cfg.idMarcador).toList();
  if (alvo.isEmpty) {
    erros.add('Marcador de calibração não encontrado.');
  } else if (alvo.length > 1) {
    erros.add('Mais de um marcador de calibração com o mesmo código.');
  } else {
    final (l, a) = medidasMarcador(alvo.first.cantos);
    lado = l;
    assim = a;
    escala = cfg.tamanhoMarcadorMm / l;
    dpMarcador = escala * dPx;
    if (l < cfg.minLadoMarcadorPx) avisos.add('Marcador pequeno na imagem: aproxime o celular.');
    if (a > cfg.maxAssimetriaMarcador) avisos.add('Marcador inclinado em relação à câmera.');
  }

  if (nitidez != null && nitidez < cfg.minNitidez) {
    avisos.add('Foto possivelmente tremida ou desfocada.');
  }

  if (dpMarcador != null && (dpMarcador < cfg.dpMinimaMm || dpMarcador > cfg.dpMaximaMm)) {
    avisos.add('DP fora da faixa esperada para adultos (${_f1(dpMarcador)} mm).');
  }

  return ResultadoDp(
    aprovada: erros.isEmpty && avisos.isEmpty,
    dpMarcadorMm: dpMarcador,
    dpIrisMm: dpIris,
    distanciaPx: dPx,
    escalaMmPorPx: escala,
    ladoMarcadorPx: lado,
    assimetriaMarcador: assim,
    diametroIrisPx: diam,
    rolagemGraus: rolagem,
    assimetriaRosto: assimRosto,
    centroA: ca,
    centroB: cb,
    erros: erros,
    avisos: avisos,
  );
}
