# Etapa 4: quebrar `UserRepository` em repositórios por agregado

Status: concluído (passos 0 a 7 implementados). Etapa 5 concluída: `updateFields`, `_blockedPrefixes` e `PublicProfileSync.touches` foram removidos e `equipField` virou `EquipSlot? equipSlot` (ver `step5-typed-writes.md`); as menções abaixo a esses itens são históricas. Desvios: (1) `AdminRepository` recebe só `db`, sem `PublicProfileSync`: `rebuildPublicProfiles` precisa contar só os perfis realmente gravados e `PublicProfileSync.write` não devolve se gravou; além disso `syncFromUser` tem derivação de e-mail diferente (fallback para `auth.currentUser`). Mantém `buildPublicProfile` + `set`. (2) `watchProfile(User)` mudou de assinatura na etapa 3 (antes observava `authStateChanges`); a etapa 4 apenas moveu o método assim. (3) `fake_cloud_firestore` suporta `runTransaction` e as transações de `FirestoreEconomyRepository` têm teste; o fake não aplica regras nem simula contenção/retentativa. (4) `updateFields` agora lança `ArgumentError` para chaves `wallet*`, `inventory*`, `dailyCheckIn*` e `role*` (imposto no código). Revisado pelo `reviewer` e pelo `reviewer-consultor` (aprovado com ressalvas, registradas em "Itens abertos da etapa 4" do plano) e validado pelo qa (`docs/qa/etapa-4.md`).

Base: `docs/architecture/restructuring.md` (seção 6, etapa 4), `docs/plans/reestruturacao-etapas-1-a-3.md` e `docs/decisions/2026-11-restructuring-decisions.md`.

## 0. Restrições

- Spark, sem Cloud Functions. `firestore.rules` e comportamento observável intocados: cada método é movido literalmente (mesmo corpo, mesmas gravações, mesma ordem, mesmas exceções).
- `EconomyRepository` é `abstract interface class`, para trocar o executor depois (compra de Poeira Estelar).
- Arquivos continuam em `lib/services/` (sem subpasta nova); feature-first só na etapa 8.
- `updateFields(Map)` continua, isolado em `ProfileRepository` (substituído por escritas tipadas na etapa 5).
- `flutter analyze` e `flutter test` verdes ao fim de cada commit.

## 1. Repositórios

Todos recebem `FirebaseFirestore db` (e `FirebaseAuth auth` só quando precisam) por construtor, vindos de `firestoreProvider`/`firebaseAuthProvider` (etapa 3). Nenhum usa `.instance` como padrão novo: os parâmetros ficam `required`.

| Repositório | Arquivo | Responsabilidade | Métodos movidos | Dependências |
|---|---|---|---|---|
| `PublicProfileSync` (helper, concreto) | `public_profile_sync.dart` | Gravar `publicProfiles/{uid}` a partir dos dados do usuário | `_writePublicProfile` (vira `write`), `syncPublicProfile` (vira `syncFromUser`), `_touchesPublicProfile` (vira `static touches(keys)`) | `db`, `auth` (fallback de e-mail em `syncFromUser`), `public_profile.dart`, `data/astrology.dart` |
| `ProfileRepository` | `profile_repository.dart` | Perfil do usuário logado | `watchProfile(User)` (assinatura da etapa 3), `createProfile`, `updateFields` (substituído por escritas tipadas na etapa 5) | `db`, `PublicProfileSync` |
| `EventsRepository` | `events_repository.dart` | Eventos/rituais em `users/{uid}/events` | `watchEvents`, `addEvent`, `deleteEvent` | `db` |
| `SocialRepository` | `social_repository.dart` | Amigos, busca por e-mail e intenções/notificações | `watchFriends`, `findUserByEmail`, `addFriend`, `sendIntention`, `watchUnreadIntention`, `markNotificationRead` | `db`, `public_profile.dart` (`hashEmail`) |
| `CatalogRepository` | `catalog_repository.dart` | Leitura do catálogo `shop_items` | `watchShopCatalog` (renomear para `watchCatalog` só na etapa 7, para o diff ficar pequeno) | `db`, `economy.dart` (`CatalogEntry`) |
| `EconomyRepository` (interface) + `FirestoreEconomyRepository` | `economy_repository.dart` | Todo crédito e débito de saldo | `purchaseItem`, `dailyCheckIn` | `db`, `PublicProfileSync`, `economy.dart` (lógica pura) |
| `AdminRepository` | `admin_repository.dart` | Operações restritas a admin | `listUsers`, `rebuildPublicProfiles` | `db`, `public_profile.dart`, `AppUser` (sem `PublicProfileSync`; ver desvios) |

