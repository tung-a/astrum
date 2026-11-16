# QA da etapa 12: aceite de amizade

> **Nota:** este documento partiu do relato do builder (commit `85eb0fc`). Esta versão é a rodada independente do QA: confere cada critério e risco de `docs/architecture/step12-friend-requests.md` contra os testes existentes, executa as suítes, corrige as contagens do relato e registra achados, lacunas e o checklist manual.

Data: 2026-11-16. Branch: `feature/flutter-migration`. Base de comparação: `git diff 0a244a7..HEAD` (commit de QA sobre `85eb0fc`).

## 1. Resultado da execução

| Verificação | Resultado |
|---|---|
| `flutter analyze` | No issues found (exit 0) |
| `flutter test`, antes dos testes novos desta rodada | 524 passaram, 0 falharam |
| `flutter test`, com os 8 testes novos desta rodada | **532 passaram, 0 falharam** (exit 0) |
| `npm test` em `test_rules/` (emulador na porta 8091) | **87 passaram, 0 falharam** (exit 0) |

Correções ao relato do builder: a tabela dizia `flutter test` 522 e regras 81; a execução mostrou 524 antes dos testes novos e **87** nas regras (a contagem de 87 também é a do checklist 6c e do arquivo `firestore.rules.test.mjs`, que tem 87 `test(`). A nota de topo falava em 524 e 87, a tabela em 522 e 81: agora fica um número só.

Ambiente das regras: a porta 8091 foi conferida livre com `Get-NetTCPConnection` antes da execução; a saída foi redirecionada para arquivo (sem pipe). Ao fim, o emulador iniciado pela execução (cmd com `--port 8091`) continuou ativo; encerrei somente esse processo e confirmei a porta livre. Os três java.exe do Gradle e do Kotlin (Android Studio) não foram tocados. `test_rules/` e `firestore.rules` não foram alterados.

## 2. Achados (bugs e divergências)

Nenhum achado bloqueia a release do ponto de vista de segurança: as regras negam o que o documento pede. Os achados abaixo são de UX e de documentação. Não foram corrigidos (`lib/` é do builder).

### A1. Escritas offline de aceitar, recusar, remover, cancelar e desbloquear não mostram "Sem conexão" (média, a confirmar no aparelho)

- **Esperado** (checklist 6c e seção 7 do arquivo de arquitetura): em modo avião, pedir e aceitar mostram "Sem conexão. Tente de novo quando estiver online.".
- **Causa provável** (código lido, comportamento do SDK inferido): `FriendshipController._errorText` só traduz `unavailable` e `deadline-exceeded`. Pedir usa `runTransaction`, que exige servidor e deve falhar offline com `unavailable`, o que mostraria a mensagem. Aceitar, recusar, remover, cancelar e desbloquear usam `ref.update` e `ref.delete` simples; o SDK do Firestore tende a enfileirá-los offline e a `Future` só completa com a confirmação do servidor. Nesse caso nenhum erro sobe, o botão continua desabilitado (`_busy`) e a mensagem não aparece até a reconexão.
- **Por que não está reproduzido aqui**: `fake_cloud_firestore` não modela offline. A conclusão é inferência do comportamento do SDK, a ser confirmada no aparelho.
- **Como reproduzir**: conta B com um pedido recebido de A; B ativa modo avião; B toca "Aceitar" e observa o snackbar e o estado do botão; depois reconecta e verifica se o aceite aparece uma vez só.
- **Tratamento sugerido**: envolver as escritas simples em `Source`/timeout como já se faz em `paged_delete.dart` e no `profile_repository` (`ServerOfflineException`), ou corrigir o texto da checklist se o comportamento real for "fila silenciosa". Até lá, o item manual M9 do checklist registra o resultado observado.

### A2. Cancelar um pedido que o outro aceitou no intervalo mostra "Pedido cancelado." (baixa)

