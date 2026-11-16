import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/friendship_controller.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const requestsEmptyText = 'Nenhum pedido por enquanto. Quando alguém quiser '
    'entrar na sua constelação, aparece aqui.';
const requestsLoadErrorText = 'Não foi possível carregar seus pedidos.';

/// Tela `/account/requests`: pedidos recebidos (aceitar/recusar), enviados
/// (aguardando, cancelar) e relacoes que o usuario recusou/removeu
/// (desbloquear). Toda escrita passa pelo [FriendshipController].
class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen> {
  /// Ids de pares com uma acao em andamento (desabilita os botoes: sem duplo
  /// toque, sem aceite duplo).
  final _busy = <String>{};

  /// Pedidos enviados cancelados nesta sessao (esconde a lapide de um pedido
  /// recusado em silencio, que o servidor nao apaga).
  final _hidden = <String>{};

  Future<void> _do(
      Friendship f, Future<String> Function(FriendshipController c) op) async {
    if (!_busy.add(f.id)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    final text = await op(ref.read(friendshipControllerProvider.notifier));
    if (!mounted) return;
    setState(() => _busy.remove(f.id));
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(friendshipsViewProvider);
    return CosmicScaffold(
      title: 'Pedidos de amizade',
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(requestsLoadErrorText, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(friendshipsProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
        data: (v) {
          final outgoing =
              v.outgoing.where((f) => !_hidden.contains(f.id)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 72, 20, 24),
            children: [
              _Header('Recebidos (${v.incoming.length})'),
              if (v.incoming.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(requestsEmptyText,
                      style: TextStyle(color: AstrumColors.muted)),
                ),
              for (final f in v.incoming)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.requesterName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18)),
                        const Text('quer entrar na sua constelação',
                            style: TextStyle(color: AstrumColors.muted)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _busy.contains(f.id)
                                  ? null
                                  : () => _do(f, (c) => c.accept(f)),
                              child: const Text('Aceitar'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _busy.contains(f.id)
                                  ? null
                                  : () => _do(f, (c) => c.decline(f)),
                              child: const Text('Recusar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (outgoing.isNotEmpty) ...[
                const SizedBox(height: 16),
                // Inclui os recusados em silencio (o remetente nao e avisado),
                // por isso difere de `pendingOutgoingCount` (cota do cliente).
                _Header('Enviados (${outgoing.length})'),
                for (final f in outgoing)
                  _OutgoingTile(
                    friendship: f,
                    busy: _busy.contains(f.id),
                    onCancel: () async {
                      await _do(f, (c) => c.cancel(f));
                      if (mounted && f.status != FriendshipStatus.pending) {
                        setState(() => _hidden.add(f.id));
                      }
                    },
                  ),
              ],
              if (v.blockedByMe.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Header('Recusados e removidos'),
                for (final f in v.blockedByMe)
                  _BlockedTile(
                    friendship: f,
                    busy: _busy.contains(f.id),
                    onUnblock: () => _do(f, (c) => c.unblock(f)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 18)),
      );
}

/// Pedido enviado. Todos os enviados sao iguais ("Aguardando resposta" e
/// "Cancelar pedido"), inclusive o recusado em silencio: cancelar esse nao
/// altera o servidor (a lapide fica, ou o remetente poderia pedir de novo) e so
/// o esconde na sessao.
class _OutgoingTile extends ConsumerWidget {
  const _OutgoingTile(
      {required this.friendship, required this.busy, required this.onCancel});
  final Friendship friendship;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = friendship.requesterUid;
    final name =
        ref.watch(publicNameProvider(friendship.otherUid(me))).valueOrNull ??
            'Viajante';
    return Card(
      child: ListTile(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Aguardando resposta'),
        trailing: TextButton(
          onPressed: busy ? null : onCancel,
          child: const Text('Cancelar pedido'),
        ),
      ),
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile(
      {required this.friendship, required this.busy, required this.onUnblock});
  final Friendship friendship;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = friendship.uids.firstWhere((u) => u != friendship.declinedBy);
    final name = friendship.otherName(friendship.declinedBy ?? '') ??
        ref.watch(publicNameProvider(other)).valueOrNull ??
        'Viajante';
    return Card(
      child: ListTile(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Não pode pedir amizade até você desbloquear'),
        trailing: TextButton(
          onPressed: busy ? null : onUnblock,
          child: const Text('Desbloquear'),
        ),
      ),
    );
  }
}
