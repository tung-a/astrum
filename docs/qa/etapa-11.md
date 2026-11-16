# QA da etapa 11: exclusão de dados e de conta

Data: 2026-11-16. Responsável: agente `qa`. Branch: `feature/flutter-migration`.
Escopo: `git diff c50c433..HEAD` (exclusão de conversa e histórico do oráculo, exclusão de conta, perfil ausente, esqueci minha senha, limpeza local, backup Android/iOS, regras, índice e auditoria de órfãos).
Base de critérios: `docs/architecture/step11-account-deletion.md`, `docs/release-checklist.md` (seção 6b), `scripts/audit_users.md`.

## 1. Resultado da execução

| Verificação | Resultado |
|---|---|
| `flutter analyze` (antes e depois dos testes novos) | No issues found (exit 0) |
| `flutter test` (antes dos testes novos) | 448 passaram, 0 falharam |
| `flutter test` (depois dos testes novos, suíte completa) | **451 passaram, 0 falharam** (exit 0) |
| `dart format` no arquivo novo | sem alterações |
| Testes de regras (`test_rules/`, emulador) | **não executados nesta sessão**, por instrução do dono. Última execução reportada: 60/60 na porta 8091. Nenhum arquivo de regras mudou desde então. |

Observação de execução: uma primeira rodada em segundo plano gravou saída truncada; a suíte foi repetida em primeiro plano e os números acima são dessa repetição.

Verificação estática (sem executar): `firestore.rules` (linhas 228, 236, 244, 263, 274 a 279, 306, 328, 348, 381, 399), `firestore.indexes.json` (`fieldOverrides` de `notifications.fromUid`, `COLLECTION_GROUP`), `AndroidManifest.xml` (`allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules`), `data_extraction_rules.xml`, `ios/Runner/AppDelegate.swift` (cria `Application Support/firestore` e marca `isExcludedFromBackup`), `lib/main.dart` (`Firebase.initializeApp` e depois `runPendingCacheWipe` antes de `runApp`). Todos conferem com o desenho da seção 4 e 6 da doc.

## 2. Testes adicionados

Arquivo novo: `test/features/profile/presentation/delete_account_flow_test.dart` (3 testes de widget, todos passando). Eles fecham as lacunas de widget da tela `/account/delete`:

| Teste | Critério coberto |
|---|---|
| falha no meio (conversas sem conexão): mostra "Sem conexão... O que já foi apagado continua apagado." e "Tentar de novo" conclui | Passo 3 e R1 (retomada na UI) |
| reautenticação exigida no fim: mostra "Por segurança, digite sua senha novamente..." e o Tentar de novo só repete a conta Auth | Passo 10, R5 |
| perfil ausente: a exclusão conclui pela mesma tela | D5, seção 4.4 |

Nada de produção foi alterado (`lib/`, `firestore.rules`, `test_rules/` intocados).

## 3. Mapa de critérios e passos

Legenda: **A** = teste automatizado existente; **A+** = adicionado nesta sessão; **M** = só verificação manual (checklist da seção 6); **E** = verificação estática desta sessão.

