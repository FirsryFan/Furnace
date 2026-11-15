// 用户反馈（两次）：
//  1. "flashcard 的卡组设置我还没有找到在哪里"（task-107 时把入口放进了设置页）；
//  2. "卡组设置不应放总设置；很多入口要合并"（task-113 第二遍清理）。
//
// 结论：卡组就是标签树，卡组的每日新卡/复习上限 + 判分方式属于**闪存卡模块**，
// 不是总设置。这条测试钉住两件事：
//  * 总设置里没有「卡组设置」；
//  * 闪存卡模块（复习 Tab 的顶栏「更多」菜单）里有它，点进去是复习计划页。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/anki/presentation/knowledge_page.dart';
import 'package:furnace/features/anki/presentation/review_plan_page.dart';
import 'package:furnace/features/assessment/presentation/assessment_center_page.dart';
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

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Locale locale = const Locale('zh'),
  }) async {
    // 设置页是一长列 tile：视口够高才不会让目标行根本没被构建。
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
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('总设置里没有「卡组设置」（卡组属于闪存卡模块）', (tester) async {
    await pumpPage(tester, const SettingsPage());

    expect(find.text(zh.settingsCardGroups), findsNothing);
    expect(find.text(zh.settingsCardGroupsHint), findsNothing);
    expect(find.byType(ReviewPlanPage), findsNothing);
  });

  testWidgets('English settings does not show deck settings either', (tester) async {
    await pumpPage(tester, const SettingsPage(), locale: const Locale('en'));

    expect(find.text(en.settingsCardGroups), findsNothing);
  });

  testWidgets('闪存卡模块里有「卡组设置」，点进去是复习计划页（卡组=标签树）',
      (tester) async {
    await pumpPage(tester, const KnowledgePage());

    // 主操作是「新建卡组」；卡组设置收在顶栏「更多」菜单里（低频入口不占图标）。
    expect(find.text(zh.deckListCreate), findsWidgets);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsCardGroups), findsOneWidget);

    await tester.tap(find.text(zh.settingsCardGroups));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewPlanPage), findsOneWidget);
    // 那一页顶部就是复习偏好的说明，下面才是每个卡组的任务量。
    expect(find.text(zh.reviewPreferences), findsWidgets);
  });

  // 用户评测板块设计文档 v1.0：设置页只留一个入口，旧的四项小测/画像两行
  // 收进评测中心页（能力测评与认知档案统一在 cog_* 八表里）。
  testWidgets('设置里有「评测与认知档案」，点进去是评测中心页', (tester) async {
    await pumpPage(tester, const SettingsPage());

    expect(find.text(zh.settingsAssessmentTitle), findsOneWidget);
    expect(find.text(zh.settingsAssessmentHint), findsOneWidget);

    await tester.tap(find.byKey(settingsAssessmentTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentCenterPage), findsOneWidget);
    expect(find.text(zh.assessmentCenterTitle), findsOneWidget);
  });
}
