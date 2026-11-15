# Etapa 9: controllers (Notifier) no lugar da lógica das telas

Status: concluída (passos 0 a 7 e ressalvas dos revisores em commits na branch; defeitos do chat corrigidos em `fix(oracle)`; ver seção 9). Refatoração pura: nenhum texto, regra, valor, gravação ou leitura do Firestore/SharedPreferences muda. Spark inalterado (zero dependência nova, zero leitura nova). `firestore.rules`, `firestore.indexes.json`, `test_rules/`, `pubspec.yaml` e `pubspec.lock` ficam sem diff.

Base: `restructuring.md` (etapa 9 e seção 4 sobre cosmos), `step8-feature-first.md` (camadas, `shared/`, dívidas), `step6-auth.md` (padrão `SignUpController`), `plans/reestruturacao-etapas-1-a-3.md` (backlog e dívidas), `chat-sync.md` (etapa 10) e o código atual de `lib/features/**` e `test/`. Riverpod é o 2.6.1 (sem `ref.mounted`; ver seção 7).

## 1. O que cada tela faz hoje além de renderizar

| Tela (linhas) | Lógica e estado que não são de apresentação |
|---|---|
| `cosmos_screen` (425; ~75 de lógica) | (a) **Horóscopo do dia**: se há signo e o `dailyHoroscope` não é de hoje, chama `OracleService.complete` com o prompt e grava `saveDailyHoroscope`; disparado uma vez por instância da tela (`_horoscopeRequested`) via post-frame, sem tratamento de erro. (b) **Tarô**: `pickDailyCard(now, uid)`, tenta `complete` (falha vira o significado local da carta), grava `saveDailyTarot`; flag `_drawing`, snackbar de falha só se a gravação falhar, aborta se a tela desmontou. (c) **Check-in**: flag `_checkingIn`, `economy.dailyCheckIn(uid, today)`, mapeia `EconomyException` e erro genérico para o texto do snackbar. (d) Derivações no `build`: `_today` (duas cópias de `DateFormat('yyyy-MM-dd')`, outra em rituals), horóscopo e tarô "de hoje", `checkedIn`, eventos de hoje filtrados e ordenados. |
| `oracle_screen` (239; ~75) | Estado do chat inteiro: lista de conversas, índice, `_loading`, `_hydrated`. Hidrata quando o perfil chega (`ChatStore.load`) e consome `pendingOraclePromptProvider`. `_send`: trim, guarda de duplo envio, monta mensagem do usuário e título (primeira mensagem vira título), `_persist`, `logEvent('send_message_chat')`, `complete`, anexa resposta, `_persist`. Nova conversa (`create(n+1)`, `_persist`). Regrava a lista inteira em `shared_preferences` a cada mutação (3 gravações por conversa nova e 2 por mensagem). TTS (`FlutterTts`) e `TextEditingController` são de UI. |
| `rituals_screen` (144; ~20) | `_add`: trim e descarte de título vazio, monta `RitualEvent(id: '')`, `addEvent`, `logEvent('add_event_calendar')`; `_delete` + `logEvent('delete_event_calendar')`; filtro e ordenação do dia. Dia selecionado e diálogo são de UI. |
| `astral_screen` (128; ~20) | Botão "Calcular mapa": `parseDateString`, defaults de hora (12) e minuto (0), `computeNatalChart`, `saveAstralMap`; snackbar se a data de nascimento falta. `_el` (cor do elemento) é de UI. |
| `shop_screen` (162; ~45) | `_buying`, decisão equipar x comprar (`inventory.contains`), `profileRepo.equip` ou `economy.purchaseItem(equipSlot)`, mapeamento de erros para snackbar, `_isEquipped` e `_label` (duplicados no inventário), filtro de itens ativos pelo catálogo do servidor. |
| `inventory_screen` (113; ~15) | `_equip` (chama `profileRepo.equip` sem tratamento de erro; snackbar "X equipado." se montado), `_isEquipped`, rótulos duplicados. |
| `account_screen` (236; ~25) | `_searchFriend` (busca por e-mail, regra "não achou ou é você", `addFriend`, textos), `sendIntention` com snackbar, alternância de preferências e `signOut` (uma linha cada). |

