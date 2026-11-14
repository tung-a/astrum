# Etapa 5: escritas tipadas no perfil e no equipar

Status: implementada (passos 1 a 6; passo 7/opção B NÃO implementado por decisão do usuário, registrada como pendente em `docs/plans/reestruturacao-etapas-1-a-3.md`). `npm test` em `test_rules/` não executado (porta 8080 ocupada por outro processo). Checklist manual do passo 6 pendente (exige app/emulador). Desvios: `saveAstralMap` é `async` (para o `StateError` de lista vazia chegar como erro do Future); o teste de M3 grava `preferences.publicProfile=false` direto no doc e chama `equip(profilePicture)`. Base: `docs/architecture/restructuring.md` (etapa 5), `docs/architecture/step4-repositories.md`, `docs/plans/reestruturacao-etapas-1-a-3.md` ("Itens abertos da etapa 4").

## 0. Restrições

- Spark, sem Cloud Functions. `firestore.rules` e `test_rules/` não mudam (`git diff` vazio em cada passo).
- Comportamento observável idêntico: mesmas chaves gravadas no Firestore (as regras validam), mesma ordem (escrita em `users/{uid}`, depois sync de `publicProfiles`), mesmas exceções. A única exceção possível é a opção B da seção 5, que só entra com decisão do usuário.
- Sem feature-first (etapa 8): arquivos ficam em `lib/services/`, `lib/models/`, `lib/data/`.
- `flutter analyze` e `flutter test` verdes ao fim de cada passo.
- Fora do escopo: `createProfile` (continua em `ProfileRepository` até a etapa 6; é o único ponto que grava `role`/`wallet`/`inventory`, e só na criação), M1, M3 (ver seção 7).

## 1. Usos reais (grep)

Telas: `account_screen.dart` (2 prefs), `astral_screen.dart` (mapa + signo), `cosmos_screen.dart` (horóscopo, tarô), `inventory_screen.dart` (equipar), `shop_screen.dart` (equipar e comprar+equipar). Nenhum uso grava `name`, `email` ou `preferences.publicProfile`. `PublicProfileSync.touches` só reage a `name`, `email`, `equipped`, `equipped.profilePicture`; na prática, só `equipped.profilePicture` dispara hoje. `equipped.skin`, `equipped.background`, `zodiacSign` e preferências não disparam.

## 2. API final

### 2.1 `EquipSlot` (novo, `lib/models/equip_slot.dart`)

```dart
enum EquipSlot {
  skin, background, profilePicture;

  /// Só o avatar entra em publicProfiles (campo `avatar`).
  bool get touchesPublicProfile => this == EquipSlot.profilePicture;
}
```

Caminho do Firestore fica fora do enum e fora das telas, em `lib/services/equip_slot_field.dart` (extensão pública apenas dentro de `services/`, usada por Profile e Economy):

```dart
extension EquipSlotField on EquipSlot {
  String get fieldPath => switch (this) {
        EquipSlot.skin => 'equipped.skin',
        EquipSlot.background => 'equipped.background',
        EquipSlot.profilePicture => 'equipped.profilePicture',
      };
}
```

Ponte com a UI, em `lib/data/cosmetics.dart` (junto de `ItemType`; elimina os dois `switch` duplicados de shop e inventory):

```dart
extension ItemTypeSlot on ItemType {
  EquipSlot get slot => switch (this) {
        ItemType.cardSkin => EquipSlot.skin,
        ItemType.background => EquipSlot.background,
        ItemType.profilePicture => EquipSlot.profilePicture,
      };
}
```

### 2.2 `ProfileRepository` (substitui `updateFields`)

```dart
Stream<AppUser?> watchProfile(User user);          // inalterado
Future<void> createProfile({...});                  // inalterado (etapa 6)

Future<void> setNotificationsEnabled(String uid, bool enabled); // 'preferences.notifications'
Future<void> setShowSign(String uid, bool enabled);             // 'preferences.showSign'
Future<void> equip(String uid, EquipSlot slot, String itemId);  // slot.fieldPath; sync se slot.touchesPublicProfile
Future<void> saveAstralMap(String uid, List<PlanetPosition> chart); // 'astralMapJson' + 'zodiacSign' (chart.first.sign)
Future<void> saveDailyHoroscope(String uid, {required String date, required String content});
Future<void> saveDailyTarot(String uid, {required String date, required String card, required String meaning});
```

