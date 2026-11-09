# Astrum ✨

Astrum é um aplicativo de astrologia, tarot e espiritualidade feito em Flutter para Android, iOS, Web, Windows, macOS e Linux.

## Requisitos

- Flutter SDK estável instalado e disponível no `PATH`
- Uma configuração Firebase para Authentication e Cloud Firestore

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
flutter build web --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
```

## Funcionalidades

- Cadastro, login e perfil armazenado no Firebase Authentication e Firestore
- Cosmos com energia lunar, horóscopo, tarot diário, check-in e rituais
- Oráculo que responde com respostas locais, sem IA externa
- Mapa astral aproximado calculado no dispositivo
- Meditação guiada, conversas persistidas localmente e leitura em voz alta
- Loja e inventário de skins, fundos e avatares zodiacais
- Agenda de rituais, constelação de amizades e envio de intenções
- Painel administrativo para consultar e filtrar usuários

O projeto Flutter e suas plataformas nativas ficam na raiz. Imagens e áudios em `assets/` são recursos compartilhados do aplicativo.
