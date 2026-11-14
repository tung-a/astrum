import 'package:cloud_firestore/cloud_firestore.dart';

/// Caminhos de documentos do Firestore (so strings, nenhum comportamento).
extension FirestorePaths on FirebaseFirestore {
  CollectionReference<Map<String, dynamic>> get usersCol =>
      collection('users');

  CollectionReference<Map<String, dynamic>> get publicCol =>
      collection('publicProfiles');

  DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> publicDoc(String uid) =>
      collection('publicProfiles').doc(uid);

  DocumentReference<Map<String, dynamic>> shopItemDoc(String id) =>
      collection('shop_items').doc(id);
}
