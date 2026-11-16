# Etapa 6: AuthRepository, cadastro com rollback e Firebase fora das telas

Status: implementada nos passos 1 a 8 (sem commit; ver `docs/plans/reestruturacao-etapas-1-a-3.md`, seção "Etapa 6 (implementada)"). Aguarda revisão do `reviewer-consultor` (autenticação e dados pessoais; ver seção 9). Base: `docs/architecture/restructuring.md` (etapa 6), `step4-repositories.md`, `step5-typed-writes.md`, `docs/plans/reestruturacao-etapas-1-a-3.md` (backlog, pendências e itens abertos das etapas 4 e 5).

Premissas aprovadas: mensagem nova de falha de cadastro e timeout de 20 s no `createProfile`; "perfil incompleto/retomada" (risco 3) fica para a etapa 11 (só documentado); `rebuildPublicProfiles` (M1) só isolado no `AdminRepository`, sem corrigir; reautenticação/exclusão de conta só como ponto de extensão documentado em `AuthRepository`. Desvios da implementação: `FirebaseAuthRepository` está em `lib/services/auth_repository.dart` junto da interface; `AdminOperationException` e `AnalyticsSummary` em `admin_repository.dart`; o redirect de `/welcome` só age para usuário deslogado (logado é tratado pelo redirect global, evitando flash para `/register` ao fim do cadastro); `RegisterScreen` descarta rascunho anterior ao entrar (exceto durante envio); testes de timeout usam `profileTimeout` curto real (50 ms), não `fakeAsync`.

## 0. Restrições

- Spark, sem Cloud Functions. `firestore.rules` e `test_rules/` não mudam (`git diff firestore.rules test_rules/` vazio em todo passo).
- Comportamento observável preservado (mensagens de erro do login, textos, rotas). Exceções deliberadas: (a) rollback do cadastro, (b) senha deixa de trafegar em `state.extra`, (c) mensagem nova para falha de cadastro pós-Auth (seção 3.3).
- Sem feature-first (etapa 8): tudo em `lib/services/`, `lib/models/`, `lib/providers/`, `lib/data/`.
- `flutter analyze` e `flutter test` verdes ao fim de cada passo. Commit só com pedido.
- Fora do escopo: M1 (`rebuildPublicProfiles` para terceiros), M3, B1, opção B da etapa 5, exclusão de conta (etapa 11), verificação de e-mail e recuperação de senha.

## 1. Estado atual (grep e leitura)

Usos diretos restantes em `lib/` (fora de `core/firebase/firebase_providers.dart` e `AnalyticsService`, que têm o default `.instance` só por conveniência e já recebem injeção pelo provider):

| Local | Uso |
|---|---|
| `screens/auth/login_screen.dart` 38 | `signInWithEmailAndPassword`; só `invalid-credential` tem mensagem própria ("Email ou senha inválidos."), o resto é "Não foi possível entrar." |
| `screens/auth/welcome_screen.dart` 96-108 | `createUserWithEmailAndPassword`, `updateDisplayName`, `profileRepositoryProvider.createProfile`, `logEvent('sign_up')`; captura só `FirebaseAuthException` (mostra `e.message`). Falha em `createProfile` não é capturada (exceção sem tratamento) e deixa conta Auth sem perfil |
| `screens/account/account_screen.dart` 169 | `FirebaseAuth.instance.signOut()` |
| `screens/admin/admin_screen.dart` 112, 124, 126, 158-181 | stream de `analytics_events`, seed de `cristais_propriedades`, publicação de `shop_items` |
| `app_router.dart` 97-110 | `/welcome` lê `name`, `email` e `password` de `state.extra` |

Arquivos que ainda importam `firebase_auth`/`cloud_firestore` em telas: login, welcome, account, admin. Meta final: zero em `lib/screens/` e `lib/widgets/`.

### 1.1 Por que o WelcomeScreen recebe a senha (item 2)

