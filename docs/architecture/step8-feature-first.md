# Etapa 8: mover para feature-first leve

Status: passos 0 a 13 implementados (um commit por passo); passos 14 (espelhar testes) e 15 (docs) pendentes. Refatoração pura: nenhum comportamento, valor, texto de tela, regra ou índice muda. `firestore.rules`, `firestore.indexes.json`, `test_rules/` e `pubspec.yaml` ficam sem diff. Plano Spark inalterado (zero dependência nova, zero leitura nova). A única mudança que não é só "caminho + import" é a divisão de `lib/providers/app_providers.dart` por feature (seção 4); ela move declarações sem alterar o corpo e é explicada lá.

Base: `restructuring.md` (seção 4 e etapa 8 da seção 6), `step7-data-models.md` (seção 5), `step4-repositories.md`, `step5-typed-writes.md`, `step6-auth.md`, `docs/plans/reestruturacao-etapas-1-a-3.md` (backlog), `git ls-files lib test` (60 arquivos em `lib/`, 25 em `test/`) e grep de todos os imports. Os mapas e as regras abaixo foram validados numa cópia da árvore: aplicados os movimentos da seção 3 com a ferramenta da seção 6, todos os `package:astrum/...` resolvem e as regras da seção 5 acusam apenas o monolito `app_providers.dart` (que a seção 4 elimina).

## 1. Decisões

| Tema | Decisão | Por quê |
|---|---|---|
| Estilo de import | `package:astrum/...` em todo o `lib/` (inclusive entre irmãos). Passo 0 converte tudo antes de mover. O teste de fronteira proíbe import relativo em `lib/`. | (1) Com feature-first os relativos viram `../../../core/...`, frágeis a qualquer movimento. (2) A fronteira vira regex sobre caminho de pacote, sem resolver `../`; hoje o teste de `core` já proíbe `../` por esse motivo. (3) `test/` já usa `package:astrum/` em 100% dos casos (só `support/` é relativo), então o projeto passa a ter um único estilo. (4) Mover um arquivo só altera os imports que apontam para ele, não os imports dele para o que não mudou. O guia de estilo do Dart prefere relativo dentro de `lib/`; aqui há ganho concreto e o `flutter_lints` não tem regra contra. Custo: um commit mecânico (cerca de 150 linhas em 45 arquivos), verificável porque o analyzer acusa o que faltar. |
| Raízes de `lib/` | `app/`, `core/`, `features/`, mais `shared/` (nova, ver abaixo) e `main.dart` | `shared/` existe porque `CosmicScaffold` (usado por 8 telas) lê estado de perfil, social e economia: não pode ir para `core/` (core não importa features) e, se morasse numa feature, criaria ciclo com as outras. |
| Subpastas | `domain/`, `data/`, `presentation/` só quando têm arquivo. Providers do Riverpod ficam em `presentation/` com nome `*_providers.dart` (ou `sign_up_provider.dart`, nome atual mantido). | Segue `restructuring.md`. Seeds estáticos puros são `domain/`; `data/` é só acesso a Firestore/prefs/áudio. |
| `app_providers.dart` | Dividido por feature, um grupo por commit de feature, e apagado no fim. Sem re-export. | Sem isso toda tela importa um arquivo que importa todos os repositórios e nenhuma fronteira é possível. É mover blocos de 3 a 10 linhas sem editar. |
| Testes | Espelhar só os testes cujo sujeito é um único arquivo/feature (9 arquivos), em commit próprio e opcional no fim. Testes transversais ficam em `test/` (seção 7). | Custo baixo e risco nulo; espelhar tudo forçaria partir testes `qa_etapa_*` que cobrem várias features. |
| `reviewer-consultor` | Uma passada única no conjunto (seção 9). | Gatilho "arquitetura" do `CLAUDE.md`. |

### 1.1 Desvios do `restructuring.md` e do `step7` (todos por evitar ciclo ou dependência indevida)

