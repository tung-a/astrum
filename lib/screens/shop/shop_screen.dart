import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/astrology.dart';
import '../../data/cosmetics.dart';
import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../services/economy.dart';
import '../../widgets/cosmic_scaffold.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  ItemType _filter = ItemType.cardSkin;
  bool _buying = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile == null) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final items = [
      ...shopCatalog,
      for (final sign in zodiacSigns)
        ShopItem(
          id: defaultProfilePictureId(sign),
          name: 'Avatar $sign · Essência Zodiacal',
          type: ItemType.profilePicture,
          rarity: ItemRarity.common,
          price: 0,
        ),
    ].where((item) => item.type == _filter);

    return CosmicScaffold(
      title: 'Loja · ${profile.stardust} ✦',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final type in ItemType.values)
                ChoiceChip(
                  label: Text(_label(type)),
                  selected: _filter == type,
                  onSelected: (_) => setState(() => _filter = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Card(
              child: ListTile(
                leading: _ItemIcon(item: item),
                title: Text(item.name),
                subtitle: Text(
                  '${rarityLabel(item.rarity)} · ${item.price} ✦\n${item.description}',
                ),
                isThreeLine: item.description.isNotEmpty,
                trailing: FilledButton(
                  onPressed:
                      _buying ? null : () => _selectItem(profile.uid, item),
                  child: Text(
                    _isEquipped(profile, item)
                        ? 'Em uso'
                        : profile.inventory.contains(item.id)
                            ? 'Equipar'
                            : 'Comprar',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(ItemType type) => switch (type) {
        ItemType.cardSkin => 'Cartas',
        ItemType.background => 'Fundos',
        ItemType.profilePicture => 'Avatares',
      };

  bool _isEquipped(AppUser profile, ShopItem item) => switch (item.type) {
        ItemType.cardSkin => profile.equippedSkin == item.id,
        ItemType.background => profile.equippedBackground == item.id,
        ItemType.profilePicture => profile.equippedProfilePicture == item.id,
      };

  Future<void> _selectItem(String uid, ShopItem item) async {
    if (_buying) return;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final field = switch (item.type) {
      ItemType.cardSkin => 'equipped.skin',
      ItemType.background => 'equipped.background',
      ItemType.profilePicture => 'equipped.profilePicture',
    };
    final repo = ref.read(userRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _buying = true);
    try {
      if (profile.inventory.contains(item.id)) {
        // Equipar nao mexe em saldo nem inventario.
        await repo.updateFields(uid, {field: item.id});
      } else {
        // Saldo e posse sao validados dentro da transacao.
        await repo.purchaseItem(
          uid: uid,
          itemId: item.id,
          price: item.price,
          equipField: field,
        );
      }
    } on EconomyException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível concluir. Tente novamente.'),
      ));
    } finally {
      if (mounted) setState(() => _buying = false);
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
      backgroundColor: rarityColor(item.rarity).withValues(alpha: 0.3),
      foregroundImage: asset == null ? null : AssetImage(asset),
      child: asset == null
          ? Icon(
              item.type == ItemType.cardSkin ? Icons.style : Icons.wallpaper,
              color: rarityColor(item.rarity),
            )
          : null,
    );
  }
}
