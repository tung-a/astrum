import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/models/shop_item.dart';
import 'package:astrum/data/catalog_seed.dart';
import 'package:astrum/data/profile_pictures.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/widgets/cosmic_scaffold.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  ItemType _filter = ItemType.cardSkin;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile == null) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final ownedItems = [
      ...fullShopCatalog,
    ].where(
        (item) => profile.inventory.contains(item.id) && item.type == _filter);

    return CosmicScaffold(
      title: 'Inventário',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final type in ItemType.values)
                ChoiceChip(
                  label: Text(switch (type) {
                    ItemType.cardSkin => 'Cartas',
                    ItemType.background => 'Fundos',
                    ItemType.profilePicture => 'Avatares',
                  }),
                  selected: _filter == type,
                  onSelected: (_) => setState(() => _filter = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (ownedItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhum item nesta categoria. Visite a loja astral.'),
            ),
          for (final item in ownedItems)
            Card(
              child: ListTile(
                leading: _ItemIcon(item: item),
                title: Text(item.name),
                subtitle: Text(rarityLabel(item.rarity)),
                trailing: TextButton(
                  onPressed: _isEquipped(profile, item)
                      ? null
                      : () => _equip(profile, item),
                  child:
                      Text(_isEquipped(profile, item) ? 'Em uso' : 'Equipar'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isEquipped(AppUser profile, ShopItem item) => switch (item.type) {
        ItemType.cardSkin => profile.equippedSkin == item.id,
        ItemType.background => profile.equippedBackground == item.id,
        ItemType.profilePicture => profile.equippedProfilePicture == item.id,
      };

  Future<void> _equip(AppUser profile, ShopItem item) async {
    await ref
        .read(profileRepositoryProvider)
        .equip(profile.uid, item.type.slot, item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} equipado.')),
      );
    }
  }
}

class _ItemIcon extends StatelessWidget {
  const _ItemIcon({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    final asset = profilePictureAssetPath(item.id);
    return CircleAvatar(
      foregroundImage: asset == null ? null : AssetImage(asset),
      child: asset == null
          ? Icon(item.type == ItemType.cardSkin ? Icons.style : Icons.wallpaper)
          : null,
    );
  }
}