O cadastro é em duas telas. A `RegisterScreen` valida nome, e-mail e senha; a `WelcomeScreen` coleta data/hora/local de nascimento e só então cria a conta (`welcome_screen.dart` 96). A conta Auth é criada no fim de propósito: quem abandona entre as duas telas não deixa conta nem perfil. Logo a senha só é usada em uma chamada, `createUserWithEmailAndPassword`, e precisa viver desde a tela 1 até a tela 2. Nada é exibido. Não há motivo para ela passar pelo estado de navegação, apenas para viver em memória entre duas telas. `name` e `email` também passam por `extra`, mas são dados que o perfil já guardará; só a senha é sensível.

## 2. API final

### 2.1 Modelos (novos, `lib/models/`)

```dart
// lib/models/sign_up_data.dart
class SignUpData {
  const SignUpData({
    required this.name, required this.email, required this.password,
    required this.birthDate, required this.birthTime, required this.birthPlace,
    required this.zodiacSign,
  });
  final String name, email, password, birthDate, birthTime, birthPlace, zodiacSign;
  @override
  String toString() => 'SignUpData(email: $email, password: ***)'; // nunca logar a senha
}

// lib/models/auth_exception.dart
enum AuthErrorCode {
  invalidCredentials, // 'invalid-credential'
  emailInUse,         // 'email-already-in-use'
  weakPassword,       // 'weak-password'
  invalidEmail,       // 'invalid-email'
  userDisabled,       // 'user-disabled'
  tooManyRequests,    // 'too-many-requests'
  network,            // 'network-request-failed'
  requiresRecentLogin,// 'requires-recent-login' (ponto de extensao da etapa 11)
  profileCreationFailed, // Auth criado, perfil falhou, rollback executado
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code, {this.detail, this.rollbackFailed = false});
  final AuthErrorCode code;
  /// Mensagem original do Firebase (hoje exibida no cadastro); nunca contem senha.
  final String? detail;
  /// So em profileCreationFailed: o delete do usuario Auth tambem falhou
  /// (conta Auth orfa; ver risco 3).
  final bool rollbackFailed;
}
```

`AuthException` não carrega `FirebaseAuthException` nem `cause` bruto para a UI (a UI não importa Firebase). O repositório pode registrar a causa com `debugPrint`, sem senha.

### 2.2 `AuthRepository` (`lib/services/auth_repository.dart`)

```dart
abstract interface class AuthRepository {
  /// Lanca AuthException (nunca FirebaseAuthException).
  Future<void> signIn({required String email, required String password});

  /// Cria a conta Auth e o perfil. Atomico do ponto de vista do app:
  /// ou existem conta e perfil, ou nenhum dos dois (ver 3.1).
  /// Lanca AuthException; profileCreationFailed indica rollback feito.
  Future<void> register(SignUpData data);

  Future<void> signOut();

  // Ponto de extensao REALIZADO na etapa 11 (docs/architecture/step11-account-deletion.md):
  //   Future<void> reauthenticate(String password);  // EmailAuthProvider.credential + user.reauthenticateWithCredential
  //   Future<void> deleteAccount();                  // user.delete() por ultimo, depois de apagar os dados
  //   Future<void> sendPasswordReset(String email);  // "Esqueci minha senha"
  // AuthErrorCode.requiresRecentLogin mapeia o requires-recent-login.
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required ProfileRepository profile,
    Duration profileTimeout = const Duration(seconds: 20),
  });
}
```

Decisões:

- A interface não expõe `authStateChanges` nem `currentUser`: `authStateProvider` e o router continuam em `firebaseAuthProvider` (etapa 3). Mover o stream para o repositório só traria churn nos testes de router/providers sem ganho.
- `FirebaseAuthRepository` recebe `ProfileRepository` concreto (a escrita do documento é dele). Os testes injetam um `implements ProfileRepository` com `noSuchMethod`, padrão já usado.
- `logEvent('login')` e `logEvent('sign_up')` ficam nas telas/controller (como hoje; `AnalyticsService` já engole `FirebaseException`). O repositório de Auth não conhece analytics.

