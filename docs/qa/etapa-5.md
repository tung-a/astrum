# QA da etapa 5: escritas tipadas no perfil e no equipar

Data: 2026-11-14. Escopo: diff não commitado da etapa 5 (`docs/architecture/step5-typed-writes.md`) e seção "Itens abertos da etapa 5" de `docs/plans/reestruturacao-etapas-1-a-3.md`. Nenhum código de `lib/` ou de `test_rules/` versionado foi alterado. Testes acrescentados só para lacunas simples.

## 1. Resultado resumido

| Verificação | Resultado |
|---|---|
| `flutter analyze` | Sem problemas (exit 0), antes e depois dos testes novos |
| `flutter test` | 95 passaram, 0 falharam (eram 92; +3 novos) |
| `git diff -- firestore.rules test_rules/` | Vazio (verificado) |
| `npm test` em `test_rules/` (comando literal, porta 8080) | NÃO EXECUTADO. A 8080 está ocupada por `java.exe` PID 16132, de outra sessão. Não foi encerrado |
| `npm test` em cópia fora do repositório, porta 8090 | 37/37 passaram (exit 0) |
| Caso extra na cópia (não versionado): dono reescreve `wallet` inteiro como mapa | Negado pela regra (38/38 na cópia) |

**Incidente (ação necessária do usuário):** na primeira execução da cópia, o teste ainda apontava para a porta 8080. Em `test_rules/firestore.rules.test.mjs`, linha 33, `initializeTestEnvironment` usa `port: 8080` fixo, e o `beforeEach` (linha 38) chama `env.clearFirestore()`. Essa execução conectou no emulador do PID 16132, de outra sessão. Os "37 passaram" desta execução são inválidos e o emulador 16132 pode ter tido os dados apagados. Não há como restaurar isso daqui. Recomenda-se verificar esse emulador. A execução válida é a da 8090, depois que a cópia foi corrigida para `port: 8090`. A suíte versionada não foi alterada e a 8080 não foi tocada depois disso.

Processos órfãos: `emulators:exec` deixou `java.exe` filhos escutando na 8090 (PIDs 23132, 13688 e 19832). Os três foram iniciados por esta sessão (a linha de comando aponta para a cópia no scratchpad) e foram encerrados. Vale registrar isso para o devops.

## 2. Casos executados e mapeamento critério → teste

Legenda: PASSOU = teste existente verde; NOVO = acrescentado nesta QA; PARCIAL = coberto em parte; LACUNA = sem teste automatizado (ver seção 3).

### 2.1 Restrições (seção 0 do step5)

| Critério | Cobertura | Situação |
|---|---|---|
| `firestore.rules` e `test_rules/` sem mudança | `git diff` vazio | PASSOU (inspeção) |
| Mesmas chaves gravadas no Firestore | `repositories_firestore_test.dart`: "setNotificationsEnabled e setShowSign...", "equip(skin) e equip(background)...", "saveAstralMap...", "saveDailyHoroscope e saveDailyTarot..."; `economy_repository_test.dart` e `qa_etapa_4_test.dart` (equipSlot) | PASSOU |
| Mesmas exceções | `saveAstralMap` com lista vazia lança `StateError` e não grava (PASSOU); exceções de compra e check-in (`economy_repository_test.dart`) | PASSOU |
| Ordem: `users` antes do sync de `publicProfiles` | Não há asserção de ordem. Indiretamente, o teste B1 de `equip` mostra que `users` já está gravado quando o sync falha | PARCIAL (ver L4) |
| `analyze` e `test` verdes | Seção 1 | PASSOU |

### 2.2 `EquipSlot`, `EquipSlotField`, `ItemTypeSlot` (passo 1)

