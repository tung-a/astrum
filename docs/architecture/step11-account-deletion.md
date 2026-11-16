# Etapa 11: exclusão de dados e de conta

Data: 2026-11-16. Status: implementado (passos 1 a 11 no código; ver "Desvios da implementação" ao fim; verificação manual em aparelho pendente, ver `docs/release-checklist.md`, seção 6b). Base: `step6-auth.md` (ponto de extensão do `AuthRepository`), `step10-chat-sync.md` (seções 5 e 14), `docs/decisions/2026-11-chat-sync-decisions.md`, `docs/release-checklist.md` (6b, bloqueante), `docs/plans/reestruturacao-etapas-1-a-3.md` (pendências da etapa 11, M1 e M3), `firestore.rules`, `test_rules/`.

Motivo: LGPD art. 18, VI e exigência da Apple de exclusão de conta dentro do app. **Bloqueante de release.** Premissas do usuário: não há usuários ativos (só contas de teste), mudanças drásticas (inclusive nas regras) são aceitas, Firebase segue no Spark (**sem Cloud Functions**: a cascata é do cliente).

## 1. Estado atual (verificado no código)

- **Provedor de login: só e-mail e senha** (`signInWithEmailAndPassword`; sem `google_sign_in`, sem Apple, sem `OAuthProvider`). Logo a reautenticação é por senha (`EmailAuthProvider.credential` + `reauthenticateWithCredential`). Não existe "esqueci minha senha" (`sendPasswordResetEmail`): quem esqueceu a senha com sessão aberta não consegue reautenticar (ver seção 11, risco R9). Se um dia entrar Google ou Apple: a reautenticação muda e, para Sign in with Apple, é obrigatório revogar o token (`revokeTokenWithAuthorizationCode`) ao excluir.
- Regras: `users/{uid}` `delete: if false` (linha 225); `publicProfiles/{uid}` `delete: if false`; `analytics_events` `update, delete: if false` e leitura só do admin. **Já permitem delete do dono**: `events` e `friends` (`read, write: if isOwner`), `notifications` (`allow read, delete: if isOwner`), `conversations` e `conversations/messages` (`delete: if isOwner`, feito na etapa 10). Nenhuma regra de subcoleção depende de `users/{uid}` existir para **apagar**.
- `ChatRepository.deleteConversation/deleteAllConversations` existem (`FirestoreChatRepository`): lêem páginas do **servidor** (`Source.server`), offline lançam `ChatOfflineException` sem apagar nada, `commit` com timeout de 15 s, filhos primeiro, idempotentes. `deleteAllConversations` hoje devolve `void`.
- `AuthRepository`: `signIn`, `register`, `signOut`. `AuthErrorCode.requiresRecentLogin` já existe.
- `ProfileRepository.watchProfile` **nunca emite null**: `AppUser.fromFirebase(data: null)` fabrica um perfil com saldo 0 e valores padrão. Por isso o app não distingue "perfil ausente" (pendências da etapa 6: conta Auth órfã, `email-already-in-use` preso, timeout do `createProfile`).
- `SocialRepository.sendIntention` grava em `users/{destino}/notifications` com `fromUid`/`fromName` do remetente: **existem dados nossos na caixa de terceiros**. `addFriend` grava em `users/{eu}/friends/{amigo}` (nome do amigo; e-mail e signo vazios na busca atual) e o amigo tem em sua lista só o que ele mesmo copiou de mim.
- `rebuildPublicProfiles` (admin) falha para terceiros (M1) e ignora `preferences.publicProfile=false` (M3).
- Analytics: **não há Firebase Analytics SDK**; só a coleção própria `analytics_events` (`eventName`, `userId` = uid, `createdAt`) via `AnalyticsService`, com eventos `login`, `sign_up`, `send_message_chat`, `add_event_calendar`, `delete_event_calendar`.
- Local: `shared_preferences` guarda só a flag `astrum.chat.notice.<uid>` (e `purgeLegacyChats` apaga restos `astrum.chat.<uid>` ao abrir o oráculo). Cache do Firestore (leveldb/SQLite do SDK) guarda o conteúdo das conversas no aparelho. `google_fonts` baixa e guarda fontes (nada pessoal). Android: `allowBackup="false"` já aplicado. iOS: sem nenhuma configuração de backup.
- Limite de camadas (`test/core_boundaries_test.dart`): `data/` de uma feature **não** importa `data/` de outra (exceções só `auth>profile`, `economy>profile`). Logo a orquestração da cascata mora num controller (camada de providers, que pode importar providers de outras features), e cada repositório ganha só o seu `deleteAll`.

## 2. Decisões de desenho (resumo)

| # | Decisão | Motivo |
|---|---|---|
| D1 | Exclusão imediata e irreversível; **sem período de espera**. | Sem Functions não há como executar exclusão agendada; o Apple aceita imediata. Ver Q1. |
| D2 | **Ordem: reautenticar, checar servidor, apagar `users/{uid}` + `publicProfiles/{uid}` (um batch), depois subcoleções, varredura final, por último o usuário Auth.** | Desvia da ordem "users depois dos filhos" do briefing, de propósito: o apagamento de `users/{uid}` vira o **marcador server-side** da exclusão em andamento ("perfil ausente"), visível em qualquer aparelho e sem flag local; fecha cedo a corrida de criação de conversas (regra `exists(users)`) e impede o `syncFromUser` de ressuscitar o perfil público. As regras de delete das subcoleções não dependem de `users/{uid}`. Dentro de cada coleção, filhos antes do pai (mensagens antes da conversa). |
| D3 | Cada passo é "apagar tudo sob X até uma página vazia lida do servidor": **idempotente, sem estado**. A retomada é só rodar de novo. | Simplicidade; sem tabela de progresso. |
| D4 | O **usuário Auth é o último**; todas as chamadas ao Firestore exigem `request.auth`, então depois dele nada mais pode ser limpo. | Ordem obrigatória. |
| D5 | **Perfil ausente** passa a ser detectado (`watchProfile` emite `null` quando o documento não existe no servidor) e leva à mesma tela de exclusão, que funciona nesse estado. | Resolve as pendências da etapa 6 (e-mail preso, conta órfã) sem fluxo novo de recriação. |
| D6 | Intenções **enviadas** por mim a terceiros são apagadas por consulta `collectionGroup('notifications').where('fromUid', ==, uid)` (regra e índice novos). Cópias do meu nome nas listas de amigos de outros ficam (backlog), com limpeza preguiçosa. Ver Q3. | Dado pessoal meu na caixa alheia; o campo já existe. Amigos não têm campo com meu uid. |
| D7 | Eventos de analytics do próprio uid são apagados (regra de leitura e delete só do próprio `userId`). Ver Q2. | `userId` é identificador; sem apagar, a exclusão é falsa. |
| D8 | Limpeza local: na exclusão, `prefs.clear()` + `terminate()` + `clearPersistence()` com **flag de contingência para a próxima partida a frio**. No logout, só drenar escritas pendentes e marcar a limpeza do cache para a próxima partida a frio (sem `terminate` em sessão). | `terminate()`/`clearPersistence()` em sessão têm comportamento a validar no aparelho; a flag torna a limpeza robusta. |

