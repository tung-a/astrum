import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(incomingRequestCountProvider);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Cosmos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.visibility_outlined),
            selectedIcon: Icon(Icons.visibility),
            label: 'Oráculo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Rituais',
          ),
          const NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Astral',
          ),
          NavigationDestination(
            icon: _ProfileIcon(count: pending, selected: false),
            selectedIcon: _ProfileIcon(count: pending, selected: true),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Icone do Perfil com selo de pedidos de amizade recebidos.
class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.person : Icons.person_outline);
    if (count == 0) return icon;
    return Semantics(
      label: count == 1 ? '1 pedido de amizade' : '$count pedidos de amizade',
      child: Badge.count(count: count, child: icon),
    );
  }
}