Decisões:

- `equip` único com `EquipSlot` em vez de `equipSkin/equipBackground/equipAvatar`: um método, um `switch` no enum, e o chamador já tem o slot via `item.type.slot`. Se o usuário preferir três métodos, são wrappers triviais.
- Preferências: dois métodos nomeados, sem `setPreference(enum, bool)`, porque só dois são usados e as regras aceitam um terceiro (`publicProfile`) cujo comportamento é o M3 (decisão pendente). Não criar `setPublicProfile` agora.
- `zodiacSign` não ganha `setZodiacSign`: nunca é gravado sozinho; `saveAstralMap` grava os dois na mesma `update`, como hoje. O `jsonEncode` sai da tela e vai para `AppUser.encodeAstralMap(List<PlanetPosition>)` (par do `parseAstralMap` existente; `jsonEncode(list.map((e) => e.toJson()).toList())`, idêntico ao atual). Lança `StateError` em lista vazia (hoje `computed.first` lançaria `StateError` na tela; mesma classe de erro).
- Não existem `setName`/`setEmail` (sem chamador). Quando existirem, nascem com sync de `publicProfiles` e entram nesta lista.
- Internamente um único `_update(uid, Map)` privado. Nenhum método público recebe `Map` nem `String` de campo, logo `wallet`, `inventory`, `dailyCheckIn` e `role` são inalcançáveis por `ProfileRepository` por construção. `_blockedPrefixes`, o `ArgumentError` e `// etapa 5: remover` somem.

### 2.3 Sync por tipo de escrita (sem string)

`PublicProfileSync.touches(Iterable<String>)` é removido. Cada método de `ProfileRepository` decide explicitamente:

```dart
Future<void> equip(String uid, EquipSlot slot, String itemId) async {
  await _userDoc(uid).update({slot.fieldPath: itemId});
  if (slot.touchesPublicProfile) await _sync.syncFromUser(uid);
}
```

Os demais métodos não chamam `_sync` (igual a hoje). Teste de caracterização garante isso (seção 6).

### 2.4 `EconomyRepository`

```dart
Future<void> purchaseItem({
  required String uid,
  required String itemId,
  EquipSlot? equipSlot,      // substitui String? equipField
});
```

Corpo da transação: `if (equipSlot != null) equipSlot.fieldPath: itemId` (mesma chave `'equipped.skin'` etc.); o `.then` vira `if (equipSlot?.touchesPublicProfile ?? false) await _sync.syncFromUser(uid)`. `dailyCheckIn` inalterado. A interface deixa de expor caminho de campo (dívida registrada na etapa 4, seção 2).

## 3. Mapa das chamadas atuais para as novas

| Local atual | Hoje | Depois |
|---|---|---|
| `account_screen.dart` ~133 | `updateFields(uid, {'preferences.notifications': enabled})` | `setNotificationsEnabled(profile.uid, enabled)` |
| `account_screen.dart` ~142 | `updateFields(uid, {'preferences.showSign': enabled})` | `setShowSign(profile.uid, enabled)` |
| `astral_screen.dart` ~79 | `updateFields(uid, {'astralMapJson': jsonEncode(...), 'zodiacSign': computed.first.sign})` | `saveAstralMap(profile.uid, computed)` (remove `import 'dart:convert'` se ficar sem uso) |
| `cosmos_screen.dart` 41 | `updateFields(uid, {'dailyHoroscope': {'date': _today, 'content': text}})` | `saveDailyHoroscope(profile.uid, date: _today, content: text)` |
| `cosmos_screen.dart` 62 | `updateFields(uid, {'dailyTarot': {'date','card','meaning'}})` | `saveDailyTarot(profile.uid, date: _today, card: card.name, meaning: meaning)` |
| `inventory_screen.dart` 84-93 | `switch` para `field` + `updateFields({field: item.id})` | `equip(profile.uid, item.type.slot, item.id)` (remove o `switch`) |
| `shop_screen.dart` 109-122 (equipar) | `updateFields(uid, {field: item.id})` | `profileRepo.equip(uid, item.type.slot, item.id)` |
| `shop_screen.dart` 125-129 (comprar) | `purchaseItem(..., equipField: field)` | `purchaseItem(..., equipSlot: item.type.slot)` (remove o `switch`/`field`) |
| `economy_repository.dart` 15/44/66/69 | `String? equipField` + `touches([equipField])` | `EquipSlot? equipSlot` + `touchesPublicProfile` |
| `profile_repository.dart` 77-91 | `updateFields`, `_blockedPrefixes` | removidos |
| `public_profile_sync.dart` 43-47 | `static touches` | removido |

