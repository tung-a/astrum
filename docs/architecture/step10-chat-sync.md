# Etapa 10: histórico do oráculo no Firestore (D9)

Status: **escopo simplificado** pelas decisões de 2026-11-14 (`docs/decisions/2026-11-chat-sync-decisions.md`): sem usuários ativos, **a migração do legado (seção 5 e passo 4) foi cortada** e removida do código; consentimento = aviso informativo único; retenção até o usuário apagar; região `southamerica-east1`; abre na conversa mais recente; texto de limite aos 500; sem botão de apagar por ora. A seção 5 fica só como registro histórico (o código está no histórico git). Marcado para `reviewer-consultor` (dado pessoal, ver seção 10). Este documento **substitui** as seções 1, 2, 4 e 6 de `chat-sync.md` (que parte de regras e interface antigas) e herda dele as seções 3 (princípios das regras) e 5 (LGPD) com os ajustes abaixo. `firestore.rules` **não muda** nesta etapa (seção 3).

Base: `chat-sync.md`, `step9-controllers.md` (3.2 e 9), decisões de 2026-11 (sem web, Spark, sem Functions, exclusão de conta na etapa 11), `firestore.rules` (linhas 272 a 315) e `test_rules/firestore.rules.test.mjs`.

## 1. O que mudou desde `chat-sync.md`

| Item | Antes | Agora | Efeito |
|---|---|---|---|
| Plataformas | Android, iOS e web | Só Android e iOS | Persistência offline do Firestore já vem ligada (100 MB); nenhuma mudança em `main.dart`; sem tratamento de `failed-precondition` da web. |
| Regras | rascunho (`messageCount` livre) | implementadas e testadas: criação com contador 0 ou 1; update com contador igual ou +1; mensagem só entra se o contador da conversa sobe exatamente 1 **no mesmo batch** (ou a conversa nasce no batch com 1); mensagem imutável | **Um batch contém no máximo uma mensagem por conversa.** A migração e o envio são "uma mensagem por batch" (seção 5). |
| Interface | `ChatRepository` por snapshot (etapa 9) | incremental, por streams (seção 4) | `ChatController` muda por dentro; a tela não muda. |
| Exclusão de conta | pendência | etapa 11 | Esta etapa entrega `deleteConversation` e `deleteAllConversations` no repositório para a etapa 11 reutilizar. |

## 2. Modelo de dados

Sem mudança em relação a `chat-sync.md` seção 1 (já refletido nas regras):

```
users/{uid}/conversations/{convId}
  title: string 1..80 | createdAt: timestamp (imutável) | updatedAt: timestamp
  messageCount: int 0..500 | schemaVersion: 1
users/{uid}/conversations/{convId}/messages/{msgId}
  role: 'user' | 'model' | text: string 1..10000 | createdAt: timestamp
```

Decisões de detalhe:

- `convId` e `msgId` gerados no cliente (`Uuid` v4, já dependência). Na migração: `convId` reaproveita o do legado; `msgId` determinístico `m0001`, `m0002`... (índice na lista **já filtrada**, ver 5).
- **Conversa criada de forma preguiçosa**: "Nova conversa" cria só um rascunho em memória (id e título "Conversa N" como hoje). O documento nasce no batch da 1ª mensagem (`set` da conversa com `messageCount: 1` e `title` = 1ª mensagem cortada). Evita documentos vazios e uma escrita a toa. Mudança visível: um rascunho vazio não sobrevive a fechar o app (hoje sobrevive, gravado em prefs). Aceito.
- **Título**: texto da 1ª mensagem, cortado em 80 unidades UTF-16 sem partir par substituto (emoji). Teste na regra com emoji.
- **Ordenação das mensagens**: `createdAt` do cliente (`Timestamp`, não `serverTimestamp`, para ordenar offline). O cliente garante `createdAt` estritamente crescente por conversa: `max(agora, última + 1 ms)`, para a resposta nunca empatar com a pergunta. Desempate natural do Firestore: id do documento.
- **Textos**: mensagem acima de 10000 caracteres é truncada na gravação (e no que vai ao oráculo); sem `maxLength` no campo (UI fica como está).
- **Índices**: só os automáticos de campo único (`updatedAt`, `createdAt`). `firestore.indexes.json` sem diff.
- **Limite de 50 conversas**: as regras não impõem. A lista consulta `limit(50)` por `updatedAt desc`. Conversas além disso continuam armazenadas, mas invisíveis; ver pergunta Q4. A exclusão de conta deve paginar **todas**, não só as 50.

