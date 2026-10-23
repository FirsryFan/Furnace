/// 题库页筛选条（搜索 + 标签 + 学科）的界面契约。
///
/// 口径：三个条件 AND；搜索命中题号/题名/题干/来源/标签（纯逻辑在
/// `application/question_library_filter.dart`）；标签是子树匹配（勾父路径命中
/// 所有子孙标签）；筛选只作用列表与计数，多选态的已选集合不被清空。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_attempt_repository.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_library_filter_bar.dart';
import 'package:furnace/features/questions/presentation/question_library_tag_filter_dialog.dart';
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

  testWidgets('搜索题号 TR-1 只留下对应题', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '第一道题', serialNo: 1);
    await _seedQuestion(db, id: 'q2', stem: '第二道题', serialNo: 2);
    await _pump(tester, db);

    await _search(tester, 'TR-1');

    expect(find.text('第一道题'), findsOneWidget);
    expect(find.text('第二道题'), findsNothing);
    expect(find.byKey(questionBankFilteredCountKey), findsOneWidget);
  });

  testWidgets('搜索题干片段命中对应题', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '求二次函数的最小值');
    await _seedQuestion(db, id: 'q2', stem: '求小球的加速度');
    await _pump(tester, db);

    await _search(tester, '加速度');

    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(find.text('求二次函数的最小值'), findsNothing);
  });

  testWidgets('无命中时给空态与清除按钮，点清除恢复全量', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '第一道题');
    await _seedQuestion(db, id: 'q2', stem: '第二道题');
    await _pump(tester, db);

    await _search(tester, '没有这道题');
    expect(find.text(zh.questionBankFilterNoMatch), findsOneWidget);
    expect(_row('q1'), findsNothing);
    expect(_row('q2'), findsNothing);

    await tester.tap(find.byKey(questionBankNoMatchClearFilterKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBankFilterNoMatch), findsNothing);
    expect(find.text('第一道题'), findsOneWidget);
    expect(find.text('第二道题'), findsOneWidget);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('筛选条「清除筛选」清空搜索框文字并恢复全量', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '求二次函数的最小值');
    await _seedQuestion(db, id: 'q2', stem: '求小球的加速度');
    await _pump(tester, db);

    await _search(tester, '加速度');
    expect(find.byKey(questionBankFilteredCountKey), findsOneWidget);

    await tester.tap(find.byKey(questionBankClearFilterKey));
    await tester.pumpAndSettle();

    expect(find.text('求二次函数的最小值'), findsOneWidget);
    expect(find.text('求小球的加速度'), findsOneWidget);
    expect(_searchField(tester).controller!.text, isEmpty);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('标签筛选：勾父路径命中其子孙标签的题', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '父路径题');
    await _seedQuestion(db, id: 'q2', stem: '子路径题');
    await _seedQuestion(db, id: 'q3', stem: '英语题');
    await _addTagLink(db, questionId: 'q1', tagId: 't-parent', path: '文化课/学科');
    await _addTagLink(db,
        questionId: 'q2', tagId: 't-child', path: '文化课/学科/数学');
    await _addTagLink(db, questionId: 'q3', tagId: 't-en', path: '文化课/英语');
    await _pump(tester, db);

    await _openTagFilter(tester);
    expect(find.text('文化课/学科'), findsOneWidget);
    await tester.tap(find.text('文化课/学科'));
    await tester.pump();
    await tester.tap(find.byKey(questionLibraryTagFilterConfirmKey));
    await tester.pumpAndSettle();

    expect(find.text('父路径题'), findsOneWidget);
    expect(find.text('子路径题'), findsOneWidget);
    expect(find.text('英语题'), findsNothing);
    expect(find.text(zh.questionBankTagFilterSelected(1)), findsOneWidget);
    expect(find.text(zh.questionBankFilteredCount(2, 3)), findsOneWidget);
  });

  testWidgets('标签筛选：多选两条路径取并集，chips 带完整路径 tooltip', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '父路径题');
    await _seedQuestion(db, id: 'q2', stem: '子路径题');
    await _seedQuestion(db, id: 'q3', stem: '英语题');
    await _addTagLink(db, questionId: 'q1', tagId: 't-parent', path: '文化课/学科');
    await _addTagLink(db,
        questionId: 'q2', tagId: 't-child', path: '文化课/学科/数学');
    await _addTagLink(db, questionId: 'q3', tagId: 't-en', path: '文化课/英语');
    await _pump(tester, db);

    await _openTagFilter(tester);
    await tester.tap(find.text('文化课/学科'));
    await tester.tap(find.text('文化课/英语'));
    await tester.pump();
    await tester.tap(find.byKey(questionLibraryTagFilterConfirmKey));
    await tester.pumpAndSettle();

    expect(find.text('父路径题'), findsOneWidget);
    expect(find.text('子路径题'), findsOneWidget);
    expect(find.text('英语题'), findsOneWidget);
    expect(find.text(zh.questionBankTagFilterSelected(2)), findsOneWidget);
    expect(
      find.byKey(ValueKey(questionBankTagChipKeyFor('文化课/学科'))),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey(questionBankTagChipKeyFor('文化课/英语'))),
      findsOneWidget,
    );
    expect(find.byTooltip('文化课/学科'), findsOneWidget);
    expect(find.byTooltip('文化课/英语'), findsOneWidget);
  });

  testWidgets('点已选标签 chip 的删除图标移除该标签筛选', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '已挂标签题');
    await _seedQuestion(db, id: 'q2', stem: '没挂标签题');
    await _addTagLink(db, questionId: 'q1', tagId: 't1', path: '文化课/数学');
    await _pump(tester, db);

    await _openTagFilter(tester);
    await tester.tap(find.text('文化课/数学'));
    await tester.pump();
    await tester.tap(find.byKey(questionLibraryTagFilterConfirmKey));
    await tester.pumpAndSettle();
    expect(find.text('没挂标签题'), findsNothing);

    final chip = find.byKey(
      ValueKey(questionBankTagChipKeyFor('文化课/数学')),
    );
    expect(chip, findsOneWidget);
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();

    expect(chip, findsNothing);
    expect(find.text('没挂标签题'), findsOneWidget);
    expect(find.text(zh.questionBankTagFilterTitle), findsOneWidget);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('标签对话框「清除标签」清掉标签筛选', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '已挂标签题');
    await _seedQuestion(db, id: 'q2', stem: '没挂标签题');
    await _addTagLink(db, questionId: 'q1', tagId: 't1', path: '文化课/数学');
    await _pump(tester, db);

    await _openTagFilter(tester);
    await tester.tap(find.text('文化课/数学'));
    await tester.pump();
    await tester.tap(find.byKey(questionLibraryTagFilterConfirmKey));
    await tester.pumpAndSettle();
    expect(find.text('已挂标签题'), findsOneWidget);
    expect(find.text('没挂标签题'), findsNothing);

    await _openTagFilter(tester);
    await tester.tap(find.byKey(questionLibraryTagFilterClearKey));
    await tester.pumpAndSettle();

    expect(find.text('没挂标签题'), findsOneWidget);
    expect(find.text(zh.questionBankTagFilterTitle), findsOneWidget);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('标签对话框可搜索路径', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '代数题');
    await _seedQuestion(db, id: 'q2', stem: '数学题');
    await _addTagLink(db, questionId: 'q1', tagId: 't1', path: '章节/代数');
    await _addTagLink(db, questionId: 'q2', tagId: 't2', path: '文化课/数学');
    await _pump(tester, db);

    await _openTagFilter(tester);
    await tester.enterText(find.byKey(questionLibraryTagFilterSearchKey), '代数');
    await tester.pump();
    expect(find.text('文化课/数学'), findsNothing);
    expect(find.text('章节/代数'), findsOneWidget);

    await tester.tap(find.text('章节/代数'));
    await tester.pump();
    await tester.tap(find.byKey(questionLibraryTagFilterConfirmKey));
    await tester.pumpAndSettle();

    expect(find.text('代数题'), findsOneWidget);
    expect(find.text('数学题'), findsNothing);
  });

  testWidgets('学科 chip 与搜索是 AND 关系', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '数学加速度题', subject: 'math');
    await _seedQuestion(db, id: 'q2', stem: '物理加速度题', subject: 'physics');
    await _pump(tester, db);

    await tester.tap(find.widgetWithText(ChoiceChip, '物理'));
    await tester.pumpAndSettle();
    expect(find.text('物理加速度题'), findsOneWidget);
    expect(find.text('数学加速度题'), findsNothing);

    await _search(tester, '数学');
    expect(find.text(zh.questionBankFilterNoMatch), findsOneWidget);
    expect(find.text(zh.questionBankFilteredCount(0, 2)), findsOneWidget);
  });

  testWidgets('错题徽标：答错过的题显示「错 N 次」，只答对过的不显示', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '错两次的题');
    await _seedQuestion(db, id: 'q2', stem: '只答对过的题');
    await _seedQuestion(db, id: 'q3', stem: '没做过的题');
    await _seedAttempt(db, questionId: 'q1', isCorrect: false, count: 2);
    await _seedAttempt(db, questionId: 'q2', isCorrect: true);
    await _pump(tester, db);

    expect(_wrongBadge('q1'), findsOneWidget);
    expect(find.text(zh.questionBankWrongCount(2)), findsOneWidget);
    expect(_wrongBadge('q2'), findsNothing);
    expect(_wrongBadge('q3'), findsNothing);
  });

  testWidgets('错题本开关：打开后只剩答错过的题，chip 选中且计数行出现', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '错过的题');
    await _seedQuestion(db, id: 'q2', stem: '答对过的题');
    await _seedQuestion(db, id: 'q3', stem: '没做过的题');
    await _seedAttempt(db, questionId: 'q1', isCorrect: false);
    await _seedAttempt(db, questionId: 'q2', isCorrect: true);
    await _pump(tester, db);

    await tester.tap(find.byKey(questionBankWrongOnlyKey));
    await tester.pumpAndSettle();

    expect(find.text('错过的题'), findsOneWidget);
    expect(find.text('答对过的题'), findsNothing);
    expect(find.text('没做过的题'), findsNothing);
    expect(
      tester.widget<FilterChip>(find.byKey(questionBankWrongOnlyKey)).selected,
      isTrue,
    );
    expect(
      tester.widget<Text>(find.byKey(questionBankFilteredCountKey)).data,
      zh.questionBankFilteredCount(1, 3),
    );
    expect(find.byTooltip(zh.questionBankWrongOnlyTooltip), findsOneWidget);
  });

  testWidgets('错题本开关：再点一次取消，全部题目回来', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '错过的题');
    await _seedQuestion(db, id: 'q2', stem: '没做过的题');
    await _seedAttempt(db, questionId: 'q1', isCorrect: false);
    await _pump(tester, db);

    await tester.tap(find.byKey(questionBankWrongOnlyKey));
    await tester.pumpAndSettle();
    expect(_row('q2'), findsNothing);

    await tester.tap(find.byKey(questionBankWrongOnlyKey));
    await tester.pumpAndSettle();

    expect(_row('q1'), findsOneWidget);
    expect(_row('q2'), findsOneWidget);
    expect(
      tester.widget<FilterChip>(find.byKey(questionBankWrongOnlyKey)).selected,
      isFalse,
    );
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('「清除筛选」同时清掉错题本开关', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '错过的题');
    await _seedQuestion(db, id: 'q2', stem: '没做过的题');
    await _seedAttempt(db, questionId: 'q1', isCorrect: false);
    await _pump(tester, db);

    await tester.tap(find.byKey(questionBankWrongOnlyKey));
    await tester.pumpAndSettle();
    expect(_row('q2'), findsNothing);
    expect(find.byKey(questionBankFilteredCountKey), findsOneWidget);

    await tester.tap(find.byKey(questionBankClearFilterKey));
    await tester.pumpAndSettle();

    expect(_row('q1'), findsOneWidget);
    expect(_row('q2'), findsOneWidget);
    expect(
      tester.widget<FilterChip>(find.byKey(questionBankWrongOnlyKey)).selected,
      isFalse,
    );
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('筛选计数显示「已筛出 X / 共 Y 道」', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '二次函数一');
    await _seedQuestion(db, id: 'q2', stem: '二次函数二');
    await _seedQuestion(db, id: 'q3', stem: '立体几何');
    await _pump(tester, db);

    await _search(tester, '二次函数');

    final countText = tester.widget<Text>(
      find.byKey(questionBankFilteredCountKey),
    );
    expect(countText.data, zh.questionBankFilteredCount(2, 3));
  });

  testWidgets('多选态「全选」只选筛出的题', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '函数一', serialNo: 1);
    await _seedQuestion(db, id: 'q2', stem: '函数二', serialNo: 2);
    await _seedQuestion(db, id: 'q3', stem: '几何题', serialNo: 3);
    await _pump(tester, db);

    await _search(tester, '函数');
    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();
    expect(find.text(zh.questionBankSelectedCount(2)), findsOneWidget);

    // 清掉搜索后 q3 出现，但没有被偷偷选中。
    await _search(tester, '');
    expect(find.text(zh.questionBankSelectedCount(2)), findsOneWidget);
  });

  testWidgets('多选态改筛选不清空已选（已选数含被筛掉的题）', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '函数一');
    await _seedQuestion(db, id: 'q2', stem: '函数二');
    await _pump(tester, db);

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();
    expect(find.text(zh.questionBankSelectedCount(2)), findsOneWidget);

    await _search(tester, '函数一');
    expect(find.text(zh.questionBankSelectedCount(2)), findsOneWidget);
    expect(_row('q2'), findsNothing);
  });

  testWidgets('搜索框 × 只清文字并恢复全量', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '函数一');
    await _seedQuestion(db, id: 'q2', stem: '几何题');
    await _pump(tester, db);

    await _search(tester, '函数');
    expect(find.byKey(questionBankSearchClearKey), findsOneWidget);
    await tester.tap(find.byKey(questionBankSearchClearKey));
    await tester.pumpAndSettle();

    expect(find.text('几何题'), findsOneWidget);
    expect(_searchField(tester).controller!.text, isEmpty);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
  });

  testWidgets('题库没有任何标签时对话框给提示，取消不改变筛选', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '无标签题');
    await _pump(tester, db);

    await _openTagFilter(tester);
    expect(find.byKey(questionLibraryTagFilterDialogKey), findsOneWidget);
    expect(find.text(zh.questionBulkTagNoMatch), findsOneWidget);

    await tester.tap(find.text(zh.commonCancel));
    await tester.pumpAndSettle();
    expect(find.byKey(questionLibraryTagFilterDialogKey), findsNothing);
    expect(find.byKey(questionBankFilteredCountKey), findsNothing);
    expect(find.text('无标签题'), findsOneWidget);
  });

  testWidgets('筛选生效时读全库：第 600 题也筛得出来，清掉筛选回到 500 档', (tester) async {
    await _seedManyQuestions(
      db,
      count: 600,
      lastStem: '第六百题：独有标记',
    );
    await _pump(tester, db);

    // 未筛选：只读前 500 题，第 600 题不在列表里，横幅说明只读了 500 题。
    expect(_row('q-0600'), findsNothing);
    expect(find.text(zh.questionBankTruncated(500)), findsOneWidget);

    await _search(tester, '独有标记');

    expect(_row('q-0600'), findsOneWidget);
    final countText = tester.widget<Text>(
      find.byKey(questionBankFilteredCountKey),
    );
    expect(countText.data, zh.questionBankFilteredCount(1, 600));
    // 筛选档读全库，不再显示「只读了前 500 题」的横幅。
    expect(find.text(zh.questionBankTruncated(500)), findsNothing);

    // 清掉筛选：回到 500 档，第 600 题重新藏起来。
    await tester.tap(find.byKey(questionBankClearFilterKey));
    await tester.pumpAndSettle();

    expect(_row('q-0600'), findsNothing);
    expect(find.text(zh.questionBankTruncated(500)), findsOneWidget);
  });

  testWidgets('筛选生效时改名：全库档跟着刷新，列表立刻显示新题名', (tester) async {
    await _seedQuestion(db, id: 'q1', stem: '求二次函数的最小值');
    await _seedQuestion(db, id: 'q2', stem: '求小球的加速度');
    await _pump(tester, db);

    await _search(tester, '二次函数');
    expect(_row('q1'), findsOneWidget);
    expect(_row('q2'), findsNothing);

    await tester.tap(find.byKey(ValueKey(questionBankRowMenuKeyFor('q1'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.questionTitleRename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(questionTitleFieldKey), '二次函数最值题型');
    await tester.tap(find.byKey(questionTitleSaveButtonKey));
    await tester.pumpAndSettle();

    // 筛选仍生效，但列表已经拿到新题名（两档数据源一起失效并重读）。
    expect(find.byKey(questionBankFilteredCountKey), findsOneWidget);
    expect(find.text('二次函数最值题型'), findsOneWidget);
    final row = await (db.select(db.questions)..where((t) => t.id.equals('q1')))
        .getSingle();
    expect(row.title, '二次函数最值题型');
  });
}

Finder _row(String id) => find.byKey(ValueKey(questionBankRowKeyFor(id)));

Finder _wrongBadge(String id) =>
    find.byKey(ValueKey(questionBankWrongBadgeKeyFor(id)));

TextField _searchField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(questionBankSearchKey));

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(questionBankSearchKey), text);
  await tester.pumpAndSettle();
}

