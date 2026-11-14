// Fronteiras de imports (step8-feature-first.md, secao 5): camadas
// core < domain < data < providers < shared < telas < app, sem ciclo, sem
// import relativo em lib/ e sem Flutter em core/astro, core/firebase e
// features/*/domain. Le lib/ como texto. Arquivos fora das pastas novas
// (legado durante a migracao) tem camada indefinida e sao ignorados.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _import = RegExp(
    r"""^\s*(?:import|export)\s+['"]package:astrum/([^'"]+)['"]""");
final _relative =
    RegExp(r"""^\s*(?:import|export)\s+['"](?!dart:|package:)""");
final _flutter = RegExp(r"""import\s+['"](package:flutter/|dart:ui)""");

const _core = 0, _domain = 1, _data = 2, _providers = 3, _shared = 4;
const _screen = 5, _app = 6;

/// Camada do caminho relativo a lib/ (ex.: 'core/astro/zodiac.dart'), ou null
/// quando o arquivo esta numa pasta legada.
int? layerOf(String p) {
  if (p.startsWith('core/')) return _core;
  final m = RegExp(r'^features/(\w+)/(domain|data|presentation)/(.*)$')
      .firstMatch(p);
  if (m != null) {
    if (m[2] == 'domain') return _domain;
    if (m[2] == 'data') return _data;
    return RegExp(r'_providers?\.dart$').hasMatch(m[3]!)
        ? _providers
        : _screen;
  }
  if (p.startsWith('shared/')) return _shared;
  if (p.startsWith('app/') || p == 'main.dart') return _app;
  return null;
}

String? featureOf(String p) =>
    RegExp(r'^features/(\w+)/').firstMatch(p)?[1];

const _dataAllow = {'auth>profile', 'economy>profile'};
const _legacyDirs = [
  'providers',
  'screens',
  'services',
  'models',
  'data',
  'widgets',
  'theme',
  'config',
];

