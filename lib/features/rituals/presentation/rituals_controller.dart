import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ritualsControllerProvider =
    NotifierProvider<RitualsController, void>(RitualsController.new);

/// Criacao e remocao de rituais (sem estado). O dialogo e o dia selecionado
/// continuam na tela.
class RitualsController extends Notifier<void> {
  @override
  void build() {}

  /// Sem perfil ou com [title] vazio (apos trim) nao faz nada.
  Future<void> add({
    required String title,
    required String time,
    required String date,
  }) async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final t = title.trim();
    if (t.isEmpty) return;
    await ref.read(eventsRepositoryProvider).addEvent(
          profile.uid,
          RitualEvent(id: '', title: t, time: time.trim(), date: date),
        );
    await ref.read(analyticsServiceProvider).logEvent('add_event_calendar');
  }

  Future<void> delete(String eventId) async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    await ref.read(eventsRepositoryProvider).deleteEvent(profile.uid, eventId);
    await ref.read(analyticsServiceProvider).logEvent('delete_event_calendar');
  }
}
