import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/cosmos/data/meditation_sounds.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _themes = [
  (
    id: 'calm',
    label: 'Calma',
    icon: Icons.spa,
    color: Color(0xFF4CAF50),
    intent: 'acalmar a ansiedade e trazer paz'
  ),
  (
    id: 'focus',
    label: 'Foco',
    icon: Icons.filter_center_focus,
    color: Color(0xFF2196F3),
    intent: 'aumentar concentração e clareza'
  ),
  (
    id: 'sleep',
    label: 'Sono',
    icon: Icons.bedtime,
    color: Color(0xFF673AB7),
    intent: 'relaxar para um sono reparador'
  ),
  (
    id: 'energy',
    label: 'Energia',
    icon: Icons.bolt,
    color: Color(0xFFFF9800),
    intent: 'revitalizar a aura e despertar poder'
  ),
];

Future<void> showMeditationSheet(BuildContext context, String sign) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AstrumColors.deepPurple,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => MeditationSheet(sign: sign),
  );
}

class MeditationSheet extends ConsumerStatefulWidget {
  const MeditationSheet({super.key, required this.sign});
  final String sign;

  @override
  ConsumerState<MeditationSheet> createState() => _MeditationSheetState();
}

class _MeditationSheetState extends ConsumerState<MeditationSheet>
    with SingleTickerProviderStateMixin {
  int _themeIndex = 0;
  String? _script;
  bool _loading = false;
  String _soundId = meditationSounds.first.id;
  bool _playing = false;
  AudioPlayer? _player;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _player?.dispose();
    _breath.dispose();
    super.dispose();
  }

  Future<void> _playSound() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(soundForId(_soundId).sourcePath));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Não foi possível tocar o som.')),
        );
      }
    }
  }

  Future<void> _toggleSound() async {
    if (_playing) {
      try {
        await _player?.pause();
      } catch (_) {}
      if (mounted) setState(() => _playing = false);
    } else {
      await _playSound();
    }
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    _playSound();
    final theme = _themes[_themeIndex];
    final text = await ref.read(oracleServiceProvider).complete(
          prompt:
              'Escreva um script de meditação guiada de 8 a 12 frases para ${theme.intent}. Signo: ${widget.sign}. Sem markdown.',
          sign: widget.sign,
        );
    if (mounted) {
      setState(() {
        _script = text;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_themeIndex];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AstrumColors.muted,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Santuário',
              style: TextStyle(fontSize: 22, color: AstrumColors.cream)),
          const SizedBox(height: 16),
          if (_script == null) ...[
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _themes.length; i++)
                  ChoiceChip(
                    selected: i == _themeIndex,
                    label: Text(_themes[i].label),
                    avatar: Icon(_themes[i].icon,
                        size: 16, color: _themes[i].color),
                    onSelected: (_) => setState(() => _themeIndex = i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Som', style: TextStyle(color: AstrumColors.muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in meditationSounds)
                  ChoiceChip(
                    selected: s.id == _soundId,
                    label: Text(s.label),
                    selectedColor: AstrumColors.amethyst,
                    labelStyle: const TextStyle(color: AstrumColors.cream),
                    onSelected: (_) => setState(() => _soundId = s.id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _start,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Meditar em ${theme.label}'),
            ),
            const SizedBox(height: 24),
          ] else ...[
            ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.08).animate(
                CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: theme.color.withValues(alpha: 0.3),
                child: Icon(theme.icon, color: theme.color, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Inspire… expire…',
                style: TextStyle(color: AstrumColors.muted)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Text(_script!, style: const TextStyle(height: 1.45)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _toggleSound,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                  color: AstrumColors.gold),
              label: Text(_playing ? 'Pausar som' : 'Retomar som'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Encerrar com gratidão'),
            ),
          ],
        ],
      ),
    );
  }
}
