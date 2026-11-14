# Etapa 7: separar `data/` e `models/` e centralizar constantes

Status: implementada nos passos 1 a 7 e 9 (sem commit); passo 8 (renomes opcionais) não feito. Ver "Desvios da implementação" ao fim. Refatoração pura: nenhum valor, nenhuma regra, nenhuma consulta e nenhum texto de tela muda. `firestore.rules`, `firestore.indexes.json` e `test_rules/` não são tocados. Plano Spark inalterado (nenhuma dependência nova, nenhuma leitura nova).

Base: `restructuring.md` (seção 6, item 7, e seção 4), `step4-repositories.md`, `step5-typed-writes.md`, `step6-auth.md`, `docs/plans/reestruturacao-etapas-1-a-3.md` (backlog e itens abertos), leitura de `lib/data/*`, `lib/models/*`, `lib/services/economy.dart`, `firestore.rules`, `test_rules/` e grep de uso em `lib/` e `test/`.

## 1. Diagnóstico (o que a etapa resolve)

| Problema | Onde |
|---|---|
| `data/astrology.dart` mistura conteúdo (`zodiacSigns`, `signElements`, `signGlyph`), algoritmos (`sunSignFromDate`, `parseDateString`, `computeNatalChart`, `getAstralSynergy`), um modelo (`PlanetPosition`) e regra de avatar (`defaultProfilePictureId`) | `lib/data/astrology.dart` (273 linhas) |
| `data/cosmetics.dart` mistura enums/modelo (`ItemType`, `ShopItem`), UI (`Color`, `SkinStyle`, `rarityColor`), seed com preços (`_baseShopCatalog`, `fullShopCatalog`), mapeamento de asset e o slug de signo | `lib/data/cosmetics.dart` (246 linhas) |
| O slug do signo (acentos removidos) existe duas vezes: `_signSlug` em `cosmetics.dart` e inline em `defaultProfilePictureId` | idem |
| `models/app_user.dart` tem 6 modelos de 4 features (`AppUser`, `RitualEvent`, `ChatConversation`, `ChatTurnStored`, `Friend`, `IntentionNotice`) e importa `data/astrology.dart` | `lib/models/app_user.dart` |
| `services/economy.dart` mistura lógica pura, modelo (`CatalogEntry`) e exceções com texto de UI | `lib/services/economy.dart` |
| Constantes duplicadas entre Dart e `firestore.rules` (seção 3) | vários |

## 2. Nova organização de arquivos

Princípios para não mover duas vezes:

1. Todo arquivo novo nasce com o nome de arquivo definitivo (o que a etapa 8 vai querer). Na etapa 8 só muda o diretório e os imports, nunca o nome nem o conteúdo.
2. O que é transversal (usado por mais de uma feature) já nasce em `lib/core/`, que é o destino final e já existe (`core/firebase/`). Esses arquivos não se movem na etapa 8.
3. O que pertence a uma feature fica, na etapa 7, nas pastas de camada atuais (`models/`, `data/`, `services/`, `theme/`), sem criar `features/`. A etapa 8 move cada um uma única vez (tabela da seção 5).
4. Sem barrel files e sem `export` de compatibilidade: cada import passa a apontar para o arquivo certo (o analyzer acusa o que faltar).

Árvore resultante da etapa 7 (`NOVO` = criado nesta etapa; `ALT` = alterado; sem marca = intocado):

