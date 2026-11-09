# Auditoria da migração RN (Expo) para Flutter

Branch: `feature/flutter-migration` (HEAD 39320e8). Base: `main` (630bf9d).
Limite da auditoria: o planner não tem Bash. Não foi possível ver o código RN original nem rodar `git status`/`flutter analyze`/`flutter test`. Tudo abaixo vem de leitura de `lib/`, `pubspec.yaml`, `.gitignore` e Glob. Itens marcados "verificar" dependem de comando que o builder/devops deve rodar.

## 1. Inventário de paridade

O RN original não está acessível no working tree (arquivos removidos). A lista de telas RN abaixo vem do contexto repassado pelo orquestrador (rotas `app/(auth)`, `(user)`, `(admin)`, `inventory`, `shop`, `modal`, `contexts/ChatContext`, `contexts/CosmeticsContext`, `NotificationManager`, `MeditationModal`, `ConstellationView`, `agenda/*`). Não afirmo comportamento interno do RN.

| Item RN | Equivalente Flutter | Status |
|---|---|---|
| (auth)/login, register, welcome | `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `welcome_screen.dart` | portado (comportamento a comparar) |
| (user)/index (home) | `lib/screens/home/cosmos_screen.dart` | portado |
| (user)/chat + ChatContext | `lib/screens/chat/oracle_screen.dart`, `lib/services/chat_store.dart`, `oracle_service.dart` | portado; histórico só local (SharedPreferences) |
| (user)/agenda + components/agenda | `lib/screens/rituals/rituals_screen.dart` (eventos em `users/{uid}/events`) | portado (verificar paridade: seletor de semana, timeline, modal de evento) |
| (user)/profile, account | `lib/screens/account/account_screen.dart`, `lib/screens/astral/astral_screen.dart` | portado; mapeamento profile/astral a confirmar |
| (admin)/dashboard, users, profile | `lib/screens/admin/admin_screen.dart` (tela única) | parcial: dashboard/users/profile fundidos; confirmar se algo sumiu |
| shop + ShopCard | `lib/screens/shop/shop_screen.dart` | portado |
| inventory | `lib/screens/shop/inventory_screen.dart` | portado |
| CosmeticsContext | `lib/data/cosmetics.dart` + providers `equippedSkinProvider`/`equippedBackgroundProvider` | portado |
| MeditationModal | `lib/screens/rituals/meditation_sheet.dart` | portado, mas sons `assets/sounds/*.mp3` sem uso no código (ver 4) |
| ConstellationView | `lib/widgets/starfield.dart` (possível) | não confirmado |
| NotificationManager | notificações in-app via Firestore (`sendIntention`, `watchUnreadIntention`); sem push (nenhum pacote de FCM/local notifications no pubspec) | parcial (provável perda de notificações push/agendadas, verificar no RN) |
| firebaseConfig.ts | `lib/config/env.dart` (`--dart-define`) | portado |
| Gemini/oráculo (se existia) | `oracle_service.dart`: Groq, depois Pollinations, depois resposta local | portado, com fallback novo |
| Tema (constants/theme.ts) | `lib/theme/astrum_theme.dart`, `astrum_colors.dart` | portado |
| Amigos / enviar intenção | `user_repository.dart:98-167` | portado (origem RN não confirmada) |
| Analytics | `lib/services/analytics_service.dart` | portado/novo |
| modal.tsx, hello-wave, parallax, collapsible, external-link, haptic-tab | sem equivalente | boilerplate do template Expo; não migrar |

Ação: T01 produz a tabela definitiva de paridade usando `git show main:<arquivo>`.

## 2. Riscos concretos no código Flutter

Severidade A = corrigir antes de merge; B = próximo ciclo.

1. A - `test/widget_test.dart:7`: `pumpWidget(const AstrumApp())` sem `ProviderScope`. `AstrumApp` é `ConsumerWidget` (`lib/main.dart:27`), então o teste deve falhar. Verificar com `flutter test`.
2. A - Chave Groq embutida no app: `lib/config/env.dart:14` e `oracle_service.dart:49-50` (Bearer enviado do cliente). `--dart-define` compila a chave no binário; qualquer usuário a extrai. Exige decisão (proxy/Cloud Function ou aceitar risco). Reviewer-consultor.
3. A - Economia no cliente, sem validação servidor: `shop_screen.dart:112-123` (compra: checa saldo no cliente, grava `inventory` por sobrescrita de array a partir de estado local, race condition), `cosmos_screen.dart:68-75` (check-in +25 só valida data no cliente), `user_repository.dart:69` (`updateFields` aceita qualquer mapa, incluindo `role`, `wallet`). Sem `firestore.rules` no repositório (Glob não achou). Um usuário pode se promover a admin ou dar-se moedas. Reviewer-consultor obrigatório.
4. A - Leitura de todos os usuários e busca por email: `user_repository.dart:113-141` (`findUserByEmail`) e `:193-205` (`listUsers`, limite 80, expõe email, role, saldo). Exige regras que limitem a admin; busca por email expõe dados pessoais. Reviewer-consultor.
5. A - `analytics_service.dart:15`: coleção `analytics_events` gravável pelo cliente, aceita `anonymous`; sem regras, é vetor de abuso/custo.
6. B - Senha passada em `state.extra` para `/welcome`: `app_router.dart:69`, `register_screen.dart:64`, `welcome_screen.dart:98`. Fica em memória/rota; avaliar fluxo criar conta primeiro e coletar perfil depois.
7. B - `user_repository.dart:32-67`: `createProfile` define `role: 'user'` e `wallet` pelo cliente; mesmo problema do item 3. Dados de nascimento (`birthDate/Time/Place`) são dado pessoal sensível (LGPD): documentar e proteger por regras.
8. B - `user_repository.dart:113-141`: lógica duplicada de montar `Friend` três vezes; busca em duas queries (lowercase e original). Normalizar email na gravação.
9. B - `cosmos_screen.dart:57` `catch (_) {}` engole erro; `:40-42` e `:58-64` sem tratamento de erro/`mounted` após `await`; `_drawing` fica `true` se `updateFields` lançar. `oracle_service.dart:105` também engole exceções sem log.
10. B - `oracle_service.dart:63-70`: fallback para `text.pollinations.ai` envia prompt do usuário (inclui signo) a terceiro sem consentimento/aviso. Decisão de privacidade.
11. B - `app_providers.dart:23-25`: `prefsProvider` lança `StateError` se não sobrescrito; testes precisam sobrescrever.
12. B - `app_router.dart:23-33`: `FirebaseAuth.instance` direto no provider impede testes; `redirect` lê `profileProvider` sem tratar erro (`hasError`), pode prender usuário em estado inconsistente.
13. B - `chat_store.dart:14`: histórico do chat em SharedPreferences sem limite de tamanho nem criptografia; sem sincronização entre dispositivos (perda de paridade possível).
14. B - Cobertura de testes: apenas `test/astrology_test.dart` e `widget_test.dart`. Sem testes de `oracle_service` (fácil: `http.Client` injetável), `chat_store`, `AppUser.fromFirebase`, `moon.dart`, `tarot.dart`, redirect do router.
15. B - `analysis_options.yaml` só com `flutter_lints` padrão; sem `prefer_single_quotes`, `unawaited_futures`, `use_build_context_synchronously` explícito, etc.

## 3. Organização do repositório

Estado informado: RN apagado no working tree, Flutter na raiz como untracked, `flutter/` commitado em 39320e8 e apagado no working tree. Glob confirma que `flutter/` não existe mais em disco e que a raiz tem `android/ ios/ web/ windows/ macos/ linux/ assets/ lib/ test/`.

- `flutter/` no HEAD: verificar com `git diff --stat HEAD -M` se os arquivos de `flutter/lib/**` foram movidos (rename) para `lib/**` sem diferença de conteúdo. Se sim, `flutter/` não deve existir (ver decisão D2).
- Rastreados mas ignorados: `.vscode/settings.json` e `.vscode/extensions.json` (`.gitignore:23`). Remover do índice com `git rm --cached` (ou decidir mantê-los e tirar a regra; D5).
- `build/` existe em disco (3965 arquivos no Glob, incluindo `build/web`). Está ignorado por `/build/` (`.gitignore:6`); confirmar que nada dele está rastreado.
- `.gitignore` não cobre artefatos RN antigos (`node_modules/`, `.expo/`) caso existam em disco. Se existirem, apagar localmente. Verificar `package.json`, `package-lock.json`, `tsconfig.json`, `expo-env.d.ts`, `scripts/`, `babel`: o Glob da raiz truncou a lista; devops deve listar o que sobrou.
- `.gitignore` ignora `google-services.json` e `GoogleService-Info.plist`: coerente com `--dart-define`, mas conferir que `android/`/`ios/` não dependem deles. Não há `firebase.json` nem `firestore.rules` em lugar algum: regras de segurança não estão versionadas.
- Assets mortos/pesados em `assets/images/`: `icon_estudai.png`, `icon_old.png`, `mesa_tarot.png`, `splash-icon.png`, `favicon.png`, `android-icon-*.png` e possivelmente restos do template. Nenhum referenciado por `lib/` (Grep). `icon.png` é usado só pelo `flutter_launcher_icons`. Remover os não usados.
- `docs/` não existia até agora (só este plano). Criar `docs/qa/`, `docs/architecture/`, `docs/decisions/` quando necessário.
- Faltam: `CHANGELOG.md`, `docs/release-checklist.md`, CI (`.github/workflows`), `firestore.rules`. Existem: `.env.example`, `README.md` reescrito.
- Atenção a segredos: `.env` está ignorado; conferir com `git ls-files | findstr env` e `git log -p -S"AIza"` que nenhuma chave Firebase/Groq do RN (`firebaseConfig.ts`, `app.config.js`) vive no histórico; se vive, chave deve ser rotacionada/restrita.

## 4. Eficiência

1. Dependências sem uso em `lib/` (Grep): `flutter_animate` (pubspec:25) sem import; `cupertino_icons` (pubspec:12) provavelmente sem uso. Verificar e remover. `flutter_markdown` está presente e usado em `oracle_screen.dart:2` (o pacote foi descontinuado; avaliar `flutter_markdown_plus`).
2. `assets/sounds/*.mp3` (calm, energy, focus, sleep) declarados em pubspec:70 e sem pacote de áudio nem referência em `lib/` (Grep `sounds` sem resultado): ou implementar áudio na meditação (paridade com RN?) ou remover os mp3 do bundle.
3. `pubspec.yaml:56` declara `assets/images/` inteiro + 12 pastas de perfil + `zodiac/`. A pasta inteira já inclui só o primeiro nível; manter subpastas é correto, mas os PNG (48 de perfil + 12 zodiac) devem ser medidos e comprimidos (WebP/oxipng) e redimensionados ao tamanho de avatar. Medir com `du`/`Get-ChildItem`.
4. `google_fonts` baixa fontes em runtime (`astrum_theme.dart:2`): em release, empacotar as fontes em `assets/fonts` para evitar rede no primeiro frame e funcionar offline.
5. `app_providers.dart`: `profileProvider` é consumido inteiro por vários providers; usar `.select` (ex.: `equippedSkinProvider` reconstrói a cada mudança de saldo). `eventsProvider`/`friendsProvider` fazem `ref.watch(profileProvider).valueOrNull` e recriam o stream a cada update do perfil: derivar `uid` com `.select((p) => p.valueOrNull?.uid)`.
6. `listUsers` faz `get()` único em `FutureBuilder` (`admin_screen.dart:83,94,156`) sem paginação além de `limit(80)`.
7. `watchProfile` (`user_repository.dart:18`) usa `asyncExpand`; trocar para `switchMap`-equivalente evita ouvir snapshots antigos ao trocar de usuário (ver `rxdart` ou `StreamProvider` encadeado). Verificar.
8. `starfield.dart`: conferir se usa `CustomPainter` com `RepaintBoundary` e `shouldRepaint` correto (custo de animação contínua). Verificar.
9. `watchEvents` (`user_repository.dart:73-81`) exige índice composto `date`+`time`; versionar `firestore.indexes.json`.
10. Build: `.dart_tool`/`build` ok; falta `flutter analyze` e `flutter test` num CI com cache de pub.

## 5. Tarefas

Convenção: R-C = precisa de reviewer-consultor.

**T01 - Provar a paridade com o RN** (qa + planner; sem código)
- Dep: D1 resolvida ou apenas leitura de `git show main:...`.
- Aceite: Dado o commit `main`, Quando cada tela/serviço RN é listado via `git ls-tree` e comparado a `lib/`, Então existe `docs/qa/paridade-rn-flutter.md` com cada item marcado portado/parcial/faltando e evidência (arquivo RN e arquivo Dart). Dado um item "parcial", Então há issue/tarefa com o que falta. R-C: não.

**T02 - Rodar a base de validação** (builder)
- Aceite: Dado a raiz do projeto, Quando roda `flutter pub get`, `flutter analyze` e `flutter test`, Então a saída é registrada em `docs/qa/baseline.md` com warnings e falhas listados. R-C: não.

**T03 - Consertar `widget_test.dart` e criar helpers de teste** (builder)
- Dep: T02.
- Aceite: Dado `AstrumApp` sem Firebase configurado, Quando o teste envolve em `ProviderScope` com `prefsProvider` sobrescrito, Então `flutter test` passa e o texto "Configure o Firebase" aparece. R-C: não.

**T04 - Higiene do git (índice)** (devops)
- Dep: D1, D2, D5.
- Aceite: Dado o índice, Quando `git ls-files .vscode build` roda, Então retorna vazio (se D5 = remover). Dado a árvore, Quando `git status --short` roda, Então não há arquivos RN deletados fora de commit nem `flutter/` órfão. Dado o histórico, Quando `git log -p -S"AIza"` e `-S"gsk_"` rodam, Então nenhum segredo aparece; se aparecer, é aberto item de rotação de chave. R-C: sim (segredos).

**T05 - Commit da migração** (devops, só com pedido explícito do usuário)
- Dep: T02, T03, T04, D1.
- Aceite: Dado a estratégia escolhida em D1, Quando os commits são feitos, Então cada commit compila (`flutter analyze` sem erro) e nenhum contém `.env`, `build/`, `.vscode/` ou chaves. R-C: não.

**T06 - Limpar assets e dependências mortas** (builder)
- Dep: T02.
- Aceite: Dado `pubspec.yaml`, Quando cada dependência é buscada com Grep em `lib/`, Então `flutter_animate` e `cupertino_icons` (se sem uso) são removidos e `flutter pub get` e `flutter analyze` passam. Dado `assets/images/`, Quando um arquivo não é referenciado em `lib/` nem em `flutter_launcher_icons`, Então é removido e o tamanho total de `assets/` é registrado antes/depois. Dado `assets/sounds/*.mp3`, Então a decisão D4 é aplicada (usar ou remover). R-C: não.

**T07 - Regras do Firestore e modelo de dados seguro** (architect + builder)
- Dep: T01 (para saber o que o RN já fazia), D3.
- Aceite: Dado `firestore.rules` versionado, Quando um usuário comum tenta alterar `role`, ou `wallet.stardust` para valor maior, ou ler `users/{outro}`, Então a escrita/leitura é negada (testada com Firebase emulator rules tests). Dado `analytics_events`, Então o cliente só cria com `userId == auth.uid` e campos permitidos. Dado `firestore.indexes.json`, Então contém o índice de `events(date,time)`. R-C: sim (segurança, dados de usuário, arquitetura).

**T08 - Mover compra, check-in e saldo para operação atômica/servidor** (architect, builder)
- Dep: T07, D3.
- Aceite: Dado saldo 50 e item de preço 100, Quando a compra é tentada, Então falha sem alterar o documento. Dado dois toques simultâneos em comprar o mesmo item, Então o item é cobrado uma vez. Dado check-in já feito hoje, Quando é repetido, Então o saldo não muda (garantido pelas regras/transação, não só pelo cliente). Dado compra, `inventory` usa `FieldValue.arrayUnion`, não sobrescrita de lista local. R-C: sim (loja/moedas/inventário).

**T09 - Chave de IA fora do cliente** (architect + builder)
- Dep: D3, D6.
- Aceite: Dado build de release, Quando o binário é inspecionado por `GROQ_API_KEY`, Então a chave não aparece; chamadas à IA passam por endpoint próprio (ou o recurso é desativado). Dado falha do endpoint, Então `localReply` é usado e o app não quebra. R-C: sim (chaves de API).

**T10 - Privacidade do oráculo e fluxo de cadastro** (designer + builder)
- Dep: D6.
- Aceite: Dado o fallback Pollinations ativo, Quando o usuário envia um prompt, Então há aviso/consentimento (ou o fallback é removido). Dado o cadastro, Quando o usuário avança para `/welcome`, Então a senha não trafega em `state.extra`. R-C: sim (dados de usuário).

**T11 - Robustez de erros nas telas** (builder)
- Dep: T03.
- Aceite: Dado falha em `updateFields` durante `_drawTarot` (`cosmos_screen.dart:58`), Quando o erro ocorre, Então `_drawing` volta a `false` e o usuário vê SnackBar. Dado `oracle_service`, Quando todas as chamadas HTTP falham, Então `localReply` responde e o erro é logado via `debugPrint`. Dado qualquer `await` seguido de uso de `context`, Então há checagem `mounted` (`flutter analyze` sem `use_build_context_synchronously`). R-C: não.

**T12 - Refatorar `UserRepository` e providers** (architect + builder)
- Dep: T03, T07.
- Aceite: Dado `findUserByEmail`, Quando refatorado, Então há uma única função de mapeamento para `Friend` e testes com `fake_cloud_firestore` ou interface mockada cobrem encontrado/não encontrado/case. Dado `eventsProvider`/`friendsProvider`, Quando só o saldo muda, Então os streams não são recriados (teste com contador de listeners). Dado `routerProvider`, Então `FirebaseAuth` e `UserRepository` vêm de providers sobrescrevíveis. R-C: sim (arquitetura).

**T13 - Testes automatizados** (qa + builder)
- Dep: T03, T12 (parte).
- Aceite: Dado `OracleService` com `http.Client` fake, Quando Groq retorna 500 e Pollinations 200, Então devolve texto Pollinations; Quando ambos falham, Então devolve `localReply`. Dado `ChatStore`, Quando o JSON salvo está corrompido, Então `load` devolve uma conversa vazia. Dado `moon.dart`/`tarot.dart`, Então datas fixas produzem fase/carta esperadas e `pickDailyCard` é determinística. Dado o redirect do router, Então deslogado vai a `/login`, admin a `/admin`, usuário comum bloqueado em `/admin`. Cobertura registrada em `docs/qa/`. R-C: não.

**T14 - Performance** (builder)
- Dep: T06.
- Aceite: Dado as fontes, Quando o app inicia sem rede, Então o texto renderiza com fonte empacotada. Dado PNGs de perfil, Quando comprimidos, Então o tamanho de `assets/images/profile-pictures` cai e não há diferença visual perceptível (print comparativo). Dado `equippedSkinProvider`, Quando muda apenas o saldo, Então não reconstrói (via `.select`). Medir com `flutter run --profile` e DevTools; registrar em `docs/qa/performance.md`. R-C: não.

**T15 - Lints mais estritos** (builder)
- Dep: T02.
- Aceite: Dado `analysis_options.yaml`, Quando regras adicionais (`prefer_single_quotes`, `unawaited_futures`, `avoid_print`, `use_build_context_synchronously`) são ativadas, Então `flutter analyze` termina sem issues. R-C: não.

**T16 - CI e checklist de release** (devops)
- Dep: T03, T15.
- Aceite: Dado um PR, Quando o workflow roda, Então executa `flutter pub get`, `flutter analyze`, `flutter test` com cache e falha em qualquer erro. Dado `docs/release-checklist.md`, Então lista: variáveis `.env`, regras do Firestore publicadas, ícones, versão, testes nas plataformas-alvo (D7). R-C: sim apenas se publicar segredos no CI.

**T17 - Documentação** (writer)
- Dep: T05, T08, T09.
- Aceite: Dado `README.md`, Quando seguido do zero, Então o app roda com `.env` copiado de `.env.example`. Dado `CHANGELOG.md`, Então a versão 2.0.0 lista a migração, mudanças de segurança e itens removidos. Dado `docs/architecture/`, Então há um documento da estrutura `lib/` e do modelo Firestore. R-C: não.

**T18 - Paridade restante (se T01 achar lacunas)** (designer + builder)
- Dep: T01, D4, D7.
- Aceite: um critério por lacuna, definido após T01 (ex.: notificações push, áudio da meditação, páginas admin separadas). R-C: depende do item.

## 6. Ordem de execução

1. Fase 0 (paralelo): T01 (leitura, sem alterar código), T02.
2. Fase 1 (paralelo após T02): T03, T06, T15; T04 depende das decisões D1, D2, D5 (pode começar parte de leitura, como a busca de segredos no histórico, desde já).
3. Fase 2: T05 (commit) só com pedido explícito e depois de T02, T03, T04. Preferível commitar a migração antes das mudanças de segurança, para ter ponto de retorno.
4. Fase 3: T07 (primeiro), depois T08, T09 e T10 em paralelo (arquivos distintos). T11 pode rodar em paralelo com T07.
5. Fase 4: T12, T13, T14 (T14 após T06).
6. Fase 5: T16, T17, T18.

Em cada tarefa com R-C, o fluxo é builder, depois reviewer, depois reviewer-consultor, depois qa.

## 7. Decisões para o usuário (não decididas aqui)

- D1. Commitar a migração em um commit grande ou em partes (ex.: 1 remoção RN, 2 Flutter na raiz, 3 limpeza)? Recomendação do planner: partes, mas a decisão é sua. Isto também define se é aceito um histórico intermediário que não compila.
- D2. Manter ou remover a pasta `flutter/` (existiu em 39320e8)? Hoje o working tree a considera removida e usa a raiz. Confirmar que a raiz é o projeto oficial.
- D3. Modelo de segurança para moedas, loja e `role`: Cloud Functions (requer plano Blaze) ou regras do Firestore + transações no cliente? Muda custo e escopo. Se a resposta cortar escopo (ex.: aceitar economia insegura no MVP), escalar para `planner-consultor`.
- D4. Paridade desejada: implementar áudio da meditação e notificações push/agendadas (existiam no RN?), ou cortar? Impacta pubspec e permissões nativas.
- D5. Manter `.vscode/` versionado (remover do `.gitignore`) ou removê-lo do índice?
- D6. Chave Groq e fallback Pollinations: proxy próprio, apenas fallback local, ou aceitar chave no cliente? É decisão de produto e de privacidade.
- D7. Plataformas-alvo: o repositório tem android, ios, web, windows, macos e linux. Manter todas (custo de teste e CI) ou reduzir a android, ios e web? Pastas desativadas podem sair do repositório.
- D8. Remover do disco e do git os assets sem uso (`icon_estudai.png`, `icon_old.png`, `mesa_tarot.png`, etc.) após confirmar com você que não são de uso futuro.
- D9. Histórico do chat: manter local-only ou sincronizar com Firestore (dado pessoal, exige regras)?
