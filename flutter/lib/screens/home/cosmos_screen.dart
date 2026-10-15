import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../data/astrology.dart';
import '../../data/cosmetics.dart';
import '../../data/moon.dart';
import '../../data/tarot.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';
import '../rituals/meditation_sheet.dart';

class CosmosScreen extends ConsumerStatefulWidget {
  const CosmosScreen({super.key});

  @override
  ConsumerState<CosmosScreen> createState() => _CosmosScreenState();
}

class _CosmosScreenState extends ConsumerState<CosmosScreen> {
  bool _drawing = false;
  bool _horoscopeRequested = false;

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _ensureHoroscope() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || profile.zodiacSign.isEmpty) return;
    final cached = profile.dailyHoroscope;
    if (cached != null && cached['date'] == _today) return;
    final text = await ref.read(oracleServiceProvider).complete(
          prompt:
              'Gere um horóscopo do dia curto e inspirador para o signo de ${profile.zodiacSign}. Foco: autoconhecimento. Máximo de 3 frases.',
          sign: profile.zodiacSign,
        );
    await ref.read(userRepositoryProvider).updateFields(profile.uid, {
      'dailyHoroscope': {'date': _today, 'content': text},
    });
  }

  Future<void> _drawTarot() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || _drawing) return;
    setState(() => _drawing = true);
    final card = pickDailyCard(DateTime.now(), profile.uid);
    var meaning = card.meaning;
    try {
      meaning = await ref.read(oracleServiceProvider).complete(
            prompt:
                'O usuário tirou a carta de Tarot "${card.name}" para o dia de hoje. Interpretação mística, direta, 2 a 3 frases.',
            sign: profile.zodiacSign,
          );
    } catch (_) {}
    await ref.read(userRepositoryProvider).updateFields(profile.uid, {
      'dailyTarot': {
        'date': _today,
        'card': card.name,
        'meaning': meaning,
      },
    });
    if (mounted) setState(() => _drawing = false);
  }

  Future<void> _checkIn() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    if (profile.dailyCheckIn == _today) return;
    await ref.read(userRepositoryProvider).updateFields(profile.uid, {
      'dailyCheckIn': _today,
      'wallet.stardust': FieldValue.increment(25),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('+25 Poeira Estelar pelo check-in de hoje')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileProvider);
    final events = ref.watch(eventsProvider).valueOrNull ?? [];
    final skin = ref.watch(equippedSkinProvider);
    final moon = moonFor(DateTime.now());

    return CosmicScaffold(
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          if (!_horoscopeRequested && profile.zodiacSign.isNotEmpty) {
            _horoscopeRequested = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _ensureHoroscope());
          }
          final firstName = profile.name.split(' ').first;
          final todayEvents =
              events.where((e) => e.date == _today).toList()
                ..sort((a, b) => a.time.compareTo(b.time));
          final horoscope = profile.dailyHoroscope?['date'] == _today
              ? profile.dailyHoroscope?['content'] as String?
              : null;
          final tarot = profile.dailyTarot?['date'] == _today
              ? profile.dailyTarot
              : null;
          final checkedIn = profile.dailyCheckIn == _today;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text('Olá, $firstName',
                  style: GoogleFonts.cinzel(
                    fontSize: 28,
                    color: AstrumColors.cream,
                  )),
              const SizedBox(height: 4),
              Text(
                'O universo saúda sua jornada hoje.',
                style: TextStyle(color: AstrumColors.muted.withValues(alpha: 0.95)),
              ),
              const SizedBox(height: 20),
              _MoonCard(moon: moon, sign: profile.zodiacSign),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${signGlyph[profile.zodiacSign] ?? '✦'}  ${profile.zodiacSign.isEmpty ? 'Signo' : profile.zodiacSign}',
                            style: const TextStyle(
                              color: AstrumColors.gold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            horoscope ?? 'Alinhando as estrelas…',
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AstrumColors.cream,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: tarot == null ? _drawTarot : null,
                      child: _TarotPreview(
                        skin: skin,
                        cardName: tarot?['card'] as String?,
                        meaning: tarot?['meaning'] as String?,
                        loading: _drawing,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: checkedIn ? null : _checkIn,
                child: Text(
                  checkedIn
                      ? 'Check-in de hoje já recebido · ${profile.stardust} ✦'
                      : 'Check-in diário · +25 Poeira Estelar',
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Rituais de hoje',
                child: todayEvents.isEmpty
                    ? Column(
                        children: [
                          const Text(
                            'O cosmos está calmo hoje.',
                            style: TextStyle(color: AstrumColors.muted),
                          ),
                          TextButton(
                            onPressed: () => context.go('/app/rituals'),
                            child: const Text('Agendar ritual'),
                          ),
                        ],
                      )
                    : Column(
                        children: todayEvents
                            .map(
                              (e) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.brightness_1,
                                    size: 10, color: AstrumColors.gold),
                                title: Text(e.title),
                                subtitle: Text(e.time),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Jornada interior',
                child: Column(
                  children: [
                    _Action(
                      icon: Icons.visibility,
                      label: 'Consultar o Oráculo',
                      onTap: () => context.go('/app/oracle'),
                    ),
                    _Action(
                      icon: Icons.star,
                      label: 'Ver meu mapa astral',
                      onTap: () => context.go('/app/astral'),
                    ),
                    _Action(
                      icon: Icons.self_improvement,
                      label: 'Entrar no santuário',
                      onTap: () => showMeditationSheet(context, profile.zodiacSign),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MoonCard extends StatelessWidget {
  const _MoonCard({required this.moon, required this.sign});
  final MoonSnapshot moon;
  final String sign;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          Text(moon.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(moon.phaseName,
                    style: const TextStyle(
                      color: AstrumColors.gold,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Text(
                  dailyEnergyFor(sign: sign, moon: moon),
                  style: const TextStyle(color: AstrumColors.cream, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarotPreview extends StatelessWidget {
  const _TarotPreview({
    required this.skin,
    required this.cardName,
    required this.meaning,
    required this.loading,
  });

  final SkinStyle skin;
  final String? cardName;
  final String? meaning;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: skin.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: skin.borderColor.withValues(alpha: 0.7)),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.style, color: skin.iconColor),
                    const SizedBox(height: 8),
                    Text(
                      cardName ?? 'Carta do Dia',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: skin.iconColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meaning ?? 'Toque para escolher',
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AstrumColors.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AstrumColors.amethyst.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AstrumColors.card.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.cinzel(fontSize: 18, color: AstrumColors.cream)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AstrumColors.gold),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: AstrumColors.muted),
    );
  }
}
