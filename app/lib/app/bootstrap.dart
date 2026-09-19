import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings/settings_controller.dart';

/// Loads persisted settings and profile on app start.
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref
            .read(settingsControllerProvider.notifier)
            .loadFromDatabase();
      } catch (_) {
        // Local persistence is best-effort on first launch.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