Notas de decisão:

- Perfil público: `PublicProfileSync` existe porque dois agregados (Profile e Economy) gravam `publicProfiles` por ele (Admin grava direto, ver desvios); originalmente eram três. Antes: gravam `publicProfiles`. Duplicar a lógica em cada um criaria divergência; um helper concreto, sem interface, resolve. Ele também acompanha a economia: o executor de compra, hoje cliente, poderia ser Function no futuro e o sync passaria para o servidor; por isso fica fora da interface.
- `AdminRepository.rebuildPublicProfiles` mantém a derivação de avatar/e-mail como está hoje (e-mail `''` quando ausente, sem fallback para `auth.currentUser`) e grava com `buildPublicProfile` + `set`, sem `PublicProfileSync`. Não unificar com `syncFromUser` (comportamento diferente; a unificação cabe na etapa 5).
- `createProfile` é conceitualmente de `AuthRepository` (etapa 6, com rollback), mas fica em `ProfileRepository` até lá.
- `CatalogRepository` e a leitura de `shop_items` dentro da transação de compra ficam separados de propósito: a transação precisa de `tx.get`, e fica no executor de economia.
- Helper de caminho: criar `lib/core/firebase/firestore_paths.dart` com extension sobre `FirebaseFirestore` (`userDoc(uid)`, `publicDoc(uid)`, `shopItemDoc(id)`), para não repetir strings de coleção em sete arquivos. Só strings; nenhum comportamento.

## 2. Interfaces

Só a economia ganha interface agora (conforme `restructuring.md` seção 4 e etapa 9 para as demais):

```dart
abstract interface class EconomyRepository {
  /// Compra atomica; se [equipField] vier, equipa na mesma gravacao.
  /// Lanca [EconomyException] sem gravar quando invalida.
  Future<void> purchaseItem({
    required String uid,
    required String itemId,
    String? equipField,
  });

  /// Check-in diario; [today] = yyyy-MM-dd. Lanca [AlreadyCheckedInException].
  Future<void> dailyCheckIn({required String uid, required String today});
}
```

- Contrato: todo ganho ou gasto de `wallet.stardust` passa por aqui; nenhum outro repositório pode gravar `wallet.*`. `ProfileRepository.updateFields` lançava `ArgumentError` para chaves que começam com `wallet`, `inventory`, `dailyCheckIn` ou `role` (substituído por escritas tipadas na etapa 5).
- `FirestoreEconomyRepository` é a implementação atual, com o corpo movido sem alteração. Um futuro `CallableEconomyRepository` (Function) implementa a mesma interface e troca-se no `economyRepositoryProvider`.
- Dívida conhecida, a ser tratada na etapa 5: `equipField` expõe caminho de campo do Firestore (`'equipped.skin'`) na interface; trocar por um enum de slot (`EquipSlot`). Não mudar agora para manter a assinatura estável para as telas.
- Os demais repositórios usam classe concreta; fakes de teste usam `implements` (padrão já em uso).

## 3. Providers

Todos em `lib/providers/app_providers.dart` (sem arquivo novo; diff pequeno).

Novos:

