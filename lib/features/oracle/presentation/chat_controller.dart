import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Texto mostrado (nao persistido) quando a conversa nao comporta mais mensagens.
const chatLimitText =
    'Esta conversa atingiu o limite. Inicie uma nova conversa.';

const _replyError = 'Não foi possível obter a resposta. Tente novamente.';

/// Resultado da exclusao de uma conversa ou de todo o historico.
enum ChatDeleteResult { ok, offline, failed }

class ChatState {
  const ChatState({
    this.conversations = const [],
    this.selectedId,
    this.loading = false,
    this.hydrated = false,
    this.error = false,
    this.limitReached = false,
    this.deleting = false,
  });

  /// Rascunho (se houver) e depois as conversas da nuvem, da mais recente para
  /// a mais antiga. So a conversa selecionada traz `messages`.
  final List<ChatConversation> conversations;
  final String? selectedId;
  final bool loading;
  final bool hydrated;

  /// Falha ao carregar o historico (antes da hidratacao); a tela oferece
  /// "Tentar de novo".
  final bool error;

  /// A conversa selecionada nao comporta mais mensagens (calculado pelo
  /// controller, nao pelo texto exibido).
  final bool limitReached;

  /// Exclusao de conversa(s) em andamento: envio, chips, "Nova conversa" e o
  /// menu ficam desabilitados.
  final bool deleting;

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
    bool? error,
    bool? limitReached,
    bool? deleting,
  }) =>
      ChatState(
        conversations: conversations ?? this.conversations,
        selectedId: selectedId ?? this.selectedId,
        loading: loading ?? this.loading,
        hydrated: hydrated ?? this.hydrated,
        error: error ?? this.error,
        limitReached: limitReached ?? this.limitReached,
        deleting: deleting ?? this.deleting,
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
  final _created = <String>{};
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
    _created.clear();
    _lastCreated.clear();
    ref.onDispose(() {
      _alive = false;
      _listSub?.cancel();
      _msgSub?.cancel();
      _listSub = _msgSub = null;
    });
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
      onError: (Object e) {
        _log('lista', e);
        if (!_alive || gen != _gen) return;
        if (!state.hydrated) state = state.copyWith(error: true);
      },
    );
  }

  /// "Tentar de novo" depois de uma falha ao carregar o historico.
  Future<void> retry() async {
    if (state.hydrated) return;
    unawaited(_listSub?.cancel());
    _listSub = null;
    _hydrateStarted = false;
    state = state.copyWith(error: false);
    await hydrate();
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
    _emit(hydrated: first ? true : null, error: false);
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

  void _emit({bool? hydrated, bool? error}) {
    final all = <ChatConversation>[
      if (_draft != null) _draft!,
      ..._cloud,
    ];
    final selected = _selectedId;
    final full = _full;
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
              if (full)
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
      error: error,
      limitReached: full,
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
        .catchError((Object e) {
      _log('gravacao', e);
      if (isNew) _created.remove(convId);
    }));
  }

  /// Devolve true se o envio foi ACEITO (a pergunta vai ser gravada);
  /// false se foi recusado (vazio, resposta em andamento, nao hidratado,
  /// sem usuario, conversa cheia) e nada mudou. [onAccepted] roda de forma
  /// sincrona na aceitacao, antes de aguardar o oraculo (a tela limpa o
  /// campo ali); [expectedUid] recusa o envio se o usuario mudou desde que a
  /// tela o leu (ex.: durante o aviso).
  Future<bool> send(
    String text, {
    String? expectedUid,
    VoidCallback? onAccepted,
  }) async {
    final trimmed = text.trim();
    final uid = _uid;
    if (trimmed.isEmpty ||
        state.loading ||
        state.deleting ||
        !state.hydrated ||
        uid == null ||
        (expectedUid != null && expectedUid != uid)) {
      return false;
    }
    final convId = _selectedId;
    if (convId == null || _full) return false;
    onAccepted?.call();
    final gen = _gen;
    final profile = ref.read(profileProvider).valueOrNull;
    final repo = ref.read(chatRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final oracle = ref.read(oracleServiceProvider);
    final isNew = _draft?.id == convId && !_created.contains(convId);
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
    // A 2a mensagem nao pode criar a conversa de novo (o rascunho so some
    // quando a nuvem confirma).
    if (isNew) _created.add(convId);
    String reply;
    try {
      await analytics.logEvent('send_message_chat');
      reply = await oracle.complete(prompt: clamped, sign: profile?.zodiacSign);
    } catch (_) {
      reply = _replyError;
    }
    // Usuario trocou/saiu ou a tela foi descartada: nao grava.
    if (!_alive || gen != _gen) return true;
    state = state.copyWith(loading: false);
    // Conversa excluida em outro aparelho: descarta a resposta.
    if (_everSeen.contains(convId) && !_cloud.any((c) => c.id == convId)) {
      return true;
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
    return true;
  }

  /// Rascunho em memoria; nao grava. Se ja ha um rascunho vazio, so o seleciona.
  Future<void> newConversation() async {
    if (!state.hydrated || _uid == null || state.deleting) return;
    _draft ??= ChatConversation(
        id: ref.read(chatRepositoryProvider).newId(),
        title: 'Conversa ${_cloud.length + 1}',
        messages: const []);
    _select(_draft!.id, emit: false);
    _emit();
  }

  /// A conversa selecionada e um rascunho que nunca foi gravado.
  bool get currentIsUnsavedDraft =>
      _draft != null &&
      _draft!.id == _selectedId &&
      !_created.contains(_selectedId);

  /// Apaga a conversa selecionada da nuvem (e de todos os aparelhos). Rascunho
  /// nunca gravado so e descartado em memoria. A lista reativa seleciona a
  /// proxima conversa (ou um rascunho novo).
  Future<ChatDeleteResult> deleteCurrent() async {
    final uid = _uid;
    final convId = _selectedId;
    if (uid == null || convId == null || !state.hydrated || state.deleting) {
      return ChatDeleteResult.failed;
    }
    if (currentIsUnsavedDraft) {
      _draft = null;
      _created.remove(convId);
      final next = _cloud.firstOrNull;
      if (next != null) {
        _select(next.id, emit: false);
      } else {
        _draft = ChatConversation(
            id: ref.read(chatRepositoryProvider).newId(),
            title: 'Conversa 1',
            messages: const []);
        _select(_draft!.id, emit: false);
      }
      _emit();
      return ChatDeleteResult.ok;
    }
    final gen = _gen;
    state = state.copyWith(deleting: true);
    try {
      await ref.read(chatRepositoryProvider).deleteConversation(uid, convId);
      unawaited(ref
          .read(analyticsServiceProvider)
          .logEvent('chat_delete_conversation'));
      return ChatDeleteResult.ok;
    } catch (e) {
      return _deleteFailure(e, 'exclusao');
    } finally {
      if (_alive && gen == _gen) state = state.copyWith(deleting: false);
    }
  }

  /// Apaga todo o historico (inclusive o que nao aparece na lista).
  Future<ChatDeleteResult> deleteAll() async {
    final uid = _uid;
    if (uid == null || !state.hydrated || state.deleting) {
      return ChatDeleteResult.failed;
    }
    final gen = _gen;
    state = state.copyWith(deleting: true);
    try {
      await ref.read(chatRepositoryProvider).deleteAllConversations(uid);
      unawaited(ref.read(analyticsServiceProvider).logEvent('chat_delete_all'));
      return ChatDeleteResult.ok;
    } catch (e) {
      return _deleteFailure(e, 'exclusao total');
    } finally {
      if (_alive && gen == _gen) state = state.copyWith(deleting: false);
    }
  }

  /// So o tipo/codigo do erro vai ao log; nunca texto de conversa.
  ChatDeleteResult _deleteFailure(Object e, String where) {
    if (e is FirebaseException) {
      debugPrint('chat: erro em $where (${e.code})');
      return e.code == 'unavailable' || e.code == 'deadline-exceeded'
          ? ChatDeleteResult.offline
          : ChatDeleteResult.failed;
    }
    _log(where, e);
    return e is ChatOfflineException
        ? ChatDeleteResult.offline
        : ChatDeleteResult.failed;
  }

  void select(int index) {
    if (index < 0 || index >= state.conversations.length) return;
    _select(state.conversations[index].id, emit: true);
  }
}