### 2.3 Providers (`lib/providers/app_providers.dart`)

```dart
final authRepositoryProvider = Provider<AuthRepository>((ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider), profile: ref.watch(profileRepositoryProvider)));
```

Depende só de `firebaseAuthProvider`/`profileRepositoryProvider` (estáveis), então não recria streams (regra da etapa 4, risco 3).

### 2.4 Decisão sobre `createProfile` (item 6)

Fica em `ProfileRepository` (grava `users/{uid}`, `wallet`, `inventory`, `role`; é um agregado de perfil e já tem constantes de saldo inicial que a etapa 7 centraliza). Muda apenas o corpo: grava `users/{uid}` e `publicProfiles/{uid}` em um único `WriteBatch` (seção 3.2). `AuthRepository.register` é o único chamador. A assinatura não muda.

## 3. Cadastro com rollback (item 1)

### 3.1 Ordem e compensação

Não existe ordem segura sem Auth primeiro: as regras exigem `isOwner(uid)` para criar `users/{uid}`, então o usuário Auth precisa existir. Portanto: criar Auth, gravar perfil, compensar se falhar.

```
register(data):
  cred = createUserWithEmailAndPassword      // FirebaseAuthException -> AuthException(code, detail: e.message)
  user = cred.user!
  try:
    await user.updateDisplayName(name)
    await profile.createProfile(...).timeout(profileTimeout)   // batch atomico (3.2)
  catch (e):
    deleted = false
    try: await user.delete(); deleted = true            // conta recem criada: sem exigir reautenticacao
    catch: pass
    try: await auth.signOut()                           // idempotente; garante deslogar mesmo se delete falhou
    catch: pass
    throw AuthException(profileCreationFailed, rollbackFailed: !deleted)
```

Pontos:

- `user.delete()` num usuário criado há segundos não dispara `requires-recent-login`. Após o delete o Firebase desloga sozinho; o `signOut` é só segurança.
- `updateDisplayName` dentro do `try`: falhar aborta o cadastro como antes (antes era exceção solta), agora com rollback.
- Timeout: com persistência offline (padrão no mobile) `set`/`commit` offline não rejeitam, ficam em fila e o `await` não retorna. Sem timeout o cadastro ficaria preso no spinner. Com 20 s o fluxo cai no rollback. Se estiver offline, o `delete` também falha e o resultado é `rollbackFailed: true` (conta Auth órfã, risco 3); a escrita enfileirada será rejeitada pelas regras quando houver rede e a conta já estiver deslogada (sem dado órfão). Valor de 20 s é sugestão do architect, ajustável pelo builder em um único parâmetro.
- Concorrência: o `signIn` do Firebase torna o usuário "logado" já no `createUser...`; por isso o router tem de segurar a navegação durante o cadastro (seção 4.3), senão a tela é trocada pela home antes do rollback e o erro se perde.

### 3.2 `createProfile` atômico

Sem isso o rollback seria incompleto: hoje `createProfile` faz `set` de `users/{uid}` e depois `_sync.write` de `publicProfiles/{uid}`. Se o segundo falhar, o doc `users/{uid}` (nome, e-mail, data/local de nascimento: dado pessoal) já existe, e `allow delete: if false` impede o cliente de apagá-lo; apagar a conta Auth o deixaria órfão e inalcançável. Proposta: `WriteBatch` com `set(userDoc, ...)` e `set(publicDoc, buildPublicProfile(...))` (este só se `buildPublicProfile` não devolver `null`, igual ao `write` de hoje; nome vazio já é barrado pela UI), um `commit`. As regras validam cada documento de forma independente (nenhum `getAfter` entre eles; ver `step5-typed-writes.md`, seção 5), então o batch passa sem mudar `firestore.rules`. É a mesma ideia da opção B, restrita à criação, e não depende da decisão pendente dela. `PublicProfileSync` deixa de ser usado em `createProfile` (continua em `equip` e economia).

