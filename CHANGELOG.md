# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). A versão corresponde ao campo `version` do `pubspec.yaml` (atualmente `2.0.0+1`).

## [Não lançado]

### Adicionado (etapa 12: aceite de amizade)

- Amizade com aceite: "Enviar pedido" por e-mail (confirmação com nome e avatar), tela "Pedidos de amizade" (`/account/requests`) com recebidos (Aceitar/Recusar), enviados (Aguardando resposta, Cancelar pedido) e recusados e removidos (Desbloquear); "Remover amizade" no cartão do amigo; selo com o número de pedidos recebidos no ícone Perfil. Pedido cruzado vira amizade na hora. Sem notificação push.
- Regras do Firestore: `friendships/{menorUid_maiorUid}` (um documento por par; só o destinatário aceita ou recusa; recusa e remoção viram lápide até quem recusou desbloquear; exclusão de conta apaga qualquer relação). Intenções só entre amigos aceitos. `publicProfiles` com `get` por uid e `list` só com `limit(1)`. 87 testes de regras (inclui a caracterização do contorno da lápide, risco aceito R-S8). **Implantar regras e cliente na ordem do `docs/release-checklist.md` (seção 6c).**
- Quem desliga "Aparecer na busca de amigos" deixa de receber pedidos novos.

### Alterado (etapa 12)

- A subcoleção `users/{uid}/friends` foi removida (sem migração; não há usuários ativos). A lista de amigos vem de `friendships`. Exclusão de conta apaga amizades e pedidos (enviados e recebidos), o que fecha o resíduo R10 da etapa 11 (nome copiado na lista de terceiros); o texto da tela de exclusão foi atualizado.
- Intenção enviada a uma amizade desfeita avisa "Esta amizade não existe mais.".
- Pedidos enviados são todos iguais na interface ("Aguardando resposta" e "Cancelar pedido"); a recusa é silenciosa só na interface. A busca avisa quando o bloqueio é do próprio usuário. Nomes longos aparecem em uma linha com reticências.
- Limite de 20 pedidos pendentes só no cliente (o Spark não conta documentos; risco R-S1; teto real com App Check ou Cloud Functions).

### Adicionado (etapa 11: exclusão de dados e de conta)

- Exclusão de conta (Perfil > "Excluir minha conta"): reautenticação por senha, diálogo final e cascata no cliente (perfil, conversas, eventos, amigos, notificações, intenções enviadas, registros de uso e usuário Auth), idempotente e retomável ("Tentar de novo"). Conta sem perfil cai na mesma tela.
- Oráculo: menu "Apagar esta conversa" e "Apagar todo o histórico"; aviso de privacidade atualizado (sem "em breve").
- "Esqueci minha senha" na tela de login; aviso "Sua conta foi excluída." depois da exclusão.
- Interruptor "Aparecer na busca de amigos" e avatar zodiacal escondido no perfil público quando "Exibir meu signo" está desligado.
- Regras do Firestore: delete do dono em `users` e `publicProfiles`, `exists(users/{uid})` na criação de conversa e de intenção, collection group de intenções enviadas (com índice) e leitura/exclusão dos próprios `analytics_events`. **Implantar índice e regras antes do cliente.**
- Android: `data_extraction_rules.xml`; iOS: cache do Firestore fora do backup (validar em Mac).

### Corrigido (revisão da etapa 11)

