import 'dart:io';

import 'package:astrum/services/meditation_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapeia id para caminho do asset', () {
    expect(soundForId('calm').assetPath, 'assets/sounds/calm.mp3');
    expect(soundForId('sleep').sourcePath, 'sounds/sleep.mp3');
  });

  test('id desconhecido cai no primeiro som', () {
    expect(soundForId('x'), meditationSounds.first);
  });

  test('quatro sons, com arquivo existente e pasta declarada no pubspec', () {
    expect(meditationSounds.map((s) => s.id).toSet(),
        {'calm', 'energy', 'focus', 'sleep'});
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/sounds/'));
    for (final s in meditationSounds) {
      expect(File(s.assetPath).existsSync(), isTrue, reason: s.assetPath);
    }
  });
}
