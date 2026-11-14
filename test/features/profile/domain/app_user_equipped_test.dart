import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

ShopItem _item(String id, ItemType type) =>
    ShopItem(id: id, name: id, type: type, rarity: ItemRarity.common, price: 0);

void main() {
  const user = AppUser(
    uid: 'u',
    email: 'u@x.com',
    name: 'U',
    equippedSkin: 'skin_gold',
    equippedBackground: 'bg_void',
    equippedProfilePicture: 'pfp_leo',
  );

  test('isEquipped compara com o slot do tipo do item', () {
    expect(user.isEquipped(_item('skin_gold', ItemType.cardSkin)), isTrue);
    expect(user.isEquipped(_item('skin_cyber', ItemType.cardSkin)), isFalse);
    expect(user.isEquipped(_item('bg_void', ItemType.background)), isTrue);
    expect(user.isEquipped(_item('pfp_leo', ItemType.profilePicture)), isTrue);
  });

  test('mesmo id em outro tipo nao conta como equipado', () {
    expect(user.isEquipped(_item('skin_gold', ItemType.background)), isFalse);
  });

  test('sem avatar equipado nenhum avatar esta em uso', () {
    const semAvatar = AppUser(uid: 'u', email: 'u@x.com', name: 'U');
    expect(semAvatar.isEquipped(_item('pfp_leo', ItemType.profilePicture)),
        isFalse);
  });

  test('itemTypeLabel mantem os rotulos da loja e do inventario', () {
    expect(itemTypeLabel(ItemType.cardSkin), 'Cartas');
    expect(itemTypeLabel(ItemType.background), 'Fundos');
    expect(itemTypeLabel(ItemType.profilePicture), 'Avatares');
  });
}
