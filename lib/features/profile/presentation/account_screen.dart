import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/core/astro/synergy.dart';
import 'package:astrum/features/economy/domain/profile_pictures.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/widgets/cosmic_scaffold.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _searchFriend() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    final found =
        await ref.read(socialRepositoryProvider).findUserByEmail(_search.text);
    if (!mounted) return;
    if (found == null || found.id == profile.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nenhuma constelação encontrada com esse email.')),
      );
      return;
    }
    await ref.read(socialRepositoryProvider).addFriend(profile.uid, found);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${found.name} entrou na sua constelação.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final friends = ref.watch(friendsProvider).valueOrNull ?? [];
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
          const SizedBox(height: 20),
          const Text('Constelação', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration:
                      const InputDecoration(hintText: 'Email de um viajante'),
                ),
              ),
              IconButton(
                  onPressed: _searchFriend,
                  icon: const Icon(Icons.person_add_alt)),
            ],
          ),
          const SizedBox(height: 12),
          if (friends.isEmpty)
            const Text('Sua constelação ainda é um céu aberto.',
                style: TextStyle(color: AstrumColors.muted)),
          ...friends.map((f) => _FriendTile(friend: f, me: profile)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sair'),
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
                      await ref.read(socialRepositoryProvider).sendIntention(
                            fromUid: me.uid,
                            fromName: me.name,
                            toUid: friend.id,
                            intentionId: i.id,
                            intentionLabel: i.label,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('${i.label} enviada a ${friend.name}')),
                        );
                      }
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
