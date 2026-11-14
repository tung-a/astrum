import 'package:intl/intl.dart';

/// Chave de dia local `yyyy-MM-dd` (formato de dailyCheckIn, dailyTarot,
/// dailyHoroscope e RitualEvent.date).
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
