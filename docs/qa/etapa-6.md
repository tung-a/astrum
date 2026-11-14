# QA da etapa 6 (AuthRepository, cadastro com rollback, AdminRepository)

Base: [step6-auth.md](../architecture/step6-auth.md) e pendências da etapa 11 em [o plano](../plans/reestruturacao-etapas-1-a-3.md).

## Resultado

| Verificação | Resultado |
|---|---|
| `flutter analyze` | Sem problemas |
| `flutter test` | 147 passaram, 0 pulados, 0 falhas (linha de base: 136) |
| `npm test` em `test_rules/` (porta 8091) | 38/38 passaram |
| `firestore.rules` e `test_rules/` | Sem diff |

- As regras rodaram com `FIRESTORE_EMULATOR_PORT=8091`. A porta 8080 não foi usada. A confirmação veio do processo (java com `--port 8091`), porque a saída do `npm` não imprime a porta.
- O emulador ficou vivo depois do `emulators:exec` (comportamento do `firebase-tools` no Windows). O qa encerrou somente o PID que ele iniciou (linha de comando com `--port 8091`). Depois: nenhum listener na 8091.
- Teste novo: `test/qa_etapa_6_test.dart` (10 ativos e 1 pulado).

## Mapeamento critério → teste

Legenda: OK = teste existente; NOVO = adicionado pelo qa; MAN = manual; LAC = lacuna.

**FirebaseAuthRepository** (`auth_repository_test.dart`, `auth_models_test.dart`)
- signIn com sucesso e `invalid-credential`: OK. Demais códigos sem vazar `FirebaseAuthException`: OK.
- register com sucesso (ordem createUser, updateDisplayName, createProfile; sem delete): OK.
- `createProfile` falha → delete 1x, signOut, `rollbackFailed` falso: OK. `updateDisplayName` falha: OK. `delete` também falha → `rollbackFailed` verdadeiro: OK.
- `createProfile` nunca completa → só signOut, sem delete (risco 4b): OK.
- Erro definitivo do Firestore (`permission-denied`) → rollback: OK.
- `email-already-in-use` e `weak-password`: OK. Senha fora de `AuthException` e de `SignUpData.toString`: OK. Senha fora de `debugPrint`: LAC (revisão estática: só código/runtimeType são logados).
- Mensagens de login e cadastro, inclusive timeout e rollbackFailed: OK. Tela de login: NOVO.

**ProfileRepository.createProfile** (`repositories_firestore_test.dart`)
- Grava `users` e `publicProfiles`: OK parcial. Payload completo contra as regras: LAC. Atomicidade do batch não é provada, porque o fake não escreve nada em commit falho.

**SignUpController e router**
- `inFlight` (sucesso, falha, exceção inesperada): OK. Envio duplicado: NOVO.
- `/welcome` sem rascunho: OK. `inFlight` segurando usuário logado: OK. Sem `extra` com senha: NOVO.
- Fluxo Register → Welcome em widget: NOVO. Falha na tela (mensagem, rascunho mantido, botão habilitado) e e-mail em uso: NOVO.

**Admin**
- `planCatalogPublish`, `publishCatalog`, `seedCrystals`, `summarizeAnalytics`, `watchAnalyticsEvents`: OK. Commit recusado vira `AdminOperationException`: NOVO.
- `rebuildPublicProfiles`: caracterização do M1 OK; conversão de erro LAC (o fake não aplica regras).
- Telas admin sem `cloud_firestore`: grep estático OK; widget LAC.

**Regras e constantes**
- `SignUpLimits` igual ao `profileShapeOk` (name 100, email 254, birthDate 20, birthTime 10, birthPlace 200): OK.
- `npm test` não cobre o payload exato do batch de `createProfile`: LAC.

**Riscos (seção 9 do desenho)**: 1 (inFlight preso) OK; 2 (dados pessoais e regras) parcial; 3 (conta Auth órfã offline) e 4 (commit ambíguo) ficam para a etapa 11; 4b (timeout sem delete) OK; 5 (Voltar do Android durante o cadastro) e 6 (mensagens em inglês do Firebase) manuais.

## Bugs e observações

- **A1 (baixo a médio):** nome só com espaços passa na RegisterScreen (checa só `isEmpty`), vira `name ''` no rascunho, cria a conta Auth e falha nas regras (`name >= 1`), caindo no rollback com "Não foi possível concluir o cadastro. Tente novamente." sem explicar o motivo. **CORRIGIDO:** `trim` antes da validação em `_next`; teste `BUG A1` em `qa_etapa_6_test.dart` agora ativo.
- **O1 (UX, verificar manualmente):** após timeout ou `rollbackFailed`, o usuário fica deslogado em `/welcome` com o rascunho. Tentar de novo dá `email-already-in-use` com texto em inglês do Firebase, e a mensagem de timeout manda "entrar com e-mail e senha", mas `/welcome` não tem atalho para o login. **CORRIGIDO:** `signUpErrorMessage` mapeia `emailInUse` para "Este e-mail já tem uma conta. Entre com seu e-mail e senha." e a WelcomeScreen mostra "Já tenho conta / Entrar" (limpa o rascunho e vai a `/login`) após erro de cadastro. Verificação manual ainda recomendada.
- **Divergência de doc:** `step6-auth.md` 8.2 dizia "timeout → rollback (fakeAsync)"; o código e o risco 4b fazem só signOut, com timeout real de 50 ms nos testes. O código segue o 4b.

## Não testado

- Logout e telas admin como widget (estado de providers grande; manual).
- Falha de rede real e timeout de 20 s (cobertos com 50 ms e pelo checklist manual).
- Exclusão de conta, reautenticação e recuperação de perfil ausente: etapa 11.
- Atomicidade real do batch e regras do payload de `createProfile`: exigiria teste no emulador.

## Checklist manual

1. Cadastro completo: conferir `users/{uid}` e `publicProfiles/{uid}` no console (campos, wallet 500, role user, avatar zodiacal).
2. Falha de rede: modo avião depois da tela 2 (Auth criado), esperar o timeout de 20 s, conferir a mensagem e se a conta Auth fica (esperado: fica, sem delete).
3. Login com senha errada: "Email ou senha inválidos."; sem rede: "Não foi possível entrar.".
4. Logout: Sair volta a `/login`, e `/app/*` não reabre sem login.
5. Admin: popular cristais, publicar catálogo (preço e `active` dos itens existentes preservados) e trocar o período de analytics.
6. Limites: nome 100, e-mail 254, cidade 200, hora 10; data no formato DD/MM/AAAA.
7. Voltar desabilitado durante o envio; matar o app entre as telas e reabrir (deve ir a `/login`, nunca a `/welcome`).
8. Android: Voltar durante o cadastro (risco 5) e nome só com espaços (A1).
9. Repetir o cadastro após timeout ou `rollbackFailed` (O1): conferir a mensagem de e-mail em uso e a saída para o login.