## 3. Regras de segurança: sem mudança

`firestore.rules` e `firestore.indexes.json` ficam sem diff. As regras atuais bastam:

- Envio = batch com 1 `set` de mensagem + 1 `update` da conversa (`updatedAt`, `messageCount: increment(1)`), ou `set` da conversa com contador 1 + `set` da mensagem (1ª mensagem). `increment` é preferível a gravar o número: continua válido com dois dispositivos escrevendo em paralelo (o servidor avalia a regra com o valor já resolvido).
- Exclusão: `allow delete` do dono em mensagem e conversa já existe. Cliente apaga filhos primeiro.
- `getAfter` impede mensagem em conversa excluída (a exclusão prevalece sobre escritas pendentes de outro dispositivo; a escrita falha com `not-found` ou `permission-denied` e é descartada).

Ponto a verificar (passo 1, só testes): o teste atual usa contador explícito (`messageCount: count`); falta cobrir `FieldValue.increment(1)` no emulador, a 500ª e a 501ª mensagem, criação da conversa com a 1ª mensagem, título de 80 unidades com emoji, e `set` de mensagem já existente (vira update, negado). Se algum falhar, volta a este documento antes de tocar em regra.

Otimização **não** adotada (só se a cota do Spark apertar na migração, Q7): permitir `messageCount` subir N com N mensagens no mesmo batch. Reduz a migração de 2 escritas por mensagem para ~1 e elimina milhares de round trips. Exige mudança de regra, passo próprio, teste de regras e `reviewer-consultor`. Hoje: não necessária.

Contrato de limites: `lib/core/firebase/rules_contract.dart` ganha `chatTitleMax = 80`, `chatMessagesMax = 500`, `chatTextMax = 10000`, `chatSchemaVersion = 1` (pendência da etapa 7), cobertas por `rules_contract_test.dart` com caso de mutação.

## 4. Interface e controller

### 4.1 Modelos (`features/oracle/domain/chat_models.dart`, puro)

- `ChatTurnStored` ganha `String? id` e `DateTime? createdAt` (opcionais; `toJson` do legado intocado). `ChatConversation` ganha `DateTime? updatedAt` e `int messageCount = 0`. A tela continua lendo `msg.role`, `msg.text`, `conversation.title`.
- `chat_limits.dart` (puro): constantes, `titleFrom(String)`, `clampText(String)`.
- `legacy_import_plan.dart` (puro): `List<ImportConversation> planLegacyImport(List<ChatConversation> legacy, DateTime now)`: remove mensagens com texto vazio, normaliza `role` (qualquer coisa fora de `user`/`model` vira `user`, como o `fromJson` de hoje), trunca texto, atribui ids `m0001...` e datas (seção 5), divide conversas com mais de 500 mensagens em partes (seção 5). Testável sem Firebase.

### 4.2 `ChatRepository` (nova interface, `features/oracle/data/chat_repository.dart`)

```dart
abstract interface class ChatRepository {
  /// Até 50 conversas, mais recente primeiro (messages vazio; só metadados).
  Stream<List<ChatConversation>> watchConversations(String uid);

  /// Últimas [limit] mensagens (padrão 500), em ordem cronológica.
  Stream<List<ChatTurnStored>> watchMessages(String uid, String convId,
      {int limit = 500});

  /// Uma mensagem por batch (exigência das regras). [isNew]: cria a conversa
  /// (título + createdAt) em vez de atualizar. Não deve ser aguardado no
  /// fluxo da UI: offline o Future só completa com o servidor.
  Future<void> appendMessage(String uid,
      {required String convId,
      required ChatTurnStored message, // id e createdAt obrigatórios aqui
      required DateTime updatedAt,
      String? title,
      bool isNew = false});

  Future<int?> remoteMessageCount(String uid, String convId); // null = não existe
  Future<void> deleteConversation(String uid, String convId);
  Future<void> deleteAllConversations(String uid); // etapa 11; pagina tudo
  Future<void> waitForSync(); // waitForPendingWrites; fake retorna já
  String newId();
}
```

