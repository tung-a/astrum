import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/oracle/presentation/chat_controller.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
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

const chatNoticeTitle = 'Seu histórico fica na nuvem';
const chatNoticeBody =
    'As conversas com o oráculo são armazenadas na nuvem (Firebase, região de '
    'São Paulo, southamerica-east1) para sincronizar entre os seus aparelhos. '
    'Elas ficam guardadas até serem apagadas, sem prazo de expiração. Em '
    'breve você poderá apagá-las no app, e elas poderão ser apagadas junto '
    'com a sua conta.';

class OracleScreen extends ConsumerStatefulWidget {
  const OracleScreen({super.key});

  @override
  ConsumerState<OracleScreen> createState() => _OracleScreenState();
}

class _OracleScreenState extends ConsumerState<OracleScreen> {
  final _input = TextEditingController();
  final _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    // Historico local antigo (pre-etapa 10) nao deve ficar no aparelho.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(chatNoticeStoreProvider).purgeLegacyChats();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _tts.stop();
    super.dispose();
  }

  bool _noticeOpen = false;

  /// Mostra o aviso de privacidade uma vez por uid; devolve false se nao deu
  /// para seguir (aviso ja aberto ou tela descartada).
  Future<bool> _ensureNotice() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return false;
    final store = ref.read(chatNoticeStoreProvider);
    if (store.seen(uid)) return true;
    if (_noticeOpen) return false;
    _noticeOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(chatNoticeTitle),
        content: const Text(chatNoticeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    _noticeOpen = false;
    await store.markSeen(uid);
    return mounted;
  }

  /// Envia [preset] (chip) ou o texto do campo; limpa o campo so quando o
  /// envio e aceito (hidratado, nao vazio e sem resposta em andamento), para
  /// nao perder o texto digitado antes de o historico carregar.
  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    final chat = ref.read(chatControllerProvider);
    if (text.isEmpty || chat.loading || !chat.hydrated || chat.limitReached) {
      return;
    }
    if (!await _ensureNotice()) return;
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(text);
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
                        onPressed: profile == null || !chat.hydrated
                            ? null
                            : () => _send(preset: q),
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
                  onPressed: chat.loading || profile == null || !chat.hydrated
                      ? null
                      : () => _send(),
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
