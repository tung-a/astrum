# Dívida econômica: tolerância de ±1 dia no check-in (2026-11)

Status: registrada, **não implementada** (decisão: não corrigir agora).

## Contexto

A regra do check-in diário aceita a data do dia anterior, de hoje ou do dia seguinte (tolerância de ±1 dia, por causa de fuso e relógio do aparelho). Como o perfil pode ser apagado e recriado (exclusão de conta, etapa 11) e o saldo inicial é exatamente 500, a tolerância permite acumular até 3 check-ins seguidos na criação da conta.

## Problema

Teto de **575** de Poeira Estelar por criação de conta (500 iniciais + 3 check-ins seguidos pela tolerância). Hoje isso está coberto por teste de caracterização em `test_rules/firestore.rules.test.mjs` ("economia: apos apagar e recriar o perfil, o teto e 575"). O impacto é pequeno (não é crédito ilimitado), mas é um ganho que a regra não pretendia dar.

## Correção futura sugerida

- Exigir `newCheck() >= dateStr(request.time - 1d)` (nunca uma data mais antiga que ontem, relativa ao horário do servidor).
- Ao criar a conta, aceitar só a data de hoje no campo do check-in.
- Atualizar o teste de caracterização (o teto volta a 500 mais um check-in) e o `docs/release-checklist.md`.

## Decisão

Não implementar agora; revisar antes de a economia ter valor real (loja com pagamento) ou se houver abuso observado. Mudança em regras de economia exige `reviewer-consultor`.
