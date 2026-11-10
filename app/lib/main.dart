import 'package:flutter/material.dart';

import 'telas/inicio_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PupilometroApp());
}

class PupilometroApp extends StatelessWidget {
  const PupilometroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pupilômetro IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F5C99),
        useMaterial3: true,
      ),
      home: const InicioPage(),
    );
  }
}