```dart
final publicProfileSyncProvider = Provider((ref) => PublicProfileSync(
    db: ref.watch(firestoreProvider), auth: ref.watch(firebaseAuthProvider)));
final profileRepositoryProvider = Provider((ref) => ProfileRepository(
    db: ref.watch(firestoreProvider), sync: ref.watch(publicProfileSyncProvider)));
final eventsRepositoryProvider  = Provider((ref) => EventsRepository(ref.watch(firestoreProvider)));
final socialRepositoryProvider  = Provider((ref) => SocialRepository(ref.watch(firestoreProvider)));
final catalogRepositoryProvider = Provider((ref) => CatalogRepository(ref.watch(firestoreProvider)));
final economyRepositoryProvider = Provider<EconomyRepository>((ref) =>
    FirestoreEconomyRepository(
        db: ref.watch(firestoreProvider), sync: ref.watch(publicProfileSyncProvider)));
final adminRepositoryProvider   = Provider((ref) => AdminRepository(ref.watch(firestoreProvider)));
```

Removido: `userRepositoryProvider` (no commit final). Até lá fica convivendo, com `UserRepository` encolhendo.

Providers derivados que passam a usar o repositório novo (sem mudar o `select` da etapa 2):

| Provider | Hoje | Depois |
|---|---|---|
| `profileProvider` | `userRepositoryProvider.watchProfile` | `profileRepositoryProvider.watchProfile` |
| `shopCatalogProvider` | `userRepositoryProvider.watchShopCatalog` | `catalogRepositoryProvider.watchShopCatalog` |
| `eventsProvider` | `userRepositoryProvider.watchEvents` | `eventsRepositoryProvider.watchEvents` |
| `friendsProvider` | `userRepositoryProvider.watchFriends` | `socialRepositoryProvider.watchFriends` |
| `intentionProvider` | `userRepositoryProvider.watchUnreadIntention` | `socialRepositoryProvider.watchUnreadIntention` |

Importante: continuar usando `ref.watch(...Provider)` do repositório (como hoje), não `ref.read`, e o repositório só depende de `firestoreProvider`/`firebaseAuthProvider`, que não mudam; assim não há recriação do stream (testes da etapa 2 continuam valendo).

## 4. Mapa de migração das chamadas nas telas

| Arquivo (linha atual) | Chamada hoje | Depois |
|---|---|---|
| `lib/screens/account/account_screen.dart` 50 | `userRepositoryProvider.findUserByEmail` | `socialRepositoryProvider.findUserByEmail` |
| `account_screen.dart` 59 | `.addFriend` | `socialRepositoryProvider.addFriend` |
| `account_screen.dart` 134, 143 | `.updateFields(uid, {'preferences...'})` | `profileRepositoryProvider.updateFields` (mesmo Map; etapa 5 tipa) |
| `account_screen.dart` 207 | `.sendIntention` | `socialRepositoryProvider.sendIntention` |
| `lib/screens/admin/admin_screen.dart` 84, 95 | `.listUsers` | `adminRepositoryProvider.listUsers` |
| `admin_screen.dart` 204 | `.rebuildPublicProfiles` | `adminRepositoryProvider.rebuildPublicProfiles` |
| `lib/screens/astral/astral_screen.dart` 80 | `.updateFields(astralMapJson, zodiacSign)` | `profileRepositoryProvider.updateFields` |
| `lib/screens/home/cosmos_screen.dart` 41, 62 | `.updateFields(dailyHoroscope/dailyTarot)` | `profileRepositoryProvider.updateFields` |
| `cosmos_screen.dart` 87 | `.dailyCheckIn` | `economyRepositoryProvider.dailyCheckIn` |
| `lib/screens/shop/shop_screen.dart` 114, 121 | `repo.updateFields({field: id})` (equipar) | `ref.read(profileRepositoryProvider).updateFields` |
| `shop_screen.dart` 124 | `repo.purchaseItem` | `ref.read(economyRepositoryProvider).purchaseItem` (a tela passa a ler dois providers; sem `repo` único) |
| `lib/screens/shop/inventory_screen.dart` 90 | `.updateFields({field: id})` | `profileRepositoryProvider.updateFields` |
| `lib/screens/rituals/rituals_screen.dart` 54, 67 | `.addEvent`, `.deleteEvent` | `eventsRepositoryProvider.addEvent/deleteEvent` |
| `lib/screens/auth/welcome_screen.dart` 101 | `.createProfile` | `profileRepositoryProvider.createProfile` |
| `lib/widgets/cosmic_scaffold.dart` 69 | `.markNotificationRead` | `socialRepositoryProvider.markNotificationRead` |

