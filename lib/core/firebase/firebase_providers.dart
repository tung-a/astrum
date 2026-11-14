import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Instancias do Firebase injetaveis. Em testes, sobrescreva com fakes.
/// So devem ser lidas depois de `Firebase.initializeApp` (o app sem config
/// nao monta nenhum provider que dependa delas).
final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
