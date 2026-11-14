/// Entrada do catalogo `shop_items/{itemId}` (preco validado pelas regras).
class CatalogEntry {
  const CatalogEntry({
    required this.price,
    required this.type,
    required this.rarity,
    required this.active,
  });

  final int price;
  final String type;
  final String rarity;
  final bool active;

  factory CatalogEntry.fromMap(Map<String, dynamic> data) => CatalogEntry(
        price: (data['price'] as num?)?.toInt() ?? -1,
        type: data['type'] as String? ?? '',
        rarity: data['rarity'] as String? ?? '',
        active: data['active'] == true,
      );
}
