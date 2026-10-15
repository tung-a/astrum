import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/astrology.dart';
import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

const intentions = [
  (id: 'luz', label: 'Luz', icon: Icons.wb_sunny, color: AstrumColors.luz),
  (id: 'coragem', label: 'Coragem', icon: Icons.local_fire_department, color: AstrumColors.coragem),
  (id: 'cura', label: 'Cura', icon: Icons.spa, color: AstrumColors.cura),
  (id: 'clareza', label: 'Clareza', icon: Icons.water_drop, color: AstrumColors.clareza),
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
        await ref.read(userRepositoryProvider).findUserByEmail(_search.text);
    if (!mounted) return;
    if (found == null || found.id == profile.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma constelação encontrada com esse email.')),
      );
      return;
    }
    await ref.read(userRepositoryProvider).addFriend(profile.uid, found);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${found.name} entrou na sua constelação.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final friends = ref.watch(friendsProvider).valueOrNull ?? [];
    if (profile == null) {
      return const CosmicScaffold(body: Center(child: CircularProgressIndicator()));
    }

    return CosmicScaffold(
      title: 'Perfil',
      actions: [
        IconButton(
          onPressed: () => context.push('/shop'),
          icon: const Icon(Icons.storefront_outlined),
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
            child: Text(
              signGlyph[profile.zodiacSign] ??
                  (profile.name.isNotEmpty ? profile.name[0] : '✦'),
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(height: 12),
          Text(profile.name, style: const TextStyle(fontSize: 22)),
          Text(profile.email, style: const TextStyle(color: AstrumColors.muted)),
          Text(
            '${profile.zodiacSign} · ${profile.stardust} Poeira Estelar',
            style: const TextStyle(color: AstrumColors.gold),
          ),
          const SizedBox(height: 20),
          const Text('Constelação', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(hintText: 'Email de um viajante'),
                ),
              ),
              IconButton(onPressed: _searchFriend, icon: const Icon(Icons.person_add_alt)),
            ],
          ),
          const SizedBox(height: 12),
          if (friends.isEmpty)
            const Text('Sua constelação ainda é um céu aberto.',
                style: TextStyle(color: AstrumColors.muted)),
          ...friends.map((f) => _FriendTile(friend: f, me: profile)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
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
        subtitle: Text('${friend.zodiacSign} · ${synergy.title} (${synergy.score}/5)'),
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
                      await ref.read(userRepositoryProvider).sendIntention(
                            fromUid: me.uid,
                            fromName: me.name,
                            toUid: friend.id,
                            intentionId: i.id,
                            intentionLabel: i.label,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${i.label} enviada a ${friend.name}')),
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