| Original | Agora | Motivo |
|---|---|---|
| `cosmos/domain/{moon,tarot}.dart` | `core/astro/{moon,tarot}.dart` | `oracle_service` (oracle) usa os dois e `cosmos_screen` usa o oráculo: em `cosmos/` haveria ciclo cosmos <-> oracle. São conteúdo esotérico transversal, como `zodiac`. Continuam sem Flutter. |
| `rituals/{data/meditation_sounds,presentation/meditation_sheet}` | `cosmos/data/meditation_sounds.dart` e `cosmos/presentation/meditation_sheet.dart` | Só `cosmos_screen` abre a meditação; em `rituals/` a home dependeria de uma tela de outra feature. `rituals` fica só com eventos e sem dependências. |
| `economy/data/catalog_seed.dart` | `economy/domain/catalog_seed.dart` | É Dart puro estático e `admin_screen` o usa (admin -> economy deve ser só domain). |
| `economy/data/equip_slot_field.dart` (step7) | `economy/domain/equip_slot_field.dart` | Extensão pura sobre `EquipSlot`; `profile_repository` a usa, e profile -> economy deve ser só domain. |
| `core/theme/cosmetics_style.dart` (step7) | `shared/cosmetics_style.dart` | Importa `ItemRarity` (economy/domain) para `rarityColor`; em `core/` violaria core -> feature. Mora ao lado do consumidor, `CosmicScaffold`. |
| `analytics/analytics_service.dart` (feature) | `core/analytics/{analytics_service,analytics_providers}.dart` | Infra transversal, sem domínio nem tela, usada por auth, oracle e rituals. Como feature criaria 3 arestas sem ganho. |
| `authStateProvider`, `currentUidProvider` em `app_providers` | `core/firebase/session_providers.dart` | profile precisa de auth e auth precisa de profile (rollback do cadastro); no core o ciclo desaparece. |
| `prefsProvider` em `app_providers` | `core/storage/prefs_providers.dart` | Provider genérico de infra (hoje só o chat o usa, mas `main.dart` o sobrescreve). |
| `public_profile.dart` (services) | `profile/domain/public_profile.dart` | Funções puras de limite de campos. |
| `AstrumApp` em `main.dart` | `app/app.dart` (a classe move sem editar; `main()` fica em `main.dart`) | Conforme `restructuring.md`; `widget_test.dart` passa a importar `app/app.dart`. |

## 2. Árvore final

```
lib/
  main.dart                              # main(): prefs, Firebase.initializeApp, ProviderScope
  app/
    app.dart                             # AstrumApp (MaterialApp.router / tela "configure o Firebase")
    router.dart                          # routerProvider, decideRedirect, routerProfileKeyProvider
    shell/main_shell.dart
  core/
    config/env.dart
    firebase/                            # firebase_providers, firestore_paths, rules_contract, session_providers (novo)
    storage/prefs_providers.dart         # novo
    analytics/                           # analytics_service, analytics_providers (novo)
    astro/                               # zodiac, natal_chart, synergy, moon, tarot   (Dart puro)
    theme/                               # astrum_colors, astrum_theme
    widgets/starfield.dart
  shared/                                # UI transversal que lê estado de features
    cosmic_scaffold.dart
    cosmetics_style.dart
    equipped_cosmetics_providers.dart    # equippedSkinProvider, equippedBackgroundProvider
  features/
    auth/
      domain/    auth_exception, sign_up_data
      data/      auth_repository
      presentation/ auth_providers (authRepositoryProvider), sign_up_provider, login_screen, register_screen, welcome_screen
    profile/
      domain/    app_user, public_profile
      data/      profile_repository, public_profile_sync
      presentation/ profile_providers (profileProvider, profileRepositoryProvider, publicProfileSyncProvider), account_screen
    economy/
      domain/    shop_item, catalog_entry, catalog_seed, equip_slot, equip_slot_field, profile_pictures, economy, economy_exceptions
      data/      economy_repository, catalog_repository
      presentation/ economy_providers (economyRepositoryProvider, catalogRepositoryProvider, shopCatalogProvider), shop_screen, inventory_screen
    oracle/
      domain/    chat_models, oracle_service
      data/      chat_store
      presentation/ oracle_providers (oracleServiceProvider, chatStoreProvider, pendingOraclePromptProvider), oracle_screen
    cosmos/
      data/      meditation_sounds
      presentation/ cosmos_screen, meditation_sheet
    rituals/
      domain/    ritual_event
      data/      events_repository
      presentation/ rituals_providers (eventsRepositoryProvider, eventsProvider), rituals_screen
    social/
      domain/    friend, intention_notice
      data/      social_repository
      presentation/ social_providers (socialRepositoryProvider, friendsProvider, intentionProvider)   # sem telas ainda
    astral/
      presentation/ astral_screen
    admin/
      data/      admin_repository, crystal_seed
      presentation/ admin_providers (adminRepositoryProvider), admin_screen
```

