/// 题组卡的界面验收（P0，2026-11-18）：列表折成**一张题组卡**，详情页说「本组共 N 小问」。
///
/// 用户口径：一篇文章 + 若干小问 = 一道题。题库列表不能按小问重复出卡，否则
/// 语文现代文阅读 II 一篇会占 4 格、组卷凑 3 精研 / 6 速刷时会多算题。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const int _ts = 1700000000000;

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  const material = '【材料 S1-M1】\n种植入门问答\n凡种植，先辨土性。';

  Future<void> seedRow(
    String id, {
    required String question,
    int serialNo = 0,
    int updatedAt = _ts,
  }) {
    return db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: '$material\n\n【题目】\n$question',
            subjectKey: const Value('chinese'),
            sourceLabel: const Value('2025 全国 I 卷'),
            serialNo: Value(serialNo),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            answer: const Value('参考答案'),
            solution: const Value('解析'),
          ),
        );
  }

  Future<void> seedStandalone(String id, {required String stem}) {
    return db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            createdAt: _ts,
            updatedAt: _ts,
            answer: const Value('A'),
            solution: const Value('解析'),
          ),
        );
  }

  Future<void> seedChineseGroup() async {
    for (var i = 1; i <= 4; i++) {
      await seedRow(
        'q-modern-$i',
        question: '（$i）第 $i 小问',
        serialNo: i,
      );
    }
  }

  Future<void> pumpBank(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(null),
          questionMediaStoreProvider.overrideWithValue(
            FakeQuestionMediaStore(database: db),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionBankPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 详情页有不满意的进度条，`pumpAndSettle` 会等不到静止：推固定帧数。
  Future<void> settleDetail(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('题库列表：4 个小问折成 1 张题组卡（材料 + 「4 小问」），不重复出卡', (tester) async {
    await seedChineseGroup();
    await seedStandalone('q-alone-1', stem: '求函数的最小值。');
    await seedStandalone('q-alone-2', stem: '求概率分布。');

    await pumpBank(tester);

    // 3 道题（1 题组 + 2 独立题），不是 6 张卡。
    expect(find.byKey(ValueKey<String>(questionBankRowKeyFor('q-modern-1'))),
        findsOneWidget);
    for (final id in <String>['q-modern-2', 'q-modern-3', 'q-modern-4']) {
      expect(
        find.byKey(ValueKey<String>(questionBankRowKeyFor(id))),
        findsNothing,
        reason: '组内小问不再各占一张卡',
      );
    }
    expect(find.byKey(ValueKey<String>(questionBankRowKeyFor('q-alone-1'))),
        findsOneWidget);
    expect(find.byKey(ValueKey<String>(questionBankRowKeyFor('q-alone-2'))),
        findsOneWidget);

    // 统计口径按题组：共 3 道题。
    expect(find.text(zh.questionBankSummary(3, 1)), findsOneWidget);

    // 题组徽标 + N 小问。
    expect(
      find.byKey(ValueKey<String>(
        questionBankGroupBadgeKeyFor('q-modern-1'),
      )),
      findsOneWidget,
    );
    expect(find.text(zh.questionBankGroupSubCount(4)), findsOneWidget);
    // 卡片摘要是材料正文，不是第一个小问的题干。
    expect(find.textContaining('种植入门问答'), findsWidgets);
  });

  testWidgets('详情页：打开组内第一题显示「本组共 4 小问」', (tester) async {
    await seedChineseGroup();

    await pumpBank(tester);
    await tester.tap(
      find.byKey(ValueKey<String>(questionBankRowKeyFor('q-modern-1'))),
    );
    await tester.pump();
    await settleDetail(tester);

    expect(find.byType(QuestionDetailPage), findsOneWidget);
    expect(find.byKey(questionDetailGroupHintKey), findsOneWidget);
    expect(find.textContaining('本组共 4 小问'), findsOneWidget);
    // 代表题的正文里材料在内（整卷导入把材料内联进每行），没有丢数据。
    expect(find.textContaining('种植入门问答'), findsWidgets);
  });

  testWidgets('详情页：独立题不显示题组提示', (tester) async {
    await seedStandalone('q-alone-1', stem: '求函数的最小值。');

    await pumpBank(tester);
    await tester.tap(
      find.byKey(ValueKey<String>(questionBankRowKeyFor('q-alone-1'))),
    );
    await tester.pump();
    await settleDetail(tester);

    expect(find.byType(QuestionDetailPage), findsOneWidget);
    expect(find.byKey(questionDetailGroupHintKey), findsNothing);
  });
}
