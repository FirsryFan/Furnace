import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../features/anki/presentation/knowledge_page.dart';
import '../../features/tags/presentation/tag_tree_page.dart';
import '../../features/packages/presentation/packages_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/thread/application/thread_rank_service.dart';
import '../../features/thread/presentation/thread_page.dart';
import '../../features/timeboard/presentation/time_page.dart';

/// Ctrl+R: re-sort the Thread feed.
class _SortThreadIntent extends Intent {
  const _SortThreadIntent();
}

/// Ctrl+1..4: jump to a top-level module.
class _GoToTabIntent extends Intent {
  const _GoToTabIntent(this.index);

  final int index;
}

/// App shell with desktop navigation rail and mobile bottom navigation.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = <Widget>[
      const TagTreePage(),
      const ThreadPage(),
      const TimePage(),
      const KnowledgePage(),
      const PackagesPage(),
      const SettingsPage(),
    ];

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.account_tree_outlined),
        selectedIcon: const Icon(Icons.account_tree),
        label: l10n.navTags,
      ),
      NavigationDestination(
        icon: const Icon(Icons.bolt_outlined),
        selectedIcon: const Icon(Icons.bolt),
        label: l10n.navThread,
      ),
      NavigationDestination(
        icon: const Icon(Icons.schedule_outlined),
        selectedIcon: const Icon(Icons.schedule),
        label: l10n.navTime,
      ),
      NavigationDestination(
        icon: const Icon(Icons.psychology_outlined),
        selectedIcon: const Icon(Icons.psychology),
        label: l10n.navAnki,
      ),
      NavigationDestination(
        icon: const Icon(Icons.library_books_outlined),
        selectedIcon: const Icon(Icons.library_books),
        label: l10n.navPackages,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.navSettings,
      ),
    ];

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions(context),
        child: _buildShell(context, l10n, pages, destinations),
      ),
    );
  }

  /// Desktop keyboard shortcuts (user feedback item 2: the app needed
  /// shortcuts, not only mouse targets).
  static final Map<ShortcutActivator, Intent> _shortcuts = {
    const SingleActivator(LogicalKeyboardKey.keyR, control: true):
        const _SortThreadIntent(),
    const SingleActivator(LogicalKeyboardKey.digit1, control: true):
        const _GoToTabIntent(0),
    const SingleActivator(LogicalKeyboardKey.digit2, control: true):
        const _GoToTabIntent(1),
    const SingleActivator(LogicalKeyboardKey.digit3, control: true):
        const _GoToTabIntent(2),
    const SingleActivator(LogicalKeyboardKey.digit4, control: true):
        const _GoToTabIntent(3),
  };

  Map<Type, Action<Intent>> _actions(BuildContext context) => {
        _SortThreadIntent: CallbackAction<_SortThreadIntent>(
          onInvoke: (intent) {
            // Sorting is a Thread action; if the user is elsewhere, switch
            // there first so the shortcut has a visible effect.
            if (_selectedIndex != 1) {
              setState(() => _selectedIndex = 1);
            }
            ref.read(threadFeedProvider.notifier).sort();
            return null;
          },
        ),
        _GoToTabIntent: CallbackAction<_GoToTabIntent>(
          onInvoke: (intent) {
            final index = intent.index.clamp(0, 3);
            setState(() => _selectedIndex = index);
            return null;
          },
        ),
      };

  Widget _buildShell(
    BuildContext context,
    AppLocalizations l10n,
    List<Widget> pages,
    List<NavigationDestination> destinations,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          );
        }

        return Scaffold(
          body: pages[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            destinations: destinations,
          ),
        );
      },
    );
  }
}