| Critério / passo (doc seção 4.2) | Cobertura | Arquivos |
|---|---|---|
| 0. Pré-condições: reautenticação (senha errada, muitas tentativas, rede, sem provedor de senha) | A | `test/features/profile/presentation/delete_account_controller_test.dart`, `test/features/auth/data/auth_repository_test.dart` |
| 0. Servidor inalcançável: aborta sem apagar nada | A | `delete_account_controller_test.dart` ("servidor inalcancavel na pre-condicao") |
| 0. `waitForPendingWrites` com prazo de 5 s | A | `test/core/storage/local_data_cleaner_test.dart` (`drainPendingWrites`) |
| 1. Flag `astrum.wipeCachePending` gravada antes de apagar dados | A | `delete_account_controller_test.dart` ("gravada antes de apagar qualquer dado") |
| 2. Batch de `users/{uid}` + `publicProfiles/{uid}`, idempotente | A | `test/account_deletion_data_test.dart` |
| 3. Conversas e mensagens paginadas (mais de 400), offline sem apagar | A | `test/features/oracle/data/firestore_chat_repository_test.dart`, `test/core/firebase/paged_delete_test.dart` |
| 4 a 8. Eventos, amigos, notificações recebidas, intenções enviadas (collection group), analytics do uid | A | `account_deletion_data_test.dart`, `test/core/analytics/analytics_delete_test.dart`, `delete_account_controller_test.dart` (ordem) |
| 9. Varredura final (conversas, eventos, amigos, notificações) | A | `delete_account_controller_test.dart` ("caminho feliz") |
| 10. Conta Auth por último; `requires-recent-login` só repete Auth; `user-not-found` é sucesso | A | `delete_account_controller_test.dart`, `auth_repository_test.dart` |
| 10. Reautenticação exigida no fim (UI) | A+ | `delete_account_flow_test.dart` |
| 11. Limpeza local: prefs mantêm só a flag; cache por flag na partida a frio; logout só marca se drenou | A | `test/core/storage/local_data_cleaner_test.dart`, `test/features/profile/presentation/sign_out_test.dart` |
| 11. Evento anônimo `account_delete_completed` após o `user.delete()` | A (parcial: confere a ordem, não o `userId == 'anonymous'`) | `delete_account_controller_test.dart` |
| Progresso `DeleteStep` ("n de 11") | A | `delete_account_controller_test.dart`, `delete_account_screen_test.dart` ("Verificando… (1 de 11)") |
| Duplo toque ignorado; PopScope na execução | A | `delete_account_controller_test.dart`, `delete_account_screen_test.dart` |
| Senha, texto e uid fora de logs e do estado | A | `delete_account_controller_test.dart` (último teste) |
| Tela: formulário, texto do que será apagado, botão só com senha, campo oculto | A | `delete_account_screen_test.dart` |
| Tela: diálogo final (cancelar não apaga; confirmar executa) | A | `delete_account_screen_test.dart` |
| Tela: senha errada com "Tentar de novo" sem novo diálogo | A | `delete_account_screen_test.dart` |
| Tela: sem conexão com "Tentar de novo" | A | `delete_account_screen_test.dart` |
| Tela: falha no meio e "Tentar de novo" | A+ | `delete_account_flow_test.dart` |
| Tela: perfil ausente com texto próprio e "Sair" | A | `delete_account_screen_test.dart` |
| Tela: perfil ausente conclui a exclusão | A+ | `delete_account_flow_test.dart` |
| D5: `watchProfile` emite `null` só com servidor; cache offline não conclui "ausente"; recriado volta a emitir | A | `test/features/profile/data/profile_missing_test.dart` |
| D5: redirect para `/account/delete` com perfil ausente, sem laço, suprimido durante a cascata | A | `test/router_test.dart` |
| Textos de erro de exclusão (`deleteAccountErrorMessage`) | A | `test/features/auth/domain/auth_models_test.dart` |
| Esqueci minha senha: pede e-mail, envia com aviso neutro, erro de rede | A | `test/features/auth/presentation/login_screen_test.dart`, `auth_models_test.dart`, `auth_repository_test.dart` |
| Banner "Sua conta foi excluída." uma vez; sem banner sem exclusão | A | `test/features/profile/presentation/sign_out_test.dart` |
| Oráculo: apagar conversa (confirma, cancela, offline, outro erro, rascunho desabilitado) | A | `test/features/oracle/presentation/oracle_screen_test.dart` |
| Oráculo: apagar tudo; `deleting` bloqueia envio; resposta em andamento recusa a exclusão | A | `test/features/oracle/presentation/chat_controller_test.dart` |
| Oráculo: aviso de privacidade aparece uma vez (texto exato de `chatNoticeBody` não é comparado) | A (parcial) | `oracle_screen_test.dart` |
| M3: interruptor "Aparecer na busca de amigos" e reversão em falha; preferência respeitada no sync | A | `account_screen_test.dart`, `test/qa_etapa_4_test.dart` |
| M1: avatar zodiacal não revela o signo | A | `test/features/profile/domain/public_profile_test.dart` |
| Remoção de `rebuildPublicProfiles` (lib e teste) | E (grep: sem ocorrências em `lib/` e `test/`) | — |
| Aceite de intenção a conta excluída: "Esta conta não está mais disponível." e amigo não removido | A | `account_controller_test.dart`, `account_deletion_data_test.dart` |
| Regras de delete do dono, perfil ausente, collection group, analytics próprio, caracterização de 575 | Regras: `test_rules/` (não executadas nesta sessão). Dart: `test/rules_contract_test.dart` cobre só constantes de contrato, não os deletes | `test_rules/firestore.rules.test.mjs` |
| Índice de `notifications.fromUid` | E (presente em `firestore.indexes.json`); estado "pronto" no Firebase: M | — |
| Android: backup desligado e regras de extração | E (manifest e XML); build e aparelho: M | — |
| iOS: `AppDelegate` exclui o cache do Firestore do backup | E (código lido); compilação e atributo no Mac: M | — |
| Ordem de `main.dart` (limpeza antes de qualquer uso do Firestore) | E; sem teste automatizado (main não é testável) | — |
| Auditoria de órfãos com Admin SDK | M (`scripts/audit_users.md` diz que o script ainda não existe) | — |
| Texto do que será apagado igual ao da doc (seção 8.2) | E (comparação visual feita: conteúdo idêntico) | `lib/features/profile/presentation/delete_account_screen.dart` |

