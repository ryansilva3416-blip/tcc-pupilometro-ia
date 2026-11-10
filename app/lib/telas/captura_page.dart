import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'resultado_page.dart';

/// Captura com guia na tela: oval para o rosto e retângulo na testa para o marcador.
///
/// A verificação de qualidade é feita depois da foto (na análise). Um guia ao vivo,
/// com detecção em tempo real, pode ser adicionado depois via EventChannel.
class CapturaPage extends StatefulWidget {
  const CapturaPage({super.key});

  @override
  State<CapturaPage> createState() => _CapturaPageState();
}

class _CapturaPageState extends State<CapturaPage> with WidgetsBindingObserver {
  CameraController? _controle;
  List<CameraDescription> _cameras = [];
  int _indice = 0;
  String? _erro;
  bool _capturando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _erro = 'Nenhuma câmera encontrada.');
        return;
      }
      // Câmera traseira por padrão: melhor resolução, e o técnico opera o celular.
      final traseira = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _indice = traseira >= 0 ? traseira : 0;
      await _abrir(_cameras[_indice]);
    } on CameraException catch (e) {
      setState(() => _erro = 'Erro na câmera: ${e.description ?? e.code}');
    }
  }

  Future<void> _abrir(CameraDescription camera) async {
    final anterior = _controle;
    _controle = null;
    await anterior?.dispose();
    final c = CameraController(camera, ResolutionPreset.max, enableAudio: false);
    await c.initialize();
    await c.lockCaptureOrientation();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _controle = c);
  }

  Future<void> _trocarCamera() async {
    if (_cameras.length < 2) return;
    _indice = (_indice + 1) % _cameras.length;
    await _abrir(_cameras[_indice]);
  }

  Future<void> _capturar() async {
    final c = _controle;
    if (c == null || !c.value.isInitialized || _capturando) return;
    setState(() => _capturando = true);
    try {
      final foto = await c.takePicture();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultadoPage(caminhoFoto: foto.path)),
      );
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao capturar: ${e.code}')));
      }
    } finally {
      if (mounted) setState(() => _capturando = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controle;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controle = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      _abrir(_cameras[_indice]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controle;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Captura'),
        actions: [
          if (_cameras.length > 1)
            IconButton(onPressed: _trocarCamera, icon: const Icon(Icons.cameraswitch_outlined)),
        ],
      ),
      body: _erro != null
          ? Center(child: Text(_erro!, style: const TextStyle(color: Colors.white)))
          : (c == null || !c.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          // previewSize vem em paisagem; a tela está em retrato.
                          aspectRatio: 1 / c.value.aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(c),
                              const CustomPaint(painter: _GuiaPainter()),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Rosto dentro do oval, marcador no retângulo, olhar para a câmera.',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FloatingActionButton.large(
                            onPressed: _capturando ? null : _capturar,
                            child: _capturando
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.camera_alt),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _GuiaPainter extends CustomPainter {
  const _GuiaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final traco = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.52),
      width: size.width * 0.62,
      height: size.height * 0.58,
    );
    canvas.drawOval(oval, traco);

    final lado = size.width * 0.18;
    final marcador = Rect.fromCenter(
      center: Offset(size.width / 2, oval.top + oval.height * 0.16),
      width: lado,
      height: lado,
    );
    canvas.drawRect(marcador, traco..color = Colors.amber);

    // Linha dos olhos
    final yOlhos = oval.top + oval.height * 0.42;
    canvas.drawLine(
      Offset(oval.left + 10, yOlhos),
      Offset(oval.right - 10, yOlhos),
      Paint()
        ..color = Colors.white38
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