```
lib/
  main.dart, app_router.dart                       (imports ALT apenas se tocarem arquivos movidos)
  config/env.dart                                  (intocado; sem constantes duplicadas)
  core/
    firebase/
      firebase_providers.dart
      firestore_paths.dart
      rules_contract.dart                          NOVO  constantes espelhadas nas regras
    astro/                                         NOVO  conhecimento astrológico transversal
      zodiac.dart                                  NOVO  zodiacSigns, signElements, signGlyph, zodiacSlug,
                                                         sunSignFromDate, parseDateString
      natal_chart.dart                             NOVO  PlanetPosition, computeNatalChart (+ helpers privados)
      synergy.dart                                 NOVO  SynergyResult, getAstralSynergy
  data/                                            (só conteúdo estático e seeds, Dart puro, sem Flutter)
    tarot.dart                                     intocado
    moon.dart                                      intocado
    crystal_seed.dart                              intocado
    catalog_seed.dart                              NOVO  seed do catálogo (preços do seed)
    profile_pictures.dart                          NOVO  variantes, defaultProfilePictureId, profilePictureAssetPath
  models/                                          (um arquivo por modelo)
    app_user.dart                                  ALT   só AppUser (+ fromDoc, codec do mapa astral)
    ritual_event.dart                              NOVO
    chat_models.dart                               NOVO  ChatConversation, ChatTurnStored
    friend.dart                                    NOVO
    intention_notice.dart                          NOVO
    catalog_entry.dart                             NOVO  CatalogEntry (saiu de economy.dart)
    shop_item.dart                                 NOVO  ItemRarity, ItemType (+ slot), ShopItem,
                                                         catalogTypeName, catalogRarityName, rarityLabel
    equip_slot.dart, auth_exception.dart, sign_up_data.dart   ALT só em sign_up_data (SignUpLimits usa o contrato)
  services/
    economy.dart                                   ALT   só funções puras (computePurchase, computeCheckIn, resolvePrice)
    economy_exceptions.dart                        NOVO  EconomyException e subclasses
    (demais arquivos: só imports ALT)
  theme/
    cosmetics_style.dart                           NOVO  SkinStyle, cosmeticStyles, cosmeticBackgrounds, rarityColor
  (providers/, screens/, widgets/: só imports ALT e os usos das constantes)
```

Removidos: `lib/data/astrology.dart`, `lib/data/cosmetics.dart`.

Decisões de projeto:

- `core/astro/` em vez de `cosmos/domain/` (que `restructuring.md` previa): signos, elementos, glifos e mapa natal são usados por auth (`welcome_screen`), perfil (`AppUser.astralMap`, `profile_repository`, `public_profile_sync`), economia (seed de avatares), social (sinergia), astral, cosmos, oráculo e admin. Colocá-los em `cosmos/` criaria dependência de quase todas as features para a feature home. `moon.dart` e `tarot.dart` ficam sem mudança porque só cosmos e oráculo os usam.
- `theme/cosmetics_style.dart` (e não em `economy/presentation/`, como em `restructuring.md`): `skinStyleProvider` e `backgroundProvider` alimentam `CosmicScaffold` (widget transversal); manter o estilo no tema evita `core -> features`. A etapa 8 leva `theme/` inteiro para `core/theme/`, então o arquivo se move uma vez, junto da pasta.
- `profile_pictures.dart` em `data/`: junta o que hoje está espalhado entre `astrology.dart` e `cosmetics.dart` (variantes `common/rare/epic/legendary`, id padrão `pfp_zodiac_<slug>`, caminho do asset). Usa `zodiacSlug` de `core/astro/zodiac.dart`, o que elimina a duplicação do slug. O seed (`catalog_seed.dart`) importa as variantes daqui, então preço e rótulo continuam definidos num lugar só.
- Intenções: id e rótulo moram em `rules_contract.dart` (as regras validam os dois: `labelOk`); ícone e cor continuam na UI (`account_screen.dart`), que passa a derivar a lista do contrato e a completar com ícone/cor por id.
- `AppUser.encodeAstralMap`/`parseAstralMap` ficam em `AppUser` (parse de campo do documento do usuário); só `PlanetPosition` e `computeNatalChart` vão para `core/astro/natal_chart.dart`.
- `AppUser.fromFirebase` é renomeado `fromDoc` (2 chamadores em `lib/`, 0 em `test/`) e `CatalogRepository.watchShopCatalog` vira `watchCatalog` (1 chamador em `lib/`, 1 em `test/qa_etapa_4_test.dart`), como `restructuring.md` e `step4-repositories.md` previram para a etapa 7. São os dois últimos passos, isolados, descartáveis se houver atrito.
- Fora de escopo (continua como está): `config/env.dart` (nenhuma constante espelhada nas regras), `tarot.dart`/`moon.dart` (conteúdo + regra pequena, 166 e 99 linhas, uso restrito), parse de `Map` dentro de `FirestoreEconomyRepository` (não é `AppUser.fromDoc`; fica para a etapa 9), o `AppUser.toFirestore()` (não alterado). Limites de chat (`title 80`, `messageCount 500`, `text 10000`, `schemaVersion 1`) ficam para a etapa 10, quando houver código Dart que os use; o teste de divergência foi desenhado para aceitar novos itens com uma linha.

## 3. Constantes duplicadas e o contrato único

