# Reestruturação proposta do Astrum

Status: em execução. Etapas 1 a 8 implementadas na branch (a 8 concluída em `step8-feature-first.md`); a etapa 9 em diante segue como plano. As seções 1 a 3 são a análise do estado anterior à etapa 1 e foram mantidas como histórico. Os desvios de execução estão nas notas "Desvio" da seção 4 e na seção 4.1, e os detalhes de cada etapa estão nos `step*.md`. Este documento descreve o plano; o código é a fonte da verdade sobre o estado atual.

Base da análise: `pubspec.yaml`, `firestore.rules`, `firestore.indexes.json`, `firebase.json`, todo `lib/`, `test/`, `test_rules/` e `docs/architecture/`. Tamanho: ~5,1 mil linhas de Dart em `lib/` + testes, 6 arquivos de teste Dart (~250 linhas) e 37 testes de regras (Node, emulador).

## 1. Visão atual

### 1.1 Camadas hoje

| Camada | Onde | Observação |
|---|---|---|
| Front: telas | `lib/screens/<área>/` (auth, home, chat, rituals, astral, account, shop, admin, shell) | `cosmos_screen.dart` (421 linhas) e `admin_screen.dart` (460) são as maiores |
| Front: widgets/tema | `lib/widgets/` (cosmic_scaffold, starfield), `lib/theme/` | pequeno e coeso |
| Front: estado | `lib/providers/app_providers.dart` (único arquivo, 72 linhas) | StreamProviders derivados de `profileProvider` |
| Front: rotas | `lib/app_router.dart` | redirect depende de FirebaseAuth e `profileProvider` |
| "Back" (cliente) | `lib/services/`: `user_repository.dart` (320 linhas), `economy.dart`, `oracle_service.dart`, `chat_store.dart`, `analytics_service.dart`, `public_profile.dart`, `meditation_sounds.dart` | não há camada de domínio; o repositório mistura tudo |
| "Back" (servidor) | `firestore.rules` (380 linhas) | é a única barreira de segurança e de economia |
| Base de dados | Firestore: `users/{uid}` (+ `events`, `friends`, `notifications`, `conversations/messages`), `shop_items`, `publicProfiles`, `analytics_events`, `cristais_propriedades`. Local: SharedPreferences (`astrum.chat.$uid`) | índice composto só para `events` (date, time) |
| Dados estáticos | `lib/data/`: `astrology.dart`, `tarot.dart`, `moon.dart`, `cosmetics.dart` | misturam conteúdo, lógica de domínio e apresentação |
| Modelos | `lib/models/app_user.dart` (206 linhas) | contém `AppUser`, `RitualEvent`, `ChatConversation`, `ChatTurnStored`, `Friend`, `IntentionNotice` |

### 1.2 Fluxo de dados real

- `profileProvider` = `UserRepository.watchProfile()` = `authStateChanges().asyncExpand(users/{uid}.snapshots())`.
- `eventsProvider`, `friendsProvider`, `intentionProvider` dependem de `ref.watch(profileProvider).valueOrNull` (app_providers.dart linhas 39 a 55).
- Telas chamam `ref.read(userRepositoryProvider).<método>` direto (account, astral, cosmos, rituals, shop, inventory, admin, welcome).
- Economia: `economy.dart` (puro, testado) é chamado só dentro das transações de `UserRepository.purchaseItem` e `dailyCheckIn`; as mesmas regras são duplicadas em `firestore.rules` (`isPurchase`, `isCheckin`).

## 2. Problemas e fronteiras borradas (com evidência)

### 2.1 Acesso ao Firebase fora de repositórios

- `lib/screens/admin/admin_screen.dart` linhas 112, 124, 158: `FirebaseFirestore.instance` direto na tela (stream de `analytics_events`, seed de `cristais_propriedades`, publicação do catálogo `shop_items`). A lógica de publicar catálogo (decidir o que preservar de preço/active, desativar itens fora do seed) é regra de negócio dentro de um `State`.
- `lib/screens/auth/login_screen.dart` (38), `welcome_screen.dart` (96), `account_screen.dart` (170): `FirebaseAuth.instance` direto (login, cadastro, logout). O cadastro faz `createUserWithEmailAndPassword` e depois `createProfile` em duas etapas sem compensação: se a segunda falhar, resta uma conta Auth sem perfil.
- `lib/app_router.dart` (23, 25) e `lib/providers/app_providers.dart` (15): o router usa `FirebaseAuth.instance` em vez do `authStateProvider` que já existe. `UserRepository` tem ainda uma terceira inscrição em `authStateChanges()`. São três streams de auth para a mesma informação.
- `lib/services/analytics_service.dart`: instancia Firestore/Auth direto (aceitável, é um serviço, mas sem interface).

