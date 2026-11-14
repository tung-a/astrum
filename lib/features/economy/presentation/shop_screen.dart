import 'package:astrum/features/economy/domain/catalog_entry.dart';
import 'package:astrum/features/economy/domain/catalog_seed.dart';
import 'package:astrum/features/economy/domain/profile_pictures.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/economy/presentation/shop_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/shared/cosmetics_style.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  ItemType _filter = ItemType.cardSkin;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final buying = ref.watch(shopControllerProvider.select((s) => s.buying));
    if (profile == null) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final catalogAsync = ref.watch(shopCatalogProvider);
    if (catalogAsync.isLoading && !catalogAsync.hasValue) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final catalog = catalogAsync.valueOrNull ?? const <String, CatalogEntry>{};
    if (catalog.isEmpty) {
      // Sem catalogo nao ha preco confiavel: nada de comprar com preco local.
      return const CosmicScaffold(
        title: 'Loja',
        body: Center(child: Text('Catálogo indisponível.')),
      );
    }

    // So itens ativos no catalogo; o preco exibido e o do servidor.
    final items = fullShopCatalog
        .where((item) =>
            item.type == _filter && (catalog[item.id]?.active ?? false))
        .toList();

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
                  label: Text(itemTypeLabel(type)),
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
                  '${rarityLabel(item.rarity)} · ${catalog[item.id]!.price} ✦\n${item.description}',
                ),
                isThreeLine: item.description.isNotEmpty,
                trailing: FilledButton(
                  onPressed: buying ? null : () => _selectItem(item),
                  child: Text(
                    profile.isEquipped(item)
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

  Future<void> _selectItem(ShopItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final message =
        await ref.read(shopControllerProvider.notifier).selectItem(item);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
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