Implementação `FirestoreChatRepository(FirebaseFirestore)` em `data/`, provider `chatRepositoryProvider` (troca a implementação em `oracle_providers.dart`). O fake de teste é `InMemoryChatRepository` em `test/support/` (substitui `FakeChatRepository`; também serve de rascunho de "modo sem sincronização" se Q1 = (b)).

O que sai: `load/save/create` por snapshot. O antigo `ChatStore` perde `implements`, vira `LegacyChatStore` (somente leitura de `astrum.chat.<uid>` + `markMigrated`), usado só pelo migrador.

### 4.3 `ChatController` (`chat_controller.dart`)

`ChatState` mantém `conversations`, `index`, `loading`, `hydrated`, `current`. Internamente passa a guardar `selectedId` (o `index` vira derivado), porque ordenar por `updatedAt` move a conversa para o topo a cada envio e um índice fixo apontaria para a conversa errada.

- `build()`: `final uid = ref.watch(currentUidProvider)` (**quita E9-B4**). Troca de uid reconstrói o notifier: cancela as `StreamSubscription`, zera `selectedId`, rascunho e `_hydrateStarted`. Como `ref.onDispose` roda antes do rebuild e o `_alive` voltaria a `true`, usar um **contador de geração** (`_gen++` em `build`; toda continuação assíncrona compara com o valor capturado) em vez de só `_alive`. Sem uid: `ChatState()` não hidratado.
- `hydrate()` (idempotente, a tela continua chamando em post-frame): exige uid; roda `LegacyChatMigrator.run(uid)` (seção 5; só enfileira, não bloqueia por rede); assina `watchConversations`; no 1º evento (cache ou servidor) `hydrated = true`. Sem conversas, o rascunho "Conversa 1" fica como `current`. Assinatura de `watchMessages(selectedId)` é refeita em `select` e em mudança de conversa; ao trocar, cancela a anterior.
- Lista exibida = `[rascunho?] + conversas da nuvem` (o rascunho some quando uma conversa com o mesmo id chega). Selecionada inicialmente: a mais recente (hoje abre a de índice 0 do legado, que é a mais antiga; mudança de ordem aceita, Q5).
- `send(text)`: mesmas guardas de hoje (vazio, `loading`, `!hydrated`). Passos: `trim`/`clampText`; `appendMessage(user, isNew: é rascunho)` **sem await** (`unawaited(...catchError(log sem texto))`); `logEvent('send_message_chat')`; `complete`; `appendMessage(model)` na conversa de origem **por id** (já corrigido no `fix(oracle)`); se a conversa sumiu da lista (excluída em outro aparelho), descarta a resposta. `loading` continua liberado em `try/finally` com a resposta "Não foi possível obter a resposta. Tente novamente." (texto existente). Aos 500 mensagens: não envia e responde localmente (não persistido) com texto novo, ver Q6.
- `newConversation()`: cria rascunho com `newId()` e título "Conversa N" (N = nº de conversas + 1), seleciona; **não grava**. Se já existe rascunho vazio, só o seleciona.
- Histórico ao oráculo: hoje `complete` recebe só o prompt (`OracleService` local), então o corte "últimas 20 mensagens" de `chat-sync.md` não se aplica.
- Erros: `appendMessage` com `permission-denied`, `not-found` ou `resource-exhausted` (cota) são registrados sem texto e **não** reabrem `loading`. A UI otimista some quando o servidor rejeita (a stream emite sem a mensagem); sem indicador novo (formato de UI intocado). Indicador `hasPendingWrites` fica fora desta etapa.

`oracle_screen.dart` não muda (precisa só de ajuste de teste se usar o fake antigo).

## 5. Migração do legado (CORTADA, registro histórico)

> Cortada em 2026-11-14: não há usuários ativos (só contas de teste do dono), então não há histórico local a preservar. Migrador, plano de importação e `LegacyChatStore` foram removidos. O texto abaixo documenta o desenho que existiu.