### 2.2 `UserRepository` grande demais (320 linhas, 8 responsabilidades)

Perfil (`watchProfile`, `createProfile`, `updateFields`), perfil público (`syncPublicProfile`, `_writePublicProfile`, `rebuildPublicProfiles`), catálogo (`watchShopCatalog`), economia (`purchaseItem`, `dailyCheckIn`), eventos, amigos e busca (`findUserByEmail`, `addFriend`), notificações/intenções, administração (`listUsers`, `rebuildPublicProfiles`).

Sintomas concretos:
- `updateFields(uid, Map<String,dynamic>)` é um "escape hatch" com nomes de campo em string, chamado das telas com caminhos como `'equipped.skin'` (shop_screen.dart) e `{'dailyHoroscope': {...}}` (cosmos_screen.dart 41 e 62). A UI conhece o esquema do Firestore e as regras só são descobertas em tempo de execução.
- Sincronizar `publicProfiles` é um efeito colateral escondido em `updateFields` e `purchaseItem` (`_touchesPublicProfile`): duas gravações separadas e não atômicas (users, depois publicProfiles). Se a segunda falhar, o perfil público fica defasado, sem retry.
- `rebuildPublicProfiles` lê a coleção `users` inteira e grava um por um, sequencialmente: migração pontual morando num repositório de uso diário.

### 2.3 Lógica de negócio em telas

- `cosmos_screen.dart`: gera horóscopo diário (`_ensureHoroscope`), sorteia/interpreta tarot (`_drawTarot`), faz check-in e controla "já fez hoje" via `DateFormat('yyyy-MM-dd')` local. É conteúdo + persistência + decisão de data na UI.
- (Situação na época da auditoria; superado pela etapa 10, o chat agora vive no Firestore.) `oracle_screen.dart` (237 linhas): guarda `_conversations` em estado local, hidrata uma vez do `ChatStore` e regrava a lista inteira a cada mensagem (`_persist`, linha 60). Perde o que for escrito por outro dispositivo e não escala.
- `shop_screen.dart`: decide o campo `equipped.*` a partir do tipo (linha ~110) e a ordem "equipar vs comprar".
- `account_screen.dart`: a lista de intenções (luz, coragem, cura, clareza) mora na tela e é duplicada literalmente em `firestore.rules` (`labelOk`).

### 2.4 Economia e regras: duplicação e acoplamento

- Constantes duplicadas em 3 a 4 lugares sem fonte única: recompensa 25 (`economy.dart`, `firestore.rules` `isCheckin`), saldo inicial 500 (`user_repository.dart`, `firestore.rules` `create`), itens padrão `skin_classic`/`bg_void` (repositório, regras, `AppUser`, `app_providers.dart` fallback, `cosmetics.dart`), intenções (tela + regras). Mudar um valor exige lembrar de editar os outros e o teste de regras.
- `data/cosmetics.dart` mistura: estilos visuais Flutter (`Color`, `SkinStyle`), semente do catálogo com preços (`_baseShopCatalog`, `fullShopCatalog`) e mapeamento de asset. A "fonte de verdade do preço" é o Firestore, mas o seed no código ainda carrega preço, o que confunde.
- `economy.dart` contém tanto lógica pura quanto o modelo do catálogo (`CatalogEntry`) e exceções de UI com texto em português (`message`).

### 2.5 Dados estáticos misturados com domínio

`data/astrology.dart` tem listas (signos, elementos, glifos), mas também lógica de cálculo (`sunSignFromDate`, `computeNatalChart`, sinergia) e `defaultProfilePictureId`, que é regra de loja/perfil. `data/moon.dart` calcula a lua do dia. Tudo isso é domínio puro e testável, mas está em `data/`, o que sugere "dados" quando é "conteúdo + algoritmos".

