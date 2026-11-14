# QA: etapa 7 (separar `data/` e `models/`, contrato com `firestore.rules`)

Escopo: diff não commitado da branch `feature/flutter-migration`, conforme `docs/architecture/step7-data-models.md`.
Executado em: 2026-11-14. Sem alterações em `lib/`, `firestore.rules` e `test_rules/`.

## 1. Resultado

| Verificação | Resultado |
|---|---|
| `flutter analyze` | Sem problemas |
| `flutter test` | 197 testes, todos passam (P0 da etapa: 147; etapa: 194 após os testes de `rules_contract`; QA: +3 de fronteiras) |
| Mutação no `firestore.rules` (cópia temporária, check-in `+ 25` -> `+ 26`) | Acusada: `checkInReward: Dart=25, regras=26` |
| Controle (regras originais, cópia temporária) | Sem divergência |
| Mutação no contrato Dart (`checkInReward = 26`, regras originais) | Acusada: `checkInReward: Dart=26, regras=25` |
| `git status` sobre `firestore.rules`, `firestore.indexes.json`, `test_rules/`, `pubspec.yaml` | Sem alterações |
| Arquivos `lib/data/astrology.dart` e `lib/data/cosmetics.dart` | Removidos |
| `lib/models/app_user.dart` | Só contém `AppUser` |
| `lib/core` | Não importa camadas de cima; não importa Flutter (também `lib/data`) |

Contagem da suíte de regras (`test/rules_contract_test.dart`): 35 casos = 1 (regras reais) + 26 mutações + 2 padrão ausente + 5 sanidade do contrato + 1 cobertura de intenções. O documento diz "25 mutações"; o código tem 26. Total de 35 confere.

Nenhum bug de produção encontrado.

## 2. Mapeamento: critérios e riscos do documento -> testes

### 2.1 Critérios de aceite (seção 8)

| Critério | Coberto por | Situação |
|---|---|---|
| Árvore criada; `astrology.dart`/`cosmetics.dart` removidos; `app_user.dart` só com `AppUser` | Verificação manual (ls/grep) | Atendido. Não há teste automatizado de estrutura de arquivos. |
| Zero literais `25`, `500`, `skin_classic`, `bg_void`, intenções fora do contrato (verificável por grep) | Grep manual | Atendido com exceções previstas: seed (`catalog_seed.dart`, preços 500), `moon.dart` (`0.25`), `admin_repository.dart` (`limit(500)`, batch de 500), testes (ids como dados). Não há teste automatizado. |
| `flutter test` inclui `rules_contract_test.dart` e falha em mutação isolada | `test/rules_contract_test.dart` (35 casos) | Atendido e verificado. |
| `git diff` sem alterações em regras, índices, `test_rules/`, `pubspec.yaml` | `git status` | Atendido. |
| `flutter analyze` e `flutter test` verdes; contagem = P0 + novos | Execução | Atendido (197). |
| `overview.md` e `restructuring.md` refletem a nova organização | Não testado (documentação) | Lacuna. Fora de escopo de QA automatizado. |

### 2.2 Constantes e payloads (seção 3.1 e riscos da seção 6)

| Item do contrato | Teste de divergência (regras) | Teste de valor/payload (Dart) |
|---|---|---|
| `checkInReward` 25 | mutação + real | `characterization_etapa_7_test.dart` ("check-in credita 25") |
| `initialStardust` 500 | mutação + real | payload `createProfile` (`wallet: {stardust: 500}`) |
| `defaultSkinId`/`defaultBackgroundId` | mutação x2 + real | defaults de `AppUser`, payload `createProfile`, sanidade (caso 4) |
| `defaultInventory` | mutação + real | defaults `AppUser`, payload, sanidade |
| `zodiacAvatarPrefix` | mutação + real | `profilePictureAssetPath` para todos os signos |
| `intentionLabels` (id e rótulo) | 3 mutações (`Luz`, par `clareza` removido, id `luz`) + real | cobertura de UI (caso 5) |
| `catalogItemTypes` | mutação + real | sanidade `catalogTypeName` (caso 4) |
| `roleUser`/`roleAdmin` | mutação x2 + real | payload `createProfile` (`role: user`) |
| `anonymousUserId` | mutação + real | não há teste Dart de `analytics_service` com usuário nulo |
| `analyticsEventNameMax` | mutação + real | sem consumidor Dart (esperado) |
| Limites de `users/{uid}` (nome, e-mail, signo, data, hora, local, mapa, astralMapJson, mapas, inventário) | 9 mutações + real | `SignUpLimits` = constantes (caso 4) |
| `publicNameMax`, `publicAvatarMax`, `emailHashLength` | mutação x3 + real | não aplicável |
| Padrão ausente vira falha barulhenta | 2 casos (`labelOk`, `birthPlace`) | - |
| Fronteira `lib/core` (risco de ciclo, seção 6) | `test/core_boundaries_test.dart` (adicionado nesta QA) | - |

### 2.3 Riscos (seção 6) e cobertura

| Risco | Cobertura |
|---|---|
| Alterar valor por engano ao substituir literais | Contrato x regras (mutações) e payload/defaults (caracterização). Diff literal não auditado por teste; depende de revisão. |
| Trocar 500 de contrato por 500 que não é | Só grep e revisão. Sem teste. |
| Import circular novo | `core_boundaries_test.dart` (adicionado) |
| Testes com caminho antigo | Suíte compila e roda: nenhum import quebrado |
| Detector frágil a reformatação | Padrão ausente: 2 casos testados (ver lacunas) |
| Detector com falso verde por outro trecho | Mutações com `replaceFirst` e ancoragem em contexto |
| Teste depende do diretório de trabalho | Verdadeiro: `File('firestore.rules')` relativo à raiz. Funciona em `flutter test` a partir da raiz do pacote (Windows, como rodamos). |
| Regressão de UI (cores, textos) | Caracterização de seed/asset; textos de exceções; caso 5. Sem widget test de `account_screen` ou `cosmos_screen` nesta etapa. |

