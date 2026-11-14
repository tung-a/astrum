// Fronteiras de imports (step8-feature-first.md, secao 5): camadas
// core < domain < data < providers < shared < telas < app, sem ciclo, sem
// import relativo em lib/, sem Flutter nas camadas puras (e no fecho
// transitivo delas) e sem widgets em *_provider(s).dart e *_controller.dart.
// Le lib/ como texto.
// Todo arquivo de lib/ precisa ter camada definida (lista de permitidas).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _import =
    RegExp(r"""^\s*(?:import|export)\s+['"]package:astrum/([^'"]+)['"]""");
final _relative = RegExp(r"""^\s*(?:import|export)\s+['"](?!dart:|package:)""");
final _flutter =
    RegExp(r"""^\s*(?:import|export)\s+['"](package:flutter/|dart:ui)""");
final _widgets = RegExp(
    r"""^\s*(?:import|export)\s+['"]package:flutter/(material|widgets)\.dart""");

final _providerFile = RegExp(r'_(providers?|controller)\.dart$');

const _core = 0, _domain = 1, _data = 2, _providers = 3, _shared = 4;
const _screen = 5, _app = 6;

/// Camada do caminho relativo a lib/ (ex.: 'core/astro/zodiac.dart'), ou null
/// quando o arquivo esta fora das pastas permitidas. A ordem importa: core/ e
/// features/ sao testados antes de shared/ e app/; dentro de presentation/, o
/// sufixo _provider(s).dart ou _controller.dart (etapa 9) classifica como
/// providers (camada 3), o resto e tela.
int? layerOf(String p) {
  if (p.startsWith('core/')) return _core;
  final m =
      RegExp(r'^features/(\w+)/(domain|data|presentation)/(.*)$').firstMatch(p);
  if (m != null) {
    if (m[2] == 'domain') return _domain;
    if (m[2] == 'data') return _data;
    return _providerFile.hasMatch(m[3]!) ? _providers : _screen;
  }
  if (p.startsWith('shared/')) return _shared;
  if (p.startsWith('app/') || p == 'main.dart') return _app;
  return null;
}

String? featureOf(String p) => RegExp(r'^features/(\w+)/').firstMatch(p)?[1];

const _dataAllow = {'auth>profile', 'economy>profile'};

/// Arquivos que dependem de Flutter de forma legitima e ficam fora da
/// verificacao de pureza (nem sao marcados, nem atravessados).
/// analytics_service usa package:flutter/foundation.dart (debugPrint/kDebugMode).
const _flutterExceptions = {'core/analytics/analytics_service.dart'};

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

Map<String, List<String>> _libLines() => {
      for (final e in _libFiles().entries) e.key: e.value.readAsLinesSync(),
    };

/// Regra 1: arquivos de lib/ sem camada definida (fora das pastas permitidas).
List<String> undefinedLayer(Iterable<String> paths) => [
      for (final p in paths)
        if (layerOf(p) == null) p
    ];

bool _isStrict(String p) =>
    p.startsWith('core/astro/') ||
    p.startsWith('core/firebase/') ||
    RegExp(r'^features/\w+/domain/').hasMatch(p);

bool _isFlutterFree(String p) =>
    _isStrict(p) ||
    p == 'features/admin/data/crystal_seed.dart' ||
    p.startsWith('core/storage/') ||
    p == 'core/analytics/analytics_providers.dart';

/// Regra 2: raizes puras nao importam/exportam Flutter nem direta nem
/// transitivamente (fecho pelos imports de package:astrum). As raizes
/// estritas (domain, core/astro, core/firebase) tambem so podem importar
/// dentro delas mesmas.
List<String> purityViolations(Map<String, List<String>> lines) {
  final bad = <String>[];
  final seen = <String>{};
  void visit(String p, String root) {
    if (!seen.add('$root|$p') || _flutterExceptions.contains(p)) return;
    for (final l in lines[p] ?? const <String>[]) {
      if (_flutter.hasMatch(l)) bad.add('$root -> $p: $l');
      final t = _import.firstMatch(l)?[1];
      if (t == null) continue;
      if (_isStrict(root) && !_isStrict(t)) {
        bad.add(
            '$root: $p importa $t (fora de domain/core/astro/core/firebase)');
      }
      visit(t, root);
    }
  }

  for (final p in lines.keys.where(_isFlutterFree)) {
    visit(p, p);
  }
  return bad;
}

