import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../configuracao/preferencias.dart';
import '../medicao/calculo_dp.dart';
import '../medicao/canal_visao.dart';
import '../medicao/registro.dart';

class _Analise {
  final AnaliseImagem imagem;
  final ResultadoDp dp;
  final ConfiguracaoCalculo cfg;
  _Analise(this.imagem, this.dp, this.cfg);
}

class ResultadoPage extends StatefulWidget {
  final String caminhoFoto;
  const ResultadoPage({super.key, required this.caminhoFoto});

  @override
  State<ResultadoPage> createState() => _ResultadoPageState();
}

class _ResultadoPageState extends State<ResultadoPage> {
  late final Future<_Analise> _analise = _analisar();
  final _repo = RepositorioMedicoes();
  final _form = GlobalKey<FormState>();
  final _codigo = TextEditingController();
  final _condicao = TextEditingController(text: 'controlada');
  final _pupilometro = TextEditingController();
  final _observacao = TextEditingController();
  bool _salvando = false;

  static String _ultimoCodigo = '';

  @override
  void initState() {
    super.initState();
    _codigo.text = _ultimoCodigo;
  }

  Future<_Analise> _analisar() async {
    final cfg = await Preferencias.carregarCalculo();
    final dicionario = await Preferencias.dicionario();
    final img = await CanalVisao.analisar(widget.caminhoFoto, dicionarioAruco: dicionario);
    final dp = calcularDp(
      pontos: img.pontosRosto,
      marcadores: img.marcadores,
      cfg: cfg,
      quantidadeRostos: img.quantidadeRostos,
      nitidez: img.nitidez,
    );
    return _Analise(img, dp, cfg);
  }

  Future<void> _salvar(_Analise a) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final codigo = _codigo.text.trim().toUpperCase();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final imagem = await _repo.guardarImagem(a.imagem.caminhoNormalizado, id);
      final pup = double.tryParse(_pupilometro.text.replaceAll(',', '.'));
      final registro = novoRegistro(
        id: id,
        codigoParticipante: codigo,
        repeticao: await _repo.proximaRepeticao(codigo),
        condicao: _condicao.text.trim(),
        resultado: a.dp,
        nitidez: a.imagem.nitidez,
        tempoTotalMs: a.imagem.tempoTotalMs,
        cfg: a.cfg,
        caminhoImagem: imagem,
        dpPupilometroMm: pup,
        observacao: _observacao.text.trim(),
      );
      await _repo.adicionar(registro);
      _ultimoCodigo = codigo;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medição salva ($codigo, repetição ${registro.repeticao}).')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _condicao.dispose();
    _pupilometro.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: FutureBuilder<_Analise>(
        future: _analise,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Analisando a foto...'),
            ]));
          }
          if (snap.hasError) {
            final e = snap.error;
            final msg = e is PlatformException ? (e.message ?? e.code) : '$e';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Falha na análise:\n$msg', textAlign: TextAlign.center),
              ),
            );
          }
          return _conteudo(snap.data!);
        },
      ),
    );
  }

  Widget _conteudo(_Analise a) {
    final r = a.dp;
    final tema = Theme.of(context);
    String mm(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} mm';

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: a.imagem.largura / a.imagem.altura,
            child: LayoutBuilder(builder: (context, box) {
              return Stack(fit: StackFit.expand, children: [
                Image.file(File(a.imagem.caminhoNormalizado), fit: BoxFit.fill),
                CustomPaint(
                  painter: _MarcacoesPainter(
                    escala: box.maxWidth / a.imagem.largura,
                    resultado: r,
                    marcadores: a.imagem.marcadores,
                    idMarcador: a.cfg.idMarcador,
                  ),
                ),
              ]);
            }),
          ),
          const SizedBox(height: 16),
          Card(
            color: r.aprovada ? Colors.green.shade50 : (r.erros.isEmpty ? Colors.amber.shade50 : Colors.red.shade50),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DP (marcador): ${mm(r.dpMarcadorMm)}', style: tema.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('DP (íris, comparação): ${mm(r.dpIrisMm)}'),
                const SizedBox(height: 8),
                Text(
                  'Rolagem ${r.rolagemGraus?.toStringAsFixed(1) ?? '—'}°  •  '
                  'Marcador ${r.ladoMarcadorPx?.toStringAsFixed(0) ?? '—'} px  •  '
                  'Nitidez ${a.imagem.nitidez.toStringAsFixed(0)}  •  '
                  '${a.imagem.tempoTotalMs} ms',
                  style: tema.textTheme.bodySmall,
                ),
                for (final e in r.erros) _linha(Icons.error_outline, Colors.red, e),
                for (final w in r.avisos) _linha(Icons.warning_amber, Colors.orange.shade800, w),
                if (r.aprovada) _linha(Icons.check_circle_outline, Colors.green, 'Captura dentro dos critérios.'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codigo,
            decoration: const InputDecoration(labelText: 'Código do participante (ex.: P001)', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pupilometro,
            decoration: const InputDecoration(
              labelText: 'DP no pupilômetro (mm) — opcional',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              return double.tryParse(v.replaceAll(',', '.')) == null ? 'Número inválido' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _condicao,
            decoration: const InputDecoration(labelText: 'Condição de captura', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _observacao,
            decoration: const InputDecoration(labelText: 'Observação', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _salvando ? null : () => Navigator.of(context).pop(),
                child: const Text('Repetir captura'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                // Salva mesmo com avisos/erros: capturas rejeitadas também são dado do experimento.
                onPressed: _salvando ? null : () => _salvar(a),
                child: Text(_salvando ? 'Salvando...' : 'Salvar medição'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _linha(IconData icone, Color cor, String texto) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(texto)),
        ]),
      );
}

class _MarcacoesPainter extends CustomPainter {
  final double escala;
  final ResultadoDp resultado;
  final List<Marcador> marcadores;
  final int idMarcador;

  _MarcacoesPainter({
    required this.escala,
    required this.resultado,
    required this.marcadores,
    required this.idMarcador,
  });

  Offset _o(Ponto p) => Offset(p.x * escala, p.y * escala);

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in marcadores) {
      final pts = m.pontos.map(_o).toList();
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(
        path,
        Paint()
          ..color = m.id == idMarcador ? Colors.amber : Colors.grey
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    final a = resultado.centroA, b = resultado.centroB;
    if (a != null && b != null) {
      final linha = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 2;
      canvas.drawLine(_o(a), _o(b), linha);
      for (final c in [a, b]) {
        canvas.drawCircle(_o(c), 5, Paint()..color = Colors.cyanAccent);
        canvas.drawCircle(
          _o(c),
          (resultado.diametroIrisPx ?? 0) / 2 * escala,
          Paint()
            ..color = Colors.cyanAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarcacoesPainter old) =>
      old.escala != escala || old.resultado != resultado;
}