### 3.1 Um único lugar no Dart

`lib/core/firebase/rules_contract.dart`: somente constantes `const` de nível superior (sem classes, sem Flutter, sem Firebase), agrupadas por comentário e cada uma com `// firestore.rules: <função/linha>`. Fica em `core/firebase/` porque o conteúdo é o espelho do arquivo de regras (e fica ao lado de `firestore_paths.dart`); não se move na etapa 8. Isto substitui a sugestão de `restructuring.md` (seção 4) de espalhar constantes em `economy/domain` e `social/domain`: com um único arquivo de regras, um único contrato é mais fácil de conferir.

| Constante | Valor | Hoje duplicada em | Regra correspondente |
|---|---|---|---|
| `checkInReward` | 25 | `economy.dart`; textos `+25` em `cosmos_screen.dart` (2); `test_rules` | `isCheckin`: `oldStar() + 25` |
| `initialStardust` | 500 | `profile_repository.createProfile`; `test_rules` | `create`: `wallet == {'stardust': 500}` |
| `defaultSkinId` | `skin_classic` | `profile_repository`, `app_user` (3x), `app_providers`, `cosmetics.dart` (seed e estilos) | `equippedOk`: `equipTypeOk(..., 'skin', 'skin_classic')`, `initialInvOk` |
| `defaultBackgroundId` | `bg_void` | idem | `equippedOk`, `initialInvOk` |
| `defaultInventory` | `[skin_classic, bg_void]` | `profile_repository`, `app_user` (2x) | `initialInvOk`: `== ['skin_classic', 'bg_void']` |
| `zodiacAvatarPrefix` | `pfp_zodiac_` | `astrology.dart`, `cosmetics.dart` | `initialInvOk`: `matches('^pfp_zodiac_[a-z]+$')` |
| `intentionLabels` | `{luz: Luz, coragem: Coragem, cura: Cura, clareza: Clareza}` | `account_screen.dart` (`intentions`) | `labelOk` |
| `catalogItemTypes` | `skin, background, profilePicture` | `catalogTypeName` | `validItem`: `d.type in [...]` |
| `roleUser` / `roleAdmin` | `user` / `admin` | `profile_repository`, `app_user` (2x) | `isAdmin`, `create`: `role == 'user'` |
| `anonymousUserId` | `anonymous` | `analytics_service`, `admin_repository.summarizeAnalytics` | `analytics_events`: `'anonymous'` |
| Limites de campo (nome 100, e-mail 254, signo 30, data 20, hora 10, local 200, `astralMapJson` 20000, inventário 500, mapas 5) | ver coluna 1 | `SignUpLimits` (só 5 deles); `public_profile.dart` (100 do nome) | `profileShapeOk`, `validPublic` |
| `publicAvatarMax` / `emailHashLength` | 100 / 64 | `public_profile.dart` (comentário) | `validPublic` |

Nomes finais dos limites (um por campo): `profileNameMax=100`, `profileEmailMax=254`, `profileZodiacSignMax=30`, `profileBirthDateMax=20`, `profileBirthTimeMax=10`, `profileBirthPlaceMax=200`, `profileAstralMapJsonMax=20000`, `profileMapFieldMaxKeys=5`, `inventoryMaxItems=500`, `publicNameMax=100`, `publicAvatarMax=100`, `emailHashLength=64`, `analyticsEventNameMax=100` (este último sem consumidor Dart hoje; entra só no contrato e no teste para não ser esquecido, ou fica de fora se o builder preferir não criar constante sem uso).

Números que NÃO são do contrato e não devem ser trocados por engano: `limit(500)` e "500 operações do batch" em `admin_repository.dart` (limites de consulta/batch, não de regra); `illumination: 0.25` em `moon.dart`; o preço 500 do avatar comum e do `bg_temple` no seed (preço de catálogo, vem do Firestore).

Consumidores que passam a usar o contrato (substituição literal, sem mudança de valor): `economy.dart`, `profile_repository.dart` (`createProfile`), `app_user.dart` (defaults e `fromDoc`), `app_providers.dart` (fallbacks de skin/fundo), `sign_up_data.dart` (`SignUpLimits` vira alias: `static const name = profileNameMax;` etc., mantendo a API e os usos em `register_screen`/`welcome_screen`), `public_profile.dart` (100), `analytics_service.dart` e `admin_repository.dart` (`anonymous`), `shop_item.dart` (`catalogTypeName`), `catalog_seed.dart`/`cosmetics_style.dart` (ids padrão como chaves), `account_screen.dart` (intenções), `cosmos_screen.dart` (texto `+$checkInReward Poeira Estelar`, mesmo texto final).