/// Regra 3: *_provider(s).dart e *_controller.dart de features nao importam
/// material/widgets (mantem BuildContext, ScaffoldMessenger e controllers de
/// texto fora da logica).
List<String> providerWidgetViolations(Map<String, List<String>> lines) => [
      for (final e in lines.entries)
        if (e.key.startsWith('features/') && _providerFile.hasMatch(e.key))
          for (final l in e.value)
            if (_widgets.hasMatch(l)) '${e.key}: $l',
    ];

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
    expect(layerOf('features/cosmos/presentation/cosmos_controller.dart'),
        _providers);
    expect(layerOf('features/oracle/presentation/chat_controller.dart'),
        _providers);
    expect(layerOf('features/cosmos/presentation/cosmos_controller_x.dart'),
        _screen);
    expect(layerOf('features/cosmos/presentation/my_controller.dart.bak'),
        _screen);
    expect(layerOf('shared/cosmic_scaffold.dart'), _shared);
    expect(layerOf('app/router.dart'), _app);
    expect(layerOf('main.dart'), _app);
    expect(layerOf('services/auth_repository.dart'), isNull);
    expect(featureOf('features/oracle/data/chat_store.dart'), 'oracle');
    expect(featureOf('core/astro/zodiac.dart'), isNull);
    expect(_import.firstMatch("import 'package:astrum/core/a.dart';")![1],
        'core/a.dart');
    expect(
        _import.hasMatch("import 'package:flutter/material.dart';"), isFalse);
    expect(_relative.hasMatch("import '../data/tarot.dart';"), isTrue);
    expect(_relative.hasMatch("import 'zodiac.dart';"), isTrue);
    expect(_relative.hasMatch("import 'package:astrum/a.dart';"), isFalse);
    expect(_relative.hasMatch("import 'dart:io';"), isFalse);
    expect(
        _flutter.hasMatch("import 'package:flutter/foundation.dart';"), isTrue);
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

  test(
      'camadas: nenhum import de camada acima nem de data/tela de outra '
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

  test('toda pasta de lib/ tem camada definida (lista de permitidas)', () {
    expect(undefinedLayer(_libFiles().keys), isEmpty);
  });

  test('camadas puras (e fecho transitivo) nao dependem de Flutter', () {
    expect(purityViolations(_libLines()), isEmpty);
  });

  test('providers e controllers de features nao importam material/widgets', () {
    expect(providerWidgetViolations(_libLines()), isEmpty);
  });

  test('regras novas detectam violacoes em memoria', () {
    expect(
        undefinedLayer(['core/a.dart', 'services/x.dart', 'features/a/x.dart']),
        ['services/x.dart', 'features/a/x.dart']);
    // import direto, export e fecho transitivo
    expect(
        purityViolations({
          'core/astro/a.dart': ["import 'package:flutter/material.dart';"],
        }),
        isNotEmpty);
    expect(
        purityViolations({
          'features/a/domain/a.dart': [
            "export 'package:flutter/widgets.dart';"
          ],
        }),
        isNotEmpty);
    expect(
        purityViolations({
          'features/a/domain/a.dart': [
            "import 'package:astrum/shared/s.dart';"
          ],
          'shared/s.dart': ["import 'package:flutter/material.dart';"],
        }),
        isNotEmpty);
    expect(
        purityViolations({
          'core/storage/p.dart': ["import 'package:astrum/shared/s.dart';"],
          'shared/s.dart': ["import 'package:flutter/material.dart';"],
        }),
        isNotEmpty);
    expect(
        purityViolations({
          'core/analytics/analytics_service.dart': [
            "import 'package:flutter/foundation.dart';"
          ],
          'core/analytics/analytics_providers.dart': [
            "import 'package:astrum/core/analytics/analytics_service.dart';"
          ],
          'features/a/domain/a.dart': [
            "import 'package:astrum/core/astro/z.dart';"
          ],
          'core/astro/z.dart': <String>[],
        }),
        isEmpty);
    expect(
        providerWidgetViolations({
          'features/a/presentation/a_providers.dart': [
            "import 'package:flutter/material.dart';"
          ],
        }),
        isNotEmpty);
    expect(
        providerWidgetViolations({
          'features/a/presentation/a_provider.dart': [
            "export 'package:flutter/widgets.dart';"
          ],
          'features/a/presentation/a_screen.dart': [
            "import 'package:flutter/material.dart';"
          ],
        }).length,
        1);
  });

  test('controllers: camada 3, importam providers de outra feature, nao tela',
      () {
    expect(
        layerViolations({
          'features/a/presentation/a_controller.dart': [
            'features/b/presentation/b_providers.dart',
            'features/b/domain/m.dart',
            'features/a/data/r.dart',
            'shared/s.dart',
          ],
        }).length,
        1); // shared/ e camada 4, acima de 3
    expect(
        layerViolations({
          'features/a/presentation/a_controller.dart': [
            'features/b/presentation/b_controller.dart',
            'features/b/data/r.dart',
          ],
          'features/a/presentation/a_screen.dart': [
            'features/a/presentation/a_controller.dart',
          ],
        }).length,
        1); // data de outra feature
    expect(
        layerViolations({
          'features/a/presentation/a_controller.dart': [
            'features/a/presentation/a_screen.dart',
          ],
        }).length,
        1); // tela acima
    expect(
        providerWidgetViolations({
          'features/a/presentation/a_controller.dart': [
            "import 'package:flutter/material.dart';"
          ],
        }),
        isNotEmpty);
    expect(
        providerWidgetViolations({
          'features/a/presentation/a_controller.dart': [
            "import 'package:flutter_riverpod/flutter_riverpod.dart';"
          ],
        }),
        isEmpty);
  });
}
