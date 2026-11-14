import 'package:astrum/features/economy/domain/economy_exceptions.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShopState {
  const ShopState({this.buying = false});
  final bool buying;
}

final shopControllerProvider =
    NotifierProvider.autoDispose<ShopController, ShopState>(ShopController.new);

/// Compra e equipar da loja. Retorna mensagens de erro (texto de snackbar);
/// a tela as exibe. `equip` (inventario) propaga erros e nao tem guarda.
class ShopController extends AutoDisposeNotifier<ShopState> {
  bool _alive = true;

  @override
  ShopState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const ShopState();
  }

  /// Equipa se o item ja esta no inventario; senao compra (e equipa na mesma
  /// gravacao). Retorna a mensagem de erro, ou null em sucesso (ou sem perfil).
  Future<String?> selectItem(ShopItem item) async {
    if (state.buying) return null;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return null;
    final profileRepo = ref.read(profileRepositoryProvider);
    final economy = ref.read(economyRepositoryProvider);

    state = const ShopState(buying: true);
    try {
      if (profile.inventory.contains(item.id)) {
        // Equipar nao mexe em saldo nem inventario.
        await profileRepo.equip(profile.uid, item.type.slot, item.id);
      } else {
        // Saldo e posse sao validados dentro da transacao.
        await economy.purchaseItem(
          uid: profile.uid,
          itemId: item.id,
          equipSlot: item.type.slot,
        );
      }
      return null;
    } on EconomyException catch (e) {
      return e.message;
    } catch (_) {
      return 'Não foi possível concluir. Tente novamente.';
    } finally {
      if (_alive) state = const ShopState();
    }
  }

  /// Usado pelo inventario: nao engole erros (como era na tela).
  Future<void> equip(ShopItem item) {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return Future.value();
    return ref
        .read(profileRepositoryProvider)
        .equip(profile.uid, item.type.slot, item.id);
  }
}
