# QA: etapa 9 (controllers) e fix(oracle)

Data: 2026-11-14. Branch: `feature/flutter-migration`.
Escopo: `git diff 94a5759..HEAD` (etapa 9 completa, passos 0 a 7, ressalvas, fechamento) e o commit `9f24f10` (`fix(oracle)`).
Referência: `docs/architecture/step9-controllers.md`, seções 3, 5, 7 e 9.

Restrições seguidas: nenhum arquivo de `lib/`, `firestore.rules` ou `test_rules/` foi alterado. `npm test` não foi executado (regras sem diff).

## 1. Resultado da execução

| Comando | Resultado |
|---|---|
| `flutter analyze` | No issues found (exit 0) |
| `flutter test` (antes dos testes novos) | 289 passaram, 0 falhas |
| `flutter test` (depois) | **293 passaram, 0 falhas, 0 pulados** (exit 0) |

Testes novos (4), todos verdes:

1. `chat_controller_test.dart`: `(1) se a 2a gravacao (da resposta) falha, a resposta fica na tela e loading e liberado`.
2. `oracle_screen_test.dart`: `falha do oraculo mostra o erro na conversa e libera o envio` (widget).
3. `shop_screen_test.dart`: `item ja possuido mostra Equipar, grava o slot e nao cobra` (widget).
4. `cosmos_screen_test.dart`: `dois toques no check-in enquanto grava chamam a economia uma vez` (widget).

Os arquivos foram formatados com `dart format` antes do commit.

## 2. Fix do chat (`9f24f10`): verificação dos 4 pontos pedidos

| # | Requisito | Testes que cobrem | Status |
|---|---|---|---|
| 1 | Falha de `complete` ou `save` libera `loading` e mostra a mensagem de erro | `(1) se o oraculo lanca...`, `(1) se o save lanca...`, `(1) se a 2a gravacao falha...` (novo), widget `falha do oraculo mostra o erro...` (novo) | Passou |
| 2 | Trocar de conversa durante a resposta grava na conversa de origem | `(2) trocar de conversa durante a resposta...` (checa conv 1 com user+model, conv 2 vazia, `index` mantido, `loading` false) | Passou |
| 3 | Envio antes da hidratação é ignorado | `(3) enviar antes da hidratacao e ignorado...` | Passou no controller. **Defeito na tela (ver seção 4, BUG-E9-1)** |
| 4 | Formato de persistência inalterado (chave `astrum.chat.<uid>`, JSON, 2 gravações por mensagem) | `1a mensagem vira o titulo...` (2 saves, conteúdo de cada um), `caracterizacao: ChatStore real grava a mesma chave e o mesmo JSON`, `chat_store_test.dart` (chave, JSON exato, `load` lê o que `save` gravou) | Passou |

Observação sobre o item 4: a contagem de 2 gravações é verificada com `FakeChatRepository` (`saves`). O teste com `ChatStore` real verifica a chave, o JSON exato e a nova conversa, mas não conta gravações. Isso é suficiente, porque a contagem é a mesma nos dois.

## 3. Matriz de critérios (etapa 9, seção 3) para testes