## 3. Exclusão de conversa e de todo o histórico (UI do oráculo)

Reverte a decisão Q4 de adiar o botão (`docs/decisions/2026-11-chat-sync-decisions.md`, item 7). Sem mudança em regras (já permitem).

### 3.1 UI (`oracle_screen.dart`)

- Novo `PopupMenuButton` (ícone `Icons.more_vert`, tooltip "Mais opções") na AppBar, ao lado do atual de seleção, com dois itens: "Apagar esta conversa" e "Apagar todo o histórico". Visível sempre que há `profile`; "Apagar esta conversa" desabilitado se a conversa atual for rascunho nunca gravado (`_draft` sem `_created`); "Apagar todo o histórico" desabilitado antes da hidratação.
- Diálogo de confirmação (`AlertDialog`, botão destrutivo com `AstrumColors` de erro, "Cancelar" à esquerda):
  - Conversa: título "Apagar esta conversa?". Corpo: "As mensagens desta conversa serão apagadas da nuvem e de todos os seus aparelhos. Não é possível desfazer."
  - Tudo: título "Apagar todo o histórico?". Corpo: "Todas as conversas com o oráculo, inclusive as que não aparecem na lista, serão apagadas da nuvem e de todos os seus aparelhos. Não é possível desfazer." Botão "Apagar tudo".
- Durante a exclusão: `ChatState.deleting` (novo bool) desabilita enviar, chips, "Nova conversa" e o próprio menu; indicador de progresso linear no topo do corpo.
- Resultado por `SnackBar`: "Conversa apagada." / "Histórico apagado." / offline "Sem conexão. Nada foi apagado. Tente de novo quando estiver online." / outro erro "Não foi possível apagar. Parte pode ter sido apagada; tente novamente." (idempotente: tentar de novo termina o trabalho).
- Aviso de privacidade: **novo `chatNoticeBody`**: "As conversas com o oráculo são armazenadas na nuvem (Firebase, região de São Paulo, southamerica-east1) para sincronizar entre os seus aparelhos. Elas ficam guardadas até você apagá-las, sem prazo de expiração. Você pode apagar uma conversa ou todo o histórico no menu do Oráculo; tudo também é apagado se você excluir a sua conta." A flag `astrum.chat.notice.<uid>` não muda (sem usuários ativos, ninguém precisa rever o aviso; se houver, trocar a chave para `...notice.v2`).

### 3.2 Controller (`chat_controller.dart`)

```dart
enum ChatDeleteResult { ok, offline, failed }
Future<ChatDeleteResult> deleteCurrent();   // conversa selecionada
Future<ChatDeleteResult> deleteAll();
```

- `deleteCurrent`: guarda `uid`, `gen` e `convId`; rascunho nunca gravado só é descartado em memória (sem rede). Persistida: `state = copyWith(deleting: true)`; `repo.deleteConversation(uid, convId)`; `finally` desliga `deleting` se `gen` ainda vale. A lista reativa (`watchConversations`) faz o resto: `_onCloud` seleciona a mais recente ou cria rascunho "Conversa 1". Uma resposta do oráculo em andamento é descartada pelo código existente (`_everSeen` e conversa sumida da lista).
- `deleteAll`: `deleteAllConversations(uid)`; ao fim a lista emite vazia e o controller cai no rascunho.
- Erros: `ChatOfflineException` e `FirebaseException unavailable/deadline-exceeded` viram `offline`; o resto `failed`; nunca logar texto, só `runtimeType`/código.
- Analytics: `chat_delete_conversation` e `chat_delete_all` (sem conteúdo nem contagem).
- Limite conhecido: a corrida da seção 5 de `step10` (outro aparelho grava entre a página vazia e o delete da conversa deixa mensagem órfã). Em exclusão **de conta** há varredura extra (seção 4, passo 8); em exclusão de **uma conversa** fica registrada como risco residual baixo.

## 4. Exclusão de conta

### 4.1 Peças novas ou alteradas

