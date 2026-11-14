# Plano: reestruturação, etapas 1 a 3 e backlog 4 a 13

Base: `docs/architecture/restructuring.md` (seção 6) e `docs/decisions/2026-11-restructuring-decisions.md`.
Branch única: `feature/flutter-migration`. Um commit pequeno por etapa; commit só com pedido explícito do usuário. Cada etapa termina com `flutter analyze` e `flutter test` verdes.

Base do plano: referências de arquivo e linha de `restructuring.md` (não reverificadas no código nesta passada; o builder deve confirmá-las). Confirmado: `.github/` ainda não existe.

## Papéis por etapa

| Etapa | architect | designer | builder | qa | writer | devops | reviewer-consultor |
|---|---|---|---|---|---|---|---|
| 1 CI | não | não | sim (teste de widget) | sim | sim (README) | sim | não |
| 2 select e redirect | não | não | sim | sim | não | não | não |
| 3 providers de infra | sim (confirmar nomes e `core/`) | não | sim | sim | não | não | sim (arquitetura/auth: router e providers de Auth) |

Nenhuma das três etapas toca `firestore.rules`, mas a 3 mexe no fluxo de autenticação e na fundação dos repositórios, daí o consultor.

## Etapa 1. Rede de segurança (CI)

**História 1.1.** Como mantenedor, quero que todo push e PR rode analyze, testes e testes de regras, para não regredir.

Critérios:
- Dado um push ou PR para `main` ou `feature/flutter-migration`, Quando o workflow `.github/workflows/ci.yml` roda, Então executa os jobs `flutter analyze` e `flutter test`, e o job de regras.
- Dado o job de regras, Quando roda, Então instala Node, instala dependências em `test_rules/`, sobe o emulador do Firestore (`firebase emulators:exec`) e os 37 testes passam; falha em qualquer teste reprova o job.
- Dado que o app é só iOS/Android, Quando o CI roda, Então não há `flutter build web` nem teste em Chrome. Os jobs de analyze/test rodam em `ubuntu-latest` (não dependem de plataforma). Build de Android (`flutter build apk --debug`) é opcional em job separado e o de iOS (`--no-codesign`, runner macOS) fica como job manual/agendado por custo; ambos exigem `.env`/Firebase config: usar `--dart-define` vazio ou só compilar quando houver secrets. Nenhum segredo é commitado.
- Dado a versão do Flutter, Quando o CI instala, Então fixa a versão do canal stable usada localmente (`flutter --version`) e usa cache de pub.
- Dado o README, Quando lido, Então traz o badge ou a explicação do CI e como rodar as mesmas verificações localmente.

**História 1.2.** Como mantenedor, quero um teste de widget mínimo, para garantir que o app sobe.

Critérios:
- Dado ausência de configuração do Firebase, Quando o `AstrumApp` é montado em `testWidgets`, Então exibe a tela "configure o Firebase" sem exceção.
- Dado `test/widget_test.dart` atual (12 linhas), Quando substituído/ampliado, Então `flutter test` continua verde sem emulador.

Dependências: nenhuma. Risco: emulador exige Java e `firebase-tools` no runner (tempo de CI); fixar versões.

## Etapa 2. Correções de custo (select e redirect)

**História 2.1.** Como usuário, quero que mudar saldo ou equipar item não reabra streams de eventos/amigos/intenções, para reduzir leituras do Firestore.

Critérios:
- Dado `eventsProvider` e `friendsProvider`, Quando só o saldo, o horóscopo ou `equipped` mudam em `users/{uid}`, Então o provider não é recriado e o repositório não recebe nova chamada de `watchEvents`/`watchFriends` (teste com repositório fake que conta assinaturas).
- Dado `intentionProvider`, Quando muda algo que não seja uid ou `notificationsEnabled`, Então não reabre a assinatura; Quando `notificationsEnabled` muda, Então reabre.
- Dado troca de usuário (logout/login com outro uid), Quando o uid muda, Então os streams são recriados para o novo uid.

**História 2.2.** Como usuário, quero que o router só reavalie o redirect quando o necessário.

Critérios:
- Dado `lib/app_router.dart`, Quando o perfil emite por mudança de saldo, Então `redirect` não é reavaliado (contador de refresh não incrementa).
- Dado mudança de `isAdmin` ou do estado de carregamento, Quando ocorre, Então o redirect é reavaliado (acesso a `/admin` concedido ou negado corretamente).
- Dado usuário não logado, Quando navega para rota protegida, Então vai para login; logado em `/login`, vai para a home (comportamento inalterado, coberto por teste do redirect).

Dependências: nenhuma (pode ser feita antes ou depois da 1, mas o CI protege). Risco: baixo; regressão de redirect, mitigada por teste.

## Etapa 3. Providers de infraestrutura

**História 3.1.** Como desenvolvedor, quero `firebaseAuthProvider` e `firestoreProvider`, para injetar e testar sem singletons.

Critérios:
- Dado `firebaseAuthProvider` e `firestoreProvider` (em `lib/providers/` ou `core/firebase/`, conforme o architect), Quando um teste faz override, Então `UserRepository` e `AnalyticsService` usam as instâncias fornecidas.
- Dado `authStateProvider`, Quando lido, Então deriva de `firebaseAuthProvider` e não de `FirebaseAuth.instance`.
- Dado o `UserRepository`, Quando observa o login, Então reutiliza `authStateProvider` em vez de uma terceira inscrição em `authStateChanges()` (se viável sem mudar comportamento).

