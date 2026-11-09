import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cosmetics.dart';
import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

enum _RoleFilter { all, admin, user }

enum _AnalyticsPeriod { today, week, month }

const _initialCrystals = [
  (
    id: 'ametista',
    name: 'Ametista - Transmutação',
    description:
        'Pedra de proteção e elevação espiritual, indicada para meditação.',
    focus: 'Espiritualidade',
  ),
  (
    id: 'quartzo-rosa',
    name: 'Quartzo Rosa - Amor Incondicional',
    description: 'Pedra associada ao amor, à paz e à cura interior.',
    focus: 'Emoções',
  ),
  (
    id: 'citrino',
    name: 'Citrino - Prosperidade',
    description: 'Pedra solar ligada à abundância e à prosperidade.',
    focus: 'Carreira/Finanças',
  ),
  (
    id: 'olho-de-tigre',
    name: 'Olho de Tigre - Proteção e Foco',
    description: 'Ajuda a encontrar clareza, foco e discernimento.',
    focus: 'Estudo/Foco',
  ),
  (
    id: 'turmalina-negra',
    name: 'Turmalina Negra - Escudo',
    description: 'Pedra tradicionalmente associada à proteção energética.',
    focus: 'Proteção',
  ),
  (
    id: 'sodalita',
    name: 'Sodalita - Intuição e Mente',
    description: 'Associada à clareza mental e ao pensamento objetivo.',
    focus: 'Intelecto',
  ),
  (
    id: 'quartzo-transparente',
    name: 'Quartzo Transparente - Amplificador',
    description: 'Cristal associado à clareza e à amplificação de intenções.',
    focus: 'Clareza',
  ),
  (
    id: 'jaspe-vermelho',
    name: 'Jaspe Vermelho - Vitalidade',
    description: 'Pedra associada à vitalidade e à coragem.',
    focus: 'Energia Física',
  ),
];

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();
  late Future<List<AppUser>> _users;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _analytics;
  _RoleFilter _role = _RoleFilter.all;
  _AnalyticsPeriod _period = _AnalyticsPeriod.today;

  @override
  void initState() {
    super.initState();
    _users = ref.read(userRepositoryProvider).listUsers();
    _analytics = _watchAnalytics(_period);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final users = ref.read(userRepositoryProvider).listUsers();
    setState(() => _users = users);
    await users;
  }

  DateTime _startOfPeriod(_AnalyticsPeriod period) {
    final now = DateTime.now();
    return switch (period) {
      _AnalyticsPeriod.today => DateTime(now.year, now.month, now.day),
      _AnalyticsPeriod.week => now.subtract(const Duration(days: 7)),
      _AnalyticsPeriod.month => DateTime(now.year, now.month, 1),
    };
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchAnalytics(
    _AnalyticsPeriod period,
  ) {
    return FirebaseFirestore.instance
        .collection('analytics_events')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfPeriod(period)),
        )
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots();
  }

  Future<void> _seedCrystals() async {
    final batch = FirebaseFirestore.instance.batch();
    for (final crystal in _initialCrystals) {
      final doc = FirebaseFirestore.instance
          .collection('cristais_propriedades')
          .doc(crystal.id);
      batch.set(doc, {
        'nome': crystal.name,
        'descricao': crystal.description,
        'foco': crystal.focus,
      });
    }

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coleção de cristais atualizada.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Falha ao atualizar cristais: ${error.message}')),
        );
      }
    }
  }

  /// Publica o catalogo da loja (shop_items) a partir de cosmetics.dart. As
  /// regras so aceitam a escrita de admin; a tela tambem confere o papel.
  Future<void> _publishCatalog() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || !profile.isAdmin) return;
    final db = FirebaseFirestore.instance;
    try {
      // Le o estado atual antes de gravar; se falhar, nada e gravado.
      final existing = await db.collection('shop_items').get();
      final existingIds = existing.docs.map((d) => d.id).toSet();
      final seedIds = fullShopCatalog.map((i) => i.id).toSet();
      final batch = db.batch(); // bem menos de 500 operacoes
      for (final item in fullShopCatalog) {
        final ref = db.collection('shop_items').doc(item.id);
        final data = <String, dynamic>{
          'type': catalogTypeName(item.type),
          'rarity': catalogRarityName(item.rarity),
        };
        // Docs existentes mantem price e active; so docs novos recebem ambos.
        if (!existingIds.contains(item.id)) {
          data['price'] = item.price;
          data['active'] = true;
        }
        batch.set(ref, data, SetOptions(merge: true));
      }
      // Itens fora do seed sao desativados, nunca apagados.
      for (final id in existingIds.difference(seedIds)) {
        batch.set(db.collection('shop_items').doc(id), {'active': false},
            SetOptions(merge: true));
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catálogo da loja publicado.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Falha ao publicar catálogo: ${error.message}')),
        );
      }
    }
  }

  /// Migracao unica: cria publicProfiles para os usuarios existentes.
  Future<void> _rebuildPublicProfiles() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || !profile.isAdmin) return;
    try {
      final n = await ref.read(userRepositoryProvider).rebuildPublicProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n perfis públicos recriados.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Falha ao recriar perfis públicos: ${error.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CosmicScaffold(
      title: 'Painel Astral',
      body: FutureBuilder<List<AppUser>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text(
                    'Não foi possível carregar usuários: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!;
          final admins = users.where((user) => user.isAdmin).length;
          final signs = <String, int>{};
          for (final user in users) {
            if (user.zodiacSign.isNotEmpty) {
              signs.update(user.zodiacSign, (total) => total + 1,
                  ifAbsent: () => 1);
            }
          }
          final filteredUsers = users.where((user) {
            final matchesRole = switch (_role) {
              _RoleFilter.all => true,
              _RoleFilter.admin => user.isAdmin,
              _RoleFilter.user => !user.isAdmin,
            };
            final query = _search.text.trim().toLowerCase();
            final matchesSearch = query.isEmpty ||
                user.name.toLowerCase().contains(query) ||
                user.email.toLowerCase().contains(query);
            return matchesRole && matchesSearch;
          }).toList()
            ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _MetricCard(
                            label: 'Viajantes', value: '${users.length}')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MetricCard(label: 'Mestres', value: '$admins')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _MetricCard(
                            label: 'Signos', value: '${signs.length}')),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Atividade',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final period in _AnalyticsPeriod.values)
                      ChoiceChip(
                        label: Text(switch (period) {
                          _AnalyticsPeriod.today => 'Hoje',
                          _AnalyticsPeriod.week => '7 dias',
                          _AnalyticsPeriod.month => 'Este mês',
                        }),
                        selected: period == _period,
                        onSelected: (_) {
                          setState(() {
                            _period = period;
                            _analytics = _watchAnalytics(period);
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _analytics,
                  builder: (context, eventSnapshot) {
                    if (eventSnapshot.hasError) {
                      return Text(
                        'Não foi possível carregar a atividade: ${eventSnapshot.error}',
                      );
                    }
                    if (!eventSnapshot.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final events = eventSnapshot.data!.docs;
                    final uniqueUsers = events
                        .map((event) => event.data()['userId'])
                        .whereType<String>()
                        .where((uid) => uid != 'anonymous')
                        .toSet()
                        .length;
                    final eventCounts = <String, int>{};
                    for (final event in events) {
                      final name = event.data()['eventName'] as String?;
                      if (name != null && name.isNotEmpty) {
                        eventCounts.update(name, (total) => total + 1,
                            ifAbsent: () => 1);
                      }
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${events.length} eventos · $uniqueUsers usuários ativos'),
                            const SizedBox(height: 8),
                            for (final entry
                                in eventCounts.entries.toList()
                                  ..sort((a, b) => b.value.compareTo(a.value)))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(entry.key.replaceAll('_', ' ')),
                                trailing: Text('${entry.value}'),
                              ),
                            if (eventCounts.isEmpty)
                              const Text('Nenhum evento neste período.'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _seedCrystals,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Popular cristais'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _publishCatalog,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Publicar catálogo'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _rebuildPublicProfiles,
                  icon: const Icon(Icons.group_outlined),
                  label: const Text('Recriar perfis públicos'),
                ),
                const SizedBox(height: 20),
                Text('Usuários', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nome ou e-mail',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in _RoleFilter.values)
                      ChoiceChip(
                        label: Text(switch (filter) {
                          _RoleFilter.all => 'Todos',
                          _RoleFilter.admin => 'Mestres',
                          _RoleFilter.user => 'Viajantes',
                        }),
                        selected: _role == filter,
                        onSelected: (_) => setState(() => _role = filter),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (filteredUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhum usuário encontrado.'),
                  ),
                for (final user in filteredUsers)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(user.name.isEmpty
                            ? '✦'
                            : user.name[0].toUpperCase()),
                      ),
                      title: Text(user.name),
                      subtitle: Text(
                        '${user.email}\n${user.zodiacSign} · ${user.role}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        '${user.stardust} ✦',
                        style: const TextStyle(color: AstrumColors.gold),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(color: AstrumColors.gold, fontSize: 22)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
