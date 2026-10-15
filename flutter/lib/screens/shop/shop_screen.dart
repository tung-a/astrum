import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cosmetics.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (profile == null) {
      return const CosmicScaffold(body: Center(child: CircularProgressIndicator()));
    }

    return CosmicScaffold(
      title: 'Loja · ${profile.stardust} ✦',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: shopCatalog.map((item) {
          final owned = profile.inventory.contains(item.id);
          final equipped = profile.equippedSkin == item.id ||
              profile.equippedBackground == item.id;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: rarityColor(item.rarity).withValues(alpha: 0.3),
                child: Icon(
                  item.type == ItemType.cardSkin ? Icons.style : Icons.wallpaper,
                  color: rarityColor(item.rarity),
                ),
              ),
              title: Text(item.name),
              subtitle: Text('${rarityLabel(item.rarity)} · ${item.price} ✦\n${item.description}'),
              isThreeLine: item.description.isNotEmpty,
              trailing: FilledButton(
                onPressed: () async {
                  if (owned) {
                    final field = item.type == ItemType.cardSkin
                        ? 'equipped.skin'
                        : 'equipped.background';
                    await ref.read(userRepositoryProvider).updateFields(profile.uid, {
                      field: item.id,
                    });
                    return;
                  }
                  if (profile.stardust < item.price) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Poeira Estelar insuficiente.')),
                    );
                    return;
                  }
                  await ref.read(userRepositoryProvider).updateFields(profile.uid, {
                    'wallet.stardust': FieldValue.increment(-item.price),
                    'inventory': [...profile.inventory, item.id],
                    if (item.type == ItemType.cardSkin) 'equipped.skin': item.id,
                    if (item.type == ItemType.background) 'equipped.background': item.id,
                  });
                },
                child: Text(equipped ? 'Em uso' : owned ? 'Equipar' : 'Comprar'),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
