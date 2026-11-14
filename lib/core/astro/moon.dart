class MoonSnapshot {
  const MoonSnapshot({
    required this.phaseName,
    required this.illumination,
    required this.guidance,
    required this.emoji,
  });

  final String phaseName;
  final double illumination;
  final String guidance;
  final String emoji;
}

MoonSnapshot moonFor(DateTime date) {
  const synodic = 29.53058867;
  final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
  final days = date.toUtc().difference(knownNewMoon).inMinutes / 1440.0;
  final age = days % synodic;
  final illumination = (1 - ((age / synodic - 0.5).abs() * 2)).clamp(0.0, 1.0);

  if (age < 1.84566) {
    return MoonSnapshot(
      phaseName: 'Lua Nova',
      illumination: illumination,
      guidance: 'Plante intenções em silêncio. O invisível está fértil.',
      emoji: '🌑',
    );
  }
  if (age < 7.38) {
    return const MoonSnapshot(
      phaseName: 'Lua Crescente',
      illumination: 0.25,
      guidance: 'Dê o primeiro passo. A energia pede movimento suave.',
      emoji: '🌒',
    );
  }
  if (age < 9.22) {
    return const MoonSnapshot(
      phaseName: 'Quarto Crescente',
      illumination: 0.5,
      guidance: 'Enfrente o que trava. Coragem com discernimento.',
      emoji: '🌓',
    );
  }
  if (age < 14.76) {
    return const MoonSnapshot(
      phaseName: 'Gibosa Crescente',
      illumination: 0.75,
      guidance: 'Refine o que já começou. Ajuste o rumo, não desista.',
      emoji: '🌔',
    );
  }
  if (age < 16.61) {
    return const MoonSnapshot(
      phaseName: 'Lua Cheia',
      illumination: 1,
      guidance: 'Revele, celebre, libere. Tudo que estava oculto pede luz.',
      emoji: '🌕',
    );
  }
  if (age < 22.14) {
    return const MoonSnapshot(
      phaseName: 'Gibosa Minguante',
      illumination: 0.75,
      guidance: 'Agradeça e compartilhe. A colheita é também entrega.',
      emoji: '🌖',
    );
  }
  if (age < 23.99) {
    return const MoonSnapshot(
      phaseName: 'Quarto Minguante',
      illumination: 0.5,
      guidance: 'Solte hábitos que já cumpriram seu ciclo.',
      emoji: '🌗',
    );
  }
  return const MoonSnapshot(
    phaseName: 'Lua Minguante',
    illumination: 0.25,
    guidance: 'Descanse. Recolha-se para nascer de novo com a próxima lua.',
    emoji: '🌘',
  );
}

String dailyEnergyFor({required String sign, required MoonSnapshot moon}) {
  final element = switch (sign) {
    'Áries' || 'Leão' || 'Sagitário' => 'fogo',
    'Touro' || 'Virgem' || 'Capricórnio' => 'terra',
    'Gêmeos' || 'Libra' || 'Aquário' => 'ar',
    _ => 'água',
  };
  final lunar = moon.phaseName.contains('Cheia')
      ? 'alta'
      : moon.phaseName.contains('Nova')
          ? 'íntima'
          : 'fluida';
  return 'Energia $lunar para o elemento $element: ${moon.guidance}';
}
