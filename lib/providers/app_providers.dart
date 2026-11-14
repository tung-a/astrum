import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/theme/cosmetics_style.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';

final equippedSkinProvider = Provider<SkinStyle>((ref) {
  final id =
      ref.watch(profileProvider).valueOrNull?.equippedSkin ?? defaultSkinId;
  return cosmeticStyles[id] ?? cosmeticStyles[defaultSkinId]!;
});

final equippedBackgroundProvider = Provider<List<Color>>((ref) {
  final id = ref.watch(profileProvider).valueOrNull?.equippedBackground ??
      defaultBackgroundId;
  return cosmeticBackgrounds[id] ?? cosmeticBackgrounds[defaultBackgroundId]!;
});