- Exclusão de conta: o estado guarda o uid que iniciou a exclusão; trocar de usuário na mesma sessão nunca pula a cascata.
- Intenção enviada a conta que parece excluída só avisa ("Esta conta não está mais disponível."), sem remover o amigo da lista.
- Android: `data_extraction_rules.xml` com `path="."` nos excludes. `deleteAccount` só trata `user-not-found` como conta já excluída. Limpeza do cache na partida com prazo de 3 s; a flag de limpeza é gravada antes de apagar as preferências.
- Oráculo: apagar conversa/histórico é recusado enquanto há resposta em andamento; mensagens de erro da exclusão não dizem que algo foi apagado antes da cascata; interruptor "Aparecer na busca de amigos" avisa e reverte se a gravação falhar.
- Regras do Firestore: criar `events` e `friends` exige o perfil do usuário; criar `conversations` usa `request.auth.uid` na checagem do perfil, com testes de perfil ausente ampliados.
- Exclusão de conta: se a limpeza do cache estourar o prazo e concluir depois, a flag de limpeza é removida (não limpa de novo na partida seguinte); com uid nulo o estado do usuário anterior é descartado; conta já excluída em outro aparelho (`user-not-found` na reautenticação) encerra a sessão, leva ao login e mostra "Esta conta já foi excluída.".
- Dívida registrada: tolerância de ±1 dia do check-in (teto de 575 por criação de conta), em `docs/decisions/2026-11-checkin-tolerancia.md`.

### Removido (etapa 11)

- `rebuildPublicProfiles` e o botão "Recriar perfis públicos" do painel de admin.

### Removido

- Histórico local do oráculo em shared_preferences (`LegacyChatStore`) e o migrador: não há usuários ativos, então não há migração.

### Corrigido

- Oráculo (revisão da etapa 10): aviso de privacidade sem prometer exclusão inexistente ("até serem apagadas", "em breve você poderá apagá-las no app"); `android:allowBackup="false"` (cache e prefs fora do backup do Google Drive); chaves antigas `astrum.chat.<uid>` apagadas do aparelho ao abrir o oráculo; falha ao carregar o histórico mostra "Não foi possível carregar o histórico." com "Tentar de novo"; o campo só é limpo quando o envio é aceito (chips não apagam o texto digitado; troca de usuário limpa o rascunho); prompt pendente também é consumido com o chat já carregado; `limitReached` calculado no controller e envio desabilitado na conversa cheia; a 2ª mensagem rápida não recria a conversa; removidos `waitForSync` e `remoteMessageCount(fromServer)`, sem uso.
- Release: exclusão de conversa/histórico e de conta passa a ser item bloqueante do `docs/release-checklist.md` (LGPD art. 18, VI).
- Oráculo: texto digitado antes de o histórico carregar não é mais apagado sem ser enviado; trocar de usuário reinicia o chat e ignora resposta pendente do usuário anterior.

### Adicionado