## 4. Mapa dos riscos (seção 11 da doc)

| Risco | Tratamento verificado | Situação |
|---|---|---|
| R1 exclusão parcial | Idempotência, retomada e "Tentar de novo" (controller e widget) | Coberto automatizado; retomada real com rede caindo: M |
| R2 mensagem órfã por corrida entre aparelhos | Varredura final (controller). Resíduo de milissegundos: auditoria | Parcial; auditoria: M |
| R3 outro aparelho recria o perfil com token válido (até 1 h) | Regra `exists(users)` para criar eventos, amigos, conversas e notificações (regras); router leva à tela de exclusão | Regras em `test_rules` (não rodadas); aparelho: M; resíduo em `users`/`publicProfiles`: auditoria |
| R4 cota do Spark (`resource-exhausted`) | Mensagem de "tente mais tarde" (controller) | Coberto |
| R5 janela de reautenticação | Só o passo de Auth pede a senha de novo (controller e widget) | Coberto |
| R6 `terminate()`/`clearPersistence()` em sessão | Decisão mudou: sem `terminate()` em sessão; limpeza só na partida a frio (`local_data_cleaner_test.dart`) | Coberto; efeito real no cache: M |
| R7 regra `{path=**}/notifications` ampla | Restrita a `fromUid == auth.uid` (leitura estática); negação testada em `test_rules` | Regras em `test_rules` (não rodadas) |
| R8 apagar e recriar para resetar saldo | Caracterização (teto de 575) em `test_rules` | Não rodada nesta sessão |
| R9 esqueci a senha não reautentica | "Esqueci minha senha" implementado e testado | Coberto |
| R10 nome em lista de amigos alheia | Aviso no texto; `removeFriend` limpa quando a intenção falha | Coberto; limpeza preguiçosa real: M |
| R11 texto prometer mais que o ocorre | Texto conferido com a doc | Revisão jurídica e política de privacidade: M |

## 5. Achados (sem falha de teste)

Nenhum teste falhou. Nenhum bug bloqueante foi identificado. Itens para o dono avaliar:

1. **Divergência de texto na doc.** `docs/architecture/step11-account-deletion.md` (linhas 134 e 322) ainda diz "Esta conta não existe mais.". O código e o teste usam "Esta conta não está mais disponível." (`account_controller.dart` linha 50), e a própria seção 14 da doc já registra a mudança. Corrigir a doc (writer).
2. **Texto de falha de conexão antes da cascata.** A seção 8.2 diz que a mensagem de "Sem conexão" sempre traz "O que já foi apagado continua apagado.". O código só acrescenta essa frase quando `partial` é verdadeiro (`auth_exception.dart`, linhas 92 a 95). É uma escolha correta, mas diverge da doc.
3. **Senha permanece no campo após falha.** A doc diz que a senha é "descartada" após `run`. Na prática, o `TextEditingController` mantém o texto enquanto a tela estiver aberta, para que "Tentar de novo" funcione. Aceitável (fica só na tela, nunca em log nem em estado), mas vale registrar.
4. **Texto de reautenticação com campo preenchido.** "Por segurança, digite sua senha novamente para concluir." aparece com a senha antiga ainda no campo, e "Tentar de novo" a reutiliza. Não é bug; o usuário pode achar que precisa redigitar. Melhoria de texto opcional.
5. **Auditoria e script.** `scripts/audit_users.md` descreve, mas o script não existe. Continua pendência de release (checklist 6b, item e).