Observação sobre `catalogTypeName`: o `switch` continua sendo a fonte do valor; o contrato lista os três valores aceitos pela regra e o teste confere que `ItemType.values.map(catalogTypeName)` é igual a `catalogItemTypes`.

### 3.2 Teste que detecta divergência com `firestore.rules`

Arquivos: `test/support/rules_contract_check.dart` (função pura) e `test/rules_contract_test.dart`.

- `List<String> findRulesDivergences(String rulesSource)` extrai com `RegExp` os valores das regras e devolve uma lista de mensagens do tipo `checkInReward: Dart=25, regras=26`. Lista vazia = em sincronia.
- Extração (todas a partir do texto de `firestore.rules`, com `File('firestore.rules')`; `flutter test` roda com a raiz do pacote como diretório atual, também no CI):

| Verificação | Padrão nas regras | Compara com |
|---|---|---|
| check-in | `newStar\(\) == oldStar\(\) \+ (\d+)` | `checkInReward` |
| saldo inicial | `wallet == \{'stardust': (\d+)\}` | `initialStardust` |
| inventário inicial | `nw\(\)\.inventory == \[([^\]]*)\]` | `defaultInventory` |
| skin/fundo padrão | `equipTypeOk\([^,]+,\s*'skin',\s*'(\w+)'\)` e `'background'` | `defaultSkinId`, `defaultBackgroundId` |
| prefixo do avatar zodiacal | `matches\('\^(pfp_zodiac_)\[a-z\]\+\$'\)` | `zodiacAvatarPrefix` |
| intenções | todos os pares `intentionId == '(\w+)' && label == '(\w+)'` dentro de `labelOk` | `intentionLabels` (mapa inteiro, nos dois sentidos: id ou rótulo faltando de qualquer lado acusa) |
| tipos do catálogo | `d\.type in \[([^\]]*)\]` | `catalogItemTypes` |
| role | `role == '(\w+)'` no `create` e `== '(\w+)'` em `isAdmin` | `roleUser`, `roleAdmin` |
| analytics anônimo | `: '(\w+)'\)` na linha de `userId` | `anonymousUserId` |
| limites de string | `optStr\('(\w+)',\s*(\d+)\)`; `name\.size\(\) <= (\d+)`; `d\.name\.size\(\) <= (\d+)`; `d\.avatar\.size\(\) <= (\d+)` | `profile*Max`, `publicNameMax`, `publicAvatarMax` |
| limites de mapa/lista | `optMap\('(\w+)',\s*(\d+)\)`; `inventory\.size\(\) <= (\d+)` | `profileMapFieldMaxKeys`, `inventoryMaxItems` |
| hash | `\{(\d+)\}\$'\)` em `validPublic` | `emailHashLength` |

- Padrão ausente nas regras (alguém reformatou ou renomeou) NÃO passa em silêncio: gera a divergência `padrão não encontrado: <nome> (ajuste o teste junto com as regras)`. É deliberado: falha barulhenta é preferível a falso verde.

Casos de teste em `test/rules_contract_test.dart`:

1. As regras reais não têm divergência (`findRulesDivergences(File('firestore.rules').readAsStringSync())` vazio).
2. Mutação por constante (parametrizado): para cada linha da tabela, altera uma cópia do texto das regras (por exemplo `+ 25` para `+ 26`, `'stardust': 500` para `501`, `'bg_void'` para `'bg_x'` no `equipTypeOk`, `label == 'Luz'` para `'Luzz'`, remove o par de `'clareza'`, `optStr('birthPlace', 200)` para `201`, `size() <= 500` para `501`, `d.type in [...]` sem `'background'`) e espera uma divergência que cite o nome da constante. Prova que o detector realmente detecta.
3. Padrão ausente: remove a função `labelOk` do texto e espera `padrão não encontrado`.
4. Sanidade do contrato em Dart (sem regras): `defaultInventory` contém exatamente `defaultSkinId` e `defaultBackgroundId`, nessa ordem; `ItemType.values.map(catalogTypeName).toSet()` igual a `catalogItemTypes.toSet()`; `SignUpLimits.*` igual às constantes `profile*Max`; `cosmeticStyles` tem a chave `defaultSkinId` e `cosmeticBackgrounds` tem `defaultBackgroundId` (os fallbacks de `app_providers.dart` nunca ficam nulos); `fullShopCatalog` contém os dois ids padrão com preço 0.
5. Cobertura da UI de intenções: toda chave de `intentionLabels` tem ícone e cor em `account_screen.dart` (teste de unidade sobre o mapa de estilos exposto pela tela, sem montar widget).

