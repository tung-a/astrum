import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_controller.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/make_container.dart';

void main() {
  late FakeEventsRepository events;
  late FakeAnalytics analytics;

  setUp(() {
    events = FakeEventsRepository();
    analytics = FakeAnalytics();
  });

  Future<RitualsController> setup({bool loggedIn = true}) async {
    final c = await makeContainer(
      user: loggedIn ? testUser() : null,
      overrides: [
        eventsRepositoryProvider.overrideWithValue(events),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(c.dispose);
    return c.read(ritualsControllerProvider.notifier);
  }

  test('add monta o evento com trim, grava e registra o analytics', () async {
    final ctl = await setup();

    await ctl.add(title: '  Meditar ', time: ' 20:00 ', date: '2026-11-14');

    expect(events.added, hasLength(1));
    final e = events.added.single;
    expect(e.uid, 'u1');
    expect(e.event.id, '');
    expect(e.event.title, 'Meditar');
    expect(e.event.time, '20:00');
    expect(e.event.date, '2026-11-14');
    expect(analytics.events, ['add_event_calendar']);
  });

  test('add com titulo vazio ou sem perfil nao faz nada', () async {
    final ctl = await setup();
    await ctl.add(title: '   ', time: '20:00', date: '2026-11-14');
    expect(events.added, isEmpty);
    expect(analytics.events, isEmpty);

    final semPerfil = await setup(loggedIn: false);
    await semPerfil.add(title: 'X', time: '20:00', date: '2026-11-14');
    expect(events.added, isEmpty);
    expect(analytics.events, isEmpty);
  });

  test('delete remove e registra o analytics', () async {
    final ctl = await setup();

    await ctl.delete('ev1');

    expect(events.deleted, [(uid: 'u1', eventId: 'ev1')]);
    expect(analytics.events, ['delete_event_calendar']);
  });
}