## 6. O que não foi testado, e por quê

- **Testes de regras (`test_rules/`)**: não executados nesta sessão, por instrução do dono (já passaram 60/60 na porta 8091 e nenhum arquivo de regras mudou). Não se usou emulador compartilhado.
- **Persistência real do cache do Firestore e `clearPersistence()` na partida a frio**: o SDK real não roda em teste unitário; coberto só pelo fake e pela lógica de flag. Exige aparelho.
- **Modo avião no meio da cascata**: os testes simulam a falha com exceções injetadas, não a rede real. Exige aparelho.
- **Compilação iOS e `isExcludedFromBackup` do diretório do Firestore**: exige Mac/Xcode. O caminho `Application Support/firestore` é a suposição do código e precisa ser confirmado no aparelho.
- **Backup Android (`dataExtractionRules`)**: verificado só estaticamente. Exige build e inspeção do manifest mesclado.
- **`main.dart` (ordem da limpeza)**: sem teste automatizado; verificado por leitura.
- **Estado "pronto" do índice e regras implantadas no Firebase**: depende do projeto real. Exige o console.
- **Auditoria de órfãos com Admin SDK**: script inexistente; exige credencial local do dono (não commitar).
- **Navegação até o login após o sucesso**: o redirect é coberto por `router_test.dart` em geral; a sequência completa na tela não é testada.
- **Conteúdo exato do aviso do oráculo (`chatNoticeBody`)**: só a presença é testada.
- **Cota diária real do Spark e tempo de `user.delete()` com janela de reautenticação**: dependem de conta real.

## 7. Checklist manual para o dono (aparelho e console)

Ordem sugerida: primeiro o deploy (itens 1 e 2), depois os fluxos em aparelho (3 a 10) e por último o Mac (11). Use contas de teste; não há usuários ativos.

