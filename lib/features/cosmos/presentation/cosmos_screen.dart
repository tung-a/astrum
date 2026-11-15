import 'package:astrum/core/astro/moon.dart';
import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/core/clock/day_key.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/cosmos/domain/daily_content.dart';
import 'package:astrum/features/cosmos/presentation/cosmos_controller.dart';
import 'package:astrum/features/cosmos/presentation/meditation_sheet.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/domain/ritual_day.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/shared/cosmetics_style.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:astrum/shared/equipped_cosmetics_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class CosmosScreen extends ConsumerStatefulWidget {
  const CosmosScreen({super.key});

  @override
  ConsumerState<CosmosScreen> createState() => _CosmosScreenState();
}

class _CosmosScreenState extends ConsumerState<CosmosScreen> {
  String get _today => dayKey(ref.read(clockProvider)());

  Future<void> _drawTarot() async {
    final messenger = ScaffoldMessenger.of(context);
    final message =
        await ref.read(cosmosControllerProvider.notifier).drawTarot();
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _checkIn() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await ref.read(cosmosControllerProvider.notifier).checkIn();
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileProvider);
    // Mantem o controller (autoDispose) vivo enquanto a tela existe.
    final cosmos = ref.watch(cosmosControllerProvider);
    final events = ref.watch(eventsProvider).valueOrNull ?? [];
    final skin = ref.watch(equippedSkinProvider);
    final moon = moonFor(DateTime.now());

    return CosmicScaffold(
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          if (profile.zodiacSign.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) =>
                ref.read(cosmosControllerProvider.notifier).ensureHoroscope());
          }
          final today = _today;
          final firstName = profile.name.split(' ').first;
          final todayEvents = eventsOfDay(events, today);
          final horoscope = horoscopeOf(profile, today);
          final tarot = tarotOf(profile, today);
          final checkedIn = checkedInToday(profile, today);

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
                style: TextStyle(
                    color: AstrumColors.muted.withValues(alpha: 0.95)),
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
                        loading: cosmos.drawingTarot,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: checkedIn || cosmos.checkingIn ? null : _checkIn,
                child: Text(
                  checkedIn
                      ? 'Check-in de hoje já recebido · ${profile.stardust} ✦'
                      : 'Check-in diário · +$checkInReward Poeira Estelar',
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
                      onTap: () =>
                          showMeditationSheet(context, profile.zodiacSign),
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
                  style:
                      const TextStyle(color: AstrumColors.cream, height: 1.3),
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
        border:
            Border.all(color: AstrumColors.amethyst.withValues(alpha: 0.35)),
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
          Text(title,
              style:
                  GoogleFonts.cinzel(fontSize: 18, color: AstrumColors.cream)),
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
