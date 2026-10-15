# Astrum (Flutter)

Migração do app Expo/React Native para Flutter, com oráculo de IA que **não depende do Gemini pago**.

## O que mudou

- **Stack**: Flutter + Riverpod + GoRouter + Firebase Auth/Firestore
- **IA**: Groq (tier gratuito, opcional) → Pollinations (sem chave) → oráculo local
- **Mapa astral**: calculado no dispositivo (não pede JSON à IA)
- **Tema**: cosmos escuro por padrão, tipografia Cinzel + Outfit
- **Novidades**: fase da lua, energia do dia, check-in diário de Poeira Estelar

O app React Native permanece na raiz do repositório nesta branch, como referência.

## Pré-requisitos

1. [Instalar o Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
2. Firebase já usado pelo app antigo (mesmas coleções `users`, `events`, `notifications`)

## Rodar

Na pasta `flutter/`:

```bash
flutter create . --project-name astrum --org com.astrum.app --platforms=android,ios,web
flutter pub get
flutter run --dart-define-from-file=.env
```

O `flutter create .` só gera as pastas nativas (`android/`, `ios/`, `web/`) sem sobrescrever `lib/`.

Variáveis (as mesmas do Expo, sem o prefixo `EXPO_PUBLIC_`):

```
FIREBASE_API_KEY
FIREBASE_AUTH_DOMAIN
FIREBASE_PROJECT_ID
FIREBASE_STORAGE_BUCKET
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_APP_ID
GROQ_API_KEY   # opcional
```

## Oráculo

1. Se `GROQ_API_KEY` existir → Llama 3.3 70B ( Groq, uso gratuito com cota )
2. Senão → [Pollinations](https://text.pollinations.ai/) sem chave
3. Se a rede falhar → respostas locais de astrologia/tarot/lua

Horóscopo e tarot do dia também usam o dicionário local quando a IA não responde, então o Cosmos continua útil offline.