| Camada | Arquivo | Mudança |
|---|---|---|
| core | `core/firebase/paged_delete.dart` | `deleteQueryPaged(query, {page = 400, commitTimeout = 15 s})`: lê página do servidor, apaga em batch, repete até vazia; offline lança `ServerOfflineException` (core, sem dependência de feature). Retorna os ids apagados (limitado). |
| core | `core/analytics/analytics_service.dart` | `deleteOwnEvents(uid)` (consulta `userId == uid`). |
| core | `core/storage/local_data_cleaner.dart` | `wipeOnAccountEnd()` e `markCacheWipePending()`/`runPendingCacheWipe(db)` (seção 7). |
| data | `rituals/data/events_repository.dart` | `deleteAllEvents(uid)`. |
| data | `social/data/social_repository.dart` | `deleteAllFriends(uid)`, `deleteAllReceivedNotifications(uid)`, `deleteSentIntentions(uid)` (collection group), `removeFriend(uid, friendId)` (limpeza preguiçosa). |
| data | `profile/data/profile_repository.dart` | `deleteProfile(uid)`: **um batch** com `users/{uid}` e `publicProfiles/{uid}`, commit com timeout; `watchProfile` passa a emitir `null` se `!snap.exists` e a snapshot não for de cache (seção 4.4). |
| data | `oracle/data/chat_repository.dart` | `deleteAllConversations` passa a **devolver** `List<String>` (ids apagados) para a varredura. |
| data | `auth/data/auth_repository.dart` | `reauthenticate(password)` e `deleteAccount()` (seção 4.3). |
| presentation | `profile/presentation/delete_account_controller.dart` | `Notifier` com a orquestração (seção 4.2), estado `DeleteAccountState`. |
| presentation | `profile/presentation/delete_account_screen.dart` | Tela `/account/delete` (seção 8). |
| presentation | `app/router.dart` | rota `/account/delete`; `RouterProfileKey` ganha `profileMissing`; redirect (seção 4.4). |

### 4.2 Sequência (idempotente e retomável)

`DeleteAccountController.run(password)`; guarda contra duplo toque (`phase == running`); `PopScope(canPop: false)` na tela enquanto roda.

0. **Pré-condições** (nada é apagado se falharem): usuário logado; `reauthenticate(password)` (erro: senha incorreta, muitas tentativas, rede); leitura de `users/{uid}` com `Source.server` (offline: aborta com "sem conexão"; o documento inexistente é lido sem erro, as regras de leitura são só `isOwner`); `waitForPendingWrites` com timeout de 5 s (descarta fila antiga no passo 9). Marca `deletionInFlight = true` (router).
1. Grava a flag local `astrum.wipeCachePending` (sem dado pessoal).
2. **Perfil**: `deleteProfile(uid)` (batch de `users/{uid}` + `publicProfiles/{uid}`). A partir daqui o perfil está "ausente" em todos os aparelhos.
3. **Conversas**: `deleteAllConversations(uid)` (mensagens em lotes de 400, depois a conversa; pagina todas, não só as 50). Guarda os ids devolvidos.
4. **Eventos**: `deleteAllEvents(uid)`.
5. **Amigos**: `deleteAllFriends(uid)`.
6. **Notificações recebidas**: `deleteAllReceivedNotifications(uid)`.
7. **Intenções enviadas a terceiros**: `deleteSentIntentions(uid)` (`collectionGroup('notifications').where('fromUid', isEqualTo: uid)`; ver regra e índice na seção 6).
8. **Analytics do uid**: `deleteOwnEvents(uid)`.
9. **Varredura final** (corrida de LGPD da etapa 10, seção 5): `deleteConversation` de novo para cada id do passo 3 (1 leitura se limpo; apaga mensagem órfã gravada por outro aparelho no meio), e uma segunda passada vazia (1 leitura cada) em conversas, eventos, amigos e notificações recebidas (pega o que outro aparelho criou entre os passos).
10. **Conta Auth**: `deleteAccount()` (`user.delete()`). `requires-recent-login` (a cascata demorou mais que a janela de reautenticação) ou perfil não encontrado: ver 4.3. Sucesso: o `authStateChanges` emite `null`.
11. **Local** (sem Firebase, melhor esforço): `terminate()` + `clearPersistence()`; se der certo remove a flag do passo 1, senão a flag fica e a limpeza roda na próxima partida a frio (seção 7); `prefs.clear()` mantendo/regravando só a flag se necessária. Evento anônimo `account_delete_completed` (seção 9) e `deleteAccountNotice` para a tela de login exibir "Sua conta foi excluída.".

Progresso exposto como `DeleteStep` (enum: verificando, perfil, conversas, eventos, amigos, notificações, intenções enviadas, registros de uso, conferência, conta, limpeza), para a UI mostrar "Apagando conversas… (3 de 9)".

**Falha no meio**: o estado fica `failed(step, kind)` com `kind` em `offline` (`ChatOfflineException`, `ServerOfflineException`, `unavailable`, `deadline-exceeded`), `quota` (`resource-exhausted`: cota diária do Spark), `wrongPassword`, `tooManyRequests`, `requiresRecentLogin`, `unknown` (permission-denied, que indica regras não implantadas, é logado só como código). A UI oferece "Tentar de novo": o mesmo `run` reexecuta; passos já concluídos custam 1 leitura vazia cada. Como o passo 2 já removeu `users/{uid}`, qualquer reabertura do app (qualquer aparelho) cai no **perfil ausente** e na mesma tela. Se a senha for solicitada de novo e falhar, nada de novo é apagado; o usuário pode "Sair" e, se lembrar a senha, entrar e concluir.

**Perfil ausente**: o passo 2 é um `delete` de documento inexistente (permitido pela regra? `resource` é null: a regra `allow delete: if isOwner(uid)` não lê `resource`, passa) e os demais passos são varreduras. A tela mostra texto próprio (seção 8.2). Resolve também a conta Auth órfã do cadastro interrompido (libera o e-mail para novo cadastro).

**Corrida: outro aparelho do mesmo usuário gravando durante a exclusão.**
- Conversa nova: depois do passo 2 a regra `exists(users/{uid})` na criação de conversa (seção 6) nega. Antes do passo 2, a conversa nasce e é apagada nos passos 3 e 9.
- Mensagem em conversa existente durante o passo 3: a regra exige `getAfter(conversa)` coerente; se a conversa já foi apagada o batch falha; se a mensagem entrar entre a página vazia e o delete da conversa, o passo 9 a pega para os ids conhecidos. **Resíduo**: mensagem órfã em conversa que nunca esteve na lista local (criada e apagada por outro aparelho dentro da mesma janela de milissegundos). Aceito; coberto pela auditoria de órfãos (seção 11).
- **Ressurreição pelo outro aparelho após `user.delete()`**: o ID token dura até 1 h e as regras só checam `request.auth != null`, então o aparelho B poderia recriar `users/{uid}` (regra `create`) com saldo 500. Mitigação: B recebe `null` do listener do perfil no passo 2 e o router o leva a `/account/delete`, não a telas de escrita; fica o resíduo de escrita em voo. Fecha-se na auditoria de órfãos com Admin SDK (release-checklist). Alternativa descartada: lápide `deleted_accounts/{uid}` consultada em `create` (guarda uid para sempre; custo/benefício ruim).
- Filas offline antigas (escritas pendentes do uid): o passo 0 as drena ou aborta por falta de rede; o `terminate()`/`clearPersistence()` do passo 11 descarta o que sobrar (dívida da seção 14 de `step10`).