- `FriendshipController.cancel` traduz `ActionOutcome.gone` para "Pedido cancelado.". O `gone` cobre a recusa silenciosa (correto) e também o caso em que o destinatário **aceitou** entre a tela carregar e o toque: a regra nega o `delete` (o documento está `accepted`), `_act` relê, vê `accepted` e devolve `gone`.
- **Resultado**: o usuário lê "Pedido cancelado." e o item vira amizade na lista de amigos, sem o aviso correto ("Vocês já são amigos." ou "Esta amizade não existe mais.").
- **Teste que fixa o comportamento**: `test/features/social/presentation/friendship_controller_test.dart`, caso "cancelar recusado em silencio", que assevera `Pedido cancelado.` também para `gone` de um pedido pendente. Não alterei esse teste (ele é do builder e a correção é de `lib/`).
- **Como reproduzir**: A envia pedido a B; B aceita; A, com a tela de Enviados ainda desatualizada (janela curta, ou A offline com cache antigo), toca "Cancelar pedido".

### A3. Documentação: textos da seção 7 incompletos (baixa)

- A seção 7 do arquivo de arquitetura lista os snackbars, mas não inclui "Desbloqueado. Você pode buscar essa pessoa de novo.", que existe no código e está testado. Sugestão para o writer: acrescentar.

### A4. Relato do builder com contagens desatualizadas (corrigido aqui)

- Contagens de 522 e 81 trocadas pelas medidas (524 antes, 532 com os novos; 87 nas regras). Ver seção 1.

## 3. Testes novos desta rodada

Criados sem alterar nenhum arquivo existente, em português, com fakes (nenhum depende de rede ou credencial):

| Arquivo | Casos | O que cobre |
|---|---|---|
| `test/features/social/presentation/friendship_flow_test.dart` | 5 | Fluxo entre duas contas (Ana e Bruno) com `SocialRepository` real sobre `FakeFirebaseFirestore` e um `ProviderContainer` por conta: (1) buscar, enviar, ver em Enviados, aceitar no outro lado, selo zerado e intenção gravada na caixa do destino; (2) recusa silenciosa uniforme (quem recusa vê "Recusados e removidos"; quem pediu vê "Enviados", "já enviou" ao pedir de novo, cancelar sem escrita e lápide preservada); (3) remover dos dois lados, bloqueio próprio, pedido genérico de quem foi removido e desbloqueio que libera novo pedido; (4) pedido cruzado pela busca vira amizade num único documento; (5) busca desligada no destinatário dá a mesma frase que e-mail inexistente e não grava nada |
| `test/app/main_shell_badge_singular_test.dart` | 3 | Selo do Perfil: rótulo no singular "1 pedido de amizade"; pedido enviado não conta no selo; selo some quando o pedido recebido vira amizade (o stream atualiza a tela) |

Resultado: os 8 passaram.

Limite honesto dos testes novos: `fake_cloud_firestore` não avalia regras. O que o servidor aceita fica em `test_rules/`. O fluxo novo verifica a lógica (textos, listas nos dois lados, selo, cota, lápide), não a contenção de transações nem o offline.

## 4. Rastreabilidade (critérios, riscos e desvios → teste ou lacuna)

Legenda: **Auto** = teste existente; **Novo** = teste criado nesta rodada; **Manual** = checklist da seção 6; **Lacuna** = não coberto, com motivo.

### 4.1 Critérios de aceite (arquitetura, seções 2, 4, 6, 7, 9 e 11)

