import 'package:flutter/material.dart';

import 'captura_page.dart';
import 'configuracoes_page.dart';
import 'registros_page.dart';

class InicioPage extends StatelessWidget {
  const InicioPage({super.key});

  @override
  Widget build(BuildContext context) {
    void abrir(Widget pagina) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));

    return Scaffold(
      appBar: AppBar(title: const Text('Pupilômetro IA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Protótipo de pesquisa — medição da distância interpupilar por fotografia calibrada.',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => abrir(const CapturaPage()),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Padding(padding: EdgeInsets.all(14), child: Text('Nova medição')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => abrir(const RegistrosPage()),
            icon: const Icon(Icons.list_alt),
            label: const Padding(padding: EdgeInsets.all(14), child: Text('Registros do experimento')),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => abrir(const ConfiguracoesPage()),
            icon: const Icon(Icons.tune),
            label: const Padding(padding: EdgeInsets.all(14), child: Text('Configurações')),
          ),
          const SizedBox(height: 32),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Como capturar:\n'
                '1. Cole o marcador impresso na testa, centralizado e reto.\n'
                '2. Participante olhando para a câmera, cabeça reta.\n'
                '3. Celular na altura dos olhos, a cerca de 40 cm.\n'
                '4. Boa iluminação, sem reflexo forte no marcador.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
