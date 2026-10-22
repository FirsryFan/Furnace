/// 题库页（顶部目的地）的界面契约：**扫读题名/题号/标签/封面 + 找得到加题入口 + 能改名**。
///
/// 用户反馈（m09439）：题库总览不需要那么多详细信息，题目命名要能自己起或
/// 自动生成，封面图要大一点。这一页因此是「封面大图 + 题名 + 题号/学科/标签」的
/// 行式列表，没有长 intro 卡、也没有卡片底座；改名与批量自动命名走
/// `question_title_dialog.dart`，测试断言行为而不是内部实现。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
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
import 'package:furnace/features/questions/presentation/question_title_dialog.dart';
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
    // 空题库没有可筛的学科，也没有需要自动命名的题。
    expect(find.text(zh.questionBankAllSubjects), findsNothing);
    expect(find.byKey(questionBankAutoNameKey), findsNothing);
    // 空题库也没有可多选的题，多选入口同样不出现。
    expect(find.byKey(questionBankSelectKey), findsNothing);
  });

  testWidgets('有题时列出题名/题干、统计与学科筛选（筛选真的过滤列表）', (tester) async {
    await _seedQuestion(db, id: 'q-math', stem: '求二次函数最小值', subject: 'math');
    await _seedQuestion(db,
        id: 'q-physics', stem: '求小球的加速度', subject: 'physics');

    await _pump(tester, db);

    expect(find.text(zh.questionBankSummary(2, 2)), findsOneWidget);
    // 有题时才有「多选」入口。
    expect(find.byKey(questionBankSelectKey), findsOneWidget);
    // 旧的长 intro 摘要卡已按用户反馈删掉。
    expect(find.text(zh.questionBankIntro), findsNothing);
    expect(find.text('求二次函数最小值'), findsOneWidget);
    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(find.text(zh.questionBankAllSubjects), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '物理'));
    await tester.pumpAndSettle();

    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(find.text('求二次函数最小值'), findsNothing);
  });

  testWidgets('有题名的行优先显示题名；没题名回退题干摘要', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-named',
      stem: '已知函数 f(x)=x^2+2x，求最小值',
      title: '二次函数最值题型',
    );
    await _seedQuestion(db, id: 'q-unnamed', stem: '求小球的加速度');

    await _pump(tester, db);

    expect(find.text('二次函数最值题型'), findsOneWidget);
    // 有题名的行不再用题干摘要占主行。
    expect(find.text('已知函数 f(x)=x^2+2x，求最小值'), findsNothing);
    expect(find.text('求小球的加速度'), findsOneWidget);
  });

  testWidgets('行尾 ⋮ 菜单：改名写库后列表立刻显示新题名', (tester) async {
    await _seedQuestion(db, id: 'q-rename', stem: '求二次函数最小值');

    await _pump(tester, db);
    await tester
        .tap(find.byKey(ValueKey(questionBankRowMenuKeyFor('q-rename'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.questionTitleRename));
    await tester.pumpAndSettle();

    expect(find.byKey(questionTitleFieldKey), findsOneWidget);
    await tester.enterText(find.byKey(questionTitleFieldKey), '二次函数最值题型');
    await tester.tap(find.byKey(questionTitleSaveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('二次函数最值题型'), findsOneWidget);
    final row = await (db.select(db.questions)
          ..where((t) => t.id.equals('q-rename')))
        .getSingle();
    expect(row.title, '二次函数最值题型');
    expect(find.text(zh.questionTitleSaved), findsOneWidget);
  });

  testWidgets('行尾 ⋮ 菜单：自动命名直接按题干写一个题名', (tester) async {
    await _seedQuestion(db, id: 'q-auto', stem: '求二次函数最小值');

    await _pump(tester, db);
    await tester.tap(find.byKey(ValueKey(questionBankRowMenuKeyFor('q-auto'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.questionBankAutoNameMenu));
    await tester.pumpAndSettle();

    final row = await (db.select(db.questions)
          ..where((t) => t.id.equals('q-auto')))
        .getSingle();
    expect(row.title, isNotNull);
    expect(row.title!.trim(), isNotEmpty);
    expect(find.text(zh.questionTitleAutoNamed(row.title!)), findsOneWidget);
  });

  testWidgets('顶部按钮批量自动命名只看没题名的题，确认后一次写库', (tester) async {
    await _seedQuestion(db, id: 'q-a', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-b', stem: '求小球的加速度');

    await _pump(tester, db);
    expect(find.byKey(questionBankAutoNameKey), findsOneWidget);

    await tester.tap(find.byKey(questionBankAutoNameKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.questionBankAutoNameDialogTitle(2)), findsOneWidget);
    await tester.tap(find.text(zh.questionBankAutoNameStart));
    await tester.pumpAndSettle();

    final rows = await db.select(db.questions).get();
    expect(rows, hasLength(2));
    expect(rows.every((row) => (row.title ?? '').trim().isNotEmpty), isTrue);
    expect(find.text(zh.questionBankAutoNameDone(2)), findsOneWidget);
  });

  testWidgets('行尾 ⋮ 菜单：复制题号到剪贴板', (tester) async {
    await _seedQuestion(db, id: 'q-copy', stem: '求二次函数最小值', serialNo: 7);

    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, db);
    await tester.tap(find.byKey(ValueKey(questionBankRowMenuKeyFor('q-copy'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.questionBankCopySerial));
    await tester.pump(const Duration(milliseconds: 300));

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect(
      (copies.single.arguments as Map<Object?, Object?>)['text'],
      'TR-00007',
    );
  });

  testWidgets('题库行：题号 + 题名，有配图时给 128×96 封面大图', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-7',
      stem: '求二次函数最小值',
      subject: 'math',
      serialNo: 7,
    );
    final mediaStore = FakeQuestionMediaStore(database: db);
    final cover = mediaStore.seed(
      questionId: 'q-7',
      fileName: 'cover.png',
      bytes: tinyPngBytes,
    );
    // 题库总览读的是 attachments 表（不是 store 的内存清单）：两边的 relPath
    // 必须一致，界面才能把字节读出来。
    await _addAttachment(
      db,
      id: 'att-cover',
      questionId: 'q-7',
      relPath: cover.relPath,
    );

    await _pump(tester, db, mediaStore: mediaStore);

    expect(find.textContaining('TR-00007'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final size = tester.getSize(find.byType(Image));
    expect(size.width, greaterThanOrEqualTo(96));
    expect(size.height, greaterThanOrEqualTo(96));
  });

  testWidgets('没编号的老题：题号位置显示占位而不是空白', (tester) async {
    await _seedQuestion(db, id: 'q-old', stem: '老题一道');

    await _pump(tester, db);

    expect(find.textContaining(zh.questionSerialUnnumbered), findsOneWidget);
  });

  testWidgets('标签只显示叶子名，超过三个折叠成 +N', (tester) async {
    await _seedQuestion(db, id: 'q-tags', stem: '标签很多的一道题');
    await _addTagLink(db, questionId: 'q-tags', tagId: 't1', path: '文化课/学科/数学');
    await _addTagLink(db, questionId: 'q-tags', tagId: 't2', path: '文化课/学科/物理');
    await _addTagLink(db, questionId: 'q-tags', tagId: 't3', path: '章节/代数');
    await _addTagLink(db, questionId: 'q-tags', tagId: 't4', path: '章节/几何');

    await _pump(tester, db);

    expect(find.text('数学'), findsOneWidget);
    expect(find.text('物理'), findsOneWidget);
    expect(find.text('代数'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('几何'), findsNothing);
    expect(find.text('文化课/学科/数学'), findsNothing);
  });

  testWidgets('行不套卡片底座，整页没有 Card', (tester) async {
    await _seedQuestion(db, id: 'q-flat', stem: '铺在背景上的题');

    await _pump(tester, db);

    expect(find.byType(Card), findsNothing);
    expect(find.text(zh.questionBankIntro), findsNothing);
  });

  testWidgets('点一行进题目详情页', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值', subject: 'math');

    await _pump(tester, db);
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
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
    final labels = <String>[
      for (final destination in destinations) destination.label
    ];
    expect(labels, contains(zh.navQuestions));
    expect(
      labels.indexOf(zh.navQuestions),
      labels.indexOf(zh.navAnki) + 1,
    );
    // 没有配 AI key 时：标签、Thread、Time、闪存卡、题库、知识库、设置。
    expect(destinations, hasLength(7));
  });
}

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
  String? title,
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
          title: Value(title),
        ),
      );
}

Future<void> _addAttachment(
  AppDatabase db, {
  required String id,
  required String questionId,
  required String relPath,
  String role = 'stem',
}) {
  return db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          id: id,
          ownerType: 'question',
          ownerId: questionId,
          relPath: relPath,
          mime: const Value('image/png'),
          sortOrder: const Value(0),
          role: Value(role),
          createdAt: _ts,
        ),
      );
}

Future<void> _addTagLink(
  AppDatabase db, {
  required String questionId,
  required String tagId,
  required String path,
}) async {
  await db.into(db.tags).insert(
        TagsCompanion.insert(
          id: tagId,
          name: path.split('/').last,
          path: Value(path),
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$questionId',
          tagId: tagId,
          objectType: 'question',
          objectId: questionId,
          createdAt: _ts,
        ),
      );
}