Risco residual: commit efetivado no servidor com a resposta perdida (falha ambígua). O rollback apagaria o usuário Auth e deixaria `users/{uid}` órfão. Probabilidade muito baixa; registrar para a limpeza da etapa 11 (varrer docs sem usuário Auth só é possível por admin/console no Spark).

### 3.3 Erros tipados para a UI

Mapeamento no repositório (`FirebaseAuthException.code` para `AuthErrorCode`, tabela na seção 2.1; qualquer outro vira `unknown`). A tradução para texto fica na UI, em helpers puros (`lib/models/auth_exception.dart`, extension ou função, testáveis):

| Tela | Regra de texto | Igual a hoje? |
|---|---|---|
| Login | `invalidCredentials` -> "Email ou senha inválidos."; qualquer outro -> "Não foi possível entrar." | idêntico (só `invalid-credential` era específico) |
| Cadastro | Falha do Auth -> `detail ?? 'Não foi possível criar a conta'` | idêntico (era `e.message`) |
| Cadastro | `profileCreationFailed` -> "Não foi possível concluir o cadastro. Tente novamente." (com `rollbackFailed`: acrescentar "Se persistir, entre em contato."; texto final do designer/writer) | novo |

Textos em português não vão para o repositório; só códigos.

## 4. Senha fora do estado de navegação (item 2)

### 4.1 Alternativa

Um `Notifier` em memória guarda o rascunho entre as duas telas. Não vai para `go_router`, para `state.extra`, nem para disco/`shared_preferences`/state restoration (providers Riverpod não entram em restauração de estado).

```dart
// lib/providers/sign_up_provider.dart
typedef SignUpDraft = ({String name, String email, String password});

class SignUpState {
  const SignUpState({this.draft, this.inFlight = false});
  final SignUpDraft? draft;
  final bool inFlight;
}

class SignUpController extends Notifier<SignUpState> {
  @override
  SignUpState build() => const SignUpState();
  void start(SignUpDraft d) => state = SignUpState(draft: d);
  void clear() => state = const SignUpState();
  /// Chama AuthRepository.register; mantem inFlight=true durante a chamada,
  /// independente do ciclo de vida do widget. Sucesso: clear(). Falha: inFlight=false,
  /// draft mantido (retentar sem redigitar), relanca AuthException.
  Future<void> submit({required String birthDate, required String birthTime,
      required String birthPlace, required String zodiacSign});
}
final signUpControllerProvider = NotifierProvider<SignUpController, SignUpState>(SignUpController.new);
```

- `RegisterScreen._next` troca `context.go('/welcome', extra: {...})` por `ref.read(signUpControllerProvider.notifier).start(...)` seguido de `context.go('/welcome')` (a tela passa a ser `ConsumerStatefulWidget`).
- `WelcomeScreen` perde os parâmetros `name`/`email`/`password`; lê o rascunho do provider. `_complete` chama `signUpController.submit(...)` e depois `logEvent('sign_up')`.
- `app_router.dart`: a rota `/welcome` fica sem `extra` e ganha `redirect: (c, s) => ref.read(signUpControllerProvider).draft == null && !inFlight ? '/register' : null`. Cobre processo morto, link direto e rascunho perdido, no lugar do snackbar "Dados de registro perdidos". Sem rascunho a tela nunca abre.
- Higiene: `clear()` no sucesso, no botão "Voltar" (que também fica desabilitado enquanto `inFlight`) e ao reentrar em `/register`. O rascunho persiste apenas na memória do processo; não é logado, e `SignUpData.toString` mascara a senha.
- Nome e e-mail seguem no mesmo objeto por simplicidade (um único lugar para limpar), embora só a senha seja sensível.

### 4.2 Por que não os outros caminhos

- Pedir a senha de novo na tela 2: piora a UX sem ganho real. 
- Fundir as duas telas em uma: mexe no design (designer), fora do escopo.
- Criar a conta Auth já na tela 1 e completar o perfil depois: elimina a senha em trânsito, mas cria contas sem perfil para quem abandona o fluxo e exige rota de "perfil incompleto" (ver risco 3). Rejeitado agora.

