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

## Funcionalidades

- Cadastro, login e perfil armazenado no Firebase Authentication e Firestore
- Cosmos com energia lunar, horóscopo, tarot diário, check-in e rituais
- Oráculo que responde com respostas locais, sem IA externa
- Mapa astral aproximado calculado no dispositivo
- Meditação guiada, conversas persistidas localmente e leitura em voz alta
- Loja e inventário de skins, fundos e avatares zodiacais
- Agenda de rituais, constelação de amizades e envio de intenções
- Painel administrativo para consultar e filtrar usuários

## Documentação

- `docs/architecture/overview.md`: visão geral da arquitetura, das coleções do Firestore e das decisões.
- `docs/architecture/restructuring.md`: análise da arquitetura atual e proposta de reestruturação (feature-first leve, repositórios por agregado).
- `docs/plans/reestruturacao-etapas-1-a-3.md`: plano de migração em etapas. As etapas 1 a 3 (CI, correções de custo com `select` e redirect, providers de infraestrutura) estão na branch.
- `docs/architecture/step4-repositories.md`: etapa 4, divisão do `UserRepository` em repositórios por agregado (concluída na branch).
- `docs/architecture/step5-typed-writes.md`: etapa 5, escritas tipadas no perfil e `EquipSlot` no equipar e na compra (concluída na branch; a atomicidade entre `users` e `publicProfiles` continua pendente).
- As demais etapas estão no backlog.
- `docs/decisions/2026-11-restructuring-decisions.md`: decisões de escopo sobre economia, plataformas, exclusão de conta e chat.

O projeto Flutter e suas plataformas nativas ficam na raiz. Imagens e áudios em `assets/` são recursos compartilhados do aplicativo.
