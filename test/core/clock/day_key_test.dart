import 'package:astrum/core/clock/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dayKey formata yyyy-MM-dd com zero a esquerda', () {
    expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
    expect(dayKey(DateTime(2026, 11, 14, 23, 59)), '2026-11-14');
  });

  test('dayKey muda na virada de dia, mes e ano', () {
    expect(dayKey(DateTime(2026, 1, 31, 23, 59, 59)), '2026-01-31');
    expect(dayKey(DateTime(2026, 2, 1)), '2026-02-01');
    expect(dayKey(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    expect(dayKey(DateTime(2027, 1, 1)), '2027-01-01');
  });
}