### 2.6 Custo de leituras e streams

- Re-assinatura em cascata (relevante): `eventsProvider`, `friendsProvider` e `intentionProvider` fazem `ref.watch(profileProvider).valueOrNull`. Como `profileProvider` emite a cada mudança em `users/{uid}` (saldo, check-in, horóscopo, equipar item), os três providers são recriados e cancelam/reabrem seus listeners a cada emissão. Cada reabertura de `events` e `friends` relê todos os documentos (a menos que haja cache local servindo, o que não deve ser contado como garantia). Correção simples: `ref.watch(profileProvider.select((p) => p.valueOrNull?.uid))` (e `notificationsEnabled` no caso de `intentionProvider`).
- `app_router.dart` incrementa `profileRefresh` a cada emissão de perfil, reavaliando o `redirect` à toa. Basta escutar `isAdmin`/`isLoading`.
- Regras com leituras cobradas: `isAdmin()` faz `exists` + `get` em `users/{uid}`; equipar item e criar notificação fazem `get` adicional. Cada `get` em regra conta como leitura. É barato hoje, mas todo `update` de `users` com `equipped` custa 1 a 3 leituras extras de regra.
- Admin: `analytics_events` com `limit(500)` e `snapshots()` relê até 500 documentos a cada abertura da tela; `listUsers` lê 80 usuários sem paginação.
- `analytics_events`: criação permitida até para usuário não logado (`userId == 'anonymous'`), sem limite de frequência e sem expiração. Crescimento ilimitado e vetor de abuso de escrita (custo e cota do plano gratuito).
- Persistência offline: não há configuração explícita (`Settings`). No mobile o cache é ligado por padrão; na web, não. Vale decidir conscientemente.

### 2.6.1 Testes e testabilidade

- Testes Dart cobrem só lógica pura (economy, astrology, oracle local, public_profile, meditation_sounds). Não há teste de repositório, de provider ou de tela (`widget_test.dart` tem 12 linhas).
- Não há interfaces; `UserRepository` aceita `FirebaseFirestore`/`FirebaseAuth` no construtor (bom), mas os providers constroem a classe concreta e as telas a usam concreta. (Na época, `ChatStore` aceitava `SharedPreferences` por construtor; removido na etapa 10.)
- Os 37 testes de regras (`test_rules/firestore.rules.test.mjs`) são o ativo mais valioso do projeto, mas rodam só manualmente (`npm test` com emulador); não há CI (`.github` não existe).
- O esquema do documento `users/{uid}` é parseado à mão em três lugares (`AppUser.fromFirebase`, `purchaseItem` com casts de `Map`, `dailyCheckIn`, `syncPublicProfile`, `rebuildPublicProfiles`).

### 2.7 Divergências entre documentação e código

`docs/architecture/chat-sync.md` está "proposto", mas `firestore.rules` já contém as regras de `conversations/messages` (sem cliente que as use) e o app ainda grava o chat em SharedPreferences. `overview.md` está curto e desatualizado (não cita `shop_items`, `publicProfiles`, `analytics_events`, `cristais_propriedades`, nem a política de economia).

## 3. Avaliação de risco: economia validada só pelas regras

O que as regras garantem hoje (e é bem feito): check-in +25 exato, uma vez por data crescente (janela UTC ±1 dia); compra com preço lido de `shop_items` e saldo novo exato; item novo único e no fim da lista; sem delete de perfil; `role` imutável; equipar exige posse e tipo do catálogo; formato fechado de campos. Isso fecha os abusos mais baratos (editar saldo, auto-conceder itens pagos).

Limites reais e o que acontece quando crescerem:

1. Só é possível validar o que é função do documento antigo e do novo. Regras não conseguem: contar eventos no tempo, aplicar limite de taxa, validar origem de um ganho ("completou meditação de 10 min"), ou agregar entre documentos além de `get`/`getAfter`. Hoje o único ganho de saldo é o check-in diário, que as regras sabem verificar. A partir do momento em que existir outro ganho (recompensa por ritual, meditação, missões, indicação de amigo), as regras só poderão validar o valor, não o fato. O cliente poderá se conceder o prêmio quantas vezes quiser.
2. O admin é cliente: o preço e `active` dos itens existentes dependem do app do admin (risco já registrado no cabeçalho das regras). Conta admin comprometida = catálogo adulterado (preço 0). O papel `admin` é atribuído no console, bom, mas não há segundo fator nem auditoria.
3. Não há aceite de amizade: a lista `friends/` é autodeclarada pelo remetente, então qualquer usuário logado pode enviar "intenções" a qualquer outro usuário cujo uid conheça (basta o uid; busca por hash de e-mail o expõe) e gerar spam de notificações, sem limite de frequência.
4. Sem App Check: qualquer cliente com a API key pública (que é pública por desenho) pode falar com o Firestore fora do app. As regras seguram, mas abuso de volume (analytics anônimo, notificações) só é contido com App Check.
5. Exclusão de conta (LGPD) está bloqueada por `allow delete: if false` no perfil e não há fluxo no app. É uma pendência de produto/legal, não só técnica: apagar `users/{uid}` com subcoleções exige cascata no cliente (ou Function).
6. Compra de itens com `price: 0` e check-in por janela UTC ±1 não geram ganho acima de 1 por dia, mas qualquer mudança futura de regra exige mexer em regras, `economy.dart` e testes em paralelo: risco de regressão por esquecimento.

Veredito: manter regras agora é correto e proporcional (moeda sem valor monetário, único ganho é o check-in, tudo validável). O gatilho para migrar para Cloud Functions (plano Blaze, exige cartão; a cota gratuita costuma bastar para esta escala) é qualquer um destes: (a) Poeira Estelar passar a ser vendida por dinheiro real (IAP) ou ter valor transferível; (b) surgir um segundo meio de ganhar saldo; (c) surgir troca/presente de itens entre usuários; (d) ranking competitivo; (e) necessidade de excluir conta com cascata server-side. Até lá, o ganho concreto está em: App Check, TTL em `analytics_events`, centralizar constantes e cobrir regras com CI. Ver seção 6.

## 4. Estrutura-alvo (feature-first leve)

Princípios: 5 mil linhas não justificam clean architecture completa (use cases, mappers DTO/entidade em todo lugar). Proposta: feature-first com 3 pastas internas só quando há necessidade real (`data` = repositório Firestore, `domain` = lógica pura/modelos, `presentation` = telas/widgets/providers de UI). Sem classes de use case; lógica pura vira funções ou classes pequenas em `domain/`.

```
lib/
  main.dart
  app/
    app.dart                  # AstrumApp (MaterialApp.router), tela "configure o Firebase"
    router.dart               # routerProvider, redirect por AuthState/isAdmin (sem FirebaseAuth.instance)
    shell/main_shell.dart
  core/
    config/env.dart
    firebase/
      firebase_providers.dart # firestoreProvider, firebaseAuthProvider, prefsProvider
      firestore_paths.dart    # nomes de coleções e helpers (users, shop_items, ...)
    theme/                    # astrum_theme.dart, astrum_colors.dart
    widgets/                  # cosmic_scaffold.dart, starfield.dart
    util/date_keys.dart       # yyyy-MM-dd (único lugar de formatar data de check-in/diário)
  features/
    auth/
      data/auth_repository.dart        # signIn, register, signOut, authStateChanges
      presentation/{login,register,welcome}_screen.dart, auth_providers.dart
    profile/
      domain/app_user.dart             # AppUser + parse único (fromDoc)
      data/profile_repository.dart     # watch, create, updatePreferences, setEquipped, saveDaily*
      data/public_profile_sync.dart    # users + publicProfiles em WriteBatch
      presentation/account_screen.dart, profile_providers.dart
    economy/                           # loja + inventário + check-in
      domain/economy.dart              # lógica pura (computePurchase/CheckIn), constantes
      domain/catalog_entry.dart
      data/economy_repository.dart     # purchaseItem, dailyCheckIn (transações)
      data/catalog_repository.dart     # watchCatalog
      data/catalog_seed.dart           # lista local usada só pelo admin para publicar
      presentation/{shop,inventory}_screen.dart, economy_providers.dart   # cosmetics_style.dart: theme/ na etapa 7, core/theme/ na etapa 8 (ver 4.1)
    oracle/
      domain/oracle_service.dart       # respostas locais (puro)
      domain/chat_models.dart          # ChatConversation, ChatMessage
      data/chat_repository.dart        # Firestore (D9) + legacy_chat_store.dart (prefs, só migração)
      presentation/oracle_screen.dart, chat_providers.dart
    cosmos/                            # tela inicial
      domain/{moon,tarot}.dart          # astrology.dart virou core/astro/ (etapa 7)
      data/daily_content_repository.dart   # horóscopo/tarô do dia (parte de profile, ou em profile)
      presentation/cosmos_screen.dart, cosmos_controller.dart
    rituals/
      domain/ritual_event.dart
      data/events_repository.dart
      data/meditation_sounds.dart
      presentation/{rituals_screen,meditation_sheet}.dart
    social/
      domain/{friend,intention}.dart   # lista de intenções única
      data/social_repository.dart      # friends, findUserByEmail, notifications
      presentation/ (widgets de amigos/intenção extraídos de account_screen)
    astral/
      presentation/astral_screen.dart
    admin/
      data/admin_repository.dart       # listUsers, publishCatalog, rebuildPublicProfiles, analytics query
      presentation/admin_screen.dart
    analytics/
      analytics_service.dart
test/
  features/<feature>/...               # espelha lib/
  support/fakes.dart                   # fakes de repositórios
test_rules/                            # inalterado; rodar em CI
```

