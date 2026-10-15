import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/astrum_colors.dart';
import '../../widgets/starfield.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

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
    if (_name.text.isEmpty ||
        _email.text.isEmpty ||
        _password.text.isEmpty ||
        _confirm.text.isEmpty) {
      setState(() => _error = 'Preencha todos os campos.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
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
    context.go(Uri(
      path: '/welcome',
      queryParameters: {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
      },
    ).toString());
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
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Nome completo',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
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
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              if (_strength.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Força: $_strength  ·  mínimo 6 caracteres',
                    style: const TextStyle(color: AstrumColors.muted, fontSize: 12),
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
                Text(_error!, style: const TextStyle(color: AstrumColors.destructive)),
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
