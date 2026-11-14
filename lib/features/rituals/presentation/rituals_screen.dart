import 'package:astrum/core/clock/day_key.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/domain/ritual_day.dart';
import 'package:astrum/features/rituals/presentation/rituals_controller.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class RitualsScreen extends ConsumerStatefulWidget {
  const RitualsScreen({super.key});

  @override
  ConsumerState<RitualsScreen> createState() => _RitualsScreenState();
}

class _RitualsScreenState extends ConsumerState<RitualsScreen> {
  late DateTime _selected = DateTime.now();

  Future<void> _add() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final title = TextEditingController();
    final time = TextEditingController(text: '20:00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo ritual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(hintText: 'Título')),
            const SizedBox(height: 8),
            TextField(
                controller: time,
                decoration: const InputDecoration(hintText: 'Horário HH:MM')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ritualsControllerProvider.notifier).add(
          title: title.text,
          time: time.text,
          date: dayKey(_selected),
        );
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider).valueOrNull ?? [];
    final profile = ref.watch(profileProvider).valueOrNull;
    final dayEvents = eventsOfDay(events, dayKey(_selected));

    return CosmicScaffold(
      title: 'Rituais',
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 88,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: 14,
              itemBuilder: (context, i) {
                final day = DateTime.now().add(Duration(days: i - 3));
                final selected = dayKey(day) == dayKey(_selected);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    label: Text(DateFormat('dd/MM').format(day)),
                    onSelected: (_) => setState(() => _selected = day),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: dayEvents.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum ritual neste dia.\nToque + para plantar uma intenção.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AstrumColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: dayEvents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = dayEvents[i];
                      return ListTile(
                        tileColor: AstrumColors.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Text(e.title),
                        subtitle: Text('${e.time} · ${e.duration} min'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: profile == null
                              ? null
                              : () => ref
                                  .read(ritualsControllerProvider.notifier)
                                  .delete(e.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
