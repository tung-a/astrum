import 'package:astrum/core/astro/zodiac.dart';

class PlanetPosition {
  const PlanetPosition({
    required this.planet,
    required this.sign,
    required this.house,
    required this.element,
    required this.summary,
  });

  final String planet;
  final String sign;
  final String house;
  final String element;
  final String summary;

  Map<String, dynamic> toJson() => {
        'planet': planet,
        'sign': sign,
        'house': house,
        'element': element,
        'summary': summary,
      };

  factory PlanetPosition.fromJson(Map<String, dynamic> json) => PlanetPosition(
        planet: json['planet'] as String? ?? '',
        sign: json['sign'] as String? ?? '',
        house: json['house'] as String? ?? '',
        element: json['element'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
      );
}

/// Mapa natal determinístico no dispositivo (sem chamar IA).
List<PlanetPosition> computeNatalChart({
  required DateTime birth,
  String? birthPlace,
}) {
  final sun = sunSignFromDate(birth.day, birth.month);
  final moon = _signFromLongitude(_moonLongitude(birth));
  final mercury = _signFromIndex((_signIndex(sun) + (birth.day % 3) - 1) % 12);
  final venus =
      _signFromIndex((_signIndex(sun) + (birth.month % 2 == 0 ? 1 : -1)) % 12);
  final mars = _signFromIndex((_signIndex(sun) + 4 + (birth.year % 3)) % 12);
  final asc = _signFromIndex((_signIndex(sun) + (birth.hour ~/ 2)) % 12);

  String houseFor(String sign) => 'Casa ${(_signIndex(sign) % 12) + 1}';

  const summaries = {
    'Sol': 'O núcleo da identidade e o propósito que ilumina o caminho.',
    'Lua': 'O mundo emocional, a memória do corpo e o que nutre a alma.',
    'Ascendente': 'A máscara sagrada: como o cosmos te apresenta ao mundo.',
    'Mercúrio': 'A mente, a palavra e a forma de traduzir o invisível.',
    'Vênus': 'O que você ama, atrai e considera belo.',
    'Marte': 'O fogo da ação, do desejo e da coragem.',
  };

  PlanetPosition pos(String planet, String sign) => PlanetPosition(
        planet: planet,
        sign: sign,
        house: houseFor(sign),
        element: signElements[sign] ?? 'Mistério',
        summary: summaries[planet] ?? '',
      );

  return [
    pos('Sol', sun),
    pos('Lua', moon),
    pos('Ascendente', asc),
    pos('Mercúrio', mercury),
    pos('Vênus', venus),
    pos('Marte', mars),
  ];
}

int _signIndex(String sign) => zodiacSigns.indexOf(sign).clamp(0, 11);

String _signFromIndex(int index) => zodiacSigns[index % 12];

String _signFromLongitude(double deg) {
  final normalized = deg % 360;
  return zodiacSigns[(normalized / 30).floor() % 12];
}

/// Longitude lunar aproximada (epoch: lua nova conhecida).
double _moonLongitude(DateTime date) {
  const synodic = 29.53058867;
  final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
  final days = date.toUtc().difference(knownNewMoon).inMinutes / 1440.0;
  final age = days % synodic;
  return (age / synodic) * 360.0;
}
