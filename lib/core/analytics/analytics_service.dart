import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:astrum/core/firebase/rules_contract.dart';

class AnalyticsService {
  AnalyticsService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<void> logEvent(String eventName) async {
    try {
      await _firestore.collection('analytics_events').add({
        'eventName': eventName,
        'userId': _auth.currentUser?.uid ?? anonymousUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      debugPrint('Falha ao registrar evento "$eventName": ${error.message}');
    }
  }
}