## 4. Passos pequenos (cada um com analyze e test verdes; commit só com pedido)

1. Fundação, sem chamadores: `EquipSlot`, `EquipSlotField`, `ItemTypeSlot`, `AppUser.encodeAstralMap`. Testes: fieldPath igual aos três literais, `ItemType.values` todos mapeados, `encodeAstralMap` faz round-trip com `parseAstralMap`.
2. `ProfileRepository`: adicionar os métodos tipados convivendo com `updateFields`; testes novos (Firestore fake) de cada método: chaves gravadas, sync só no avatar, wallet/inventory/role intactos.
3. Migrar as telas, uma por commit lógico: account, astral, cosmos, inventory, shop (ramo equipar). `grep updateFields lib` cai a zero.
4. Economia: `equipSlot` em `purchaseItem` (interface, implementação, shop, testes `economy_repository_test.dart` e `qa_etapa_4_test.dart`). Reviewer-consultor revisa este diff.
5. Remoção: apagar `updateFields`, `_blockedPrefixes`, `PublicProfileSync.touches`; trocar o teste de `ArgumentError` por testes de ausência de caminho para campos protegidos (seção 6); atualizar `step4-repositories.md` (nota "etapa 5 concluída"), `overview.md` e `restructuring.md`.
6. Fechamento: `npm test` em `test_rules/` (a porta 8080 estava ocupada na etapa 4), `git diff firestore.rules test_rules/` vazio, checklist manual: equipar skin, fundo e avatar (e conferir busca de amigo), comprar com equipar, alternar preferências, calcular mapa astral, gerar horóscopo e tarô.

Passo opcional 7 (só com decisão do usuário): opção B da seção 5.

## 5. Atomicidade entre `users/{uid}` e `publicProfiles/{uid}` (opção separada)

Hoje (e na proposta padrão): grava `users`, depois `syncFromUser` lê `users` de novo e grava `publicProfiles`. Falhas do segundo passo deixam os dois documentos divergentes e, na compra, o erro chega à UI com a compra já efetivada (B1, caracterizado em `qa_etapa_4_test.dart`). Esta etapa não muda isso.

Opção B (muda comportamento de falha; exige decisão):

- Extrair de `PublicProfileSync` uma função pura `static Map<String,dynamic>? dataFor(Map<String,dynamic> userData, {String? fallbackEmail})` (mesma derivação de hoje, inclusive `defaultProfilePictureId` e fallback de e-mail do Auth); `syncFromUser` passa a usá-la sem mudança de comportamento (pode ir no passo 1 ou 2 como refatoração neutra).
- `ProfileRepository.equip` para `profilePicture`: `runTransaction` (lê `users`, calcula o público com o novo avatar, `tx.update(users)` + `tx.set(publicProfiles)`). Prefere-se transação a `WriteBatch` porque a derivação precisa de nome e e-mail atuais; um `get` fora do batch abriria janela de corrida. Custo: leituras iguais às de hoje (1 leitura em vez da do `syncFromUser`), 2 escritas iguais.
- `purchaseItem` com `equipSlot == profilePicture`: dentro da transação existente, `tx.set(publicDoc(uid), dataFor(data com o equipped novo))`. Sem leitura extra (o `data` do usuário já foi lido). Resolve o B1: ou tudo grava ou nada.
- Compatibilidade com as regras: `users` e `publicProfiles` são validados de forma independente (nenhuma regra usa `getAfter` entre eles), então o commit atômico passa sem alterar `firestore.rules`. Se `dataFor` devolver `null` (nome inválido), pula o `set`, como `write` faz hoje. Efeito colateral: avatar inválido em `publicProfiles` (>100 chars) passaria a reprovar a equipagem inteira, antes só reprovava o sync.
- Testes: `fake_cloud_firestore` suporta `runTransaction`; o teste B1 de caracterização é substituído por "falha do `set` público desfaz a compra" (falha injetada por fake de `PublicProfileSync`/db). Atualizar `docs/plans` (B1 resolvido).
- `reviewer-consultor`: sim (dado de usuário, saldo e inventário).

