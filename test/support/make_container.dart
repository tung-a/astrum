import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relogio fixo dos testes de controller (meio-dia local).
final testNow = DateTime(2026, 11, 14, 12);

/// [ProviderContainer] com perfil fixo e relogio fixo, ja com o perfil
/// resolvido (controllers leem `profileProvider` com `valueOrNull`).
/// Fecha o container no tearDown do teste que o pedir via [addTearDown].
Future<ProviderContainer> makeContainer({
  AppUser? user,
  DateTime? now,
  List<Override> overrides = const [],
}) async {
  final c = ProviderContainer(overrides: [
    profileProvider.overrideWith((ref) => Stream<AppUser?>.value(user)),
    clockProvider.overrideWithValue(() => now ?? testNow),
    ...overrides,
  ]);
  await c.read(profileProvider.future);
  return c;
}