### 4.3 Router durante o cadastro

`createUserWithEmailAndPassword` loga o usuário imediatamente; `decideRedirect` (`loggedIn && authRoute && !isLoading`) mandaria o usuário para `/app/cosmos` antes de `createProfile`/rollback terminarem, desmontando a tela e perdendo a mensagem de erro. Proposta mínima: `routerProfileKeyProvider` passa a combinar `isLoading: profileLoading || signUp.inFlight` (watch com `select` só em `inFlight`; `decideRedirect` inalterada). Enquanto o cadastro está em andamento o usuário fica em `/welcome`; ao terminar com sucesso o flag cai, o router reavalia e vai à home; com falha e rollback ele fica deslogado em `/welcome` (rota de autenticação) com o erro visível e o rascunho mantido. `decideRedirect` e seus testes não mudam; adicionar teste do `routerProfileKeyProvider`.

## 5. Admin (item 3)

Tudo vira método de `AdminRepository` (recebe só `db`, como hoje). Cada mudança é movida com o mesmo comportamento.

```dart
class AdminRepository {
  // existentes: rebuildPublicProfiles (M1 isolado, nao resolver), listUsers

  Stream<List<AnalyticsEventRow>> watchAnalyticsEvents({required DateTime since});
  Future<void> seedCrystals([List<CrystalSeed> crystals = initialCrystals]);
  Future<void> publishCatalog(List<ShopItem> seed);   // le shop_items, aplica plano puro, batch
}

typedef AnalyticsEventRow = ({String? userId, String? eventName});
class AnalyticsSummary { final int total, uniqueUsers; final Map<String,int> counts; }
AnalyticsSummary summarizeAnalytics(List<AnalyticsEventRow> rows); // pura: exclui 'anonymous', ignora eventName vazio

// Plano puro do publish (testavel sem Firestore):
Map<String, Map<String, dynamic>> planCatalogPublish({
  required Set<String> existingIds, required List<ShopItem> seed});
// novo: {type, rarity, price, active:true}; existente: {type, rarity} (merge preserva price/active);
// existente fora do seed: {active:false}. Nunca apaga.

class AdminOperationException implements Exception { final String message; }
```

- `watchAnalyticsEvents`: mesma query (`where createdAt >= since`, `orderBy createdAt desc`, `limit 500`, `snapshots`), mapeando para linhas tipadas; sem índice composto novo (range e orderBy no mesmo campo). `_startOfPeriod` (decisão de UI de "hoje/7 dias/mês") fica na tela, que passa `since`. A agregação de `eventCounts`/`uniqueUsers` sai do `StreamBuilder` para `summarizeAnalytics`.
- `seedCrystals`: o `batch.set` com `nome`/`descricao`/`foco` por cristal. A constante `_initialCrystals` sai da tela para `lib/data/crystal_seed.dart` (`CrystalSeed` record e `initialCrystals`); a etapa 7 reorganiza `data/`.
- `publishCatalog`: `get` de `shop_items`; se a leitura falhar nada é gravado (como hoje); `planCatalogPublish` decide os writes; um `batch` com `SetOptions(merge: true)`. O conjunto de documentos é bem menor que 500 operações (hoje o catálogo completo tem dezenas); documentar o limite no comentário e testar o tamanho.
- Erros: `seedCrystals` e `publishCatalog` convertem `FirebaseException` em `AdminOperationException(error.message ?? '')`; a tela mantém os textos "Falha ao atualizar cristais: …" e "Falha ao publicar catálogo: …". O erro de `rebuildPublicProfiles` (permission-denied para terceiros, M1) passa pelo mesmo wrapper, sem tentar corrigir, e continua documentado no repositório e no plano. Streams e `listUsers` propagam o erro cru (a tela só chama `toString()`).
- A verificação `profile.isAdmin` continua na tela (defesa de UX); a barreira real é `firestore.rules` (`isAdmin()`), inalterada.
- A tela deixa de importar `cloud_firestore`.

