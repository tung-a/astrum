import 'dart:convert';

import 'package:astrum/features/oracle/data/legacy_chat_repository.dart';
import 'package:astrum/features/oracle/data/legacy_chat_store.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late LegacyChatStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = LegacyChatStore(prefs);
  });

  test('e um LegacyChatRepository', () {
    expect(store, isA<LegacyChatRepository>());
  });

  test('sem historico, load devolve uma conversa vazia "Conversa 1"', () async {
    final all = await store.load('u1');
    expect(all, hasLength(1));
    expect(all.single.title, 'Conversa 1');
    expect(all.single.messages, isEmpty);
  });

  test('save grava na chave astrum.chat.<uid> com o JSON de sempre', () async {
    await store.save('u1', const [
      ChatConversation(id: 'a', title: 'Oi', messages: [
        ChatTurnStored(role: 'user', text: 'Oi'),
        ChatTurnStored(role: 'model', text: 'Ola'),
      ]),
      ChatConversation(id: 'b', title: 'Conversa 2', messages: []),
    ]);

    expect(prefs.getKeys(), {'astrum.chat.u1'});
    expect(
        prefs.getString('astrum.chat.u1'),
        '{"conversations":['
        '{"id":"a","title":"Oi","messages":['
        '{"role":"user","text":"Oi"},{"role":"model","text":"Ola"}]},'
        '{"id":"b","title":"Conversa 2","messages":[]}]}');
  });

  test('load le o que save gravou', () async {
    await store.save('u1', const [
      ChatConversation(id: 'a', title: 'Oi', messages: [
        ChatTurnStored(role: 'user', text: 'Oi'),
      ]),
    ]);

    final all = await store.load('u1');

    expect(all.single.id, 'a');
    expect(all.single.messages.single.text, 'Oi');
    expect(jsonDecode(prefs.getString('astrum.chat.u1')!), isA<Map>());
  });

  test('JSON corrompido ou lista vazia cai em uma conversa vazia', () async {
    await prefs.setString('astrum.chat.u1', 'nao e json');
    expect(await store.load('u1'), hasLength(1));
    await prefs.setString('astrum.chat.u1', '{"conversations":[]}');
    expect(await store.load('u1'), hasLength(1));
  });

  test('historicos de usuarios diferentes nao se misturam', () async {
    await store.save('u1', const [
      ChatConversation(id: 'a', title: 'A', messages: []),
    ]);
    expect((await store.load('u2')).single.id, isNot('a'));
  });
}
