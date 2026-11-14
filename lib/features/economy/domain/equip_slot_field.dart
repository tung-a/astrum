import 'package:astrum/features/economy/domain/equip_slot.dart';

/// Caminho do campo em `users/{uid}` para cada slot.
extension EquipSlotField on EquipSlot {
  String get fieldPath => switch (this) {
        EquipSlot.skin => 'equipped.skin',
        EquipSlot.background => 'equipped.background',
        EquipSlot.profilePicture => 'equipped.profilePicture',
      };
}
