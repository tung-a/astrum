# Arquitetura do Astrum - visão geral

Flutter + Riverpod + go_router; Firebase Auth e Cloud Firestore (plano gratuito, sem Cloud Functions); sem IA externa (o oráculo responde com respostas locais, `localReply` em `lib/services/oracle_service.dart`); shared_preferences para dados locais.

Estrutura de `lib/`: `config/`, `core/` (infraestrutura: `core/firebase/` com `firebaseAuthProvider`, `firestoreProvider`, injetáveis em testes, e `firestore_paths.dart`, com os caminhos dos documentos), `data/` (dados estáticos), `models/`, `providers/`, `services/`, `screens/<área>/`, `theme/`, `widgets/`, `app_router.dart`, `main.dart`.

`lib/services/` (etapa 4, repositórios por agregado; `UserRepository` foi removido):

- Repositórios: `ProfileRepository` (perfil do usuário logado), `EventsRepository` (`users/{uid}/events`), `SocialRepository` (amigos, busca por e-mail e intenções), `CatalogRepository` (`shop_items`), `AdminRepository` (operações de admin).
- Economia: `EconomyRepository` é uma interface, com implementação `FirestoreEconomyRepository` (compra e check-in em transação). Todo crédito e débito de saldo passa por ela.
- Perfil público: `PublicProfileSync` grava `publicProfiles/{uid}` e é usado por `ProfileRepository` e pela economia.
- Integrações e lógica pura: `economy.dart`, `oracle_service.dart`, `chat_store.dart`, `analytics_service.dart`, `public_profile.dart`, `meditation_sounds.dart`.

## Firestore (coleções em uso)

- `users/{uid}` com subcoleções `events`, `friends`, `notifications`.
- `users/{uid}/conversations/{id}/messages/{id}`: histórico do oráculo (proposto em D9).

- Demais coleções: `shop_items` (catálogo e preço, escrita só do admin), `publicProfiles/{uid}` (nome, avatar, hash do e-mail, para busca de amigo), `analytics_events`, `cristais_propriedades`. A economia (check-in e compra) é validada só pelas regras (`firestore.rules`), com testes em `test_rules/`.

## Decisões

- [restructuring.md](restructuring.md): análise da arquitetura atual e proposta de reestruturação (feature-first leve, repositórios por agregado, migração em etapas). Plano de execução em `docs/plans/reestruturacao-etapas-1-a-3.md`; decisões do usuário em `docs/decisions/2026-11-restructuring-decisions.md`. Etapas 1 a 3 na branch; demais no backlog.
- [step4-repositories.md](step4-repositories.md): etapa 4, quebra de `UserRepository` em repositórios por agregado (Events, Social, Catalog, Economy atrás de interface, Profile, Admin) e `PublicProfileSync`; concluída, ordem de commits e fakes de teste.
- [chat-sync.md](chat-sync.md): sincronização do histórico do oráculo com o Firestore (proposto, aguardando revisão e decisões do usuário).