Somente trocas de provider e nome; nenhuma lógica de tela muda. Arquivos de tela tocados: account, admin, astral, cosmos, shop, inventory, rituals, welcome, cosmic_scaffold.

## 5. Ordem de execução para o builder

Um commit por passo (somente quando o usuário pedir commit), com `flutter analyze` e `flutter test` verdes em cada um. Regra comum: mover o código copiando literalmente, remover do `UserRepository`, trocar providers, telas e fake do teste no mesmo commit, para nunca haver duas fontes.

0. Preparação, sem mover métodos: criar `core/firebase/firestore_paths.dart` e `PublicProfileSync`; `UserRepository` passa a delegar a ele (ele recebe o sync por construtor ou o instancia a partir de `db`/`auth`, o que for mais simples para manter `UserRepository(db:, auth:)` funcionando). Providers e testes existentes ficam intactos.
1. `EventsRepository` (3 métodos, nenhuma dependência cruzada). Telas: rituals. Fake: ver seção 6.
2. `SocialRepository` (6 métodos). Telas: account (3 chamadas), cosmic_scaffold.
3. `CatalogRepository` (1 método; só `shopCatalogProvider` muda).
4. `EconomyRepository` + `FirestoreEconomyRepository` (R: reviewer-consultor). Telas: cosmos (check-in), shop (compra). Conferir por diff que o corpo das transações e a chamada de `sync` pós-compra são idênticos (inclusive o `.then` que só sincroniza quando `equipField` toca perfil público).
5. `ProfileRepository` (`watchProfile`, `createProfile`, `updateFields`). Mudança em `profileProvider`; telas: account (prefs), astral, cosmos (horóscopo/tarô), shop e inventory (equipar), welcome. Os testes de provider e router dependem do `profileProvider`: migrar o fake no mesmo commit.
6. `AdminRepository` (`listUsers`, `rebuildPublicProfiles`). Telas: admin.
7. Remoção: com `UserRepository` vazio, apagar `user_repository.dart`, `userRepositoryProvider` e `FakeUserRepository`; atualizar `overview.md` e este documento (status "concluído"). `grep -r UserRepository lib test` deve retornar zero.

Verificação extra em todos os passos: `grep -rn "userRepositoryProvider" lib` deve listar só o que ainda não foi migrado; `git diff firestore.rules test_rules/` vazio.

## 6. Estratégia dos fakes de teste

Hoje há um único `FakeUserRepository implements UserRepository` (com `noSuchMethod` lançando `UnimplementedError`), usado em `router_test.dart`, `providers_subscriptions_test.dart` e `qa_etapas_1_a_3_test.dart`. `firebase_providers_test.dart` usa `FakeFirestore` e o repositório real.

Proposta: dividir o fake em um por repositório, no mesmo arquivo ou ao lado, mantendo o padrão atual (`implements` + `noSuchMethod`):

