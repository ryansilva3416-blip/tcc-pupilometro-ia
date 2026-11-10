import 'package:flutter/material.dart';

import '../configuracao/preferencias.dart';
import '../medicao/calculo_dp.dart';
import '../medicao/canal_visao.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _tamanho = TextEditingController();
  final _id = TextEditingController();
  ModoCentro _modo = ModoCentro.contorno;
  Map<String, String> _versoes = {};
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final cfg = await Preferencias.carregarCalculo();
    Map<String, String> v = {};
    try {
      v = await CanalVisao.versoes();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _tamanho.text = cfg.tamanhoMarcadorMm.toString();
      _id.text = cfg.idMarcador.toString();
      _modo = cfg.modoCentro;
      _versoes = v;
      _carregado = true;
    });
  }

  Future<void> _salvar() async {
    final t = double.tryParse(_tamanho.text.replaceAll(',', '.'));
    final id = int.tryParse(_id.text);
    if (t == null || t <= 0 || id == null || id < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valores inválidos.')));
      return;
    }
    await Preferencias.salvar(tamanhoMarcadorMm: t, idMarcador: id, modoCentro: _modo);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: !_carregado
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                controller: _tamanho,
                decoration: const InputDecoration(
                  labelText: 'Lado do marcador impresso (mm)',
                  helperText: 'Meça o quadrado preto externo com uma régua após imprimir.',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'Código (id) do marcador', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('Centro da pupila'),
              RadioListTile<ModoCentro>(
                value: ModoCentro.contorno,
                groupValue: _modo,
                onChanged: (v) => setState(() => _modo = v!),
                title: const Text('Média do contorno da íris'),
              ),
              RadioListTile<ModoCentro>(
                value: ModoCentro.ponto,
                groupValue: _modo,
                onChanged: (v) => setState(() => _modo = v!),
                title: const Text('Ponto central do modelo'),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _salvar, child: const Text('Salvar')),
              const SizedBox(height: 32),
              Text('Algoritmo $versaoAlgoritmo', style: Theme.of(context).textTheme.bodySmall),
              for (final e in _versoes.entries)
                Text('${e.key}: ${e.value}', style: Theme.of(context).textTheme.bodySmall),
            ]),
    );
  }
}
