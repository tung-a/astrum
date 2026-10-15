const zodiacSigns = [
  'Áries',
  'Touro',
  'Gêmeos',
  'Câncer',
  'Leão',
  'Virgem',
  'Libra',
  'Escorpião',
  'Sagitário',
  'Capricórnio',
  'Aquário',
  'Peixes',
];

const signElements = {
  'Áries': 'Fogo',
  'Leão': 'Fogo',
  'Sagitário': 'Fogo',
  'Touro': 'Terra',
  'Virgem': 'Terra',
  'Capricórnio': 'Terra',
  'Gêmeos': 'Ar',
  'Libra': 'Ar',
  'Aquário': 'Ar',
  'Câncer': 'Água',
  'Escorpião': 'Água',
  'Peixes': 'Água',
};

const signGlyph = {
  'Áries': '♈',
  'Touro': '♉',
  'Gêmeos': '♊',
  'Câncer': '♋',
  'Leão': '♌',
  'Virgem': '♍',
  'Libra': '♎',
  'Escorpião': '♏',
  'Sagitário': '♐',
  'Capricórnio': '♑',
  'Aquário': '♒',
  'Peixes': '♓',
};

String sunSignFromDate(int day, int month) {
  if ((month == 1 && day >= 20) || (month == 2 && day <= 18)) return 'Aquário';
  if ((month == 2 && day >= 19) || (month == 3 && day <= 20)) return 'Peixes';
  if ((month == 3 && day >= 21) || (month == 4 && day <= 19)) return 'Áries';
  if ((month == 4 && day >= 20) || (month == 5 && day <= 20)) return 'Touro';
  if ((month == 5 && day >= 21) || (month == 6 && day <= 20)) return 'Gêmeos';
  if ((month == 6 && day >= 21) || (month == 7 && day <= 22)) return 'Câncer';
  if ((month == 7 && day >= 23) || (month == 8 && day <= 22)) return 'Leão';
  if ((month == 8 && day >= 23) || (month == 9 && day <= 22)) return 'Virgem';
  if ((month == 9 && day >= 23) || (month == 10 && day <= 22)) return 'Libra';
  if ((month == 10 && day >= 23) || (month == 11 && day <= 21)) {
    return 'Escorpião';
  }
  if ((month == 11 && day >= 22) || (month == 12 && day <= 21)) {
    return 'Sagitário';
  }
  return 'Capricórnio';
}

({int day, int month, int year})? parseDateString(String dateString) {
  final parts = dateString.split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return (day: day, month: month, year: year);
}

class SynergyResult {
  const SynergyResult({
    required this.title,
    required this.description,
    required this.score,
    required this.elementA,
    required this.elementB,
  });

  final String title;
  final String description;
  final int score;
  final String elementA;
  final String elementB;
}

SynergyResult getAstralSynergy(String sign1, String sign2) {
  final el1 = signElements[sign1];
  final el2 = signElements[sign2];
  if (el1 == null || el2 == null) {
    return SynergyResult(
      title: 'Energia Misteriosa',
      description:
          'Os astros ainda não revelaram a conexão completa entre esses signos.',
      score: 3,
      elementA: el1 ?? '?',
      elementB: el2 ?? '?',
    );
  }
  if (el1 == el2) {
    return SynergyResult(
      title: 'Espelhos da Alma',
      description:
          'Ambos vibram no elemento $el1. A compreensão é instantânea. Cuidado para não intensificarem os mesmos padrões.',
      score: 5,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Fogo' && el2 == 'Ar') || (el1 == 'Ar' && el2 == 'Fogo')) {
    return SynergyResult(
      title: 'Expansão e Movimento',
      description:
          'O Ar alimenta o Fogo. Entusiasmo, conversas longas e aventuras. Vocês se inspiram a ir mais longe.',
      score: 4,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Terra' && el2 == 'Água') || (el1 == 'Água' && el2 == 'Terra')) {
    return SynergyResult(
      title: 'Jardim Fértil',
      description:
          'A Água nutre a Terra. Apoio profundo, segurança e sensibilidade. Conexão com raízes fortes.',
      score: 4,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Fogo' && el2 == 'Água') || (el1 == 'Água' && el2 == 'Fogo')) {
    return SynergyResult(
      title: 'Vapor e Intensidade',
      description:
          'Emoção versus ação. Podem criar paixão ou conflito. A água não apaga o fogo, e o fogo não seca a água.',
      score: 3,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Terra' && el2 == 'Ar') || (el1 == 'Ar' && el2 == 'Terra')) {
    return SynergyResult(
      title: 'Céu e Terra',
      description:
          'O Ar sonha, a Terra constrói. Distantes no início, juntos realizam o impossível.',
      score: 3,
      elementA: el1,
      elementB: el2,
    );
  }
  return SynergyResult(
    title: 'Encontro de Forças',
    description:
        'Elementos distintos com grandes lições. A convivência exige adaptação e gera evolução.',
    score: 2,
    elementA: el1,
    elementB: el2,
  );
}

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
  final venus = _signFromIndex((_signIndex(sun) + (birth.month % 2 == 0 ? 1 : -1)) % 12);
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

String defaultProfilePictureId(String? zodiacSign) {
  if (zodiacSign == null || zodiacSign.isEmpty) return '';
  final slug = zodiacSign
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ã', 'a')
      .replaceAll('ç', 'c');
  return 'pfp_zodiac_$slug';
}
