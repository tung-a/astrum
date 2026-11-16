import 'package:astrum/core/astro/synergy.dart';
import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/features/economy/domain/profile_pictures.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/account_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/presentation/friendship_controller.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:astrum/shared/cosmic_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Icone e cor de cada intencao, por id. Os ids e rotulos vem do contrato
/// (`intentionLabels`), que espelha `labelOk` em firestore.rules.
const intentionStyles = <String, ({IconData icon, Color color})>{
  'luz': (icon: Icons.wb_sunny, color: AstrumColors.luz),
  'coragem': (icon: Icons.local_fire_department, color: AstrumColors.coragem),
  'cura': (icon: Icons.spa, color: AstrumColors.cura),
  'clareza': (icon: Icons.water_drop, color: AstrumColors.clareza),
};

final intentions = [
  for (final e in intentionLabels.entries)
    (
      id: e.key,
      label: e.value,
      icon: intentionStyles[e.key]!.icon,
      color: intentionStyles[e.key]!.color
    ),
];

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _search = TextEditingController();

  /// Valor otimista do interruptor de busca enquanto grava; volta ao do perfil
  /// se a gravacao falhar.
  bool? _publicPending;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _setPublicProfile(String uid, bool enabled) async {
    setState(() => _publicPending = enabled);
    try {
      await ref.read(profileRepositoryProvider).setPublicProfile(uid, enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível salvar. Tente de novo.')));
      }
    } finally {
      if (mounted) setState(() => _publicPending = null);
    }
  }

  bool _sending = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Busca o e-mail, pede confirmacao com nome e avatar e so entao envia o
  /// pedido. Nenhuma mensagem revela se o e-mail existe, se a busca esta
  /// desligada ou se houve recusa.
  Future<void> _sendRequest() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final ctl = ref.read(friendshipControllerProvider.notifier);
      final lookup = await ctl.lookup(_search.text);
      if (!mounted) return;
      final found = lookup.friend;
      if (found == null) return _snack(lookup.message!);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => _ConfirmRequestDialog(friend: found),
      );
      if (ok != true || !mounted) return;
      final text = await ctl.sendRequest(found);
      if (!mounted) return;
      _search.clear();
      _snack(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final friendsAsync = ref.watch(friendsProvider);
    final friends = friendsAsync.valueOrNull ?? [];
    final incoming = ref.watch(incomingRequestCountProvider);
    final avatarAsset = profile == null
        ? null
        : profilePictureAssetPath(
            profile.equippedProfilePicture ??
                defaultProfilePictureId(profile.zodiacSign),
          );
    if (profile == null) {
      return const CosmicScaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return CosmicScaffold(
      title: 'Perfil',
      actions: [
        IconButton(
          onPressed: () => context.push('/shop'),
          icon: const Icon(Icons.storefront_outlined),
        ),
        IconButton(
          tooltip: 'Inventário',
          onPressed: () => context.push('/inventory'),
          icon: const Icon(Icons.inventory_2_outlined),
        ),
        if (profile.isAdmin)
          IconButton(
            onPressed: () => context.push('/admin'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: AstrumColors.amethyst,
            foregroundImage:
                avatarAsset == null ? null : AssetImage(avatarAsset),
            child: avatarAsset == null
                ? Text(
                    signGlyph[profile.zodiacSign] ??
                        (profile.name.isNotEmpty ? profile.name[0] : '✦'),
                    style: const TextStyle(fontSize: 28),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(profile.name, style: const TextStyle(fontSize: 22)),
          Text(profile.email,
              style: const TextStyle(color: AstrumColors.muted)),
          Text(
            [
              if (profile.showSign && profile.zodiacSign.isNotEmpty)
                profile.zodiacSign,
              '${profile.stardust} Poeira Estelar',
            ].join(' · '),
            style: const TextStyle(color: AstrumColors.gold),
          ),
          const SizedBox(height: 16),
          const Text('Preferências', style: TextStyle(fontSize: 18)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notificações de intenções'),
            value: profile.notificationsEnabled,
            onChanged: (enabled) => ref
                .read(profileRepositoryProvider)
                .setNotificationsEnabled(profile.uid, enabled),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exibir meu signo'),
            value: profile.showSign,
            onChanged: (enabled) => ref
                .read(profileRepositoryProvider)
                .setShowSign(profile.uid, enabled),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aparecer na busca de amigos'),
            value: _publicPending ?? profile.publicProfile,
            onChanged: (enabled) => _setPublicProfile(profile.uid, enabled),
          ),
          const SizedBox(height: 20),
          const Text('Constelação', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendRequest(),
            decoration: const InputDecoration(hintText: 'Email de um viajante'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _sending ? null : _sendRequest,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Enviar pedido'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Badge.count(
                count: incoming,
                isLabelVisible: incoming > 0,
                child: const Icon(Icons.mail_outline),
              ),
              title: Text('Pedidos de amizade ($incoming)'),
              subtitle: const Text('Recebidos, enviados e desbloqueio'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/account/requests'),
            ),
          ),
          const SizedBox(height: 12),
          if (friendsAsync.isLoading && friends.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (friendsAsync.hasError && friends.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Não foi possível carregar sua constelação.',
                    style: TextStyle(color: AstrumColors.muted)),
                TextButton(
                  onPressed: () => ref.invalidate(friendshipsProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            )
          else if (friends.isEmpty)
            const Text('Sua constelação ainda é um céu aberto.',
                style: TextStyle(color: AstrumColors.muted)),
          ...friends.map((f) => _FriendTile(friend: f, me: profile)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () =>
                ref.read(accountControllerProvider.notifier).signOut(),
            child: const Text('Sair'),
          ),
          const SizedBox(height: 8),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: AstrumColors.destructive),
            onPressed: () => context.push('/account/delete'),
            child: const Text('Excluir minha conta'),
          ),
        ],
      ),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.friend, required this.me});
  final Friend friend;
  final AppUser me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final synergy = getAstralSynergy(me.zodiacSign, friend.zodiacSign);
    return Card(
      child: ExpansionTile(
        title: Text(friend.name),
        subtitle: Text([
          if (friend.zodiacSign.isNotEmpty) friend.zodiacSign,
          '${synergy.title} (${synergy.score}/5)',
        ].join(' · ')),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(synergy.description),
          ),
          Wrap(
            spacing: 8,
            children: intentions
                .map(
                  (i) => ActionChip(
                    avatar: Icon(i.icon, size: 16, color: i.color),
                    label: Text(i.label),
                    onPressed: () async {
                      final text = await ref
                          .read(accountControllerProvider.notifier)
                          .sendIntention(me, friend, i.id, i.label);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(text)));
                      }
                    },
                  ),
                )
                .toList(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: AstrumColors.destructive),
              onPressed: () => _confirmRemove(context, ref),
              child: const Text('Remover amizade'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${friend.name}?'),
        content: Text('Vocês deixam de trocar intenções e ${friend.name} não '
            'poderá pedir amizade de novo, a menos que você desbloqueie.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: AstrumColors.destructive),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text =
        await ref.read(friendshipControllerProvider.notifier).remove(friend);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

/// Confirmacao antes de enviar: nome e avatar publicos de quem sera pedido.
class _ConfirmRequestDialog extends StatelessWidget {
  const _ConfirmRequestDialog({required this.friend});
  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final asset =
        friend.avatar.isEmpty ? null : profilePictureAssetPath(friend.avatar);
    return AlertDialog(
      title: Text('Enviar pedido a ${friend.name}?'),
      content: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AstrumColors.amethyst,
            foregroundImage: asset == null ? null : AssetImage(asset),
            child: Text(friend.name.isNotEmpty ? friend.name[0] : '✦'),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('A pessoa só entra na sua constelação se aceitar.'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Enviar pedido'),
        ),
      ],
    );
  }
}