| Critério | Cobertura | Onde |
|---|---|---|
| Documento único `friendships/{pairId}`, `pairIdOf` igual à regra | Auto | `friendship_test.dart` (tabela de pares); `rules_contract_test.dart` (separador) |
| Máquina de estados (pendente, aceito, recusado; quem pode cada transição) | Auto | `test_rules` (aceite, recusa e lápide, remoção, cancelar, desbloqueio) |
| Create: a si mesmo, uids desordenados, id divergente, `requesterUid` alheio, `status` ≠ pending, `requesterName` falso, campo extra, `createdAt` sem `request.time`, sem perfil, destino sem `users`, destino sem `publicProfiles`, anônimo, terceiro | Auto | `test_rules` (friendships create, 3 casos) |
| Duplicata e pedido cruzado negados na regra; o outro lado aceita | Auto | `test_rules` (duplicata e cruzado) |
| Aceite só pelo não remetente; remetente, terceiro, anônimo e admin negados; campos imutáveis; `responderName` falso; aceite duplo; remetente excluído | Auto | `test_rules` (aceite, 4 casos) |
| Recusa e lápide: remetente não recria, altera nem apaga; quem recusou desbloqueia | Auto | `test_rules` (recusa e lápide; desbloqueio) |
| Remover amizade aceita por qualquer membro; terceiro negado | Auto | `test_rules` (remoção) |
| Cancelar só o próprio pendente; `accepted` não é apagado | Auto | `test_rules` (cancelar) |
| Exclusão de conta apaga qualquer relação própria (lápide inclusive); terceiros não | Auto | `test_rules` (exclusão de conta) |
| Leitura: `get` do par próprio (inclusive inexistente); `array-contains` do próprio uid; admin, collection group e par alheio negados | Auto | `test_rules` (leitura, 2 casos) |
| Intenção só entre amigos aceitos (nos dois sentidos); sem relação, pendente, recusada e removida negadas; `users/{uid}/friends` negado | Auto | `test_rules` (passo 6, 2 casos + "modelo antigo") |
| `publicProfiles` com `limit(1)` em `list` (passo 7) | Auto | `test_rules` (publicProfiles list) |
| UIDs reais de 28 caracteres | Auto | `test_rules` |
| Batch de 400 deletes (cascata) passa nos limites de `exists()` | Auto | `test_rules` |
| Repositório: pedido, cruzado sequencial, duplicata, aceite duplo idempotente, remover, cancelar, desbloquear, consulta só do uid, `deleteAllFriendships` (450 docs), erros | Auto | `social_repository_friendship_test.dart` |
| Transação do cruzado sob contenção real (duas transações simultâneas) | Manual | Lacuna: `fake_cloud_firestore` não reproduz contenção (ver seção 5, L3) |
| Controller: textos, cota de 20 (cliente), mensagens genéricas idênticas, offline neutro, `sendIntention` com amizade desfeita | Auto | `friendship_controller_test.dart`; `account_controller_test.dart`; `account_deletion_data_test.dart` |
| Tela de pedidos: carregando, vazio, erro com "Tentar de novo", aceitar, recusar, falha, enviado, recusado silencioso, desbloquear | Auto | `friend_requests_screen_test.dart` |
| Conta: enviar com confirmação do nome, cancelar a confirmação, e-mail desconhecido genérico, remover com diálogo, cartão "Pedidos de amizade (n)" | Auto | `account_friends_test.dart` |
| Selo no ícone Perfil com a contagem de recebidos (inclusive singular, enviado não conta, some ao aceitar) | Auto + Novo | `main_shell_badge_test.dart`; `main_shell_badge_singular_test.dart` |
| Fluxo de duas contas (buscar, enviar, Enviados, aceitar no outro lado, remover, desbloquear) | Novo | `friendship_flow_test.dart` (ver seção 5, L1, para o que fica fora) |
| Cascata de exclusão chama `deleteAllFriendships` nas duas passadas, com o rótulo novo | Auto | `delete_account_controller_test.dart` (log `friendships.deleteAll`, 3 ocorrências) |
| Provedor de amigos não reabre o stream quando o saldo muda | Auto | `providers_subscriptions_test.dart` |
| Constantes Dart × regras (status, separador, limite de nome, aceito nas intenções) | Auto | `rules_contract_test.dart`; `test/support/rules_contract_check.dart` |
| Sem índice novo; `firestore.indexes.json` não mudou | Verificado | `git diff 0a244a7..HEAD -- firestore.indexes.json` vazio |
| Texto da tela de exclusão (amizades e pedidos; nome deixa de aparecer) | Parcial | `delete_account_screen_test.dart` confere a presença da constante, não o texto literal (lacuna baixa, L8) |

### 4.2 Riscos (seção 13)

| Risco | Cobertura | Situação |
|---|---|---|
| R-S1 Sem teto de pedidos no servidor | Cota de 20 no cliente: Auto (`friendship_controller_test`). Teto no servidor: não existe (Spark) | Aceito. Não há teste de "o servidor aceita 21", por design |
| R-S2 Enumeração de `publicProfiles` | `test_rules`: `list` sem limite, `limit > 1`, sem filtro e anônimo negados; `limit(1)` permitido | Parcial: a varredura paginada com `limit(1)` + `startAfter` continua possível, por design. Aceito até o App Check |
| R-S3 `split('_')` e uids com `_` | `test_rules`: uid com `_` negado; uids de 28 caracteres ok | Coberto |
| R-S4 Lápide impede reconciliação após recriar a conta | `test_rules`: exclusão apaga a lápide; caracterização R-S8 | Coberto |
| R-S5 Leitura de regras falha sem perfil (fecha) | `test_rules`: create sem perfil do remetente negado; remetente sem `users` no aceite negado | Parcial: falta caso de `update` (aceite ou recusa) por quem não tem perfil. Lacuna L6, baixa |
| R-S6 Contas de teste com `friends` legado | `test_rules`: `users/{uid}/friends` negado (create, read, delete) | Coberto. Limpeza das contas: manual (M14) |
| R-S7 Nome copiado não acompanha edição | Não há edição de nome no app; backlog | Aceito, sem teste (fora do escopo atual) |
| R-S8 Contorno da lápide refazendo o perfil | `test_rules`: "R-S8 (caracterizacao)" | Coberto e aceito |

