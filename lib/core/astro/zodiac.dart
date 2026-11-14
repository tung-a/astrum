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
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return (day: day, month: month, year: year);
}

/// Slug do signo sem acentos (ex.: `Gêmeos` -> `gemeos`), usado em ids e
/// caminhos de avatar.
String zodiacSlug(String sign) => sign
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('â', 'a')
    .replaceAll('é', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ã', 'a')
    .replaceAll('ç', 'c');
