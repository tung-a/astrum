// Garante que `lib/core/firebase/rules_contract.dart` continua igual ao que
// `firestore.rules` valida. `flutter test` roda com a raiz do pacote como
// diretorio atual (tambem no CI), entao `firestore.rules` e lido de la.
import 'dart:io';

import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/economy/domain/catalog_seed.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/profile/presentation/account_screen.dart';
import 'package:astrum/shared/cosmetics_style.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rules_contract_check.dart';

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  test('as regras reais nao divergem do contrato', () {
    expect(findRulesDivergences(rules), isEmpty);
  });

  group('detecta divergencia (mutacao em copia do texto)', () {
    // (nome da constante, trecho original, trecho alterado)
    final mutations = <(String, String, String)>[
      ('checkInReward', '+ 25', '+ 26'),
      ('initialStardust', "'stardust': 500", "'stardust': 501"),
      (
        'defaultInventory',
        "== ['skin_classic', 'bg_void']",
        "== ['skin_classic', 'bg_x']"
      ),
      ('defaultSkinId', "'skin', 'skin_classic'", "'skin', 'skin_x'"),
      (
        'defaultBackgroundId',
        "'background', 'bg_void'",
        "'background', 'bg_x'"
      ),
      ('zodiacAvatarPrefix', "^pfp_zodiac_[a-z]+\$", "^pfp_sign_[a-z]+\$"),
      ('intentionLabels', "label == 'Luz'", "label == 'Luzz'"),
      (
        'intentionLabels',
        "|| (intentionId == 'clareza' && label == 'Clareza')",
        ''
      ),
      ('intentionLabels', "intentionId == 'luz'", "intentionId == 'luzx'"),
      (
        'catalogItemTypes',
        "d.type in ['skin', 'background', 'profilePicture']",
        "d.type in ['skin', 'profilePicture']"
      ),
      ('roleUser', "data.role == 'user'", "data.role == 'usr'"),
      ('roleAdmin', "== 'admin';", "== 'root';"),
      ('anonymousUserId', ": 'anonymous')", ": 'anon')"),
      (
        'analyticsEventNameMax',
        'eventName.size() <= 100',
        'eventName.size() <= 101'
      ),
      ('profileNameMax', 'nw().name.size() <= 100', 'nw().name.size() <= 101'),
      ('profileEmailMax', "optStr('email', 254)", "optStr('email', 255)"),
      (
        'profileZodiacSignMax',
        "optStr('zodiacSign', 30)",
        "optStr('zodiacSign', 31)"
      ),
      (
        'profileBirthDateMax',
        "optStr('birthDate', 20)",
        "optStr('birthDate', 21)"
      ),
      (
        'profileBirthTimeMax',
        "optStr('birthTime', 10)",
        "optStr('birthTime', 11)"
      ),
      (
        'profileBirthPlaceMax',
        "optStr('birthPlace', 200)",
        "optStr('birthPlace', 201)"
      ),
      (
        'profileAstralMapJsonMax',
        "optStr('astralMapJson', 20000)",
        "optStr('astralMapJson', 20001)"
      ),
      (
        'profileMapFieldMaxKeys',
        "optMap('dailyTarot', 5)",
        "optMap('dailyTarot', 6)"
      ),
      (
        'inventoryMaxItems',
        'nw().inventory.size() <= 500',
        'nw().inventory.size() <= 501'
      ),
      ('publicNameMax', 'd.name.size() <= 100', 'd.name.size() <= 99'),
      ('publicAvatarMax', 'd.avatar.size() <= 100', 'd.avatar.size() <= 101'),
      ('emailHashLength', '{64}', '{63}'),
      ('chatTitleMax', 'd.title.size() <= 80', 'd.title.size() <= 81'),
      ('chatMessagesMax', 'd.messageCount <= 500', 'd.messageCount <= 501'),
      ('chatTextMax', 'data.text.size() <= 10000', 'data.text.size() <= 10001'),
      ('chatSchemaVersion', 'd.schemaVersion == 1', 'd.schemaVersion == 2'),
      (
        'friendshipPending',
        "request.resource.data.status == 'pending'",
        "request.resource.data.status == 'pendente'"
      ),
      (
        'friendshipStatus',
        "request.resource.data.status == 'accepted'",
        "request.resource.data.status == 'aceita'"
      ),
      (
        'friendshipStatus',
        "request.resource.data.status == 'declined'",
        "request.resource.data.status == 'recusada'"
      ),
      (
        'friendshipNameMax',
        'requesterName.size() <= 100',
        'requesterName.size() <= 99'
      ),
      (
        'friendshipIdSeparator',
        "pid.split('_').size() == 2",
        "pid.split('-').size() == 2"
      ),
      (
        'friendshipIdSeparator (pairId)',
        "a + '_' + b : b + '_' + a",
        "a + '-' + b : b + '-' + a"
      ),
    ];

    for (final (name, from, to) in mutations) {
      test('$name: "$from" -> "$to"', () {
        expect(rules, contains(from),
            reason: 'trecho de origem sumiu das regras; ajuste a mutacao');
        final mutated = rules.replaceFirst(from, to);
        final found = findRulesDivergences(mutated);
        expect(found.where((m) => m.contains(name)), isNotEmpty,
            reason: 'divergencias: $found');
      });
    }
  });

  test('padrao ausente falha com mensagem clara', () {
    final mutated = rules.replaceAll('function labelOk', 'function labelXx');
    final found = findRulesDivergences(mutated);
    expect(
        found, contains(startsWith('padrão não encontrado: intentionLabels')));
  });

  test('padrao ausente de um limite tambem falha', () {
    final mutated = rules.replaceFirst("optStr('birthPlace', 200)", 'true');
    expect(findRulesDivergences(mutated),
        contains(startsWith('padrão não encontrado: profileBirthPlaceMax')));
  });

  group('sanidade do contrato em Dart', () {
    test('inventario padrao e skin + fundo padrao, nessa ordem', () {
      expect(defaultInventory, [defaultSkinId, defaultBackgroundId]);
    });

    test('tipos do catalogo batem com catalogTypeName', () {
      expect(ItemType.values.map(catalogTypeName).toSet(),
          catalogItemTypes.toSet());
    });

    test('SignUpLimits usa as constantes do contrato', () {
      expect(SignUpLimits.name, profileNameMax);
      expect(SignUpLimits.email, profileEmailMax);
      expect(SignUpLimits.birthDate, profileBirthDateMax);
      expect(SignUpLimits.birthTime, profileBirthTimeMax);
      expect(SignUpLimits.birthPlace, profileBirthPlaceMax);
    });

    test('fallbacks de skin e fundo nunca ficam nulos', () {
      expect(cosmeticStyles, contains(defaultSkinId));
      expect(cosmeticBackgrounds, contains(defaultBackgroundId));
    });

    test('catalogo seed tem os dois itens padrao com preco 0', () {
      for (final id in defaultInventory) {
        expect(fullShopCatalog.singleWhere((i) => i.id == id).price, 0);
      }
    });
  });

  test('toda intencao do contrato tem icone e cor na UI', () {
    expect(intentionStyles.keys.toSet(), intentionLabels.keys.toSet());
    expect(intentions.map((i) => i.id).toList(), intentionLabels.keys.toList());
    expect(intentions.map((i) => i.label).toList(),
        intentionLabels.values.toList());
  });
}