Desenho guiado pelas regras: não há batch com várias mensagens da mesma conversa e `set` sobre mensagem existente é negado. Logo a migração é **retomável pela contagem** em vez de por sobrescrita.

1. Gatilho: `hydrate()`, uma vez por sessão e uid. Para se `astrum.chat.migrated.<uid>` existe.
2. Leitura crua de `astrum.chat.<uid>` (distingue ausente de vazio; `load` atual devolve placeholder). Ausente ou lista vazia: grava a flag e sai. JSON inválido: **não apaga**, copia o texto cru para `astrum.chat.<uid>.bak`, grava a flag `...migrated.<uid>` com valor `corrupt` e segue sem migrar (evita laço infinito; o `.bak` permite recuperação manual/suporte).
3. `planLegacyImport`: descarta mensagens vazias, normaliza `role`, trunca texto, ignora conversas sem mensagens (eram rascunhos). Conversa com mais de 500 mensagens (teto da regra) é **dividida em partes** de até 500, sem descartar nada: a parte 1 mantém `<id>` e o título; a parte `p` usa id `<id>-p<p>` (`-p2`, `-p3`…) e título `<título> (parte p)` (cortando o título base para caber em 80 unidades UTF-16 sem partir par substituto). Ids de mensagem `m0001…` por parte; cada parte é uma conversa nas datas sintéticas (as partes seguintes ficam mais recentes). Ids determinísticos mantêm a idempotência e a retomada pela contagem de cada conversa. Datas sintéticas: lista legada em ordem de criação; parte `i` (0-based) recebe `updatedAt = createdAt = base + i s` e a mensagem `j` (0-based) recebe `createdAt = base + i s + j ms` (< 500 ms por parte). Ancoradas no **início**: anexar conversas ou mensagens ao fim do legado entre tentativas nunca muda a data do que já foi enviado. A ordem do legado vira "a última conversa é a mais recente (maior `updatedAt`)". Ids de conversa únicos no plano (repetidos ou colisão com `<id>-pN` ganham `-d2`, `-d3`…).
4. Para cada conversa: `k = remoteMessageCount` (leitura com visão local, que inclui escritas pendentes de tentativa anterior). `k == null`: 1ª mensagem com `isNew: true`; depois mensagens `k+1..n` em sequência, uma por batch, **sem aguardar cada commit** (a fila do Firestore preserva ordem e persiste em disco; funciona offline). O app vê tudo imediatamente pelo cache otimista.
5. Aguarda `waitForSync()` com timeout (30 s, não bloqueia a UI: roda em segundo plano depois de `hydrated`). Depois confere por leitura **do servidor** `remoteMessageCount == n` de cada conversa. Tudo igual: grava `astrum.chat.<uid>.bak` (cópia do JSON), apaga a chave original e grava a flag. Divergência ou falha: nada é apagado, repete na próxima abertura (retoma pela contagem do servidor).
6. Concorrência (dois aparelhos migrando o mesmo legado): o segundo batch da mesma mensagem falha por regra (mensagem existe / contador). O migrador trata `permission-denied` como "alguém avançou", relê a contagem e continua; ao convergir, termina. Resultado idêntico, sem duplicar (ids determinísticos + contagem).
7. Conversas além de 50: migram todas (sem perda); a lista mostra as 50 mais recentes (Q4).
8. Vários uids no aparelho: chaves por uid, cada um migra o seu.
9. O `.bak` e o cache do Firestore guardam conteúdo no aparelho; expurgo do `.bak` e `ChatStore` na etapa 13 (higiene) ou numa versão posterior, e na exclusão de conta (etapa 11) apagar `astrum.chat.*`, `.bak` e a flag.

Ajustes da revisão (passos 0 a 4):