### 4.3 `AuthRepository`

```dart
Future<void> reauthenticate(String password);
Future<void> deleteAccount();
```

- `reauthenticate`: `user = _auth.currentUser`; se `user == null || user.email == null` ou `providerData` sem `password` lança `AuthException(unknown)` com `detail` genérico; `EmailAuthProvider.credential(email: user.email!, password: password)`; `reauthenticateWithCredential`. Erros mapeados por `authErrorCodeFromFirebase` (`invalid-credential`, `wrong-password` passa a mapear para `invalidCredentials`, `too-many-requests`, `network-request-failed`). Log só do código.
- `deleteAccount`: `user.delete()`; `requires-recent-login` vira `AuthException(requiresRecentLogin)` (a UI pede a senha de novo e chama `reauthenticate` + `deleteAccount`, sem repetir os passos de Firestore, que já terminaram); `user-not-found`/`user-token-expired`/`no-current-user` (outro aparelho já excluiu) são tratados como **sucesso** (`signOut` local).
- Texto de erro novo em `auth_exception.dart`: `deleteAccountErrorMessage(AuthException)`.
- Provedores futuros: documentar no comentário da interface que Google e Apple exigem outro fluxo e, no Apple, revogação de token.

### 4.4 Perfil ausente no app

- `watchProfile(user)`: `snapshots(includeMetadataChanges: true)`; descarta (não emite) snapshots `!exists && metadata.isFromCache` (offline sem cache: continua carregando, não conclui "ausente"); emite `null` quando `!exists` do servidor; `AppUser` caso exista. `profileProvider` já aceita `null` (telas mostram o spinner). Consumidores a revisar: `routerProfileKeyProvider`, `ShopController.equip`, `AccountScreen` (já trata `null`). Teste de que um cadastro recém-gravado offline (doc local pendente, `exists == true, isFromCache`) continua emitindo.
- `RouterProfileKey = ({bool isAdmin, bool isLoading, bool profileMissing})`; `profileMissing = uid != null && !p.isLoading && p.hasValue && p.value == null`. `deletionInFlight` (do controller) entra em `isLoading` como `signUpInFlight` (suprime redirects enquanto a cascata roda).
- `decideRedirect(..., profileMissing)`: logado + `profileMissing` + `!isLoading` + `location != '/account/delete'` retorna `/account/delete`; fora desse caso o comportamento atual não muda. Parâmetro novo com padrão `false` para não quebrar `router_test.dart`.
- Fora de escopo agora (registrado): "completar cadastro" (recriar o perfil de uma conta sem perfil). A única saída oferecida é excluir e sair.

## 5. Dados já enviados a terceiros e o que fica

| Dado | Destino | Tratamento |
|---|---|---|
| `users/{uid}` e subcoleções (eventos, amigos, notificações, conversas, mensagens) | Firestore | Apagados (passos 2 a 9). |
| `publicProfiles/{uid}` | Firestore (legível por qualquer logado) | Apagado no passo 2; o hash do e-mail some junto. |
| Intenções que enviei | `users/{outro}/notifications` | Apagadas pelo remetente via collection group (D6). |
| Meu nome copiado na lista de amigos de outra pessoa | `users/{outro}/friends/{eu}` | **Fica** (só o dono apaga; sem campo para consulta). Mitigação: `sendIntention` para conta excluída recebe `permission-denied` (nova regra `exists(users/{destino})`), a UI mostra "Esta conta não existe mais." e chama `removeFriend`. O texto da tela de exclusão avisa. Backlog: campo `friendUid` + collection group para apagar também. |
| Eventos de analytics com meu uid | `analytics_events` | Apagados (D7); depois só o evento anônimo de conclusão. |
| Cache local e prefs | Aparelho | Seção 7. |
| Registro do usuário Auth (e-mail, hash de senha) | Firebase Auth | Removido por `user.delete()`. O Google pode manter logs/cópias de segurança por prazo próprio; o texto da UI não promete prazo. |
| Fontes (google_fonts) | Cache do app | Sem dado pessoal; nada a fazer. A requisição de fonte expõe IP ao Google: citar na política de privacidade (ou empacotar as fontes, backlog). |

Retenção por obrigação legal: nenhuma identificada (sem pagamento, sem dados fiscais; o app não guarda logs de acesso/IP próprios). Ver Q2.

## 6. `firestore.rules`, índice e testes de regras (**exige `reviewer-consultor`**)

Marcado para o consultor: **tudo desta seção** (dados de usuário, autenticação, Firestore, economia).

### 6.1 Mudanças propostas (menor privilégio)

```
match /users/{uid} {
  allow delete: if isOwner(uid);            // era: if false
  ...
  match /conversations/{convId} {
    allow create: if isOwner(uid) && validConv(...) && messageCount <= 1
      && exists(/databases/$(database)/documents/users/$(uid));   // novo: sem perfil, sem conversa nova
  }
  match /notifications/{id} {
    allow create: if ... && exists(/databases/$(database)/documents/users/$(uid)); // novo: destino precisa existir
  }
}
match /publicProfiles/{uid} { allow delete: if isOwner(uid); }     // era: if false

// Intencoes que EU enviei, em qualquer caixa (collection group):
match /{path=**}/notifications/{id} {
  allow read, delete: if signedIn() && resource.data.fromUid == request.auth.uid;
}

match /analytics_events/{id} {
  allow read: if isAdmin() || (signedIn() && resource.data.userId == request.auth.uid);
  allow delete: if signedIn() && resource.data.userId == request.auth.uid;
  allow update: if false;
}
```