| Critério | Teste | Situação |
|---|---|---|
| `fieldPath` igual aos três literais | `equip_slot_test.dart`: "fieldPath igual aos literais gravados no Firestore" | PASSOU |
| Só `profilePicture` toca o perfil público | `equip_slot_test.dart`: "so profilePicture toca o perfil publico" | PASSOU |
| `ItemType` mapeia para slot distinto e para o `fieldPath` esperado | `equip_slot_test.dart`: "ItemType.slot mapeia..." e "todo ItemType mapeia para um slot distinto" | PASSOU |
| `encodeAstralMap` faz round-trip com `parseAstralMap` | `equip_slot_test.dart`: "encodeAstralMap faz round-trip..." | PASSOU |
| `encodeAstralMap` lança `StateError` em lista vazia | `equip_slot_test.dart`: "encodeAstralMap lanca StateError em lista vazia" | PASSOU |
| `encodeAstralMap` gera o mesmo texto do `jsonEncode` antigo da tela | `equip_slot_test.dart`: "encodeAstralMap gera o mesmo texto do jsonEncode antigo da tela" | NOVO, PASSOU |

### 2.3 `ProfileRepository` (passo 2) e sync por tipo (2.3 do step5)

| Critério | Teste | Situação |
|---|---|---|
| `equip(profilePicture)` grava `equipped.profilePicture` e sincroniza (avatar novo, nome e hash preservados) | `repositories_firestore_test.dart`: "equip(profilePicture) grava a chave e sincroniza publicProfiles" | PASSOU |
| `equip(skin)` e `equip(background)` gravam sem sincronizar | "equip(skin) e equip(background) gravam sem sincronizar" | PASSOU |
| `setNotificationsEnabled` e `setShowSign` gravam só a sua chave, sem sync | "setNotificationsEnabled e setShowSign gravam so a sua chave, sem sync" | PASSOU |
| `saveAstralMap` grava `astralMapJson` e `zodiacSign`, sem sync | "saveAstralMap grava astralMapJson e zodiacSign sem sync" | PASSOU |
| `saveAstralMap` com lista vazia não grava | "saveAstralMap com lista vazia lanca StateError sem gravar" | PASSOU |
| `saveDailyHoroscope` e `saveDailyTarot` gravam as chaves esperadas | "saveDailyHoroscope e saveDailyTarot gravam as chaves esperadas" | PASSOU |
| Nenhum método tipado altera `wallet`, `inventory`, `role`, `dailyCheckIn`, `name`, `email` | "nenhum metodo tipado altera wallet/inventory/role/dailyCheckIn" (executa todos os métodos com valores fixos e compara). A ausência de método público que aceite `Map` ou caminho foi verificada por inspeção de `profile_repository.dart` (só `_update` privado) | PASSOU (teste + inspeção) |
| Sync só no avatar, nunca em skin, fundo, preferências, `zodiacSign` | Testes acima; `PublicProfileSync.touches` removido, sem referência em `lib/` nem `test/` (grep) | PASSOU |
| M3 caracterizado: `equip(profilePicture)` ignora `preferences.publicProfile=false` | `qa_etapa_4_test.dart`: "equip(profilePicture) com preferences.publicProfile=false ignora a preferencia..." | PASSOU |

### 2.4 `EconomyRepository.purchaseItem` com `equipSlot` (passo 4)

| Critério | Teste | Situação |
|---|---|---|
| Compra paga com `equipSlot` debita, acrescenta ao fim e equipa | `economy_repository_test.dart`: "sucesso: debita, acrescenta ao fim do inventario e equipa" | PASSOU |
| Sem `equipSlot`, não altera `equipped` nem `publicProfiles` | "sem equipSlot nao altera equipped nem publicProfiles" | PASSOU |
| `equipSlot = profilePicture` sincroniza `publicProfiles` | "equipar foto de perfil sincroniza publicProfiles" | PASSOU |
| `equipSlot = skin` não sincroniza | "equipar skin nao sincroniza publicProfiles" | PASSOU |
| Saldo insuficiente, inativo, inexistente, já possuído: lança e não grava | `economy_repository_test.dart` (5 testes) | PASSOU |
| Compra gratuita com equipar | `qa_etapa_4_test.dart`: "compra gratuita..." | PASSOU |
| Perfil inexistente lança `StateError` | `economy_repository_test.dart` | PASSOU |
| `dailyCheckIn` inalterado | `economy_repository_test.dart` (4 testes) | PASSOU |

### 2.5 Riscos (seção 7 do step5)