CI: `ci.yml` já roda `flutter test`; nenhum workflow novo. O job do emulador de `test_rules/` continua independente (os testes `.mjs` mantêm seus literais, são a verificação de comportamento das regras; o teste Dart verifica só que o Dart não se afastou delas).

## 4. Passos pequenos (um commit por passo; `flutter analyze` e `flutter test` verdes ao fim de cada um)

Pré-condição P0: rodar `flutter analyze` e `flutter test` na branch limpa e anotar a contagem de testes. O `npm test` de `test_rules/` segue pendente (porta 8080 ocupada nas etapas 4 a 6); como as regras não mudam, ele não bloqueia a etapa, mas quem puder deve rodá-lo uma vez ao final (`FIRESTORE_EMULATOR_PORT` alternativa).

| # | Passo | Mudança | Imports afetados |
|---|---|---|---|
| 1 | Rede de segurança | Testes de caracterização que travam o comportamento atual: seed do catálogo (ids, tipos, raridades, preços, quantidade de `fullShopCatalog`), `profilePictureAssetPath` para todos os ids, defaults de `AppUser.fromFirebase` com `data == null`, payload de `createProfile` (já há base em `repositories_firestore_test.dart`; completar com `wallet`, `inventory`, `equipped`, `role`), textos de `computeCheckIn`/exceções. Sem tocar em `lib/`. | nenhum |
| 2 | Contrato e teste de divergência | Criar `core/firebase/rules_contract.dart`, `test/support/rules_contract_check.dart`, `test/rules_contract_test.dart` (casos 1 a 3; os casos 4 e 5 entram no passo 3). Nenhum consumidor ainda: o teste prova que os valores do contrato batem com as regras antes de qualquer substituição. | nenhum |
| 3 | Consumir o contrato | Substituir literais pelas constantes (lista na seção 3.1); `SignUpLimits` vira alias; `account_screen.dart` passa a derivar `intentions` de `intentionLabels`; textos `+25` interpolados; `economy.dart` perde a própria `checkInReward` e importa a do contrato (ajuste de import em `economy_test.dart` se ele referenciar a constante). Adicionar casos 4 e 5. | `economy.dart`, `profile_repository.dart`, `app_user.dart`, `app_providers.dart`, `sign_up_data.dart`, `public_profile.dart`, `analytics_service.dart`, `admin_repository.dart`, `account_screen.dart`, `cosmos_screen.dart` |
| 4 | Dividir `models/app_user.dart` | Criar `ritual_event.dart`, `chat_models.dart`, `friend.dart`, `intention_notice.dart`; `app_user.dart` fica só com `AppUser`. Mover o corpo sem editar. | `RitualEvent`: `events_repository`, `rituals_screen`. `ChatConversation`/`ChatTurnStored`: `chat_store`, `oracle_screen`. `Friend`: `social_repository`, `account_screen`, `test/support/fake_repositories.dart` se usar. `IntentionNotice`: `social_repository`, `cosmic_scaffold`, `app_providers`. `AppUser` continua importado de `app_user.dart` por todos os demais. |
| 5 | Dividir `data/astrology.dart` | Criar `core/astro/zodiac.dart` (com `zodiacSlug` extraído do código duplicado), `natal_chart.dart`, `synergy.dart` e `data/profile_pictures.dart` (`profilePictureVariants`, `defaultProfilePictureId`, `profilePictureAssetPath`, `_zodiacPictureFiles`). Apagar `data/astrology.dart`. `_signSlug` de `cosmetics.dart` passa a chamar `zodiacSlug` (ainda sem dividir `cosmetics.dart`). | `zodiacSigns`/`signElements`/`signGlyph`/`sunSignFromDate`/`parseDateString` (zodiac): `oracle_service`, `welcome_screen`, `account_screen`, `astral_screen`, `cosmos_screen`, `cosmetics.dart`. `PlanetPosition`/`computeNatalChart` (natal_chart): `app_user`, `profile_repository`, `astral_screen`; testes `equip_slot_test`, `repositories_firestore_test`. `getAstralSynergy` (synergy): `account_screen`, `astrology_test`. `defaultProfilePictureId` (profile_pictures): `admin_repository`, `profile_repository`, `public_profile_sync`, `account_screen`; testes `astrology_test`, `repositories_firestore_test`, `qa_etapa_4_test`. |
| 6 | Dividir `data/cosmetics.dart` | Criar `models/shop_item.dart`, `data/catalog_seed.dart`, `theme/cosmetics_style.dart`; mover `profilePictureAssetPath` e variantes para `profile_pictures.dart` se ainda não estiverem; apagar `cosmetics.dart`. `ItemTypeSlot` vai junto de `ItemType` (continua importando `EquipSlot`). Em `catalog_seed.dart` e `cosmetics_style.dart`, os ids padrão usam o contrato. | `cosmeticStyles`/`cosmeticBackgrounds`: `app_providers`. `ShopItem`/`ItemType`/`catalogTypeName`/`catalogRarityName`: `admin_repository`, `inventory_screen`, `shop_screen`; testes `admin_test`, `equip_slot_test`. `fullShopCatalog` (seed): `admin_screen`, `inventory_screen`, `shop_screen`; testes `admin_test`, `astrology_test`. `rarityLabel`: `inventory_screen`, `shop_screen`. `rarityColor`: `shop_screen`. `profilePictureAssetPath`: `account_screen`, `inventory_screen`, `shop_screen`; teste `astrology_test`. `cosmos_screen` importa `cosmetics.dart` hoje: se só sobrar import morto, remover (o analyzer indica). |
| 7 | Dividir `services/economy.dart` | Criar `models/catalog_entry.dart` e `services/economy_exceptions.dart`; `economy.dart` mantém `PurchaseResult`, `computePurchase`, `computeCheckIn`, `resolvePrice`. | `CatalogEntry`: `catalog_repository`, `app_providers`, `economy_repository`, `shop_screen`. Exceções: `cosmos_screen`, `shop_screen`, `economy_repository`; testes `economy_test`, `economy_repository_test`. |
| 8 | Renomear (opcional, isolado) | `AppUser.fromFirebase` para `fromDoc`; `CatalogRepository.watchShopCatalog` para `watchCatalog` (o `shopCatalogProvider` mantém o nome; renomeá-lo para `catalogProvider` é opcional e toca `shop_screen`/`inventory_screen`). | `profile_repository`, `admin_repository`, `app_providers`, `qa_etapa_4_test.dart`, fakes se implementarem `watchShopCatalog` |
| 9 | Documentação | Atualizar `overview.md` (estrutura de `lib/`, parágrafo de constantes e do teste de divergência) e corrigir em `restructuring.md` as seções 4 e 6 (item 7) com os destinos finais da seção 5 abaixo; registrar a etapa 7 no backlog de `docs/plans/reestruturacao-etapas-1-a-3.md` e marcar "Limites de campos do cadastro (`SignUpLimits`)" como coberto pelo teste de divergência. Writer: CHANGELOG. | nenhum |

