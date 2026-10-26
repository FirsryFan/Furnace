import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/questions/question_capability.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

void main() {
  testWidgets('能力点：标注了就用词表中文名摆出来', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '已知二次函数，求最值。',
      capability: const <String>['A3', 'A9'],
    );

    await _pumpDetail(tester, database, question.id);
    final l10n = _l10nOf(tester);

    await _waitFor(tester, find.byKey(questionCapabilityChipsKey));
    expect(find.text(l10n.questionCapabilitySection), findsOneWidget);
    expect(
      find.text(
          '${QuestionCapability.a3.code} ${QuestionCapability.a3.labelZh}'),
      findsOneWidget,
    );
    expect(
      find.text(
          '${QuestionCapability.a9.code} ${QuestionCapability.a9.labelZh}'),
      findsOneWidget,
    );
  });

  testWidgets('能力点：没标注时整块不出现', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database, stem: '没有标能力点的题。');

    await _pumpDetail(tester, database, question.id);
    final l10n = _l10nOf(tester);

    expect(find.byKey(questionCapabilityChipsKey), findsNothing);
    expect(find.text(l10n.questionCapabilitySection), findsNothing);
  });

  testWidgets('母题在库里：入口带母题题号，点进去是母题详情', (WidgetTester tester) async {
    final database = _newDatabase();
    final parent = await _seedQuestion(
      database,
      stem: '母题：已知二次函数的图像过三点。',
      zujuanQuestionId: 'zj-parent-1',
    );
    final child = await _seedQuestion(
      database,
      stem: '扩展题：求这个二次函数的最小值。',
      zujuanQuestionId: 'zj-child-1',
      extensionOf: 'zj-parent-1',
    );

    await _pumpDetail(tester, database, child.id);
    final l10n = _l10nOf(tester);

    await _waitFor(tester, find.byKey(questionExtensionParentKey));
    expect(find.byKey(questionExtensionLinksKey), findsOneWidget);
    expect(
      find.text(l10n.questionExtensionParentSerial(parent.serialNo!)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(questionExtensionParentKey));
    await _waitFor(tester, find.textContaining('母题：已知二次函数'));
    // 路由退场动画期间旧页还在树里，按 questionId 认新页而不是数数量。
    expect(_pageFor(parent.id), findsOneWidget);
  });

  testWidgets('母题不在库里：摆组卷网题号与缺失提示，点不动', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '孤儿扩展题：母题还没导入。',
      zujuanQuestionId: 'zj-orphan-1',
      extensionOf: 'zj-gone-9',
    );

    await _pumpDetail(tester, database, question.id);
    final l10n = _l10nOf(tester);

    await _waitFor(
      tester,
      find.text(l10n.questionExtensionParentZujuan('zj-gone-9')),
    );
    expect(find.text(l10n.questionExtensionParentMissing), findsOneWidget);
    expect(find.byKey(questionExtensionParentKey), findsNothing);
  });

  testWidgets('扩展题：标题带数量，点一行进子题详情', (WidgetTester tester) async {
    final database = _newDatabase();
    final parent = await _seedQuestion(
      database,
      stem: '母题：一道可以派生的题。',
      zujuanQuestionId: 'zj-chain-1',
    );
    final first = await _seedQuestion(
      database,
      stem: '扩展题一：改变一个条件。',
      zujuanQuestionId: 'zj-chain-child-1',
      extensionOf: 'zj-chain-1',
    );
    final second = await _seedQuestion(
      database,
      stem: '扩展题二：再改一个条件。',
      zujuanQuestionId: 'zj-chain-child-2',
      extensionOf: 'zj-chain-1',
    );

    await _pumpDetail(tester, database, parent.id);
    final l10n = _l10nOf(tester);

    await _waitFor(tester, find.byKey(questionExtensionLinksKey));
    expect(find.text(l10n.questionExtensionChildrenTitle(2)), findsOneWidget);
    expect(find.text('扩展题一：改变一个条件。'), findsOneWidget);
    expect(find.text('扩展题二：再改一个条件。'), findsOneWidget);
    expect(find.byKey(questionExtensionChildKey(first.id)), findsOneWidget);
    expect(find.byKey(questionExtensionChildKey(second.id)), findsOneWidget);

    await tester.tap(find.byKey(questionExtensionChildKey(second.id)));
    // 先等新页出现：子题行预览里也有同样标题，等文字会被当前页立刻满足。
    await _waitFor(tester, _pageFor(second.id));
    expect(find.textContaining('扩展题二：再改一个条件'), findsWidgets);
  });

  testWidgets('两边都空：整块扩展关联不出现', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '既不是扩展题、也没有扩展题的独立题。',
      zujuanQuestionId: 'zj-alone-1',
    );

    await _pumpDetail(tester, database, question.id);

    expect(find.byKey(questionExtensionLinksKey), findsNothing);
    expect(find.byKey(questionExtensionParentKey), findsNothing);
  });
}

/// 每个用例自己建一个内存库并关掉。
AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seedQuestion(
  AppDatabase database, {
  required String stem,
  String? zujuanQuestionId,
  String? extensionOf,
  List<String> capability = const <String>[],
}) async {
  final result = await QuestionRepository(database).ingest(
    QuestionDraft(
      stem: stem,
      answer: '略',
      solution: '略',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      difficulty: 3,
      zujuanQuestionId: zujuanQuestionId,
      extensionOf: extensionOf,
      capability: capability,
    ),
  );
  return result.question;
}

/// 打开题目详情页：视口放大，避免内容被裁掉影响断言。
Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId,
) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: questionId),
      ),
    ),
  );
  // 页面里有不定值转圈与异步 provider，不用 pumpAndSettle：固定推进到读数落地。
  await _settle(tester);
}

/// 固定推进一段模拟时间：让题目 / 能力点 / 扩展关联几份异步读数都落地。
Future<void> _settle(WidgetTester tester, {int frames = 40}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(QuestionDetailPage).first));

/// 详情页按 questionId 定位：路由退场动画期间旧的详情页还在树上。
Finder _pageFor(String questionId) => find.byWidgetPredicate(
      (widget) =>
          widget is QuestionDetailPage && widget.questionId == questionId,
    );

/// 等某个 finder 命中（异步 provider 的块出现得比首帧晚）。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int rounds = 80,
}) async {
  for (var index = 0; index < rounds; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 4 秒也没等到 $finder');
}