Fora do escopo desta etapa (registrado): `login_screen`/`register_screen`/`welcome_screen` (já têm `SignUpController`; `login` tem lógica pequena), `admin_screen` (350 linhas, uso restrito a admin), `main_shell` e router. Podem virar "9b" depois sem afetar o que segue.

## 2. Decisões

| Tema | Decisão | Por quê |
|---|---|---|
| Onde moram os controllers | `features/<f>/presentation/<nome>_controller.dart`, **não** em `domain/`. | `Notifier` vem de `flutter_riverpod`, que depende do SDK Flutter; `domain/` é Flutter-free e a pureza é verificada no fecho transitivo (regra 6 do step 8). Não há `riverpod` puro no `pubspec` e não entra dependência nova. O mesmo critério já colocou `SignUpController` em `presentation/`. |
| Camada do arquivo `*_controller.dart` | Passa a ser a camada 3 ("providers"). O regex `layerOf` muda de `_providers?\.dart$` para `_(providers?\|controller)\.dart$`. | Com o regex atual seria camada 5 ("tela") e nenhum `shared/` nem outra feature poderia importá-lo; um controller não é tela. Como providers, herda de graça a regra "não importa `material`/`widgets`", que é o que mantém `BuildContext`, `ScaffoldMessenger` e `TextEditingController` fora dele. O teste ganha casos de `layerOf` e de mutação em memória (como os existentes). |
| Regras de negócio puras | Funções puras em `features/<f>/domain/` (sem Flutter) ou `core/`, testadas sem Riverpod. | Barato de testar e já é o padrão (`computeCheckIn`, `pickDailyCard`, `planCatalogPublish`). |
| Feedback ao usuário | O controller **não** mostra snackbar. Retorna um resultado simples (`String? message` ou um enum/record) com o **mesmo texto de hoje**; a tela captura o `ScaffoldMessenger` antes do `await` (como hoje) e exibe. | Mantém os textos idênticos, o controller testável e preserva o comportamento de "snackbar mesmo se a tela desmontou" onde ele existe hoje. |
| Estado de UI puro | Fica na tela: dia selecionado, filtro de tipo, `TextEditingController`, `FlutterTts`, diálogo de novo ritual. | Não é regra de negócio; mover só adiciona cerimônia. |
| Tempo | Novo `core/clock/clock_providers.dart` (`clockProvider = Provider<DateTime Function()>((_) => DateTime.now)`) e `core/clock/day_key.dart` (`String dayKey(DateTime)` = `yyyy-MM-dd`, usando `intl`, já dependência). Controllers leem o relógio por provider. | Hoje `DateTime.now()` está espalhado; sem relógio injetável não há teste determinístico de "de hoje", check-in e tarô diário. Pure Dart, sem dependência nova. |
| Ciclo de vida | `NotifierProvider.autoDispose` para os controllers com estado (cosmos, chat, shop); stateless (`Notifier<void>`) para rituals, astral e account. | Equivale ao `State` da tela que substituem (flags nascem e morrem com a tela). Não usar `keepAlive`: mudaria o comportamento (gravações continuariam após sair da tela). |
| Interfaces | Só as do backlog: `AuthRepository` e `EconomyRepository` **já existem**; criar `abstract interface class ProfileRepository` (+ `FirestoreProfileRepository`, mesmo padrão de economia) e `ChatRepository`. `OracleService`, `EventsRepository`, `SocialRepository` ficam classes concretas (fakes `implements` com `noSuchMethod`, padrão de `test/support/fake_repositories.dart`). | Segue o backlog ("interfaces só para Auth/Profile/Economy/Chat") e o princípio do mínimo. |
| Dívida "equipar mora em `ProfileRepository`" | **Não resolver nesta etapa.** Os controllers passam a ser o único chamador (`ShopController.equip`), o que isola a decisão; mover `equip` fica para junto da decisão pendente da Opção B (atomicidade `users` + `publicProfiles`, `step5-typed-writes.md` seção 5). | Ver seção 6. |
| Dívidas de `shared/` (`cosmetics_style`, `equipped_cosmetics_providers`) | Não mudam. Nenhum controller as toca (`equippedSkinProvider` continua lido pela tela). Extrair `CosmicScaffold` do estado de feature segue como melhoria futura, fora de escopo. | Não há ganho de testabilidade na etapa e há risco de ciclo. |

