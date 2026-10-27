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
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_library_provider.dart';
import 'package:furnace/features/questions/application/question_library_sort.dart';
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

  testWidgets('题库为空时给出可读空态，只留组卷与材料入库两个入口', (tester) async {
    await _pump(tester, db);

    expect(find.text(zh.questionBankEmpty), findsOneWidget);
    expect(find.text(zh.questionBankEmptyHint), findsOneWidget);
    expect(find.text(zh.questionPaperTitle), findsOneWidget);
    expect(find.text(zh.materialIntakeTitle), findsOneWidget);
    // 收题/拍照整理改为内置 agent 收题（create_questions 工具），题库页不再有
    // 手动收题入口。
    expect(find.text(zh.questionIntakeTitle), findsNothing);
    expect(find.text(zh.handwritingQueueTitle), findsNothing);
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

  testWidgets('整卡截图题：行里补「整题截图」小标签，标题用正文摘录', (tester) async {
    final placeholders =
        List<String>.generate(12, (index) => '［图${index + 1}］').join();
    await _seedQuestion(
      db,
      id: 'q-snapshot',
      stem: r'已知函数 $f(x)=x^2$，求最小值。' + placeholders,
    );
    await _addAttachment(
      db,
      id: 'att-snapshot',
      questionId: 'q-snapshot',
      relPath: 'media/q-snapshot/page.png',
    );

    await _pump(tester, db);

    expect(find.text(zh.questionBankSnapshotBadge), findsOneWidget);
    expect(find.text(r'已知函数 $f(x)=x^2$，求最小值'), findsOneWidget);
    // 有可读摘录时标题不落到「整题截图 · N 处公式/图」。
    expect(find.textContaining('整题截图 ·'), findsNothing);
    expect(find.textContaining('［图'), findsNothing);
  });

  testWidgets('整卡截图题没有可读摘录时：标题回落「整题截图 · N 处公式/图」，不再重复小标签', (tester) async {
    final placeholders =
        List<String>.generate(12, (index) => '［图${index + 1}］').join();
    await _seedQuestion(
      db,
      id: 'q-snapshot-plain',
      stem: '，。$placeholders',
    );
    await _addAttachment(
      db,
      id: 'att-snapshot-plain',
      questionId: 'q-snapshot-plain',
      relPath: 'media/q-snapshot-plain/page.png',
    );

    await _pump(tester, db);

    expect(find.text('整题截图 · 12 处公式/图'), findsOneWidget);
    // 标题里已有「整题截图」，同一行不再重复小标签。
    expect(find.text(zh.questionBankSnapshotBadge), findsNothing);
  });

  testWidgets('普通题（1 张图 1 处占位）不算整卡快照，不显示小标签', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-inline',
      stem: '如图所示，求加速度。［图1］',
    );
    await _addAttachment(
      db,
      id: 'att-inline',
      questionId: 'q-inline',
      relPath: 'media/q-inline/page.png',
    );

    await _pump(tester, db);

    expect(find.text(zh.questionBankSnapshotBadge), findsNothing);
    expect(find.textContaining('整题截图'), findsNothing);
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

  testWidgets('有自测记录时顶部多一行「自测 N 次 · 答对 M 次（P%）」', (tester) async {
    await _seedQuestion(db, id: 'q-attempts', stem: '求二次函数最小值');
    await _addAttempt(db,
        id: 'qa-1', questionId: 'q-attempts', isCorrect: true);
    await _addAttempt(db,
        id: 'qa-2', questionId: 'q-attempts', isCorrect: false);
    await _addAttempt(db,
        id: 'qa-3', questionId: 'q-attempts', isCorrect: true);

    await _pump(tester, db);

    expect(find.byKey(questionBankAttemptStatsKey), findsOneWidget);
    // 3 次里答对 2 次 → 67%（四舍五入）。
    expect(find.text(zh.questionBankAttemptStats(3, 2, 67)), findsOneWidget);
    // 原有的题数统计行还在。
    expect(find.text(zh.questionBankSummary(1, 0)), findsOneWidget);
  });

  testWidgets('全库 0 条作答记录时「自测统计」行不渲染（不占位）', (tester) async {
    await _seedQuestion(db, id: 'q-no-attempts', stem: '求小球的加速度');

    await _pump(tester, db);

    expect(find.byKey(questionBankAttemptStatsKey), findsNothing);
    expect(find.textContaining('自测 '), findsNothing);
  });

  testWidgets('1 对 1 错时百分比是 50%', (tester) async {
    await _seedQuestion(db, id: 'q-half', stem: '已知函数 f(x)=x^2，求最小值');
    await _addAttempt(db, id: 'qa-ok', questionId: 'q-half', isCorrect: true);
    await _addAttempt(db, id: 'qa-no', questionId: 'q-half', isCorrect: false);

    await _pump(tester, db);

    expect(find.text(zh.questionBankAttemptStats(2, 1, 50)), findsOneWidget);
  });

  group('排序菜单', () {
    testWidgets('默认「最新」：按读表顺序显示，不读全库档', (tester) async {
      final overview = _snapshotOf([
        _entry('q-new-c', serialNo: 3, title: '最新题C'),
        _entry('q-new-a', serialNo: 1, title: '最新题A'),
        _entry('q-new-b', serialNo: 2, title: '最新题B'),
      ]);
      final full = _snapshotOf([
        _entry('q-only-full', serialNo: 9, title: '全库独有题'),
      ]);

      await _pumpWithSnapshot(tester, db, overview: overview, full: full);

      expect(find.byKey(questionBankSortMenuKey), findsOneWidget);
      // 默认「最新」= 读表顺序原样，且读的是总览档，不出现全库档独有题。
      expect(find.text('全库独有题'), findsNothing);
      expect(_rowTop(tester, 'q-new-c'), lessThan(_rowTop(tester, 'q-new-a')));
      expect(_rowTop(tester, 'q-new-a'), lessThan(_rowTop(tester, 'q-new-b')));

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      expect(find.text(zh.questionLibrarySortNewest), findsOneWidget);
      expect(find.text(zh.questionLibrarySortSerial), findsOneWidget);
      expect(find.text(zh.questionLibrarySortWrongFirst), findsOneWidget);
    });

    testWidgets('选「题号」：按题号升序，并改读全库档', (tester) async {
      final overview = _snapshotOf([
        _entry('q-ov-c', serialNo: 3, title: '总览三'),
        _entry('q-ov-a', serialNo: 1, title: '总览一'),
      ]);
      final full = _snapshotOf([
        _entry('q-full-5', serialNo: 5, title: '全库五'),
        _entry('q-full-2', serialNo: 2, title: '全库二'),
        _entry('q-full-1', serialNo: 1, title: '全库一'),
      ]);

      await _pumpWithSnapshot(tester, db, overview: overview, full: full);
      expect(find.text('总览三'), findsOneWidget);

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(questionBankSortMenuItemKey(QuestionLibrarySort.serial)),
      );
      await tester.pumpAndSettle();

      // 排序不是「最新」时必须改读全库档：总览档数据消失，全库独有题出现。
      expect(find.text('总览三'), findsNothing);
      expect(find.text('全库一'), findsOneWidget);
      expect(
          _rowTop(tester, 'q-full-1'), lessThan(_rowTop(tester, 'q-full-2')));
      expect(
          _rowTop(tester, 'q-full-2'), lessThan(_rowTop(tester, 'q-full-5')));
    });

    testWidgets('选「错题优先」：按错题次数降序', (tester) async {
      final full = _snapshotOf([
        _entry('q-w0', serialNo: 1, title: '错0次', wrongAttemptCount: 0),
        _entry('q-w3', serialNo: 2, title: '错3次', wrongAttemptCount: 3),
        _entry('q-w1', serialNo: 3, title: '错1次', wrongAttemptCount: 1),
      ]);

      await _pumpWithSnapshot(tester, db, overview: full, full: full);
      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(questionBankSortMenuItemKey(QuestionLibrarySort.wrongFirst)),
      );
      await tester.pumpAndSettle();

      expect(_rowTop(tester, 'q-w3'), lessThan(_rowTop(tester, 'q-w1')));
      expect(_rowTop(tester, 'q-w1'), lessThan(_rowTop(tester, 'q-w0')));
    });

    testWidgets('菜单里当前排序带勾选标记', (tester) async {
      final snapshot = _snapshotOf([
        _entry('q-One', serialNo: 1, title: '唯一题'),
      ]);
      await _pumpWithSnapshot(tester, db, overview: snapshot, full: snapshot);

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      expect(_sortCheck(QuestionLibrarySort.newest), findsOneWidget);
      expect(_sortCheck(QuestionLibrarySort.serial), findsNothing);

      await tester.tap(
        find.byKey(questionBankSortMenuItemKey(QuestionLibrarySort.wrongFirst)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      expect(_sortCheck(QuestionLibrarySort.wrongFirst), findsOneWidget);
      expect(_sortCheck(QuestionLibrarySort.newest), findsNothing);
    });
  });

  group('排序偏好落盘', () {
    testWidgets('有存档「按题号」：首帧后按题号升序，菜单当前档也是它', (tester) async {
      await SettingsRepository(db).updateQuestionLibrarySortMode('serial');
      // 编号 2/1/3，id 顺序 a/b/c：最新档是 a→b→c，按题号是 b→a→c。
      await _seedQuestion(db, id: 'seed-a', stem: '编号二的题', serialNo: 2);
      await _seedQuestion(db, id: 'seed-b', stem: '编号一的题', serialNo: 1);
      await _seedQuestion(db, id: 'seed-c', stem: '编号三的题', serialNo: 3);

      await _pump(tester, db);

      expect(_rowTop(tester, 'seed-b'), lessThan(_rowTop(tester, 'seed-a')));
      expect(_rowTop(tester, 'seed-a'), lessThan(_rowTop(tester, 'seed-c')));

      final menu = tester.widget<PopupMenuButton<QuestionLibrarySort>>(
        find.byKey(questionBankSortMenuKey),
      );
      expect(menu.initialValue, QuestionLibrarySort.serial);
      // 打开菜单勾选态也落在「题号」。
      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      expect(_sortCheck(QuestionLibrarySort.serial), findsOneWidget);
      expect(_sortCheck(QuestionLibrarySort.newest), findsNothing);
    });

    testWidgets('切换排序写库：选「题号」后库里存 serial', (tester) async {
      await _seedQuestion(db, id: 'switch-1', stem: '切换排序的题');

      await _pump(tester, db);
      final repository = SettingsRepository(db);
      expect(await repository.getQuestionLibrarySortMode(), isNull);

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(questionBankSortMenuItemKey(QuestionLibrarySort.serial)),
      );
      await tester.pumpAndSettle();

      expect(await repository.getQuestionLibrarySortMode(), 'serial');
      final menu = tester.widget<PopupMenuButton<QuestionLibrarySort>>(
        find.byKey(questionBankSortMenuKey),
      );
      expect(menu.initialValue, QuestionLibrarySort.serial);
    });

    testWidgets('库里是未知 code：不崩，回落「最新」', (tester) async {
      await SettingsRepository(db).updateQuestionLibrarySortMode('bogus');
      await _seedQuestion(db, id: 'bad-a', stem: '甲题', serialNo: 2);
      await _seedQuestion(db, id: 'bad-b', stem: '乙题', serialNo: 1);
      await _seedQuestion(db, id: 'bad-c', stem: '丙题', serialNo: 3);

      await _pump(tester, db);

      expect(tester.takeException(), isNull);
      expect(find.text('甲题'), findsOneWidget);
      // 未知值回落出厂「最新」= 读表顺序（id 升序 a→b→c），不是题号序。
      expect(_rowTop(tester, 'bad-a'), lessThan(_rowTop(tester, 'bad-b')));
      expect(_rowTop(tester, 'bad-b'), lessThan(_rowTop(tester, 'bad-c')));

      final menu = tester.widget<PopupMenuButton<QuestionLibrarySort>>(
        find.byKey(questionBankSortMenuKey),
      );
      expect(menu.initialValue, QuestionLibrarySort.newest);
    });

    testWidgets('本次手选优先于落盘值：存档「按题号」后手选「最新」不被覆盖', (tester) async {
      await SettingsRepository(db).updateQuestionLibrarySortMode('serial');
      await _seedQuestion(db, id: 'over-a', stem: '题号二', serialNo: 2);
      await _seedQuestion(db, id: 'over-b', stem: '题号一', serialNo: 1);

      await _pump(tester, db);
      // 首帧后按题号：b(1) 在 a(2) 前。
      expect(_rowTop(tester, 'over-b'), lessThan(_rowTop(tester, 'over-a')));

      await tester.tap(find.byKey(questionBankSortMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(questionBankSortMenuItemKey(QuestionLibrarySort.newest)),
      );
      await tester.pumpAndSettle();

      // 手选「最新」后回到读表顺序 a→b；写库触发的偏好重读（仍是 serial）
      // 不能把本次手选顶掉。
      expect(_rowTop(tester, 'over-a'), lessThan(_rowTop(tester, 'over-b')));
      expect(
          await SettingsRepository(db).getQuestionLibrarySortMode(), 'newest');
    });
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

/// 用假快照替代真实读表：
///
/// [overview] 对应「总览档」（最新排序 + 无筛选时读前 500 题），
/// [full] 对应「全库档」（有筛选或非最新排序时读全库）。页面把哪一档作为
/// `questionLibrarySnapshotProvider` 的入参，就直接决定看到哪组数据——
/// 这样测试能钉住「排序不是最新时必须改读全库」。
Future<void> _pumpWithSnapshot(
  WidgetTester tester,
  AppDatabase db, {
  required QuestionLibrarySnapshot overview,
  required QuestionLibrarySnapshot full,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: db),
        ),
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => LibraryDiagnosis.notRun,
        ),
        questionLibrarySnapshotProvider.overrideWith(
          (ref, bool filterActive) async => filterActive ? full : overview,
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

QuestionLibraryEntry _entry(
  String id, {
  int? serialNo,
  String? title,
  String stem = '',
  String subjectKey = '',
  int wrongAttemptCount = 0,
}) {
  return QuestionLibraryEntry(
    questionId: id,
    serialNo: serialNo,
    title: title,
    stem: stem,
    subjectKey: subjectKey,
    sourceLevel: 'gaokao',
    sourceLabel: '高考',
    wrongAttemptCount: wrongAttemptCount,
  );
}

QuestionLibrarySnapshot _snapshotOf(List<QuestionLibraryEntry> entries) =>
    QuestionLibrarySnapshot(entries: entries, totalCount: entries.length);

/// 行在列表里的 y 坐标——用来钉住排序后的真实展示顺序。
double _rowTop(WidgetTester tester, String questionId) => tester
    .getTopLeft(find.byKey(ValueKey<String>(questionBankRowKeyFor(questionId))))
    .dy;

/// 排序菜单里某一项左侧的勾选标记。
Finder _sortCheck(QuestionLibrarySort sort) => find.descendant(
      of: find.byKey(questionBankSortMenuItemKey(sort)),
      matching: find.byIcon(Icons.check),
    );

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

Future<void> _addAttempt(
  AppDatabase db, {
  required String id,
  required String questionId,
  required bool isCorrect,
}) {
  return db.into(db.questionAttempts).insert(
        QuestionAttemptsCompanion.insert(
          id: id,
          questionId: questionId,
          isCorrect: isCorrect,
          attemptedAt: _ts,
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