## 6. Mapa: chamada atual para nova

| Local | Hoje | Depois |
|---|---|---|
| `login_screen.dart` 38 | `FirebaseAuth.instance.signInWithEmailAndPassword` + `catch FirebaseAuthException` | `ref.read(authRepositoryProvider).signIn(email: trim, password:)` + `catch AuthException` com helper de texto |
| `account_screen.dart` 169 | `FirebaseAuth.instance.signOut()` | `ref.read(authRepositoryProvider).signOut()` (remove import `firebase_auth` se ficar sem uso) |
| `register_screen.dart` 59-66 | `context.go('/welcome', extra: {name,email,password})` | `signUpController.start(...)` + `context.go('/welcome')` |
| `welcome_screen.dart` 77-120 | `createUser...`, `updateDisplayName`, `profileRepo.createProfile`, `logEvent` | `signUpController.submit(...)`, depois `logEvent('sign_up')`; `catch AuthException` |
| `welcome_screen.dart` construtor | `name`, `email`, `password` | sem parâmetros |
| `app_router.dart` 97-110 | `/welcome` com `extra` | `/welcome` com `redirect` por rascunho; `routerProfileKeyProvider` inclui `inFlight` |
| `profile_repository.dart` 40-77 | `set` + `_sync.write` | `WriteBatch` (users + publicProfiles) |
| `admin_screen.dart` 112 | `FirebaseFirestore.instance.collection('analytics_events')...snapshots()` | `adminRepositoryProvider.watchAnalyticsEvents(since:)` + `summarizeAnalytics` |
| `admin_screen.dart` 124-134 | batch de `cristais_propriedades` | `adminRepositoryProvider.seedCrystals()` |
| `admin_screen.dart` 158-188 | leitura de `shop_items` + merge + batch | `adminRepositoryProvider.publishCatalog(fullShopCatalog)` |
| `admin_screen.dart` 15-65 | `_initialCrystals` | `lib/data/crystal_seed.dart` |

`AnalyticsService` e `firebase_providers.dart` mantêm `.instance` apenas como valor de default/provider (aceito na etapa 3); o objetivo da etapa é zero em telas.

## 7. Passos pequenos (cada um com analyze e test verdes; commit só com pedido)

1. Fundação sem chamadores: `SignUpData`, `AuthException`/`AuthErrorCode` e helpers de texto; `AuthRepository` (interface); `FakeAuthRepository` em `test/support/fake_repositories.dart`; teste do mapeamento de códigos e dos helpers de texto (login idêntico ao atual).
2. `ProfileRepository.createProfile` em `WriteBatch` (R). Testes em `repositories_firestore_test.dart`: grava os dois documentos com os mesmos campos de hoje; nome inválido não grava `publicProfiles`; nenhuma escrita parcial se o batch falhar (db que falha no commit).
3. `FirebaseAuthRepository` + `authRepositoryProvider` + testes com `FakeFirebaseAuth` estendido (seção 8). Ainda sem telas.
4. Migrar login e logout (`login_screen`, `account_screen`).
5. Senha fora do `extra` (R): `SignUpController`, register/welcome, router (`redirect` da rota e `inFlight` no `routerProfileKeyProvider`), teste de widget/router. `grep -rn "extra" lib/app_router.dart lib/screens/auth` sem a senha.
6. Admin 1: `crystal_seed.dart`, `seedCrystals`, `planCatalogPublish`, `publishCatalog`, `AdminOperationException`; telas usam; testes com `fake_cloud_firestore`.
7. Admin 2: `watchAnalyticsEvents`, `summarizeAnalytics`, tela sem `cloud_firestore`. Conferir os resultados do `grep`.
8. Fechamento: `grep -rn "FirebaseAuth.instance\|FirebaseFirestore.instance" lib/screens lib/widgets lib/app_router.dart lib/providers` = 0; `grep -rn "package:\(firebase_auth\|cloud_firestore\)" lib/screens lib/widgets` = 0; `git diff firestore.rules test_rules/` vazio; `npm test` em `test_rules/` se a porta 8080 estiver livre (pendente desde a etapa 4, inclusive teste de criação de perfil com os dois documentos, sem mudar regra); checklist manual (seção 8.3); atualizar `overview.md`, `restructuring.md` (etapa 6), `step4-repositories.md` (nota) e a seção de pendências do plano (senha em `extra` resolvida, B3 resolvido).

