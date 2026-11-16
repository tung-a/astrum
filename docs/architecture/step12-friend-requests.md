# Etapa 12: aceite de amizade pelo destinatário

Data: 2026-11-16. Status: **implementada na branch (passos 1 a 8, incluindo o opcional 7); verificação manual e deploy de regras pendentes, ver `docs/release-checklist.md`**. Base: `docs/decisions/2026-11-restructuring-decisions.md` (item 3: aceite desejável; "aceite de amizade altera modelo e regras; exige `reviewer-consultor`"), `step11-account-deletion.md` (cascata, marcador "perfil ausente", `exists(users/{uid})`, collection group de `notifications`), `docs/plans/reestruturacao-etapas-1-a-3.md` (backlog, item 12), `firestore.rules`, `test_rules/`.

Nota de numeração: `restructuring-decisions.md` ainda chama de "etapa 12" o upgrade de dependências; o plano renumerou (aceite = 12, higiene = 13, upgrade = 14). Usar a numeração do plano.

Premissas do usuário: sem usuários ativos (migração livre, pode-se zerar `friends`), Spark sem Cloud Functions, só iOS e Android, sempre seguir as recomendações.

## 1. Problema (verificado no código, antes da etapa 12)

- Antes da etapa 12, `SocialRepository.addFriend` gravava só em `users/{eu}/friends/{outro}` (nome copiado da busca por hash). O outro lado não sabia e não consentia (a subcoleção `friends` foi removida).
- A regra de `notifications` (create) aceitava qualquer remetente que tivesse o destino na **própria** lista `friends` (`exists(users/{eu}/friends/{uid})`). Logo qualquer logado que achasse o e-mail de alguém enviava intenções sem aceite: era o vetor de spam (hoje exige `friendships/{par}.status == 'accepted'`).
- O cliente só escreve no próprio `uid` (e em `notifications` alheias com regra estrita). Sem Admin SDK, o "vínculo nos dois lados" não pode ser gravado por uma pessoa só.
- Resíduo R10 da etapa 11: meu nome fica copiado na lista de quem me adicionou, mesmo após eu excluir a conta.

## 2. Modelo escolhido: documento de relação único

### 2.1 Alternativas avaliadas

| Alternativa | Como o aceite grava no lado do remetente | Veredito |
|---|---|---|
| A. (descartada) Pedido em `users/{to}/friendRequests/{from}`; aceite cria `users/{to}/friends/{from}` e **espelho** `users/{from}/friends/{to}` por regra que valida o pedido com `get()` | O destinatário escreve na lista alheia (precisa `get` + `exists` e regra de create por terceiro). | Rejeitada: dois documentos para manter coerentes, escrita de terceiro em coleção privada, remoção de um lado deixa o outro vinculado (sem aceite), e o nome continua copiado em lista alheia após exclusão (R10 persiste). |
| B. Cada lado "reivindica": destinatário marca o pedido como aceito e o remetente, ao abrir o app, consulta pedidos aceitos e cria o próprio `friends` | Remetente lê o pedido alheio por collection group (`fromUid`) e grava o próprio vínculo. | Rejeitada: o vínculo só existe quando o remetente abre o app (janela assimétrica, intenção de volta recusada), precisa de outro collection group e índice, e a limpeza continua em duas listas. |
| **C. Um documento de relação por par em `friendships/{pairId}`** | Não há "outro lado": o par tem **um** documento que os dois leem; o remetente cria (`pending`), o destinatário altera só o `status`. | **Escolhida.** Cada escrita é de quem a autoriza, atomicidade natural, duplicidade e pedido cruzado resolvidos pelo próprio id, exclusão de conta apaga o par inteiro (fecha R10), sem collection group nem índice composto. |

### 2.2 Coleção `friendships/{pairId}` (raiz)

`pairId = menorUid + '_' + maiorUid` (comparação lexicográfica; uids do Firebase Auth são alfanuméricos, sem `_`). A mesma função existe em Dart (`pairIdOf`) e nas regras.

| Campo | Tipo | Quem grava | Observação |
|---|---|---|---|
| `uids` | list[string] de 2 | criador | `[menor, maior]`, `uids[0] < uids[1]` (impede pedir a si mesmo); id == `uids[0]_uids[1]`. Imutável. |
| `requesterUid` | string | criador | == `request.auth.uid`, está em `uids`. Imutável. |
| `requesterName` | string 1..100 | criador | == `users/{eu}.name` (a regra confere por `get`). Nomes não são editáveis no app, então não envelhecem. |
| `status` | `'pending'` \| `'accepted'` \| `'declined'` | ver 2.3 | |
| `responderName` | string 1..100 | destinatário, no aceite | == `users/{eu}.name`. |
| `declinedBy` | string | quem recusa/remove | só com `status == 'declined'`. |
| `createdAt` | timestamp | criador | == `request.time`. |
| `respondedAt` | timestamp | quem muda o status | == `request.time`. |