Somem: `lib/config`, `lib/data`, `lib/models`, `lib/providers`, `lib/screens`, `lib/services`, `lib/theme`, `lib/widgets`, `lib/app_router.dart`.

## 3. Tabela: arquivo atual para destino (todos `git mv`)

Cada linha é uma linha do mapa `moves_all.txt` (seção 6); a coluna Passo diz em que commit a linha entra.

| Atual (`lib/`) | Destino (`lib/`) | Passo |
|---|---|---|
| `config/env.dart` | `core/config/env.dart` | 1 |
| `theme/astrum_colors.dart`, `theme/astrum_theme.dart` | `core/theme/` | 1 |
| `widgets/starfield.dart` | `core/widgets/starfield.dart` | 1 |
| `data/moon.dart`, `data/tarot.dart` | `core/astro/` | 1 |
| `services/analytics_service.dart` | `core/analytics/analytics_service.dart` | 1 |
| `screens/astral/astral_screen.dart` | `features/astral/presentation/` | 3 |
| `models/ritual_event.dart` | `features/rituals/domain/` | 4 |
| `services/events_repository.dart` | `features/rituals/data/` | 4 |
| `screens/rituals/rituals_screen.dart` | `features/rituals/presentation/` | 4 |
| `models/chat_models.dart`, `services/oracle_service.dart` | `features/oracle/domain/` | 5 |
| `services/chat_store.dart` | `features/oracle/data/` | 5 |
| `screens/chat/oracle_screen.dart` | `features/oracle/presentation/` | 5 |
| `services/admin_repository.dart`, `data/crystal_seed.dart` | `features/admin/data/` | 6 |
| `screens/admin/admin_screen.dart` | `features/admin/presentation/` | 6 |
| `models/friend.dart`, `models/intention_notice.dart` | `features/social/domain/` | 7 |
| `services/social_repository.dart` | `features/social/data/` | 7 |
| `screens/home/cosmos_screen.dart`, `screens/rituals/meditation_sheet.dart` | `features/cosmos/presentation/` | 8 |
| `services/meditation_sounds.dart` | `features/cosmos/data/` | 8 |
| `models/auth_exception.dart`, `models/sign_up_data.dart` | `features/auth/domain/` | 9 |
| `services/auth_repository.dart` | `features/auth/data/` | 9 |
| `providers/sign_up_provider.dart`, `screens/auth/{login,register,welcome}_screen.dart` | `features/auth/presentation/` | 9 |
| `models/app_user.dart`, `services/public_profile.dart` | `features/profile/domain/` | 10 |
| `services/profile_repository.dart`, `services/public_profile_sync.dart` | `features/profile/data/` | 10 |
| `screens/account/account_screen.dart` | `features/profile/presentation/` | 10 |
| `models/{shop_item,catalog_entry,equip_slot}.dart`, `data/{profile_pictures,catalog_seed}.dart`, `services/{economy,economy_exceptions,equip_slot_field}.dart` | `features/economy/domain/` | 11 |
| `services/economy_repository.dart`, `services/catalog_repository.dart` | `features/economy/data/` | 11 |
| `screens/shop/{shop,inventory}_screen.dart` | `features/economy/presentation/` | 11 |
| `widgets/cosmic_scaffold.dart`, `theme/cosmetics_style.dart` | `shared/` | 12 |
| `app_router.dart` | `app/router.dart` | 13 |
| `screens/shell/main_shell.dart` | `app/shell/main_shell.dart` | 13 |
| `main.dart` (`AstrumApp`) | `app/app.dart` (classe) e `main.dart` (só `main()`) | 13 |
| `core/firebase/*`, `core/astro/{zodiac,natal_chart,synergy}.dart` | ficam | nenhum |
| `providers/app_providers.dart` | dividido (seção 4) e apagado | 2, 4 a 12 |

## 4. Divisão de `app_providers.dart`