Observações para a revisão:
- Admin **não** ganha delete de `users` de terceiros (menor privilégio; remoção de conta de outro usuário é pelo console).
- A regra `{path=**}` exige `rules_version = '2'` (já é). Usar `resource.data.fromUid` (e não `.get(...)`) para a consulta provar a restrição. A leitura "como remetente" também vale em `get` direto, o que é inofensivo (o conteúdo é o que eu mesmo enviei).
- Efeito colateral aceito: o remetente pode retirar uma intenção enviada ainda não lida.
- `analytics_events`: o evento anônimo (`userId == 'anonymous'`) não casa com nenhum uid, ninguém o lê nem apaga fora do admin (que só lê). Consulta sem filtro por `userId` continua negada (o teste 184 existente).
- **Efeito econômico a registrar**: com `delete` do perfil liberado, o dono (cliente modificado) pode apagar `users/{uid}` e recriá-lo com saldo 500 e inventário inicial. Não gera ganho relevante: o saldo volta a 500 e perde-se o inventário e o equipado. **Teto real: 575 por recriação** (500 mais 3 check-ins de 25, porque a regra de check-in aceita as datas UTC de ontem, hoje e amanhã, em ordem crescente; tolerância que já existia antes da etapa). O mesmo ganho já se obtém com outra conta (outro e-mail). Caracterizado em `test_rules/` ("apos apagar e recriar o perfil, o teto e 575").
- **Create de `events` e `friends` exige `exists(users/{uid})`** (como conversas e notificações); update/delete seguem só do dono. Nenhum fluxo legítimo cria evento ou amigo sem perfil: o cadastro grava o perfil antes (`createProfile`), e a conta sem perfil cai na tela de exclusão. Evita que um aparelho com token válido recrie dados depois da exclusão. Custo: 1 leitura extra por criação.
- Risco aceito: `exists()` extra por criação de conversa e por intenção enviada (1 leitura cada, ver seção 10).

### 6.2 `firestore.indexes.json`

```json
"fieldOverrides": [
  { "collectionGroup": "notifications", "fieldPath": "fromUid",
    "indexes": [ { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" } ] }
]
```

A consulta de collection group por `fromUid` exige esse índice; ele leva um tempo para ser construído. **Implantar índice e regras antes de distribuir o cliente.**

### 6.3 Testes em `test_rules/` (porta por `FIRESTORE_EMULATOR_PORT`, padrão 8080)

Atualizar: o teste "delete do perfil negado" (linha 118) e "publicProfiles: delete pelo dono negado" (linha 544) passam a ser positivos. Novos casos:
1. `users` delete: dono ok; outro usuário, admin e anônimo negados.
2. Estado **perfil ausente**: após o delete, o dono ainda apaga (e lê, em consulta com filtro) `conversations`, `messages`, `events`, `friends`, `notifications`; criar conversa nova (com e sem mensagem no batch) negado; criar notificação para esse destino negado; recriar `users/{uid}` com saldo 500 funciona (caracterização, saldo não ultrapassa 500).
3. `publicProfiles`: dono apaga; outro não; recriar depois ok.
4. Collection group: remetente consulta `where('fromUid', '==', alice)` e apaga as suas na caixa de bob; consulta com o uid de outro, sem filtro ou apagar de terceiros, negados; o dono da caixa continua lendo/apagando as suas.
5. `analytics_events`: dono consulta `where('userId','==',uid)` e apaga os seus; consulta sem filtro e `userId` alheio negados; `update` negado; evento `anonymous` não apagável; admin continua lendo tudo.
6. `test/rules_contract_test.dart`: conferir se algum padrão depende de `allow delete: if false` ou da lista de `match`; ajustar o detector se necessário (não há constante de contrato nova).

## 7. Limpeza local

- **Exclusão de conta** (passo 11): `FirebaseFirestore.terminate()` e `clearPersistence()` (requer nenhum listener ativo; após `user.delete()` o `authStateProvider` emite `null` e os providers cancelam os streams; chamar depois de aguardar um `Future.delayed(Duration.zero)`/a próxima emissão). `prefs.clear()` apaga tudo (só há chaves `astrum.*`; nada de outros usuários vale preservar). Contingência: a flag `astrum.wipeCachePending` (gravada no passo 1) faz `main.dart`, depois de `Firebase.initializeApp` e **antes** de qualquer uso do Firestore, chamar `clearPersistence()` e remover a flag. Se o `terminate()` em sessão quebrar o uso posterior da instância (validar no aparelho: cadastrar nova conta logo depois), trocar para só a contingência e orientar "reinicie o app" (manual do qa).
- **Logout**: `waitForPendingWrites` com timeout de 5 s, `signOut`, e `markCacheWipePending()` (limpa na próxima partida a frio, sem `terminate` em sessão). Custo: reler a lista e a conversa aberta no próximo login (dezenas de leituras). Escritas que não drenaram em 5 s (offline) se perdem na limpeza: aceito e documentado; alternativa: não marcar a flag se `waitForPendingWrites` estourar (cache fica, pendências sobrevivem). **Recomendado:** não marcar se estourar.
- O cache local não é particionado por usuário, mas o app só consulta o próprio `uid`; o risco em aparelho compartilhado é baixo e é isso que a limpeza do logout reduz.
- **Android**: `allowBackup="false"` já está. Adicionar `android:dataExtractionRules` (`res/xml/data_extraction_rules.xml` excluindo `cloud-backup` e `device-transfer` de todos os domínios) para Android 12+ e `android:fullBackupContent="false"`; torna explícito e verificável. Sem risco funcional.
- **iOS**: `UserDefaults` (shared_preferences) e a pasta do cache do Firestore (`Library/Application Support/firestore`) entram no backup do iCloud/iTunes. Proposta: no `AppDelegate.swift`, antes de `GeneratedPluginRegistrant`, criar o diretório `Application Support/firestore` e marcar `URLResourceKey.isExcludedFromBackupKey = true`. Não há `Info.plist` para isso. **Não testável no Windows**: exige validação em Mac (checklist) e é o passo menos urgente; o Firebase Auth guarda a sessão no Keychain, removida por `signOut`/`delete`. Proteção de dados: o padrão do iOS (`CompleteUntilFirstUserAuthentication`) é suficiente; sem mudança.

