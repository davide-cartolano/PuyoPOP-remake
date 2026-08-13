import 'package:flutter_test/flutter_test.dart';

import 'package:puyopop_feveer/main.dart';

void main() {
  testWidgets('il menu principale mostra titolo e pulsanti di gioco', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PUYO POP'), findsOneWidget);
    expect(find.text('FEVER'), findsOneWidget);
    expect(find.text('Gioca da solo'), findsOneWidget);
    expect(find.text('Gioca contro CPU'), findsOneWidget);
  });

  testWidgets('premere "Gioca contro CPU" apre la scelta della difficoltà', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Gioca contro CPU'));
    await tester.pumpAndSettle();

    expect(find.text('Difficoltà CPU'), findsOneWidget);
    expect(find.text('Facile'), findsOneWidget);
    expect(find.text('Normale'), findsOneWidget);
    expect(find.text('Difficile'), findsOneWidget);
  });
}
