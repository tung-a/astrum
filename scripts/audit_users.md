# Roteiro manual de auditoria com Admin SDK (nao ha script)

Este arquivo e um **roteiro manual**: nenhum script foi escrito. Quem executa monta a consulta com o Admin SDK (ou o console) seguindo os itens abaixo.

Roda o responsavel, com a credencial local de service account. **Nao commitar a credencial.** Plano gratuito (Spark): sem Cloud Functions, entao estas verificacoes sao manuais e periodicas.

## 1. Perfis antigos (antes do deploy das regras)
- Usuarios com `equipped` ou `inventory` fora do catalogo `shop_items` (ficam travados em escritas depois das novas regras).

## 2. Orfaos da exclusao de conta (etapa 11)
- `users/{uid}` (e subcolecoes `events`, `notifications`, `conversations/messages`) cujo `uid` nao existe mais no Firebase Auth.
- Mensagens orfas (`users/{uid}/conversations/{id}/messages` sem a conversa): corrida entre aparelhos do mesmo usuario durante a exclusao.
- `users/{uid}` recriado por outro aparelho depois de `user.delete()` (token valido por ate 1 h) e `publicProfiles/{uid}` sem usuario Auth.
- `friendships/{pairId}` cujo `uids` contem um uid que nao existe mais no Firebase Auth (a cascata apaga as relacoes do uid; sobra so em falha parcial ou token de 1 h).
- `users/*/friends` (modelo antigo, removido na etapa 12): apagar tudo, sem migrar. As regras negam o caminho, entao so o Admin SDK ou o console alcanca.
- `analytics_events` com `userId` de contas excluidas (o evento anonimo `account_delete_completed` fica).
- Remocao: `firebase firestore:delete --recursive` ou Admin SDK; so apos conferir que o uid nao existe no Auth.
