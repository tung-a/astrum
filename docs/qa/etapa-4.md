# QA da etapa 4: quebra de `UserRepository` em repositórios por agregado

- Data: 2026-11-14
- Branch: `feature/flutter-migration` (diff não commitado)
- Base: `docs/architecture/step4-repositories.md` e seção "Itens abertos da etapa 4" de `docs/plans/reestruturacao-etapas-1-a-3.md`
- Escopo: somente testes e relatório. Nenhum arquivo de `lib/` foi alterado. `firestore.rules` e `test_rules/` não foram alterados.

## 1. Resultado resumido

| Verificação | Resultado |
|---|---|
| `flutter analyze` | No issues found (0 problemas) |
| `flutter test` (suíte completa) | 82 passaram, 0 falharam (73 existentes + 9 novos em `test/qa_etapa_4_test.dart`) |
| `test_rules`: `npm ci` | OK (111 pacotes). A auditoria do npm reporta 12 vulnerabilidades (6 moderadas, 6 altas); não tratadas nesta etapa |
| `test_rules`: `npm test` (comando literal) | NÃO EXECUTADO. A porta 8080 está ocupada por `java.exe` (PID 16132), que não foi iniciado por esta sessão. Não foi encerrado. Além disso, o `beforeEach` chama `clearFirestore()`, então rodar contra esse emulador apagaria os dados dele |
| `test_rules`: mesma suíte em porta 8181 (cópia fora do repositório) | 37 de 37 passaram |
| `git diff -- firestore.rules test_rules/` | vazio (regras e testes de regras intocados) |
| `grep` de `UserRepository` / `userRepositoryProvider` / `user_repository` em `lib/` e `test/` | zero ocorrências (restam apenas referências em documentos e no CHANGELOG) |