- **Exclusão** (`deleteConversation`/`deleteAllConversations`): toda paginação lê do **servidor** (`Source.server`); offline falha com `ChatOfflineException` sem apagar nada; filhos primeiro; a conversa só é apagada depois de uma página vazia de mensagens lida do servidor; idempotente.
- **Legado alterado durante a migração**: antes de `.bak`/remoção, `rawJson` deve ser igual ao lido no início; se mudou, `incomplete` e nada é apagado.
- **Datas sintéticas estáveis**: a base `now` é gravada em prefs (`astrum.chat.migbase.<uid>`) na 1ª tentativa e reutilizada nas retomadas (removida ao concluir); execução única por uid no processo (chamadas concorrentes compartilham a mesma execução).
- **Lacuna permanente**: esgotadas as rodadas, lista os ids existentes no servidor (`remoteMessageIds`) e envia só os que faltam.
- **Parse tolerante** (como `fromJson`): `role`/`text` atípicos, mensagens não-mapa e ids inválidos (fallback `legacy-<FNV-1a de título + 1ª mensagem>`, estável se a lista mudar de posição) não corrompem; só raiz não-mapa ou `conversations` não-lista é `corrupt`.
- **`.bak` confirmado**: `backup`/`markMigrated` devolvem o `bool` do `setString`; falha aborta e o original nunca é removido sem `.bak` confirmado.
- **Uid atual** (opcional, injetado): se deixa de ser o uid migrado (logout/troca), a migração aborta como `incomplete` em vez de insistir em `permission-denied`.
- **Lacuna e contador inflado**: a verificação é por contagem, não por ids. Se a lista de ids vem vazia mas a conversa existe (contador inflado, sem mensagens), recriar com `isNew` seria negado para sempre; vira `incomplete` com log fixo sem texto (requer intervenção).
- **Exclusão offline**: o `commit` do lote de exclusão tem timeout (15 s) e vira `ChatOfflineException`; a nova tentativa é idempotente.
- **Corrida de LGPD na exclusão (registrada, não resolvida)**: se outro aparelho grava uma mensagem entre a leitura da página vazia e o `delete` da conversa, a mensagem fica órfã (subcoleção sem documento pai, inacessível pela UI mas ainda armazenada). Sugestão para a etapa 11: exclusão recursiva no servidor (Admin SDK / `firebase-tools firestore:delete --recursive`, ou extensão Delete User Data) na exclusão de conta, que varre também órfãos.
- Registrado sem implementar: (8) `+1` sem mensagem é aceito pela regra (autoprejuízo, caracterizado em `test_rules/`); (10) `fieldOverrides` isentando `messages.text` de indexação em `firestore.indexes.json` como otimização futura, e o ritmo de ~1 escrita/s por documento da conversa na migração. A decisão do usuário sobre o corte das 500 mais recentes foi substituída pela divisão em partes.

Custo da migração: usuário com `M` mensagens válidas e `C` conversas = `2M` escritas + `~2M` leituras de regra, `C` leituras de contagem e `C` leituras de verificação. Exemplo `M=200`: 400 escritas, ~400+ leituras. Atenção à cota diária (seção 8).

## 6. Estratégia de sincronização

- Lista: listener (`snapshots`) em `conversations.orderBy(updatedAt, desc).limit(50)` enquanto o oráculo está aberto (`autoDispose`); sincroniza criação, exclusão e novas mensagens de outro aparelho.
- Mensagens: listener só na conversa selecionada, `orderBy(createdAt, desc).limit(500)` invertido no cliente. **Sem paginação nesta etapa**: limite = teto da regra (500), custo proporcional ao que existe; a UI atual mostra a conversa inteira e não tem botão "carregar anteriores" (Q6 trata de adicioná-lo). O parâmetro `limit` fica no repositório para paginar depois sem mudar a interface.
- Cache offline: persistência padrão de Android/iOS. Reabrir o listener em até ~30 min reaproveita o cache e só cobra deltas; depois disso o Firestore relê a consulta inteira.
- Offline: leitura do cache, escrita em fila; `Future` de escrita não é aguardado no fluxo da UI. O oráculo é local e responde sem rede; a resposta entra na fila. Primeiro login em aparelho novo e offline: `hydrated = true` com lista vazia a partir do cache, preenche ao reconectar.
- Dois dispositivos: mensagens imutáveis com ids únicos, sem conflito; intercalam por `createdAt`. `title` e `updatedAt`: último a gravar vence. Contador por `increment`. Exclusão prevalece (seção 3).
- `loading` é local: não sincroniza "digitando" entre aparelhos.

