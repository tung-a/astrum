# Astrum — guia para o Claude

App Flutter de astrologia, tarot e espiritualidade (Riverpod, go_router, Firebase Auth + Cloud Firestore). Configuração via `--dart-define-from-file=.env`. Validação: `flutter analyze` e `flutter test`. Responda em português.

## Organização por agentes

O trabalho é dividido entre subagentes definidos em `.claude/agents/`. A sessão principal age como orquestradora: delega cada etapa ao agente do papel certo e não pula etapas.

| Papel | Agente | Modelo | Quando age |
|---|---|---|---|
| Planner | `planner` | Sonnet | rotina: quebrar features, escrever critérios de aceite |
| Planner (consultor) | `planner-consultor` | Opus | decisões cruciais de escopo ou prioridade |
| Architect | `architect` | Sonnet | estrutura, stack, modelo de dados |
| Designer | `designer` | Sonnet | telas e design system |
| Builder | `builder` | Sonnet | implementação |
| Reviewer | `reviewer` | Sonnet | revisão do dia a dia |
| Reviewer (consultor) | `reviewer-consultor` | Opus | segurança, pagamentos, dados de usuário, mudanças de arquitetura |
| QA | `qa` | Haiku | casos de teste e relatórios |
| Writer | `writer` | Haiku | README, changelog |
| DevOps | `devops` | Sonnet | pipeline e checklist de release |

## Fluxo de uma feature

1. **planner** quebra a feature e escreve critérios de aceite em `docs/plans/`. Se houver decisão crucial de escopo/prioridade → **planner-consultor**.
2. **architect** entra quando a feature cria ou altera estrutura, dependências ou modelo de dados.
3. **designer** entra quando há tela nova ou mudança no design system.
4. **builder** implementa, com testes, e roda `flutter analyze` e `flutter test`.
5. **reviewer** revisa o diff. Se tocar segurança, autenticação, Firestore, dados pessoais, loja/moedas/inventário, chaves de API ou arquitetura → **reviewer-consultor** também revisa.
6. **qa** escreve e executa casos de teste e registra o relatório em `docs/qa/`.
7. **writer** atualiza README e CHANGELOG.
8. **devops** cuida do pipeline e, em releases, do `docs/release-checklist.md`.

Os agentes Opus (consultores) são caros: use-os só nos gatilhos acima.

## Onde ficam os artefatos

- `docs/plans/` — planos e critérios de aceite
- `docs/decisions/` — decisões de escopo/prioridade
- `docs/architecture/` — decisões técnicas
- `docs/design/` — especificações de telas
- `docs/qa/` — casos de teste e relatórios

## Regras gerais

- Nunca commitar `.env`, chaves ou dados de usuários.
- Commit, push, tags e publicação só com pedido explícito.