## 8. UX da exclusão de conta

### 8.1 Entrada e estados

- `AccountScreen`: abaixo de "Sair", `TextButton` vermelho "Excluir minha conta" que abre `/account/delete`. O botão "Sair" passa a chamar o fluxo de logout da seção 7.
- `DeleteAccountScreen` (rota raiz, fora do shell, sem depender de `profile`): estados `idle` (formulário), `running` (progresso, sem voltar), `failed` (erro e "Tentar de novo"), `done` (navega ao login via redirect de auth `null`).
- Nenhuma tela mostra a senha digitada nem a guarda: o campo é local à tela, passado a `run(password)` e descartado.

### 8.2 Textos (português)

Título: "Excluir conta".

Corpo (conta com perfil): "Esta ação é permanente e não pode ser desfeita. Vamos apagar: seu perfil e seus dados de nascimento, seu mapa astral e horóscopos salvos, sua Poeira Estelar e todos os seus itens, seus eventos e rituais, todo o histórico de conversas com o oráculo, sua lista de amigos e as notificações que você recebeu, as intenções que você enviou, seu perfil público (você deixa de aparecer na busca de amigos), os registros de uso associados à sua conta e o acesso com seu e-mail e senha. Poeira Estelar e itens não podem ser recuperados nem reembolsados. Seu nome pode continuar aparecendo na lista de amigos de quem adicionou você, até essa pessoa removê-lo. Cópias de segurança do provedor (Google/Firebase) podem levar algum tempo para serem eliminadas."

Corpo (perfil ausente): "Esta conta não tem um perfil completo, por isso não é possível usar o app. Você pode excluí-la agora para apagar o que restou e liberar o e-mail para um novo cadastro. A exclusão é permanente."

Campo: "Digite sua senha para confirmar". Botão: "Excluir minha conta" (habilitado com senha não vazia) abre diálogo final: "Excluir a conta definitivamente? Não será possível desfazer." ("Cancelar" / "Excluir definitivamente").

Progresso: "Excluindo sua conta… Não feche o app." mais o rótulo do passo ("Apagando conversas… 3 de 9").

Erros:
- Senha incorreta: "Senha incorreta. Nada foi apagado."
- Muitas tentativas: "Muitas tentativas. Aguarde alguns minutos e tente de novo."
- Sem conexão: "Sem conexão. Conecte-se e toque em Tentar de novo. O que já foi apagado continua apagado."
- Cota diária: "O serviço atingiu o limite de hoje. Tente de novo mais tarde; o que já foi apagado continua apagado."
- Reautenticação exigida no fim: "Por segurança, digite sua senha novamente para concluir."
- Outro: "Não foi possível concluir a exclusão. Parte dos seus dados já foi apagada. Toque em Tentar de novo."
Sucesso (banner na tela de login, uma vez): "Sua conta foi excluída."

Acessibilidade: botão destrutivo com rótulo textual, `Semantics` no progresso, foco no campo de senha.

### 8.3 Aviso do oráculo e checklist

- `chatNoticeBody` conforme a seção 3.1.
- `docs/release-checklist.md`, seção 6b: marcar a UI de exclusão de conversa e de conta; remover o "em breve" (item 2); **adicionar**: (a) implantar índice e regras antes do cliente (ordem: catálogo, índices, regras); (b) testar no aparelho Android e iOS: exclusão com sucesso, modo avião no meio (retomada), perfil ausente, conta recém-criada em seguida; (c) política de privacidade atualizada (lista de dados, retenção, Google/Firebase como operador, fontes); (d) nota para a revisão da App Store: "Perfil > Excluir minha conta"; (e) rotina de **auditoria de órfãos** com Admin SDK (`users`/subcoleções sem usuário Auth; atualizar `scripts/audit_users.md`); (f) seção 5 ("Recriar perfis públicos") removida (seção 10).

## 9. Analytics sem dados pessoais

- `account_delete_completed`: registrado **depois** de `user.delete()`, já deslogado: `AnalyticsService` grava `userId = 'anonymous'` (regra existente aceita), sem uid, sem e-mail, sem contagem. Falha ao registrar é ignorada (já existe tratamento).
- `chat_delete_conversation` e `chat_delete_all`: com uid, como os demais eventos; somem na exclusão de conta (passo 8).
- Nenhum evento de início ou falha de exclusão (levariam uid; só entram no log local `debugPrint` com código).
- Dados já enviados: apagados pelo passo 8; resumo do admin (`uniqueUsers`) perde esses uids (esperado). O Firebase Analytics SDK não está no app; se entrar, exige `resetAnalyticsData()` na exclusão.

## 10. M1 e M3 (ligação) e `rebuildPublicProfiles`

Independentes da cascata, mas a regra de delete do `publicProfiles` as destrava; entram como passos finais separados.

- **`rebuildPublicProfiles`: remover** (método, botão "Recriar perfis públicos" em `admin_screen.dart`, teste, item 5 do release-checklist). Motivos: falha para terceiros (M1 aberto) e, se funcionasse, publicaria perfis de quem optou por sair (M3). Sem usuários ativos e com cada cliente gravando o próprio perfil público, não há migração a fazer. Regra do admin **não** é ampliada.
- **M3 (`publicProfile=false` ignorado)**: `ProfileRepository.setPublicProfile(uid, enabled)`: grava `preferences.publicProfile`; `true` chama `syncFromUser`; `false` apaga `publicProfiles/{uid}`. `PublicProfileSync.syncFromUser` passa a respeitar a preferência (se `false`, não grava). Interruptor novo em `AccountScreen`: "Aparecer na busca de amigos". O hash do e-mail sem sal e o `emailHash` arbitrário seguem fora do escopo (registrados).
- **M1 (avatar zodiacal revela o signo com `showSign=false`)**: função pura `publicAvatarFor(avatar, showSign)` em `public_profile.dart`: se `!showSign` e o avatar começa com `pfp_zodiac_`, publica `''`. `setShowSign` e `saveAstralMap` passam a chamar `syncFromUser` (corrige também o avatar defasado). Decisão do usuário já registrada em `docs/decisions/` é pré-requisito: se não houver, perguntar (recomendo aplicar).

