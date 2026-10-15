import 'package:firebase_core/firebase_core.dart';

class Env {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAuthDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const groqApiKey = String.fromEnvironment('GROQ_API_KEY');

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty;

  static bool get hasGroq => groqApiKey.isNotEmpty;

  static FirebaseOptions get firebaseOptions => FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        messagingSenderId: firebaseMessagingSenderId,
        projectId: firebaseProjectId,
        authDomain: firebaseAuthDomain,
        storageBucket: firebaseStorageBucket,
      );

  static List<String> get missingFirebaseVars {
    final pairs = <String, String>{
      'FIREBASE_API_KEY': firebaseApiKey,
      'FIREBASE_AUTH_DOMAIN': firebaseAuthDomain,
      'FIREBASE_PROJECT_ID': firebaseProjectId,
      'FIREBASE_STORAGE_BUCKET': firebaseStorageBucket,
      'FIREBASE_MESSAGING_SENDER_ID': firebaseMessagingSenderId,
      'FIREBASE_APP_ID': firebaseAppId,
    };
    return pairs.entries
        .where((e) => e.value.isEmpty)
        .map((e) => e.key)
        .toList();
  }
}