| Controller / item | Testes existentes | Lacunas |
|---|---|---|
| `CosmosController.ensureHoroscope` | 6 (gera, não regera com cache de hoje, regera de outro dia, segunda chamada não refaz, sem signo/perfil, falha propaga) | Widget do horóscopo na tela não testado |
| `CosmosController.drawTarot` | 6 (prompt, fallback do `complete`, falha ao gravar, `drawingTarot`, descartado não grava, sem perfil) | Toque no tarô na tela não testado |
| `CosmosController.checkIn` | 5 unitários + 3 widget (saudação, sucesso, já feito) + 1 widget novo (dois toques) | Nenhuma. Cobertura completa para check-in |
| `ChatController` | 17 (ver seção 2 e grupos hydrate, send, newConversation/select, descartado) + 6 do `ChatStore` | Falha de `load` na hidratação (ver seção 5) |
| `RitualsController` | 3 (add com trim e analytics, título vazio/sem perfil, delete) + `ritual_day` 2 | Tela de rituais sem widget (por decisão do plano) |
| `AstralController` + `birthDateTimeOf` | 2 unitários + 2 widget + 4 do domínio | Nenhuma relevante |
| `ShopController` (comprar, equipar, erro, `buying`, descartado, inventário) | 9 unitários + 2 widget (comprar com erro de saldo, equipar novo) | Equipar pelo inventário na tela (`inventory_screen`) só tem teste de controller |
| `AccountController` (busca, próprio e-mail, sucesso, sem perfil, intenção) | 5 unitários | Sem widget (por decisão do plano); fluxo de adicionar amigo fica no checklist manual |
| Domínio puro (`daily_content`, `ritual_day`, `isEquipped`, `itemTypeLabel`, `dayKey`) | Cobertos (ver lista de arquivos em `test/`) | Nenhuma |
| Fronteiras (`core_boundaries_test.dart`) | Regra `_controller.dart` como camada 3, detector e mutações, sem ciclo, sem import relativo, controllers sem `material` | Nenhuma |
| Persistência do chat | `chat_store_test.dart` e caracterização no controller | Nenhuma |

## 4. Defeito encontrado

### BUG-E9-1: texto digitado antes da hidratação do chat é apagado sem ser enviado

- Severidade: baixa na janela atual (`ChatStore` carrega quase de imediato); média quando o histórico vier do Firestore (etapa 10).
- Causa: `OracleScreen._send` limpa `_input` (`_input.clear()`) antes de chamar `ChatController.send`. O controller ignora o envio quando `hydrated` é `false`, mas o campo já foi limpo. O botão de enviar fica habilitado nesse estado (só desabilita com `loading` ou sem perfil), e os chips também.
- Passos para reproduzir:
  1. Entrar com perfil válido e abrir o Oráculo.
  2. Antes de o histórico carregar (com carga lenta, ou no primeiro frame), digitar "Oi".
  3. Tocar no botão de enviar (ou pressionar Enter).
- Resultado observado: o campo fica vazio, nenhuma mensagem aparece e `OracleService.complete` não é chamado. Reproduzido com um teste temporário (`CAMPO=[] CHAMADAS=0`), que foi removido. Não foi commitado porque falharia a suíte.
- Resultado esperado: o texto permanece no campo, ou o botão fica desabilitado até a hidratação.
- Correção sugerida (não aplicada, pois `lib/` está fora do escopo): em `_send`, verificar `hydrated` antes de `_input.clear()`, do mesmo jeito que já se verifica `loading`. Ou desabilitar o botão e os chips enquanto `!chat.hydrated`.
- Ponto de atenção: o mesmo problema vale para os chips. Um chip tocado antes da hidratação é ignorado, e `_input.clear()` ainda apaga o texto que o usuário tinha digitado.

## 5. Riscos e observações (não são falhas de teste)

- `ChatController.hydrate`: `_hydrateStarted` vira `true` antes do `await`. Se `load` lançar, o chat fica sem hidratação para sempre, e todo envio é ignorado em silêncio (com o defeito BUG-E9-1). Hoje `ChatStore.load` não lança, então não há teste. Ao migrar para o Firestore (etapa 10), vale um teste de falha de `load` e uma política de nova tentativa.
- `ChatController.newConversation` chama `_persist` sem `try/catch`. Uma falha de gravação vira erro não tratado no `onPressed` do botão. O código original tinha o mesmo comportamento, então não é regressão.
- `ChatController.send` usa um único `try` para `save`, `logEvent` e `complete`. Uma falha de analytics aparece para o usuário como "Não foi possível obter a resposta", e o oráculo não é chamado. Não há teste para esse caminho.
- Dívidas aceitas do fechamento da etapa (horóscopo sem tratamento de erro em `ensureHoroscope`; `equip` do inventário sem guarda de reentrada) continuam sem correção e estão só parcialmente testadas (o `equip` do inventário tem teste de propagação de erro no controller).
- O oráculo é 100% local (`OracleService` não usa rede). Por isso o cenário "falha de rede" do checklist não se aplica ao oráculo: só é possível forçar falha de gravação (prefs), o que os testes já cobrem.

