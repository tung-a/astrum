import 'package:shared_preferences/shared_preferences.dart';

/// Guarda, por uid, se o aviso de privacidade do historico ja foi mostrado.
/// E uma flag de UI (nao dado pessoal) e nao e consentimento com recusa.
class ChatNoticeStore {
  const ChatNoticeStore(this._prefs);

  final SharedPreferences _prefs;

  static const _legacyPrefix = 'astrum.chat.';
  static const _noticePrefix = 'astrum.chat.notice.';

  /// Apaga o historico local antigo (`astrum.chat.<uid>`, pre-etapa 10) que
  /// ainda esteja no aparelho. Nao toca na flag do aviso nem em outras chaves.
  Future<void> purgeLegacyChats() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_legacyPrefix) && !k.startsWith(_noticePrefix)) {
        await _prefs.remove(k);
      }
    }
  }

  static String _key(String uid) => 'astrum.chat.notice.$uid';

  bool seen(String uid) => _prefs.getBool(_key(uid)) ?? false;

  Future<void> markSeen(String uid) => _prefs.setBool(_key(uid), true);
}