Sem avatar, signo, e-mail ou hash na relação: o destinatário vê só o nome (o mesmo `name` que o remetente já publica em `publicProfiles`). Signo/avatar do amigo: backlog (copiar só se `showSign`, validado por `get(users/{eu}.preferences)`); hoje o `Friend` vindo da busca já tem signo vazio, então não há regressão.

### 2.3 Máquina de estados (transições que as regras permitem)

```
(inexistente) --criar (remetente)--------------------> pending
pending  --aceitar (NÃO remetente)--------------------> accepted     (afeta só status, responderName, respondedAt)
pending  --recusar (NÃO remetente)--------------------> declined     (declinedBy = eu)
accepted --remover amizade (qualquer um dos dois)-----> declined     (declinedBy = eu)
pending  --cancelar (remetente)  [delete]------------> (inexistente)
declined --"desbloquear" (declinedBy)  [delete]-------> (inexistente)
qualquer --exclusão de conta (membro sem users/{eu})--> (inexistente)
```

`declined` funciona como **lápide**: enquanto existir, o outro lado **não** consegue criar de novo (o id já existe; update por quem não recusou é negado) nem apagar. Isso entrega "sem pedido a quem recusou ou removeu" e "sem duplicata" sem contador. Quem recusou/removeu pode "desbloquear" (apaga a lápide) e, se quiser, buscar a pessoa de novo.

### 2.4 Regras propostas (esboço; implementação do builder, **revisão do `reviewer-consultor`**)

```
function pairId(a, b) { return a < b ? a + '_' + b : b + '_' + a; }

match /friendships/{pid} {
  // get por id (precisa funcionar com documento inexistente, para a transação do pedido cruzado);
  // list so de documentos em que sou membro (consulta array-contains prova a restricao).
  allow get: if signedIn() && request.auth.uid in pid.split('_');
  allow list: if signedIn() && request.auth.uid in resource.data.uids;

  allow create: if signedIn()
    && request.resource.data.keys().hasOnly(['uids','requesterUid','requesterName','status','createdAt'])
    && request.resource.data.uids is list && request.resource.data.uids.size() == 2
    && request.resource.data.uids[0] < request.resource.data.uids[1]
    && pid == request.resource.data.uids[0] + '_' + request.resource.data.uids[1]
    && request.auth.uid in request.resource.data.uids
    && request.resource.data.requesterUid == request.auth.uid
    && request.resource.data.status == 'pending'
    && request.resource.data.createdAt == request.time
    && exists(users/$(request.auth.uid))
    && request.resource.data.requesterName == get(users/$(request.auth.uid)).data.name
    // o outro precisa existir E aparecer na busca (preferencia "Aparecer na busca de amigos")
    && exists(publicProfiles/$(outro)) && exists(users/$(outro));
        // outro = uids[0] == auth.uid ? uids[1] : uids[0]

  allow update: if signedIn() && request.auth.uid in resource.data.uids
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['status','responderName','declinedBy','respondedAt'])
    && request.resource.data.respondedAt == request.time
    && exists(users/$(request.auth.uid))
    && (
      // aceitar: pending -> accepted, por quem NAO pediu, com o remetente ainda existente
      (resource.data.status == 'pending' && resource.data.requesterUid != request.auth.uid
        && request.resource.data.status == 'accepted'
        && request.resource.data.responderName == get(users/$(request.auth.uid)).data.name
        && exists(users/$(resource.data.requesterUid)))
      // recusar (por quem nao pediu) ou remover amizade (qualquer membro)
      || ((resource.data.status == 'accepted'
            || (resource.data.status == 'pending' && resource.data.requesterUid != request.auth.uid))
          && request.resource.data.status == 'declined'
          && request.resource.data.declinedBy == request.auth.uid)
    );

  allow delete: if signedIn() && request.auth.uid in resource.data.uids
    && (
      !exists(users/$(request.auth.uid))                                          // exclusao de conta (marcador da etapa 11)
      || (resource.data.status == 'pending' && resource.data.requesterUid == request.auth.uid)  // cancelar pedido
      || (resource.data.status == 'declined' && resource.data.declinedBy == request.auth.uid)); // desbloquear
}
```