## 3. Controllers

Convenção: `profileProvider` é lido por `ref.read(...).valueOrNull` dentro do método, no momento da ação (como as telas fazem hoje); nunca `watch` do perfil inteiro no controller (evita reconstruir ao mudar saldo). Todos os caminhos de importação respeitam o teste de fronteira (providers de outra feature podem ser importados; `data` de outra feature, nunca).

### 3.1 `CosmosController` (`features/cosmos/presentation/cosmos_controller.dart`)

- Responsabilidade: horóscopo do dia, tarô do dia, check-in.
- Estado: `CosmosState { bool drawingTarot, bool checkingIn }`. Flag interna `_horoscopeRequested` (não é estado de UI) e `_alive` (ver seção 7).
- Dependências: `profileProvider`, `profileRepositoryProvider`, `oracleServiceProvider`, `economyRepositoryProvider`, `clockProvider`.
- Métodos:
  - `Future<void> ensureHoroscope()`: se `_horoscopeRequested` ou perfil sem signo, retorna; senão marca o flag (mesmo critério de hoje: o flag é marcado quando há signo, mesmo com o horóscopo já em cache) e executa a regra de `horoscopeIfNeeded`. A tela continua chamando em post-frame. Exceções continuam sem tratamento (comportamento atual; dívida registrada).
  - `Future<String?> drawTarot()`: guarda `drawingTarot`; `pickDailyCard`, `complete` com fallback para `card.meaning`, `saveDailyTarot`. Retorna a mensagem de falha ("Não foi possível salvar a carta. Tente novamente.") ou `null`. Se o controller foi descartado após o `complete`, retorna sem gravar (equivale ao `if (!mounted) return`).
  - `Future<String> checkIn()`: guarda `checkingIn`; `dailyCheckIn(uid, today)`; retorna `'+$checkInReward Poeira Estelar pelo check-in de hoje'`, `e.message` (`EconomyException`) ou "Não foi possível fazer o check-in. Tente novamente.".
- Domínio novo, puro (`features/cosmos/domain/daily_content.dart`): `String horoscopePrompt(sign)`, `String tarotPrompt(cardName)` (textos literais de hoje), `bool needsHoroscope(AppUser, String today)`, `String? horoscopeOf(AppUser, String today)`, `Map<String,dynamic>? tarotOf(AppUser, String today)`, `bool checkedInToday(AppUser, String today)`. Importa `profile/domain` (permitido: domain de outra feature).
- Sai da tela: os três métodos privados, `_drawing`, `_checkingIn`, `_horoscopeRequested`, `_today`, as derivações de "de hoje". Fica: layout, `GestureDetector` (`onTap: tarot == null ? ... : null`), `moonFor(DateTime.now())` (função pura de apresentação do card), snackbars, navegação.
- Eventos do dia: `eventsOfDay(List<RitualEvent>, String dayKey)` em `features/rituals/domain/ritual_day.dart` (filtra e ordena por `time`), usado por cosmos e rituals (remove a duplicação). Cosmos importa o domain de rituals (permitido).

### 3.2 `ChatController` (`features/oracle/presentation/chat_controller.dart`) e `ChatRepository`