**História 3.2.** Como desenvolvedor, quero o router sem `FirebaseAuth.instance`.

Critérios:
- Dado `grep FirebaseAuth.instance lib/app_router.dart lib/providers/`, Então zero ocorrências (restam apenas as telas, tratadas na etapa 6).
- Dado `routerProvider` com `firebaseAuthProvider` sobrescrito por fake, Quando o usuário é nulo/logado, Então o redirect decide corretamente (teste).
- Dado `flutter analyze` e `flutter test`, Então verdes, sem alteração de comportamento visível.

Dependências: 2 (mesmos arquivos; fazer depois evita conflito). Risco: ordem de inicialização do Firebase em `main.dart`; app sem config deve continuar mostrando a tela de configuração.

## Backlog ordenado, etapas 4 a 13

Prioridade (do usuário): refactor primeiro; exclusão de conta é importante; aceite de amizade e chat são desejáveis; compra com dinheiro real fica fora.

4. Quebrar `UserRepository` (Events, Social, Catalog, Economy, Profile, Admin; um commit por repositório). `EconomyRepository` com interface isolando todo crédito/débito de saldo (requisito de trocar o executor depois). architect + (R) na parte de economia.
5. Tipar escritas (substituir `updateFields(Map)`), perfil público em `WriteBatch`. (R) dados de usuário.
6. Tirar Firebase das telas: `AuthRepository` (cadastro com rollback) e `AdminRepository`. (R) autenticação.
7. Separar `data/` e `models/`, constantes de economia e intenções centralizadas com comentário para as regras.
8. Mover para feature-first, um commit por feature (só caminhos e imports).
9. Controllers (`Notifier`) de cosmos e oráculo; interfaces só para Auth/Profile/Economy/Chat.
10. Chat no Firestore (D9, desejável), conforme `chat-sync.md`, com migração do legado em SharedPreferences. architect + (R) dado pessoal.
11. Exclusão de conta (LGPD, importante, no Spark). Fluxo: reautenticação, apagar subcoleções pelo cliente em lotes (`events`, `friends`, `notifications`, `conversations/messages`), depois `publicProfiles/{uid}`, `users/{uid}` e por último a conta Auth; idempotente e retomável. Exige documento do architect, ajuste de `allow delete` nas regras com testes em `test_rules/` e `reviewer-consultor`. Posicionada logo após o chat para cobrir também as conversas; se o usuário quiser antes, pode subir para depois da etapa 6 (cobrindo então as coleções existentes e estendendo na 10).
12. Aceite de amizade (desejável): `friends` com estado (pendente/aceito), regras e testes, notificação de pedido, UI. architect + designer + (R) regras e dados pessoais.
13. Higiene de custo e abuso: TTL e limite em `analytics_events`, paginação de `listUsers`, App Check (Play Integrity e App Attest/DeviceCheck, modo monitor e depois enforcement). (R) regras.
14. Upgrade das dependências Firebase (depois), Riverpod/go_router só se houver motivo; verificação manual em Android e iOS.

Nota: a renumeração acima insere exclusão de conta e aceite de amizade (antigo item 13 do architect) como etapas próprias, e desloca higiene e upgrade para 13 e 14. Gatilhos de Cloud Functions/RevenueCat ficam fora do backlog (decisão adiada).

## Riscos gerais e escalonamento

- Qualquer proposta de ganho de saldo novo, venda de Poeira Estelar ou adoção de Blaze: parar e escalar ao `planner-consultor`.
- Exclusão de conta no cliente pode deixar dados órfãos em falha parcial; mitigar com ordem de apagamento e retentativa.

## Pendências registradas (revisões das etapas 1 a 3; não implementadas)

- CI: fixar as actions por SHA de commit e habilitar Dependabot para `github-actions` antes de qualquer workflow que use segredos.
- CI: fixar versões (pin) do `firebase-tools` e dos runners (`ubuntu-latest`, `macos-latest`).
- CI: confirmar que o build Android funciona sem `google-services.json` na primeira execução manual do workflow.
- Segurança: a senha trafega em `state.extra` da rota `/welcome`; tratar na etapa 6 (`AuthRepository`), sem passar a senha entre rotas.

## Itens abertos da etapa 4 (exigem decisão do usuário; não implementados)

- (M1) `rebuildPublicProfiles` falha com permission-denied para terceiros: `firestore.rules` só deixa o dono escrever `publicProfiles/{uid}`. Opções: remover a função; permitir `isAdmin()` na regra (com teste em `test_rules/`); ou cada cliente migrar o próprio perfil ao logar.
- (M3, LGPD) `preferences.publicProfile=false` é ignorado (o perfil público é gravado mesmo assim); o hash de e-mail sem sal permite enumeração de e-mails conhecidos; não há exclusão do `publicProfile` (`allow delete: if false`). Relacionar à etapa 11 (exclusão de conta), que exigirá ajustar a regra de delete.
- (B1) Falha do sync de `publicProfiles` após a transação de compra é propagada à UI como erro, mesmo com a compra já efetivada. Decidir se o sync vira best-effort (erro engolido/registrado) ou se entra na transação.
- `npm test` de `test_rules/` não foi executado na etapa 4 porque a porta 8080 estava ocupada; rodar antes de fechar a etapa.