- Histórico do oráculo no Firestore (`users/{uid}/conversations`), sincronizado entre aparelhos, em `southamerica-east1`: conversas da mais recente para a mais antiga, abre na mais recente, limite de 500 mensagens por conversa ("Esta conversa atingiu o limite. Inicie uma nova conversa."), guardado até o usuário apagar. Aviso informativo único no primeiro uso do oráculo.
- CI no GitHub Actions (`.github/workflows/ci.yml`), em push e PR para `main` e `feature/flutter-migration`: `flutter analyze` e `flutter test` no Ubuntu, e os testes das regras do Firestore no emulador.
- Workflow manual de build (`.github/workflows/build.yml`): APK debug para Android e build iOS sem assinatura. O build de iOS também roda semanalmente. Não usa segredos.
- Providers de infraestrutura `firebaseAuthProvider` e `firestoreProvider` (`lib/core/firebase/`), que permitem trocar as instâncias do Firebase em testes.
- `currentUidProvider`, `routerProfileKeyProvider` e a função `decideRedirect` em `lib/app_router.dart`, para que a decisão de redirect seja testável.
- Testes novos: widget de boot sem configuração do Firebase, redirect do router, providers de assinatura (contagem de listeners por uid), providers de infraestrutura, casos de QA das etapas 1 a 3, testes dos repositórios com `fake_cloud_firestore` (`test/repositories_firestore_test.dart`) e testes das transações de compra e check-in (`test/economy_repository_test.dart`).
- Dependência de desenvolvimento `fake_cloud_firestore`, para testar repositórios sem Firestore real.
- Regras do Firestore com testes em `test_rules/`, cobrindo check-in e compra da loja.
- Catálogo da loja lido de `shop_items` no Firestore, com preço validado pelas regras.
- Perfil público mínimo (`publicProfiles`) para busca de amigo.
- Escritas tipadas em `ProfileRepository`: `setNotificationsEnabled`, `setShowSign`, `equip(uid, EquipSlot, itemId)`, `saveAstralMap`, `saveDailyHoroscope` e `saveDailyTarot`. As telas deixam de montar caminhos de campo do Firestore.
- Enum `EquipSlot` (`lib/models/equip_slot.dart`) para skin, fundo e avatar; `ItemType.slot` liga o tipo do item ao slot.
- Testes novos: `test/equip_slot_test.dart` e testes de cada escrita tipada em `test/repositories_firestore_test.dart`, incluindo a verificação de que nenhum método do perfil altera `wallet`, `inventory`, `role` ou `dailyCheckIn`.
- `AuthRepository` (`lib/services/auth_repository.dart`) para entrar, criar conta e sair. Os erros chegam às telas como `AuthException`, com código tipado (`lib/models/auth_exception.dart`); as telas não recebem mais exceções do Firebase.
- Cadastro com desfazimento: se o perfil não puder ser criado depois da conta, a conta recém-criada é apagada e a sessão é encerrada. Se o aparelho não conseguir apagar a conta, a mensagem pede nova tentativa e, se persistir, contato com o suporte.
- Limite de tempo de 20 s para criar o perfil no cadastro. Ao estourar, a conta não é apagada (a gravação pode ainda ser concluída); o usuário é orientado a entrar com e-mail e senha em instantes.
- `SignUpController` (`lib/providers/sign_up_provider.dart`) guarda o rascunho do cadastro só em memória entre as telas de dados e de boas-vindas. A senha deixa de trafegar pela navegação.
- Limites de tamanho nos campos do cadastro (`SignUpLimits` e `signUpLengthError` em `lib/models/sign_up_data.dart`), com `maxLength` nas telas e checagem antes do envio.
- `AdminRepository` ganha `watchAnalyticsEvents`, `seedCrystals`, `publishCatalog`, `planCatalogPublish` (regra de publicação do catálogo, pura), `summarizeAnalytics` (contagem de eventos, pura) e `AdminOperationException`.
- Testes novos: `test/auth_models_test.dart`, `test/auth_repository_test.dart`, `test/sign_up_test.dart` e `test/admin_test.dart`, além de testes do `createProfile` em lote em `test/repositories_firestore_test.dart`. Os fakes de `FirebaseAuth` e de repositórios em `test/support/` foram ampliados.
- Contrato único com as regras do Firestore em `lib/core/firebase/rules_contract.dart`: recompensa de check-in, saldo inicial, itens padrão, prefixo do avatar zodiacal, intenções, tipos de catálogo, papéis, id anônimo e limites de campo. Cada constante traz a regra correspondente em comentário.
- `test/rules_contract_test.dart` lê `firestore.rules` e falha se um valor do contrato divergir das regras (com casos de mutação por constante) ou se um padrão da regra sumir. Não há workflow novo: roda no `flutter test`.
- Testes de caracterização do seed do catálogo, dos caminhos de avatar, dos defaults de `AppUser`, do payload de `createProfile` e do check-in (`test/characterization_etapa_7_test.dart`), e teste de fronteira de imports de `lib/core` (`test/core_boundaries_test.dart`).

### Corrigido

- Oráculo: `loading` não fica mais preso se a resposta ou a gravação falhar (a conversa recebe "Não foi possível obter a resposta. Tente novamente."); a resposta vai para a conversa que originou o envio, mesmo se o usuário trocar de conversa; enviar antes de o histórico carregar é ignorado (antes gerava `RangeError`).

### Alterado

