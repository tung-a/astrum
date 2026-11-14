import 'package:astrum/core/firebase/rules_contract.dart';

/// Compara o contrato Dart (`rules_contract.dart`) com o texto de
/// `firestore.rules`. Devolve uma mensagem por divergencia; lista vazia = em
/// sincronia. Padrao ausente nas regras tambem e divergencia (falha barulhenta
/// em vez de falso verde): ajuste teste e regras juntos.
List<String> findRulesDivergences(String rules) {
  final out = <String>[];

  void missing(String name) => out
      .add('padrão não encontrado: $name (ajuste o teste junto com as regras)');

  void intRule(String name, int dart, RegExp re) {
    final m = re.firstMatch(rules);
    if (m == null) return missing(name);
    final v = int.parse(m.group(1)!);
    if (v != dart) out.add('$name: Dart=$dart, regras=$v');
  }

  void strRule(String name, String dart, RegExp re) {
    final m = re.firstMatch(rules);
    if (m == null) return missing(name);
    final v = m.group(1)!;
    if (v != dart) out.add('$name: Dart=$dart, regras=$v');
  }

  List<String> quoted(String s) =>
      RegExp(r"'([^']*)'").allMatches(s).map((m) => m.group(1)!).toList();

  void listRule(String name, List<String> dart, RegExp re) {
    final m = re.firstMatch(rules);
    if (m == null) return missing(name);
    final v = quoted(m.group(1)!);
    if (v.join(',') != dart.join(',')) {
      out.add('$name: Dart=$dart, regras=$v');
    }
  }

  intRule('checkInReward', checkInReward,
      RegExp(r'newStar\(\) == oldStar\(\) \+ (\d+)'));
  intRule('initialStardust', initialStardust,
      RegExp(r"wallet == \{'stardust': (\d+)\}"));
  listRule('defaultInventory', defaultInventory,
      RegExp(r'nw\(\)\.inventory == \[([^\]]*)\]'));
  strRule('defaultSkinId', defaultSkinId,
      RegExp(r"equipTypeOk\([^,]+,\s*'skin',\s*'(\w+)'\)"));
  strRule('defaultBackgroundId', defaultBackgroundId,
      RegExp(r"equipTypeOk\([^,]+,\s*'background',\s*'(\w+)'\)"));
  strRule('zodiacAvatarPrefix', zodiacAvatarPrefix,
      RegExp(r"matches\('\^(\w+_)\[a-z\]\+\$'\)"));
  listRule(
      'catalogItemTypes', catalogItemTypes, RegExp(r'd\.type in \[([^\]]*)\]'));
  strRule('roleUser', roleUser,
      RegExp(r"request\.resource\.data\.role == '(\w+)'"));
  strRule('roleAdmin', roleAdmin,
      RegExp(r"function isAdmin\(\)[\s\S]*?== '(\w+)';"));
  strRule(
      'anonymousUserId',
      anonymousUserId,
      RegExp(r"request\.resource\.data\.userId == \(signedIn\(\) \? "
          r"request\.auth\.uid : '(\w+)'\)"));

  // Intencoes: mapa inteiro, nos dois sentidos.
  final labelOk = RegExp(r'function labelOk\([^)]*\)\s*\{([\s\S]*?)\n\s*\}')
      .firstMatch(rules);
  if (labelOk == null) {
    missing('intentionLabels');
  } else {
    final pairs = <String, String>{
      for (final m in RegExp(r"intentionId == '(\w+)' && label == '(\w+)'")
          .allMatches(labelOk.group(1)!))
        m.group(1)!: m.group(2)!,
    };
    if (pairs.isEmpty) missing('intentionLabels');
    for (final e in intentionLabels.entries) {
      if (!pairs.containsKey(e.key)) {
        out.add('intentionLabels: id ${e.key} ausente nas regras');
      } else if (pairs[e.key] != e.value) {
        out.add('intentionLabels: ${e.key} Dart=${e.value}, '
            'regras=${pairs[e.key]}');
      }
    }
    for (final id in pairs.keys) {
      if (!intentionLabels.containsKey(id)) {
        out.add('intentionLabels: id $id ausente no Dart');
      }
    }
  }

  // Limites de string/mapa em profileShapeOk.
  final optStr = <String, int>{
    for (final m in RegExp(r"optStr\('(\w+)',\s*(\d+)\)").allMatches(rules))
      m.group(1)!: int.parse(m.group(2)!),
  };
  final optMap = <String, int>{
    for (final m in RegExp(r"optMap\('(\w+)',\s*(\d+)\)").allMatches(rules))
      m.group(1)!: int.parse(m.group(2)!),
  };
  void field(String name, int dart, Map<String, int> from, String key) {
    final v = from[key];
    if (v == null) return missing('$name ($key)');
    if (v != dart) out.add('$name: Dart=$dart, regras=$v');
  }

  field('profileEmailMax', profileEmailMax, optStr, 'email');
  field('profileZodiacSignMax', profileZodiacSignMax, optStr, 'zodiacSign');
  field('profileBirthDateMax', profileBirthDateMax, optStr, 'birthDate');
  field('profileBirthTimeMax', profileBirthTimeMax, optStr, 'birthTime');
  field('profileBirthPlaceMax', profileBirthPlaceMax, optStr, 'birthPlace');
  field('profileAstralMapJsonMax', profileAstralMapJsonMax, optStr,
      'astralMapJson');
  for (final k in ['astrologyData', 'dailyHoroscope', 'dailyTarot']) {
    field('profileMapFieldMaxKeys', profileMapFieldMaxKeys, optMap, k);
  }

  intRule('profileNameMax', profileNameMax,
      RegExp(r'nw\(\)\.name\.size\(\) <= (\d+)'));
  intRule('inventoryMaxItems', inventoryMaxItems,
      RegExp(r'nw\(\)\.inventory\.size\(\) <= (\d+)'));
  intRule(
      'publicNameMax', publicNameMax, RegExp(r'd\.name\.size\(\) <= (\d+)'));
  intRule('publicAvatarMax', publicAvatarMax,
      RegExp(r'd\.avatar\.size\(\) <= (\d+)'));
  intRule('emailHashLength', emailHashLength, RegExp(r'\[0-9a-f\]\{(\d+)\}'));
  intRule('analyticsEventNameMax', analyticsEventNameMax,
      RegExp(r'request\.resource\.data\.eventName\.size\(\) <= (\d+)'));

  return out;
}