## 7. Privacidade e LGPD

1. Passa a existir tratamento novo: o conteúdo das conversas sai do aparelho para o Firestore (Google). É dado pessoal e potencialmente sensível (o usuário digita livremente sobre amor, saúde, crenças). Antes de ativar: política de privacidade e aviso (Q1), retenção (Q2), região (Q3).
2. Finalidade: "manter seu histórico em todos os seus aparelhos". Sem outra finalidade; **nenhum texto de conversa em analytics, logs ou mensagens de erro** (`send_message_chat` continua sem conteúdo; `catchError` registra só o código do erro). Regras só do dono, sem acesso de admin.
3. Oráculo segue 100% local, sem IA externa; se voltar, é risco novo (compartilhamento do histórico com terceiro).
4. Exclusão: `deleteConversation` (filhos primeiro, em lotes de 400, depois o documento; interrompida, a conversa continua visível e se repete) e `deleteAllConversations` (pagina até esvaziar, não só 50) ficam no repositório. A etapa 11 chama o segundo antes de `users/{uid}`, e apaga prefs/`.bak`/flag e o cache (`clearPersistence`). UI de apagar conversa: Q4.
5. Troca de conta no mesmo aparelho: o app só consulta `users/{uid}/...` do uid logado; o cache local não é consultado por outro uid. Risco baixo; `clearPersistence` ao excluir conta, não a cada logout (custo de releitura).
6. Criptografia ponta a ponta fora de escopo (sem recuperação de chave). Exportação fora de escopo.

## 8. Custo estimado (Spark: 50 mil leituras, 20 mil escritas, 20 mil exclusões por dia, projeto inteiro)

Usuário ativo típico por dia: abre o oráculo 1 vez, 5 conversas guardadas, conversa aberta com ~30 mensagens, envia 10 perguntas (20 mensagens).

| Operação | Escritas | Leituras |
|---|---|---|
| Abrir oráculo | 0 | lista ~5 + conversa ~30 (cache <30 min: ~0) |
| 20 mensagens (user + model) | 40 (mensagem + conversa) | 20 a 40 (regra: `get` e `getAfter` da conversa; o `exists` repete o mesmo documento, que pode ou não ser cobrado em dobro; usar 2 por mensagem como teto) |
| Outro aparelho com o app aberto | 0 | ~1 por mensagem recebida na lista + 1 na conversa aberta |
| Total | ~40 | ~55 a 75 |

Capacidade do chat sozinho: escritas 20000/40 ≈ 500 usuários ativos/dia; leituras 50000/75 ≈ 650. Como a cota é compartilhada com eventos, amigos, economia e `listUsers`, tratar ~250 a 300 usuários ativos/dia como limite prático antes de reavaliar (Blaze). Hoje (**antes**) o chat custa 0.

Pico de migração: 2 escritas por mensagem legada. 100 usuários com 200 mensagens cada no mesmo dia = 40 mil escritas, acima da cota diária (as escritas excedentes falham com `resource-exhausted` e a migração é retomada no dia seguinte, mas disputa com o uso normal). Mitigações: a migração é preguiçosa (acontece na 1ª abertura do oráculo de cada usuário, espalhando no tempo); opção de mudança de regra da seção 3 se o volume real exigir (Q7). Armazenamento: ~1 KB por mensagem; usuário intenso ~5 MB; irrelevante frente a 1 GiB. Exclusão de conversa de 100 mensagens = 101 exclusões e ~100 leituras.

## 9. Passos (um commit cada; `flutter analyze` e `flutter test` verdes em todos)

Pré-condição: árvore limpa, 289 testes verdes. Em todos: `git diff -- firestore.rules firestore.indexes.json pubspec.yaml pubspec.lock` vazio (`pubspec` só se um passo disser o contrário; nenhuma dependência nova: `fake_cloud_firestore` já está nas `dev_dependencies`).

