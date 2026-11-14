# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). A versão corresponde ao campo `version` do `pubspec.yaml` (atualmente `2.0.0+1`).

## [Não lançado]

### Adicionado

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

### Alterado

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

### Corrigido

- O perfil não fica mais preso ao trocar de conta. O uid vem da autenticação, então a troca direta de usuário A para B (sem logout) não mantém eventos ou amizades de A durante o carregamento de B. Um perfil retido de outro usuário também não concede acesso de administrador.
- Erro no stream de autenticação passa a ser tratado como usuário deslogado.
- Compra e check-in passam a ser atômicos (transação).
- Regras do Firestore ajustadas após revisão de segurança.
- Fechadas brechas de inventário e de catálogo na loja.
- Falha ao criar o perfil no fim do cadastro não era tratada e deixava a conta sem perfil. Agora a conta é desfeita (ou o usuário é orientado, se o desfazimento falhar), o mesmo vale para falha ao definir o nome de exibição.
- O cadastro podia gravar `users/{uid}` sem `publicProfiles/{uid}` quando a segunda escrita falhava. Agora as duas gravações são um único lote.

### Removido

- `ProfileRepository.updateFields`, a trava por prefixo que recusava chaves `wallet*`, `inventory*`, `dailyCheckIn*` e `role*` (com `ArgumentError`) e `PublicProfileSync.touches`. Não há mais escrita genérica por caminho de campo.

- `UserRepository` (`lib/services/user_repository.dart`), `userRepositoryProvider` e o `FakeUserRepository` dos testes, substituídos pelos repositórios por agregado.
- Dependências sem uso.
- Histórico morto do `OracleService`.
- Nome, e-mail e senha como `state.extra` da rota `/welcome`. A senha não passa mais pelo estado de navegação.
- Chamadas diretas a `FirebaseAuth` e `FirebaseFirestore` nas telas de login, cadastro, conta e admin.
