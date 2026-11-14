import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/astral/presentation/astral_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class AstralScreen extends ConsumerWidget {
  const AstralScreen({super.key});

  Color _el(String element) {
    final el = element.toLowerCase();
    if (el.contains('fogo')) return AstrumColors.fire;
    if (el.contains('água') || el.contains('agua')) return AstrumColors.water;
    if (el.contains('ar')) return AstrumColors.air;
    if (el.contains('terra')) return AstrumColors.earth;
    return AstrumColors.cream;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile == null) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final map = profile.astralMap;

    return CosmicScaffold(
      title: 'Mapa Astral',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            profile.name,
            style: GoogleFonts.cinzel(fontSize: 24, color: AstrumColors.cream),
          ),
          Text(
            [
              if (profile.birthDate.isNotEmpty) profile.birthDate,
              if (profile.birthTime.isNotEmpty) profile.birthTime,
              if (profile.birthPlace.isNotEmpty) profile.birthPlace,
            ].join(' · '),
            style: const TextStyle(color: AstrumColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            '${signGlyph[profile.zodiacSign] ?? ''}  Sol em ${profile.zodiacSign}',
            style: const TextStyle(color: AstrumColors.gold, fontSize: 16),
          ),
          const SizedBox(height: 20),
          if (map.isEmpty)
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await ref
                    .read(astralControllerProvider.notifier)
                    .calculate(profile);
                if (!ok) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content:
                            Text('Preencha a data de nascimento na conta.')),
                  );
                }
              },
              child: const Text('Calcular mapa no dispositivo'),
            )
          else
            ...map.map(
              (p) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AstrumColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: _el(p.element).withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(p.planet,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          '${signGlyph[p.sign] ?? ''} ${p.sign}',
                          style: TextStyle(color: _el(p.element)),
                        ),
                      ],
                    ),
                    Text(p.house,
                        style: const TextStyle(
                            color: AstrumColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(p.summary, style: const TextStyle(height: 1.35)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'O mapa é calculado localmente (Sol preciso, Lua e planetas aproximados). Não usa IA paga.',
            style: TextStyle(color: AstrumColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
