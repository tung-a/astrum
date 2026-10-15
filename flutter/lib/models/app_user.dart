import 'dart:convert';

import '../data/astrology.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    this.role = 'user',
    this.zodiacSign = '',
    this.birthDate = '',
    this.birthTime = '',
    this.birthPlace = '',
    this.stardust = 0,
    this.inventory = const ['skin_classic', 'bg_void'],
    this.equippedSkin = 'skin_classic',
    this.equippedBackground = 'bg_void',
    this.equippedProfilePicture,
    this.dailyHoroscope,
    this.dailyTarot,
    this.dailyCheckIn,
    this.astralMap = const [],
    this.notificationsEnabled = true,
    this.publicProfile = true,
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

  bool get isAdmin => role == 'admin';

  factory AppUser.fromFirebase({
    required String uid,
    required String email,
    required String displayName,
    required Map<String, dynamic>? data,
  }) {
    final wallet = data?['wallet'] as Map<String, dynamic>?;
    final equipped = data?['equipped'] as Map<String, dynamic>?;
    final prefs = data?['preferences'] as Map<String, dynamic>?;
    final inventory = (data?['inventory'] as List?)?.cast<String>() ??
        const ['skin_classic', 'bg_void'];

    return AppUser(
      uid: uid,
      email: email,
      name: (data?['name'] as String?) ?? displayName,
      role: (data?['role'] as String?) ?? 'user',
      zodiacSign: (data?['zodiacSign'] as String?) ?? '',
      birthDate: (data?['birthDate'] as String?) ?? '',
      birthTime: (data?['birthTime'] as String?) ?? '',
      birthPlace: (data?['birthPlace'] as String?) ?? '',
      stardust: (wallet?['stardust'] as num?)?.toInt() ?? 0,
      inventory: inventory,
      equippedSkin: (equipped?['skin'] as String?) ?? 'skin_classic',
      equippedBackground: (equipped?['background'] as String?) ?? 'bg_void',
      equippedProfilePicture: equipped?['profilePicture'] as String?,
      dailyHoroscope: data?['dailyHoroscope'] as Map<String, dynamic>?,
      dailyTarot: data?['dailyTarot'] as Map<String, dynamic>?,
      dailyCheckIn: data?['dailyCheckIn'] as String?,
      astralMap: parseAstralMap(data?['astralMapJson']),
      notificationsEnabled: prefs?['notifications'] as bool? ?? true,
      publicProfile: prefs?['publicProfile'] as bool? ?? true,
    );
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
          'showSign': true,
        },
      };
}

class RitualEvent {
  const RitualEvent({
    required this.id,
    required this.title,
    required this.time,
    required this.date,
    this.duration = 30,
    this.energy,
  });

  final String id;
  final String title;
  final String time;
  final String date;
  final int duration;
  final String? energy;

  factory RitualEvent.fromDoc(String id, Map<String, dynamic> data) =>
      RitualEvent(
        id: id,
        title: data['title'] as String? ?? '',
        time: data['time'] as String? ?? '',
        date: data['date'] as String? ?? '',
        duration: (data['duration'] as num?)?.toInt() ?? 30,
        energy: data['energy'] as String?,
      );
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
  });

  final String id;
  final String title;
  final List<ChatTurnStored> messages;
}

class ChatTurnStored {
  const ChatTurnStored({required this.role, required this.text});
  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};

  factory ChatTurnStored.fromJson(Map<String, dynamic> json) => ChatTurnStored(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
      );
}

class Friend {
  const Friend({
    required this.id,
    required this.name,
    this.email = '',
    this.zodiacSign = '',
  });

  final String id;
  final String name;
  final String email;
  final String zodiacSign;
}

class IntentionNotice {
  const IntentionNotice({
    required this.id,
    required this.intentionId,
    required this.intentionLabel,
    required this.fromName,
  });

  final String id;
  final String intentionId;
  final String intentionLabel;
  final String fromName;
}
