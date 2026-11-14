// Fronteiras de imports da etapa 7 (step7-data-models.md, secao 6): lib/core
// nao importa camadas de cima (models, data, services, theme, providers,
// screens, widgets) nem usa import relativo para subir de pasta, e lib/core e
// lib/data nao importam Flutter. Evita ciclo novo sem depender de grep manual.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _upperLayer = RegExp(
    r"""import\s+['"](package:astrum/(models|data|services|theme|providers|screens|widgets)/|\.\./)""");
final _flutter = RegExp(r"""import\s+['"](package:flutter/|dart:ui)""");

List<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  test('regex de fronteira reconhece imports proibidos e permitidos', () {
    expect(_upperLayer.hasMatch("import 'package:astrum/models/app_user.dart';"),
        isTrue);
    expect(_upperLayer.hasMatch("import '../data/tarot.dart';"), isTrue);
    expect(_upperLayer.hasMatch("import 'zodiac.dart';"), isFalse);
    expect(
        _upperLayer
            .hasMatch("import 'package:astrum/core/astro/zodiac.dart';"),
        isFalse);
    expect(_flutter.hasMatch("import 'package:flutter/foundation.dart';"),
        isTrue);
    expect(
        _flutter.hasMatch("import 'package:flutter_riverpod/flutter_riverpod.dart';"),
        isFalse);
  });

  test('lib/core nao importa camadas de cima', () {
    final files = _dartFiles('lib/core');
    expect(files.length, greaterThan(3), reason: 'a varredura nao achou arquivos');
    final bad = <String>[];
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        if (_upperLayer.hasMatch(line)) bad.add('${f.path}: $line');
      }
    }
    expect(bad, isEmpty);
  });

  test('lib/core e lib/data nao importam Flutter', () {
    final bad = <String>[];
    for (final dir in ['lib/core', 'lib/data']) {
      for (final f in _dartFiles(dir)) {
        for (final line in f.readAsLinesSync()) {
          if (_flutter.hasMatch(line)) bad.add('${f.path}: $line');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
