import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

class RitualsScreen extends ConsumerStatefulWidget {
  const RitualsScreen({super.key});

  @override
  ConsumerState<RitualsScreen> createState() => _RitualsScreenState();
}

class _RitualsScreenState extends ConsumerState<RitualsScreen> {
  late DateTime _selected = DateTime.now();

  String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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
            TextField(controller: title, decoration: const InputDecoration(hintText: 'Título')),
            const SizedBox(height: 8),
            TextField(controller: time, decoration: const InputDecoration(hintText: 'Horário HH:MM')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await ref.read(userRepositoryProvider).addEvent(
          profile.uid,
          RitualEvent(
            id: '',
            title: title.text.trim(),
            time: time.text.trim(),
            date: _key(_selected),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider).valueOrNull ?? [];
    final profile = ref.watch(profileProvider).valueOrNull;
    final dayEvents = events.where((e) => e.date == _key(_selected)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

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
                final selected = _key(day) == _key(_selected);
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
                                  .read(userRepositoryProvider)
                                  .deleteEvent(profile.uid, e.id),
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
