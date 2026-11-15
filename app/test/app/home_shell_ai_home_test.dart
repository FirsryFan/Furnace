/// AI 默认首页与导航顺序（用户决定 2026-11-15：AI 当主页，标签保留为知识入口）。
///
/// 这个文件守四件事：
///   1. 启动第一帧落在 AI（索引 0），未配置 key 时显示配置引导而不是空白；
///   2. 标签仍是知识入口：桌面 rail 点得到，选中索引变成 1；
///   3. 8 个目的地的顺序 = AI、标签、Thread、Time、闪存卡、题库、MindNet、设置；
///   4. Ctrl+1..7 与 Ctrl+0 的语义跟导航顺序一致。
///
/// 快捷键用例通过 `Shortcuts` 的映射表 + `Actions` 注册表触发：无头 widget
/// 测试里没有可聚焦的输入框，真实键盘事件不会冒泡到 shell 的 `Shortcuts`，
/// 而走同一条 intent -> action 路径可以验证映射本身没有错位。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/shell/home_shell.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/features/anki/presentation/knowledge_page.dart';
import 'package:furnace/features/cognitive/presentation/mindnet_page.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';
import 'package:furnace/features/thread/presentation/thread_page.dart';
import 'package:furnace/features/timeboard/presentation/time_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));

/// 装一个宽屏 shell（NavigationRail，8 个目的地全部可见）。
///
/// 空测试库 = 没配 AI key，因此 AI 页渲染配置引导；这正是
/// "AI 不可用时启动仍然可用" 要守的场景。
Future<void> _pumpWideShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

NavigationRail _rail(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail));

/// 取 shell 自己的 `Shortcuts`（页内也可能有 Shortcuts，取 HomeShell 下第一个）。
Shortcuts _shellShortcuts(WidgetTester tester) => tester.widget<Shortcuts>(
      find
          .descendant(
            of: find.byType(HomeShell),
            matching: find.byType(Shortcuts),
          )
          .first,
    );

/// 在 `Shortcuts.shortcuts` 里找 Ctrl+[key] 对应的 intent。
///
/// 不能直接 `map[SingleActivator(...)]`：`SingleActivator` 没有重写 `==`
/// （按键匹配靠 `accepts`，不是靠 Map 查找），所以 Map 的 const key 只能被
/// 同一个 const 实例命中，用变量构造的 activator 查不到。这里按字段匹配。
Intent? _ctrlIntentFor(Shortcuts shortcuts, LogicalKeyboardKey key) {
  for (final entry in shortcuts.shortcuts.entries) {
    final activator = entry.key;
    if (activator is SingleActivator &&
        activator.trigger == key &&
        activator.control &&
        !activator.shift &&
        !activator.alt &&
        !activator.meta) {
      return entry.value;
    }
  }
  return null;
}

/// 按 `Shortcuts` 表里的 Ctrl+[digit] 触发一次，走 shell 注册的 action。
Future<void> _invokeCtrlDigit(WidgetTester tester, int digit) async {
  final shortcuts = _shellShortcuts(tester);
  final key = switch (digit) {
    0 => LogicalKeyboardKey.digit0,
    1 => LogicalKeyboardKey.digit1,
    2 => LogicalKeyboardKey.digit2,
    3 => LogicalKeyboardKey.digit3,
    4 => LogicalKeyboardKey.digit4,
    5 => LogicalKeyboardKey.digit5,
    6 => LogicalKeyboardKey.digit6,
    7 => LogicalKeyboardKey.digit7,
    _ => throw ArgumentError.value(digit, 'digit'),
  };
  final intent = _ctrlIntentFor(shortcuts, key);
  expect(intent, isNotNull, reason: 'Ctrl+$digit 没有注册到 shell Shortcuts');
  final resolved = intent!;

  final context = tester.element(find.byType(NavigationRail));
  final action = Actions.maybeFind<Intent>(context, intent: resolved);
  expect(action, isNotNull, reason: 'Ctrl+$digit 的 intent 没有对应的 action');
  Actions.invoke(context, resolved);
  await tester.pumpAndSettle();
}

void main() {
  test('8 个目的地顺序：AI 第一、标签第二、设置最后', () {
    final destinations = shellDestinations(
      l10n: _zh,
      icons: const <String, String>{},
    );
    expect(
      <String>[for (final destination in destinations) destination.label],
      <String>[
        _zh.navAi,
        _zh.navTags,
        _zh.navThread,
        _zh.navTime,
        _zh.navAnki,
        _zh.navQuestions,
        _zh.navMindnet,
        _zh.navSettings,
      ],
      reason: 'AI 是默认首页并排第一；标签仍是第二位知识入口；设置固定最后',
    );
  });

  testWidgets('启动落在 AI：selectedIndex 为 0，未配置 key 时显示配置引导', (tester) async {
    await _pumpWideShell(tester);

    expect(_rail(tester).selectedIndex, 0, reason: '默认首页是 AI（索引 0）');
    expect(find.byType(AiChatPage), findsOneWidget);
    expect(
      find.text(_zh.aiNotConfigured),
      findsOneWidget,
      reason: '没有 key 时 AI 页要有配置引导，不能是一片空白',
    );
    expect(find.byType(TagTreePage), findsNothing, reason: '启动不落在标签页');

    final first = _rail(tester).destinations.first;
    expect((first.label as Text).data, _zh.navAi);
  });

  testWidgets('标签仍是知识入口：桌面 rail 点得到，选中索引变成 1', (tester) async {
    await _pumpWideShell(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        // 未选中的标签画 outlined 变体（AI 此时占着 filled）。
        matching: find.byIcon(Icons.account_tree_outlined),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TagTreePage), findsOneWidget);
    expect(find.byType(AiChatPage), findsNothing);
    expect(_rail(tester).selectedIndex, 1);
  });

  testWidgets('Ctrl+1..7 与 Ctrl+0 按导航顺序跳转', (tester) async {
    await _pumpWideShell(tester);

    // Ctrl+N（1..7）按 1-based 对应导航顺序；Ctrl+0 固定是设置页。
    final steps = <(int, Type, int)>[
      (1, AiChatPage, 0),
      (2, TagTreePage, 1),
      (3, ThreadPage, 2),
      (4, TimePage, 3),
      (5, KnowledgePage, 4),
      (6, QuestionBankPage, 5),
      (7, MindNetPage, 6),
      (0, SettingsPage, 7),
    ];
    for (final (digit, page, index) in steps) {
      await _invokeCtrlDigit(tester, digit);
      expect(
        find.byType(page),
        findsOneWidget,
        reason: 'Ctrl+$digit 应打开 $page',
      );
      expect(
        _rail(tester).selectedIndex,
        index,
        reason: 'Ctrl+$digit 的 selectedIndex 应为 $index',
      );
    }
  });

  testWidgets('Ctrl+R 会切到 Thread 页（Thread 现在是索引 2）', (tester) async {
    await _pumpWideShell(tester);

    final shortcuts = _shellShortcuts(tester);
    final intent = _ctrlIntentFor(shortcuts, LogicalKeyboardKey.keyR);
    expect(intent, isNotNull);

    final context = tester.element(find.byType(NavigationRail));
    final action = Actions.maybeFind<Intent>(context, intent: intent!);
    expect(action, isNotNull);
    Actions.invoke(context, intent);
    await tester.pumpAndSettle();

    expect(find.byType(ThreadPage), findsOneWidget);
    expect(_rail(tester).selectedIndex, 2);
  });
}