Map<String, File> _libFiles() {
  final out = <String, File>{};
  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    out[f.path.replaceAll(r'\', '/').substring('lib/'.length)] = f;
  }
  return out;
}

Map<String, List<String>> _graph(Map<String, File> files) => {
      for (final e in files.entries)
        e.key: [
          for (final l in e.value.readAsLinesSync())
            if (_import.firstMatch(l) != null) _import.firstMatch(l)![1]!,
        ],
    };

/// Violacoes das regras 1 e 3 (camada acima, tela/data de outra feature).
List<String> layerViolations(Map<String, List<String>> graph) {
  final bad = <String>[];
  for (final e in graph.entries) {
    final p = e.key;
    final lp = layerOf(p);
    for (final t in e.value) {
      final lt = layerOf(t);
      if (lp == _core && !t.startsWith('core/')) {
        bad.add('$p -> $t (core importa fora de core)');
      }
      if (lp == null || lt == null) continue;
      if (lt > lp) bad.add('$p -> $t (camada acima)');
      final a = featureOf(p), b = featureOf(t);
      if (a != null && b != null && a != b) {
        if (lt == _screen) bad.add('$p -> $t (tela de outra feature)');
        if (lt == _data && !(lp == _data && _dataAllow.contains('$a>$b'))) {
          bad.add('$p -> $t (data de outra feature)');
        }
      }
    }
  }
  return bad;
}

/// Regra 4: ciclos por DFS no grafo de imports.
List<String> cycles(Map<String, List<String>> graph) {
  final bad = <String>[];
  final state = <String, int>{};
  void dfs(String n, List<String> path) {
    if (state[n] == 2) return;
    if (state[n] == 1) {
      bad.add('ciclo: ${[...path, n].join(' > ')}');
      return;
    }
    state[n] = 1;
    for (final t in graph[n] ?? const <String>[]) {
      dfs(t, [...path, n]);
    }
    state[n] = 2;
  }

  for (final n in graph.keys) {
    dfs(n, []);
  }
  return bad;
}

void main() {
  test('detector reconhece camadas, features e imports', () {
    expect(layerOf('core/astro/zodiac.dart'), _core);
    expect(layerOf('features/auth/domain/sign_up_data.dart'), _domain);
    expect(layerOf('features/auth/data/auth_repository.dart'), _data);
    expect(layerOf('features/economy/presentation/economy_providers.dart'),
        _providers);
    expect(layerOf('features/auth/presentation/sign_up_provider.dart'),
        _providers);
    expect(layerOf('features/auth/presentation/login_screen.dart'), _screen);
    expect(layerOf('shared/cosmic_scaffold.dart'), _shared);
    expect(layerOf('app/router.dart'), _app);
    expect(layerOf('main.dart'), _app);
    expect(layerOf('services/auth_repository.dart'), isNull);
    expect(featureOf('features/oracle/data/chat_store.dart'), 'oracle');
    expect(featureOf('core/astro/zodiac.dart'), isNull);
    expect(_import.firstMatch("import 'package:astrum/core/a.dart';")![1],
        'core/a.dart');
    expect(_import.hasMatch("import 'package:flutter/material.dart';"),
        isFalse);
    expect(_relative.hasMatch("import '../data/tarot.dart';"), isTrue);
    expect(_relative.hasMatch("import 'zodiac.dart';"), isTrue);
    expect(_relative.hasMatch("import 'package:astrum/a.dart';"), isFalse);
    expect(_relative.hasMatch("import 'dart:io';"), isFalse);
    expect(_flutter.hasMatch("import 'package:flutter/foundation.dart';"),
        isTrue);
    expect(
        _flutter.hasMatch(
            "import 'package:flutter_riverpod/flutter_riverpod.dart';"),
        isFalse);
  });

  test('detector acusa violacoes sinteticas', () {
    expect(
        layerViolations({
          'core/a.dart': ['features/x/domain/b.dart'],
          'features/a/domain/d.dart': ['features/a/data/e.dart'],
          'features/a/data/r.dart': ['features/b/data/r.dart'],
          'features/a/presentation/s_screen.dart': [
            'features/b/presentation/t_screen.dart'
          ],
          'features/auth/data/r.dart': ['features/profile/data/r.dart'],
          'features/a/presentation/ok_screen.dart': [
            'features/b/domain/m.dart',
            'features/b/presentation/b_providers.dart',
            'shared/c.dart',
          ],
        }).length,
        5);
    expect(
        cycles({
          'a': ['b'],
          'b': ['c'],
          'c': ['a'],
        }),
        isNotEmpty);
    expect(
        cycles({
          'a': ['b', 'c'],
          'b': ['c'],
          'c': <String>[],
        }),
        isEmpty);
  });

  test('sanidade: a varredura encontra arquivos em cada raiz existente', () {
    final files = _libFiles();
    expect(files.length, greaterThan(10));
    for (final root in ['core/', 'features/', 'shared/', 'app/']) {
      if (Directory('lib/$root').existsSync()) {
        expect(files.keys.where((p) => p.startsWith(root)), isNotEmpty,
            reason: 'sem arquivos em lib/$root');
      }
    }
  });

  test('camadas: nenhum import de camada acima nem de data/tela de outra '
      'feature; core so importa core', () {
    expect(layerViolations(_graph(_libFiles())), isEmpty);
  });

  test('sem ciclo entre arquivos de lib/', () {
    expect(cycles(_graph(_libFiles())), isEmpty);
  });

  test('sem import relativo em lib/', () {
    final bad = <String>[];
    for (final e in _libFiles().entries) {
      for (final line in e.value.readAsLinesSync()) {
        if (_relative.hasMatch(line)) bad.add('${e.key}: $line');
      }
    }
    expect(bad, isEmpty);
  });

  test('core/astro, core/firebase e features/*/domain nao importam Flutter',
      () {
    final bad = <String>[];
    for (final e in _libFiles().entries) {
      final p = e.key;
      final pure = p.startsWith('core/astro/') ||
          p.startsWith('core/firebase/') ||
          RegExp(r'^features/\w+/domain/').hasMatch(p);
      if (!pure) continue;
      for (final line in e.value.readAsLinesSync()) {
        if (_flutter.hasMatch(line)) bad.add('$p: $line');
      }
    }
    expect(bad, isEmpty);
  });

  // Ativado no passo 13 da etapa 8.
  test('pastas legadas de lib/ nao existem mais', () {
    final left = [
      for (final d in _legacyDirs)
        if (Directory('lib/$d').existsSync()) 'lib/$d',
      if (File('lib/app_router.dart').existsSync()) 'lib/app_router.dart',
    ];
    expect(left, isEmpty);
  }, skip: 'ativado no passo 13');
}