| Risco | Cobertura | Situação |
|---|---|---|
| R1 (alto): `purchaseItem` muda a chave de equipar | Golden de `fieldPath`, testes de transação, `npm test` na cópia | PASSOU |
| R2 (médio): regressão silenciosa de sync | Skin e fundo sem sync (testes acima) | PASSOU |
| R3 (latente): `saveAstralMap` altera `zodiacSign` sem sync, avatar público defasado | NOVO: "M1 (caracterizacao): saveAstralMap troca zodiacSign mas nao regrava publicProfiles existente". Documenta o comportamento atual, que é o defeito | NOVO, PASSOU |
| R4 (baixo): `saveAstralMap` vazio | Teste acima | PASSOU |
| R5 (baixo): `createProfile` continua gravando `role/wallet/inventory` | "createProfile: saldo 500, inventario padrao..." (`qa_etapa_4_test.dart`) | PASSOU |
| R6: M1 e M3 abertos | M3: caracterizações (`rebuildPublicProfiles` com `publicProfile=false`, `equip` ignora a preferência). M1 (admin sem permissão no `publicProfiles` de terceiros): não reproduzível com `fake_cloud_firestore`, que não aplica regras | PARCIAL (L1) |

### 2.6 Desvios documentados no step5

| Desvio | Cobertura | Situação |
|---|---|---|
| `saveAstralMap` é `async` (StateError chega como erro do Future) | "saveAstralMap com lista vazia lanca StateError sem gravar" usa `expectLater` | PASSOU |
| Teste de M3 grava `publicProfile=false` direto e chama `equip(profilePicture)` | `qa_etapa_4_test.dart`, grupo "perfil publico e LGPD (M3, caracterizacao)" | PASSOU |

### 2.7 Itens abertos da etapa 5 (plano)

| Item | Cobertura | Situação |
|---|---|---|
| I1 (M1, LGPD): avatar zodiacal `pfp_zodiac_<signo>` visível mesmo com `showSign=false`; `saveAstralMap` sem sync | Caracterização de R3 acima. O vazamento do signo pelo avatar não é testável com o fake (depende de regra e de UI) | PARCIAL. Decisão não registrada em `docs/decisions/` (grep sem resultado) |
| I2 (B1 do consultor): teste de regras no emulador para escrita de `wallet` pelo dono | `test_rules`: casos com `wallet.stardust` (linhas 84-85, 95-110, 256-271). Escrita de `wallet` inteiro como mapa não está no suite versionado. Caso extra na cópia: negado (PASSOU) | LACUNA no suite versionado (L2) |
| I3 (B3 do consultor): `admin_screen.dart` usa `FirebaseFirestore.instance` direto | Não coberto. Confirmado: linhas 112, 124, 126 e 158 ainda usam o acesso direto | LACUNA, fora do escopo da etapa 5 (etapa 6) |

## 3. Lacunas

- **L1 (M1 e M3, LGPD).** Sem decisão registrada em `docs/decisions/`. Os testes são de caracterização e documentam o comportamento atual, não o desejado. Quando a decisão sair, os testes de caracterização de M3 e de R3 devem ser atualizados junto com a correção.
- **L2 (B1 do consultor, regras de `wallet`).** O suite `test_rules/` versionado não tem o caso "dono reescreve `wallet` inteiro como mapa", e não é permitido alterá-lo nesta tarefa. Caso equivalente na cópia (`updateDoc(ref, { wallet: { stardust: 9999 } })`, com e sem `inventory` junto): negado. Sugestão: adicionar esse caso ao `test_rules/firestore.rules.test.mjs` em tarefa própria. O fluxo do repositório (`purchaseItem`) não pode ser testado em `test/` porque o fake não aplica regras.
- **L3 (B3).** `admin_screen.dart` ainda grava e lê direto no Firestore. Fica para a etapa 6.
- **L4 (ordem das escritas).** Não há asserção de que `users/{uid}` é gravado antes de `publicProfiles`. Só é indiretamente verificado pelo teste de B1 de `equip`.
- **L5 (telas).** Nenhum teste de widget cobre `account_screen`, `astral_screen`, `cosmos_screen`, `inventory_screen` ou `shop_screen` depois da migração. As trocas de chamada são simples, mas o caminho "já possuído: equipa sem cobrar" da loja não tem teste automatizado. Coberto pelo checklist manual (seção 4).
- **L6 (B1 em produção).** `fake_cloud_firestore` não simula concorrência, retry de transação nem regras. A falha parcial entre `users` e `publicProfiles` é caracterizada, não corrigida (opção B do step5, decisão pendente).
- **L7 (`npm test` literal).** Não executado, porque a 8080 está ocupada. Rodar só com a 8080 livre e sem emulador de outra sessão. Como `test_rules` fixa `port: 8080`, a execução sem alterar o arquivo só é segura quando a 8080 estiver livre; a cópia com `port: 8090` é o caminho seguro enquanto isso.
- **L8 (`saveAstralMap` com múltiplos planetas).** Só o caso de um planeta é testado. `zodiacSign` recebe `chart.first.sign`, e o teste de round-trip cobre a lista inteira. Risco baixo.