Notas da estrutura:
- Mover não é obrigatório de uma vez: dá para iniciar só criando `core/` e quebrando o repositório, deixando `screens/` onde está (ver etapas).
- Perfil + conteúdo diário: o horóscopo/tarô do dia são campos de `users/{uid}`; a gravação fica em `ProfileRepository` com métodos tipados (`saveDailyHoroscope`, `saveDailyTarot`), e a regra "gerar se não for de hoje" vira um controller/provider em `cosmos/`.
- Repositórios por agregado: `AuthRepository`, `ProfileRepository`, `EconomyRepository`, `CatalogRepository`, `EventsRepository`, `SocialRepository`, `ChatRepository`, `AdminRepository`. `UserRepository` desaparece no final.
- Interfaces: criar `abstract interface class` apenas para o que será trocado em teste ou deve ter fronteira clara: `AuthRepository`, `ProfileRepository`, `EconomyRepository`, `ChatRepository`. Os demais podem usar a classe concreta e ser substituídos nos testes por fakes que `implements` a classe (Dart permite). Não criar interface "por padrão".
- Modelos: um arquivo por modelo, parse centralizado (`AppUser.fromDoc`, usado por `watch`, `listUsers`, transações), eliminando os casts repetidos.
- Constantes de domínio de economia (`checkInReward`, `initialStardust`, itens padrão, ids de intenção) em `economy/domain` e `social/domain`, com comentário apontando para o trecho equivalente em `firestore.rules`. Não existe como gerar regras a partir de Dart sem tooling; a defesa é um teste de regras que lê os valores (ou uma checklist) e o CI.
- Roteador: manter go_router; ajustar para ler `authStateProvider` e um `routerStateProvider` derivado (`isLoggedIn`, `isAdmin`, `isLoading`) via `ref.listen` + `select`, sem `FirebaseAuth.instance`. Senha no `extra` de `/welcome` (router, linha ~58) é evitável: ao registrar, guardar o rascunho no provider (`StateProvider`) e passar só o necessário; não persiste em disco, risco baixo, mas é dado sensível trafegando por estado de navegação.

### 4.1 Desvios da execução (etapas 1 a 7)

A árvore acima é o alvo original. Ao executar, algumas decisões mudaram o destino de arquivos ou nomes. Os motivos estão em `step7-data-models.md` (seção 2 e 9). O texto original acima foi mantido.

