# Astrum ✨

Astrum é um aplicativo de astrologia, tarot e espiritualidade feito em Flutter para Android e iOS. Web não é suportada.

## Requisitos

- Flutter SDK estável instalado e disponível no `PATH` (o CI usa a versão 3.47.7)
- Uma configuração Firebase para Authentication e Cloud Firestore
- Para compilar para iOS: macOS com Xcode
- Para rodar os testes das regras do Firestore: Node 22, Java 21 e firebase-tools (`npm install -g firebase-tools@13.29.1`)

## Configuração

Copie `.env.example` para `.env` e preencha os valores do seu projeto Firebase. O arquivo `.env` é local e não deve ser commitado.

```text
FIREBASE_API_KEY
FIREBASE_AUTH_DOMAIN
FIREBASE_PROJECT_ID
FIREBASE_STORAGE_BUCKET
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_APP_ID
```

As opções Firebase são passadas ao Flutter com `--dart-define-from-file`; não é necessário adicionar os arquivos de configuração nativos do Firebase ao repositório. O app verifica todas as variáveis Firebase necessárias e mostra quais faltam.

## Executar

Na raiz do repositório:

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

Para selecionar um dispositivo, liste os disponíveis com `flutter devices` e use `flutter run -d <id> --dart-define-from-file=.env`.

## Validar e gerar builds

```bash
flutter analyze
flutter test
flutter build apk --dart-define-from-file=.env
flutter build ios --dart-define-from-file=.env   # somente em macOS
```

`flutter test` roda sem emulador e sem `.env`. Os testes das regras do Firestore precisam do emulador (veja abaixo).

## Integração contínua

Os workflows ficam em `.github/workflows/`.

- `ci.yml`, em push e PR para `main` e `feature/flutter-migration`:
  - job `flutter` (`ubuntu-latest`): `flutter analyze` e `flutter test`, com Flutter 3.47.7 (stable) e cache.
  - job `firestore-rules`: Node 22, Java 21 e firebase-tools 13.29.1; roda `npm test` em `test_rules/` contra o emulador do Firestore. Qualquer teste que falhe reprova o job.
- `build.yml`, manual (`workflow_dispatch`) e, para iOS, semanal (segundas às 06:00 UTC):
  - Android: `flutter build apk --debug` (Java 17), quando marcado na execução manual.
  - iOS: `flutter build ios --debug --no-codesign` em `macos-latest`, na execução manual ou no agendamento.

Os builds não usam `.env` nem segredos.

Para repetir as verificações localmente:

```bash
flutter analyze
flutter test
cd test_rules && npm ci && npm test
```

O `npm test` chama o comando `firebase`, então é preciso ter firebase-tools instalado globalmente e Java no `PATH`.

O emulador usa a porta 8080 por padrão. Se ela estiver ocupada, defina `FIRESTORE_EMULATOR_PORT` (o `npm test` gera uma config temporária com essa porta, sem alterar `firebase.json`):

```bash
FIRESTORE_EMULATOR_PORT=8091 npm test            # bash
$env:FIRESTORE_EMULATOR_PORT=8091; npm test      # PowerShell
```

## Funcionalidades

- Cadastro em duas telas (dados da conta e dados de nascimento), login e perfil armazenado no Firebase Authentication e Firestore. A conta só é criada no fim do cadastro e é desfeita se o perfil não puder ser salvo.
- Cosmos com energia lunar, horóscopo, tarot diário, check-in e rituais
- Oráculo que responde com respostas locais, sem IA externa
- Mapa astral aproximado calculado no dispositivo
- Meditação guiada, conversas persistidas localmente e leitura em voz alta
- Loja e inventário de skins, fundos e avatares zodiacais
- Agenda de rituais, constelação de amizades e envio de intenções
- Painel administrativo para consultar e filtrar usuários, ver atividade por período, popular os cristais e publicar o catálogo da loja

## Documentação

- `docs/architecture/overview.md`: visão geral da arquitetura, das coleções do Firestore e das decisões.
- `docs/architecture/restructuring.md`: análise da arquitetura atual e proposta de reestruturação (feature-first leve, repositórios por agregado).
- `docs/plans/reestruturacao-etapas-1-a-3.md`: plano de migração em etapas (o nome é histórico; o arquivo registra também as etapas 4 a 6 e o backlog). As etapas 1 a 8 estão na branch (a 8 reorganizou `lib/` em `app/`, `core/`, `features/` e `shared/`).
- `docs/architecture/step4-repositories.md`: etapa 4, divisão do `UserRepository` em repositórios por agregado (concluída na branch).
- `docs/architecture/step5-typed-writes.md`: etapa 5, escritas tipadas no perfil e `EquipSlot` no equipar e na compra (concluída na branch; a atomicidade entre `users` e `publicProfiles` continua pendente).
- `docs/architecture/step6-auth.md`: etapa 6, `AuthRepository`, cadastro com desfazimento, senha fora da navegação e Firebase fora das telas (implementada na branch, sem commit; aguarda revisão do `reviewer-consultor`).
- `docs/architecture/step7-data-models.md`: etapa 7, separação de `data/` e `models/`, contrato único com `firestore.rules` e teste de divergência (implementada na branch, sem commit; renomes opcionais do passo 8 não feitos).
- `docs/architecture/step9-controllers.md`: etapa 9, controllers (`Notifier`) no lugar da lógica das telas, interface `ProfileRepository` e `ChatRepository` (concluída na branch).
- `docs/architecture/step10-chat-sync.md`: etapa 10, histórico do oráculo no Firestore (concluída na branch; escopo simplificado, ver `docs/decisions/2026-11-chat-sync-decisions.md`).
- Etapa 10 (chat do oráculo no Firestore) concluída; no backlog: 11 exclusão de conta, 12 aceite de amizade, 13 higiene de custo e abuso, 14 upgrade de dependências.
- `docs/decisions/2026-11-restructuring-decisions.md`: decisões de escopo sobre economia, plataformas, exclusão de conta e chat.

O projeto Flutter e suas plataformas nativas ficam na raiz. Imagens e áudios em `assets/` são recursos compartilhados do aplicativo.
