import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/core/widgets/starfield.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/auth/presentation/sign_up_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Reentrar no cadastro descarta rascunho anterior (nao durante envio).
    // Adiado com Future(...) porque o Riverpod proibe alterar um provider
    // durante o build/initState da arvore de widgets.
    Future(() {
      if (!mounted) return;
      final c = ref.read(signUpControllerProvider.notifier);
      if (!ref.read(signUpControllerProvider).inFlight) c.clear();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _strength {
    if (_password.text.isEmpty) return '';
    if (_password.text.length < 6) return 'Fraca';
    if (_password.text.length < 10) return 'Média';
    return 'Forte';
  }

  void _next() {
    setState(() => _error = null);
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty ||
        email.isEmpty ||
        _password.text.isEmpty ||
        _confirm.text.isEmpty) {
      setState(() => _error = 'Preencha todos os campos.');
      return;
    }
    final lengthError = signUpLengthError(name: name, email: email);
    if (lengthError != null) {
      setState(() => _error = lengthError);
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Email inválido.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'As senhas não coincidem.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'A senha deve ter pelo menos 6 caracteres.');
      return;
    }
    ref.read(signUpControllerProvider.notifier).start(SignUpDraft(
          name: name,
          email: email,
          password: _password.text,
        ));
    context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Starfield(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              const Text(
                'Crie sua conta',
                style: TextStyle(fontSize: 28, color: AstrumColors.cream),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                maxLength: SignUpLimits.name,
                decoration: const InputDecoration(
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Nome completo',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                maxLength: SignUpLimits.email,
                decoration: const InputDecoration(
                  counterText: '',
                  prefixIcon: Icon(Icons.mail_outline),
                  hintText: 'Email',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: 'Senha',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              if (_strength.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Força: $_strength  ·  mínimo 6 caracteres',
                    style: const TextStyle(
                        color: AstrumColors.muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Confirmar senha',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: AstrumColors.destructive)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _next,
                child: const Text('Continuar para o mapa natal'),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Já tenho conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