| Proposta original | O que foi feito | Por quê | Destino final |
|---|---|---|---|
| `cosmos/domain/astrology.dart` | `core/astro/{zodiac,natal_chart,synergy}.dart` | signos, mapa natal e sinergia são usados por auth, perfil, economia, social, astral, cosmos, oráculo e admin; em `cosmos/` criariam dependência de quase todas as features para a home | fica em `core/astro/` |
| `economy/presentation/cosmetics_style.dart` | `theme/cosmetics_style.dart` (etapa 7); `core/theme/` na etapa 8 | `CosmicScaffold` (widget transversal) usa o estilo; no tema evita `core -> features` | `core/theme/cosmetics_style.dart` (a etapa 8 move `theme/` inteiro) |
| constantes de economia em `economy/domain` e intenções em `social/domain` | `core/firebase/rules_contract.dart`, um único contrato com comentário por regra | um único arquivo de regras pede um único contrato, fácil de conferir; `test/rules_contract_test.dart` detecta divergência | fica em `core/firebase/` |
| `social/domain/{friend,intention}.dart` | `models/friend.dart` e `models/intention_notice.dart` (nome do arquivo de intenção mudou para `intention_notice.dart`) | um arquivo por modelo; a pasta de feature ainda não existe | `features/social/domain/` (etapa 8) |
| `data/catalog_seed.dart` em `economy/data/` | `lib/data/catalog_seed.dart` | pasta de feature ainda não existe | `features/economy/data/` (etapa 8) |
| `CatalogEntry` em `economy/domain/` | `models/catalog_entry.dart` (saiu de `services/economy.dart`) | um arquivo por modelo | `features/economy/domain/` (etapa 8) |
| (não estava na proposta) `profile_pictures.dart` | `lib/data/profile_pictures.dart` | junta variantes, id padrão e caminho do asset, antes espalhados em `astrology.dart` e `cosmetics.dart` | `features/economy/domain/` (etapa 8, `step7-data-models.md` seção 5) |
| (não estava na proposta) `ItemType`, `ShopItem` | `models/shop_item.dart` | saiu de `data/cosmetics.dart` | `features/economy/domain/` (etapa 8) |
| `AppUser.fromDoc` e `CatalogRepository.watchCatalog` | ainda `AppUser.fromFirebase` e `CatalogRepository.watchShopCatalog` | renomes são o passo 8 da etapa 7, opcional; não feito | renome pendente, sem mudança de comportamento |

## 5. Manter / ajustar / trocar

| Componente | Recomendação | Justificativa | Custo/risco |
|---|---|---|---|
| Riverpod 2.6 | Manter (ajustar uso) | Funciona bem. O problema não é a lib e sim `watch` em objeto inteiro sem `select`. Riverpod 3 (disponível, 3.5.0) é migração opcional: mudanças de API (Notifier, retry automático, pausar providers) e sem ganho funcional hoje | Ajustar: baixo. Subir major: médio, adiar |
| go_router 14 | Manter (ajustar redirect) | Rotas simples, `StatefulShellRoute` já em uso. Trocar não tem ganho. Há versão 18 disponível; subir major só junto com revisão geral de dependências | Ajuste: baixo. Upgrade: baixo/médio |
| Firebase Auth | Manter | E-mail/senha cobre o caso, sem custo. Extrair `AuthRepository`, tratar rollback de cadastro, avaliar verificação de e-mail/recuperação de senha (não existe hoje) | Baixo |
| Cloud Firestore | Manter | Modelo de dados adequado (docs por usuário, subcoleções). Ajustes: `select` nos providers, batch atômico para `publicProfiles`, TTL e App Check em `analytics_events`, paginação no admin | Baixo |
| Cloud Functions | Não adicionar agora; adotar quando houver gatilho (seção 3) | Exige plano Blaze e novo código/deploy em Node/TS (outra linguagem, outro pipeline). Hoje as regras cobrem o único ganho de saldo. Preparar o terreno isolando a economia em `EconomyRepository` (trocável por chamada `httpsCallable` sem mexer nas telas) | Hoje 0; futuro: médio |
| Regras do Firestore | Manter e reforçar | Bem escritas e testadas. Rodar `test_rules` em CI; centralizar constantes; considerar App Check; documentar o gatilho de migração | Baixo |
| shared_preferences | Manter só para preferências locais; tirar o chat daqui | Chat em prefs perde histórico ao trocar de dispositivo, reescreve tudo a cada mensagem e já tem regras prontas no Firestore (D9). Prefs continua ótimo para flags locais | Baixo (migração de chat tem risco de dados; ver D9) |
| Oráculo local | Manter, isolar | `oracle_service.dart` é puro e testado; deixar atrás de uma interface simples (`OracleService.complete`) já resolve; trocar por IA externa é decisão de produto/custo/privacidade (chave em cliente é inseguro; exigiria Function/proxy) | Nenhum agora |
| Dependências auxiliares | Manter; revisar `flutter_markdown` | `flutter_markdown` foi descontinuado pelo time do Flutter; confirmar com `flutter pub outdated`/pub.dev e planejar substituição quando houver necessidade. `crypto`, `uuid`, `intl`, `audioplayers`, `flutter_tts`, `google_fonts` ok | Baixo |
| Firebase (core/auth/firestore) versões | Planejar upgrade em etapa dedicada | `flutter pub outdated`: cloud_firestore 5.6.12 -> 7.1.0, firebase_auth 5.7.0 -> 7.0.1, firebase_core 3.15.2 -> 5.1.0 (2 majors atrás). Hoje funciona; atrasar muito aumenta o custo. Fazer depois do refactor, com a suíte verde, em branch própria | Médio (APIs e plataformas) |
| Estrutura por camada | Trocar para feature-first leve | Ver seção 4; ganho de coesão e navegabilidade sem custo de abstração | Médio (mover arquivos), mecânico |
| Firebase App Check | Adicionar | Gratuito, reduz abuso fora do app (analytics, notificações). Precisa de provedor por plataforma (Play Integrity, DeviceCheck/App Attest, reCAPTCHA na web) | Médio (config por plataforma); ativar em modo "monitorar" antes de impor |
| Testes/CI | Ajustar | Criar CI (analyze, test, rules emulator). Hoje só há testes de lógica pura | Baixo |