Cada declaração vai, sem editar o corpo, para o arquivo abaixo no commit da feature (as importações dos tipos acompanham).

| Provider | Destino | Passo |
|---|---|---|
| `authStateProvider`, `currentUidProvider` | `core/firebase/session_providers.dart` | 2 |
| `prefsProvider` | `core/storage/prefs_providers.dart` | 2 |
| `analyticsServiceProvider` | `core/analytics/analytics_providers.dart` | 2 |
| `eventsRepositoryProvider`, `eventsProvider` | `features/rituals/presentation/rituals_providers.dart` | 4 |
| `oracleServiceProvider`, `chatStoreProvider`, `pendingOraclePromptProvider` | `features/oracle/presentation/oracle_providers.dart` | 5 |
| `adminRepositoryProvider` | `features/admin/presentation/admin_providers.dart` | 6 |
| `socialRepositoryProvider`, `friendsProvider`, `intentionProvider` | `features/social/presentation/social_providers.dart` | 7 |
| `authRepositoryProvider` | `features/auth/presentation/auth_providers.dart` | 9 |
| `profileProvider`, `profileRepositoryProvider`, `publicProfileSyncProvider` | `features/profile/presentation/profile_providers.dart` | 10 |
| `economyRepositoryProvider`, `catalogRepositoryProvider`, `shopCatalogProvider` | `features/economy/presentation/economy_providers.dart` | 11 |
| `equippedSkinProvider`, `equippedBackgroundProvider` | `shared/equipped_cosmetics_providers.dart` | 12 (o arquivo `app_providers.dart` fica vazio: `git rm`) |

São 22 providers, todos contemplados. Os imports de consumidores são reescritos pela ferramenta `split` (seção 6), que troca `import '.../app_providers.dart'` pelos imports dos novos arquivos cujos símbolos o arquivo usa; `dart fix --apply` remove sobras. A ordem 2, 4 a 12 garante que um arquivo novo só depende de provedores que ainda estão em `app_providers.dart` ou já foram movidos, e `app_providers.dart` nunca importa de volta um arquivo novo (sem ciclo em nenhum passo intermediário).

## 5. Regra de dependência e teste de fronteira

### 5.1 Camadas (número maior importa número menor ou igual)

| # | Camada | Onde |
|---|---|---|
| 0 | core | `lib/core/**` |
| 1 | domain | `lib/features/*/domain/**` |
| 2 | data | `lib/features/*/data/**` |
| 3 | providers | `lib/features/*/presentation/*_provider(s).dart` |
| 4 | shared | `lib/shared/**` |
| 5 | telas/widgets | demais arquivos de `lib/features/*/presentation/**` |
| 6 | app | `lib/app/**`, `lib/main.dart` |

Regras:

1. Nenhum arquivo importa camada acima da sua.
2. `core` importa só `core` (nem `shared`, nem `features`, nem `app`).
3. Entre features: `domain` de outra feature pode ser importado de qualquer camada; `providers` de outra feature, de providers/telas/shared; `data` de outra feature só nas arestas permitidas `auth -> profile` e `economy -> profile` (um repositório recebe o repositório/sync do perfil); tela de outra feature, nunca. `shared` é visto por telas (camada 5) e `app`.
4. Sem ciclo entre arquivos (DFS no grafo de imports de `lib/`).
5. Sem import relativo em `lib/`.
6. Sem Flutter (`package:flutter/`, `dart:ui`) em `core/astro`, `core/firebase` e `features/*/domain`.

Resultado em arestas entre features (é isto que a regra 3 produz; confirmado na cópia da árvore): data: `auth -> profile`, `economy -> profile`. Domain: `profile -> economy` (`profile_pictures`, `equip_slot`, `equip_slot_field`), `admin -> economy`, `admin -> profile`, `oracle`/`cosmos` só core. Providers: `auth`, `social`, `economy` e `shared` dependem de `profile`; `social` e `shared` de `economy`/`social`; nenhum para trás. `profile` (domain) -> `economy` (domain) e `economy` (presentation) -> `profile` (domain/providers) não formam ciclo porque estão em camadas diferentes; a regra 4 prova.

### 5.2 `test/core_boundaries_test.dart` (estender, não substituir)

