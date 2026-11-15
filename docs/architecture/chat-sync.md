# Sincronização do histórico do oráculo com o Firestore (D9)

Status: **superado** por `step10-chat-sync.md` (e `docs/decisions/2026-11-chat-sync-decisions.md`). Marcado para revisão do `reviewer-consultor` (dado pessoal sensível, regras do Firestore, exclusão de conta).

## Contexto

- Hoje o histórico vive só em SharedPreferences, chave `astrum.chat.$uid` (`lib/services/chat_store.dart`), como um JSON único `{conversations: [{id, title, messages: [{role, text}]}]}`. `OracleScreen` carrega tudo uma vez (`_hydrate`) e regrava a lista inteira a cada mensagem (`_persist`).
- Os modelos `ChatConversation` e `ChatTurnStored` estão em `lib/models/app_user.dart`. Os ids de conversa são UUID v4. Mensagens não têm id nem data.
- O RN (`ChatContext.tsx`) tinha chave de IA no cliente e as chamadas `logAddConversation`/`logDeleteConversation` comentadas. Não há requisito de paridade além do que já existe.
- Os repositórios (`ProfileRepository`, `EventsRepository`, `SocialRepository`; o antigo `UserRepository` foi dividido na etapa 4) já usam `users/{uid}/<subcoleção>` (events, friends, notifications). Seguimos o mesmo padrão.
- Restrições: plano gratuito (sem Cloud Functions), segurança só por regras, e as regras ainda não existem (T07).
- Não existe hoje fluxo de exclusão de conta no app (nenhum `delete` de usuário em `lib/`). Ver seção 5.

## 1. Modelo de dados

```
users/{uid}/conversations/{convId}
users/{uid}/conversations/{convId}/messages/{msgId}
```

Conversa (`convId` = UUID já usado hoje, reaproveitado na migração):

| Campo | Tipo | Regra |
|---|---|---|
| `title` | string | 1 a 80 caracteres (cliente corta o texto da 1ª mensagem) |
| `createdAt` | timestamp | imutável após criação |
| `updatedAt` | timestamp | atualizado a cada mensagem; usado para ordenar |
| `messageCount` | int | 0 a 500 |
| `schemaVersion` | int | 1 |

Mensagem (`msgId` = UUID v4 gerado no cliente; na migração, id determinístico `m0001`, `m0002`...):

| Campo | Tipo | Regra |
|---|---|---|
| `role` | string | `user` ou `model` |
| `text` | string | 1 a 10000 caracteres |
| `createdAt` | timestamp | `Timestamp.now()` do cliente (não `serverTimestamp`, para ordenar corretamente offline) |

Limites:
- 50 conversas por usuário. Imposto só no cliente (regras não contam documentos sem `get` caro). Estourar só consome a própria cota do usuário; o cliente bloqueia "Nova conversa" e oferece apagar a mais antiga.
- 500 mensagens por conversa, imposto nas regras via `messageCount` (ver seção 3).
- Mensagem de até 10000 caracteres. Adicionar `maxLength: 2000` no `TextField` do oráculo (hoje sem limite); o limite de 10000 nas regras cobre respostas do modelo (`max_tokens` 700, ~3000 caracteres) e dados legados.
- Documento Firestore tem teto de 1 MiB; estamos muito abaixo.

Por que subcoleção e não array dentro da conversa: mensagens só são acrescentadas, então documentos imutáveis evitam conflito de escrita entre dispositivos (um array seria reescrito inteiro e o último a gravar perderia mensagens). Custo: uma leitura por mensagem em vez de uma por conversa; aceitável (seção 4).

Índices: apenas de campo único (`updatedAt` em `conversations`, `createdAt` em `messages`), criados automaticamente. Nenhum índice composto.

Consultas:
- Lista: `conversations.orderBy('updatedAt', descending: true).limit(50)` com `snapshots()`.
- Conversa aberta: `messages.orderBy('createdAt', descending: true).limit(100)` com `snapshots()`, mais botão "carregar anteriores" com `startAfterDocument`.

## 2. Estratégia de sincronização

Código novo (para o builder): `lib/services/chat_repository.dart` (substitui `ChatStore` como fonte de verdade), provider `chatRepositoryProvider` em `lib/providers/app_providers.dart`, e `StreamProvider.family` para lista de conversas e mensagens. `ChatStore` permanece só para a migração (leitura do legado) e sai depois (tarefa 8). `OracleScreen` passa a observar providers em vez de guardar `_conversations` em estado local.