Não recomendado trocar: Riverpod por Bloc, go_router por auto_route, Firestore por outro backend, Auth por outro provedor. Nenhum tem ganho concreto proporcional ao custo.

## 6. Plano de migração incremental

Cada etapa é um PR pequeno; ao final de cada uma `flutter analyze` e `flutter test` devem passar (e `npm test` em `test_rules/` nas etapas que tocarem regras). Responsáveis: builder implementa, reviewer revisa; etapas marcadas (R) passam também pelo `reviewer-consultor`.

1. Rede de segurança. Criar CI (GitHub Actions: `flutter analyze`, `flutter test`, e job do emulador com `test_rules`). Adicionar teste de widget mínimo (app sobe sem Firebase mostrando a tela de configuração). Sem mudança em `lib/`.
2. Correções de custo sem mover arquivos. `select` em `eventsProvider`, `friendsProvider`, `intentionProvider` (só uid/`notificationsEnabled`); router escuta apenas o que muda (`isAdmin`, `isLoading`); router usa `authStateProvider`. Teste: provider não recria o stream quando só o saldo muda (usando repositório fake).
3. Providers de infraestrutura. Criar `firebaseAuthProvider`, `firestoreProvider`; `UserRepository`, `AnalyticsService` recebem por provider. Elimina `FirebaseAuth.instance` do router e dos providers. Mover `core/` (config, theme, widgets) se desejado; só renomear imports.
4. Quebrar `UserRepository` (sem mudar comportamento). Extrair, na ordem: `EventsRepository`, `SocialRepository` (friends, busca, notificações), `CatalogRepository`, `EconomyRepository` (purchase e check-in), `ProfileRepository`, `AdminRepository`. Um PR por repositório, mantendo providers e assinaturas; `UserRepository` encolhe até sumir. (R na parte de economia, por tocar saldo/inventário.)
5. (Implementada; ver `step5-typed-writes.md`.) Tipar as escritas. Substituir `updateFields(Map)` por métodos nomeados (`setEquipped(type, id)`, `saveDailyHoroscope`, `saveDailyTarot`, `updatePreferences`, `saveAstralMap`). Telas deixam de conhecer caminhos de campo. Perfil público sincronizado em `WriteBatch` com `users` quando possível, ou com retry/`syncPublicProfile` explícito. (R: dados de usuário.)
6. Tirar Firebase das telas restantes. `AuthRepository` (login, cadastro com rollback do usuário Auth se `createProfile` falhar, logout) e `AdminRepository` (publicar catálogo, seed de cristais, stream de analytics). Telas só usam providers. Teste de `publishCatalog` com a lógica de merge extraída para função pura. (R: autenticação.)
7. Separar `data/` e `models/`. `models/app_user.dart` dividido por modelo; `AppUser.fromDoc` único (na etapa 7 o método ainda se chama `fromFirebase`; o renome é o passo 8, opcional, não feito); `data/cosmetics.dart` em `cosmetics_style.dart` (UI) + `catalog_seed.dart`; `astrology` em `core/astro/{zodiac,natal_chart,synergy}.dart` (+ `profile_pictures.dart`) e `moon/tarot` para `cosmos/domain`; `cosmetics_style.dart` em `theme/` (depois `core/theme/`); `economy.dart` separa `CatalogEntry` das exceções. Constantes de economia e intenções em um lugar (`core/firebase/rules_contract.dart`, com teste de divergência contra `firestore.rules`) e comentário apontando para as regras. Implementada em `step7-data-models.md`; destinos finais da etapa 8 na seção 5 desse documento.
8. Mover para feature-first. Mover arquivos por feature (auth, profile, economy, oracle, cosmos, rituals, social, astral, admin) em PRs separados, um por feature, só com mudança de caminho e imports. Roteador para `app/router.dart`.
9. Controllers das telas pesadas. Extrair de `cosmos_screen.dart` e `oracle_screen.dart` a lógica (horóscopo do dia, tarô, check-in, envio de mensagem) para `Notifier`/`AsyncNotifier` testáveis com repositórios fake. Interfaces `abstract interface class` só para Auth/Profile/Economy/Chat.
10. Chat no Firestore (D9, já com regras prontas). Implementar `ChatRepository` conforme `chat-sync.md`, migração do legado de prefs, `OracleScreen` observando streams. (R: dado pessoal sensível.)
11. Higiene de custo e abuso. TTL (campo `expireAt`, política de TTL no console) em `analytics_events`; paginação em `listUsers`; considerar rate limit do analytics por regra básica; ativar App Check em modo monitor e depois enforcement. Qualquer mudança em `firestore.rules` com teste novo em `test_rules/`. (R: regras.)
12. Atualização de dependências Firebase/Riverpod/go_router em branch própria, uma família por vez (Firebase primeiro), com a suíte verde e verificação manual em cada plataforma (Android, iOS, web). Decidir sobre Riverpod 3 só se houver motivo.
13. Decisões de produto pendentes que destravam trabalho de backend: exclusão de conta (LGPD), aceite de amizade, e gatilhos de migração para Cloud Functions (seção 3). Cada uma gera seu próprio documento de arquitetura antes de implementar.