## 11. Riscos

| # | Risco | Tratamento |
|---|---|---|
| R1 | Exclusão parcial (app morto, rede cai). | Idempotente; perfil ausente é o marcador no servidor; tela de retomada. |
| R2 | Mensagem órfã por corrida (outro aparelho). | Varredura do passo 9; resíduo raro coberto pela auditoria Admin SDK. |
| R3 | Outro aparelho recria o perfil com token ainda válido (até 1 h). | Router o leva à tela de exclusão; auditoria de órfãos; lápide descartada. |
| R4 | Cota do Spark (20 mil exclusões/dia, 50 mil leituras). | `resource-exhausted` vira mensagem de "tente mais tarde"; retomável. Ver custo. |
| R5 | Janela de reautenticação (~5 min) vence antes do `user.delete()`. | Pedir a senha de novo só para o passo 10. |
| R6 | `terminate()`/`clearPersistence()` em sessão com comportamento incerto. | Flag de contingência para partida a frio; validar no aparelho. |
| R7 | Regra `{path=**}/notifications` ampla demais. | Restrita a `fromUid == request.auth.uid`; teste de negação; consultor. |
| R8 | Delete do perfil reabre "apagar e recriar para resetar o saldo". | Sem ganho acima de 500 (seção 6.1); teste de caracterização. |
| R9 | Usuário que esqueceu a senha não reautentica. | Backlog imediato: "Esqueci minha senha" (`sendPasswordResetEmail`) na tela de login; até lá, contato do suporte na política. Recomendado entrar na etapa 11 como passo opcional (seção 12, passo 11). |
| R10 | Cópia do meu nome na lista de amigos de terceiros. | Limpeza preguiçosa + aviso no texto; backlog `friendUid`. |
| R11 | Texto prometer mais do que ocorre. | Texto revisado (seção 8.2); sem prazo de eliminação em backups; revisão jurídica da política. |

## 12. Custo (por exclusão) e passos

Custo, com `M` mensagens, `C` conversas, `E` eventos, `F` amigos, `N` notificações recebidas, `S` intenções enviadas, `A` eventos de analytics:

- Leituras do servidor ≈ `M + 2C + E + F + N + S + A` + ~12 (verificações e varredura). Exclusões ≈ `M + C + E + F + N + S + A` + 2. Regras de delete não fazem `get`, sem leitura extra.
- Exemplo: `M=300, C=8, E=20, F=10, N=15, S=10, A=300` ≈ 680 leituras e 665 exclusões (o cap de exclusões do Spark é 20 mil/dia: ~30 contas desse tamanho por dia saturam; conta típica é bem menor). Os `A` dominam; se virar problema, limitar o log de analytics (etapa 13, higiene).
- Exclusão de conversa isolada: `m + 2` leituras e `m + 1` exclusões.
- Regras novas: +1 leitura por criação de conversa e por intenção enviada (`exists`). Mensagens não mudam.

Passos (um commit cada, `flutter analyze` e `flutter test` verdes em todos; `reviewer` comum em cada um; **RC = `reviewer-consultor`, uma passada única, nos passos 1, 4, 5, 6, 7**):

| # | Commit | Conteúdo | Verificação |
|---|---|---|---|
| 1 (RC) | `feat(rules): exclusao do dono, regras de perfil ausente e de intencoes enviadas` | Seção 6: `firestore.rules`, `firestore.indexes.json`, `test_rules/` (casos da 6.3), ajustes em `rules_contract_check` se preciso. | `FIRESTORE_EMULATOR_PORT=<livre> node run-tests.mjs` (não usar emulador em uso). |
| 2 | `feat(oracle): apagar conversa e historico` | Seção 3: `deleteCurrent/deleteAll`, `deleting`, menu, diálogos, novo aviso, `deleteAllConversations` devolve ids; testes de controller (`InMemoryChatRepository`: ok, offline, falha, descarte da resposta em andamento, rascunho) e de widget (confirmação, cancelar, snackbars). | `flutter test`. Independente do passo 1 (regras já permitem). |
| 3 | `feat(core): exclusao paginada e limpeza local` | `paged_delete.dart`, `LocalDataCleaner`, `AnalyticsService.deleteOwnEvents`, `runPendingCacheWipe` em `main.dart`. | `fake_cloud_firestore`: >400 docs, vazio, retomada, offline (sobrescrever o leitor como em `getServerPage`). |
| 4 (RC) | `feat(data): deleteAll nos repositorios` | Eventos, amigos, notificações recebidas e enviadas (collection group), `deleteProfile`, `removeFriend`, `sendIntention` com `permission-denied` tratado. | `fake_cloud_firestore`; fakes em `test/support/fake_repositories.dart` ganham os métodos. |
| 5 (RC) | `feat(auth): reautenticacao e exclusao da conta Auth` | Seção 4.3 e textos de erro. | `FakeFirebaseAuth` ganha `reauthenticateWithCredential`/`delete` com falhas injetáveis; casos: senha errada, recente-login, usuário já excluído, sem provedor senha. |
| 6 (RC) | `feat(profile): perfil ausente` | Seção 4.4: `watchProfile`, `RouterProfileKey`, `decideRedirect`, rota. | `router_test` (novo parâmetro), `profile_repository` com `fake_cloud_firestore` (doc inexistente servidor vs cache), cadastro offline continua emitindo. |
| 7 (RC) | `feat(profile): exclusao de conta` | `DeleteAccountController` + tela + botão em `AccountScreen` + banner no login + logout com limpeza. | Controller: ordem dos passos (fakes registram chamadas), retomada após falha em cada passo, perfil ausente, duplo toque, requires-recent-login só repete Auth, sem texto/senha em log; widget: formulário, diálogo final, progresso, erros e "Tentar de novo". |
| 8 | `refactor(admin): remove rebuildPublicProfiles` | Seção 10. | Testes de admin ajustados. |
| 9 | `feat(profile): publicProfile e avatar sem revelar o signo (M3, M1)` | Seção 10; precisa da decisão do usuário sobre M1. | `public_profile_test`, `profile_repository` (sync respeita preferência). |
| 10 | `chore(platform): backup android e ios` | `data_extraction_rules.xml`; `AppDelegate.swift` (validar no Mac). | Build Android; iOS no checklist manual. |
| 11 (opcional) | `feat(auth): esqueci minha senha` | `sendPasswordResetEmail` na tela de login. | Teste de widget e repositório. |
| 12 | `docs: etapa 11` | `release-checklist.md` (6b e itens da seção 8.3), `overview.md`, `step6-auth.md` (ponto de extensão realizado), `step10-chat-sync.md` seção 14 (marcar resolvida), plano, `scripts/audit_users.md`, `docs/qa/etapa-11.md` (qa), CHANGELOG (writer). | Links válidos. |

