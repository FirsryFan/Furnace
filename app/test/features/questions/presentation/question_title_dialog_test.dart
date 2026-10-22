/// 题目命名对话框：纯函数（单行/批量建议题名）与对话框行为（保存/自动生成/
/// 非法长度/清除/取消）的契约。
///
/// 改名是题库列表与题目详情页共用的入口，两个页面都不自己写库：对话框负责
/// `setQuestionTitle` + invalidate；测试直接查库断言「真的写进去了」。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';
import 'package:furnace/features/questions/presentation/question_title_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

const int _ts = 1700000000000;

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  QuestionLibraryEntry entry(
    String id, {
    String? title,
    String stem = '已知函数 f(x)=x^2+2x，求最小值',
  }) =>
      QuestionLibraryEntry(
        questionId: id,
        serialNo: 1,
        title: title,
        stem: stem,
        subjectKey: 'math',
        sourceLevel: 'gaokao',
        sourceLabel: '',
      );

  group('纯函数', () {
    test('单行自动命名给出非空且不超长的题名', () {
      final title = suggestQuestionTitleForEntry(entry('q1'));

      expect(title, isNotNull);
      expect(title!.trim(), isNotEmpty);
      expect(title.length, lessThanOrEqualTo(80));
    });

    test('批量自动命名只补没题名的行，生成结果互不重复', () {
      final titles = suggestBulkQuestionTitles(<QuestionLibraryEntry>[
        entry('q1'),
        entry('q2'),
        entry('q3', title: '已有题名'),
      ]);

      expect(titles.keys, unorderedEquals(<String>['q1', 'q2']));
      expect(titles['q1']!.trim(), isNotEmpty);
      expect(titles['q1'], isNot(titles['q2']));
    });

    test('全部已有题名时不生成任何建议', () {
      final titles = suggestBulkQuestionTitles(<QuestionLibraryEntry>[
        entry('q1', title: '甲'),
        entry('q2', title: '乙'),
      ]);

      expect(titles, isEmpty);
    });
  });

  group('对话框', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('保存把题名写进库，并提示已保存', (tester) async {
      await _seedQuestion(db, 'q1');
      await _open(tester, db, questionId: 'q1');

      await tester.enterText(find.byKey(questionTitleFieldKey), '二次函数最值题型');
      await tester.tap(find.byKey(questionTitleSaveButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(questionTitleFieldKey), findsNothing);
      expect(await _titleOf(db, 'q1'), '二次函数最值题型');
      expect(find.text(zh.questionTitleSaved), findsOneWidget);
    });

    testWidgets('自动生成填满输入框，保存写库', (tester) async {
      await _seedQuestion(db, 'q1');
      await _open(tester, db, questionId: 'q1');

      await tester.tap(find.byKey(questionTitleAutoButtonKey));
      await tester.pumpAndSettle();

      expect(find.text(zh.questionTitleAutoFilled), findsOneWidget);
      final controller = tester
          .widget<TextField>(find.byKey(questionTitleFieldKey))
          .controller!;
      expect(controller.text.trim(), isNotEmpty);

      await tester.tap(find.byKey(questionTitleSaveButtonKey));
      await tester.pumpAndSettle();

      expect(await _titleOf(db, 'q1'), controller.text.trim());
    });

    testWidgets('输入超过 80 字被输入框截到 80 字后仍可保存', (tester) async {
      await _seedQuestion(db, 'q1');
      await _open(tester, db, questionId: 'q1');

      final tooLong = List<String>.filled(81, '题').join();
      await tester.enterText(find.byKey(questionTitleFieldKey), tooLong);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byKey(questionTitleFieldKey))
          .controller!;
      expect(controller.text.length, 80);

      await tester.tap(find.byKey(questionTitleSaveButtonKey));
      await tester.pumpAndSettle();

      final saved = await _titleOf(db, 'q1');
      expect(saved, controller.text);
      expect(saved!.length, 80);
    });

    testWidgets('清除题名写回 NULL，并提示已清除', (tester) async {
      await _seedQuestion(db, 'q1', title: '旧题名');
      await _open(tester, db, questionId: 'q1', currentTitle: '旧题名');

      await tester.tap(find.byKey(questionTitleClearButtonKey));
      await tester.pumpAndSettle();

      expect(await _titleOf(db, 'q1'), isNull);
      expect(find.text(zh.questionTitleCleared), findsOneWidget);
    });

    testWidgets('取消不写库', (tester) async {
      await _seedQuestion(db, 'q1');
      await _open(tester, db, questionId: 'q1');

      await tester.enterText(find.byKey(questionTitleFieldKey), '不该保存的名字');
      await tester.tap(find.text(zh.commonCancel));
      await tester.pumpAndSettle();

      expect(find.byKey(questionTitleFieldKey), findsNothing);
      expect(await _titleOf(db, 'q1'), isNull);
    });
  });
}

Future<void> _seedQuestion(AppDatabase db, String id, {String? title}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: '已知函数 f(x)=x^2+2x，求最小值',
          createdAt: _ts,
          updatedAt: _ts,
          title: Value(title),
        ),
      );
}

Future<String?> _titleOf(AppDatabase db, String id) async {
  final row = await (db.select(db.questions)..where((t) => t.id.equals(id)))
      .getSingle();
  return row.title;
}

/// 摆一个只有按钮的宿主页，点按钮打开命名对话框。
Future<void> _open(
  WidgetTester tester,
  AppDatabase db, {
  required String questionId,
  String? currentTitle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showQuestionTitleDialog(
                  context,
                  questionId: questionId,
                  stem: '已知函数 f(x)=x^2+2x，求最小值',
                  currentTitle: currentTitle,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
