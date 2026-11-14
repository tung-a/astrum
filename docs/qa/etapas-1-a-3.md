# QA: etapas 1 a 3 da reestruturação

- Data: 2026-11-14
- Plano: `docs/plans/reestruturacao-etapas-1-a-3.md`
- Escopo: diff não commitado na branch `feature/flutter-migration` (`lib/app_router.dart`, `lib/providers/app_providers.dart`, `lib/services/user_repository.dart`, `lib/core/firebase/`, `.github/workflows/`, `README.md`, `test/`).
- Ambiente: Windows 11, Flutter 3.47.7 (stable), Node 22.18, Java 24 (o CI usa Java 21), firebase-tools 14.17.0 local (o CI pina 13.29.1; a versão local não representa o CI).

## Resultado geral

| Verificação | Resultado |
|---|---|
| `flutter analyze` | Passou: "No issues found" |
| `flutter test` | Passou: 52 testes, 0 skipped (reexecutado após a correção do BUG-1) |
| `test_rules/` (`npm ci` e `npm test`, emulador Firestore local) | Passou: 37 de 37 |
| CI no GitHub (`ci.yml`, `build.yml`) | Não executado (sem push; só inspeção estática) |
| Build Android (`flutter build apk --debug`) | Não executado |
| Build iOS (`--no-codesign`) | Não executado (sem macOS) |

Nenhum código em `lib/` foi alterado. Foi acrescentado `test/qa_etapas_1_a_3_test.dart` (4 casos; o do BUG-1 passou a rodar após a correção).

## Mapeamento critério → teste

Legenda: PASSOU = teste automatizado que passou; ESTÁTICO = conferido por leitura/grep; NÃO VERIFICADO = não rodado; LACUNA = sem cobertura.

### Etapa 1. CI e widget de boot

| Critério | Cobertura | Status |
|---|---|---|
| 1.1 workflow `ci.yml` roda analyze, test e job de regras em push/PR para `main` e `feature/flutter-migration` | `.github/workflows/ci.yml` | ESTÁTICO (não rodado no GitHub) |
| 1.1 job de regras: Node, `npm ci` em `test_rules/`, `firebase emulators:exec`, 37 testes | `npm test` local, 37/37 | PASSOU (local); job no runner NÃO VERIFICADO |
| 1.1 sem `flutter build web` nem Chrome | inspeção de `ci.yml` e `build.yml` | ESTÁTICO |
| 1.1 Android e iOS opcionais em jobs separados, sem segredos | `build.yml` (manual; iOS também semanal). Não há referência a `google-services` em `android/` | ESTÁTICO; build NÃO VERIFICADO |
| 1.1 Flutter fixado na versão local (3.47.7) e cache | `FLUTTER_VERSION: "3.47.7"`; `cache: true` no flutter-action | ESTÁTICO. Cache de pub: sem cache explícito de `~/.pub-cache` (ver observações) |
| 1.1 README com explicação do CI e como rodar localmente | seção "Integração contínua" no `README.md` | ESTÁTICO (badge não existe; o critério aceita a explicação) |
| 1.2 sem config do Firebase, `AstrumApp` mostra "Configure o Firebase" sem exceção | `test/widget_test.dart` | PASSOU |
| 1.2 `flutter test` verde sem emulador | suíte completa sem emulador | PASSOU |

### Etapa 2. Custo (select e redirect)

| Critério | Cobertura | Status |
|---|---|---|
| 2.1 saldo ou `equipped` não recriam `eventsProvider`/`friendsProvider` | `providers_subscriptions_test.dart`, "saldo, equipar e horoscopo..." | PASSOU |
| 2.1 horóscopo não recria os streams | `qa_etapas_1_a_3_test.dart`, "2.1 horoscopo diario e check-in..." (lacuna fechada pelo QA; o teste existente não mudava `dailyHoroscope`) | PASSOU |
| 2.1 `intentionProvider` não reabre com mudança fora de uid/`notificationsEnabled`; reabre quando `notificationsEnabled` muda | `providers_subscriptions_test.dart`, "saldo, equipar..." e "notificationsEnabled reabre apenas a intencao" | PASSOU |
| 2.1 troca de uid recria streams para o novo usuário | "troca de uid recria os streams..." e "login A, logout, login B..." | PASSOU |
| 2.2 saldo não reavalia o redirect (contador não incrementa) | "routerProfileKeyProvider saldo nao dispara..." e "2.2 horoscopo nao dispara..." | PASSOU na fonte (`routerProfileKeyProvider`). LACUNA parcial: o contador `profileRefresh` interno do router não é observado diretamente |
| 2.2 mudança de `isAdmin` ou de loading reavalia o redirect | "routerProfileKeyProvider..." (refresh+1 em `role: admin`), `router_test.dart` "admin logado em /login..." e "nao admin em /admin..." | PASSOU |
| 2.2 não logado vai para login; logado em `/login` vai para home | `router_test.dart` "sem usuario, rota protegida vai para /login" e grupo `decideRedirect` | PASSOU |

