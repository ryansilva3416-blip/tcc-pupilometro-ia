import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'calculo_dp.dart';

/// Resultado bruto devolvido pelo código Android (AnalisadorImagem.kt).
class AnaliseImagem {
  final String caminhoNormalizado;
  final int largura;
  final int altura;
  final int quantidadeRostos;
  final List<Ponto> pontosRosto;
  final List<double>? matrizRosto;
  final List<Marcador> marcadores;
  final double nitidez;
  final int tempoRostoMs;
  final int tempoMarcadorMs;
  final int tempoTotalMs;

  const AnaliseImagem({
    required this.caminhoNormalizado,
    required this.largura,
    required this.altura,
    required this.quantidadeRostos,
    required this.pontosRosto,
    required this.matrizRosto,
    required this.marcadores,
    required this.nitidez,
    required this.tempoRostoMs,
    required this.tempoMarcadorMs,
    required this.tempoTotalMs,
  });

  factory AnaliseImagem.doMapa(Map<Object?, Object?> m) {
    final bruto = m['pontosRosto'] as Float64List?;
    final pontos = <Ponto>[];
    if (bruto != null) {
      for (var i = 0; i + 2 < bruto.length; i += 3) {
        pontos.add(Ponto(bruto[i], bruto[i + 1]));
      }
    }
    final marcadores = <Marcador>[
      for (final item in (m['marcadores'] as List<Object?>? ?? const []))
        Marcador(
          ((item as Map<Object?, Object?>)['id'] as num).toInt(),
          (item['cantos'] as Float64List).toList(),
        ),
    ];
    return AnaliseImagem(
      caminhoNormalizado: m['caminhoNormalizado'] as String,
      largura: (m['largura'] as num).toInt(),
      altura: (m['altura'] as num).toInt(),
      quantidadeRostos: (m['quantidadeRostos'] as num).toInt(),
      pontosRosto: pontos,
      matrizRosto: (m['matrizRosto'] as Float64List?)?.toList(),
      marcadores: marcadores,
      nitidez: (m['nitidez'] as num).toDouble(),
      tempoRostoMs: (m['tempoRostoMs'] as num).toInt(),
      tempoMarcadorMs: (m['tempoMarcadorMs'] as num).toInt(),
      tempoTotalMs: (m['tempoTotalMs'] as num).toInt(),
    );
  }
}

/// Acesso ao Platform Channel de visão computacional (somente Android).
class CanalVisao {
  static const _canal = MethodChannel('br.ufpa.tcc.pupilometro/visao');

  static Future<AnaliseImagem> analisar(String caminho, {String dicionarioAruco = 'DICT_4X4_50'}) async {
    final mapa = await _canal.invokeMapMethod<Object?, Object?>('analisarImagem', {
      'caminho': caminho,
      'dicionarioAruco': dicionarioAruco,
    });
    if (mapa == null) throw StateError('O código nativo não devolveu resultado.');
    return AnaliseImagem.doMapa(mapa);
  }

  static Future<Map<String, String>> versoes() async {
    final m = await _canal.invokeMapMethod<String, String>('versao');
    return m ?? const {};
  }
}
