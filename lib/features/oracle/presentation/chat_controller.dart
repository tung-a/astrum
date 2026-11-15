import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Texto mostrado (nao persistido) quando a conversa nao comporta mais mensagens.
const chatLimitText =
    'Esta conversa atingiu o limite. Inicie uma nova conversa.';

const _replyError = 'Não foi possível obter a resposta. Tente novamente.';

class ChatState {
  const ChatState({
    this.conversations = const [],
    this.selectedId,
    this.loading = false,
    this.hydrated = false,
  });

  /// Rascunho (se houver) e depois as conversas da nuvem, da mais recente para
  /// a mais antiga. So a conversa selecionada traz `messages`.
  final List<ChatConversation> conversations;
  final String? selectedId;
  final bool loading;
  final bool hydrated;

  /// A conversa selecionada nao comporta mais mensagens.
  bool get limitReached =>
      current.messages.isNotEmpty &&
      current.messages.last.text == chatLimitText;

  int get index {
    final i = conversations.indexWhere((c) => c.id == selectedId);
    return i < 0 ? 0 : i;
  }

  /// Conversa atual; antes da hidratacao, um placeholder vazio.
  ChatConversation get current => conversations.isEmpty
      ? const ChatConversation(id: 'x', title: 'Conversa', messages: [])
      : conversations[index];

  ChatState copyWith({
    List<ChatConversation>? conversations,
    String? selectedId,
    bool? loading,
    bool? hydrated,
  }) =>
      ChatState(
        conversations: conversations ?? this.conversations,
        selectedId: selectedId ?? this.selectedId,
        loading: loading ?? this.loading,
        hydrated: hydrated ?? this.hydrated,
      );
}

final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatState>(ChatController.new);

/// Estado e regras do chat do oraculo sobre o Firestore (etapa 10); a tela so
/// renderiza e fala (TTS).
///
/// - `build` depende de `currentUidProvider`: trocar de usuario reinicia o
///   estado e o contador de geracao invalida respostas pendentes do uid antigo.
/// - "Nova conversa" e um rascunho em memoria; o documento nasce com a 1a
///   mensagem.
/// - A resposta e gravada na conversa de origem, por id.
/// - Nenhum texto de conversa vai a analytics, logs ou excecoes.
class ChatController extends AutoDisposeNotifier<ChatState> {
  // Riverpod 2.6 nao tem ref.mounted.
  bool _alive = true;
  int _gen = 0;
  String? _uid;
  bool _hydrateStarted = false;

  StreamSubscription<List<ChatConversation>>? _listSub;
  StreamSubscription<List<ChatTurnStored>>? _msgSub;
  List<ChatConversation> _cloud = const [];
  List<ChatTurnStored> _messages = const [];
  ChatConversation? _draft;
  String? _selectedId;
  final _everSeen = <String>{};
  final _lastCreated = <String, DateTime>{};

  @override
  ChatState build() {
    _gen++;
    _alive = true;
    _uid = ref.watch(currentUidProvider);
    _hydrateStarted = false;
    _cloud = const [];
    _messages = const [];
    _draft = null;
    _selectedId = null;
    _everSeen.clear();
    _lastCreated.clear();
    ref.onDispose(() {
      _alive = false;
      _listSub?.cancel();
      _msgSub?.cancel();
      _listSub = _msgSub = null;
    });
    // Rebuild por troca de uid: cancela os listeners do usuario anterior.
    _listSub?.cancel();
    _msgSub?.cancel();
    _listSub = _msgSub = null;
    return const ChatState();
  }

  /// Registro sem texto de conversa: so o tipo/codigo do erro.
  void _log(String where, Object e) =>
      debugPrint('chat: erro em $where (${e.runtimeType})');

  /// Assina a lista de conversas uma vez (a tela chama em post-frame).
  Future<void> hydrate() async {
    final uid = _uid;
    if (_hydrateStarted || uid == null) return;
    _hydrateStarted = true;
    final gen = _gen;
    _listSub = ref.read(chatRepositoryProvider).watchConversations(uid).listen(
      (list) {
        if (!_alive || gen != _gen) return;
        _onCloud(list);
      },
      onError: (Object e) => _log('lista', e),
    );
  }

  void _onCloud(List<ChatConversation> list) {
    _cloud = list;
    for (final c in list) {
      _everSeen.add(c.id);
    }
    if (_draft != null && list.any((c) => c.id == _draft!.id)) _draft = null;
    final first = !state.hydrated;
    final ids = {for (final c in list) c.id, if (_draft != null) _draft!.id};
    if (_selectedId == null || !ids.contains(_selectedId)) {
      // Abre na mais recente; sem conversas, num rascunho "Conversa 1".
      if (list.isNotEmpty) {
        _select(list.first.id, emit: false);
      } else {
        _draft ??= ChatConversation(
            id: ref.read(chatRepositoryProvider).newId(),
            title: 'Conversa 1',
            messages: const []);
        _select(_draft!.id, emit: false);
      }
    }
    _emit(hydrated: first ? true : null);
  }