Ordem de implantação: índices e regras (passo 1) antes de distribuir qualquer cliente com os passos 2 a 7.

## 13. Perguntas ao usuário (decisões que só você toma)

- **Q1 (período de espera).** Excluir na hora (irreversível) ou aguardar N dias antes da exclusão definitiva? Sem Cloud Functions não há agendamento seguro. **Recomendo exclusão imediata**, com confirmação dupla (senha + diálogo).
- **Q2 (retenção e analytics).** Há alguma obrigação ou interesse em reter dados após a exclusão (ex.: registros de uso, estatísticas)? **Recomendo reter nada identificável**: apagar também os eventos de analytics do uid (exige as regras de leitura/delete do próprio `userId`) e manter só o evento anônimo `account_delete_completed`.
- **Q3 (terceiros).** Apagar as intenções que o usuário enviou na caixa de outros (regra de collection group e índice novos) e deixar o nome na lista de amigos alheios com aviso e limpeza preguiçosa? **Recomendo sim** para as intenções e aceitar o resíduo dos amigos (backlog `friendUid`).
- **Q4 (ordem).** Confirma a ordem com `users/{uid}` **primeiro** (marcador no servidor) em vez de depois das subcoleções? **Recomendo aceitar** (seção 2, D2).
- **Q5 (M1).** Esconder o avatar zodiacal público quando "Exibir meu signo" está desligado (passo 9)? **Recomendo sim.**
- **Q6 (senha esquecida).** Incluir "Esqueci minha senha" nesta etapa (passo 11)? **Recomendo sim** (sem ele, quem esqueceu a senha não consegue excluir a conta pelo app).


## 14. Desvios da implementação

- **Sem `terminate()` em sessão.** A limpeza do cache do Firestore usa só a flag `astrum.wipeCachePending` e `clearPersistence()` na próxima partida a frio (`LocalDataCleaner.runPendingCacheWipe`, chamado em `main` antes de qualquer uso do Firestore). Motivo: reutilizar o Firestore depois de `terminate()` na mesma sessão (cadastro de nova conta logo após a exclusão) é arriscado e não é testável no Windows. A exclusão grava a flag **antes** de apagar dados e `prefs.clear()` mantém só a flag; o logout marca a flag só se `waitForPendingWrites` (5 s) drenou.
- `ChatOfflineException` passou a **estender** `ServerOfflineException` (core), para o controller de exclusão tratar as duas sem importar `data/` do oráculo.
- `ProfileRepository` ganhou `ensureServerReachable(uid)` (leitura `Source.server` de `users/{uid}`) e `drainPendingWrites()` (5 s), usados na pré-condição; `FirebaseAuthRepository.deleteAccount` com usuário nulo é sucesso.
- `sendIntention` a conta excluída: `permission-denied` **e** `publicProfiles/{destino}` ausente viram `RecipientUnavailableException` ("Esta conta não existe mais." e `removeFriend`); com perfil público presente o erro original sobe (evita remover amigo por outra negação de regra). Quem desligou "Aparecer na busca de amigos" pode gerar esse aviso (limite aceito).
- **Remetente lê o campo `read`** das notificações que enviou (a regra de leitura por `fromUid` expõe o documento inteiro): ele vê se o destinatário já leu a intenção. Aceito; registrado como limite.
- **NSUserDefaults (shared_preferences) no iOS ficam no backup do iCloud.** Hoje só guardam flags `astrum.*` (sem dado pessoal); a exclusão apaga as chaves e deixa só a flag de limpeza. Não guardar dado pessoal ali.
- **Resíduos de token de 1 h:** depois de `user.delete()`, outro aparelho com ID token ainda válido (até 1 h) pode gravar até o token expirar; `events`/`friends`/conversas/notificações novas agora exigem o perfil, mas campos de `users`/`publicProfiles` recriados por esse aparelho dependem da auditoria de órfãos (`scripts/audit_users.md`).
- Revisão: o estado de exclusão guarda o uid que o iniciou (nunca pula a cascata para outro uid); `sendIntention` a conta que parece excluída só avisa (não remove o amigo, pois `publicProfiles` some também com a busca desligada) e a mensagem passou a "Esta conta não está mais disponível."; `deleteAccount` só trata `user-not-found` como já excluída (`user-token-expired` vira reautenticação); `clearPersistence()` na partida tem prazo de 3 s e `wipeOnAccountEnd` grava a flag antes de remover as demais chaves; excluir conversa/histórico é recusado durante resposta em andamento.
- Progresso: 11 etapas (`DeleteStep`), "n de 11".
- O sync do perfil público (`syncFromUser`) respeita `publicProfile` e `showSign`; `setShowSign` e `saveAstralMap` regravam o perfil público (M1/M3).
- `docs/qa/etapa-11.md` e o CHANGELOG ficam com os agentes `qa` e `writer`; o CHANGELOG recebeu uma entrada resumida.
