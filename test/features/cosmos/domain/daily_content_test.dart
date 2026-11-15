import 'package:astrum/features/cosmos/domain/daily_content.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user({
  String sign = 'Peixes',
  Map<String, dynamic>? horoscope,
  Map<String, dynamic>? tarot,
  String? checkIn,
}) =>
    AppUser(
      uid: 'u',
      email: 'u@x.com',
      name: 'U',
      zodiacSign: sign,
      dailyHoroscope: horoscope,
      dailyTarot: tarot,
      dailyCheckIn: checkIn,
    );

void main() {
  const today = '2026-11-14';

  test('prompts mantem o texto literal de antes da refatoracao', () {
    expect(horoscopePrompt('Peixes'),
        'Gere um horóscopo do dia curto e inspirador para o signo de Peixes. Foco: autoconhecimento. Máximo de 3 frases.');
    expect(tarotPrompt('O Louco'),
        'O usuário tirou a carta de Tarot "O Louco" para o dia de hoje. Interpretação mística, direta, 2 a 3 frases.');
  });

  test('horoscopeOf so devolve o texto de hoje', () {
    expect(
        horoscopeOf(_user(horoscope: {'date': today, 'content': 'oi'}), today),
        'oi');
    expect(
        horoscopeOf(
            _user(horoscope: {'date': '2026-11-13', 'content': 'oi'}), today),
        isNull);
    expect(horoscopeOf(_user(), today), isNull);
  });

  test('tarotOf so devolve a carta de hoje', () {
    final tarot = {'date': today, 'card': 'O Sol', 'meaning': 'x'};
    expect(tarotOf(_user(tarot: tarot), today), tarot);
    expect(
        tarotOf(_user(tarot: {...tarot, 'date': '2026-11-13'}), today), isNull);
    expect(tarotOf(_user(), today), isNull);
  });

  test('needsHoroscope: precisa de signo e de horoscopo que nao seja de hoje',
      () {
    expect(needsHoroscope(_user(), today), isTrue);
    expect(needsHoroscope(_user(sign: ''), today), isFalse);
    expect(
        needsHoroscope(
            _user(horoscope: {'date': today, 'content': 'x'}), today),
        isFalse);
    expect(
        needsHoroscope(
            _user(horoscope: {'date': '2026-11-13', 'content': 'x'}), today),
        isTrue);
  });

  test('checkedInToday compara com o dia', () {
    expect(checkedInToday(_user(checkIn: today), today), isTrue);
    expect(checkedInToday(_user(checkIn: '2026-11-13'), today), isFalse);
    expect(checkedInToday(_user(), today), isFalse);
  });
}