Leitura e escrita:
- A UI lê dos streams. Toda escrita local aparece imediatamente (compensação de latência do Firestore), sem manter cópia paralela em `setState`.
- Enviar mensagem = `WriteBatch` com (a) `set` da mensagem e (b) `update` da conversa (`updatedAt`, `messageCount` via `FieldValue.increment(1)`, `title` se for a primeira). Para criar a conversa, o batch usa `set`. Um batch por mensagem do usuário e outro por resposta do modelo.
- Gravar a mensagem do usuário antes de chamar o oráculo, como hoje. O histórico enviado ao modelo deve ser limitado às últimas 20 mensagens (hoje é ilimitado; evita estourar contexto/tokens agora que o histórico pode crescer).

Offline:
- Android e iOS: persistência do Firestore vem ligada por padrão. Web: vem desligada; ligar explicitamente em `main.dart` (`Settings(persistenceEnabled: true)`), sabendo que a persistência na web só funciona bem com uma aba aberta por vez (tratar `failed-precondition` sem travar o app).
- Offline, leituras saem do cache e escritas entram numa fila local; o SDK envia ao reconectar, na ordem. O app não precisa de lógica própria de retry.
- Importante: o `Future` de uma escrita só completa com confirmação do servidor, então offline ele não completa. O código não deve dar `await` no `commit()` antes de continuar o fluxo (diferente do `await _persist` atual). Disparar sem esperar e tratar erro com `catchError`/log.
- O oráculo em si precisa de rede; sem rede cai no `localReply`, e essa resposta é gravada normalmente na fila.
- Indicador discreto de "sincronizando" usando `snapshot.metadata.hasPendingWrites` (opcional).

Conflitos:
- Mensagens são imutáveis e têm id único: não há conflito. Dois dispositivos escrevendo na mesma conversa geram intercalação por `createdAt`; empate improvável e sem consequência.
- `title` e `updatedAt`: último a gravar vence. `messageCount` usa `increment`, que é seguro com concorrência.
- Exclusão de conversa prevalece sobre qualquer escrita pendente de outro dispositivo; para evitar ressurgimento, a regra de criação de mensagem exige que a conversa exista (seção 3).

Migração do SharedPreferences (uma vez, sem perda):
1. Gatilho: no primeiro carregamento do oráculo após login, se existir `astrum.chat.$uid` e não existir a flag `astrum.chat.migrated.$uid`.
2. Ler com `ChatStore.load`. Ignorar conversas vazias e o placeholder criado por `load` quando não há dado (usar uma leitura crua que distinga "sem dado" de "vazio").
3. Para cada conversa, em lotes de no máximo 400 operações: `set` da conversa com o mesmo `convId` e `messageCount`, e `set` de cada mensagem com id determinístico `m0001...`. `createdAt` sintético: horário da migração menos (N - i) milissegundos, preservando a ordem (o legado não tem datas). `createdAt` da conversa e `updatedAt` = horário da migração.
4. Idempotente: ids determinísticos com `set` significam que repetir (queda no meio, dois dispositivos migrando) apenas sobrescreve com o mesmo conteúdo. Se já houver conversa com o mesmo id na nuvem, a migração pula (não sobrescreve conteúdo mais novo).
5. Textos acima de 10000 caracteres são truncados (caso raro; o campo de entrada não tinha limite). Conversas além de 50: migrar as 50 mais recentes na ordem da lista e manter as demais no backup local.
6. Só depois de todos os batches confirmados pelo servidor (aqui sim aguardar `commit`; exige rede), gravar a flag de migração e renomear a chave antiga para `astrum.chat.$uid.bak`. O backup é apagado numa versão posterior (tarefa 8). Se falhar, nada é apagado e a tentativa se repete na próxima abertura.
7. Dois usuários no mesmo aparelho: a chave é por uid, então cada um migra os seus.

## 3. Regras de segurança (para o T07)

Princípios: apenas o dono (`request.auth.uid == uid`) lê e escreve; sem exceção de admin. O campo `role` em `users/{uid}` é gravável pelo próprio cliente (ver `createProfile`/`updateFields`), então qualquer regra baseada nele seria burlável; por isso não há acesso de admin. Se um dia for necessário (suporte, moderação), exige decisão do usuário e mecanismo seguro (custom claims, que dependem de backend).