1. **Implantar catálogo, índices e regras, nessa ordem** (release-checklist 6b, a). Conferir no console, em "Firestore > Índices", que o índice de `notifications` com `fromUid` (escopo de coleção de grupo) está **pronto**, não "criando". Só então distribuir o cliente.
2. **Testes de regras opcionais** (se quiser repetir): `FIRESTORE_EMULATOR_PORT=<porta livre> node run-tests.mjs` em `test_rules/`, sem emulador em uso. Não rodar com o emulador de outra sessão.
3. **Exclusão de conta completa (Android e iOS)**: criar conta de teste, completar perfil, criar pelo menos uma conversa com mensagem, um evento, um amigo e uma intenção enviada a outra conta de teste. Excluir pelo Perfil > "Excluir minha conta". Conferir no console: `users/{uid}`, `publicProfiles/{uid}`, subcoleções, `analytics_events` com o `userId` do uid, e o usuário em Authentication. Na outra conta, a intenção recebida de quem excluiu deve ter sumido. A mensagem final deve ser o login com "Sua conta foi excluída.".
4. **Modo avião no meio e retomada**: iniciar a exclusão com várias conversas e ligar o modo avião durante "Apagando conversas…". Deve aparecer "Sem conexão. Conecte-se e toque em Tentar de novo. O que já foi apagado continua apagado.". Desligar o modo avião, tocar em "Tentar de novo" e conferir que termina e que nada reaparece. Repetir com o modo avião logo no início (antes de qualquer dado): deve mostrar só "Sem conexão. Conecte-se e toque em Tentar de novo." e nada deve ser apagado.
5. **Senha errada**: com dados presentes, digitar senha errada. Deve aparecer "Senha incorreta. Nada foi apagado." e nada deve sumir no console.
6. **Perfil ausente**: no console, apagar manualmente `users/{uid}` de uma conta de teste (ou interromper a exclusão logo após o passo do perfil). Reabrir o app: deve cair em "Excluir conta" com o texto "Esta conta não tem um perfil completo...". Excluir e conferir a limpeza. Também: antes de excluir, o botão "Sair" deve aparecer.
7. **Criar conta logo depois, na mesma sessão**: concluir uma exclusão e, sem fechar o app, cadastrar uma nova conta com outro e-mail. O cadastro deve funcionar e o Firestore deve gravar o perfil. Depois, cadastrar com o e-mail excluído: deve estar liberado (caso do perfil ausente).
8. **Apagar uma conversa e todo o histórico (menu do Oráculo)**: apagar uma conversa (conferir no console que a conversa e as mensagens somem e que a lista do app troca de conversa). Apagar todo o histórico (conferir a coleção vazia). Com modo avião, a mensagem deve ser "Sem conexão. Nada foi apagado...". Em um segundo aparelho logado na mesma conta, a lista deve atualizar. Com uma resposta do oráculo em andamento, "Apagar" deve ser recusado.
9. **Esqueci minha senha**: na tela de login, informar o e-mail de uma conta de teste, enviar e conferir o e-mail de redefinição. Redefinir e entrar com a nova senha. Com e-mail inexistente, a mensagem deve ser neutra (não revelar se a conta existe). Sem rede, aparece erro de conexão.
10. **Cache do Firestore some na partida a frio**: (a) logado, com conversas abertas, sair com rede e fechar o app de vez (não só minimizar); reabrir, entrar com outra conta de teste e conferir que nenhuma conversa da conta anterior aparece. (b) Exclusão concluída, forçar o fechamento do app (force-stop) e reabrir: a conversa não deve aparecer localmente. (c) Logout sem rede: o cache é mantido de propósito (documentado); confirmar esse comportamento.
11. **iOS em Mac**: (a) compilar (`flutter build ios --no-codesign` ou pelo Xcode) e confirmar que `AppDelegate.swift` compila; (b) abrir o app e conferir que inicia normalmente; (c) confirmar que a pasta `Library/Application Support/firestore` existe e está marcada como excluída do backup (por exemplo, pelo código de teste ou pelo Xcode); (d) confirmar que `UserDefaults` continua no backup e contém só chaves `astrum.*`.
12. **Android**: gerar o APK, conferir no manifest mesclado (`build/app/intermediates`) que `android:allowBackup="false"`, `android:fullBackupContent="false"` e `android:dataExtractionRules` estão presentes; instalar e abrir.
13. **Auditoria de órfãos (Admin SDK)**: seguir `scripts/audit_users.md`: listar `users` sem usuário em Authentication; subcoleções órfãs; mensagens sem conversa; `publicProfiles` sem Auth; `analytics_events` de uids excluídos. Usar a credencial local do dono, sem commitá-la. O script ainda não existe; a verificação é manual até lá.
14. **Política de privacidade e nota para a App Store** (release-checklist 6b, c, d, f): lista de dados, retenção, Google/Firebase como operador, fontes (IP exposto ao Google) e o caminho de exclusão ("Oráculo > menu" e "Perfil > Excluir minha conta").
15. **Textos**: conferir na tela que o texto de exclusão, os erros e o aviso do Oráculo coincidem com a seção 8.2 e 3.1 da doc (a diferença de "não existe mais" é apenas na doc, ver achado 1).

## 8. Conclusão

A etapa 11 está coberta por testes automatizados nas camadas de dados, controller e widget (451 testes passando, análise limpa). As lacunas de widget da exclusão de conta foram fechadas com 3 testes novos. O que falta é verificação em aparelho (modo avião, cache, perfil ausente real), iOS em Mac, implantação e índice no Firebase, a auditoria de órfãos e a rodada final de `test_rules/`. Não há bloqueio por falha de teste; a release continua bloqueada pelos itens manuais da seção 6b, como previsto.
