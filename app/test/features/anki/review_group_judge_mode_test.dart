/// 按卡组判分方式：持久层读写 + 计划页入口的验收点。
///
///  * 写 review_group_plans.judge_mode；读回来 NULL = 跟随全局；
///  * 未知值按「跟随全局」处理，不回填；
///  * 计划页每个已配置的卡组有「自判 / 严格」两个 chip，点严格真的落库。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/application/judge_mode_preference.dart';
import 'package:furnace/features/anki/presentation/review_plan_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewPlanRepository plans;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    plans = ReviewPlanRepository(db, anki);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  test('写入/读回/清除：NULL = 跟随全局', () async {
    final tag = await tags.createTag(name: '数学');

    await plans.setGroupJudgeMode(tag.id, JudgeModePreference.strict);
    var group = (await plans.groupPlans()).single;
    expect(group.judgeMode, JudgeModePreference.strict);
    expect(group.tagPath, '数学');

    await plans.setGroupJudgeMode(tag.id, JudgeModePreference.self);
    group = (await plans.groupPlans()).single;
    expect(group.judgeMode, JudgeModePreference.self);

    // null = 跟随全局：列真的写回 NULL，而不是写 'self'。
    await plans.setGroupJudgeMode(tag.id, null);
    group = (await plans.groupPlans()).single;
    expect(group.judgeMode, isNull);
    final row = (await db.select(db.reviewGroupPlans).get()).single;
    expect(row.judgeMode, isNull);
  });

  test('未知值按跟随全局处理，不报错', () async {
    final tag = await tags.createTag(name: '物理');
    await db.into(db.reviewGroupPlans).insert(
          ReviewGroupPlansCompanion.insert(
            id: 'rgp::${tag.id}',
            tagId: tag.id,
            judgeMode: const Value<String?>('a-mode-from-the-future'),
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    final group = (await plans.groupPlans()).single;
    expect(group.judgeMode, isNull);
    expect(await plans.judgeModeRules(), isEmpty);
  });

  test('judgeModeRules 只返回显式设置过的卡组（带标签路径）', () async {
    final parent = await tags.createTag(name: '文化课');
    final math = await tags.createTag(name: '数学', parentId: parent.id);
    final chinese = await tags.createTag(name: '语文', parentId: parent.id);
    await plans.setGroupJudgeMode(math.id, JudgeModePreference.strict);
    await plans.setGroupJudgeMode(chinese.id, JudgeModePreference.self);

    final rules = await plans.judgeModeRules();
    expect(rules, hasLength(2));
    final byPath = {for (final rule in rules) rule.tagPath: rule.mode};
    expect(byPath['文化课/数学'], JudgeModePreference.strict);
    expect(byPath['文化课/语文'], JudgeModePreference.self);
  });

  testWidgets('计划页：点「严格」chip 真的写进 review_group_plans.judge_mode',
      (tester) async {
    final tag = await tags.createTag(name: '数学');
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 50,
    );

    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewPlanPage(),
        ),
      ),
    );
    await settle(tester);

    final strictChip = find.byKey(reviewGroupJudgeStrictKey(tag.id));
    expect(strictChip, findsOneWidget);
    // 默认跟随全局（自判）：自判 chip 选中、严格 chip 未选中。
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(
              reviewGroupJudgeSelfKey(tag.id),
            ))
            .selected,
        isTrue);

    await tester.tap(strictChip);
    await settle(tester);

    final row = (await db.select(db.reviewGroupPlans).get()).single;
    expect(row.judgeMode, 'strict');
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(reviewGroupJudgeStrictKey(tag.id)))
          .selected,
      isTrue,
    );
  });
}