- Responsabilidade: todo o estado do chat do oráculo; a tela só renderiza e fala (TTS).
- Estado: `ChatState { List<ChatConversation> conversations, int index, bool loading, bool hydrated }` com getter `current` (mantém o placeholder `ChatConversation(id: 'x', title: 'Conversa', messages: [])` quando vazio, como hoje).
- Dependências: `chatRepositoryProvider` (substitui `chatStoreProvider`), `oracleServiceProvider`, `analyticsServiceProvider`, `profileProvider` (uid e signo, lidos na ação), `pendingOraclePromptProvider`.
- Métodos: `Future<void> hydrate()` (idempotente; carrega quando há perfil; a tela chama em post-frame como hoje), `String? takePendingPrompt()` (devolve e limpa o provider; a tela coloca no campo), `Future<void> send(String text)` (mesma sequência de hoje: trim, descarte de vazio/duplo envio, usuário, persistir, `logEvent('send_message_chat')`, `complete`, resposta, persistir), `Future<void> newConversation()` (`create(length + 1)`, seleciona, persiste), `void select(int index)`.
- `ChatRepository` (`abstract interface class`, em `features/oracle/data/chat_repository.dart`): `Future<List<ChatConversation>> load(String uid)`, `Future<void> save(String uid, List<ChatConversation> all)`, `ChatConversation create(int index)`. `ChatStore` passa a `implements ChatRepository` (corpo e chave `astrum.chat.<uid>` intocados; `load` apenas devolve `Future` já resolvido). A **interface é por snapshot** de propósito: com ela as gravações em prefs ficam byte a byte iguais às de hoje (uma interface incremental, `appendMessage`, perderia no caso "primeira conversa vazia + nova conversa" a conversa 1 vazia ao reabrir o app).
- Para a etapa 10: a troca da fonte é um novo `ChatRepository` (Firestore, com migração do legado) e, se for incremental, a mudança de `_persist` dentro do `ChatController`. A tela não muda: ela só vê `ChatState` e `send/newConversation/select/takePendingPrompt`. O estado `hydrated`/`loading` já cobre a carga assíncrona. Por isso `load` já é `Future`.
- Sai da tela: `_conversations`, `_index`, `_loading`, `_hydrated`, `_hydrate`, `_persist`, `_send`, a criação de conversa. Fica: `_input`, `_tts`, lista, chips, `ref.listen` em `hydrated` para aplicar o prompt pendente.
- Comportamento preservado literalmente, **com os defeitos latentes** (registrados como dívida, não corrigidos aqui): (1) se `complete` ou `save` lançar, `loading` fica `true` para sempre; (2) a resposta é gravada em `conversations[index]` do **momento da resposta**, não da conversa que originou o envio (trocar de conversa durante a resposta põe a resposta na errada). `OracleService` é 100% local, então (1) não ocorre hoje; (2) é possível. Corrigir é uma linha cada (capturar o id da conversa; `try/finally`) e fica como pós-etapa, com aval do planner, porque muda comportamento observável.

### 3.3 `RitualsController` (`features/rituals/presentation/rituals_controller.dart`)

- `Notifier<void>`, sem estado. Dependências: `profileProvider`, `eventsRepositoryProvider`, `analyticsServiceProvider`.
- `Future<void> add({required String title, required String time, required String date})`: sem perfil, retorna; `title.trim().isEmpty`, retorna; `addEvent(uid, RitualEvent(id: '', title: t, time: time.trim(), date: date))`; `logEvent('add_event_calendar')`.
- `Future<void> delete(String eventId)`: `deleteEvent` e `logEvent('delete_event_calendar')`.
- Sai da tela: montagem do evento e analytics. Fica: diálogo, dia selecionado (usa `dayKey` e `eventsOfDay`).

### 3.4 `AstralController` (`features/astral/presentation/astral_controller.dart`)

- `Notifier<void>`. Dependências: `profileRepositoryProvider`.
- `Future<bool> calculate(AppUser profile)` retorna `false` quando a data de nascimento é inválida (a tela mostra "Preencha a data de nascimento na conta."); senão `computeNatalChart` + `saveAstralMap` e `true`. Sem guarda de reentrada (como hoje).
- Domínio novo, puro (`features/astral/domain/birth_datetime.dart`): `DateTime? birthDateTimeOf({required String birthDate, required String birthTime})` com os defaults de hoje (hora 12, minuto 0, partes não numéricas viram o default). Cria a pasta `domain/` em `astral`.