Pontos para o consultor: `get` por id com `split('_')` (vazamento de existência só do par que contém o próprio uid); `affectedKeys` fixa `uids`, `requesterUid`, `requesterName`, `createdAt`; na transição `declined` o doc mantém `responderName` ausente (aceite nunca ocorreu); `delete` com `!exists(users/{eu})` reaproveita o marcador "perfil ausente" e permite que a cascata apague também lápides em que fui o recusado; ninguém além dos dois membros lê. Admin **não** lê relações (menor privilégio).

### 2.5 Intenções: só amigos aceitos

Regra de `users/{uid}/notifications` (create) troca a linha `exists(users/{eu}/friends/{uid})` por:

```
&& get(/databases/$(database)/documents/friendships/$(pairId(request.auth.uid, uid))).data.status == 'accepted'
```

(ausente ou diferente de `accepted` nega). Custo igual ao atual (1 leitura). A **subcoleção `friends` deixa de existir nas regras** (cai no curinga negado). Mesma regra de `exists(users/{uid})` do destino e `fromName` continuam.

### 2.6 Anti-spam: o que as regras conseguem e o que não

Honestidade: **no Spark as regras não contam documentos**, então "no máximo N pedidos pendentes por usuário" **não** é imposto no servidor. Contador em `users/{eu}` desincroniza (o destinatário recusa e não pode decrementar o contador do remetente) e remover entradas "à vontade" anula o limite; descartado por custo/benefício. O que **é** imposto:

1. **Sem pedido para si mesmo** (`uids[0] < uids[1]`), **sem duplicata** (id único por par), **sem pedido a quem recusou/removeu** (lápide), **sem pedir a conta inexistente**.
2. **Quem desliga "Aparecer na busca de amigos" não recebe pedidos** (create exige `publicProfiles/{outro}`): comportamento novo, e é o controle do destinatário contra spam.
3. **Pedido não gera notificação nem push**: aparece só como contador na tela de pedidos (a intenção só chega a quem aceitou). O dano máximo de um spammer é uma linha na lista do alvo, que o alvo recusa (a lápide barra o mesmo remetente para sempre).
4. **Pedir exige conhecer o e-mail exato** (hash; ver seção 6).
5. Limite **só no cliente**: máximo de 20 pedidos enviados pendentes (mensagem "Você já tem muitos pedidos aguardando resposta."), mais confirmação com o nome antes de enviar. Não é barreira de segurança, só higiene de UX.
6. Teto real exige Cloud Functions/Blaze (fora do escopo, decisão do usuário). Registrar como risco residual R-S1; **App Check** (já planejado para mobile) é a mitigação realista contra clientes forjados.

## 3. Migração e limpeza dos amigos autodeclarados

**Recomendação: zerar `users/*/friends` e não migrar.** Não há usuários ativos; migrar exigiria pedir aceite de cada par, que é exatamente o que a etapa cria. Passos:

1. Remover o uso de `friends` do código (`addFriend`, `watchFriends` antigo, `deleteAllFriends`) e a regra da subcoleção (passo 5 da seção 10).
2. Documentos antigos de contas de teste ficam **inalcançáveis** (curinga negado) e inofensivos; limpar pelo console ou pelo script de auditoria de órfãos (`scripts/audit_users.md`, acrescentar "apagar `users/*/friends`"). Não manter regra de delete só para isso.
3. Ordem de implantação: regras novas (aditivas) -> cliente -> regra de `notifications` e remoção de `friends` (ver 10).

## 4. Exclusão de conta (interação com a etapa 11)

- `deleteAllFriends(uid)` vira `deleteAllFriendships(uid)`: `deleteQueryPaged(db.collection('friendships').where('uids', arrayContains: uid))`. Mesmo `DeleteStep.friends` (rótulo na UI passa a "Apagando amizades e pedidos…"; contagem "n de 11" não muda). Roda **depois** do `deleteProfile` (já é a ordem), então a regra `!exists(users/{eu})` autoriza apagar qualquer relação, inclusive lápides em que fui o recusado.
- **Apaga pedidos enviados e recebidos e os vínculos nas "listas alheias" de uma vez**, porque não há mais lista alheia: fecha R10. O texto da tela de exclusão perde a frase "Seu nome pode continuar aparecendo na lista de amigos de quem adicionou você" e ganha "seus pedidos e amizades são removidos".
- Varredura final: repetir `deleteAllFriendships` (já existe a segunda passada de `friends`).
- **Heurística "conta não disponível"**: continua válida só para a corrida (amigo excluiu entre o carregar da lista e o toque). Troca o teste de `publicProfiles/{destino}` ausente (que dava falso positivo para quem desligou a busca) por: em `permission-denied`, reler `friendships/{pairId}`; se ausente ou `!= accepted` lança `RecipientUnavailableException` com a mensagem nova "Esta amizade não existe mais." (e a lista, que é stream, já se atualiza); se continua `accepted`, o erro original sobe. Mantém o `try/catch` defensivo atual.
- **Collection group e índices: nenhuma mudança.** A coleção é raiz, a consulta é `array-contains` em campo único (índice automático), a classificação é no cliente. O índice de `notifications.fromUid` continua. `firestore.indexes.json` **não muda**.
- Escrita pendente de aceite durante a exclusão: o aceite exige `exists(users/{eu})` e `exists(users/{remetente})` (2.4), então um aparelho com token válido não recria vínculo depois do passo `profile`.