Atenção ao compor o arquivo: regras se somam por OR. O T07 não pode ter um `match /users/{uid}/{document=**}` com `allow` mais amplo, senão ele anula as validações abaixo.

```
function isOwner(uid) { return request.auth != null && request.auth.uid == uid; }

match /users/{uid}/conversations/{convId} {
  function validConv(d) {
    return d.keys().hasOnly(['title','createdAt','updatedAt','messageCount','schemaVersion'])
      && d.title is string && d.title.size() >= 1 && d.title.size() <= 80
      && d.createdAt is timestamp && d.updatedAt is timestamp
      && d.messageCount is int && d.messageCount >= 0 && d.messageCount <= 500
      && d.schemaVersion == 1;
  }
  allow read: if isOwner(uid);
  allow create: if isOwner(uid) && validConv(request.resource.data);
  allow update: if isOwner(uid) && validConv(request.resource.data)
    && request.resource.data.createdAt == resource.data.createdAt;
  allow delete: if isOwner(uid);

  match /messages/{msgId} {
    allow read: if isOwner(uid);
    allow create: if isOwner(uid)
      && request.resource.data.keys().hasOnly(['role','text','createdAt'])
      && request.resource.data.role in ['user','model']
      && request.resource.data.text is string
      && request.resource.data.text.size() >= 1 && request.resource.data.text.size() <= 10000
      && request.resource.data.createdAt is timestamp
      && getAfter(/databases/$(database)/documents/users/$(uid)/conversations/$(convId)).data.messageCount <= 500;
    allow update: if false;
    allow delete: if isOwner(uid);
  }
}
```

Observações para o reviewer-consultor:
- `getAfter` avalia o estado depois do batch, então a mensagem só entra se o `update` da conversa no mesmo batch respeitar o teto; também exige que a conversa exista (impede ressurgimento de mensagens após exclusão). Cada `getAfter` conta como uma leitura (seção 4).
- Limitação conhecida: as regras não garantem que `messageCount` corresponde ao número real de mensagens; um cliente malicioso pode mentir sobre o contador na própria conta. O impacto é só na cota do próprio usuário; aceito.
- `list` e `get` ficam cobertos por `read`. Sem `collectionGroup` de leitura: nenhuma consulta de grupo é necessária, e sem regra para elas o acesso cruzado fica negado.
- Testar com o emulador de regras (`@firebase/rules-unit-testing`) casos: outro uid lê/escreve, não autenticado, campo extra, texto de 10001 caracteres, role inválido, update de mensagem, 501ª mensagem, criar mensagem sem conversa.

## 4. Custo no plano gratuito (Spark)

Cotas diárias: 50 mil leituras, 20 mil escritas, 20 mil exclusões; 1 GiB armazenado; 10 GiB/dia de saída. As cotas são do projeto inteiro e compartilhadas com eventos, amigos, notificações e `listUsers`.

Uso típico por usuário ativo/dia (supondo 10 trocas = 20 mensagens, 5 conversas guardadas):
- Escritas: cada mensagem = 1 mensagem + 1 atualização da conversa = 2. Total 40 escritas/dia (+1 criação eventual de conversa).
- Leituras: abrir a lista (5) + abrir uma conversa (até 100, típico 20 a 40, menos com cache válido) + `getAfter` das regras (20) + atualizações recebidas por listener (~0 em um só dispositivo). Total ~50 a 80 leituras/dia.
- Armazenamento: ~1 KB por mensagem com overhead de índices. Usuário intenso (50 conversas x 100 mensagens) = ~5 MB; típico < 200 KB.

Capacidade aproximada só do chat: escritas 20000/40 = ~500 usuários ativos/dia; leituras 50000/80 = ~600 usuários ativos/dia. Armazenamento não é o limite. Ou seja, o chat é viável para centenas de usuários diários e vira gargalo antes de milhares; ao se aproximar de ~300 DAU, avaliar o plano Blaze (que também destravaria Cloud Functions para exclusão em cascata). Mitigações já previstas: `limit(100)` nas mensagens, paginação, persistência offline (evita releituras) e cap de 20 mensagens de contexto (não afeta Firestore, só tokens).

Exclusão: apagar uma conversa de 100 mensagens = 101 exclusões; o tráfego é pequeno frente a 20 mil/dia.

## 5. Privacidade (LGPD)