## 6. O que não foi testado e por quê

- **Telas de rituais, conta (adicionar amigo) e inventário sem widget test**: o plano (seção 5) previa só teste de controller para elas. Cobertos pelos controllers e pelo checklist manual.
- **Tarô e horóscopo na tela**: o plano previa widget test só para check-in, saudação e snackbar. O comportamento está coberto nos controllers. Fica no checklist manual.
- **Firebase real, Firestore, regras e Auth**: fora do escopo (testes sem rede e sem credenciais). Regras cobertas por `rules_contract_test.dart`; `npm test` não foi rodado.
- **TTS (`flutter_tts`)** e **Starfield/animações**: não testados; o plano manda usar `pump`, não `pumpAndSettle`.
- **Comportamento visual** (cores, layout, scroll): não avaliado.

## 7. Checklist manual (dispositivo real, antes de liberar)

Oráculo:
- [ ] Enviar uma mensagem pelo botão e pela tecla Enter. A resposta aparece e o campo limpa.
- [ ] Enviar com o campo vazio ou só com espaços: nada acontece.
- [ ] Trocar de conversa pelo menu enquanto a resposta está sendo gerada. A resposta deve aparecer na conversa de origem, e a conversa selecionada deve continuar a mesma.
- [ ] Fechar e reabrir o app: o histórico e os títulos continuam iguais.
- [ ] Digitar logo ao abrir o Oráculo, antes do histórico carregar (BUG-E9-1). Esperado: o texto não se perde. Pode falhar; ver seção 4.
- [ ] Falha de gravação (simulada, se possível): mensagem de erro aparece e o envio volta a funcionar.
- [ ] Tocar no volume de uma resposta: o TTS fala o texto.

Loja:
- [ ] Comprar item com saldo suficiente: saldo cai e o item vira "Equipar".
- [ ] Comprar sem saldo: mensagem "Poeira Estelar insuficiente.".
- [ ] Equipar item já possuído pela loja e pelo inventário: "Em uso" aparece no item equipado; o inventário mostra "<nome> equipado.".

Check-in:
- [ ] Fazer o check-in: +25 Poeira Estelar e o botão fica "Check-in de hoje já recebido".
- [ ] Tocar duas vezes rápido: só um crédito.
- [ ] No dia seguinte, o check-in volta a ficar disponível.

Horóscopo e tarô:
- [ ] Horóscopo aparece ao abrir o Cosmos (perfil com signo) e não é gerado de novo no mesmo dia.
- [ ] Tocar na carta do tarô: a interpretação aparece e fica salva ao reabrir o app.

Rituais:
- [ ] Adicionar evento com título vazio: nada acontece.
- [ ] Adicionar evento com título: aparece no dia selecionado, ordenado por horário.
- [ ] Excluir evento: some da lista.

Mapa astral:
- [ ] Calcular sem data de nascimento: "Preencha a data de nascimento na conta.".
- [ ] Calcular com data válida: mapa é mostrado e fica salvo ao reabrir.

Conta:
- [ ] Adicionar amigo com e-mail inexistente: "Nenhuma constelação encontrada com esse email.".
- [ ] Adicionar amigo com o próprio e-mail: mesma mensagem de inexistente.
- [ ] Adicionar amigo válido: "<nome> entrou na sua constelação.".
- [ ] Enviar intenção para amigo: a notificação chega ao destinatário.

## 8. Arquivos alterados neste QA

- `docs/qa/etapa-9.md` (este relatório).
- `test/features/oracle/presentation/chat_controller_test.dart`: 1 teste novo e a classe `_FailSecondSave`.
- `test/features/oracle/presentation/oracle_screen_test.dart`: 1 widget test novo.
- `test/features/economy/presentation/shop_screen_test.dart`: 1 widget test novo.
- `test/features/cosmos/presentation/cosmos_screen_test.dart`: 1 widget test novo.
