import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../theme/astrum_colors.dart';
import '../../widgets/cosmic_scaffold.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CosmicScaffold(
      title: 'Admin',
      body: FutureBuilder(
        future: ref.read(userRepositoryProvider).listUsers(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!;
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, i) {
              final u = users[i];
              return ListTile(
                title: Text(u.name),
                subtitle: Text('${u.email} · ${u.zodiacSign} · ${u.role}'),
                trailing: Text('${u.stardust} ✦',
                    style: const TextStyle(color: AstrumColors.gold)),
              );
            },
          );
        },
      ),
    );
  }
}