## 5. Notificação do pedido (reaproveitar `notifications`?)

**Não reaproveitar.** `notifications` tem regra de create fechada em `type == 'intention'`, lista fixa de intenções e exige amizade aceita; abrir `type: friendRequest` aí criaria um segundo caminho de spam que o remetente nem precisaria de relação para usar, dobraria escritas (pedido + notificação) e exigiria sincronizar o ciclo de vida. O próprio documento `friendships` é o pedido: o destinatário o vê por uma consulta que já alimenta amigos, pedidos recebidos e enviados (um único listener). Sem push (não há FCM no app); o sinal é visual:

- Selo numérico no ícone "Perfil" do `MainShell` e card "Pedidos de amizade (n)" no topo de "Constelação".
- `intentionProvider` e o banner de intenção (`CosmicScaffold`) não mudam.

## 6. Privacidade e busca

- Destinatário vê: **nome** (`requesterName`) e "quer entrar na sua constelação". Sem e-mail, sem signo, sem avatar (backlog). O remetente, antes de enviar, vê o **nome e o avatar de `publicProfiles`** (que já respeitam "Aparecer na busca" e `publicAvatarFor`/`showSign`) e confirma: "Enviar pedido a <nome>?".
- "Aparecer na busca de amigos" desligado: não é achado e **não recebe pedidos novos** (2.6). Pedidos/amizades já existentes não são afetados. `showSign` não entra no modelo.
- Mensagens sem vazamento: busca sem resultado, alvo que desligou a busca, alvo que recusou/removeu e conta excluída produzem a **mesma** mensagem ao remetente ("Não foi possível enviar o pedido a esse e-mail."). Só "pedido já enviado" e "vocês já são amigos" são distintos (o remetente já conhece essa relação).
- **Enumeração em massa (limite do Spark, não resolvido aqui):** `publicProfiles` é legível por qualquer logado e a regra de `read` permite `list`; hoje já dá para varrer a coleção (nome + hash). Esta etapa **não piora** (a relação não expõe mais dados), mas recomendo, como passo opcional 7 e para o `reviewer-consultor`: trocar `allow read` por `allow get` (por uid) mais `allow list: if signedIn() && request.query.limit <= 1` (a busca por hash já usa `limit(1)`), o que encarece, mas **não impede**, a varredura paginada por um cliente forjado; a barreira real é App Check. Hash sem sal continua registrado como limite (etapa 11, seção 10).
- A lápide é silenciosa **só na interface**: ao remetente cuja solicitação foi recusada, a UI mostra "Aguardando resposta" e o mesmo botão "Cancelar pedido" de qualquer pedido enviado. Cancelar uma lápide (recusada por outro) não toca o servidor (as regras negariam e apagar liberaria novo pedido): o app responde "Pedido cancelado." e esconde o item só naquela sessão. O documento continua legível a um cliente modificado (`get`/`list` do próprio par), que enxerga `status: declined`; isso é aceito, pois o sigilo é de apresentação, não de dados. Evita constrangimento e retaliação.
- **Bloqueio próprio:** quando o par está em "Recusados e removidos" (eu recusei/removi), a busca avisa "Você recusou ou removeu essa pessoa. Desbloqueie em Pedidos de amizade." (só o próprio usuário vê isso); nos demais casos a mensagem genérica única não revela nada.
- **Varredura e `limit(1)`:** `limit(1)` em `publicProfiles` não impede varredura (paginação com `startAfter`); a barreira real é o App Check (etapa 13).
- **Nomes:** `requesterName` e `responderName` vêm de `users.name`, editável pelo dono sem regex; o risco é texto livre de até 100 caracteres exibido ao outro (a UI limita a uma linha com reticências).

## 7. UX (português)

Fluxo na `AccountScreen` e nova tela `FriendRequestsScreen` (rota `/account/requests`, raiz como `/account/delete`, não depende do shell; `designer` detalha a tela em `docs/design/`).