Como a suíte de regras foi executada: copiei `test_rules/firestore.rules.test.mjs` e `package.json` para `C:\Users\aarth\AppData\Local\Temp\claude\1b125e1c40d4ebb5\55b7f6bb-073f-4539-a354-7d0684338b50\scratchpad\rules-run\`, troquei apenas a porta 8080 por 8181 e o caminho das regras por caminho absoluto, e rodei `firebase --config <cópia do firebase.json> emulators:exec --only firestore --project demo-astrum "node --test firestore.rules.test.mjs"` a partir dessa pasta. O arquivo versionado não foi alterado. Para o comando literal, falta apenas liberar a porta 8080.

## 2. Equivalência do código movido

Comparei com `git show HEAD:lib/services/user_repository.dart`:

- `purchaseItem`: corpo da transação idêntico (leitura do perfil e de `shop_items`, `resolvePrice`, `computePurchase`, mesmo `tx.update`). O `.then` que sincroniza só quando `equipField != null && touches([equipField])` é idêntico.
- `dailyCheckIn`: corpo idêntico (`computeCheckIn`, mesmo `tx.update` com `wallet.stardust` e `dailyCheckIn`).
- `syncFromUser` (antigo `syncPublicProfile`): mesma leitura, mesmo fallback de avatar (`defaultProfilePictureId`) e mesmo fallback de e-mail (`auth.currentUser`).
- `updateFields` (substituído por escritas tipadas na etapa 5): única mudança é a guarda `ArgumentError` (desvio 4, intencional). Gravação e sync pós-gravação mantidos.
- `watchProfile`: assinatura mudou por causa da etapa 3 (desvio 2), já documentado.
- Divergência esperada e documentada: `AdminRepository.rebuildPublicProfiles` não usa `PublicProfileSync` (desvio 1). Coberta pelo teste de desvio 1 abaixo.

## 3. Mapa de critérios e riscos para testes

Legenda: PASSOU = teste existente verde; NOVO = teste acrescentado nesta etapa; LACUNA = sem teste automatizado (ver seção 5).

### 3.1 Restrições (seção 0) e Repositórios (seção 1)

| Item do documento | Teste | Status |
|---|---|---|
| Compra paga: debita, acrescenta ao fim do inventário e equipa | `economy_repository_test.dart`: "sucesso: debita, acrescenta ao fim do inventario e equipa" | PASSOU |
| Compra sem `equipField` não altera `equipped` nem `publicProfiles` | `economy_repository_test.dart`: "sem equipField nao altera equipped nem publicProfiles" | PASSOU |
| Equipar foto de perfil sincroniza `publicProfiles` (avatar, nome, emailHash) | `economy_repository_test.dart`: "equipar foto de perfil sincroniza publicProfiles" | PASSOU |
| Equipar skin não sincroniza `publicProfiles` | `economy_repository_test.dart`: "equipar skin nao sincroniza publicProfiles" | PASSOU |
| Saldo insuficiente: lança e não grava | `economy_repository_test.dart`: "saldo insuficiente lanca e nao grava" | PASSOU |
| Item inativo, inexistente, já possuído: lançam e não cobram | `economy_repository_test.dart`: três testes (NotPurchasable, NotPurchasable, AlreadyOwned) | PASSOU |
| Perfil inexistente lança `StateError` (compra e check-in) | `economy_repository_test.dart`: dois testes | PASSOU |
| Compra gratuita (preço 0, item novo): sem débito, item acrescentado e equipado | `qa_etapa_4_test.dart`: "compra gratuita (preco 0, item novo) nao debita, acrescenta e equipa" | NOVO, PASSOU |
| Check-in: credita +25 e grava a data | `economy_repository_test.dart`: "sucesso: credita e grava a data" | PASSOU |
| Check-in repetido no mesmo dia: lança e não credita de novo | `economy_repository_test.dart`: "repetido no mesmo dia lanca e nao credita de novo" | PASSOU |
| Check-in no dia seguinte credita de novo | `economy_repository_test.dart`: "dia seguinte credita novamente" | PASSOU |
| `ProfileRepository.createProfile` (saldo 500, role user, inventário padrão, pfp zodiacal, publicProfiles) | `qa_etapa_4_test.dart`: "createProfile: saldo 500, inventario padrao, pfp zodiacal e publicProfiles" | NOVO, PASSOU (antes sem teste) |
| `ProfileRepository.updateFields` sincroniza quando toca nome/avatar | `repositories_firestore_test.dart`: "sincroniza publicProfiles quando toca nome/avatar" | PASSOU |
| `updateFields` não sincroniza quando não toca perfil público | `repositories_firestore_test.dart`: "nao sincroniza quando nao toca perfil publico" | PASSOU |
| `updateFields` lança `ArgumentError` para `wallet*`, `inventory*`, `dailyCheckIn*`, `role*` (desvio 4) | `repositories_firestore_test.dart`: "rejeita chaves protegidas sem gravar" (ver fragilidade F1) | PASSOU, com ressalva |
| `EventsRepository`: add, watch ordenado e delete | `repositories_firestore_test.dart`: "add, watch (ordenado) e delete" | PASSOU |
| `SocialRepository`: `findUserByEmail` (inclusive e-mail vazio) | `repositories_firestore_test.dart`: "findUserByEmail usa publicProfiles" | PASSOU |
| `SocialRepository`: `addFriend` e `watchFriends` | `repositories_firestore_test.dart`: "addFriend e watchFriends" | PASSOU |
| `SocialRepository`: `sendIntention`, `watchUnreadIntention`, `markNotificationRead` | `repositories_firestore_test.dart`: "sendIntention, watchUnreadIntention e markNotificationRead" | PASSOU |
| `CatalogRepository.watchShopCatalog` mapeia `shop_items` pelo id | `qa_etapa_4_test.dart`: "CatalogRepository.watchShopCatalog mapeia shop_items pelo id" | NOVO, PASSOU (antes sem teste) |
| `AdminRepository.listUsers` (limite de 80, lê e-mail e nome) | `qa_etapa_4_test.dart`: "AdminRepository.listUsers limita a 80 usuarios..." | NOVO, PASSOU (antes sem teste) |
| `AdminRepository.rebuildPublicProfiles` conta só os perfis gravados | `repositories_firestore_test.dart`: "conta so os perfis gravados e pula os que nao geram perfil" | PASSOU (ver M1 na seção 4) |
| `PublicProfileSync.touches` e `write` | cobertos indiretamente pelos testes de `updateFields` e de equipar foto | PASSOU |
| Helper `firestore_paths.dart` (só strings) | sem teste direto; exercitado por todos os testes acima | PASSOU (indireto) |

### 3.2 Desvios documentados

| Desvio | Teste | Status |
|---|---|---|
| 1. `syncFromUser` usa e-mail do `auth` quando o perfil não tem e-mail; `AdminRepository` não usa (pula o usuário) | `qa_etapa_4_test.dart`: "desvio 1: syncFromUser usa e-mail do auth ..." | NOVO, PASSOU |
| 2. `watchProfile(User)` com assinatura da etapa 3 | `firebase_providers_test.dart` (repositório real, `ProfileRepository` e `profileProvider`) e `providers_subscriptions_test.dart` (fake) | PASSOU |
| 3. `fake_cloud_firestore` não aplica regras nem contenção de transação | limitação declarada nos cabeçalhos de `economy_repository_test.dart`; regras cobertas em `test_rules/` (seção 1) | PASSOU, com limitação |
| 4. Guarda `ArgumentError` em `updateFields` | `repositories_firestore_test.dart` (ver F1) | PASSOU, com ressalva |

### 3.3 Interfaces e providers (seções 2 e 3)

| Item | Teste | Status |
|---|---|---|
| `EconomyRepository` é interface e a implementação atual é `FirestoreEconomyRepository` | os testes de `economy_repository_test.dart` instanciam a implementação concreta | PASSOU (parcial) |
| Fake de economia que registra chamadas para testar a UI pela interface (seção 6) | não criado: as telas não podem ser montadas sem `FirebaseFirestore.instance` | LACUNA (L4) |
| Providers de repositório não são recriados a cada mudança de perfil (risco 3) | `providers_subscriptions_test.dart` (contagem de assinaturas, com fakes) e NOVO "eventsRepositoryProvider e economyRepositoryProvider mantem a instancia ao trocar de usuario" em `qa_etapa_4_test.dart` (repositórios reais) | PASSOU |
| `profileProvider` e `routerProfileKeyProvider` com troca de usuário e de admin | `providers_subscriptions_test.dart`, `router_test.dart`, `qa_etapas_1_a_3_test.dart` | PASSOU |

### 3.4 Mapa de telas (seção 4)

| Item | Teste | Status |
|---|---|---|
| Cada tela usa o provider indicado no mapa | sem teste de widget (telas usam `FirebaseFirestore.instance`). Conferido por `grep` nesta etapa: `cosmos`/`astral`/`account`/`inventory`/`shop` usam `profileRepositoryProvider`; `cosmos`/`shop` usam `economyRepositoryProvider`; `account`/`cosmic_scaffold` usam `socialRepositoryProvider`; `rituals` usa `eventsRepositoryProvider`; `admin` usa `adminRepositoryProvider`; `welcome` usa `profileRepositoryProvider.createProfile` | LACUNA (L1); verificado só por grep |

### 3.5 Riscos (seção 7)

| Risco | Teste | Status |
|---|---|---|
| 1. Saldo e inventário (alto) | lógica e transações: `economy_repository_test.dart`; regras: `test_rules/` (37 testes, 37 passaram na porta 8181); fluxo do app: checklist manual (seção 8) | PASSOU, com lacunas L2, L3, L5 |
| 2. Perfil público esquecido após compra (médio) | "equipar foto de perfil sincroniza publicProfiles" e "equipar skin nao sincroniza" (`economy_repository_test.dart`); checklist manual item 5 | PASSOU, com lacuna L5 |
| 3. Re-assinatura de streams (médio) | `providers_subscriptions_test.dart` e NOVO de instância | PASSOU |
| 4. Escape hatch de `updateFields` (médio) | `repositories_firestore_test.dart` (ver F1) | PASSOU, com ressalva |
| 5. Fakes frágeis (baixo) | não se aplica nesta etapa | n/a |
| 6. `createProfile` sem rollback (baixo, etapa 6) | NOVO `createProfile` (conteúdo gravado). Rollback não existe e está fora do escopo | PASSOU (conteúdo); rollback fora do escopo |
| 7. Inicialização lazy dos providers (baixo) | não reexecutado nesta etapa; coberto na etapa 1 (`qa_etapas_1_a_3_test.dart`, `widget_test.dart`) | não reexecutado especificamente |
| 8. Nome `watchShopCatalog` | n/a (renomeação prevista para a etapa 7) | n/a |

## 4. Itens abertos da etapa 4 (decisões do usuário)

### M1. `rebuildPublicProfiles` falha com permission-denied para terceiros

- Evidência: em `test_rules/firestore.rules.test.mjs`, o teste 35 ("publicProfiles: dono cria e atualiza; escrever o de outro negado") passa, ou seja, `firestore.rules` nega a escrita em `publicProfiles/{outroUid}`. `AdminRepository.rebuildPublicProfiles` (`lib/services/admin_repository.dart`, linha 31) grava `publicDoc(d.id)` para todos os usuários.
- Teste no repositório: `repositories_firestore_test.dart` documenta a limitação no comentário (o fake não aplica regras), e o teste de contagem passa.
- Status: confirmado por análise das regras e pelo teste 35. NÃO reproduzido no app.
- Passos para reproduzir no app: entrar com conta admin; abrir a tela de admin; acionar a ação de reconstruir perfis públicos; resultado esperado segundo as regras: `permission-denied` ao gravar o perfil de outro usuário.

### M3. LGPD: `preferences.publicProfile=false` é ignorado

- Caracterização nos testes novos (`qa_etapa_4_test.dart`):
  - "rebuildPublicProfiles grava perfil mesmo com preferences.publicProfile=false": o admin grava o perfil de quem desligou a opção.
  - "updateFields com preferences.publicProfile=false nao remove o publicProfiles existente": desligar a opção não remove o perfil público já gravado.
- Regras: teste 37 (`delete` do próprio `publicProfiles` negado) confirma que não há exclusão pelo cliente. Esse é o ponto a ajustar na etapa 11.
- Hash de e-mail sem sal: o teste 34 confirma que só usuário logado consulta por `emailHash`. A enumeração por hash conhecido é uma decisão de desenho, não coberta por teste de falha.
- Status: comportamento atual confirmado nos testes. Não corrigido (fora do escopo de QA).

### B1. Falha do sync após a compra é propagada como erro

- Caracterização: "B1 (caracterizacao): falha do sync apos compra com foto propaga erro, mas a compra ja esta gravada" (`qa_etapa_4_test.dart`). Com um sync que falha, `purchaseItem` lança `StateError`, e saldo (90) e equipado (`pfp_a`) já estão gravados.
- Na UI (`lib/screens/shop/shop_screen.dart`, `_selectItem`): o `catch (_)` mostra "Não foi possível concluir. Tente novamente.", mesmo com a compra efetivada. Uma nova tentativa cai no ramo de equipar (item já possuído), então não há cobrança duplicada, mas o usuário vê erro falso.
- Status: confirmado no repositório. Não reproduzido no app (exigiria falha de rede entre a transação e o sync).

## 5. Lacunas

- L1. Telas (shop, cosmos, account, admin, inventory, rituals, welcome, cosmic_scaffold) sem teste de widget. Motivo: usam `FirebaseFirestore.instance` diretamente. Mitigação: checklist manual (seção 8).
- L2. Contenção e retentativa de transação não são simuladas pelo `fake_cloud_firestore`. Dois clientes comprando ao mesmo tempo não são testados.
- L3. Regras do Firestore não são aplicadas ao fluxo de compra e check-in feito pelo app; estão em `test_rules/` (37 testes, verificados pela cópia na porta 8181). A execução literal de `npm test` ainda está pendente (porta 8080).
- L4. Fake de `EconomyRepository` para testar telas pela interface (seção 6 do documento) não foi criado (depende de montar as telas).
- L5. Comportamento da UI quando o sync falha após a compra (B1): só o repositório foi caracterizado.
- L6. Itens da seção 4 do documento (mapa de telas) conferidos por `grep`, não por teste automatizado.
- L7. Risco 7 (inicialização lazy) não reexecutado nesta etapa.
- L8. Exclusão de conta e `publicProfile` (M3 completo): etapa 11, fora do escopo.

## 6. Fragilidades e observações (não são falhas de produção)

- F1. `test/repositories_firestore_test.dart`, teste "rejeita chaves protegidas sem gravar" (linhas 125 a 141): as chamadas `expect(() => repo.updateFields(...), throwsArgumentError)` não são aguardadas (`await`). O teste passa porque o matcher 0.12.20 trata funções que retornam Future, mas uma falha dessas asserções poderia ser reportada fora deste teste. Recomendação: `await expectLater(repo.updateFields(...), throwsArgumentError)`. Não alterado, pois é um teste existente.
- F2. A guarda de `updateFields` (`lib/services/profile_repository.dart`, `_blockedPrefixes`) usa `startsWith` sem ponto. Ela também bloqueia chaves como `roles` ou `walletX`. Hoje não há campo legítimo com esses prefixos. Registrado apenas como observação.
- F3. `CHANGELOG.md` linha 25 ainda descreve `UserRepository` no presente. É uma entrada da etapa 3. Pode ser revisada pelo `writer` na próxima atualização.
- F4. Ambiente: `npm audit` reporta 12 vulnerabilidades em `test_rules/` (6 moderadas, 6 altas). Não tratado nesta etapa.

## 7. Testes novos (`test/qa_etapa_4_test.dart`, 9 testes)

1. compra gratuita (preço 0, item novo) não debita, acrescenta e equipa
2. createProfile: saldo 500, inventário padrão, pfp zodiacal e publicProfiles
3. B1 (caracterização): falha do sync após compra propaga erro, mas a compra já está gravada
4. M3 (caracterização): rebuildPublicProfiles grava perfil mesmo com `preferences.publicProfile=false`
5. M3 (caracterização): updateFields com `publicProfile=false` não remove o `publicProfiles` existente
6. desvio 1: syncFromUser usa e-mail do auth; AdminRepository pula o usuário sem e-mail
7. AdminRepository.listUsers limita a 80 usuários e lê e-mail e nome
8. CatalogRepository.watchShopCatalog mapeia `shop_items` pelo id
9. risco 3: `eventsRepositoryProvider` e `economyRepositoryProvider` mantêm a instância ao trocar de usuário

Os testes de caracterização (3, 4 e 5) descrevem o comportamento atual dos itens abertos. Quando a decisão do usuário for implementada, eles devem ser atualizados junto com a correção.

## 8. Checklist de verificação manual (app, emulador ou projeto de teste)

Use uma conta de teste. Confira os valores também no console do Firestore (`users/{uid}`, `publicProfiles/{uid}`).

1. Compra paga: na loja, comprar um item pago com saldo suficiente. Esperado: saldo diminui exatamente pelo preço; item aparece ao final do inventário; equipado não muda.
2. Compra gratuita: comprar um item de preço 0. Esperado: saldo não muda; item entra no inventário. Com saldo insuficiente para um item pago: mensagem de saldo insuficiente e nada gravado.
3. Equipar após comprar: comprar uma skin e um fundo, equipar cada um na mesma compra. Esperado: aparecem equipados na hora e continuam após fechar e reabrir o app.
4. Check-in duas vezes: fazer o check-in no Cosmos. Esperado: +25 na primeira vez. Na segunda, no mesmo dia, mensagem de já feito e saldo sem mudança, mesmo após recarregar o app.
5. Busca de amigo com avatar atualizado: usuário A equipa uma foto de perfil nova (comprada ou já possuída). Usuário B busca o e-mail de A na tela de conta. Esperado: o avatar mostrado é o novo. No console, `publicProfiles/A.avatar` deve coincidir com `users/A.equipped.profilePicture`.
6. Troca de usuário: fazer logout de A e login de B no mesmo aparelho. Esperado: saldo, inventário, eventos e amigos são de B; nada de A aparece depois do login. Se A for admin, B não deve acessar `/admin`.
7. Falha esperada M1: como admin, acionar a reconstrução de perfis públicos. Esperado segundo as regras: `permission-denied` ao gravar perfis de outros usuários. Registrar o resultado observado.
8. Caso M3: com `preferences.publicProfile` desligado, verificar se `publicProfiles/{uid}` continua existindo. Esperado pelo comportamento atual: continua (confirma o item aberto).
9. Caso B1 (se for possível simular falha de rede logo após a compra com foto de perfil): esperado atual: a mensagem de erro aparece, mas saldo e item estão gravados.
10. Quando a porta 8080 estiver livre: `cd test_rules && npm test`. Esperado: 37 testes passam.

## 9. Comandos executados

- `flutter analyze`: No issues found
- `flutter test`: All tests passed (82)
- `flutter test test/qa_etapa_4_test.dart`: 9 passaram
- `npm ci` em `test_rules/`: OK
- `npm test` literal: não executado (porta 8080 ocupada por PID 16132, `java.exe`, que não foi iniciado nesta sessão e não foi encerrado)
- Suíte de regras na cópia com porta 8181: 37 passaram
