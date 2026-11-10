import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'calculo_dp.dart';

/// Uma medição do experimento (aplicativo x pupilômetro).
///
/// Nesta etapa os registros ficam só no celular. Na etapa 2 passam para o Supabase.
/// Identificação SEMPRE por código (ex.: P001), nunca por nome.
class RegistroMedicao {
  final String id;
  final DateTime dataHora;
  final String codigoParticipante;
  final int repeticao;
  final String condicao; // ex.: "controlada", "pouca luz", "distancia 40cm"
  final double? dpMarcadorMm;
  final double? dpIrisMm;
  final double? dpPupilometroMm;
  final bool aprovada;
  final List<String> erros;
  final List<String> avisos;
  final double? rolagemGraus;
  final double? assimetriaRosto;
  final double? assimetriaMarcador;
  final double? ladoMarcadorPx;
  final double? diametroIrisPx;
  final double nitidez;
  final int tempoTotalMs;
  final String modoCentro;
  final double tamanhoMarcadorMm;
  final String versaoAlgoritmo;
  final String caminhoImagem;
  final String observacao;

  RegistroMedicao({
    required this.id,
    required this.dataHora,
    required this.codigoParticipante,
    required this.repeticao,
    required this.condicao,
    required this.dpMarcadorMm,
    required this.dpIrisMm,
    required this.dpPupilometroMm,
    required this.aprovada,
    required this.erros,
    required this.avisos,
    required this.rolagemGraus,
    required this.assimetriaRosto,
    required this.assimetriaMarcador,
    required this.ladoMarcadorPx,
    required this.diametroIrisPx,
    required this.nitidez,
    required this.tempoTotalMs,
    required this.modoCentro,
    required this.tamanhoMarcadorMm,
    required this.versaoAlgoritmo,
    required this.caminhoImagem,
    required this.observacao,
  });

  Map<String, Object?> paraJson() => {
        'id': id,
        'dataHora': dataHora.toIso8601String(),
        'codigoParticipante': codigoParticipante,
        'repeticao': repeticao,
        'condicao': condicao,
        'dpMarcadorMm': dpMarcadorMm,
        'dpIrisMm': dpIrisMm,
        'dpPupilometroMm': dpPupilometroMm,
        'aprovada': aprovada,
        'erros': erros,
        'avisos': avisos,
        'rolagemGraus': rolagemGraus,
        'assimetriaRosto': assimetriaRosto,
        'assimetriaMarcador': assimetriaMarcador,
        'ladoMarcadorPx': ladoMarcadorPx,
        'diametroIrisPx': diametroIrisPx,
        'nitidez': nitidez,
        'tempoTotalMs': tempoTotalMs,
        'modoCentro': modoCentro,
        'tamanhoMarcadorMm': tamanhoMarcadorMm,
        'versaoAlgoritmo': versaoAlgoritmo,
        'caminhoImagem': caminhoImagem,
        'observacao': observacao,
      };

  factory RegistroMedicao.doJson(Map<String, Object?> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return RegistroMedicao(
      id: j['id'] as String,
      dataHora: DateTime.parse(j['dataHora'] as String),
      codigoParticipante: j['codigoParticipante'] as String,
      repeticao: (j['repeticao'] as num).toInt(),
      condicao: j['condicao'] as String? ?? '',
      dpMarcadorMm: d('dpMarcadorMm'),
      dpIrisMm: d('dpIrisMm'),
      dpPupilometroMm: d('dpPupilometroMm'),
      aprovada: j['aprovada'] as bool,
      erros: (j['erros'] as List).cast<String>(),
      avisos: (j['avisos'] as List).cast<String>(),
      rolagemGraus: d('rolagemGraus'),
      assimetriaRosto: d('assimetriaRosto'),
      assimetriaMarcador: d('assimetriaMarcador'),
      ladoMarcadorPx: d('ladoMarcadorPx'),
      diametroIrisPx: d('diametroIrisPx'),
      nitidez: d('nitidez') ?? 0,
      tempoTotalMs: (j['tempoTotalMs'] as num?)?.toInt() ?? 0,
      modoCentro: j['modoCentro'] as String? ?? '',
      tamanhoMarcadorMm: d('tamanhoMarcadorMm') ?? 0,
      versaoAlgoritmo: j['versaoAlgoritmo'] as String? ?? '',
      caminhoImagem: j['caminhoImagem'] as String? ?? '',
      observacao: j['observacao'] as String? ?? '',
    );
  }