Mantém os casos atuais adaptados e acrescenta, tudo lendo `lib/` como texto (sem `dart:mirrors`, sem pacote novo):

1. Teste do próprio detector (como o atual): regex de import `package:astrum/...`, função `layerOf(path)` e `featureOf(path)` com exemplos para cada camada, para `*_providers.dart` e para `sign_up_provider.dart`.
2. `core` só importa `core` (substitui o `_upperLayer` atual; o teste atual lista `models|data|services|theme|providers|screens|widgets` e some quando as pastas legadas somem).
3. Nenhum import de camada superior (regra 1) e nenhuma tela/`data` de outra feature fora da lista `{auth>profile, economy>profile}` (regra 3). Arquivos fora das pastas novas (legado durante a migração) têm camada indefinida e são ignorados, então o teste já vale desde o passo 1 e fica estrito no passo 13.
4. Ciclo: monta o grafo e faz DFS (o analyzer não acusa ciclo de arquivo no mesmo pacote).
5. Sem import relativo em `lib/` (regex `^\s*(import|export)\s+['"](?!dart:|package:)`).
6. Sem Flutter em `core/astro`, `core/firebase` e `features/*/domain` (substitui o teste "core e data não importam Flutter").
7. Sanidade: a varredura encontra arquivos em cada raiz que já existe (evita falso verde, como o `greaterThan(3)` atual).
8. Rede de segurança de estrutura: `lib/providers`, `lib/screens`, `lib/services`, `lib/models`, `lib/data`, `lib/widgets`, `lib/theme`, `lib/config` não existem (ativado só no passo 13).

Rascunho do detector (regras 1, 3 e 4) rodou limpo na cópia da árvore final: `scratchpad/tool/layers_check.dart`.

## 6. Automação dos imports (sem instalar nada)

Ferramenta pronta e testada numa cópia: `C:\Users\aarth\AppData\Local\Temp\claude\1b125e1c40d4ebb5\55b7f6bb-073f-4539-a354-7d0684338b50\scratchpad\tool\fix_imports.dart` (só `dart:io`, roda com o Dart do Flutter já instalado). Mapa de movimentos: `...\scratchpad\tool\moves_all.txt` (uma linha `antigo novo`, relativa a `lib/`; 52 linhas). O scratchpad é volátil: o orquestrador deve copiar os dois para fora do repositório (ou me pedir para regenerá-los) antes de entregar ao builder; não entram no repositório.

| Comando (na raiz do projeto) | Faz |
|---|---|
| `dart run <tool>/fix_imports.dart to-package` | Passo 0: converte import/export relativo de `lib/` em `package:astrum/...`. |
| `grep " features/rituals/" moves_all.txt > passo.txt && dart run <tool>/fix_imports.dart remap passo.txt --git` | `git mv` de cada linha (cria pastas, preserva histórico) e reescreve `package:astrum/<antigo>` em `lib/` e `test/`. Filtros: `" core/"`, `" features/<nome>/"`, `" shared/"`, `" app/"`. |
| `dart run <tool>/fix_imports.dart split providers/app_providers.dart features/rituals/presentation/rituals_providers.dart ...` | Depois de mover as declarações à mão: troca o import do arquivo antigo pelos dos novos cujos símbolos o arquivo usa. |
| `dart run <tool>/fix_imports.dart check` | Falha se algum `package:astrum/...` aponta para arquivo inexistente. |
| `dart fix --apply` | Embutido no SDK; remove `unused_import` sobrando. |
| `flutter analyze` | Confirma o resto (nome não definido, import faltando). |

Propriedades: lê e grava texto sem normalizar quebras de linha (preserva CRLF byte a byte); só toca na URI entre aspas das linhas `import`/`export`; não formata; idempotente (rodar duas vezes não muda nada). Não resolve ordenação de imports (o projeto não usa `directives_ordering`).

Resultado do ensaio: passo 0 na cópia deu `OK` no `check`; aplicando os 52 movimentos sem `--git` e depois o `remap`, o `check` deu `OK` para os 60 arquivos de `lib/` e os de `test/`; as regras da seção 5 só acusaram o monólito `app_providers.dart`. Esse ensaio já corrigiu um erro do desenho (`equip_slot_field` em `economy/data` fazia `profile/data -> economy/data`; agora vai para `economy/domain`).

