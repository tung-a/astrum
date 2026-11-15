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
2. [ ] **Depois**, implantar as regras: `firebase deploy --only firestore`.

Avisos:
- Nunca desativar (`active: false`) nem apagar os avatares `pfp_zodiac_*` em `shop_items`. Sem eles, quem se cadastra com signo nao consegue criar o perfil.
- Publicar as regras antes do catalogo bloqueia compras e cadastros.

## 4. Auditoria de perfis antigos (antes do deploy das regras)
- [ ] Verificar usuarios com `equipped` ou `inventory` fora do catalogo: eles ficam travados em escritas depois das novas regras.
- [ ] A auditoria e um script com Admin SDK que o responsavel roda com a credencial local. **Nao commitar a credencial.**
- [ ] PENDENCIA: o script ainda nao existe; ver `scripts/audit_users.md` (apenas descreve o que checar).

## 5. Perfis publicos
- [ ] Recriar perfis publicos pelo painel (botao "Recriar perfis publicos").

## 6. Testes em dispositivo
- [ ] Compra na loja (saldo debitado, item no inventario).
- [ ] Check-in diario.
- [ ] Busca de amigo.
- [ ] Meditacao (audio toca e para corretamente).

## 6b. Privacidade e LGPD (BLOQUEANTE)
- [ ] **BLOQUEANTE:** UI de exclusao de conversa/historico do oraculo e exclusao de conta funcionando, incluindo os dados em `users/{uid}/conversations` (LGPD art. 18, VI). Sem isso, nao publicar.
- [ ] Quando a exclusao existir, revisar o texto do aviso de privacidade do oraculo (`chatNoticeBody` em `lib/features/oracle/presentation/oracle_screen.dart`): remover o "em breve" e descrever o que de fato acontece.

## 7. Seguranca do repositorio
- [ ] `.env` nao esta no git: `git ls-files .env` deve retornar vazio e `.env` deve estar no `.gitignore`.
- [ ] Nenhuma chave ou credencial (service account) no diff da release.

## 8. Builds, plataformas e fechamento
- [ ] Builds gerados (web, apk) com `--dart-define-from-file=.env`.
- [ ] Icones conferidos.
- [ ] Smoke test nas plataformas-alvo.
- [ ] Tag criada (somente por pedido explicito do responsavel).