### 4.3 Desvios da implementação (seção 16)

| Desvio | Cobertura |
|---|---|
| Regras de `update` separadas por transição (aceite com `responderName` sem `declinedBy`; recusa sem `responderName`) | `test_rules`: campos do aceite e `responderName` junto da recusa negados |
| Nome do destinatário em "Enviados" vem de `publicProfiles` ("Viajante" se oculto) | `friend_requests_screen_test.dart` ("Cris" e "Viajante") |
| "Enviados" só na tela `/account/requests`, não na conta | `account_friends_test.dart` (cartão com o contador) |
| Recusa silenciosa (remetente continua "Aguardando resposta"; cancelar só esconde; "já enviou" ao pedir de novo; não conta na cota) | Auto (controller, repositório, tela) + Novo (fluxo, teste 2) |
| Pedido cruzado simultâneo garantido pela transação | Sequencial: Auto + Novo (fluxo, teste 4). Simultâneo: Manual (M7) |
| Limite de 400 deletes na cascata | `test_rules` (batch de 400) + `social_repository_friendship_test` (450) |
| Designer sem documento em `docs/design/` | Não aplicável a teste |
| Sem push | Não aplicável a teste |

### 4.4 Checklist 6c (`docs/release-checklist.md`)

| Item | Situação |
|---|---|
| Ordem de implantação (regras, cliente, regras finais) | Manual (M13). Ver seção 6.1 |
| `test_rules` com 87 testes em porta livre | Auto: executado nesta rodada, 87 passaram |
| Dois aparelhos: pedir, selo, aceitar, intenção nos dois sentidos, recusar, remover, desbloquear, cruzado | Manual (M1 a M7). O fluxo lógico está em Novo |
| Busca desligada em B: A recebe a mensagem genérica; pedidos existentes continuam | Auto (regra + fluxo, teste 5). Manual (M8) |
| Modo avião: "Sem conexão" ao pedir e aceitar | **Divergência provável (A1)**. Manual (M9) |
| Excluir conta com amizades: relações somem para a outra pessoa | Auto (cascata, regras, repositório). Manual (M11) |
| Risco R-S8 e R-S1 aceitos | Auto (caracterização e cota). Aceito |

## 5. Lacunas: o que não foi testado e por quê

| # | Lacuna | Motivo |
|---|---|---|
| L1 | Fluxo de duas contas na **UI** (widgets reais dos dois lados) | O fluxo foi coberto no nível controller + repositório real + fake firestore (teste 1 a 5). A UI de cada tela tem widget test próprio. Um teste de widget com troca de identidade entre as duas contas seria frágil e pouco ganho |
| L2 | Offline real (fila do SDK, pedido em modo avião) | `fake_cloud_firestore` não modela offline. Coberto só pelo mapeamento de erro. Manual M9 |
| L3 | Pedido cruzado **simultâneo** (contenção de transação) | Não reproduzível com o fake. Coberto o caso sequencial. Manual M7 |
| L4 | Enforcement real das regras no cliente (o que o servidor nega em tempo real) | Não se aplica ao fake. Coberto em `test_rules` (87 testes) |
| L5 | Exclusão de conta de ponta a ponta contra o servidor real | Exige contas reais e Admin. Coberto pela cascata nos testes unitários e regras. Manual M11 |
| L6 | R-S5: `update` (aceite ou recusa) por quem não tem perfil | Sem caso explícito em `test_rules`. A regra tem `exists(meDoc())` no `update`, mas não há teste direto. Baixa |
| L7 | Varredura paginada de `publicProfiles` com `limit(1)` | Aceito (R-S2). Não há teste de "permitido", só de negação |
| L8 | Texto literal da tela de exclusão | `delete_account_screen_test.dart` confere a constante, não o texto. Baixa |
| L9 | Revisão do `reviewer-consultor` (passos 1, 6 e 7) | Processo do agente, não é teste. Não verificado por este QA |
| L10 | Migração e limpeza de `users/*/friends` em contas de teste | Operacional (console ou `scripts/audit_users.md`). Manual M14 |
| L11 | Efeito de A2 (cancelar aceito no intervalo) em tela real | Coberto só pelo controller (teste fixa o comportamento). Manual, opcional |