## 8. Testes

### 8.1 Fakes

- `FakeAuthRepository implements AuthRepository` (`noSuchMethod`): registra `signInCalls`, `registerCalls`, `signOutCalls`; `failWith` configurável (`AuthException`) e `completer` opcional para segurar `register` (testa `inFlight` e navegação).
- Estender `FakeFirebaseAuth` em `test/support/fake_firebase.dart`: `createUserWithEmailAndPassword` (devolve `FakeUserCredential` com `FakeUser`), `signInWithEmailAndPassword`, `signOut` (emite `null`), com contadores e falhas injetáveis por código (`FirebaseAuthException(code: ...)`). `FakeUser` ganha `updateDisplayName` e `delete` com flags de falha e contadores. Não adicionar `firebase_auth_mocks` (dependência de dev extra que acompanha o major do `firebase_auth`, que será atualizado na etapa 14).
- `FakeProfileRepository`/stub que `implements ProfileRepository` com `createProfile` configurável (sucesso, falha, nunca completa).

### 8.2 Casos obrigatórios

`FirebaseAuthRepository`:
- `signIn` sucesso; `invalid-credential` -> `invalidCredentials`; demais códigos -> código correspondente ou `unknown`; nunca lança `FirebaseAuthException`.
- `register` sucesso: ordem `createUser`, `updateDisplayName`, `createProfile`; nenhum `delete`.
- Rollback: `createProfile` falha -> `user.delete()` chamado uma vez, `signOut` chamado, `AuthException(profileCreationFailed, rollbackFailed: false)`.
- `updateDisplayName` falha -> mesmo rollback; `createProfile` não é chamado.
- `delete` também falha -> `signOut` chamado e `rollbackFailed: true`.
- `createProfile` nunca completa -> com `profileTimeout` curto (parâmetro do construtor), rollback ocorre (usar `fakeAsync`).
- Falha em `createUser` (`email-already-in-use`, `weak-password`) -> sem `delete`/`createProfile`; `detail` preserva a mensagem do Firebase.
- A senha não aparece em `AuthException`, `toString` de `SignUpData` nem em `debugPrint` (teste de `toString`).

`ProfileRepository.createProfile`: ver passo 2.

Controller e router:
- `SignUpController`: `start` guarda rascunho; `submit` mantém `inFlight` até terminar; sucesso limpa tudo; falha preserva o rascunho e solta o flag; `clear`.
- `/welcome` sem rascunho redireciona para `/register`; com rascunho abre; sem `state.extra` em lugar nenhum (`decideRedirect` inalterada, testes atuais continuam).
- Com `inFlight=true` e usuário logado em `/welcome`, o router não vai para a home; ao terminar com sucesso vai.

Admin:
- `planCatalogPublish`: item novo recebe `price` e `active:true`; existente mantém (sem `price`/`active` no payload); fora do seed recebe só `active:false`; nunca remove.
- `publishCatalog`/`seedCrystals` com `FakeFirebaseFirestore`: documentos finais corretos, preço e `active` de itens existentes preservados, falha na leitura não grava (db que lança no `get`).
- `summarizeAnalytics`: exclui `anonymous` de `uniqueUsers`, ignora `eventName` vazio, conta por nome.
- `watchAnalyticsEvents`: filtra por `since`, ordena desc, respeita `limit`.
- `AdminOperationException` leva a mensagem original; `rebuildPublicProfiles` continua com o teste de caracterização de M1 (inalterado).