| # | Commit | Conteúdo | Verificação |
|---|---|---|---|
| 0 | `chore(oracle): modelos e limites do chat` | Campos opcionais em `ChatTurnStored`/`ChatConversation`; `chat_limits.dart`; `legacy_import_plan.dart`; constantes em `rules_contract.dart`. Sem fiação. | Testes puros: título (80, emoji), truncamento, plano (vazios, role inválido, ids `m0001`, datas crescentes, ordem), contrato com mutação. Comportamento idêntico. |
| 1 | `test(rules): cobre increment e limites do chat` | Só `test_rules/`: casos da seção 3. Sem mudar `firestore.rules`. (R-consultor) | `FIRESTORE_EMULATOR_PORT=<porta livre> node run-tests.mjs`; falha de regra pára a etapa. |
| 2 | `refactor(oracle): ChatRepository antigo vira legado` | Renomear interface snapshot para `LegacyChatRepository` (ou remover `implements`), `ChatStore` mantido como `LegacyChatStore`; controller continua igual. Mecânico. | Testes de caracterização do passo 6 da etapa 9 intactos. |
| 3 | `feat(oracle): FirestoreChatRepository` | Nova interface `ChatRepository`, `FirestoreChatRepository`, `InMemoryChatRepository` (test/support), `deleteConversation`/`deleteAllConversations`. **Não ligado** ao controller (provider novo `firestoreChatRepositoryProvider`). (R-consultor) | `fake_cloud_firestore`: stream da lista ordenada e limitada, stream de mensagens em ordem, 1ª mensagem cria conversa com contador 1, `increment`, título só na criação, exclusão em cascata em lotes (> 400), `deleteAll` pagina 60 conversas, `remoteMessageCount`. |
| 4 | ~~`feat(oracle): migrador do legado`~~ (CORTADO) | `LegacyChatMigrator` + flags/`.bak`; ainda não ligado. (R-consultor) | Casos: ausente, vazio, corrompido (`.bak`, flag `corrupt`), feliz, reexecução (não duplica), queda no meio (retoma pela contagem), concorrência (segundo migrador não duplica), texto >10000, mensagens vazias, mais de 50, dois uids, falha de `waitForSync` (nada apagado). |
| 5 | `refactor(oracle): ChatController sobre o Firestore` | `build` depende de `currentUidProvider` (E9-B4), contador de geração, `selectedId`, subscriptions, rascunho, `send/newConversation/select` incrementais, `hydrate` chama o migrador, `chatRepositoryProvider` troca para Firestore. Tela sem mudança. (R-consultor) | Reescrever `chat_controller_test` com `InMemoryChatRepository`: hidrata; envio grava 2 mensagens sem aguardar; resposta vai à conversa de origem mesmo trocando de conversa; conversa excluída por outro aparelho descarta a resposta; **troca de uid reinicia estado e ignora resposta pendente do uid antigo**; logout limpa; rascunho não grava; abre na conversa mais recente; `loading` liberado em erro; 500 mensagens. `oracle_screen_test` adaptado. |
| 6 | `feat(oracle): aviso de privacidade do histórico` | Depende de Q1 (se (a): texto único no primeiro uso, flag local; se (b): consentimento com recusa e `InMemoryChatRepository` como modo sem sincronização). Texto da política. | Teste de widget do aviso; sem Firestore antes do aceite se (b). |
| 7 | `docs: etapa 10` | `overview.md` (coleções do chat deixam de ser "propostas"), `chat-sync.md` marcado como superado, plano e `CHANGELOG` (writer), `docs/qa/etapa-10.md` (qa). | Links válidos. |

Depois da etapa (versão futura): remover `LegacyChatStore` e os `.bak` (etapa 13), UI de apagar conversa conforme Q4.

## 10. Testes e revisão

- Puros (`test/features/oracle/domain/`): limites, título, plano de importação.
- Repositório com `fake_cloud_firestore` (`test/features/oracle/data/`). **O fake não aplica regras de segurança**; por isso as regras ficam em `test_rules/` com o emulador, porta por `FIRESTORE_EMULATOR_PORT` (padrão 8080; usar porta livre para evitar conflito). Não há teste de integração com o SDK real offline: fica no checklist manual (modo avião no Android e no iOS: enviar, reabrir, reconectar, ver a fila subir; dois aparelhos).
- Controller com `InMemoryChatRepository` e `ProviderContainer`; `currentUidProvider` sobrescrito para simular troca de uid.
- Manual (qa): migrar a partir de dados reais do app atual; migração com rede ruim; excluir conversa em um aparelho enquanto outro responde.
- `reviewer-consultor`: **obrigatório** (dados pessoais), uma passada única nos passos 1, 3, 4, 5 e 6, com foco em: regras vs batch (uma mensagem por batch), ausência de texto em logs/analytics, migração (não apagar o legado antes da confirmação do servidor; sem duplicar), exclusão em cascata, `deleteAllConversations` para a etapa 11, e diff vazio em `firestore.rules`/índices. `reviewer` comum em cada commit.

