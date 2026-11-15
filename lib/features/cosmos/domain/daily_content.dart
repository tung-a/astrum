import 'package:astrum/features/profile/domain/app_user.dart';

/// Prompt do horoscopo do dia para [sign].
String horoscopePrompt(String sign) =>
    'Gere um horóscopo do dia curto e inspirador para o signo de $sign. Foco: autoconhecimento. Máximo de 3 frases.';

/// Prompt da interpretacao da carta do dia.
String tarotPrompt(String cardName) =>
    'O usuário tirou a carta de Tarot "$cardName" para o dia de hoje. Interpretação mística, direta, 2 a 3 frases.';

/// Texto do horoscopo gravado para [today] (`yyyy-MM-dd`), ou null.
String? horoscopeOf(AppUser user, String today) {
  final h = user.dailyHoroscope;
  return h != null && h['date'] == today ? h['content'] as String? : null;
}

/// Carta gravada para [today] (`card`, `meaning`), ou null.
Map<String, dynamic>? tarotOf(AppUser user, String today) {
  final t = user.dailyTarot;
  return t != null && t['date'] == today ? t : null;
}

/// Horoscopo precisa ser gerado: ha signo e o gravado nao e de [today].
bool needsHoroscope(AppUser user, String today) {
  if (user.zodiacSign.isEmpty) return false;
  final cached = user.dailyHoroscope;
  return !(cached != null && cached['date'] == today);
}

bool checkedInToday(AppUser user, String today) => user.dailyCheckIn == today;