Regra para o builder em todos os passos: mover trechos de código sem reformatar nem renomear (exceto os dois renomes do passo 8) para o diff continuar legível com `git diff --color-moved`. Os testes existentes só têm os imports ajustados; nenhuma asserção muda.

## 5. Mapa: arquivo atual -> etapa 7 -> etapa 8

Só o necessário para não mover duas vezes. A etapa 8 move apenas diretórios/arquivos e imports.

| Hoje | Etapa 7 | Etapa 8 (destino final) |
|---|---|---|
| `data/astrology.dart` (conteúdo, `sunSignFromDate`, `parseDateString`) | `core/astro/zodiac.dart` | fica (já final) |
| `data/astrology.dart` (`PlanetPosition`, `computeNatalChart`) | `core/astro/natal_chart.dart` | fica |
| `data/astrology.dart` (`SynergyResult`, `getAstralSynergy`) | `core/astro/synergy.dart` | fica |
| `data/astrology.dart` (`defaultProfilePictureId`) | `data/profile_pictures.dart` | `features/economy/domain/profile_pictures.dart` |
| `data/cosmetics.dart` (enums, `ShopItem`, nomes do catálogo) | `models/shop_item.dart` | `features/economy/domain/shop_item.dart` |
| `data/cosmetics.dart` (seed) | `data/catalog_seed.dart` | `features/economy/data/catalog_seed.dart` |
| `data/cosmetics.dart` (`SkinStyle`, cores) | `theme/cosmetics_style.dart` | `core/theme/cosmetics_style.dart` |
| `data/cosmetics.dart` (`profilePictureAssetPath`) | `data/profile_pictures.dart` | `features/economy/domain/profile_pictures.dart` |
| `data/crystal_seed.dart` | intocado | `features/admin/data/crystal_seed.dart` |
| `data/moon.dart`, `data/tarot.dart` | intocados | `features/cosmos/domain/moon.dart`, `tarot.dart` |
| `models/app_user.dart` (`AppUser`) | `models/app_user.dart` | `features/profile/domain/app_user.dart` |
| `models/app_user.dart` (`RitualEvent`) | `models/ritual_event.dart` | `features/rituals/domain/ritual_event.dart` |
| `models/app_user.dart` (`ChatConversation`, `ChatTurnStored`) | `models/chat_models.dart` | `features/oracle/domain/chat_models.dart` |
| `models/app_user.dart` (`Friend`) | `models/friend.dart` | `features/social/domain/friend.dart` |
| `models/app_user.dart` (`IntentionNotice`) | `models/intention_notice.dart` | `features/social/domain/intention_notice.dart` |
| `models/equip_slot.dart` | intocado | `features/economy/domain/equip_slot.dart` (junto de `equip_slot_field.dart`, que vai para `features/economy/data/`) |
| `models/auth_exception.dart`, `models/sign_up_data.dart` | intocados (sign_up_data com alias) | `features/auth/domain/` |
| `services/economy.dart` | `services/economy.dart` (só funções) | `features/economy/domain/economy.dart` |
| `services/economy.dart` (`CatalogEntry`) | `models/catalog_entry.dart` | `features/economy/domain/catalog_entry.dart` |
| `services/economy.dart` (exceções) | `services/economy_exceptions.dart` | `features/economy/domain/economy_exceptions.dart` |
| (novo) contrato | `core/firebase/rules_contract.dart` | fica |
| `config/env.dart` | intocado | `core/config/env.dart` |

