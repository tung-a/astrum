// QA etapa 6: lacunas dos casos de docs/qa/etapa-6.md que os testes existentes
// nao cobriam. Tudo com fakes; nenhum acesso a Firebase real.
import 'dart:async';

import 'package:astrum/app_router.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/models/auth_exception.dart';
import 'package:astrum/providers/app_providers.dart';
import 'package:astrum/providers/sign_up_provider.dart';
import 'package:astrum/screens/auth/login_screen.dart';
import 'package:astrum/screens/auth/welcome_screen.dart';
import 'package:astrum/services/admin_repository.dart';
import 'package:astrum/core/analytics/analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_firebase.dart';
import 'support/fake_repositories.dart';

const _dataNascimento = '01/01/2000';

Finder _campo(String hint) => find
    .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

/// Starfield anima sem parar (nada de pumpAndSettle), e o go_router leva
/// alguns frames para trocar a rota: avanca em passos fixos.
Future<void> _estabiliza(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _toque(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await _estabiliza(tester);
}

class _App {
  _App(this.container, this.router, this.authRepo);
  final ProviderContainer container;
  final GoRouter router;
  final FakeAuthRepository authRepo;
}

/// Monta o app real (routerProvider) com fakes e abre /register.
Future<_App> _pumpCadastro(WidgetTester tester) async {
  final firebaseAuth = FakeFirebaseAuth(); // deslogado
  final repos = FakeRepos();
  final authRepo = FakeAuthRepository();
  final c = ProviderContainer(overrides: [
    firebaseAuthProvider.overrideWithValue(firebaseAuth),
    authRepositoryProvider.overrideWithValue(authRepo),
    analyticsServiceProvider.overrideWithValue(AnalyticsService(
      firestore: FakeFirebaseFirestore(),
      auth: firebaseAuth,
    )),
    ...repos.overrides,
  ]);
  addTearDown(c.dispose);
  final router = c.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(routerConfig: router),
  ));
  router.go('/register');
  await _estabiliza(tester);
  return _App(c, router, authRepo);
}

/// Preenche pelo controller do campo. Com enterText em sequencia, o texto de
/// um campo cai no anterior (o foco nao migra no harness): artefato do teste,
/// nao do app. Os campos do cadastro nao tem mascara, entao atribuir basta.
void _preenche(WidgetTester tester, String hint, String valor) {
  tester.widget<TextField>(_campo(hint)).controller!.text = valor;
}

Future<void> _preencherRegister(
  WidgetTester tester, {
  String nome = 'Nova',
  String email = 'nova@x.com',
  String senha = 'segredo123',
  String confirma = 'segredo123',
}) async {
  _preenche(tester, 'Nome completo', nome);
  _preenche(tester, 'Email', email);
  _preenche(tester, 'Senha', senha);
  _preenche(tester, 'Confirmar senha', confirma);
  await tester.pump();
  await _toque(tester, find.text('Continuar para o mapa natal'));
}

Future<void> _preencherNascimento(WidgetTester tester) async {
  _preenche(tester, 'Data de nascimento (DD/MM/AAAA)', _dataNascimento);
  await tester.pump();
}

/// Perfil e login: so o que o teste precisa; sem Firebase.
Future<void> _pumpLogin(
    WidgetTester tester, FakeAuthRepository authRepo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(authRepo)],
    child: const MaterialApp(home: LoginScreen()),
  ));
  await _estabiliza(tester);
}

/// Batch cujo commit e recusado (permission-denied). Leituras e a colecao
/// delegam ao fake, para o admin chegar ao ponto de gravacao.
class _DbCommitRecusado implements FirebaseFirestore {
  _DbCommitRecusado(this.inner);
  final FakeFirebaseFirestore inner;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      inner.collection(path);