  void _select(String id, {required bool emit}) {
    if (_selectedId == id && _msgSub != null) return;
    final uid = _uid;
    if (uid == null) return;
    _selectedId = id;
    _messages = const [];
    _msgSub?.cancel();
    final gen = _gen;
    _msgSub = ref.read(chatRepositoryProvider).watchMessages(uid, id).listen(
      (msgs) {
        if (!_alive || gen != _gen || _selectedId != id) return;
        _messages = msgs;
        _emit();
      },
      onError: (Object e) => _log('mensagens', e),
    );
    if (emit) _emit();
  }

  int get _count {
    final meta = _cloud.where((c) => c.id == _selectedId).firstOrNull;
    final n = meta?.messageCount ?? 0;
    return n > _messages.length ? n : _messages.length;
  }

  /// Cabe a pergunta e a resposta (a regra aceita no maximo 500 mensagens).
  bool get _full => _count > chatMessagesMax - 2;

  void _emit({bool? hydrated}) {
    final all = <ChatConversation>[
      if (_draft != null) _draft!,
      ..._cloud,
    ];
    final selected = _selectedId;
    final composed = [
      for (final c in all)
        if (c.id == selected)
          ChatConversation(
            id: c.id,
            title: c.title,
            updatedAt: c.updatedAt,
            messageCount: c.messageCount,
            messages: [
              ..._messages,
              if (_full)
                const ChatTurnStored(role: 'model', text: chatLimitText),
            ],
          )
        else
          c,
    ];
    state = state.copyWith(
      conversations: composed,
      selectedId: selected,
      hydrated: hydrated,
    );
  }

  /// Devolve e limpa o prompt que outra tela deixou para o oraculo.
  String? takePendingPrompt() {
    final pending = ref.read(pendingOraclePromptProvider);
    if (pending != null) {
      ref.read(pendingOraclePromptProvider.notifier).state = null;
    }
    return pending;
  }

  /// `createdAt` estritamente crescente por conversa (a resposta nunca empata
  /// com a pergunta).
  DateTime _next(String convId) {
    final now = ref.read(clockProvider)();
    final last = _lastCreated[convId];
    final t = last != null && !now.isAfter(last)
        ? last.add(const Duration(milliseconds: 1))
        : now;
    return _lastCreated[convId] = t;
  }

  void _write(
    String uid,
    String convId,
    ChatTurnStored message, {
    String? title,
    bool isNew = false,
  }) {
    // Sem await: offline o Future so completa com o servidor.
    unawaited(ref
        .read(chatRepositoryProvider)
        .appendMessage(uid,
            convId: convId,
            message: message,
            updatedAt: message.createdAt!,
            title: title,
            isNew: isNew)
        .catchError((Object e) => _log('gravacao', e)));
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    final uid = _uid;
    if (trimmed.isEmpty || state.loading || !state.hydrated || uid == null) {
      return;
    }
    final convId = _selectedId;
    if (convId == null || _full) return;
    final gen = _gen;
    final profile = ref.read(profileProvider).valueOrNull;
    final repo = ref.read(chatRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final oracle = ref.read(oracleServiceProvider);
    final isNew = _draft?.id == convId;
    final clamped = clampText(trimmed);

    state = state.copyWith(loading: true);
    _write(
      uid,
      convId,
      ChatTurnStored(
          id: repo.newId(),
          role: 'user',
          text: clamped,
          createdAt: _next(convId)),
      title: isNew ? titleFrom(trimmed) : null,
      isNew: isNew,
    );
    String reply;
    try {
      await analytics.logEvent('send_message_chat');
      reply = await oracle.complete(prompt: clamped, sign: profile?.zodiacSign);
    } catch (_) {
      reply = _replyError;
    }
    // Usuario trocou/saiu ou a tela foi descartada: nao grava.
    if (!_alive || gen != _gen) return;
    state = state.copyWith(loading: false);
    // Conversa excluida em outro aparelho: descarta a resposta.
    if (_everSeen.contains(convId) && !_cloud.any((c) => c.id == convId)) {
      return;
    }
    _write(
      uid,
      convId,
      ChatTurnStored(
          id: repo.newId(),
          role: 'model',
          text: clampText(reply),
          createdAt: _next(convId)),
    );
  }

  /// Rascunho em memoria; nao grava. Se ja ha um rascunho vazio, so o seleciona.
  Future<void> newConversation() async {
    if (!state.hydrated || _uid == null) return;
    _draft ??= ChatConversation(
        id: ref.read(chatRepositoryProvider).newId(),
        title: 'Conversa ${_cloud.length + 1}',
        messages: const []);
    _select(_draft!.id, emit: false);
    _emit();
  }

  void select(int index) {
    if (index < 0 || index >= state.conversations.length) return;
    _select(state.conversations[index].id, emit: true);
  }
}
