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

  /// Envia [preset] (chip) ou o texto do campo. O controller decide se aceita
  /// (hidratado, nao vazio, sem resposta em andamento, conversa nao cheia, mesmo
  /// usuario de antes do aviso); o campo so e limpo quando aceita, e nunca por
  /// envio de chip (o texto digitado e preservado).
  Future<void> _send({String? preset}) async {
    final text = (preset ?? _input.text).trim();
    final chat = ref.read(chatControllerProvider);
    if (text.isEmpty || chat.loading || !chat.hydrated || chat.limitReached) {
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (!await _ensureNotice()) return;
    await ref.read(chatControllerProvider.notifier).send(
          text,
          expectedUid: uid,
          onAccepted: preset == null ? _input.clear : null,
        );
  }

  void _consumePending() {
    if (!ref.read(chatControllerProvider).hydrated) return;
    final pending =
        ref.read(chatControllerProvider.notifier).takePendingPrompt();
    if (pending != null) _input.text = pending;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final chat = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    // Prompt deixado por outra tela: consome ao hidratar e tambem quando chega
    // com o chat ja hidratado.
    ref.listen(chatControllerProvider.select((s) => s.hydrated), (_, hydrated) {
      if (hydrated) _consumePending();
    });
    ref.listen(pendingOraclePromptProvider, (_, pending) {
      if (pending != null) _consumePending();
    });
    // Rascunho de um usuario nao pode aparecer para o proximo.
    ref.listen(currentUidProvider, (_, __) => _input.clear());
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
          if (chat.error && !chat.hydrated)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Não foi possível carregar o histórico.',
                        style: TextStyle(color: AstrumColors.muted)),
                  ),
                  TextButton(
                    onPressed: controller.retry,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
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
                        onPressed: profile == null ||
                                !chat.hydrated ||
                                chat.limitReached
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
                  onPressed: chat.loading ||
                          profile == null ||
                          !chat.hydrated ||
                          chat.limitReached
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