- Etapa 9, controllers (refatoração, sem mudança de regra, texto de tela ou dependência): `AstralController`, `RitualsController`, `ShopController`, `CosmosController` (horóscopo, tarô e check-in), `ChatController` e `AccountController` assumem a lógica das telas. `ProfileRepository` virou interface (`FirestoreProfileRepository`), `ChatRepository` foi criado, e `core/clock/` traz `clockProvider` e `dayKey`. `test/core_boundaries_test.dart` passa a tratar `*_controller.dart` como camada de providers (sem `material`/`widgets`/`cupertino`). `ShopController.equip` devolve `bool`. Detalhes em `docs/architecture/step9-controllers.md`.
- `AccountController.addFriendByEmail` adiciona o amigo mesmo se o usuário sair da tela durante a busca (desvio aceito).

- Etapa 8, estrutura feature-first leve (refatoração pura, sem mudança de comportamento, regra, texto de tela ou dependência): `lib/` passa a ter `app/`, `core/`, `features/<feature>/{domain,data,presentation}/`, `shared/` e `main.dart`. O `app_providers.dart` monolítico foi dividido por feature, os imports de `lib/` usam só `package:astrum/` e 9 testes foram espelhados em `test/features/`. Detalhes e desvios em `docs/architecture/step8-feature-first.md`.
- `test/core_boundaries_test.dart` verifica as fronteiras: camadas (core < domain < data < providers < shared < telas < app), ausência de ciclos e de import relativo em `lib/`, camada definida para todo arquivo, camadas puras sem Flutter (inclusive transitivamente) e `*_providers.dart` sem `material`/`widgets`.
- Lint `directives_ordering` ativada em `analysis_options.yaml`; imports de `lib/` e `test/` ordenados.
- `UserRepository` foi dividido em repositórios por agregado em `lib/services/`: `ProfileRepository` (perfil do usuário logado), `EventsRepository` (rituais), `SocialRepository` (amigos, busca e intenções), `CatalogRepository` (catálogo da loja), `AdminRepository` (listagem de usuários e reconstrução de perfis públicos) e `EconomyRepository`, uma interface com implementação `FirestoreEconomyRepository`, que concentra todo crédito e débito de saldo (compra e check-in). O comportamento foi preservado: os métodos foram movidos sem mudar gravações, ordem ou exceções.
- `PublicProfileSync` centraliza a gravação de `publicProfiles` usada pelo perfil e pela economia.
- Providers por repositório (`profileRepositoryProvider`, `eventsRepositoryProvider`, `socialRepositoryProvider`, `catalogRepositoryProvider`, `economyRepositoryProvider`, `adminRepositoryProvider`) substituem `userRepositoryProvider` nas telas e nos providers derivados.
- `FirebaseFirestore` é usado por construtor em cada repositório, com caminhos de documentos centralizados em `lib/core/firebase/firestore_paths.dart`.
- `eventsProvider`, `friendsProvider` e `intentionProvider` observam apenas o uid (via `select`). Mudanças de saldo, horóscopo ou item equipado não reabrem mais os listeners do Firestore, o que reduz leituras. `intentionProvider` reabre só quando `notificationsEnabled` muda.
- O router reavalia o redirect apenas quando muda `isAdmin` ou o estado de carregamento do perfil, e não a cada atualização de `users/{uid}`.
- O app usa uma única assinatura de `authStateChanges`, compartilhada pelo router e pelo perfil.
- `AnalyticsService` recebe as instâncias do Firebase por construtor, fornecidas pelos providers.
- `test/widget_test.dart` foi ampliado.
- As telas de conta, mapa astral, cosmos, inventário e loja usam os métodos tipados de `ProfileRepository`. As chaves gravadas, a ordem das escritas e as exceções não mudaram.
- `purchaseItem` recebe `EquipSlot? equipSlot` no lugar de `String? equipField`; a interface `EconomyRepository` deixa de expor caminho de campo.
- A sincronização de `publicProfiles` é decidida por tipo de escrita. Só equipar o avatar (direto ou na compra) sincroniza. Continua em duas gravações não atômicas; a atomicidade (opção B) segue pendente de decisão.
- Nenhum método público de `ProfileRepository` aceita `Map` ou caminho de campo, então `wallet`, `inventory`, `role` e `dailyCheckIn` não são alcançáveis por ele.
- As telas de login, cadastro, boas-vindas, conta e admin não importam mais `firebase_auth` nem `cloud_firestore`. Login, logout e cadastro usam `authRepositoryProvider`; o painel admin usa `adminRepositoryProvider`. O comportamento das mensagens de login não mudou.
- `ProfileRepository.createProfile` grava `users/{uid}` e `publicProfiles/{uid}` em um único lote (`WriteBatch`). A assinatura não mudou.
- A lógica do painel admin (eventos por período, seed de cristais e publicação do catálogo) saiu da tela. A lista inicial de cristais foi para `lib/data/crystal_seed.dart`. A publicação mantém a regra anterior: itens existentes preservam preço e status, itens novos recebem os dois, e itens fora do catálogo são desativados, nunca apagados.
- Durante o cadastro, o app fica na tela de boas-vindas até a operação terminar, mesmo com a conta já autenticada. Isso evita sair da tela antes de exibir um erro.
- `/welcome` sem rascunho de cadastro volta para `/register`. Ao entrar em `/register`, um rascunho anterior é descartado.
- Reorganização de `lib/data/` e `lib/models/`, sem mudança de comportamento (mesmos valores, regras, consultas e textos). Os cálculos astrológicos e o seed do catálogo saíram de arquivos mistos: `core/astro/` (signos, mapa natal, sinergia), `data/catalog_seed.dart`, `data/profile_pictures.dart`, `models/shop_item.dart` e `theme/cosmetics_style.dart`. Cada modelo tem arquivo próprio (`ritual_event.dart`, `chat_models.dart`, `friend.dart`, `intention_notice.dart`); `app_user.dart` ficou só com `AppUser`. `CatalogEntry` foi para `models/catalog_entry.dart` e as exceções de economia para `services/economy_exceptions.dart`.
- Os valores que estavam duplicados entre o código Dart e `firestore.rules` (saldo inicial, recompensa do check-in, skin e fundo padrão, papéis, limites do cadastro e de perfil) passam a vir do contrato em `rules_contract.dart`. `SignUpLimits` mantém a mesma API, agora com as constantes do contrato.

