/// 题库包「导出范围」筛选的纯逻辑与对话框契约：
/// 题号校验、条件组装（空集=不约束）、取消返回 null、勾选与输入原样带回。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
import 'package:furnace/features/settings/presentation/question_pack_export_filter_dialog.dart';
import 'package:furnace/features/settings/presentation/question_pack_tag_path_picker.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;
  late AppDatabase db;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// One tag row, plus [questions] pretend question links on it.
  Future<void> seedTag(String id, String path, {int questions = 0}) async {
    await db.into(db.tags).insert(TagsCompanion.insert(
          id: id,
          name: path,
          path: Value(path),
          createdAt: 0,
          updatedAt: 0,
        ));
    for (var index = 0; index < questions; index++) {
      await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
            id: 'obj-$id-$index',
            tagId: id,
            objectType: 'question',
            objectId: 'question-$id-$index',
            createdAt: 0,
          ));
    }
  }

  group('questionPackSerialRangeIssue', () {
    test('两端留空/未填都算不限', () {
      expect(
        questionPackSerialRangeIssue(null, null),
        QuestionPackSerialRangeIssue.none,
      );
      expect(
        questionPackSerialRangeIssue('', ''),
        QuestionPackSerialRangeIssue.none,
      );
      expect(
        questionPackSerialRangeIssue('  ', null),
        QuestionPackSerialRangeIssue.none,
      );
    });

    test('纯数字合法，前导零由 normalizeSerialBound 归一', () {
      expect(
        questionPackSerialRangeIssue('0012', '30'),
        QuestionPackSerialRangeIssue.none,
      );
      expect(
        questionPackSerialRangeIssue('5', '5'),
        QuestionPackSerialRangeIssue.none,
      );
      expect(
        questionPackSerialRangeIssue('0', '1'),
        QuestionPackSerialRangeIssue.none,
      );
    });

    test('起始或结束不是纯数字时报对应错误', () {
      expect(
        questionPackSerialRangeIssue('abc', null),
        QuestionPackSerialRangeIssue.invalidFrom,
      );
      expect(
        questionPackSerialRangeIssue('12a', '30'),
        QuestionPackSerialRangeIssue.invalidFrom,
      );
      expect(
        questionPackSerialRangeIssue(null, 'x'),
        QuestionPackSerialRangeIssue.invalidTo,
      );
      expect(
        questionPackSerialRangeIssue('1', '-3'),
        QuestionPackSerialRangeIssue.invalidTo,
      );
    });

    test('两端合法但起始大于结束报反向', () {
      expect(
        questionPackSerialRangeIssue('9', '3'),
        QuestionPackSerialRangeIssue.reversed,
      );
      expect(
        questionPackSerialRangeIssue('0010', '9'),
        QuestionPackSerialRangeIssue.reversed,
      );
    });
  });

  group('questionPackSelectionFromFilter', () {
    test('默认全不选=全部导出', () {
      final QuestionPackSelection selection = questionPackSelectionFromFilter();
      expect(selection.isEmpty, isTrue);
      expect(selection.subjectKeys, isEmpty);
      expect(selection.sourceLevels, isEmpty);
      expect(selection.serialFrom, isNull);
      expect(selection.serialTo, isNull);
      expect(selection.hasSerialRange, isFalse);
    });

    test('集合与题号原样组装，题号归一', () {
      final QuestionPackSelection selection = questionPackSelectionFromFilter(
        subjectKeys: <String>{'math', 'physics'},
        sourceLevels: <String>{'gaokao'},
        serialFrom: '0012',
        serialTo: ' 30 ',
      );
      expect(
        selection.subjectKeys,
        unorderedEquals(<String>{'math', 'physics'}),
      );
      expect(selection.sourceLevels, unorderedEquals(<String>{'gaokao'}));
      expect(selection.serialFrom, 12);
      expect(selection.serialTo, 30);
      expect(selection.hasSerialRange, isTrue);
      expect(selection.isEmpty, isFalse);
    });

    test('非法题号按不限处理（对话框已在 UI 层拦截）', () {
      final QuestionPackSelection selection = questionPackSelectionFromFilter(
        serialFrom: 'abc',
        serialTo: '',
      );
      expect(selection.serialFrom, isNull);
      expect(selection.serialTo, isNull);
      expect(selection.hasSerialRange, isFalse);
    });

    test('返回的集合不可变，避免调用方后续改动影响 service', () {
      final QuestionPackSelection selection = questionPackSelectionFromFilter(
        subjectKeys: <String>{'math'},
        sourceLevels: <String>{'gaokao'},
      );
      expect(
        () => selection.subjectKeys.add('chemistry'),
        throwsUnsupportedError,
      );
      expect(
        () => selection.sourceLevels.add('school'),
        throwsUnsupportedError,
      );
    });

    test('标签路径原样组装并归一（trim/丢空/去重/不可变）', () {
      final QuestionPackSelection selection = questionPackSelectionFromFilter(
        tagPaths: <String>{' 数学/函数 ', '数学/函数', '', '  '},
      );
      expect(selection.tagPaths, unorderedEquals(<String>{'数学/函数'}));
      expect(selection.isEmpty, isFalse);
      expect(
        () => selection.tagPaths.add('数学/数列'),
        throwsUnsupportedError,
      );
    });
  });

  test('来源档位候选覆盖六档且顺序稳定', () {
    expect(questionPackFilterSourceLevels, hasLength(6));
    expect(questionPackFilterSourceLevels.first, 'gaokao');
    expect(
      questionPackFilterSourceLevels,
      containsAll(<String>[
        'gaokao',
        'provincial_diagnostic',
        'elite_school',
        'school',
        'personal',
        'unknown',
      ]),
    );
  });

  group('QuestionPackExportFilterDialog', () {
    Future<QuestionPackSelection?> Function() pumpDialog(WidgetTester tester) {
      QuestionPackSelection? result;
      var opened = false;
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      return () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              appDatabaseProvider.overrideWithValue(db),
            ],
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<QuestionPackSelection>(
                        context: context,
                        builder: (_) => const QuestionPackExportFilterDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        if (!opened) {
          opened = true;
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        }
        return result;
      };
    }

    testWidgets('默认点导出返回空条件', (tester) async {
      final read = pumpDialog(tester);
      await read();
      await tester.tap(
        find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
      );
      await tester.pumpAndSettle();
      final QuestionPackSelection? result = await read();
      expect(result, isNotNull);
      expect(result!.isEmpty, isTrue);
    });

    testWidgets('取消返回 null', (tester) async {
      final read = pumpDialog(tester);
      await read();
      await tester.tap(find.widgetWithText(TextButton, zh.commonCancel));
      await tester.pumpAndSettle();
      final QuestionPackSelection? result = await read();
      expect(result, isNull);
    });

    testWidgets('勾选学科/来源并填题号后原样带回', (tester) async {
      final read = pumpDialog(tester);
      await read();
      await tester.tap(find.widgetWithText(FilterChip, '数学'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialFrom),
        '7',
      );
      await tester.enterText(
        find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialTo),
        '21',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
      );
      await tester.pumpAndSettle();
      final QuestionPackSelection? result = await read();
      expect(result, isNotNull);
      expect(result!.subjectKeys, unorderedEquals(<String>{'math'}));
      expect(result.serialFrom, 7);
      expect(result.serialTo, 21);
    });

    testWidgets('标签路径：选择器确认后按钮显示计数并随导出带回', (tester) async {
      await seedTag('t-math', '数学', questions: 2);
      await seedTag('t-english', '英语');
      final read = pumpDialog(tester);
      await read();

      await tester.tap(
        find.byKey(const ValueKey<String>('question-pack-filter-tag-paths')),
      );
      await tester.pumpAndSettle();

      expect(find.text('数学 · 2 道'), findsOneWidget);
      await tester.tap(find.text('数学 · 2 道'));
      await tester.pump();
      await tester.tap(find.byKey(questionPackTagPickerConfirmKey));
      await tester.pumpAndSettle();

      expect(
        find.text(zh.settingsQuestionPackFilterTagsSelected(1)),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
      );
      await tester.pumpAndSettle();
      final QuestionPackSelection? result = await read();
      expect(result, isNotNull);
      expect(result!.tagPaths, unorderedEquals(<String>{'数学'}));
    });

    testWidgets('标签路径：取消选择器保留原来的选择', (tester) async {
      await seedTag('t-math', '数学');
      final read = pumpDialog(tester);
      await read();

      await tester.tap(
        find.byKey(const ValueKey<String>('question-pack-filter-tag-paths')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(questionPackTagPickerCancelKey));
      await tester.pumpAndSettle();

      expect(find.text(zh.settingsQuestionPackFilterTagSelect), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
      );
      await tester.pumpAndSettle();
      final QuestionPackSelection? result = await read();
      expect(result, isNotNull);
      expect(result!.tagPaths, isEmpty);
    });
  });
}
