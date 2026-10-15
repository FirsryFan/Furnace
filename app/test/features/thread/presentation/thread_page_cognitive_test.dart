import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';
import 'package:furnace/features/thread/presentation/thread_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The cognitive-order switch is the only place the user can turn roadmap §2-D's
/// tier on, and the note under the app bar is the only place the UI admits the
/// boosts are uncalibrated. Both are pinned here.
AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ThreadPage)));

void main() {
  testWidgets('菜单里的认知排序开关落库，并在打开时标出未标定', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await TaskRepository(db).createTask(title: '写物理作业', estimateMinutes: 15);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // The page shows "需要重新排序" until the feed has been built once; the
    // switch has to work on the real list, so sort before pumping.
    await container.read(threadFeedProvider.notifier).sort();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThreadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    final rankRepository = ThreadRankRepository(db);
    // 页面上不止一个 ⋮（状态栏自己也有一个），只点 AppBar 里那个菜单。
    final menuFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_vert),
    );

    // 默认关：不仅库里是 false，界面上也不该出现"未标定"的说明。
    expect(await rankRepository.getCognitiveRankEnabled(), isFalse);
    expect(find.text('写物理作业'), findsOneWidget);
    expect(find.text(l10n.threadCognitiveRankNote), findsNothing);

    // `_ThreadMenuItem` 是私有类型，只能按"菜单项里带这段文字"找；直接点文字会
    // 打在 RenderParagraph 上（hit test 报 warnIfMissed），所以点它所在的菜单项。
    Finder menuItem(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
        );
    Future<void> openMenu() async {
      await tester.tap(menuFinder);
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text(l10n.threadCognitiveRankToggle), findsOneWidget);
    expect(find.text(l10n.threadRhythmToggle), findsOneWidget);

    await tester.tap(menuItem(l10n.threadCognitiveRankToggle));
    await tester.pumpAndSettle();

    expect(await rankRepository.getCognitiveRankEnabled(), isTrue);
    expect(container.read(cognitiveRankEnabledProvider).valueOrNull, isTrue);
    expect(find.text(l10n.threadCognitiveRankNote), findsOneWidget);

    // 再翻回去：库里写回 false，说明行消失（开关是可逆的，不是一次性）。
    await openMenu();
    await tester.tap(menuItem(l10n.threadCognitiveRankToggle));
    await tester.pumpAndSettle();

    expect(await rankRepository.getCognitiveRankEnabled(), isFalse);
    expect(find.text(l10n.threadCognitiveRankNote), findsNothing);
  });
}
