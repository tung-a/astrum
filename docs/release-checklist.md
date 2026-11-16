# Checklist de release do Astrum

Marque cada item na ordem. Nao pule etapas.

## 1. Versao e changelog
- [ ] Versao atualizada em `pubspec.yaml` (`version: x.y.z+build`).
- [ ] `CHANGELOG.md` atualizado com as mudancas da versao.

## 2. Validacao
- [ ] `flutter analyze` sem problemas.
- [ ] `flutter test` verde.
- [ ] `npm test` em `test_rules` verde (testes das regras do Firestore, com emulador).

## 3. Deploy do Firestore (ORDEM OBRIGATORIA)
1. [ ] **Primeiro**, publicar o catalogo: o admin clica em "Publicar catalogo" no painel.
2. [ ] **Depois**, implantar indices e regras: `firebase deploy --only firestore` (publica `firestore.indexes.json` e `firestore.rules`). O indice de collection group de `notifications.fromUid` (etapa 11) leva um tempo para ser construido: conferir no console que esta **pronto** antes de seguir.
3. [ ] **So entao** distribuir o cliente (a exclusao de conta usa o indice e as regras novas; sem eles a etapa "intencoes enviadas" falha).

Avisos:
- Nunca desativar (`active: false`) nem apagar os avatares `pfp_zodiac_*` em `shop_items`. Sem eles, quem se cadastra com signo nao consegue criar o perfil.
- Publicar as regras antes do catalogo bloqueia compras e cadastros.

## 4. Auditoria de perfis antigos (antes do deploy das regras)
- [ ] Verificar usuarios com `equipped` ou `inventory` fora do catalogo: eles ficam travados em escritas depois das novas regras.
- [ ] A auditoria e um script com Admin SDK que o responsavel roda com a credencial local. **Nao commitar a credencial.**
- [ ] PENDENCIA: nao ha script; a auditoria e um roteiro manual em `scripts/audit_users.md` (Admin SDK ou console).

## 5. Perfis publicos
Removido na etapa 11: o botao "Recriar perfis publicos" (`rebuildPublicProfiles`) foi apagado. Cada cliente grava o proprio perfil publico; nao ha migracao a fazer.

## 6. Testes em dispositivo
- [ ] Compra na loja (saldo debitado, item no inventario).
- [ ] Check-in diario.
- [ ] Busca de amigo.
- [ ] Meditacao (audio toca e para corretamente).

## 6b. Privacidade e LGPD (BLOQUEANTE)
- [x] **BLOQUEANTE (etapa 11 concluida e testada; a aguardar a verificacao manual abaixo e o deploy de regras e indice):** UI de exclusao de conversa/historico do oraculo (menu do Oraculo) e exclusao de conta (Perfil > "Excluir minha conta", rota `/account/delete`), incluindo `users/{uid}/conversations` (LGPD art. 18, VI). Cobertura automatizada: testes de regras (`test_rules`), controller, widget e repositorios. **Nao publicar sem fechar a verificacao manual em aparelho:**
  - [ ] (a) Implantar indice e regras antes do cliente (ordem: catalogo, indices, regras; ver secao 3).
  - [ ] (b) Testar em aparelho Android e iOS: exclusao com sucesso; modo aviao no meio (retomada com "Tentar de novo"); perfil ausente (conta sem perfil cai na tela de exclusao); criar conta nova logo depois da exclusao, na mesma sessao.
  - [ ] (c) Validar a limpeza local: o cache do Firestore e limpo na proxima partida a frio (flag `astrum.wipeCachePending`; nao ha `terminate()` em sessao). Conferir que depois de excluir/sair e reabrir o app nao resta conversa no aparelho. Se um dia se adotar `terminate()` + `clearPersistence()` na mesma sessao, validar no aparelho que o Firestore continua usavel (cadastrar nova conta em seguida).
  - [ ] (d) iOS (nao testavel no Windows): conferir em Mac que `AppDelegate.swift` exclui `Library/Application Support/firestore` do backup (`isExcludedFromBackup`) e que o app abre normalmente; UserDefaults continua no backup (so a flag e chaves `astrum.*`).
  - [ ] (e) Auditoria de orfaos com Admin SDK (`users` e subcolecoes sem usuario Auth; mensagens orfas da corrida entre aparelhos; `users/{uid}` recriado por outro aparelho com token ainda valido): roteiro manual em `scripts/audit_users.md`.
  - [ ] (f) Politica de privacidade atualizada: lista de dados, retencao, Google/Firebase como operador, fontes (google_fonts expoe o IP ao Google) e como excluir (menu do Oraculo e Perfil > Excluir minha conta).
  - [ ] (h) Android: `flutter build apk --debug` compila com `data_extraction_rules.xml` (`path="."` nos excludes); conferir backup/transferencia em aparelho. iOS: NSUserDefaults seguem no backup do iCloud (so flags `astrum.*`, sem dado pessoal).
  - [ ] (i) Regras: create de `events` e `friends` exige o perfil; rodar `test_rules` antes de implantar (publicar regras antes do cliente).
  - [ ] (g) Nota para a revisao da App Store: "Perfil > Excluir minha conta".
- [x] Aviso de privacidade do oraculo (`chatNoticeBody`) revisado: sem "em breve", descreve apagar uma conversa, todo o historico e a exclusao de conta.
- [ ] Suporte: quem esqueceu a senha usa "Esqueci minha senha" na tela de login; sem a senha nao ha como reautenticar a exclusao.

## 7. Seguranca do repositorio
- [ ] `.env` nao esta no git: `git ls-files .env` deve retornar vazio e `.env` deve estar no `.gitignore`.
- [ ] Nenhuma chave ou credencial (service account) no diff da release.

## 8. Builds, plataformas e fechamento
- [ ] Builds gerados (web, apk) com `--dart-define-from-file=.env`.
- [ ] Icones conferidos.
- [ ] Smoke test nas plataformas-alvo.
- [ ] Tag criada (somente por pedido explicito do responsavel).
