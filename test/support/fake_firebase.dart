// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FakeUser implements User {
  FakeUser(this.uid, {this.email = 'a@b.c', this.displayName});

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class FakeFirebaseAuth implements FirebaseAuth {
  FakeFirebaseAuth([this._user]);

  User? _user;
  final _changes = StreamController<User?>.broadcast();
  int authStateChangesCalls = 0;

  void setUser(User? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  User? get currentUser => _user;

  void setError(Object error) => _changes.addError(error);

  /// Como o FirebaseAuth real: emite o usuario atual ao assinar e depois
  /// acompanha as mudancas. Cada assinatura cancelada e contabilizada.
  @override
  Stream<User?> authStateChanges() {
    authStateChangesCalls++;
    return Stream<User?>.multi((c) {
      c.add(_user);
      final sub = _changes.stream.listen(c.add, onError: c.addError);
      c.onCancel = sub.cancel;
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class FakeDocSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  FakeDocSnapshot(this._data);
  final Map<String, dynamic>? _data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  FakeDocRef(this.path, this._data);

  @override
  final String path;
  final Map<String, dynamic>? _data;

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      Stream.value(FakeDocSnapshot(_data));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class FakeCollection implements CollectionReference<Map<String, dynamic>> {
  FakeCollection(this.db, this.name);
  final FakeFirestore db;
  final String name;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final full = '$name/$path';
    db.docPaths.add(full);
    return FakeDocRef(full, db.docs[full]);
  }

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
      Map<String, dynamic> data) async {
    db.added.add((name, data));
    return FakeDocRef('$name/auto', data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class FakeFirestore implements FirebaseFirestore {
  final docs = <String, Map<String, dynamic>>{};
  final docPaths = <String>[];
  final added = <(String, Map<String, dynamic>)>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      FakeCollection(this, path);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