## 7. Testes: espelhar ou não

Decisão: espelhar parcialmente, num último commit opcional (passo 14), só os testes cujo sujeito é um arquivo ou feature única. Os demais ficam em `test/` porque cobrem mais de uma feature ou o app inteiro e não têm casa honesta.

| Hoje (`test/`) | Depois |
|---|---|
| `auth_models_test.dart` | `features/auth/domain/` |
| `auth_repository_test.dart` | `features/auth/data/` |
| `economy_test.dart`, `equip_slot_test.dart` | `features/economy/domain/` |
| `economy_repository_test.dart` | `features/economy/data/` |
| `admin_test.dart` | `features/admin/data/` |
| `meditation_sounds_test.dart` | `features/cosmos/data/` |
| `oracle_service_test.dart` | `features/oracle/domain/` |
| `public_profile_test.dart` | `features/profile/domain/` |
| ficam: `astrology_test` (mistura `core/astro` e seed), `qa_etapa_4/6`, `qa_etapas_1_a_3`, `characterization_etapa_7`, `repositories_firestore_test`, `router_test`, `sign_up_test`, `providers_subscriptions_test`, `firebase_providers_test`, `rules_contract_test`, `core_boundaries_test`, `widget_test`, `support/` | sem mudança |

Custo: 9 `git mv`; os imports de `lib/` já são `package:astrum/`, então só mudam as duas linhas relativas `import 'support/fake_firebase.dart'` (em `auth_repository_test` e `economy_repository_test`) para o caminho relativo novo (`../../../support/fake_firebase.dart`, a partir de `test/features/<f>/<camada>/`). Nenhuma asserção muda. Sem esse passo nada quebra: ele é cosmético; se houver pressa, descartar. Os testes que movem durante os passos 1 a 13 só têm imports de `lib/` reescritos pela ferramenta.

## 8. Passos (um commit cada; `flutter analyze` e `flutter test` verdes em todos)

Pré-condição P0: árvore limpa, `flutter analyze` e `flutter test` verdes; anotar a contagem de testes. A contagem final tem de ser igual à de P0 (esta etapa não cria nem remove teste; o teste de fronteira só ganha casos dentro do mesmo arquivo, então a contagem sobe só por eles). Em todo passo, além de analyze e test: `dart run fix_imports.dart check`; `git diff --cached -M --stat` mostrando renames (`R`) e não `D`+`A`; `git diff main -- firestore.rules firestore.indexes.json test_rules pubspec.yaml pubspec.lock` vazio; `git status` sem arquivo solto na pasta antiga.

Ordem: da mais isolada (poucos dependentes) para a mais conectada.

