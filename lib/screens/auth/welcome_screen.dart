import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/models/auth_exception.dart';
import 'package:astrum/models/sign_up_data.dart';
import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/providers/sign_up_provider.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/core/widgets/starfield.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _place = TextEditingController();
  bool _loading = false;
  bool _signUpFailed = false;

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
    final parsed = parseDateString(_date.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha a data no formato DD/MM/AAAA')),
      );
      return;
    }
    final lengthError = signUpLengthError(
      birthDate: _date.text,
      birthTime: _time.text,
      birthPlace: _place.text,
    );
    if (lengthError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(lengthError)));
      return;
    }
    final sign = sunSignFromDate(parsed.day, parsed.month);
    // Le antes do await: o widget pode ser desmontado durante o cadastro.
    final analytics = ref.read(analyticsServiceProvider);
    final controller = ref.read(signUpControllerProvider.notifier);
    setState(() => _loading = true);
    try {
      final registered = await controller.submit(
        birthDate: _date.text,
        birthTime: _time.text,
        birthPlace: _place.text,
        zodiacSign: sign,
      );
      if (registered) await analytics.logEvent('sign_up');
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _signUpFailed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(signUpErrorMessage(e))),
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
              const Icon(Icons.auto_awesome,
                  size: 52, color: AstrumColors.amethyst),
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
                maxLength: SignUpLimits.birthTime,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'Hora de nascimento (HH:MM) — opcional',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _place,
                maxLength: SignUpLimits.birthPlace,
                decoration: const InputDecoration(
                  counterText: '',
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
                    border: Border.all(
                        color: AstrumColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${signGlyph[sign]}  Seu Sol está em $sign · ${signElements[sign]}',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: AstrumColors.gold, fontSize: 16),
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
                onPressed: _loading
                    ? null
                    : () {
                        ref.read(signUpControllerProvider.notifier).clear();
                        context.go('/register');
                      },
                child: const Text('Voltar'),
              ),
              if (_signUpFailed)
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          ref.read(signUpControllerProvider.notifier).clear();
                          context.go('/login');
                        },
                  child: const Text('Já tenho conta / Entrar'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
