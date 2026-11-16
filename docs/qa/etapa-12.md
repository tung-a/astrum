# QA da etapa 12: aceite de amizade

> **Nota:** o conteúdo inicial deste documento é um relato do builder (execução e verificação feitas por ele); o `qa` independente complementa com casos e relatório próprios. Após a rodada de revisão: 524 testes Flutter e 87 de regras.

Data: 2026-11-16. Branch: `feature/flutter-migration`. Base: `docs/architecture/step12-friend-requests.md` (seções 7, 9 e 11).

## 1. Resultado da execução

| Verificação | Resultado |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **522 passaram, 0 falharam** |
| `test_rules` (emulador na porta 8091) | **81 passaram, 0 falharam** |

Os testes de regras rodaram numa porta fixa diferente da padrão, com a porta conferida como livre antes e depois; nenhum emulador em uso foi tocado.

## 2. Casos automatizados

| Critério | Onde |
|---|---|
| Pedido válido; a si mesmo; uids desordenados; id divergente; `requesterUid` alheio; status ≠ pending; nome divergente; campo extra; `createdAt` sem `request.time`; sem perfil; destino sem `users`; destino sem `publicProfiles` (busca desligada); anônimo; terceiro | `test_rules` (friendships create) |
| Duplicata e pedido cruzado negados na regra; o outro lado aceita | `test_rules` |
| Aceite só pelo não remetente; remetente, terceiro, anônimo e admin negados; campos imutáveis; `responderName` falso; aceite duplo; remetente excluído | `test_rules` |
| Recusa, lápide (não recria, não altera, não apaga), desbloqueio, remoção por qualquer dos dois, terceiro negado | `test_rules` |
| Cancelar `pending`; `accepted` não é apagado; exclusão de conta apaga qualquer relação própria (inclusive lápide); batch de 400 deletes | `test_rules` |
| Leitura: `get` do par próprio (inclusive inexistente), par alheio negado, `array-contains` próprio ok, sem filtro e collection group negados, admin negado; uids de 28 caracteres | `test_rules` |
| Intenção negada sem relação, `pending`, `declined`, após remoção; permitida `accepted` nos dois sentidos; `users/{uid}/friends` negado | `test_rules` |
| `publicProfiles`: busca com `limit(1)` ok; sem limit, `limit > 1`, sem filtro e anônimo negados | `test_rules` |
| `pairIdOf` equivale a `pairId` (tabela de pares); `viewFor` (amigos, recebidos, enviados, recusa silenciosa, bloqueados) | `friendship_test.dart` |
| Pedido, cruzado, duplicata, lápide, aceite duplo idempotente, remover, cancelar, desbloquear, consulta só do uid, `deleteAllFriendships` (450 documentos) | `social_repository_friendship_test.dart` |
| Cota de 20 pendentes no cliente; mensagens genéricas idênticas; offline e erro sem detalhe; `sendIntention` com amizade desfeita | `friendship_controller_test.dart`, `account_controller_test.dart`, `account_deletion_data_test.dart` |
| UI: carregando, vazio, erro com "Tentar de novo", aceitar, recusar, enviado, recusado silencioso, desbloquear, diálogo de confirmação do pedido, diálogo de remoção, selo no Perfil | `friend_requests_screen_test.dart`, `account_friends_test.dart`, `main_shell_badge_test.dart` |
| Cascata de exclusão chama `deleteAllFriendships` nas duas passadas | `delete_account_controller_test.dart` |
| Contrato Dart × regras (status, separador, limite de nome, status aceito nas intenções) | `rules_contract_test.dart` |

## 3. Pendências de verificação manual

Ver `docs/release-checklist.md`, seção 6c: dois aparelhos (pedido, selo, aceite, intenção nos dois sentidos, recusa silenciosa, remoção e desbloqueio, pedido cruzado simultâneo), busca desligada, modo avião, exclusão de conta com amizades e deploy das regras na ordem indicada.
