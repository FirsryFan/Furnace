/// 学生端干净 UI 的回归测试（2026-11-15）。
///
/// 三件事：
///  1. 学生页只显示学生内容：不出现 `content_package`、`已结构化`、来源分级、
///     内部 id、`aiQuality` 这些开发字段，也不出现「添加原题链接 / 改来源 /
///     改名 / 入库体检」等开发动作；
///  2. 开发字段与动作没有消失，统一在页底的「开发者信息」里；
///  3. 长题干与 Markdown 表格在窄视口里不裁切：文字换行，表格自带横向滚动，
///     页面不抛溢出异常。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_audit_reader.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';
import 'package:furnace/features/questions/presentation/question_audit_view.dart';
import 'package:furnace/features/questions/presentation/question_developer_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_source_edit_dialog.dart';
import 'package:furnace/features/questions/presentation/question_title_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const String _stemMarkdown =
    '15．为研究某疾病与超声波检查结果的关系，从做过超声波检查的人群中随机调查了1000人，得到如下列联表：\n\n'
    '| 超声波检查结果组别 | 正常 | 不正常 | 合计 |\n'
    '| --- | --- | --- | --- |\n'
    '| 患该疾病 | 20 | 180 | 200 |\n'
    '| 未患该疾病 | 780 | 20 | 800 |\n'
    '| 合计 | 800 | 200 | 1000 |';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('学生页：只有学生内容，开发字段与开发动作都不出现', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    // 视口拉高：这一条只看“该出现/不该出现什么”，不测尺寸。
    await _pumpDetail(
      tester,
      database,
      question.id,
      size: const Size(1280, 2600),
    );
    await _waitForText(tester, '列联表独立性检验');

    // 题名 / 题号 / 题干 / 选项这些学生内容在。
    expect(find.text('列联表独立性检验'), findsOneWidget);
    expect(find.text('TR-00001'), findsOneWidget);
    expect(find.text(_zh.questionDetailSelfTest), findsOneWidget);
    expect(find.text(_zh.questionDetailSolveButton), findsOneWidget);

    // 来源行只留「学科 · 年份 · 地区」，开发字段一个都不出现。
    expect(find.text('数学 · 2025 年 · 全国一卷'), findsOneWidget);
    for (final forbidden in <String>[
      'content_package',
      '已结构化',
      '高考真题',
      'structured',
      'ai_quality',
      '0.42',
      question.id,
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: '学生页不该显示开发字段：$forbidden',
      );
    }

    // 开发动作不在学生页。
    for (final forbidden in <String>[
      _zh.questionSourceAdd,
      _zh.questionSourceEdit,
      _zh.questionSourceCopyLink,
      _zh.questionDetailEditSource,
      _zh.questionAuditSectionTitle,
      _zh.questionTitleRename,
    ]) {
      expect(
        find.text(forbidden),
        findsNothing,
        reason: '学生页不该出现开发动作：$forbidden',
      );
    }
    expect(find.byKey(questionTitleEditButtonKey), findsNothing);
    expect(find.byKey(questionSourceEditButtonKey), findsNothing);
    expect(find.byKey(questionSourceCopyButtonKey), findsNothing);
    expect(find.byKey(questionAuditSectionKey), findsNothing);

    // 但开发入口只有一个，且在页底。
    expect(find.byKey(questionDeveloperEntryKey), findsOneWidget);
    expect(find.text(_zh.questionDeveloperEntry), findsOneWidget);
  });

  testWidgets('开发者信息页：开发字段与开发动作都在这里', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id);
    await _waitForText(tester, '列联表独立性检验');
    await _openDeveloper(tester);
    await _waitForText(tester, _zh.questionDeveloperRawTitle);

    // 内部字段回来了。
    expect(find.textContaining(question.id), findsOneWidget);
    expect(find.textContaining('content_package'), findsOneWidget);
    expect(find.textContaining('已结构化'), findsOneWidget);
    expect(find.textContaining(_zh.questionIntakeSourceGaokao), findsOneWidget);

    // 开发动作也回来了。
    expect(find.text(_zh.questionSourceAdd), findsOneWidget);
    expect(find.text(_zh.questionDetailEditSource), findsOneWidget);
    expect(find.byKey(questionTitleEditButtonKey), findsOneWidget);
    expect(find.byKey(questionAuditSectionKey), findsOneWidget);
  });

  testWidgets('1280×720：长题干换行，Markdown 表格有横向滚动，不裁切不溢出',
      (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, size: const Size(1280, 720));
    await _waitForText(tester, '列联表独立性检验');

    // 页面没有溢出异常。
    expect(tester.takeException(), isNull);

    // 1280 宽下长题干一行放得下；关键是它没有超出视口（不裁切）。
    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('得到如下列联表'),
    );
    expect(paragraph, findsOneWidget);
    expect(tester.getSize(paragraph).width, lessThanOrEqualTo(1248));

    // 表格自带横向滚动（gpt_markdown TableOverflow.scroll）：表格不能被裁切。
    final horizontalScrollables = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollables, findsWidgets);
    final tableScroll = tester.getSize(horizontalScrollables.first);
    expect(tableScroll.width, lessThanOrEqualTo(1280));
  });

  testWidgets('窄视口 640×720：长题干照常换行，表格仍可横向滚动', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, size: const Size(640, 720));
    await _waitForText(tester, '列联表独立性检验');

    expect(tester.takeException(), isNull);

    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('得到如下列联表'),
    );
    expect(paragraph, findsOneWidget);
    expect(tester.getSize(paragraph).height, greaterThan(30));
    expect(tester.getSize(paragraph).width, lessThanOrEqualTo(640));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsWidgets,
    );
  });
}

AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

/// 一道「看起来像开发数据」的题：来源分级 gaokao、状态 structured、
/// origin content_package、有 aiQuality、题干是带表格的 Markdown。
Future<Question> _seedQuestion(AppDatabase database) async {
  final result = await QuestionRepository(database).ingest(
    const QuestionDraft(
      stem: _stemMarkdown,
      answer: '(1) 9/10\n(2) 有关',
      solution: '先读列联表，再代 χ² 公式。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      sourceLabel: '2025 高考全国一卷',
      year: 2025,
      region: '全国一卷',
      textFormat: 'markdown',
      origin: 'content_package',
      state: 'structured',
      aiQuality: 0.42,
      aiQualityNote: '来源等级高、题干完整',
      difficulty: 5,
      options: <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: '有关', isCorrect: true),
        QuestionOptionDraft(label: 'B', content: '无关'),
        QuestionOptionDraft(label: 'C', content: '无法判断'),
        QuestionOptionDraft(label: 'D', content: '以上都不对'),
      ],
    ),
  );
  // ingest 会给一个顺序题号；这里固定成 1，测试文案才好断言。
  await (database.update(database.questions)
        ..where((row) => row.id.equals(result.question.id)))
      .write(const QuestionsCompanion(
        serialNo: Value<int?>(1),
        title: Value<String>('列联表独立性检验'),
      ));
  return (await QuestionRepository(database).byId(result.question.id))!;
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  Size size = const Size(1280, 720),
}) async {
  tester.view.physicalSize = size;
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
        questionAuditReportProvider.overrideWith(
          (ref) async => const QuestionAuditReport(findings: []),
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
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
}

Future<void> _openDeveloper(WidgetTester tester) async {
  final entry = find.byKey(questionDeveloperEntryKey);
  // 入口在 ListView 最底部：视口只有 720 高时先滚到它。
  await tester.scrollUntilVisible(
    entry,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这段文字：$text');
}