## 4. Checklist manual para o usuário (app em emulador ou dispositivo)

Pré-requisitos: usuário de teste logado, com saldo de stardust suficiente, e um segundo usuário para a busca de amigo. Rodar com `flutter run --dart-define-from-file=.env` no emulador do projeto, nunca no emulador de outra sessão.

1. **Equipar skin.** Inventário > escolher uma skin possuída > "equipado" aparece no SnackBar. Conferir em `users/{uid}`: `equipped.skin` novo. Conferir que `publicProfiles/{uid}` não mudou.
2. **Equipar fundo.** Mesmo fluxo com fundo. Conferir `equipped.background`. Sem mudança em `publicProfiles`.
3. **Equipar avatar.** Inventário > foto de perfil possuída. Conferir `equipped.profilePicture` e `publicProfiles/{uid}.avatar` com o novo valor. `name` e `emailHash` preservados.
4. **Busca de amigo com avatar.** Com o usuário do passo 3, buscar pelo e-mail a partir do segundo usuário. O avatar novo deve aparecer no resultado.
5. **Comprar e equipar (loja).** Comprar um item não possuído com a opção de equipar. Conferir: saldo debitado uma vez, item no fim de `inventory`, `equipped.*` com o item. Se for foto de perfil, `publicProfiles.avatar` também atualizado.
6. **Loja, item já possuído.** Tocar em um item possuído. Deve equipar sem debitar saldo nem alterar `inventory`.
7. **Preferências.** Em Conta, alternar "notificações" e "mostrar signo". Conferir `preferences.notifications` e `preferences.showSign` em `users/{uid}`. Recarregar o app e confirmar que o estado persiste. Conferir que `publicProfiles` não foi alterado.
8. **Mapa astral.** Em Astral, "Calcular mapa no dispositivo". Conferir `astralMapJson` (string JSON) e `zodiacSign` (signo do primeiro planeta) em `users/{uid}`. A tela deve mostrar os planetas após recarregar.
9. **Horóscopo do dia.** Em Cosmos, gerar horóscopo. Conferir `dailyHoroscope.date` (hoje) e `dailyHoroscope.content`.
10. **Tarô do dia.** Em Cosmos, puxar carta. Conferir `dailyTarot.{date, card, meaning}`. Se a gravação falhar, a SnackBar "Não foi possível salvar a carta" deve aparecer.
11. **Erro simulado (opcional).** Desligar a rede e equipar avatar. Deve aparecer erro na tela, e o `equipped.profilePicture` pode já estar gravado (comportamento atual, B1). Registrar o resultado.

## 5. Não testado e por quê

- `npm test` literal em `test_rules/`: porta 8080 ocupada por outra sessão (seção 1 e L7).
- Caso "wallet inteiro" no suite versionado: vetado nesta tarefa (L2).
- Telas e fluxos de UI: sem teste de widget para as cinco telas alteradas. Coberto pelo checklist manual (L5).
- Regras reais e concorrência de transação: `fake_cloud_firestore` não aplica regras nem simula contenção (L6).
- Opção B (atomicidade): não implementada, por decisão do usuário.
- M1 e M3: dependem de decisão do usuário (L1).
