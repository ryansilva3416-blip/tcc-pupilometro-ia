import 'package:flutter_test/flutter_test.dart';
import 'package:pupilometro/main.dart';

void main() {
  testWidgets('tela inicial abre com os botões principais', (tester) async {
    await tester.pumpWidget(const PupilometroApp());
    expect(find.text('Nova medição'), findsOneWidget);
    expect(find.text('Registros do experimento'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
  });
}