### 3.5 `ShopController` (`features/economy/presentation/shop_controller.dart`)

- Estado: `ShopState { bool buying }`. Dependências: `profileProvider`, `profileRepositoryProvider`, `economyRepositoryProvider`.
- `Future<String?> selectItem(ShopItem item)`: guarda `buying`; sem perfil, retorna `null`; se `profile.inventory.contains(item.id)` chama `profileRepo.equip(uid, item.type.slot, item.id)`, senão `economy.purchaseItem(uid:, itemId:, equipSlot: item.type.slot)`; retorna `e.message` (`EconomyException`), "Não foi possível concluir. Tente novamente." (outro erro) ou `null`.
- `Future<void> equip(ShopItem item)`: usado pelo inventário; **não** engole erros e não tem guarda (como hoje). O snackbar "`${item.name}` equipado." continua na tela, após o `await`.
- Duplicações que saem das duas telas: `_isEquipped` vira `AppUser.isEquipped(ShopItem)` (getter puro em `features/profile/domain/app_user.dart`; usa a aresta já existente profile -> economy domain, sem criar a inversa) e `itemTypeLabel(ItemType)` em `economy/domain/shop_item.dart`. Filtro de tipo e `catalog[item.id]?.active` ficam na tela (apresentação do catálogo do servidor). `_ItemIcon` fica (UI).

### 3.6 `AccountController` (`features/profile/presentation/account_controller.dart`)

- `Notifier<void>`. Dependências: `profileProvider`, `socialRepositoryProvider`.
- `Future<String?> addFriendByEmail(String email)`: busca; se `null` ou `found.id == uid`, devolve "Nenhuma constelação encontrada com esse email."; senão `addFriend` e devolve "`${found.name}` entrou na sua constelação.". Sem perfil: `null`. A tela mantém o `mounted` entre os `await`s ao exibir.
- `Future<void> sendIntention(AppUser me, Friend friend, String id, String label)` repassa a `sendIntention(fromUid, fromName, toUid, intentionId, intentionLabel)`.
- Ficam na tela, por serem de uma linha: `setNotificationsEnabled`, `setShowSign`, `signOut`. O mapa `intentions`/`intentionStyles` fica onde está (importado por `rules_contract_test`).

## 4. Passos (um commit cada; `flutter analyze` e `flutter test` verdes em todos)

Pré-condição P0: árvore limpa, analyze e test verdes; anotar a contagem de testes. Em todo passo: `git diff -- firestore.rules firestore.indexes.json test_rules pubspec.yaml pubspec.lock` vazio, e os textos de snackbar/UI por grep antes e depois (nenhum literal muda).

