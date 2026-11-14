import 'package:astrum/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sem config do Firebase mostra a tela de configuracao',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AstrumApp()));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.textContaining('Configure o Firebase'), findsOneWidget);
    expect(find.textContaining('FIREBASE_API_KEY'), findsOneWidget);
  });
}