## 6. Checklist manual para o dono (dois aparelhos)

Preparação:
- Aparelho A (conta A) e aparelho B (conta B), contas de teste sem amizades entre elas. Uma terceira conta C para o item de recusa.
- Regras e cliente na mesma janela (item 6.1). Antes: limpar `users/*/friends` das contas de teste (M14).
- Anotar o resultado de cada item: passou, falhou (com print e passos) ou não se aplica.

### 6.1 Ordem de implantação (M13)

- [ ] Antes de começar, o cliente novo está pronto para distribuição (build com `--dart-define-from-file=.env`).
- [ ] Publicar o catálogo (item 3.1 do checklist).
- [ ] Regras intermediárias (passo 1, commit `6def61f`): `git show 6def61f:firestore.rules` contém `match /friendships` e ainda contém `match /friends`. Essa é a versão que pode ir antes do cliente, se quiser separar. Publicar só essa versão com `firebase deploy --only firestore:rules` a partir de um arquivo temporário, depois restaurar o arquivo atual.
- [ ] Distribuir o cliente novo.
- [ ] Regras finais (HEAD): `firebase deploy --only firestore:rules` com o `firestore.rules` atual. Não há índice novo: `firestore.indexes.json` não mudou; confirmar no console que nenhum índice novo é pedido.
- [ ] Observação: como não há usuários ativos, a janela pode ser única. Um cliente antigo, depois das regras finais, perde intenções e trava a exclusão de conta (`deleteAllFriends` cai em `permission-denied` depois que o perfil foi apagado). Por isso o cliente novo precisa estar instalado antes do fim da janela.

### 6.2 Fluxo com dois aparelhos

