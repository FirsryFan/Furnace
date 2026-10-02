import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../core/theme/app_icons.dart';
import '../../features/ai/application/ai_providers.dart';
import '../../features/ai/presentation/ai_chat_page.dart';
import '../../features/anki/presentation/knowledge_page.dart';
import '../../features/settings/application/appearance_providers.dart';
import '../../features/tags/presentation/tag_tree_page.dart';
import '../../features/packages/presentation/packages_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/thread/application/thread_rank_service.dart';
import '../../features/thread/presentation/thread_page.dart';
import '../../features/timeboard/presentation/time_page.dart';

/// The shell's destinations, with their icons resolved from the active theme.
///
/// Slot names are the only thing that ties a destination to an icon: the labels
/// stay exactly where they were (l10n), and an unconfigured slot renders the
/// factory icon, so an untouched theme looks like the app always looked.
///
/// A top-level function rather than an inline list so the theme -> icon path can
/// be exercised without mounting every page the shell hosts (see
/// `test/features/settings/icon_picker_test.dart`).
List<NavigationDestination> shellDestinations({
  required AppLocalizations l10n,
  required Map<String, String> icons,
  required bool aiConfigured,
}) {
  NavigationDestination destination(String slot, String label) =>
      NavigationDestination(
        icon: Icon(AppIcons.iconData(slot, icons, filled: false)),
        selectedIcon: Icon(AppIcons.iconData(slot, icons, filled: true)),
        label: label,
      );

  return <NavigationDestination>[
    destination('tags', l10n.navTags),
    destination('thread', l10n.navThread),
    destination('time', l10n.navTime),
    destination('knowledge', l10n.navAnki),
    destination('packages', l10n.navPackages),
    if (aiConfigured) destination('ai', l10n.navAi),
    destination('settings', l10n.navSettings),
  ];
}

/// Ctrl+R: re-sort the Thread feed.
class _SortThreadIntent extends Intent {
  const _SortThreadIntent();
}

/// Ctrl+1..4: jump to a top-level module.
class _GoToTabIntent extends Intent {
  const _GoToTabIntent(this.index);

  final int index;
}

/// Ctrl+0: jump to Settings, whose index depends on whether the AI page is
/// present.
class _GoToSettingsIntent extends Intent {
  const _GoToSettingsIntent();
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
    // The AI destination exists only once a key is configured (AI_DESIGN D15 /
    // requirement 8). Until then the shell is the app it was before the feature
    // existed, which is what keeps "offline by default" a property rather than
    // a promise.
    final aiConfigured = ref.watch(aiEnabledProvider);

    final pages = <Widget>[
      const TagTreePage(),
      const ThreadPage(),
      const TimePage(),
      const KnowledgePage(),
      const PackagesPage(),
      if (aiConfigured)
        AiChatPage(onOpenSettings: () => _goToTab(_settingsIndex)),
      const SettingsPage(),
    ];

    final destinations = shellDestinations(
      l10n: l10n,
      // The icons come from the active theme document (APPEARANCE_DESIGN D1).
      // Watching the provider is what makes a theme change visible immediately:
      // saving a theme invalidates it, this rebuilds, and the rail/bar re-renders
      // with the new IconData. `data` is null while following the legacy
      // system/light/dark setting, which is why the map defaults to empty - every
      // slot then renders its factory icon.
      icons: ref.watch(activeAppearanceProvider).valueOrNull?.data?.icons ??
          const <String, String>{},
      aiConfigured: aiConfigured,
    );

    // Clearing the key removes the AI destination; if it happened to be
    // selected, the index would point past the end.
    final selected = _selectedIndex.clamp(0, pages.length - 1);

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions(
          context,
          aiConfigured: aiConfigured,
          pageCount: pages.length,
        ),
        child: _buildShell(context, l10n, pages, destinations, selected),
      ),
    );
  }

  /// Index of the Settings tab, which shifts when the AI page is present.
  int get _settingsIndex => ref.read(aiEnabledProvider) ? 6 : 5;

  void _goToTab(int index) => setState(() => _selectedIndex = index);

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
    const SingleActivator(LogicalKeyboardKey.digit0, control: true):
        const _GoToSettingsIntent(),
  };

  Map<Type, Action<Intent>> _actions(
    BuildContext context, {
    required bool aiConfigured,
    required int pageCount,
  }) =>
      {
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
            // Ctrl+1..4 stay pinned to the first four modules: their positions
            // never move, so the shortcuts a user learned keep working no
            // matter whether the AI page is present.
            final index = intent.index.clamp(0, pageCount - 1);
            setState(() => _selectedIndex = index);
            return null;
          },
        ),
        // Ctrl+0 jumps to Settings, whose index shifts with the AI page.
        _GoToSettingsIntent: CallbackAction<_GoToSettingsIntent>(
          onInvoke: (intent) {
            setState(() => _selectedIndex = aiConfigured ? 6 : 5);
            return null;
          },
        ),
      };

  Widget _buildShell(
    BuildContext context,
    AppLocalizations l10n,
    List<Widget> pages,
    List<NavigationDestination> destinations,
    int selected,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
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
                Expanded(child: pages[selected]),
              ],
            ),
          );
        }

        return Scaffold(
          body: pages[selected],
          bottomNavigationBar: NavigationBar(
            selectedIndex: selected,
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