- **Constelação (AccountScreen)**: campo de e-mail + botão "Enviar pedido" (ícone `person_add_alt`); diálogo de confirmação com nome e avatar; lista de amigos aceitos (como hoje) com menu "Remover amizade" (diálogo: "Remover <nome>? Vocês deixam de trocar intenções e <nome> não poderá pedir amizade de novo, a menos que você desbloqueie."); item "Pedidos (n)" que abre a tela; seção "Pedidos enviados" (nome + "Aguardando resposta" + "Cancelar pedido" só se o servidor ainda mostra pendente; ver silêncio da lápide).
- **FriendRequestsScreen**: abas ou seções "Recebidos" (cartões com nome, "Aceitar" e "Recusar") e "Enviados"; "Recusados e removidos" (quem **eu** recusei/removi) com "Desbloquear".
- Estados: **carregando** (spinner da primeira emissão do stream), **vazio** ("Nenhum pedido por enquanto. Quando alguém quiser entrar na sua constelação, aparece aqui."), **erro** ("Não foi possível carregar seus pedidos." + "Tentar de novo" que reinvalida o provider), **offline** (as escritas na fila do Firestore enfileiram; para aceitar/recusar/pedir, falha por `unavailable` mostra "Sem conexão. Tente de novo quando estiver online." sem otimismo).
- Mensagens (snackbar): "Pedido enviado a <nome>."; "Pedido cruzado: vocês agora são amigos." (quando o outro já tinha pedido e o app aceitou); "Vocês já são amigos."; "Você já enviou um pedido a essa pessoa."; "Não foi possível enviar o pedido a esse e-mail." (genérica); "Você já tem muitos pedidos aguardando resposta."; "<nome> entrou na sua constelação."; "Pedido recusado."; "Amizade removida."; "Esta amizade não existe mais." (corrida); "Não foi possível concluir. Tente de novo."
- Acessibilidade: botões com rótulo textual; selo com `Semantics(label: 'n pedidos de amizade')`.

## 8. Camadas e código (`core_boundaries_test`)

| Camada | Arquivo | Mudança |
|---|---|---|
| core | `core/firebase/rules_contract.dart` | constantes: `friendshipPending/Accepted/Declined`, `friendshipNameMax = 100`, separador `'_'`, `maxPendingOutgoingClient = 20` (esta só do app). Cada uma com a função de regra em comentário. `test/support/rules_contract_check.dart` ganha as verificações. |
| core | `core/firebase/firestore_paths.dart` | `friendshipsCol`, `friendshipDoc(pairId)`. |
| domain | `social/domain/friendship.dart` | `Friendship` (uids, requesterUid, nomes, status, declinedBy), `pairIdOf(a, b)`, `FriendshipStatus`, `FriendshipsView {friends, incoming, outgoing, blockedByMe}` derivada por função pura `viewFor(uid, list)`. `Friend` continua para a UI (id, name). |
| data | `social/data/social_repository.dart` | `watchFriendships(uid)` (query `array-contains`), `requestFriendship(me, myName, other)` em **transação** (ver 9), `acceptFriendship`, `declineFriendship`, `removeFriendship`, `cancelRequest`, `unblock`, `deleteAllFriendships`. `findUserByEmail` mantém e passa a devolver também `avatar` (já devolve). Saem: `addFriend`, `removeFriend`, `watchFriends`, `deleteAllFriends`. |
| providers | `social/presentation/social_providers.dart` | `friendshipsProvider` (StreamProvider de `Friendship`), `friendshipsViewProvider` (Provider derivado), `friendsProvider` passa a ser `select` do view (mesmo tipo `List<Friend>`: a `AccountScreen` e `providers_subscriptions_test` mudam pouco), `incomingRequestCountProvider` (para o selo). Continua dependendo só de `currentUidProvider` (não reabre stream em mudança de saldo, requisito da história 2.1). |
| controller | `social/presentation/friendship_controller.dart` (novo) | `request(email)`, `accept`, `decline`, `remove`, `cancel`, `unblock`; devolve textos (padrão atual) e usa `profileProvider` só para `uid`/`name`. `AccountController.addFriendByEmail` é removido (delegado); `sendIntention` troca a heurística (seção 4). |
| apresentação | `profile/presentation/account_screen.dart`, `social/presentation/friend_requests_screen.dart`, `app/router.dart`, `app/shell/main_shell.dart` | UI da seção 7; `profile` já importa `social` (permitido). `main_shell` lê `incomingRequestCountProvider`. |
| profile | `delete_account_controller.dart` | `social.deleteAllFriendships`; `DeleteStep.friends` com novo rótulo. |

## 9. Corridas e transações

