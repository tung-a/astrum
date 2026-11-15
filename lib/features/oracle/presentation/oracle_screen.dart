import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/oracle/presentation/chat_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _starters = [
  'Qual a energia de hoje?',
  'Previsão para o amor',
  'Qual cristal usar?',
  'Como está a lua hoje?',
];

class OracleScreen extends ConsumerStatefulWidget {
  const OracleScreen({super.key});

  @override
  ConsumerState<OracleScreen> createState() => _OracleScreenState();
}

class _OracleScreenState extends ConsumerState<OracleScreen> {
  final _input = TextEditingController();
  final _tts = FlutterTts();

  @override
  void dispose() {
    _input.dispose();
    _tts.stop();
    super.dispose();
  }

  /// Envia [preset] (chip) ou o texto do campo; limpa o campo so quando o
  /// envio e aceito (nao vazio e sem resposta em andamento).
  Future<void> _send({String? preset}) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || ref.read(chatControllerProvider).loading) {
      return Future.value();
    }
    _input.clear();
    return ref.read(chatControllerProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final chat = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    ref.listen(chatControllerProvider.select((s) => s.hydrated), (_, hydrated) {
      if (!hydrated) return;
      final pending = controller.takePendingPrompt();
      if (pending != null) _input.text = pending;
    });
    if (profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.hydrate();
      });
    }

    return CosmicScaffold(
      title: 'Oráculo',
      actions: [
        IconButton(
          tooltip: 'Nova conversa',
          onPressed: profile == null ? null : controller.newConversation,
          icon: const Icon(Icons.add_comment_outlined),
        ),
        if (chat.conversations.length > 1)
          PopupMenuButton<int>(
            onSelected: controller.select,
            itemBuilder: (context) => [
              for (var i = 0; i < chat.conversations.length; i++)
                PopupMenuItem(
                    value: i, child: Text(chat.conversations[i].title)),
            ],
          ),
      ],
      body: Column(
        children: [
          if (chat.current.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _starters
                    .map(
                      (q) => ActionChip(
                        label: Text(q),
                        onPressed:
                            profile == null ? null : () => _send(preset: q),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: chat.current.messages.length + (chat.loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= chat.current.messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('O oráculo consulta as esferas…',
                        style: TextStyle(color: AstrumColors.muted)),
                  );
                }
                final msg = chat.current.messages[i];
                final mine = msg.role == 'user';
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 520),
                    decoration: BoxDecoration(
                      color: mine
                          ? AstrumColors.amethyst.withValues(alpha: 0.35)
                          : AstrumColors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                                color: AstrumColors.cream, height: 1.4),
                          ),
                        ),
                        if (!mine)
                          IconButton(
                            onPressed: () => _tts.speak(msg.text),
                            icon: const Icon(Icons.volume_up, size: 18),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(hintText: 'Pergunte ao oráculo…'),
                    onSubmitted: (_) {
                      if (profile != null) _send();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed:
                      chat.loading || profile == null ? null : () => _send(),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