  @override
  WriteBatch batch() => _BatchRecusado();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _BatchRecusado implements WriteBatch {
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {}

  @override
  Future<void> commit() async => throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'sem permissao');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('SignUpController: envio duplicado', () {
    test('segundo submit enquanto inFlight nao chama o repositorio de novo',
        () async {
      final auth = FakeAuthRepository()..completer = Completer<void>();
      final c = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(auth)]);
      addTearDown(c.dispose);
      c.read(signUpControllerProvider.notifier).start(const SignUpDraft(
          name: 'Nova', email: 'n@x.com', password: 'segredo123'));

      Future<bool> envia() => c.read(signUpControllerProvider.notifier).submit(
          birthDate: _dataNascimento,
          birthTime: '',
          birthPlace: '',
          zodiacSign: 'Aries');

      final primeiro = envia();
      await Future<void>.delayed(Duration.zero);
      expect(await envia(), isFalse);
      expect(auth.registerCalls.length, 1);

      auth.completer!.complete();
      expect(await primeiro, isTrue);
    });
  });

  group('AdminRepository: falha de gravacao vira AdminOperationException', () {
    test('seedCrystals com commit recusado', () async {
      await expectLater(
          AdminRepository(_DbCommitRecusado(FakeFirebaseFirestore()))
              .seedCrystals(),
          throwsA(isA<AdminOperationException>()
              .having((e) => e.message, 'message', 'sem permissao')));
    });

    test('publishCatalog com commit recusado', () async {
      await expectLater(
          AdminRepository(_DbCommitRecusado(FakeFirebaseFirestore()))
              .publishCatalog(const []),
          throwsA(isA<AdminOperationException>()
              .having((e) => e.message, 'message', 'sem permissao')));
    });
  });

  group('Login: mensagens na tela (AuthException -> texto)', () {
    testWidgets('credencial invalida mostra "Email ou senha inválidos."',
        (tester) async {
      final authRepo = FakeAuthRepository()
        ..failWith = const AuthException(AuthErrorCode.invalidCredentials);
      await _pumpLogin(tester, authRepo);

      _preenche(tester, 'Email', ' a@b.c ');
      _preenche(tester, 'Senha', 'errada');
      await tester.pump();
      await _toque(tester, find.widgetWithText(FilledButton, 'Entrar'));

      expect(authRepo.signInCalls.single.email, 'a@b.c');
      expect(find.text('Email ou senha inválidos.'), findsOneWidget);
    });

    testWidgets('outra falha (rede) mostra "Não foi possível entrar."',
        (tester) async {
      final authRepo = FakeAuthRepository()
        ..failWith = const AuthException(AuthErrorCode.network);
      await _pumpLogin(tester, authRepo);

      _preenche(tester, 'Email', 'a@b.c');
      _preenche(tester, 'Senha', 'x');
      await tester.pump();
      await _toque(tester, find.widgetWithText(FilledButton, 'Entrar'));

      expect(find.text('Não foi possível entrar.'), findsOneWidget);
      expect(find.text('Email ou senha inválidos.'), findsNothing);
    });
  });

  group('Cadastro em duas telas (Register -> Welcome)', () {
    testWidgets('Register leva ao Welcome com rascunho em memoria, sem extra',
        (tester) async {
      final app = await _pumpCadastro(tester);

      await _preencherRegister(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(app.router.state.matchedLocation, '/welcome');
      // A senha nao vai para go_router (state.extra).
      expect(app.router.state.extra, isNull);
      final draft = app.container.read(signUpControllerProvider).draft!;
      expect(draft.name, 'Nova');
      expect(draft.email, 'nova@x.com');
      expect(draft.password, 'segredo123');
    });

    testWidgets('senhas diferentes nao avancam para o Welcome', (tester) async {
      final app = await _pumpCadastro(tester);

      await _preencherRegister(tester, confirma: 'outra123');

      expect(find.text('As senhas não coincidem.'), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(app.container.read(signUpControllerProvider).draft, isNull);
    });

    testWidgets('Welcome envia o cadastro com os dados do rascunho',
        (tester) async {
      final app = await _pumpCadastro(tester);
      await _preencherRegister(tester);
      await _preencherNascimento(tester);

      await _toque(tester, find.text('Nascer no Astrum'));

      final chamada = app.authRepo.registerCalls.single;
      expect(chamada.name, 'Nova');
      expect(chamada.email, 'nova@x.com');
      expect(chamada.password, 'segredo123');
      expect(chamada.birthDate, _dataNascimento);
      expect(chamada.zodiacSign, isNotEmpty);
      // Sucesso limpa o rascunho da memoria.
      expect(app.container.read(signUpControllerProvider).draft, isNull);
    });

    testWidgets(
        'falha no cadastro mostra a mensagem, mantem o rascunho e libera o botao',
        (tester) async {
      final app = await _pumpCadastro(tester);
      await _preencherRegister(tester);
      await _preencherNascimento(tester);
      app.authRepo.failWith =
          const AuthException(AuthErrorCode.profileCreationFailed);

      await _toque(tester, find.text('Nascer no Astrum'));

      expect(
          find.text('Não foi possível concluir o cadastro. Tente novamente.'),
          findsOneWidget);
      expect(app.router.state.matchedLocation, '/welcome');
      final s = app.container.read(signUpControllerProvider);
      expect(s.draft, isNotNull, reason: 'rascunho deve ficar para retentar');
      expect(s.inFlight, isFalse);
      final botao = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Nascer no Astrum'));
      expect(botao.onPressed, isNotNull);
    });

    testWidgets(
        'erro do Auth (email em uso) mostra mensagem em portugues e '
        'atalho para o login (O1)', (tester) async {
      final app = await _pumpCadastro(tester);
      await _preencherRegister(tester);
      await _preencherNascimento(tester);
      app.authRepo.failWith = const AuthException(AuthErrorCode.emailInUse,
          detail: 'The email address is already in use.');
      expect(find.text('Já tenho conta / Entrar'), findsNothing);

      await _toque(tester, find.text('Nascer no Astrum'));

      expect(
          find.text(
              'Este e-mail já tem uma conta. Entre com seu e-mail e senha.'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // SnackBar expira
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Já tenho conta / Entrar'));
      await tester.pump();
      await _toque(tester, find.text('Já tenho conta / Entrar'));
      expect(app.router.state.matchedLocation, '/login');
      expect(app.container.read(signUpControllerProvider).draft, isNull);
    });

    // BUG (QA etapa 6, ver docs/qa/etapa-6.md, achado A1): o nome so com espacos
    // passa na validacao da RegisterScreen (so checa isEmpty) e o rascunho
    // guarda ''. As regras exigem name com 1 a 100 caracteres, entao o cadastro
    // cria a conta Auth e cai no rollback. Este teste descreve o comportamento
    // esperado (corrigido: trim antes de validar).
    testWidgets('BUG A1: nome so com espacos e barrado antes de criar a conta',
        (tester) async {
      final app = await _pumpCadastro(tester);

      await _preencherRegister(tester, nome: '   ');

      expect(app.container.read(signUpControllerProvider).draft, isNull);
      expect(app.router.state.matchedLocation, '/register');
      expect(app.authRepo.registerCalls, isEmpty);
    });
  });
}
