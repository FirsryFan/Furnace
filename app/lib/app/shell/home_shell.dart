import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../core/state/data_change_bus.dart';
import '../../core/theme/app_icons.dart';
import '../../features/ai/presentation/ai_chat_page.dart';
import '../../features/anki/application/review_reminder_service.dart';
import '../../features/anki/presentation/knowledge_page.dart';
import '../../features/anki/presentation/review_reminder_texts.dart';
import '../../features/settings/application/appearance_providers.dart';
import '../../features/tags/presentation/tag_tree_page.dart';
import '../../features/cognitive/presentation/mindnet_page.dart';
import '../../features/questions/presentation/question_bank_page.dart';
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
    destination('questions', l10n.navQuestions),
    // MindNet 是用户模型模块（决策记录 docs/DECISIONS-2026-11.md D3）；
    // 知识库（.kpak）不再是顶层目的地，入口下沉到设置页。
    destination('mindnet', l10n.navMindnet),
    destination('ai', l10n.navAi),
    destination('settings', l10n.navSettings),
  ];
}

/// Ctrl+R: re-sort the Thread feed.
class _SortThreadIntent extends Intent {
  const _SortThreadIntent();
}

/// Ctrl+1..5: jump to a top-level module.
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  /// 是否正在重排复习提醒：启动首帧与回到前台可能挨着触发，只跑一次。
  bool _reminderRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧之后再排：initState 里读不到 AppLocalizations，而且通知插件的初始化
    // 不该挡在第一帧前面。排不上不影响界面（异常在方法里吞掉）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshReviewReminder();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the foreground is a data change even when nothing was
  /// written: due cards, today's schedule and "sorted N minutes ago" are all
  /// derived from the clock. Refreshing here is what keeps a long-running app
  /// from showing yesterday.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DataChangeBus.instance.recordChange();
      // 到期卡数随时钟变（跨过午夜、隔天再打开），回到前台就重算一次。
      _refreshReviewReminder();
    }
  }

  /// 重排「什么时候提醒复习」的那条本地通知。
  ///
  /// 排程是 cancel-then-schedule（见 `ReviewReminderService.refresh`），重复
  /// 调用只会把旧通知换成新的，不会叠出两条。失败只记日志：一条提醒排不上，
  /// 不该让外壳启动失败。
  Future<void> _refreshReviewReminder() async {
    if (_reminderRefreshing) {
      return;
    }
    _reminderRefreshing = true;
    try {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      await ref
          .read(reviewReminderServiceProvider)
          .refresh(texts: reviewReminderTextsFor(l10n));
    } on Object catch (error) {
      debugPrint('复习提醒刷新失败：$error');
    } finally {
      _reminderRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // AI 是一等模块（决策记录 D4）：入口常驻，未配置 key 时对话页自己渲染
    // 配置引导。这样它不再像"某个开关打开后才存在的附属功能"。
    final pages = <Widget>[
      const TagTreePage(),
      const ThreadPage(),
      const TimePage(),
      const KnowledgePage(),
      const QuestionBankPage(),
      const MindNetPage(),
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
    );

    // Clearing the key removes the AI destination; if it happened to be
    // selected, the index would point past the end.
    final selected = _selectedIndex.clamp(0, pages.length - 1);

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions(
          context,
          pageCount: pages.length,
        ),
        child: _buildShell(context, l10n, pages, destinations, selected),
      ),
    );
  }

  /// 设置页在 8 个常驻目的地里固定是最后一个。
  int get _settingsIndex => 7;

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
    // Ctrl+5: 题库。它和 Ctrl+1..4 一样钉在固定位置（AI 目的地在它后面插入）。
    const SingleActivator(LogicalKeyboardKey.digit5, control: true):
        const _GoToTabIntent(4),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true):
        const _GoToSettingsIntent(),
  };

  Map<Type, Action<Intent>> _actions(
    BuildContext context, {
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
            setState(() => _selectedIndex = 7);
            return null;
          },
        ),
      };

  /// 手机底部导航的「更多」面板：低频入口不挤占主 Tab，但一步可达。
  void _openMoreSheet(
    BuildContext context,
    List<({int index, IconData icon, String label})> items, {
    required ValueChanged<int> onPick,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onPick(item.index);
                },
              ),
          ],
        ),
      ),
    );
  }

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

        // 手机宽度只放 5 个主入口：Thread、复习、题库、MindNet、更多。
        // 其余入口（标签树、Time、AI、设置）收进「更多」面板，底部导航不再
        // 挤 8 个图标；桌面端 NavigationRail 仍保留全部目的地。
        const primaryIndices = <int>[1, 3, 4, 5];
        final secondary = <({int index, IconData icon, String label})>[
          (index: 0, icon: Icons.sell_outlined, label: l10n.navTags),
          (index: 2, icon: Icons.schedule_outlined, label: l10n.navTime),
          (index: 6, icon: Icons.forum_outlined, label: l10n.navAi),
          (index: 7, icon: Icons.settings_outlined, label: l10n.navSettings),
        ];
        final primaryPosition = primaryIndices.indexOf(selected);
        return Scaffold(
          body: pages[selected],
          bottomNavigationBar: NavigationBar(
            selectedIndex: primaryPosition >= 0 ? primaryPosition : 4,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (position) {
              if (position == 4) {
                _openMoreSheet(context, secondary, onPick: (index) {
                  setState(() => _selectedIndex = index);
                });
                return;
              }
              setState(() => _selectedIndex = primaryIndices[position]);
            },
            destinations: [
              for (final index in primaryIndices)
                NavigationDestination(
                  icon: destinations[index].icon,
                  selectedIcon: destinations[index].selectedIcon,
                  label: destinations[index].label,
                ),
              NavigationDestination(
                icon: const Icon(Icons.more_horiz),
                selectedIcon: const Icon(Icons.more_horiz),
                label: l10n.knowledgeMoreActions,
              ),
            ],
          ),
        );
      },
    );
  }
}
