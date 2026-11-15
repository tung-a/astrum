import 'package:shared_preferences/shared_preferences.dart';

/// Guarda, por uid, se o aviso de privacidade do historico ja foi mostrado.
/// E uma flag de UI (nao dado pessoal) e nao e consentimento com recusa.
class ChatNoticeStore {
  const ChatNoticeStore(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String uid) => 'astrum.chat.notice.$uid';

  bool seen(String uid) => _prefs.getBool(_key(uid)) ?? false;

  Future<void> markSeen(String uid) => _prefs.setBool(_key(uid), true);
}