### Etapa 3. Providers de infraestrutura

| Critério | Cobertura | Status |
|---|---|---|
| 3.1 override de `firebaseAuthProvider` e `firestoreProvider` chega a `UserRepository` e `AnalyticsService` | `firebase_providers_test.dart`, testes 1 e 2 | PASSOU |
| 3.1 `authStateProvider` deriva de `firebaseAuthProvider` | `firebase_providers_test.dart`, "authStateProvider deriva de firebaseAuthProvider" | PASSOU |
| 3.1 `UserRepository` não abre terceira inscrição em `authStateChanges()` | `providers_subscriptions_test.dart` (`authStateChangesCalls == 1` após login/logout/login); `qa_etapas_1_a_3_test.dart`, "3.1 router e perfil compartilham uma unica assinatura" (router + perfil = 1). ESTÁTICO: `authStateChanges` só aparece em `app_providers.dart` | PASSOU |
| 3.2 `grep FirebaseAuth.instance lib/app_router.dart lib/providers/` retorna zero | grep manual | ESTÁTICO, zero ocorrências |
| 3.2 `routerProvider` com `firebaseAuthProvider` sobrescrito decide o redirect | `router_test.dart` (3 casos) | PASSOU |
| 3.2 `analyze` e `test` verdes, sem mudança visível | analyze e test verdes; mudança visível NÃO VERIFICADA manualmente | PASSOU / NÃO VERIFICADO |

## Bugs

### BUG-1 (baixa severidade): troca de usuário A para B sem logout mantém o uid de A durante o loading de B

- Teste: `test/qa_etapas_1_a_3_test.dart`, "BUG-1 ..." (**CORRIGIDO**: `currentUidProvider` agora deriva de `authStateProvider` e o router só considera `isAdmin` do perfil do uid autenticado; sem `skip`).
- Passos para reproduzir:
  1. Logar como A com o perfil carregado e `eventsProvider` ativo.
  2. Mudar a auth para B sem passar por `null` (login direto como B, sem signOut). A UI atual faz logout antes, então este é um cenário de borda.
  3. Antes de o perfil de B emitir, ler `currentUidProvider`.
- Resultado observado (sonda, com `FakeUserRepository`): `currentUidProvider == 'a'`; `profileProvider` com `isLoading=true` e `hasValue=true` (valor anterior retido); `eventsProvider` segue em `users/a/events`.
- Esperado: uid de A não deve aparecer depois que a auth já é de B.
- Causa provável: `valueOrNull` do `StreamProvider` retém o valor anterior durante o rebuild.
- Impacto: as regras do Firestore limitam leitura ao dono, então não há vazamento comprovado; o risco é a UI mostrar eventos de A por instantes e o listener falhar com permissão negada. Não reproduzido no app real.
- Sugestão (não aplicada, é de `lib/`): derivar o uid de `authStateProvider` (`ref.watch(authStateProvider).valueOrNull?.uid`) em vez de `profileProvider`.

## Observações (não são falhas do critério)

- `UserRepository` e `AnalyticsService` ainda têm fallback `?? FirebaseAuth.instance` / `FirebaseFirestore.instance` nos construtores. Os providers sempre passam as instâncias, então o critério é atendido, mas o singleton continua acessível.
- Telas (`login_screen`, `welcome_screen`, `account_screen`, `admin_screen`) ainda usam os singletons. É esperado: a etapa 6 trata disso. Por isso não há teste de widget para elas.
- CI: `ci.yml` não tem cache explícito de `~/.pub-cache`, apesar do critério citar cache de pub. Confirmar se o `cache: true` do flutter-action cobre isso no runner.
- CI: actions usam tags (`@v4`, `@v2`), não SHA. Já está registrado como pendência no plano.
- CI: `firebase-tools` pinado em 13.29.1 no workflow; a versão local é 14.17.0. Os testes de regras rodaram localmente com a versão local, não com a do CI.
- Java: local 24, CI 21 (regras) e 17 (build Android). Não testado com Java 21.

## Lacunas e itens não verificados

- CI no GitHub: os workflows não foram executados. Não houve push, e YAML/actionlint não foram validados por ferramenta.
- Build Android (`flutter build apk --debug`): não executado. A inspeção estática não encontrou `google-services` em `android/`, mas a compilação real precisa ser rodada para confirmar o item pendente do plano.
- Build iOS (`--no-codesign`): não executado (sem macOS).
- Emulador de regras no runner do CI: não verificado; localmente rodou com cache do emulador já baixado.
- Comportamento visível em Android/iOS e de navegação real: não verificado manualmente.
- Telas: sem teste de widget (dependem de `FirebaseFirestore.instance` direto; etapa 6).
- Contador `profileRefresh` do router: coberto pela fonte (`routerProfileKeyProvider`), não observado diretamente.

## Comandos executados

```
flutter analyze
flutter test
cd test_rules && npm ci && npm test
```

Arquivos adicionados por este QA: `test/qa_etapas_1_a_3_test.dart` (não commitado) e este relatório.
