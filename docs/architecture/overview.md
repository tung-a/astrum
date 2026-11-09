# Arquitetura do Astrum - visão geral

Flutter + Riverpod + go_router; Firebase Auth e Cloud Firestore (plano gratuito, sem Cloud Functions); sem IA externa (o oráculo responde com respostas locais, `localReply` em `lib/services/oracle_service.dart`); shared_preferences para dados locais.

Estrutura de `lib/`: `config/`, `data/` (dados estáticos), `models/`, `providers/`, `services/` (repositórios e integrações), `screens/<área>/`, `theme/`, `widgets/`, `app_router.dart`, `main.dart`.

## Firestore (coleções em uso)

- `users/{uid}` com subcoleções `events`, `friends`, `notifications`.
- `users/{uid}/conversations/{id}/messages/{id}`: histórico do oráculo (proposto em D9).

## Decisões

- [chat-sync.md](chat-sync.md): sincronização do histórico do oráculo com o Firestore (proposto, aguardando revisão e decisões do usuário).
