import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/astrology.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/starfield.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _place = TextEditingController();
  bool _loading = false;

  String? get _previewSign {
    final parsed = parseDateString(_date.text);
    if (parsed == null) return null;
    return sunSignFromDate(parsed.day, parsed.month);
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _place.dispose();
    super.dispose();
  }

  void _maskDate(String text) {
    final cleaned = text.replaceAll(RegExp(r'\D'), '');
    var formatted = cleaned;
    if (cleaned.length > 2) {
      formatted = '${cleaned.substring(0, 2)}/${cleaned.substring(2)}';
    }
    if (cleaned.length > 4) {
      formatted =
          '${cleaned.substring(0, 2)}/${cleaned.substring(2, 4)}/${cleaned.substring(4, cleaned.length.clamp(4, 8))}';
    }
    _date.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() {});
  }

  void _maskTime(String text) {
    final cleaned = text.replaceAll(RegExp(r'\D'), '');
    var formatted = cleaned;
    if (cleaned.length > 2) {
      formatted =
          '${cleaned.substring(0, 2)}:${cleaned.substring(2, cleaned.length.clamp(2, 4))}';
    }
    _time.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  Future<void> _complete() async {
    if (widget.name.isEmpty || widget.email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados de registro perdidos. Volte e tente de novo.')),
      );
      return;
    }
    final parsed = parseDateString(_date.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha a data no formato DD/MM/AAAA')),
      );
      return;
    }
    final sign = sunSignFromDate(parsed.day, parsed.month);
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: widget.email,
        password: widget.password,
      );
      await cred.user!.updateDisplayName(widget.name);
      await ref.read(userRepositoryProvider).createProfile(
            user: cred.user!,
            name: widget.name,
            birthDate: _date.text,
            birthTime: _time.text,
            birthPlace: _place.text,
            zodiacSign: sign,
          );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Não foi possível criar a conta')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sign = _previewSign;
    return Scaffold(
      body: Starfield(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              const Icon(Icons.auto_awesome, size: 52, color: AstrumColors.amethyst),
              const SizedBox(height: 12),
              const Text(
                'Bem-vindo ao Universo',
                style: TextStyle(fontSize: 28, color: AstrumColors.cream),
              ),
              const SizedBox(height: 8),
              const Text(
                'Para alinhar suas energias, precisamos dos seus dados astrais. O signo é calculado na hora.',
                style: TextStyle(color: AstrumColors.muted),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _date,
                keyboardType: TextInputType.number,
                onChanged: _maskDate,
                decoration: const InputDecoration(
                  hintText: 'Data de nascimento (DD/MM/AAAA)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _time,
                keyboardType: TextInputType.number,
                onChanged: _maskTime,
                decoration: const InputDecoration(
                  hintText: 'Hora de nascimento (HH:MM) — opcional',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _place,
                decoration: const InputDecoration(
                  hintText: 'Cidade de nascimento — opcional',
                ),
              ),
              if (sign != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AstrumColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AstrumColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${signGlyph[sign]}  Seu Sol está em $sign · ${signElements[sign]}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AstrumColors.gold, fontSize: 16),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _loading ? null : _complete,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Nascer no Astrum'),
              ),
              TextButton(
                onPressed: () => context.go('/register'),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