Ajuste ao `restructuring.md` seção 4 (a registrar no passo 9): `cosmos/domain/{astrology,moon,tarot}` vira `core/astro/` + `cosmos/domain/{moon,tarot}`; `economy/presentation/cosmetics_style.dart` vira `core/theme/cosmetics_style.dart`; constantes em `economy/domain` e `social/domain` viram `core/firebase/rules_contract.dart`; `social/domain/intention.dart` vira `intention_notice.dart`.

## 6. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Alterar um valor por engano ao substituir literais (saldo inicial, ids padrão, limites) | Passo 2 prova contrato == regras antes de usar; passo 1 trava o payload de `createProfile` e os defaults; o diff do passo 3 é revisado literal a literal |
| Trocar um `500` de contrato por um `500` que não é (limite de query/batch, preço do seed) | Lista explícita de "não é contrato" na seção 3.1; revisão do diff |
| Import circular novo (`core/astro` <-> `models`; `profile_pictures` <-> `catalog_seed`) | Direção única: `core/*` não importa nada de `models/`, `data/` nem `services/`; `catalog_seed -> profile_pictures -> core/astro`; `app_user -> natal_chart`. O analyzer não detecta ciclos de pacote único, então conferir com `grep '^import' lib/core` no passo 5 |
| Testes que importam os caminhos antigos quebram | Ajuste de imports na lista de cada passo; nenhuma asserção muda |
| Detector de divergência frágil a reformatação das regras | Falha barulhenta (`padrão não encontrado`), mensagem manda ajustar teste e regras juntos; regex ancoradas em nomes de função, não em linha |
| Detector dá falso verde por pegar outro trecho com o mesmo padrão | Cada padrão é ancorado no contexto (`isCheckin`, `labelOk`, `validItem`...) e o teste de mutação prova que a alteração é vista |
| Teste depende do diretório de trabalho para achar `firestore.rules` | `flutter test` usa a raiz do pacote; se necessário usar `Directory.current` com fallback para `../firestore.rules`; documentado no cabeçalho do teste |
| Diff grande de imports dificulta revisão | Passos pequenos, um por commit; mover sem reformatar; `git diff --color-moved` |
| Conflito com a etapa 8 | Nenhum arquivo muda de nome na etapa 8 (seção 5); `core/` não se move |
| Regressão invisível de UI (cores, textos) | Passo 1 e os testes existentes cobrem seed e assets; cores são movidas sem edição; checklist manual rápido (loja, inventário, tela de conta com intenções, check-in) |