- **Pedido cruzado (A->B e B->A ao mesmo tempo)**: ambos usam o **mesmo** `pairId`. `requestFriendship` é `runTransaction`: `get(pairDoc)`; se ausente, `set(pending)`; se `pending` com `requesterUid == outro`, `update(accepted)` (os dois queriam: resolve como amizade e a UI avisa); se `pending` meu, devolve "já enviado" sem escrever; se `accepted`, "já são amigos"; se `declined`, mensagem genérica. Se ambas as transações leem "ausente", só uma cria; a outra falha no commit (a transação reexecuta no cliente e vê `pending` do outro, segue o caminho do aceite). Resultado final sempre válido: um documento, sem duplicata.
- **Aceite duplo** (dois aparelhos do destinatário, ou duplo toque): o segundo update falha na regra (`status != pending`); `acceptFriendship` trata `permission-denied` relendo o documento e, se `accepted`, devolve sucesso (idempotente). Botões desabilitados durante a chamada.
- **Aceitar vs. cancelar/recusar**: o aceite é update, o cancelamento é delete; o último a chegar falha e a UI relê (a stream já refletiu). Sem estado inconsistente: só existe um documento.
- **Exclusão concorrente**: ver seção 4.
- **Remover vs. enviar intenção**: a regra de `notifications` lê a relação a cada envio; após `declined` o envio nega e vira "Esta amizade não existe mais.".
- Offline: transação exige servidor; falha com `unavailable` (mensagem de conexão). Aceitar/recusar/remover como `update` simples entram na fila offline normal; efeito otimista pela stream do cache.

## 10. Passos (um commit cada; `flutter analyze` e `flutter test` verdes; `reviewer` comum em todos; **RC = `reviewer-consultor`**)

| # | Commit | Conteúdo | Verificação |
|---|---|---|---|
| 1 (RC) | `feat(regras): friendships (pedido, aceite, recusa, remocao)` | Seção 2.4 em `firestore.rules` (**aditivo**: `friends` e `notifications` ainda como hoje, o app segue funcionando); constantes em `rules_contract.dart` e `rules_contract_check`. | `test_rules/` com `FIRESTORE_EMULATOR_PORT=<livre> node run-tests.mjs` (nunca contra emulador em uso). Casos: ver 11.1. |
| 2 | `feat(social): modelo Friendship e visoes derivadas` | `friendship.dart`, `pairIdOf` (teste de equivalência com a regra: lista de pares), `viewFor`. | testes unitários puros. |
| 3 | `feat(social): repositorio de amizades` | métodos novos do `SocialRepository` (sem remover os antigos ainda), `firestore_paths`, fakes em `test/support/fake_repositories.dart`. | `fake_cloud_firestore`: pedido, cruzado (transação sequencial simulada), aceite duplo, recusa+lápide, remover, cancelar, query só do uid. |
| 4 | `feat(social): providers e controller de amizade` | providers da seção 8, `FriendshipController`, troca de `friendsProvider`, heurística de `sendIntention`, remoção de `addFriend`/`watchFriends` antigos. | `account_controller_test`, `providers_subscriptions_test` (continua sem reabrir stream com saldo mudando), novo `friendship_controller_test`. |
| 5 | `feat(profile): UI de pedidos de amizade` | `AccountScreen`, `FriendRequestsScreen`, rota, selo no shell, textos da seção 7 (**designer** antes). | widget tests mínimos: vazio, recebido (aceitar/recusar), enviado, erro com "Tentar de novo", diálogo de remoção. |
| 6 (RC) | `feat(regras): intencoes so entre amigos aceitos; remove friends` | `notifications` create exige `friendships/{pairId}.status == 'accepted'`; remove `match /friends`; `deleteAllFriends` -> `deleteAllFriendships` na cascata e no `DeleteAccountController`; textos da tela de exclusão. | `test_rules/` (casos 11.2), `delete_account_controller_test`, `account_deletion_data_test`. |
| 7 (opcional, RC) | `feat(regras): publicProfiles com limit(1) em list` | seção 6 (enumeração). Só se o usuário aprovar (Q do fim). | `test_rules/`: busca por hash passa; varredura sem limite negada. |
| 8 | `docs: etapa 12` | `overview.md`, `step11` (R10 resolvida), `release-checklist.md` (**ordem de implantação: regras do passo 1, cliente, regras do passo 6; limpar `friends` de teste**), `scripts/audit_users.md`, `docs/qa/etapa-12.md` (qa), CHANGELOG (writer). | links válidos. |

Ordem de implantação em produção: regras do passo 1 -> cliente -> regras do passo 6 (cliente antigo ficaria sem intenções após o 6; sem usuários ativos).

## 11. Testes