| # | Commit | O que faz | Verificação específica |
|---|---|---|---|
| 0 | `refactor: imports package:astrum em lib/ (etapa 8)` | `to-package`. Estende `core_boundaries_test.dart` com os casos 1, 4, 5, 7 e a regex de relativo (seção 5.2). Sem mover nada. | `grep -rn "^import '\.\|^import '[a-z_]*\.dart" lib` vazio; testes verdes. |
| 1 | `refactor: core/ (config, theme, widgets, astro, analytics) (etapa 8)` | `remap` das linhas `" core/"` (env, colors, theme, starfield, moon, tarot, analytics_service). Atualiza o teste: `core` só importa `core`; "sem Flutter" passa a valer só para `core/astro` e `core/firebase` (core/theme e widgets usam Flutter). | `lib/core/theme` e `core/widgets` não importam `models/services/...`. |
| 2 | `refactor: providers transversais em core/ (etapa 8)` | Divisão da seção 4 (passo 2): `session_providers.dart`, `prefs_providers.dart`, `analytics_providers.dart`; `split` nos consumidores (`app_router`, `main`, `sign_up_provider`, screens, testes). | `profile_repository.dart` só cita `authStateProvider` em comentário (nenhum import novo). |
| 3 | `refactor: feature astral (etapa 8)` | `remap` `" features/astral/"`. | analyze/test. |
| 4 | `refactor: feature rituals (etapa 8)` | `remap` + `rituals_providers.dart` + `split`. | `rituals` não importa outra feature (só `shared`/legado). |
| 5 | `refactor: feature oracle (etapa 8)` | idem; `oracle_service` importa `core/astro/{moon,tarot}`. | `oracle` não importa `cosmos`. |
| 6 | `refactor: feature admin (etapa 8)` | idem; `admin_screen` importa `economy` ainda no caminho legado (fica correto depois do passo 11). | `AdminRepository` e `crystal_seed` só movidos. |
| 7 | `refactor: feature social (etapa 8)` | idem; `intentionProvider` importa `profileProvider` ainda de `app_providers.dart`. | `social` sem tela. |
| 8 | `refactor: feature cosmos (etapa 8)` | `remap` (inclui `meditation_sheet` e `meditation_sounds`). | `cosmos` não importa `rituals`. |
| 9 | `refactor: feature auth (etapa 8)` | `remap` + `auth_providers.dart` (`authRepositoryProvider`); `split`. **Tocam autenticação: só caminho/import e a declaração movida; conferir no diff.** | `git diff -M --color-moved` sem linha alterada além de imports; `qa_etapa_6_test`, `sign_up_test`, `router_test` verdes. |
| 10 | `refactor: feature profile (etapa 8)` | `remap` + `profile_providers.dart`; `split`. **Dados de usuário: idem.** | `characterization_etapa_7_test` e `repositories_firestore_test` verdes sem editar asserção. |
| 11 | `refactor: feature economy (etapa 8)` | `remap` + `economy_providers.dart`; `split`. **Loja/saldo: idem.** | `economy_test`, `economy_repository_test`, `rules_contract_test` verdes. |
| 12 | `refactor: shared/ (CosmicScaffold e cosmeticos) (etapa 8)` | `remap` `" shared/"` + `equipped_cosmetics_providers.dart`; `git rm lib/providers/app_providers.dart` (vazio). | `lib/providers` não existe. |
| 13 | `refactor: app/ e limpeza das pastas legadas (etapa 8)` | `remap` `" app/"`; move a classe `AstrumApp` para `app/app.dart`; `widget_test` e demais passam a importar `app/app.dart`/`app/router.dart`; ativa o caso 8 do teste (pastas legadas inexistentes) e as regras estritas. | `flutter run` não é exigido; `routerProvider` e `widget_test` verdes; `lib/` só tem `app core features shared main.dart`. |
| 14 | `refactor: espelha testes por feature (etapa 8)` (opcional) | Seção 7. | contagem de testes igual à do passo 13. |
| 15 | `docs: etapa 8` | `overview.md` (árvore e regra de dependência), `restructuring.md` (seção 4.1: novos desvios da seção 1.1 deste arquivo; status etapa 8), backlog em `docs/plans/reestruturacao-etapas-1-a-3.md`, CHANGELOG (writer). Docs `step4..step7` ficam como histórico (citam caminhos antigos de propósito). | links dos `.md` válidos. |

Se um passo falhar a verificação, reverter só o passo (`git restore --staged --worktree .`/`git reset` do que o builder ainda não commitou), corrigir o mapa e repetir; como cada passo é mecânico, não se corrige no meio.

## 9. Riscos