## 3. Testes adicionados nesta QA

- `test/core_boundaries_test.dart` (3 testes): verifica que `lib/core` não importa `models|data|services|theme|providers|screens|widgets` nem usa `../`, e que `lib/core` e `lib/data` não importam Flutter. Inclui um teste de sanidade da regex e um de que a varredura achou arquivos (evita falso verde). Não toca regras nem `lib/`.

Nenhum outro teste foi acrescentado: as lacunas abaixo são de cobertura adicional e não justificam mais código nesta etapa de refatoração pura.

## 4. Lacunas (não testado ou testado parcialmente)

1. `findRulesDivergences` testa padrão ausente em só 2 de 26 padrões. Os demais caem no mesmo `missing()`, mas não há teste direto. Risco baixo.
2. Mutação de `profileMapFieldMaxKeys` só cobre `dailyTarot`; `astrologyData` e `dailyHoroscope` usam o mesmo código de comparação, mas não têm mutação própria.
3. O detector usa `Map` por nome em `optStr`/`optMap`: se o mesmo campo aparecer duas vezes nas regras, a última ocorrência vence. Hoje cada campo aparece uma vez (verificado por grep). Risco se alguém duplicar.
4. Extração de `labelOk` por regex lazy até `\n\s*}`: funciona com o formato atual; reformatação da função pode gerar falso "padrão não encontrado" (falha barulhenta, não silenciosa).
5. Comportamento real das regras não foi verificado: `npm test` de `test_rules/` não rodado (regras sem diff; o próprio documento dispensa). Emulador não iniciado; porta 8091 não usada.
6. Sem widget test para `account_screen` (intenções renderizadas), `cosmos_screen` (texto "+25 Poeira Estelar") nem `shop_screen`/`inventory_screen` (rótulos e cores de raridade). Cobertura é só de unidade e de dados.
7. Passo 8 (renomes `fromFirebase`/`watchShopCatalog`) pulado, como registrado no documento. `AppUser.fromFirebase` continua em uso (`profile_repository`, `admin_repository`, testes).
8. `overview.md` e `restructuring.md` não foram revisados (documentação).
9. Documento: "25 mutações" deveria ser "26" (contagem real). Não impacta o resultado; sugerido corrigir na seção 9.
10. Não verificado: cadastro, loja, perfil, mapa astral, horóscopo, check-in e admin na execução real. Ver checklist.

## 5. Checklist manual para o usuário (app em dispositivo ou emulador, com projeto de teste)

Conferir que o comportamento não mudou (refatoração pura):

- [ ] Cadastro: criar conta; a tela de cadastro aceita nome, e-mail, signo, data, hora e local com os mesmos limites de antes (nome 100, e-mail 254, local 200). Após cadastro, o perfil mostra 500 Poeira Estelar e o inventário com a skin e o fundo padrão.
- [ ] Loja: itens base (skin clássica, fundo vazio), avatares zodiacais gratuitos e a compra de um item pago (ex.: skin dourada 2000). Preços e raridades iguais aos de antes; cores de raridade inalteradas.
- [ ] Inventário: itens possuídos aparecem; os equipados batem com o perfil; avatar zodiacal mostra a imagem certa.
- [ ] Perfil / conta: intenções (Luz, Coragem, Cura, Clareza) aparecem na mesma ordem, com o mesmo ícone e cor; salvar uma intenção grava o rótulo esperado.
- [ ] Mapa astral: signo solar, elementos e glifos iguais aos de antes; sinergia entre dois perfis mostra o mesmo resultado.
- [ ] Horóscopo / oráculo: textos e signos carregam sem erro de asset.
- [ ] Check-in diário: primeiro check-in do dia credita 25 (saldo passa de X para X+25); o texto diz "+25 Poeira Estelar"; segundo check-in no mesmo dia mostra "Você já fez o check-in de hoje.".
- [ ] Admin: lista de usuários e eventos de analytics carregam; eventos sem login aparecem como anônimos (não contados como usuários únicos).

Se algum item divergir do comportamento anterior, reportar antes de commit.

## 6. Como reproduzir a validação do detector

1. Copiar `firestore.rules` para fora do repositório (diretório temporário).
2. Trocar `newStar() == oldStar() + 25` por `+ 26` na cópia.
3. Rodar `findRulesDivergences` (função pura de `test/support/rules_contract_check.dart`, com `rules_contract.dart` copiado e o import ajustado para relativo) sobre o texto da cópia.
4. Esperado: `checkInReward: Dart=25, regras=26`.

Feito nesta QA; o repositório não foi alterado.

## 7. Comandos executados

- `flutter analyze`: "No issues found!"
- `flutter test` (suíte completa): 197 testes, "All tests passed!"
- `flutter test test/core_boundaries_test.dart test/rules_contract_test.dart`: 38 testes, verde
- `git status` sobre regras, índices, `test_rules/`, `pubspec.yaml`: sem alterações
- Mutações em cópia temporária (scratchpad): ver seção 6

Não executados: `npm test` de `test_rules/` (dispensado pelo documento; regras sem diff).
