/// 题库页（顶部目的地）的界面契约：**看得到题库 + 找得到加题的四个入口**。
///
/// 用户反馈（m29290）"知识库、新建题目、题库总览找不到入口"之后，这一页是
/// 唯一的题库总览；入口（收题/组卷/拍照整理/材料入库）从设置页搬到这里。
/// 所以断言只围绕两件事：空态是否给出"怎么加题"的说明，有题时是否真的列出
/// 题干、学科筛选是否真的过滤、点一下能不能进详情。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/shell/home_shell.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
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

  testWidgets('题库为空时给出可读空态，四个加题入口都在', (tester) async {
    await _pump(tester, db);

    expect(find.text(zh.questionBankEmpty), findsOneWidget);
    expect(find.text(zh.questionBankEmptyHint), findsOneWidget);
    expect(find.text(zh.questionIntakeTitle), findsOneWidget);
    expect(find.text(zh.questionPaperTitle), findsOneWidget);
    expect(find.text(zh.handwritingQueueTitle), findsOneWidget);
    expect(find.text(zh.materialIntakeTitle), findsOneWidget);
    // 空题库没有可筛的学科。
    expect(find.text(zh.questionBankAllSubjects), findsNothing);
  });

  testWidgets('有题时列出题干、统计与学科筛选（筛选真的过滤列表）', (tester) async {
    await _seedQuestion(db, id: 'q-math', stem: '求二次函数最小值', subject: 'math');
    await _seedQuestion(db,
        id: 'q-physics', stem: '求小球的加速度', subject: 'physics');

    await _pump(tester, db);

    expect(find.text(zh.questionBankSummary(2, 2)), findsOneWidget);
    expect(find.text(zh.questionBankIntro), findsOneWidget);
    expect(find.text('求二次函数最小值'), findsOneWidget);
    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(find.text(zh.questionBankAllSubjects), findsOneWidget);

    await tester.tap(find.text('物理'));
    await tester.pumpAndSettle();

    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(find.text('求二次函数最小值'), findsNothing);
  });

  testWidgets('点一行进题目详情页', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值', subject: 'math');

    await _pump(tester, db);
    await tester.tap(find.text('求二次函数最小值'));
    await tester.pumpAndSettle();

    expect(find.byType(QuestionDetailPage), findsOneWidget);
  });

  testWidgets('组卷入口能进组卷页', (tester) async {
    await _pump(tester, db);
    await tester.tap(find.text(zh.questionPaperTitle));
    await tester.pumpAndSettle();

    expect(find.byType(QuestionPaperPage), findsOneWidget);
  });

  test('shell 的目的地里多了一个「题库」，位置在闪存卡之后', () {
    final destinations = shellDestinations(
      l10n: zh,
      icons: const <String, String>{},
      aiConfigured: false,
    );
    final labels = [for (final destination in destinations) destination.label];
    expect(labels, contains(zh.navQuestions));
    expect(
      labels.indexOf(zh.navQuestions),
      labels.indexOf(zh.navAnki) + 1,
    );
    // 没有配 AI key 时：标签、Thread、Time、闪存卡、题库、知识库、设置。
    expect(destinations, hasLength(7));
  });

  testWidgets('题库行：题号 + 题干，配图给首图缩略图', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-7',
      stem: '求二次函数最小值',
      subject: 'math',
      serialNo: 7,
    );
    final mediaStore = FakeQuestionMediaStore(database: db)
      ..seed(
        questionId: 'q-7',
        fileName: 'cover.png',
        bytes: tinyPngBytes,
      );

    await _pump(tester, db, mediaStore: mediaStore);

    expect(find.textContaining('TR-00007'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('没编号的老题：题号位置显示占位而不是空白', (tester) async {
    await _seedQuestion(db, id: 'q-old', stem: '老题一道');

    await _pump(tester, db);

    expect(find.textContaining(zh.questionSerialUnnumbered), findsOneWidget);
  });
}

/// 浅色/英文都无所谓：断言用的都是 zh 词表。
Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  FakeQuestionMediaStore? mediaStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        questionMediaStoreProvider.overrideWithValue(
          mediaStore ?? FakeQuestionMediaStore(database: db),
        ),
        // 组卷页会读诊断；快层没跑是"未知"，用 notRun 而不是空 map。
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => LibraryDiagnosis.notRun,
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

Future<void> _seedQuestion(
  AppDatabase db, {
  required String id,
  required String stem,
  String subject = '',
  String sourceLevel = 'gaokao',
  int? serialNo,
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: Value(subject),
          sourceLevel: Value(sourceLevel),
          serialNo: Value(serialNo),
        ),
      );
}