| # | Commit | O que faz | Verificação específica |
|---|---|---|---|
| 0 | `chore: base da etapa 9` | `layerOf` aceita `_controller.dart` como camada 3 (+ casos de detector e mutação); `core/clock/{clock_providers,day_key}.dart`; helpers de teste (`test/support/`: `FakeOracleService`, `FakeEconomyRepository`, `FakeChatRepository`, `FakeAnalytics`, `makeContainer(...)`); spike de widget test com `GoogleFonts`/`Starfield` (ver seção 7). Nenhuma tela muda. | `core_boundaries_test` verde com os casos novos. |
| 1 | `refactor(profile): interface ProfileRepository` | `abstract interface class ProfileRepository` com os métodos públicos de hoje; classe atual vira `FirestoreProfileRepository` (corpo intocado); `profileRepositoryProvider` tipado pela interface; `FakeProfileRepository` e os testes de repositório passam a usar o novo nome. | `git diff -M --color-moved`: só renomes e a interface; `characterization_etapa_7`, `repositories_firestore`, `qa_etapa_4` e `providers_subscriptions` verdes sem editar asserção. Revisão (R). |
| 2 | `refactor(astral): AstralController` | Template do padrão: `birth_datetime.dart` (+ teste puro dos defaults), `astral_controller.dart`, tela chama o controller. Teste de container e widget mínimo. | Snackbar "Preencha a data de nascimento na conta." igual. |
| 3 | `refactor(rituals): RitualsController` | `ritual_day.dart` (`eventsOfDay`), `rituals_controller.dart`, `dayKey` na tela. | Analytics com os mesmos nomes de evento. |
| 4 | `refactor(economy): ShopController e AppUser.isEquipped` | Controller, `isEquipped`, `itemTypeLabel`; `shop_screen` e `inventory_screen` migram. Corpo dos repositórios intocado. | `economy_repository_test`/`qa_etapa_4` verdes; mensagens idênticas. (R) |
| 5a | `refactor(cosmos): daily_content e horóscopo` | `daily_content.dart` (+ testes puros), `CosmosController.ensureHoroscope`; `eventsOfDay`/`dayKey` no cosmos. | Prompt do horóscopo idêntico (teste compara o literal). |
| 5b | `refactor(cosmos): tarô` | `drawTarot` + `drawingTarot`. | Teste do fallback de `complete` falhando. |
| 5c | `refactor(cosmos): check-in` | `checkIn` + `checkingIn`. | Chama `dailyCheckIn(uid:, today:)` com `dayKey(clock())`. (R) |
| 6 | `refactor(oracle): ChatController e ChatRepository` | Interface, `ChatStore implements ChatRepository`, `chatRepositoryProvider`, controller, tela migrada. | Teste de caracterização: número e conteúdo das gravações no prefs fake (mesma chave, mesmo JSON) para 1 mensagem e para nova conversa. |
| 7 | `refactor(account): AccountController` | Busca de amigo e envio de intenção. | Textos idênticos. |
| 8 | `docs: etapa 9` | `overview.md` (controllers, regra `_controller.dart`), backlog e dívidas em `plans/`, `CHANGELOG` (writer). | Links válidos. |

Ordem: da menor/mais isolada (astral, rituals) para as com dinheiro (shop, check-in) e a mais acoplada (oracle). O passo 1 vem antes dos controllers que usam `ProfileRepository` (2, 4, 5, 7).

## 5. Estratégia de testes

- **Puros (sem Riverpod)**: `daily_content`, `eventsOfDay`, `birthDateTimeOf`, `AppUser.isEquipped`, `dayKey` (inclui virada de dia/mês). Em `test/features/<f>/domain/`.
- **Controllers** com `ProviderContainer` e overrides (`test/features/<f>/presentation/<x>_controller_test.dart`): `profileProvider.overrideWith((ref) => Stream.value(user))`, `profileRepositoryProvider` com `FakeProfileRepository` (que passa a `implements` a interface e registra `saveDailyHoroscope/saveDailyTarot/equip/saveAstralMap`), `economyRepositoryProvider` com `FakeEconomyRepository` (registra argumentos, lança `AlreadyCheckedInException`/`InsufficientFundsException`/erro genérico sob comando), `oracleServiceProvider` com `FakeOracleService` (resposta fixa, falha sob comando, `Completer` para controlar a ordem), `chatRepositoryProvider` com `FakeChatRepository` em memória (conta `save`), `analyticsServiceProvider` com `FakeAnalytics` (lista de eventos), `clockProvider` fixo. Manter o autoDispose vivo com `container.listen(provider, (_, __) {})`. Casos mínimos:
  - cosmos: horóscopo gerado e gravado uma vez, não regerado com cache de hoje, não rechamado na 2ª chamada, sem signo não faz nada; tarô com fallback quando `complete` falha, `drawingTarot` true durante e false depois, descartado no meio não grava; check-in feliz, já feito (mensagem da exceção), erro genérico, `checkingIn` impede duplo toque.
  - oracle: hidrata do repositório; `send` vazio/duplo ignorado; título vira o texto da 1ª mensagem; 2 `save` por mensagem e 1 por conversa nova (caracterização); `logEvent` chamado; `takePendingPrompt` limpa o provider; pin do defeito (2) em teste marcado como "comportamento atual".
  - rituals, astral, shop (comprar x equipar, erro de economia, `buying`), inventory (`equip` propaga erro), account (e-mail inexistente, o próprio e-mail, sucesso).