### 8.3 Checklist manual (passo 8)

Login válido e inválido; logout; cadastro completo (conferir `users` e `publicProfiles` no console); cadastro com `createProfile` forçado a falhar (por exemplo, regra do emulador/avião após Auth) e conferir que o usuário Auth some e a tela mostra o erro; botão Voltar em andamento; matar o app entre as telas e reabrir (volta ao login, sem ir a `/welcome`); admin: popular cristais, publicar catálogo, trocar período de atividade.

## 9. Riscos, revisão e decisões abertas

Riscos:
1. (alto, autenticação) Router segurando a navegação: `inFlight` no `routerProfileKeyProvider` altera o fluxo de redirect. Se o flag ficar preso em `true` (exceção não tratada), o usuário não sai de `/welcome`. Mitigação: `try/finally` em `submit` e teste.
2. (alto, dados pessoais) `createProfile` em batch e rollback tocam `users/{uid}`; qualquer divergência de campos violaria as regras `create` (`wallet == {'stardust': 500}`, `role == 'user'`, inventário inicial). Mitigação: testes comparando campos com o corpo atual e `npm test` das regras.
3. (médio) Conta Auth órfã quando `delete` falha (offline): o usuário não consegue refazer o cadastro com o mesmo e-mail (`email-already-in-use`) e, ao logar, entra sem perfil. Hoje o problema já existe e é mais provável; o rollback o reduz, mas não o zera. Correção completa exige modo "perfil incompleto" (detectar `users/{uid}` inexistente após login e reabrir `/welcome` em modo retomada, sem senha porque já há sessão). Não incluído; candidato a etapa própria ou à 11. Registrar como pendência.
4. (médio) Falha ambígua do commit (3.2) deixando doc órfão.
4b. (alto, corrigido em parte) Commit lento/ambíguo: com persistência offline o `createProfile` pode ficar em fila e o write efetivar depois do timeout. Apagar o usuário Auth nesse caso deixaria `users/{uid}` e `publicProfiles/{uid}` órfãos, sem caminho de exclusão pelo cliente. Mitigação atual: em `TimeoutException` NÃO há `user.delete()`; só `signOut()` e `AuthException(profileCreationTimeout)` com a mensagem "o cadastro está demorando mais que o esperado; verifique a conexão e entre com seu e-mail e senha em instantes". `user.delete()` + `signOut` ficam só para falhas definitivas (permission-denied, invalid-argument etc.), com `rollbackFailed` mantido. Limite remanescente: se o write nunca efetivar, a conta Auth fica sem perfil. Recuperação de "perfil ausente" no login fica para a etapa 11, junto da varredura de docs sem usuário Auth.
5. (baixo) Back do Android durante o cadastro: o controller vive além da tela, então a operação conclui mesmo assim; o flag evita redirecionar antes. Testar manualmente.
6. (baixo) Mensagem de erro do cadastro continua dependente do texto do Firebase em inglês (comportamento atual preservado; localizar mensagens é decisão de produto).
7. (baixo) `AdminRepository` ainda não tem interface; os testes usam o Firestore fake. Interfaces para Auth/Profile/Economy/Chat só na etapa 9, e Auth entra agora por ser fronteira de teste.

Exige `reviewer-consultor`: passos 2, 3 e 5 (autenticação, rollback, dados pessoais e redirect) e o passo 6 (publicação de catálogo, preço de loja controlado pelo admin; mesmo que só mova código). Os demais (1, 4, 7, 8) podem passar pelo `reviewer`; pedir ao consultor uma revisão única do conjunto 2 a 5. `qa`: relatório em `docs/qa/etapa-6.md` com o checklist 8.3.

Decisões que só o usuário toma (nenhuma bloqueia o início):
- Aceitar a mensagem nova e o timeout de 20 s do cadastro (seção 3.1 e 3.3). Padrão assumido: sim.
- Tratar o "perfil incompleto/retomada" (risco 3) agora ou na etapa 11. Padrão assumido: depois, só registrado.