Ordem de valor: 1, 2 e 3 trazem ganho imediato com risco mínimo; 4 a 6 resolvem o maior débito estrutural; 7 a 9 organizam; 10 a 13 são evolução.

## 7. Perguntas em aberto para o usuário

1. A Poeira Estelar terá valor monetário (venda por IAP, saques, troca entre usuários) ou novos modos de ganhar saldo além do check-in? Se sim, quando? Isso define se Cloud Functions (plano Blaze) entra no roadmap.
2. Aceita adotar o plano Blaze (cartão cadastrado, com alerta de orçamento) se Functions virar necessário? Ou o projeto deve permanecer estritamente no plano gratuito?
3. O app terá versão web em produção? (Impacta App Check/reCAPTCHA, persistência offline do Firestore e cache de leituras.)
4. Amizade deve passar a ter aceite do destinatário (mudança de modelo e regras) ou a lista autodeclarada continua aceitável?
5. Exclusão de conta (LGPD): prioridade e escopo (apagar `users/{uid}` e subcoleções, `publicProfiles`, notificações enviadas)? Hoje as regras proíbem delete de perfil.
6. O histórico do oráculo deve sincronizar entre dispositivos (D9) ou continuar só local? Se for sincronizar, confirmar as decisões pendentes de `chat-sync.md`.
7. O oráculo permanecerá 100% local? Se IA externa for planejada, exige proxy/Function (não colocar chave no cliente).
8. Preferência para a migração: fazer tudo de uma vez em branch dedicada (mais rápido, mais risco) ou por PRs pequenos como proposto? E há intenção de subir as versões do Firebase (2 majors atrás) antes ou depois do refactor?
9. Quanto de rigor de testes se espera nas telas (widget tests) versus só em lógica e repositórios?