| Risco | Mitigação |
|---|---|
| Import quebrado ou sobrando | `check` + analyze + `dart fix --apply` em cada passo; a ferramenta é idempotente. |
| Símbolo novo importado de feature errada ao dividir `app_providers` | Só os 22 providers da seção 4; teste de fronteira e DFS de ciclo; `split` importa pelo uso real do símbolo. Falso positivo (símbolo com mesmo nome em comentário) gera import sobrando, removido pelo `dart fix`. |
| `git mv` e histórico | Os movimentos entram com poucas edições por arquivo (só linhas de import), mantendo similaridade acima de 50%. Conferir `git diff --cached -M --stat` e `git log --follow` em 2 ou 3 arquivos pequenos (por exemplo `friend.dart`, `ritual_event.dart`); arquivos de modelo sem import não mudam de conteúdo. Se algum aparecer como `D`+`A`, baixar o limiar (`-M30%`) só para conferir; não há ação corretiva além de manter edição mínima. |
| CRLF | `git config core.autocrlf` é `true` e a árvore de trabalho tem CRLF; a ferramenta preserva CRLF. Arquivos novos (os `*_providers.dart`) criados pelo builder podem sair com LF; o git converte no commit (aviso de "LF will be replaced by CRLF" é inofensivo). Não rodar `dart format` em arquivos movidos (reformata e polui o diff, como na etapa 7). |
| Conflito com outros trabalhos | Branch `feature/flutter-migration` sem outro trabalho em `lib/`; avisar o usuário para não editar `lib/` em paralelo durante a etapa. Cada passo é pequeno para facilitar rebase. |
| Windows: pasta aberta pelo IDE/analyzer | `git mv` pode falhar com arquivo em uso; fechar o analisador do IDE ou repetir. |
| Ciclo entre providers durante a migração | Ordem da seção 4 e regra "`app_providers.dart` nunca importa um arquivo novo". |
| Teste de fronteira estrito demais quebra um passo intermediário | Camada indefinida (pasta legada) é ignorada até o passo 13; o caso 8 só é ativado no passo 13. |
| `shared/` virar depósito | Regra de admissão (reescrita no fechamento da etapa): só entra em `shared/` UI ou estilo usado por 3 ou mais features, ou lido por um widget transversal (`CosmicScaffold`). Exceções conscientes, registradas como dívida: `cosmetics_style.dart` (depende de `ItemRarity` de economy/domain, então não pode ir para `core/`) e `equipped_cosmetics_providers.dart` (lido pelo `CosmicScaffold`); movê-los para uma feature criaria dependência inversa ou ciclo. Hoje são 3 arquivos. Revisar na etapa 9 (extrair `CosmicScaffold` do estado de feature é melhoria futura, não parte desta etapa). |
| Docs apontam caminhos antigos | Passo 15; `step4..step7` ficam como estão (histórico). |
| Regras do Firestore e `test_rules/` | Nenhum caminho de `lib/` aparece neles nem em `.github/workflows` (grep). `npm test` não é necessário; o `rules_contract_test` (Dart) lê `firestore.rules` por caminho de raiz e não muda. |

## 10. Revisão

Conclusão: `reviewer-consultor` revisa, uma única vez, depois do passo 13 (sobre `git diff -M` do conjunto, mais os commits 2 e 4 a 12 onde há divisão de providers), e não por feature. `reviewer` (Sonnet) cobre cada commit.

Por quê: o `CLAUDE.md` lista "arquitetura" como gatilho, e esta etapa fixa regras de dependência permanentes (camadas, `shared/`, arestas permitidas) e toca arquivos de autenticação, perfil e economia. Em contrapartida, o risco de comportamento é baixo: nenhum valor, regra, dependência ou texto muda, e o consultor não precisa reler o código movido linha a linha. Pedir a ele: (1) julgar se o modelo de camadas e as exceções (`shared/`, arestas `auth -> profile` e `economy -> profile`, desvios da seção 1.1) são defensáveis; (2) conferir por `git diff -M --color-moved` que os passos 9, 10 e 11 só mudam linhas de `import` e a localização dos providers (nenhuma alteração em corpo de repositório, transação, `createProfile`, `register`, `purchaseItem`, `dailyCheckIn`); (3) confirmar diff vazio em `firestore.rules`, `firestore.indexes.json`, `test_rules/`, `pubspec.yaml` e `pubspec.lock`. Se o orquestrador considerar o custo alto, a alternativa aceitável é o `reviewer` comum com essa mesma lista, desde que (2) e (3) sejam verificados mecanicamente; mas isso é uma exceção ao gatilho literal e deve ser decisão consciente dele.

## 11. Critérios de aceite

- `lib/` contém só `main.dart`, `app/`, `core/`, `shared/`, `features/`; árvore igual à da seção 2.
- `flutter analyze` e `flutter test` verdes em cada commit; contagem de testes igual à de P0 mais os casos novos do teste de fronteira.
- `core_boundaries_test.dart` aplica as regras da seção 5 e falha se um import proibido for introduzido (o próprio arquivo tem o teste do detector).
- Nenhum `import` relativo em `lib/`; nenhum import de `providers/app_providers.dart`.
- Zero diff em `firestore.rules`, `firestore.indexes.json`, `test_rules/`, `pubspec.yaml`, `pubspec.lock`.
- `git log --follow` funciona nos arquivos movidos (renames detectados).