## 7. Revisão

- `reviewer` (Sonnet) revisa cada passo ou o conjunto: basta para uma refatoração pura.
- `reviewer-consultor` NÃO é necessário se valerem todas as condições: (a) `firestore.rules`, `firestore.indexes.json` e `test_rules/` sem diff; (b) nenhum valor de constante muda (conferido pelo teste de divergência e pelo passo 1); (c) o payload de `createProfile` e os defaults de `AppUser` ficam idênticos; (d) nenhuma dependência nova.
- Chamar o `reviewer-consultor` se qualquer condição falhar, em especial se o builder alterar regras, o payload de criação de usuário, a lista de intenções aceita ou a semântica de `fromDoc`/`createProfile`. Marcação para ele: apenas se o passo 3 ou 8 ultrapassarem substituição literal.
- Alinhamento com `CLAUDE.md`: a tabela de gatilhos cita "Firestore e dados pessoais"; esta etapa toca arquivos de modelo do usuário e `createProfile` apenas por substituição de constantes, então a leitura recomendada é que o `reviewer` comum confira o item (c) com o diff e o teste do passo 1. Se o orquestrador preferir seguir a letra do gatilho, uma passada curta do consultor só sobre o diff do passo 3 basta.

## 8. Critérios de aceite

- Árvore da seção 2 criada; `lib/data/astrology.dart` e `lib/data/cosmetics.dart` não existem; `lib/models/app_user.dart` só tem `AppUser`.
- Zero ocorrência dos literais `25` (check-in), `500` (saldo inicial), `'skin_classic'`, `'bg_void'` e da lista de intenções fora de `rules_contract.dart`, dos testes e do seed/estilos que usam os ids como chave (verificável por grep).
- `flutter test` inclui `rules_contract_test.dart` e falha se um valor do contrato ou das regras for alterado isoladamente (casos de mutação).
- `git diff` sem alterações em `firestore.rules`, `firestore.indexes.json`, `test_rules/` e `pubspec.yaml`.
- `flutter analyze` e `flutter test` verdes; a contagem de testes é a do passo P0 mais os novos.
- `overview.md` e `restructuring.md` refletem a nova organização e os destinos da etapa 8.

## 9. Desvios da implementação

- Passo 8 (renomes `fromFirebase`/`watchShopCatalog`) pulado por decisão do orquestrador; segue opcional.
- `data/profile_pictures.dart` nasceu no passo 5 só com `defaultProfilePictureId` (para não criar ciclo com `ItemRarity`, ainda em `cosmetics.dart`); no passo 6 recebeu `profilePictureVariants` (agora pública), `_zodiacPictureFiles` e `profilePictureAssetPath`.
- `account_screen.dart`: `intentionStyles` (id -> ícone e cor, const) e `intentions` derivada de `intentionLabels`; o teste de cobertura da UI (caso 5) usa esses dois símbolos.
- `analyticsEventNameMax` entrou no contrato (sem consumidor Dart), conferido pelo detector.
- Teste de divergência: 35 casos (regras reais, 26 mutações, 2 de padrão ausente, 5 de sanidade do contrato, 1 de cobertura de intenções). A mutação de `catalogItemTypes` ancora em `d.type in [...]` porque a lista também aparece em `equippedOk`.
- `ItemTypeSlot`, `catalogTypeName` (continua `switch`) e `rarityLabel` ficam em `models/shop_item.dart`; `rarityColor` em `theme/cosmetics_style.dart`.
- Contagem de testes: 147 (P0) -> 194. `dart format` reformatou duas linhas de exceções em `economy.dart` (movidas em seguida para `economy_exceptions.dart`) e as linhas tocadas em `app_user.dart`. Arquivos tocados foram regravados com CRLF, como o restante da árvore de trabalho.
- `npm test` de `test_rules/` não rodado (regras sem diff).
