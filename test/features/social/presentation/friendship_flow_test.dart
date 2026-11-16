import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/friendship_controller.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fluxo de amizade entre DUAS contas (Ana e Bruno), com o SocialRepository
/// real sobre fake_cloud_firestore. Cada conta tem o seu ProviderContainer,
/// como dois aparelhos que compartilham o mesmo banco.
///
/// fake_cloud_firestore NAO avalia regras: o que o servidor aceita fica em
/// test_rules/. Aqui se verifica a logica de ponta a ponta (textos, listas
/// nos dois lados, selo, cota, recusa silenciosa, lapide, desbloqueio).

const _ana = AppUser(uid: 'u1', email: 'ana@x.com', name: 'Ana');
const _bruno = AppUser(uid: 'u2', email: 'bruno@x.com', name: 'Bruno');

void main() {
  late FakeFirebaseFirestore db;
  late ProviderContainer ana;
  late ProviderContainer bruno;

  /// Espera o stream do Firestore (fake) entregar a nova emissao.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<void> seedPerfil(AppUser u, {bool buscavel = true}) async {
    await db.collection('users').doc(u.uid).set({'name': u.name});
    if (buscavel) {
      await db.collection('publicProfiles').doc(u.uid).set({
        'name': u.name,
        'avatar': '',
        'emailHash': hashEmail(u.email),
      });
    }
  }

  Future<ProviderContainer> aparelho(AppUser user) async {
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      profileProvider.overrideWith((ref) => Stream<AppUser?>.value(user)),
      currentUidProvider.overrideWithValue(user.uid),
    ]);
    addTearDown(c.dispose);
    await c.read(profileProvider.future);
    c.listen(friendshipsViewProvider, (_, __) {});
    return c;
  }

  FriendshipController ctl(ProviderContainer c) =>
      c.read(friendshipControllerProvider.notifier);

  FriendshipsView viewOf(ProviderContainer c) =>
      c.read(friendshipsViewProvider).valueOrNull!;

  /// Ana pede a Bruno pela busca (e-mail) e confirma: o pedido fica pendente.
  Future<void> anaPedeAoBruno() async {
    final achado = await ctl(ana).lookup('bruno@x.com');
    expect(achado.friend, isNotNull);
    expect(await ctl(ana).sendRequest(achado.friend!), 'Pedido enviado a Bruno.');
    await settle();
  }

  /// Ana e Bruno viram amigos (pedido de Ana, aceite de Bruno).
  Future<void> viramAmigos() async {
    await anaPedeAoBruno();
    final pedido = viewOf(bruno).incoming.single;
    expect(await ctl(bruno).accept(pedido),
        'Ana entrou na sua constelação.');
    await settle();
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seedPerfil(_ana);
    await seedPerfil(_bruno);
    ana = await aparelho(_ana);
    bruno = await aparelho(_bruno);
    bruno.listen(incomingRequestCountProvider, (_, __) {});
  });

  test('fluxo completo: buscar, enviar, ver em Enviados, aceitar no outro lado '
      'e trocar intencao', () async {
    final achado = await ctl(ana).lookup('bruno@x.com');
    expect(achado.message, isNull);
    expect(achado.friend?.name, 'Bruno');

    expect(await ctl(ana).sendRequest(achado.friend!),
        'Pedido enviado a Bruno.');
    await settle();

    // Ana ve em Enviados (aguardando); Bruno ve em Recebidos e no selo.
    expect(viewOf(ana).outgoing, hasLength(1));
    expect(viewOf(ana).pendingOutgoingCount, 1);
    expect(viewOf(bruno).incoming, hasLength(1));
    expect(viewOf(bruno).incoming.single.requesterName, 'Ana');
    expect(bruno.read(incomingRequestCountProvider), 1);

    expect(await ctl(bruno).accept(viewOf(bruno).incoming.single),
        'Ana entrou na sua constelação.');
    await settle();

    // Amizade nos dois lados; o pedido sai de Enviados e do selo.
    expect(viewOf(ana).friends.map((f) => f.name), ['Bruno']);
    expect(viewOf(bruno).friends.map((f) => f.name), ['Ana']);
    expect(viewOf(ana).outgoing, isEmpty);
    expect(bruno.read(incomingRequestCountProvider), 0);

    // Intencao de Bruno para Ana (a regra de notifications so libera isso
    // com amizade aceita; aqui so se confere a gravacao na caixa de Ana).
    await bruno.read(socialRepositoryProvider).sendIntention(
          fromUid: 'u2',
          fromName: 'Bruno',
          toUid: 'u1',
          intentionId: 'luz',
          intentionLabel: 'Luz',
        );
    final caixa =
        await db.collection('users').doc('u1').collection('notifications').get();
    expect(caixa.docs, hasLength(1));
    expect(caixa.docs.single.data()['fromUid'], 'u2');
  });

  test('recusa silenciosa: quem recusa ve bloqueio proprio; quem pediu segue '
      'vendo "enviado" e nao pode pedir de novo', () async {
    await anaPedeAoBruno();

    expect(await ctl(bruno).decline(viewOf(bruno).incoming.single),
        'Pedido recusado.');
    await settle();

    // Bruno: fora de Recebidos, em "Recusados e removidos".
    expect(viewOf(bruno).incoming, isEmpty);
    expect(viewOf(bruno).blockedByMe, hasLength(1));

    // Ana: continua em Enviados como aguardando; nao conta na cota.
    expect(viewOf(ana).friends, isEmpty);
    expect(viewOf(ana).outgoing, hasLength(1));
    expect(viewOf(ana).pendingOutgoingCount, 0);

    // Novo pedido ao mesmo e-mail: mesma frase de "ja enviado", sem revelar a
    // recusa.
    final r = await ctl(ana).lookup('bruno@x.com');
    expect(r.message, friendAlreadySent);
    expect(await ctl(ana).sendRequest(Friend(id: 'u2', name: 'Bruno')),
        friendAlreadySent);

    // Cancelar o recusado: mesma resposta e nada escrito no servidor.
    expect(await ctl(ana).cancel(viewOf(ana).outgoing.single),
        friendRequestCancelled);
    final docs = await db.collection('friendships').get();
    expect(docs.docs, hasLength(1));
    expect(docs.docs.single.data()['status'], 'declined');

    // Quem recusou ve a propria mensagem; Ana, a generica de sempre.
    expect((await ctl(bruno).lookup('ana@x.com')).message, friendBlockedByMe);
  });

  test('remover, bloqueio e desbloqueio: remove dos dois lados, quem removeu '
      'desbloqueia e pode pedir de novo', () async {
    await viramAmigos();

    expect(await ctl(ana).remove(Friend(id: 'u2', name: 'Bruno')),
        'Amizade removida.');
    await settle();

    // Quem removeu: fora de Amigos, em bloqueados.
    expect(viewOf(ana).friends, isEmpty);
    expect(viewOf(ana).blockedByMe, hasLength(1));
    // Quem foi removido: some sem aviso e sem bloqueio proprio.
    expect(viewOf(bruno).friends, isEmpty);
    expect(viewOf(bruno).blockedByMe, isEmpty);

    // Bruno pode buscar Ana, mas o pedido recebe a frase generica (lapide).
    final achadoAna = await ctl(bruno).lookup('ana@x.com');
    expect(achadoAna.friend, isNotNull);
    expect(await ctl(bruno).sendRequest(achadoAna.friend!),
        friendRequestGeneric);

    // Ana ve a mensagem do proprio bloqueio.
    expect((await ctl(ana).lookup('bruno@x.com')).message, friendBlockedByMe);

    // Desbloquear apaga a lapide e libera um pedido novo.
    expect(await ctl(ana).unblock(viewOf(ana).blockedByMe.single),
        'Desbloqueado. Você pode buscar essa pessoa de novo.');
    await settle();
    expect(viewOf(ana).blockedByMe, isEmpty);
    expect(await ctl(ana).sendRequest(Friend(id: 'u2', name: 'Bruno')),
        'Pedido enviado a Bruno.');
  });

  test('pedido cruzado pela busca: o segundo pedido vira amizade', () async {
    await anaPedeAoBruno();

    // Bruno busca Ana (ele ja tem um pedido dela recebido) e pede tambem.
    final achado = await ctl(bruno).lookup('ana@x.com');
    expect(achado.friend, isNotNull);
    expect(await ctl(bruno).sendRequest(achado.friend!),
        friendCrossAccepted);
    await settle();

    expect(viewOf(ana).friends.map((f) => f.name), ['Bruno']);
    expect(viewOf(bruno).friends.map((f) => f.name), ['Ana']);
    expect((await db.collection('friendships').get()).docs, hasLength(1));
  });

  test('busca desligada no destinatario: mesma frase generica de e-mail '
      'inexistente, e nada e gravado', () async {
    // Bruno desliga "Aparecer na busca de amigos": some do publicProfiles.
    await db.collection('publicProfiles').doc('u2').delete();

    final desligado = await ctl(ana).lookup('bruno@x.com');
    final inexistente = await ctl(ana).lookup('ninguem@x.com');
    expect(desligado.friend, isNull);
    expect(desligado.message, friendRequestGeneric);
    expect(inexistente.message, desligado.message);

    expect((await db.collection('friendships').get()).docs, isEmpty);
  });
}