- **Widget tests mínimos** das telas migradas (`ProviderScope` com os mesmos fakes; `pump()` em vez de `pumpAndSettle` porque `Starfield` anima em loop): cosmos (mostra "Olá, <nome>"; toque no check-in exibe o snackbar de sucesso; botão fica desabilitado quando já feito), oracle (toque num chip adiciona a mensagem do usuário e a resposta), shop (toque em "Comprar" chama o fake e mostra o erro de saldo), astral (data vazia mostra o snackbar). Rituals e account entram só com teste de controller.
- Testes antigos (`providers_subscriptions`, `characterization_etapa_7`, `qa_*`) continuam verdes sem editar asserção; só o nome da classe muda no passo 1. Contagem final = P0 + testes novos; nenhum teste removido.

## 6. Decisão: "equipar" fica para depois

Opções: (A) mover `equip` (e `EquipSlot`/sincronização do avatar) de `ProfileRepository` para a economia agora; (B) manter e isolar atrás do `ShopController` (escolhida).

Por que não agora: (1) é a mesma superfície da Opção B pendente do usuário (equipar o avatar gravar `users` e `publicProfiles` na mesma transação, B1 aberto); mover o método antes dessa decisão significaria mexer duas vezes em código de repositório que a etapa promete não alterar. (2) `EconomyRepository` é, por requisito, a interface que isola todo crédito/débito de `wallet`; `equip` não mexe em saldo, então o lugar certo provavelmente é um repositório de cosméticos/inventário novo, e criar repositório novo é decisão de arquitetura com custo de revisão (consultor) que não traz ganho de testabilidade agora. (3) Risco: mexer na economia dentro de uma etapa sobre telas mistura o diff de apresentação com o de dinheiro/inventário. (4) A dívida fica barata de quitar: depois do passo 4 só `ShopController` chama `equip`, e `purchaseItem(equipSlot:)` já está em `EconomyRepository`. A migração futura troca uma dependência dentro do controller, sem tocar telas nem testes de widget.

Registrar na etapa: dívida "equipar" reclassificada de "revisar na etapa 9" para "junto da Opção B (etapa 5/B1), com `reviewer-consultor`".

## 7. Riscos

| Risco | Mitigação |
|---|---|
| Riverpod 2.6 não tem `ref.mounted`: atribuir `state` após o dispose lança erro (o `State.mounted` de hoje evitava isso). | Flag `_alive` virada em `ref.onDispose`; toda escrita de `state` e a gravação pós-`complete` do tarô checam o flag. Teste de "descartado no meio". |
| Mudar o ciclo de vida: `keepAlive` gravaria o tarô/histórico mesmo após sair da tela. | `autoDispose` em todos os controllers com estado. |
| Hidratação do chat: hoje roda uma vez por tela; o controller `autoDispose` recarrega ao reabrir a tela (também hoje, pois o `State` é recriado). | Mesma semântica; teste de reabertura. Se o uid mudar com a tela viva (não acontece: logout redireciona), o controller reinicia em vez de manter o estado de outro usuário. |
| Dois defeitos latentes do chat (seção 3.2) e erros não tratados em horóscopo/equipar do inventário. | Preservados e fixados em teste; dívida registrada. Corrigir só com decisão do planner. |
| Interface do chat por snapshot pode não casar com Firestore. | Aceito: a etapa 10 muda o repositório e o `_persist` do controller, não a tela. Se quiser incremental, fica como 1ª tarefa da etapa 10. |
| Widget tests com `GoogleFonts` (cosmos, astral usam `GoogleFonts.cinzel`) e `Starfield` (animação infinita) no `flutter test`: busca de fonte e `pumpAndSettle` podem falhar. Hoje nenhum teste de widget toca essas telas. | Spike no passo 0. Se a fonte quebrar o teste, helper de teste que ignora o erro de fetch de fonte (`FlutterError.onError` filtrado) ou `GoogleFonts.config.allowRuntimeFetching = false` com fallback; usar `pump(Duration)`. Se não resolver, reduzir os widget tests a shop/oracle e manter cosmos só em controller. |
| Regex de camada (`_controller.dart`) classificar errado arquivos futuros. | Casos de detector e de mutação no teste; um `*_controller.dart` que importe `material` falha o teste. |
| Ciclo cosmos -> rituals/profile/economy. | Só `domain` (rituals, profile) e `providers` (economy, oracle, profile): arestas já permitidas; o DFS do teste confirma. |
| Mudar texto por descuido. | Literais movidos, não reescritos; verificação por grep antes/depois em cada passo. |
| Conflito com trabalho paralelo em `lib/`. | Branch única; avisar para não editar `lib/` durante a etapa. |