- [ ] **M1. Pedido por e-mail.** A busca o e-mail de B e toca "Enviar pedido". Esperado: diálogo "Enviar pedido a <nome de B>?" com o nome e o avatar. Cancelar o diálogo não envia nada. Confirmar: "Pedido enviado a <nome de B>.". Em "Pedidos de amizade", A vê "Enviados (1)" com "Aguardando resposta" e "Cancelar pedido". Negativo: e-mail inexistente mostra "Não foi possível enviar o pedido a esse e-mail." sem diálogo.
- [ ] **M2. Selo.** B vê o selo "1" no ícone Perfil (rótulo de acessibilidade "1 pedido de amizade"). Em "Pedidos de amizade", B vê "Recebidos (1)" com o nome de A e "quer entrar na sua constelação". A não vê selo (pedido enviado não conta).
- [ ] **M3. Aceitar.** B toca "Aceitar". Esperado: "<A> entrou na sua constelação.". O selo de B some. Sem reabrir o app: A vê B em amigos e o pedido sai de "Enviados".
- [ ] **M4. Intenção nos dois sentidos.** A envia uma intenção a B pelo menu do amigo. Esperado: B recebe o aviso (banner de intenção). B envia a A: A recebe. Ambos os sentidos precisam funcionar.
- [ ] **M5. Recusa silenciosa.** C recebe pedido de A e toca "Recusar". Esperado em C: "Pedido recusado." e o item em "Recusados e removidos" com "Desbloquear". Em A: o pedido continua em "Enviados" como "Aguardando resposta". A toca "Cancelar pedido": "Pedido cancelado.", o item some nesta sessão. Fechar e reabrir o app: o item volta como "Aguardando resposta" (esperado por desenho: a recusa não aparece para A). A busca C de novo: "Você já enviou um pedido a essa pessoa." (esperado). C toca "Desbloquear": o item some para C; A pode então buscar C e enviar de novo ("Pedido enviado a ...").
- [ ] **M6. Remoção e desbloqueio.** A, com amizade aceita com B, toca em B, depois "Remover amizade". Esperado: diálogo "Remover <B>?" com a explicação de que B não poderá pedir de novo sem desbloqueio. Confirmar: "Amizade removida.". B deixa de ver A em amigos, sem aviso. B busca A e pede: "Não foi possível enviar o pedido a esse e-mail." (frase genérica). A busca B: "Você recusou ou removeu essa pessoa. Desbloqueie em Pedidos de amizade.". A toca "Desbloquear" em "Recusados e removidos": "Desbloqueado. Você pode buscar essa pessoa de novo.". B pode pedir de novo.
- [ ] **M7. Pedido cruzado simultâneo.** A e B buscam um ao outro e tocam "Enviar pedido" ao mesmo tempo (ou com a menor diferença possível). Esperado: um dos dois vê "Pedido cruzado: vocês agora são amigos." ou "Pedido enviado" e o outro vê a amizade após atualizar. No console do Firestore, a coleção `friendships` tem **um** documento com id `<menor>_<maior>` e `status: accepted`. Repetir em sequência rápida como controle.
- [ ] **M8. Busca desligada em quem recebe.** B desliga "Aparecer na busca de amigos". A busca B e envia: "Não foi possível enviar o pedido a esse e-mail." (mesma frase de e-mail inexistente). Pedidos e amizades que B já tinha continuam. B religa a busca e volta a aparecer para A.
- [ ] **M9. Modo avião (item A1).** B em modo avião. (a) B toca "Aceitar" em um pedido recebido: registrar o que aparece. Esperado pelo checklist: "Sem conexão. Tente de novo quando estiver online.". Observado: ______. (b) B pede amizade a um e-mail pela busca: esperado a mesma mensagem. (c) Reconectar: o aceite foi aplicado uma vez só? O botão voltou a funcionar? Se a mensagem não aparecer em (a), registrar como falha de A1.
- [ ] **M10. Pedido aceito no intervalo (item A2, opcional).** Só se houver tempo: A tem pedido pendente para B, B aceita, e A toca "Cancelar pedido" antes da lista atualizar (ou com A offline com cache antigo). Registrar a mensagem: esperado algo como "Vocês já são amigos.", com a observação de que hoje aparece "Pedido cancelado.".
- [ ] **M11. Exclusão de conta com amizades.** A tem amigo B, pedido enviado a C e lápide com D. A exclui a conta. Esperado: a tela de exclusão lista "suas amizades e seus pedidos de amizade (enviados e recebidos)" e o passo "Apagando amizades e pedidos…". Ao terminar, no console: nenhum documento em `friendships` contém o uid de A; `publicProfiles/<A>` foi apagado. Em B: A some da lista de amigos (após atualizar) e B busca o e-mail de A: mensagem genérica. Opcional: repetir interrompendo a conexão no meio da cascata: deve pedir para repetir, e a repetição conclui.
- [ ] **M12. Smoke de regressão.** Oráculo (enviar uma mensagem), check-in, loja (uma compra simples), login e logout. Só para confirmar que nada fora da amizade quebrou.
- [ ] **M13. Ordem de deploy** (item 6.1 acima): registrar a data e a versão das regras publicadas e a versão do cliente distribuído.
- [ ] **M14. Dados legados.** Antes do deploy, remover `users/*/friends` das contas de teste (console ou o roteiro de `scripts/audit_users.md`). Confirmar que nenhuma subcoleção `friends` continua visível para o cliente.

### 6.3 Riscos aceitos a repetir na revisão de release

- [ ] R-S8: quem foi recusado pode apagar o próprio perfil, apagar a lápide e refazer a conta. Equivale a outra conta. Mitigação real: App Check (etapa 13).
- [ ] R-S1: sem teto de pedidos no servidor (Spark). O limite de 20 existe só no cliente.

## 7. Como reproduzir esta rodada

- `flutter analyze` e `flutter test` na raiz do projeto (saída em arquivo).
- Regras: conferir `Get-NetTCPConnection -LocalPort 8091` vazio; `cd test_rules && FIRESTORE_EMULATOR_PORT=8091 npm test > <arquivo> 2>&1`; ao fim, conferir se o java do emulador com `--port 8091` ainda existe e encerrá-lo apenas se foi iniciado pela execução. Nunca rodar contra emulador em uso.
