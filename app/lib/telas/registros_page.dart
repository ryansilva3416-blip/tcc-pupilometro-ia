import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../medicao/registro.dart';

class RegistrosPage extends StatefulWidget {
  const RegistrosPage({super.key});

  @override
  State<RegistrosPage> createState() => _RegistrosPageState();
}

class _RegistrosPageState extends State<RegistrosPage> {
  final _repo = RepositorioMedicoes();
  late Future<List<RegistroMedicao>> _lista = _repo.listar();

  Future<void> _exportar() async {
    final arquivo = await _repo.exportarCsv();
    await Share.shareXFiles([XFile(arquivo.path, mimeType: 'text/csv')], subject: 'Medições do experimento');
  }

  @override
  Widget build(BuildContext context) {
    String mm(double? v) => v == null ? '—' : v.toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registros'),
        actions: [
          IconButton(tooltip: 'Exportar CSV', onPressed: _exportar, icon: const Icon(Icons.ios_share)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _lista = _repo.listar()),
        child: FutureBuilder<List<RegistroMedicao>>(
          future: _lista,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final itens = snap.data!;
            if (itens.isEmpty) {
              return ListView(children: const [
                Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhuma medição salva ainda.'))),
              ]);
            }
            return ListView.separated(
              itemCount: itens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = itens[i];
                final dif = (r.dpMarcadorMm != null && r.dpPupilometroMm != null)
                    ? ' (Δ ${(r.dpMarcadorMm! - r.dpPupilometroMm!).toStringAsFixed(1)})'
                    : '';
                return ListTile(
                  leading: Icon(
                    r.aprovada ? Icons.check_circle_outline : Icons.warning_amber,
                    color: r.aprovada ? Colors.green : Colors.orange,
                  ),
                  title: Text('${r.codigoParticipante} • rep. ${r.repeticao} • ${r.condicao}'),
                  subtitle: Text('App ${mm(r.dpMarcadorMm)} mm • Íris ${mm(r.dpIrisMm)} mm • '
                      'Pupilômetro ${mm(r.dpPupilometroMm)} mm$dif'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