Recomendação do architect: padrão agora (sem mudar o comportamento), B como passo 7 separado, porque também resolve a divergência silenciosa. A decisão sobre B1 (best-effort versus transação) é do usuário.

## 6. Impacto nos fakes e nos testes

- `FakeProfileRepository` (`test/support/fake_repositories.dart`) usa `implements` + `noSuchMethod`: métodos novos não exigem mudança; nenhum teste de providers/router chama `updateFields`.
- `test/repositories_firestore_test.dart`, grupo `ProfileRepository.updateFields`: reescrever. "sincroniza quando toca nome/avatar" vira `equip(profilePicture)` com checagem de `publicProfiles` (avatar novo, nome e hash do e-mail preservados); "não sincroniza" vira `setShowSign` e `equip(skin)`; o teste de `ArgumentError` vira "nenhum método tipado altera wallet/inventory/role/dailyCheckIn" (executar todos e comparar o doc antes e depois). Um teste de sync para `name` desaparece porque não há `setName`.
- `test/qa_etapa_4_test.dart`: linhas 60 e 112 trocam `equipField: 'equipped.skin'`/`'equipped.profilePicture'` por `equipSlot: EquipSlot.skin`/`.profilePicture`; a linha 152 (`updateFields('preferences.publicProfile': false)`) perde o método; reescrever a caracterização de M3 gravando o doc direto e chamando `equip(profilePicture)` (o `publicProfiles` existente continua), ou removê-la e manter só a do `rebuildPublicProfiles`.
- `test/economy_repository_test.dart` linhas 46, 65, 74: mesma troca por `equipSlot`.
- Novo `test/equip_slot_test.dart` (passo 1) e testes de cada método tipado (passo 2). Verificar no passo 5 que nenhum teste referencia `PublicProfileSync.touches` (o grep atual não mostra).
- Chaves idênticas: os testes de cada método comparam o doc inteiro do Firestore fake com o esperado (`astralMapJson` string, `zodiacSign`, `dailyHoroscope.{date,content}`, `dailyTarot.{date,card,meaning}`, `preferences.{notifications,showSign}`, `equipped.*`). As regras reais seguem cobertas por `test_rules/` (37 testes), sem alteração.

## 7. Riscos e pontos de atenção

1. Alto, mas mecânico: `purchaseItem` mexe em saldo/inventário (passo 4). Mitigação: só muda a chave do equipar (derivada do enum), diff pequeno, golden de `fieldPath`, teste da transação existente, `npm test`.
2. Médio, regressão silenciosa de sync: trocar `touches(keys)` por `touchesPublicProfile` pode mudar quando o sync dispara. Equivalência: só `profilePicture` dispara hoje; o teste de caracterização cobre skin e fundo sem sync.
3. Latente, não corrigido aqui: `saveAstralMap` altera `zodiacSign` e não faz sync, mas o avatar público cai em `defaultProfilePictureId(zodiacSign)` quando não há `equipped.profilePicture`; o avatar público pode ficar defasado. Comportamento atual preservado; corrigir muda observável (candidato à opção B ou a decisão futura).
4. Baixo: `saveAstralMap` com lista vazia; a tela já só chama com resultado de `computeNatalChart` (não vazio).
5. Baixo: `createProfile` ainda é a única escrita de `role/wallet/inventory` fora de `EconomyRepository` (permitida por regra só na criação); sai na etapa 6.
6. M1 (`rebuildPublicProfiles` com permission-denied para terceiros) e M3 (LGPD, `publicProfile=false` ignorado, hash sem sal, sem delete) continuam abertos e independentes; um futuro `setPublicProfile` deve nascer junto da decisão do M3.

## 8. Revisão

- `reviewer-consultor`: passo 4 (economia), passo 5 (remoção da trava: confirmar por inspeção que nenhum método público de `ProfileRepository` aceita `Map`/caminho) e, se escolhida, a opção B. Os passos 1 a 3 tocam dados de usuário (perfil), então peça ao consultor uma única revisão do conjunto 2+3 em vez de uma por commit.
- `reviewer`: passo 1 e fechamento. `qa`: relatório em `docs/qa/etapa-5.md` com o checklist manual do passo 6.