Future<void> _openTagFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(questionBankTagFilterKey));
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: db),
        ),
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
  int? serialNo,
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: Value(subject),
          sourceLevel: const Value('gaokao'),
          serialNo: Value(serialNo),
        ),
      );
}

/// 造自测作答记录（错题徽标与错题本筛选的数据来源）。
Future<void> _seedAttempt(
  AppDatabase db, {
  required String questionId,
  required bool isCorrect,
  int count = 1,
}) async {
  final attempts = QuestionAttemptRepository(db);
  for (var index = 0; index < count; index++) {
    await attempts.record(
      questionId: questionId,
      selectedLabels: const <String>['A'],
      isCorrect: isCorrect,
      now: DateTime(2026, 10, 20, 9, index),
    );
  }
}

Future<void> _seedManyQuestions(
  AppDatabase db, {
  required int count,
  String? lastStem,
}) {
  return db.batch((batch) {
    batch.insertAll(db.questions, [
      for (var index = 1; index <= count; index++)
        QuestionsCompanion.insert(
          id: 'q-${index.toString().padLeft(4, '0')}',
          stem:
              index == count ? (lastStem ?? '第$index题：普通题干') : '第$index题：普通题干',
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: const Value(''),
          sourceLevel: const Value('gaokao'),
        ),
    ]);
  });
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
