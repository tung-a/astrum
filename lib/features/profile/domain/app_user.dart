import 'dart:convert';

import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/core/firebase/rules_contract.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.role = roleUser,
    this.zodiacSign = '',
    this.birthDate = '',
    this.birthTime = '',
    this.birthPlace = '',
    this.stardust = 0,
    this.inventory = defaultInventory,
    this.equippedSkin = defaultSkinId,
    this.equippedBackground = defaultBackgroundId,
    this.equippedProfilePicture,
    this.dailyHoroscope,
    this.dailyTarot,
    this.dailyCheckIn,
    this.astralMap = const [],
    this.notificationsEnabled = true,
    this.publicProfile = true,
    this.showSign = true,
  });

  final String uid;
  final String email;
  final String name;
  final String role;
  final String zodiacSign;
  final String birthDate;
  final String birthTime;
  final String birthPlace;
  final int stardust;
  final List<String> inventory;
  final String equippedSkin;
  final String equippedBackground;
  final String? equippedProfilePicture;
  final Map<String, dynamic>? dailyHoroscope;
  final Map<String, dynamic>? dailyTarot;
  final String? dailyCheckIn;
  final List<PlanetPosition> astralMap;
  final bool notificationsEnabled;
  final bool publicProfile;
  final bool showSign;

  bool get isAdmin => role == roleAdmin;

  factory AppUser.fromFirebase({
    required String uid,
    required String email,
    required String displayName,
    required Map<String, dynamic>? data,
  }) {
    final wallet = data?['wallet'] as Map<String, dynamic>?;
    final equipped = data?['equipped'] as Map<String, dynamic>?;
    final prefs = data?['preferences'] as Map<String, dynamic>?;
    final inventory =
        (data?['inventory'] as List?)?.cast<String>() ?? defaultInventory;

    return AppUser(
      uid: uid,
      email: email,
      name: (data?['name'] as String?) ?? displayName,
      role: (data?['role'] as String?) ?? roleUser,
      zodiacSign: (data?['zodiacSign'] as String?) ?? '',
      birthDate: (data?['birthDate'] as String?) ?? '',
      birthTime: (data?['birthTime'] as String?) ?? '',
      birthPlace: (data?['birthPlace'] as String?) ?? '',
      stardust: (wallet?['stardust'] as num?)?.toInt() ?? 0,
      inventory: inventory,
      equippedSkin: (equipped?['skin'] as String?) ?? defaultSkinId,
      equippedBackground:
          (equipped?['background'] as String?) ?? defaultBackgroundId,
      equippedProfilePicture: equipped?['profilePicture'] as String?,
      dailyHoroscope: data?['dailyHoroscope'] as Map<String, dynamic>?,
      dailyTarot: data?['dailyTarot'] as Map<String, dynamic>?,
      dailyCheckIn: data?['dailyCheckIn'] as String?,
      astralMap: parseAstralMap(data?['astralMapJson']),
      notificationsEnabled: prefs?['notifications'] as bool? ?? true,
      publicProfile: prefs?['publicProfile'] as bool? ?? true,
      showSign: prefs?['showSign'] as bool? ?? true,
    );
  }

  /// Par de [parseAstralMap]. Lanca [StateError] em lista vazia.
  static String encodeAstralMap(List<PlanetPosition> chart) {
    if (chart.isEmpty) throw StateError('Mapa astral vazio.');
    return jsonEncode(chart.map((e) => e.toJson()).toList());
  }

  static List<PlanetPosition> parseAstralMap(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => PlanetPosition.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'role': role,
        'zodiacSign': zodiacSign,
        'birthDate': birthDate,
        'birthTime': birthTime,
        'birthPlace': birthPlace,
        'wallet': {'stardust': stardust},
        'inventory': inventory,
        'equipped': {
          'skin': equippedSkin,
          'background': equippedBackground,
          'profilePicture': equippedProfilePicture,
        },
        'preferences': {
          'notifications': notificationsEnabled,
          'publicProfile': publicProfile,
          'showSign': showSign,
        },
      };
}
