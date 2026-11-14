/// Slot de cosmetico equipavel. O caminho no Firestore fica em
/// `services/equip_slot_field.dart`, fora das telas.
enum EquipSlot {
  skin,
  background,
  profilePicture;

  /// So o avatar entra em publicProfiles (campo `avatar`).
  bool get touchesPublicProfile => this == EquipSlot.profilePicture;
}
