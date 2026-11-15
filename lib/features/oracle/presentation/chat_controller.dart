import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatState {
  const ChatState({
    this.conversations = const [],
    this.index = 0,
    this.loading = false,
    this.hydrated = false,
  });

  final List<ChatConversation> conversations;
  final int index;
  final bool loading;
  final bool hydrated;

  /// Conversa atual; antes da hidratacao, um placeholder vazio.
  ChatConversation get current => conversations.isEmpty
      ? const ChatConversation(id: 'x', title: 'Conversa', messages: [])
      : conversations[index];

  ChatState copyWith({
    List<ChatConversation>? conversations,
    int? index,
    bool? loading,
    bool? hydrated,
  }) =>
      ChatState(
        conversations: conversations ?? this.conversations,
        index: index ?? this.index,
        loading: loading ?? this.loading,
        hydrated: hydrated ?? this.hydrated,
      );
}

final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatState>(ChatController.new);

/// Estado e regras do chat do oraculo; a tela so renderiza e fala (TTS).
///
/// Defeitos da refatoracao original corrigidos: `loading` e liberado mesmo se
/// `complete`/`save` lancar (a conversa recebe uma resposta de erro); a
/// resposta vai para a conversa que originou o envio, mesmo se o usuario
/// trocar de conversa; envio antes da hidratacao e ignorado.
class ChatController extends AutoDisposeNotifier<ChatState> {
  // Riverpod 2.6 nao tem ref.mounted: o flag evita escrever state depois do
  // dispose, como o State.mounted da tela fazia.
  bool _alive = true;
  bool _hydrateStarted = false;

  @override
  ChatState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const ChatState();
  }

  /// Carrega o historico uma vez, quando ha perfil (a tela chama em post-frame).
  Future<void> hydrate() async {
    if (_hydrateStarted) return;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    _hydrateStarted = true;
    final loaded = await ref.read(chatRepositoryProvider).load(profile.uid);
    if (!_alive) return;
    state = state.copyWith(conversations: loaded, index: 0, hydrated: true);
  }

  /// Devolve e limpa o prompt que outra tela deixou para o oraculo.
  String? takePendingPrompt() {
    final pending = ref.read(pendingOraclePromptProvider);
    if (pending != null) {
      ref.read(pendingOraclePromptProvider.notifier).state = null;
    }
    return pending;
  }

  Future<void> _persist(String uid) =>
      ref.read(chatRepositoryProvider).save(uid, state.conversations);

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.loading || !state.hydrated) return;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final uid = profile.uid;
    final sign = profile.zodiacSign;
    final repo = ref.read(chatRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final oracle = ref.read(oracleServiceProvider);

    final current = state.current;
    final convId = current.id; // a resposta volta para esta conversa
    state = state.copyWith(
      loading: true,
      conversations: [...state.conversations]..[state.index] = ChatConversation(
          id: current.id,
          title: current.messages.isEmpty ? trimmed : current.title,
          messages: [
            ...current.messages,
            ChatTurnStored(role: 'user', text: trimmed),
          ],
        ),
    );
    String reply;
    try {
      await repo.save(uid, state.conversations);
      await analytics.logEvent('send_message_chat');
      reply = await oracle.complete(prompt: trimmed, sign: sign);
    } catch (_) {
      reply = 'Não foi possível obter a resposta. Tente novamente.';
    }
    if (!_alive) return;
    final idx = state.conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) {
      state = state.copyWith(loading: false);
      return;
    }
    final target = state.conversations[idx];
    state = state.copyWith(
      loading: false,
      conversations: [...state.conversations]..[idx] = ChatConversation(
          id: target.id,
          title: target.title,
          messages: [
            ...target.messages,
            ChatTurnStored(role: 'model', text: reply)
          ],
        ),
    );
    try {
      await repo.save(uid, state.conversations);
    } catch (_) {
      // Resposta ja esta na tela; a proxima gravacao leva o historico inteiro.
    }
  }

  Future<void> newConversation() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final next =
        ref.read(chatRepositoryProvider).create(state.conversations.length + 1);
    final all = [...state.conversations, next];
    state = state.copyWith(conversations: all, index: all.length - 1);
    await _persist(profile.uid);
  }

  void select(int index) => state = state.copyWith(index: index);
}
