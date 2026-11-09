import 'package:astrum/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks for Firebase configuration before opening the app',
      (tester) async {
    await tester.pumpWidget(const AstrumApp());

    expect(find.textContaining('Configure o Firebase'), findsOneWidget);
    expect(find.textContaining('FIREBASE_API_KEY'), findsOneWidget);
  });
}