### 11.1 `test_rules/` (passo 1; reaproveitar helpers do arquivo atual, porta por `FIRESTORE_EMULATOR_PORT`)
1. Create: ok com dados válidos; negado a si mesmo, com `uids` desordenados ou id divergente, `requesterUid` de outro, `status != pending`, `requesterName` diferente do perfil, campo extra, `createdAt` sem `request.time`, sem perfil, para destino sem `users`, para destino **sem `publicProfiles`**, anônimo, terceiro que não está em `uids`.
2. Duplicata: segundo create do mesmo par (mesmo remetente) negado; **pedido cruzado**: B cria o par que A já criou, negado (id existe); B aceita ok.
3. Aceite: só o não-remetente; remetente aceitando o próprio pedido, terceiro e anônimo negados; alterar `uids`/`requesterUid`/`requesterName`/`createdAt` negado; `responderName` != nome do perfil negado; aceitar `accepted` ou `declined` negado; remetente ausente (`users` apagado) negado.
4. Recusa e lápide: não-remetente recusa; remetente **não** recria nem altera nem apaga a lápide; quem recusou apaga ("desbloquear") e o par pode ser criado de novo. Remoção de `accepted` por qualquer um dos dois; terceiro negado.
5. Cancelar: remetente apaga `pending`; destinatário não apaga `pending`; ninguém apaga `accepted` com perfil existente; **após apagar `users/{eu}`** o membro apaga qualquer relação sua (incluindo lápide em que fui recusado), terceiros não.
6. Leitura: `get` do par próprio ok (inclusive inexistente); `get` de par alheio negado; query `array-contains` com o próprio uid ok, com uid alheio, sem filtro e `collection group` negados; admin não lê.
7. Passo 6: intenção negada sem relação, com `pending`, com `declined`, após remoção; permitida com `accepted` nos dois sentidos (A->B e B->A); mantém as negações atuais (`fromName`, rótulo, destino excluído); `users/{uid}/friends` negado (create, read, delete).

### 11.2 Dart
- `fake_cloud_firestore` não avalia regras: testa só a lógica do repositório (transação, idempotência, query) e `deleteAllFriendships` (>400, retomada, offline `ServerOfflineException`, como `paged_delete`).
- Fakes: `FakeSocialRepository` com os métodos novos e falhas injetáveis (`unavailable`, `permission-denied`).
- Controller: cruzado vira amizade, cota de 20 pendentes (cliente), mensagens genéricas idênticas para busca vazia/desligada/lápide, `sendIntention` com amizade desfeita.
- Widget: estados da tela de pedidos (seção 7); sem testes de pixel.
- `rules_contract_test` cobre as constantes novas; `core_boundaries_test` sem exceção nova (controller não importa Flutter material; `profile` importa `social` já é permitido).

## 12. Custo (leituras e escritas)

- Listener `friendships`: 1 leitura por documento na primeira carga mais 1 por mudança; documentos = pares com qualquer histórico (amigos, pendentes, lápides): dezenas por usuário. Substitui o listener de `friends` (mesma ordem de grandeza).
- Pedido: 1 escrita + 3 leituras de regra (perfil próprio, `publicProfiles/{outro}`, `users/{outro}`) + 1 leitura da transação. Aceite: 1 escrita + 2 leituras de regra. Intenção: 1 escrita + 3 leituras de regra (as mesmas do atual).
- Exclusão de conta: `F` passa a ser nº de pares (inclui pedidos e lápides); mesma fórmula da etapa 11.
- Sem novo índice, sem collection group novo.

## 13. Riscos

| # | Risco | Tratamento |
|---|---|---|
| R-S1 | Sem teto de pedidos pendentes no servidor (Spark). | Mitigações 2.6 (alvo controla, lápide, e-mail exato, sem notificação) + App Check; teto real só com Functions. Aceito. |
| R-S2 | Enumeração de `publicProfiles` por cliente forjado. | Preexistente; passo 7 opcional e App Check. |
| R-S3 | `get`/`split('_')` e comparação de strings nas regras: erro de borda (uids com `_`) negaria tudo. | Uids do Auth não têm `_`; teste de regras com uids de 28 chars; falha é fechada (nega). |
| R-S4 | Lápide impede reconciliação quando o recusado exclui a conta e a recria. | Exclusão apaga a lápide (regra de delete) e o novo uid é outro par. |
| R-S5 | Leitura das regras (`get(users/{eu})`) falha se o perfil estiver ausente. | Falha fechada; fluxo legítimo sempre tem perfil. |
| R-S6 | Contas de teste com `friends` legado. | Inalcançáveis; limpar pelo console/auditoria. |
| R-S7 | Nome gravado na relação não acompanha futura edição de nome. | Hoje não há edição; se surgir, atualizar a relação junto (backlog). |
| R-S8 | Contorno da lápide refazendo o perfil: quem foi recusado apaga `users/{eu}`, a regra de exclusão de conta libera apagar a lápide, recria `users/{eu}` e `publicProfiles/{eu}` e pede de novo (caracterizado em `test_rules/`). | **Aceito:** equivale a criar outra conta. Mitigação real: App Check (etapa 13). Alternativa descartada: documento de bloqueio em `users/{B}/blocks`, que custa 1 leitura por pedido e não fecha o caso de outra conta. |

