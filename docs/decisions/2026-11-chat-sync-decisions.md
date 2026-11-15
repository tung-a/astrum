# Decisões: histórico do oráculo no Firestore (etapa 10)

Data: 2026-11-14. Origem: respostas do dono do projeto às perguntas Q1 a Q7 de `docs/architecture/step10-chat-sync.md`.

## Contexto

O histórico do oráculo sai do aparelho (shared_preferences) e passa a viver em `users/{uid}/conversations`. O conteúdo é texto livre e pode ser sensível (LGPD). Não há usuários ativos: todas as contas existentes são de teste do próprio dono.

## Decisões

1. **Consentimento (Q1, opção a).** Aviso informativo único no primeiro uso do oráculo, sem recusa. O "visto" é guardado por uid em shared_preferences (flag de UI, não dado pessoal).
2. **Retenção (Q2).** As conversas ficam guardadas até o usuário apagar; sem expiração automática. O aviso diz isso.
3. **Região (Q3).** Firestore em `southamerica-east1` (São Paulo). O aviso cita a região.
4. **Sem usuários ativos (Q7 e migração).** Mudanças drásticas são permitidas e ninguém é afetado. **Não há migração do histórico local**: migrador, plano de importação e `LegacyChatStore` foram removidos (o histórico git preserva o trabalho). A discussão sobre cota na migração em massa e sobre a regra `+N` deixa de valer.
5. **Ordem e abertura (Q5).** Conversas da mais recente para a mais antiga; o oráculo abre na mais recente.
6. **Conversa longa (Q6).** Ao atingir 500 mensagens, mostra "Esta conversa atingiu o limite. Inicie uma nova conversa." (não persistido). Sem "carregar anteriores".
7. **Apagar conversa (Q4).** O botão não entra agora; o repositório já suporta `deleteConversation`/`deleteAllConversations`. Conversas além das 50 mais recentes ficam invisíveis até haver UI.

## Consequências

- Escopo menor: os passos 4 (migrador) do desenho original foram cortados; os passos 5 a 7 seguem.
- Rascunho vazio de "Nova conversa" não sobrevive a fechar o app (aceito).
- Quando existir exclusão de conta (etapa 11), as conversas poderão ser apagadas junto; até lá o aviso não promete isso.
- `firestore.rules` e `firestore.indexes.json` sem mudança.
