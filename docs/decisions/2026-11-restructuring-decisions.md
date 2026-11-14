# Decisões da reestruturação (2026-11)

Origem: `docs/architecture/restructuring.md` e respostas do usuário às perguntas em aberto (seção 7 do documento).

## Contexto

O architect propôs 13 etapas de migração e levantou perguntas sobre economia, plataformas, amizade, LGPD, chat e forma de entrega. O usuário respondeu em 2026-11-14.

## Decisões

1. **Poeira Estelar por dinheiro real: futuro, fora do escopo agora.**
   - Firebase permanece no plano Spark (gratuito); sem Cloud Functions.
   - Blaze versus RevenueCat fica adiado.
   - Requisito de arquitetura: todo crédito/débito de saldo isolado em `EconomyRepository`, para trocar o executor (regras do cliente hoje, Function/servidor depois) sem mexer nas telas.
2. **Plataformas: apenas iOS e Android.** Sem web (sem reCAPTCHA, sem tratamento de persistência offline web; CI e App Check só para mobile).
3. **Amizade com aceite do destinatário: desejável.** Entra no plano em etapa posterior (mudança de modelo e de regras).
4. **Exclusão de conta (LGPD): importante.** Feita no Spark, com reautenticação e apagando subcoleções pelo cliente (sem Function). Exige mudar `allow delete` em `firestore.rules`.
5. **Sincronizar chat entre dispositivos (D9): desejável**, na etapa 10.
6. **Entrega:** branch única `feature/flutter-migration`, commits pequenos por etapa. Commit só com pedido explícito do usuário. Upgrade do Firebase (e demais dependências) só depois do refactor.

## Consequências

- Etapa 12 (upgrade) vem depois das demais e verifica só Android e iOS.
- Exclusão de conta pelo cliente não é atômica: é preciso ordem de apagamento e idempotência (retentar após falha parcial); conta Auth é apagada por último. Risco residual aceito no Spark.
- Sem Functions, o ganho de saldo continua limitado ao check-in validado por regras. Qualquer novo meio de ganho de saldo reabre a decisão Blaze/RevenueCat e deve ser escalado ao `planner-consultor`.
- Aceite de amizade altera modelo (`friends` com estado) e regras; exige `reviewer-consultor`.
- Chat no Firestore e exclusão de conta tocam dados pessoais: `reviewer-consultor` obrigatório.
- Perguntas 7 (oráculo sempre local, sem chave de IA no cliente) e 9 (rigor de testes em telas) seguem como padrão do documento: oráculo local; testes em lógica, repositórios e providers, widget test mínimo.
