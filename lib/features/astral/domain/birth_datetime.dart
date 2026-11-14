import 'package:astrum/core/astro/zodiac.dart';

/// Data e hora de nascimento a partir dos textos do perfil (`dd/MM/yyyy` e
/// `HH:mm`), ou null quando a data e invalida. Hora ausente ou nao numerica
/// vira 12; minuto ausente ou nao numerico vira 0.
DateTime? birthDateTimeOf({
  required String birthDate,
  required String birthTime,
}) {
  final parsed = parseDateString(birthDate);
  if (parsed == null) return null;
  final timeParts = birthTime.split(':');
  final hour = timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 12 : 12;
  final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
  return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
}