## 11. Riscos

| Risco | Mitigação |
|---|---|
| Cota do Spark na migração em massa (seção 8). | Migração preguiçosa; monitorar uso no console; opção de regra `+N` (Q7). |
| Migração parcial e usuário vê conversas incompletas. | Escritas ficam na fila persistente; a retomada é pela contagem; legado só apagado após conferência no servidor. |
| Escrita rejeitada depois de "enviada" (otimista some). | Aceito e raro (só excluída em outro aparelho, cota ou regra); sem UI nova. |
| Regra avalia `increment` diferente do esperado. | Passo 1 testa no emulador antes de qualquer código. |
| Perda do rascunho vazio ao fechar o app. | Documentado; sem impacto em dado. |
| Conteúdo sensível no cache do aparelho e no `.bak`. | Expurgo do `.bak`; `clearPersistence` na exclusão de conta. |
| Fila offline presa sem rede por dias. | O cache persiste em disco; sem limite prático; ver comportamento ao exceder o cache de 100 MB (improvável: conversa é texto). |
| Conflito de ordem por relógio errado do aparelho. | Só afeta a ordenação das mensagens do próprio usuário; aceito. |
| Cobrança em dobro de leituras das regras (`get` + `getAfter`). | Estimativa usa o teto (2 por mensagem). |

## 12. Perguntas ao usuário (decisões que só você toma)

- **Q1 (consentimento/aviso).** O histórico passa a ir para o Firestore. (a) Aviso informativo único no primeiro uso, mais atualização da política; (b) consentimento explícito com opção de recusa (sem aceite, o chat fica só em memória no aparelho e o legado não é migrado). **Recomendo (a)** por simplicidade e porque o app já guarda o perfil na nuvem, mas o conteúdo é livre e pode ser sensível (LGPD art. 11): se houver dúvida jurídica, (b). A estrutura aceita trocar depois.
- **Q2 (retenção).** Guardar até o usuário apagar (conversa ou conta) ou expirar automaticamente (ex.: 12 meses)? **Recomendo sem expiração automática** (sem Functions; regra de TTL a validar no Spark) e dizer isso na política.
- **Q3 (região do Firestore).** Em qual região o banco foi criado? Não dá para mudar depois. Se ainda não existir, **recomendo `southamerica-east1`** (São Paulo); se já existir fora do Brasil, a política deve citar a transferência internacional.
- **Q4 (apagar conversa e limite de 50).** Incluir botão de apagar conversa (formato de UI muda, texto de confirmação novo) nesta etapa ou na seguinte? Enquanto não houver, conversas além de 50 ficam invisíveis. **Recomendo deixar a UI de apagar para depois desta etapa** (o repositório já suporta) e não bloquear "Nova conversa".
- **Q5 (ordem das conversas).** O menu passa a listar da mais recente para a mais antiga e o app abre na mais recente (hoje abre na mais antiga). **Recomendo aceitar.**
- **Q6 (conversa longa).** Sem paginação, conversas de até 500 mensagens carregam inteiras (custo proporcional). Aos 500, mostrar texto novo "Esta conversa atingiu o limite. Inicie uma nova conversa." (não persistido). **Recomendo aceitar este texto** e deixar "carregar anteriores" para depois.
- **Q7 (escala).** Quantos usuários ativos por dia e quantos com histórico local relevante você espera no lançamento? Se passar de ~100 usuários migrando no mesmo dia, **recomendo aprovar a mudança de regra `+N`** (passo à parte, com `reviewer-consultor`); abaixo disso, não mexer nas regras.
