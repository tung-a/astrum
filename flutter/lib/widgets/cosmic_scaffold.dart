import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../providers/app_providers.dart';
import '../theme/astrum_colors.dart';
import 'starfield.dart';

class CosmicScaffold extends ConsumerWidget {
  const CosmicScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottom,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(intentionProvider).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: title != null,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
            ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottom,
      body: Starfield(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              if (notice != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: _IntentionBanner(
                    notice: notice,
                    onDismiss: () {
                      final uid = ref.read(profileProvider).valueOrNull?.uid;
                      if (uid == null) return;
                      ref
                          .read(userRepositoryProvider)
                          .markNotificationRead(uid, notice.id);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntentionBanner extends StatelessWidget {
  const _IntentionBanner({required this.notice, required this.onDismiss});

  final IntentionNotice notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AstrumColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AstrumColors.gold.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AstrumColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${notice.fromName} enviou ${notice.intentionLabel}',
                style: const TextStyle(color: AstrumColors.cream),
              ),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Receber')),
          ],
        ),
      ),
    );
  }
}
