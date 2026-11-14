/// Sons de fundo da meditacao (assets locais em assets/sounds/).
class MeditationSound {
  const MeditationSound(this.id, this.label);
  final String id;
  final String label;

  /// Caminho completo do asset, como declarado no pubspec.
  String get assetPath => 'assets/sounds/$id.mp3';

  /// Caminho relativo a "assets/", como exigido pelo AssetSource do audioplayers.
  String get sourcePath => 'sounds/$id.mp3';
}

const meditationSounds = [
  MeditationSound('calm', 'Calma'),
  MeditationSound('energy', 'Energia'),
  MeditationSound('focus', 'Foco'),
  MeditationSound('sleep', 'Sono'),
];

/// Devolve o som pelo id, ou o primeiro som se o id for desconhecido.
MeditationSound soundForId(String id) => meditationSounds.firstWhere(
      (s) => s.id == id,
      orElse: () => meditationSounds.first,
    );
