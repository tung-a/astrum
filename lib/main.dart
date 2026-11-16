import 'package:astrum/app/app.dart';
import 'package:astrum/core/config/env.dart';
import 'package:astrum/core/storage/local_data_cleaner.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  if (Env.hasFirebase) {
    await Firebase.initializeApp(options: Env.firebaseOptions);
    // Limpeza do cache do Firestore marcada no logout/exclusao: antes de
    // qualquer uso do Firestore.
    await LocalDataCleaner(prefs)
        .runPendingCacheWipe(FirebaseFirestore.instance);
  }

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const AstrumApp(),
    ),
  );
}
