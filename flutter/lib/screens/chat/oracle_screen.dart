import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../services/oracle_service.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

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
  List<ChatConversation> _conversations = [];
  int _index = 0;
  bool _loading = false;
  bool _hydrated = false;

  ChatConversation get _current =>
      _conversations.isEmpty ? const ChatConversation(id: 'x', title: 'Conversa', messages: []) : _conversations[_index];

  @override
  void dispose() {
    _input.dispose();
    _tts.stop();
    super.dispose();
  }

  void _hydrate(String uid) {
    if (_hydrated) return;
    _hydrated = true;
    final loaded = ref.read(chatStoreProvider).load(uid);
    setState(() {
      _conversations = loaded;
      _index = 0;
    });
    final pending = ref.read(pendingOraclePromptProvider);
    if (pending != null) {
      _input.text = pending;
      ref.read(pendingOraclePromptProvider.notifier).state = null;
    }
  }

  Future<void> _persist(String uid) {
    return ref.read(chatStoreProvider).save(uid, _conversations);
  }

  Future<void> _send(String uid, String? sign, {String? preset}) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _input.clear();
      final msgs = [..._current.messages, ChatTurnStored(role: 'user', text: text)];
      _conversations = [..._conversations]..[_index] = ChatConversation(
          id: _current.id,
          title: _current.messages.isEmpty ? text : _current.title,
          messages: msgs,
        );
    });
    await _persist(uid);
    final history = _current.messages
        .map((m) => ChatTurn(role: m.role, text: m.text))
        .toList();
    // last user already included
    final reply = await ref.read(oracleServiceProvider).complete(
          prompt: text,
          history: history.take(history.length - 1).toList(),
          sign: sign,
        );
    setState(() {
      _conversations = [..._conversations]..[_index] = ChatConversation(
          id: _current.id,
          title: _current.title,
          messages: [..._current.messages, ChatTurnStored(role: 'model', text: reply)],
        );
      _loading = false;
    });
    await _persist(uid);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate(profile.uid));
    }

    return CosmicScaffold(
      title: 'Oráculo',
      actions: [
        IconButton(
          tooltip: 'Nova conversa',
          onPressed: profile == null
              ? null
              : () async {
                  final next = ref.read(chatStoreProvider).create(_conversations.length + 1);
                  setState(() {
                    _conversations = [..._conversations, next];
                    _index = _conversations.length - 1;
                  });
                  await _persist(profile.uid);
                },
          icon: const Icon(Icons.add_comment_outlined),
        ),
        if (_conversations.length > 1)
          PopupMenuButton<int>(
            onSelected: (i) => setState(() => _index = i),
            itemBuilder: (context) => [
              for (var i = 0; i < _conversations.length; i++)
                PopupMenuItem(value: i, child: Text(_conversations[i].title)),
            ],
          ),
      ],
      body: Column(
        children: [
          if (_current.messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _starters
                    .map(
                      (q) => ActionChip(
                        label: Text(q),
                        onPressed: profile == null
                            ? null
                            : () => _send(profile.uid, profile.zodiacSign, preset: q),
                      ),
                    )
                    .toList(),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _current.messages.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _current.messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('O oráculo consulta as esferas…',
                        style: TextStyle(color: AstrumColors.muted)),
                  );
                }
                final msg = _current.messages[i];
                final mine = msg.role == 'user';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
                            p: const TextStyle(color: AstrumColors.cream, height: 1.4),
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
                    decoration: const InputDecoration(hintText: 'Pergunte ao oráculo…'),
                    onSubmitted: (_) {
                      if (profile != null) {
                        _send(profile.uid, profile.zodiacSign);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading || profile == null
                      ? null
                      : () => _send(profile.uid, profile.zodiacSign),
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