## 14. Revisão obrigatória (`reviewer-consultor`)

Passos **1, 6 e 7**: toda a seção 2.4, 2.5 e 6 (regras, dados de usuário, privacidade, exclusão de conta). Também uma passada sobre o passo 5 de UI apenas para checar que nenhuma tela grava fora do repositório.

## 15. Perguntas ao usuário (recomendação já adotada como padrão)

- **Q1.** Aceitar que o limite de pedidos pendentes seja **só no cliente** (20) e que o servidor limite apenas duplicata/lápide/pedido a si mesmo, por ser impossível contar documentos no Spark? **Recomendo sim** (teto real exige Blaze/Functions, decisão já adiada).
- **Q2.** "Aparecer na busca de amigos" desligado passa a **impedir receber novos pedidos**? **Recomendo sim** (é o controle do destinatário contra spam, sem custo).
- **Q3.** Recusar ou remover amizade **bloqueia o outro de pedir de novo** até quem recusou "desbloquear" (e o recusado vê "Pedido enviado", sem saber da recusa)? **Recomendo sim.**
- **Q4.** Zerar `friends` antigos sem migrar (sem usuários ativos)? **Recomendo sim.**
- **Q5.** Incluir o passo 7 opcional (`list` de `publicProfiles` com `limit(1)`)? **Recomendo sim**, ciente de que só encarece a varredura; a barreira real é App Check na etapa de release.

## 16. Desvios da implementação e decisões do usuário

Decisões do usuário (seguiram as recomendações): Q1 limite de 20 pedidos pendentes só no cliente; Q2 busca desligada impede receber pedidos; Q3 recusar/remover bloqueia até o desbloqueio e o recusado vê "Aguardando resposta"; Q4 `friends` zerado sem migrar; Q5 passo 7 incluído.

Desvios em relação ao desenho:

- **Regras de `update` separadas por transição.** Aceitar permite só `status`, `responderName`, `respondedAt`; recusar/remover permite só `status`, `declinedBy`, `respondedAt` (o esboço da seção 2.4 usava um único `hasOnly`, que deixaria quem recusa gravar um `responderName` livre). `responderName` ganhou o limite de 1 a 100 caracteres e o create exige `pid.split('_').size() == 2`.
- **Nome do destinatário em pedido enviado.** O documento não carrega o nome de quem recebeu o pedido (create só tem `requesterName`), então a lista "Enviados" lê `publicProfiles/{uid}` (`publicNameProvider`, "Viajante" se oculto ou excluído). O passo 7 mantém `get` por uid liberado.
- **"Pedidos enviados"** ficam só na tela `/account/requests` (a `AccountScreen` mostra o cartão "Pedidos de amizade (n)" que abre a tela), em vez de repetir a seção na conta.
- **Recusa silenciosa:** o pedido recusado pelo outro lado continua em "Enviados" como "Aguardando resposta" com o mesmo "Cancelar pedido" dos demais (cancelar a lápide só mostra "Pedido cancelado." e esconde o item na sessão, sem escrita; "Enviados (n)" inclui os recusados e por isso difere da cota) e um novo pedido ao mesmo e-mail responde "Você já enviou um pedido a essa pessoa."; só a lápide de amizade removida (ou minha) gera a mensagem genérica. Pedidos recusados não contam na cota de 20.
- **Pedido cruzado simultâneo:** garantido pela transação do Firestore (reexecução no cliente); `fake_cloud_firestore` não reproduz a contenção, então o teste cobre o caso sequencial e a lógica dos resultados.
- **Designer:** a tela seguiu o desenho da seção 7 sem documento próprio em `docs/design/`.
- **Limites das regras verificados no emulador:** um batch de 400 deletes de `friendships` sem perfil (página da cascata, 1 `exists(users/{eu})` por delete) passa, então o limite de chamadas de acesso por requisição não bloqueia a cascata. Teste em `test_rules/`.
- **Sem push:** o pedido só aparece no selo do ícone Perfil e na tela de pedidos.