  static const colunasCsv = [
    'id', 'dataHora', 'codigoParticipante', 'repeticao', 'condicao', 'dpMarcadorMm', 'dpIrisMm',
    'dpPupilometroMm', 'aprovada', 'erros', 'avisos', 'rolagemGraus', 'assimetriaRosto',
    'assimetriaMarcador', 'ladoMarcadorPx', 'diametroIrisPx', 'nitidez', 'tempoTotalMs',
    'modoCentro', 'tamanhoMarcadorMm', 'versaoAlgoritmo', 'arquivoImagem', 'observacao',
  ];

  List<String> linhaCsv() {
    String n(double? v) => v == null ? '' : v.toStringAsFixed(4);
    return [
      id, dataHora.toIso8601String(), codigoParticipante, '$repeticao', condicao, n(dpMarcadorMm),
      n(dpIrisMm), n(dpPupilometroMm), aprovada ? '1' : '0', erros.join(' | '), avisos.join(' | '),
      n(rolagemGraus), n(assimetriaRosto), n(assimetriaMarcador), n(ladoMarcadorPx), n(diametroIrisPx),
      n(nitidez), '$tempoTotalMs', modoCentro, n(tamanhoMarcadorMm), versaoAlgoritmo,
      p.basename(caminhoImagem), observacao,
    ];
  }
}

String _csvCampo(String s) =>
    (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;

/// Gera o CSV (separador vírgula, ponto decimal) lido pelos scripts de analysis/.
String gerarCsv(List<RegistroMedicao> registros) {
  final b = StringBuffer()..writeln(RegistroMedicao.colunasCsv.join(','));
  for (final r in registros) {
    b.writeln(r.linhaCsv().map(_csvCampo).join(','));
  }
  return b.toString();
}

/// Persistência local em JSON Lines + cópia das imagens.
class RepositorioMedicoes {
  Future<Directory> _pasta() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'medicoes'));
    await Directory(p.join(d.path, 'imagens')).create(recursive: true);
    return d;
  }

  Future<File> _arquivo() async => File(p.join((await _pasta()).path, 'registros.jsonl'));

  Future<String> guardarImagem(String origem, String id) async {
    final destino = p.join((await _pasta()).path, 'imagens', '$id.jpg');
    await File(origem).copy(destino);
    return destino;
  }

  Future<void> adicionar(RegistroMedicao r) async {
    final f = await _arquivo();
    await f.writeAsString('${jsonEncode(r.paraJson())}\n', mode: FileMode.append, flush: true);
  }

  Future<List<RegistroMedicao>> listar() async {
    final f = await _arquivo();
    if (!await f.exists()) return [];
    final linhas = await f.readAsLines();
    return [
      for (final l in linhas)
        if (l.trim().isNotEmpty) RegistroMedicao.doJson(jsonDecode(l) as Map<String, Object?>),
    ].reversed.toList();
  }

  Future<int> proximaRepeticao(String codigo) async {
    final todos = await listar();
    return todos.where((r) => r.codigoParticipante == codigo).length + 1;
  }

  Future<File> exportarCsv() async {
    final registros = (await listar()).reversed.toList();
    final pasta = await getTemporaryDirectory();
    final carimbo = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final f = File(p.join(pasta.path, 'medicoes_$carimbo.csv'));
    await f.writeAsString(gerarCsv(registros));
    return f;
  }
}

/// Cria o registro a partir do resultado do cálculo.
RegistroMedicao novoRegistro({
  required String id,
  required String codigoParticipante,
  required int repeticao,
  required String condicao,
  required ResultadoDp resultado,
  required double nitidez,
  required int tempoTotalMs,
  required ConfiguracaoCalculo cfg,
  required String caminhoImagem,
  double? dpPupilometroMm,
  String observacao = '',
}) {
  return RegistroMedicao(
    id: id,
    dataHora: DateTime.now(),
    codigoParticipante: codigoParticipante,
    repeticao: repeticao,
    condicao: condicao,
    dpMarcadorMm: resultado.dpMarcadorMm,
    dpIrisMm: resultado.dpIrisMm,
    dpPupilometroMm: dpPupilometroMm,
    aprovada: resultado.aprovada,
    erros: resultado.erros,
    avisos: resultado.avisos,
    rolagemGraus: resultado.rolagemGraus,
    assimetriaRosto: resultado.assimetriaRosto,
    assimetriaMarcador: resultado.assimetriaMarcador,
    ladoMarcadorPx: resultado.ladoMarcadorPx,
    diametroIrisPx: resultado.diametroIrisPx,
    nitidez: nitidez,
    tempoTotalMs: tempoTotalMs,
    modoCentro: cfg.modoCentro.name,
    tamanhoMarcadorMm: cfg.tamanhoMarcadorMm,
    versaoAlgoritmo: resultado.versao,
    caminhoImagem: caminhoImagem,
    observacao: observacao,
  );
}
