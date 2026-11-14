import 'package:astrum/features/rituals/domain/ritual_event.dart';

/// Eventos de [dayKey] (`yyyy-MM-dd`), ordenados pelo horario (`time`).
List<RitualEvent> eventsOfDay(List<RitualEvent> events, String dayKey) =>
    events.where((e) => e.date == dayKey).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