## 8. Revisão

Conclusão: **economia: sim; dados pessoais: não, nesta etapa**; arquitetura: sim (nova regra de camada).

- `reviewer-consultor`, **uma passada única** (como no step 8) depois do passo 7, sobre os passos 0, 1, 4 e 5c: (a) arquitetura: regra `_controller.dart` e interfaces; (b) economia: `ShopController` e `checkIn` chamam `purchaseItem`/`dailyCheckIn`/`equip` com os mesmos argumentos, nenhum repositório de economia muda, nenhum novo ponto de escrita em `wallet`/`inventory` (`ProfileRepository` continua sem `Map` público), nenhum ganho de saldo novo; diff vazio em regras, índices e `test_rules/`. Checagem mecânica sugerida: `git diff -M --color-moved` nos corpos de `economy_repository.dart` e `profile_repository.dart` (só rename de classe).
- Dados pessoais: o histórico do chat continua em `shared_preferences` (mesma chave, mesmo JSON) e nada novo é lido, escrito ou enviado; por isso o chat (passo 6) e o resto passam só pelo `reviewer` comum. O gatilho de dado pessoal do chat é da **etapa 10** (Firestore), onde o consultor é obrigatório.
- `reviewer` (Sonnet) revisa cada commit.
- `qa`: caracterização do chat (gravações) e checklist manual curto por tela migrada (mesmos textos, check-in, compra/equipar, mapa astral, ritual) em `docs/qa/etapa-9.md`.
- Escalar ao `planner-consultor` se surgir qualquer ganho de saldo novo ou Blaze (regra geral do plano).

## 9. Fechamento e desvios aceitos

Etapa concluída. Suíte ao fechar: 289 testes; `flutter analyze` sem problemas; `firestore.rules`, `firestore.indexes.json`, `test_rules/`, `pubspec.yaml` e `pubspec.lock` sem diff.

Desvios em relação ao projeto acima:

- `CosmosController.checkIn` devolve `Future<String?>` (mensagem do snackbar ou null), em vez de a tela montar o texto.
- Flag `_alive` (virada em `ref.onDispose`) em todos os controllers com escrita pós-`await`, pois o Riverpod 2.6 não tem `ref.mounted`.
- Os controllers com estado são `autoDispose`; os que não guardam estado de tela (`NotifierProvider` simples) ficam sem `autoDispose`, onde o ciclo de vida não importa.
- `AccountController.addFriendByEmail`: o amigo passa a ser adicionado mesmo se o usuário sair da tela (antes `mounted` abortava entre a busca e o `addFriend`). Aceito pelos revisores; o código não foi mudado.
- Reinício do chat por troca de uid com a tela viva não foi implementado (logout redireciona, então não ocorre hoje).
- `FakeChatRepository` entrou no passo 6 (não no passo 0), junto com a interface `ChatRepository`.
- Helpers extras de teste além dos previstos (`pump_screen` com `tolerateListTileInkAssertion`, `make_container`).
- `ShopController.equip` passou a devolver `bool` (false sem perfil) para o inventário não exibir "equipado" quando nada foi gravado.
- Os dois defeitos latentes do chat (seção 3.2) e o `RangeError` antes da hidratação foram corrigidos no commit `fix(oracle)`, em vez de ficarem como dívida: `loading` é liberado em erro (resposta "Não foi possível obter a resposta. Tente novamente."), a resposta grava na conversa de origem (por id) e o envio antes da hidratação é ignorado.