Itens obrigatórios:
1. Apagar conversa: ação na UI (hoje não existe) com confirmação. Rotina `deleteConversation(uid, convId)`: listar e apagar as mensagens em lotes de 400 e por último o documento da conversa. A ordem (filhos primeiro) garante que, se for interrompida, a conversa continua visível e o usuário repete; não sobram mensagens órfãs invisíveis. Disparar `logDeleteConversation` (já existe no RN, comentado).
2. Apagar tudo / excluir conta: o app não tem hoje exclusão de conta. Precisa existir (Apple e Google Play exigem exclusão de conta dentro do app para apps com criação de conta, e a LGPD dá o direito de eliminação). Sequência no cliente: reautenticar (o Firebase exige login recente), apagar conversas e mensagens, depois as demais subcoleções (`events`, `friends`, `notifications`), depois `users/{uid}`, e por último `FirebaseAuth.currentUser.delete()`. Os dados vêm antes do usuário Auth porque, depois dele, as regras negam o acesso. Sem Cloud Functions não há garantia de cascata se o app for fechado no meio; mitigação: marcar `users/{uid}.deletionRequestedAt` antes de começar e retomar a rotina no próximo login enquanto o Auth existir. A extensão oficial "Delete User Data" exige Blaze, fica como alternativa futura.
3. Terceiros: hoje o oráculo não envia dados a terceiros de IA. Ele responde só com respostas locais (`localReply` em `lib/services/oracle_service.dart`), sem Groq nem Pollinations. O único envio para fora do aparelho previsto é a sincronização com o Firestore (Google, ver item 4). Se uma IA externa voltar a ser usada, o histórico enviado a ela é compartilhamento de dado sensível: precisa estar descrito na política de privacidade e, idealmente, ter consentimento explícito antes do primeiro uso do oráculo. Isso deve ser tratado como risco separado na época.
4. Política de privacidade e termos devem mencionar: armazenamento na nuvem (Firebase), finalidade, retenção até o usuário apagar, e transferência internacional (a região do banco Firestore precisa ser confirmada; ver decisões pendentes).
5. Criptografia: o Firestore cifra em repouso e em trânsito, mas o Google tem acesso técnico. Criptografia ponta a ponta no cliente não é proposta (sem recuperação de chave se o usuário perder o aparelho, e complexidade alta); fica como decisão do usuário.
6. Exportação (portabilidade): fora do escopo agora; a estrutura permite exportar depois lendo as coleções.
7. Logs e analytics: nunca enviar o texto das mensagens ao Analytics (hoje só `send_message_chat` sem conteúdo; manter).

## 6. Plano de implementação

| # | Tarefa | Papel | Depende de |
|---|---|---|---|
| 1 | Revisar este documento (privacidade, regras, exclusão de conta) | reviewer-consultor | - |
| 2 | Incluir no T07 as regras da seção 3 e testes no emulador (casos listados) | builder | 1 |
| 3 | `ChatRepository` (CRUD de conversas, envio de mensagem em batch, paginação, `deleteConversation`) + providers + testes com `fake_cloud_firestore` ou equivalente (avaliar a dependência de dev; sem impacto no app) | builder | 2 |
| 4 | Refatorar `OracleScreen` para streams/providers, sem `await` em escritas, `maxLength` 2000 no campo, limite de 20 mensagens de contexto, bloqueio em 50 conversas | builder | 3 |
| 5 | Migração única do SharedPreferences (seção 2) com testes: legado vazio, corrompido, re-execução, queda no meio, vários uids | builder | 3 |
| 6 | UI de apagar conversa e indicador de sincronização; `logDeleteConversation` | builder (com designer se houver tela nova) | 4 |
| 7 | Persistência offline na web (`Settings`) e teste manual offline/reconexão em Android e web | builder | 4 |
| 8 | Fluxo de exclusão de conta com reautenticação e retomada (`deletionRequestedAt`) | builder | 3 |
| 9 | Revisão do diff (regras, migração, exclusão de conta, texto de privacidade) | reviewer-consultor | 2 a 8 |
| 10 | Casos de teste e relatório em `docs/qa/`: regras (acesso cruzado), offline, migração a partir de dados reais do RN/Flutter antigo, exclusão de conversa e de conta | qa | 4 a 8 |
| 11 | Remover backup `.bak` e `ChatStore` numa versão posterior | builder | 10 e uma versão em produção |
| 12 | Atualizar política de privacidade, README e CHANGELOG | writer | 8 |

## Decisões que dependem do usuário

Ver a lista no final do relatório do architect (D9-a a D9-f).
