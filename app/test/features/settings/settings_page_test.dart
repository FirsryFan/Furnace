// 用户反馈："flashcard 的卡组设置我还没有找到在哪里"。
//
// 卡组在这个 app 里就是一个**标签**（`docs/AI_DESIGN.md` 的复习一节：标签树就是卡组），
// 真正的设置在「复习计划」页：每个标签的每日新卡/复习上限 + 判分方式/卡片类型。
// 之前它只挂在复习页顶栏的两个图标后面，等于藏起来了 —— 这条测试钉住设置页里的
// 明确入口，防止它再被"顺手挪走"。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/anki/presentation/review_plan_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;
  late AppLocalizations en;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpSettings(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
  }) async {
    // 设置页是一长列 tile：视口够高才不会让"卡组设置"这一行根本没被构建。
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置里有「卡组设置」，点进去就是卡组（=标签树）的每日任务量与复习偏好', (tester) async {
    await pumpSettings(tester);

    expect(find.text(zh.settingsCardGroups), findsOneWidget);
    // 副标题把"卡组=标签树"说清楚，不让人再猜一次。
    expect(find.text(zh.settingsCardGroupsHint), findsOneWidget);

    await tester.tap(find.text(zh.settingsCardGroups));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewPlanPage), findsOneWidget);
    // 那一页顶部就是复习偏好的说明，下面才是每个卡组的任务量。
    expect(find.text(zh.reviewPreferences), findsWidgets);
  });

  testWidgets('English settings points at the same place', (tester) async {
    await pumpSettings(tester, locale: const Locale('en'));

    expect(find.text(en.settingsCardGroups), findsOneWidget);

    await tester.tap(find.text(en.settingsCardGroups));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewPlanPage), findsOneWidget);
  });
}
