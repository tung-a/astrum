import 'package:astrum/features/rituals/domain/ritual_day.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';
import 'package:flutter_test/flutter_test.dart';

RitualEvent _e(String id, String date, String time) =>
    RitualEvent(id: id, title: id, time: time, date: date);

void main() {
  test('filtra pelo dia e ordena por horario', () {
    final out = eventsOfDay([
      _e('c', '2026-11-14', '21:00'),
      _e('x', '2026-11-15', '08:00'),
      _e('a', '2026-11-14', '07:30'),
      _e('b', '2026-11-14', '20:00'),
    ], '2026-11-14');
    expect(out.map((e) => e.id), ['a', 'b', 'c']);
  });

  test('dia sem eventos devolve lista vazia e nao altera a original', () {
    final all = [_e('a', '2026-11-14', '07:30')];
    expect(eventsOfDay(all, '2026-11-13'), isEmpty);
    expect(eventsOfDay(const [], '2026-11-14'), isEmpty);
    expect(all, hasLength(1));
  });
}