- `FakeProfileRepository`: `emit(AppUser)`, `watchProfile`, `profileWatchedUids`, `activeProfileListeners` (código atual do fake, movido).
- `FakeEventsRepository`: `watchEventsCalls`, `eventsUids`.
- `FakeSocialRepository`: `watchFriendsCalls`, `watchIntentionCalls`.
- Fakes de Catalog, Economy (`implements EconomyRepository`, gravando as chamadas) e Admin criados só quando algum teste precisar.
- Pacote de conveniência `FakeRepos` em `test/support/fake_repositories.dart`, que cria os três fakes e expõe `overrides` (lista de `overrideWithValue` dos providers), para que cada teste tenha uma linha em vez de três. `testUser(...)` continua exportado do mesmo arquivo (ou reexportado).
- Em cada passo de migração, mover os métodos do `FakeUserRepository` para o fake novo e ajustar os testes (`repo.emit` vira `repos.profile.emit`; `repo.watchEventsCalls` vira `repos.events.watchCalls`; o cast em `router_test.dart` linha 125 vira `container.read(profileRepositoryProvider) as FakeProfileRepository`). Durante a transição o `FakeUserRepository` continua cobrindo o que ainda estiver no `UserRepository`; no passo 7 é apagado.
- Para economia: testes novos que verificam que a UI/providers usam `EconomyRepository` pela interface (fake que registra chamadas). `fake_cloud_firestore` suporta `runTransaction`, e as transações de `FirestoreEconomyRepository` têm teste (`economy_repository_test.dart`); o fake não aplica regras nem simula contenção, então regras ficam em `test_rules/` e `economy_test.dart` cobre a lógica pura.
- Testes de regressão com `fake_cloud_firestore` (suporta `orderBy`/`where`): `test/repositories_firestore_test.dart` cobre Events, Social, Admin e `ProfileRepository.updateFields`.

## 7. Riscos e mitigações

1. Saldo e inventário (alto): erro ao mover a transação pode quebrar a compra sem que o analyzer note. Mitigação: mover literalmente, diff revisado pelo `reviewer-consultor`, teste manual no emulador/app (comprar item pago, item gratuito, equipar após compra, check-in duas vezes) e `npm test` em `test_rules/` (deve passar sem mudança). Sem teste automatizado de transação hoje.
2. Perfil público (médio): três repositórios dependem do `PublicProfileSync`; se `economyRepositoryProvider` esquecer o sync, o avatar comprado e equipado não atualiza a busca de amigo. Mitigação: o commit 4 mantém o `.then` do sync condicionado a `equipField`; item de checklist para o revisor.
3. Re-assinatura de streams (médio): se um provider de repositório passar a depender de algo que muda (por exemplo, `ref.watch(profileProvider)`), os streams reabririam. Mitigação: repositórios dependem só de `firestoreProvider`/`firebaseAuthProvider`; os testes de contagem de assinatura da etapa 2 continuam no CI.
4. Escape hatch `updateFields` (médio): aceitava qualquer chave, inclusive `wallet.stardust`, ferindo o contrato do `EconomyRepository`; agora recusa as chaves protegidas. Mitigação: `ArgumentError` para chaves protegidas e comentário `// etapa 5: remover`; sem `@Deprecated` (daria `info` no analyze nas telas).
5. Fakes frágeis (baixo): `noSuchMethod` falha em runtime se um provider chamar método não implementado. Mitigação: falhar rápido; cada passo roda a suíte inteira.
6. Conflito com a etapa 6 (baixo): `createProfile` fica em `ProfileRepository` e o fluxo de cadastro continua sem rollback; registrado para a etapa 6.
7. Inicialização (baixo): providers de repositório continuam lazy; app sem config do Firebase não os lê (o teste de widget da etapa 1 cobre).
8. Nomes: `watchShopCatalog` permanece por ora; renomear só na etapa 7 evita mexer em chamadas.

## 8. Fora do escopo desta etapa

Tipar escritas e `WriteBatch` do perfil público (etapa 5), `AuthRepository` e Firebase nas telas de admin/login (etapa 6), separar `models/`/`data/` (etapa 7), mover para feature-first (etapa 8), controllers e demais interfaces (etapa 9). Nada em `firestore.rules`, `firestore.indexes.json` ou `test_rules/`.

## 9. Revisão

Marcado para `reviewer-consultor`: passo 4 (economia: saldo/inventário) e a introdução de `PublicProfileSync` (passo 0; dado de usuário público). Os demais passos podem ser revisados pelo `reviewer`.