### Corrigido

- O perfil não fica mais preso ao trocar de conta. O uid vem da autenticação, então a troca direta de usuário A para B (sem logout) não mantém eventos ou amizades de A durante o carregamento de B. Um perfil retido de outro usuário também não concede acesso de administrador.
- Erro no stream de autenticação passa a ser tratado como usuário deslogado.
- Compra e check-in passam a ser atômicos (transação).
- Regras do Firestore ajustadas após revisão de segurança.
- Fechadas brechas de inventário e de catálogo na loja.
- Falha ao criar o perfil no fim do cadastro não era tratada e deixava a conta sem perfil. Agora a conta é desfeita (ou o usuário é orientado, se o desfazimento falhar), o mesmo vale para falha ao definir o nome de exibição.
- O cadastro podia gravar `users/{uid}` sem `publicProfiles/{uid}` quando a segunda escrita falhava. Agora as duas gravações são um único lote.

### Removido

- `lib/data/astrology.dart` e `lib/data/cosmetics.dart`, substituídos pelos arquivos da reorganização (ver "Alterado"). A duplicação do slug do signo virou uma única função (`zodiacSlug`).
- `ProfileRepository.updateFields`, a trava por prefixo que recusava chaves `wallet*`, `inventory*`, `dailyCheckIn*` e `role*` (com `ArgumentError`) e `PublicProfileSync.touches`. Não há mais escrita genérica por caminho de campo.

- `UserRepository` (`lib/services/user_repository.dart`), `userRepositoryProvider` e o `FakeUserRepository` dos testes, substituídos pelos repositórios por agregado.
- Dependências sem uso.
- Histórico morto do `OracleService`.
- Nome, e-mail e senha como `state.extra` da rota `/welcome`. A senha não passa mais pelo estado de navegação.
- Chamadas diretas a `FirebaseAuth` e `FirebaseFirestore` nas telas de login, cadastro, conta e admin.
