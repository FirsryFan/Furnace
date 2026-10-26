/// 题库包导出「标签路径」筛选：标签行到选项的映射（纯逻辑），以及
/// 二级选择对话框的契约（空库提示、搜索、勾选、取消）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/package/question_pack_tag_options.dart';
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

  const Tag noPath = Tag(
    id: 't-no-path',
    name: '无路径',
    createdAt: 3,
    updatedAt: 3,
  );

  group('questionPackTagPathOptionsFromTags', () {
    test('path 为空时退化为 name，空名字丢弃，同路径题数累加', () {
      const List<Tag> tags = <Tag>[
        Tag(
          id: 't-math-a',
          name: '旧名',
          path: '文化课/数学',
          createdAt: 1,
          updatedAt: 1,
        ),
        Tag(
          id: 't-math-b',
          name: '数学',
          path: '文化课/数学',
          createdAt: 2,
          updatedAt: 2,
        ),
        noPath,
        Tag(
            id: 't-blank',
            name: '   ',
            path: '   ',
            createdAt: 4,
            updatedAt: 4),
      ];
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptionsFromTags(
        tags: tags,
        questionCountByTagId: const <String, int>{
          't-math-a': 2,
          't-math-b': 1,
          't-no-path': 5,
          't-blank': 9,
        },
      );

      expect(options.map((o) => o.path).toList(), <String>['无路径', '文化课/数学']);
      expect(options.first.questionCount, 5);
      expect(options[1].questionCount, 3);
    });

    test('负数题数按 0 计', () {
      const List<Tag> tags = <Tag>[
        Tag(id: 't-1', name: '数学', path: '数学', createdAt: 1, updatedAt: 1),
      ];
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptionsFromTags(
        tags: tags,
        questionCountByTagId: const <String, int>{'t-1': -3},
      );
      expect(options.single.questionCount, 0);
      expect(options.single.selected, isFalse);
    });

    test('没有标签时返回空列表', () {
      expect(
        questionPackTagPathOptionsFromTags(tags: const <Tag>[]),
        isEmpty,
      );
    });

    test('截断上限透传，返回的列表不可变', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptionsFromTags(
        tags: const <Tag>[
          Tag(id: 't-1', name: 'A', path: 'A', createdAt: 1, updatedAt: 1),
          Tag(id: 't-2', name: 'B', path: 'B', createdAt: 2, updatedAt: 2),
        ],
        questionCountByTagId: const <String, int>{'t-1': 1, 't-2': 2},
        maxOptionCount: 1,
      );
      expect(options.map((o) => o.path).toList(), <String>['B']);
      expect(
        () => options.add(
          const QuestionPackTagPathOption(path: 'C', questionCount: 1),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('QuestionPackTagPathPickerDialog', () {
    Future<void> seedTag(
      String id,
      String path, {
      int questions = 0,
      String? parentId,
      String? usageCodes,
    }) async {
      await db.into(db.tags).insert(TagsCompanion.insert(
            id: id,
            name: path,
            path: Value(path),
            parentId: Value(parentId),
            usageCodes: Value(usageCodes),
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

    Future<Set<String>?> Function() pumpPicker(
      WidgetTester tester, {
      Set<String> initialSelection = const <String>{},
    }) {
      Set<String>? result;
      var opened = false;
      tester.view.physicalSize = const Size(1000, 1800);
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
                      result = await showDialog<Set<String>>(
                        context: context,
                        builder: (_) => QuestionPackTagPathPickerDialog(
                          initialSelection: initialSelection,
                        ),
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

    testWidgets('空库：显示「先建标签」提示', (tester) async {
      final read = pumpPicker(tester);
      await read();

      expect(
        find.text(zh.settingsQuestionPackTagPickerEmpty),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('选项显示路径与题数，按题数降序', (tester) async {
      await seedTag('t-math', '数学', questions: 2);
      await seedTag('t-english', '英语');
      final read = pumpPicker(tester);
      await read();

      expect(find.text('数学 · 2 道'), findsOneWidget);
      expect(find.text('英语 · 0 道'), findsOneWidget);
      final List<String> titles = <String>[
        for (final CheckboxListTile tile in tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        ))
          (tile.title! as Text).data!,
      ];
      expect(titles, <String>['数学 · 2 道', '英语 · 0 道']);
    });

    testWidgets('勾选后确认返回选中的路径', (tester) async {
      await seedTag('t-math', '数学', questions: 2);
      final read = pumpPicker(tester);
      await read();

      await tester.tap(find.text('数学 · 2 道'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, zh.commonConfirm));
      await tester.pumpAndSettle();

      expect(await read(), unorderedEquals(<String>{'数学'}));
    });

    testWidgets('取消返回 null', (tester) async {
      await seedTag('t-math', '数学');
      final read = pumpPicker(tester);
      await read();

      await tester.tap(find.widgetWithText(TextButton, zh.commonCancel));
      await tester.pumpAndSettle();

      expect(await read(), isNull);
    });

    testWidgets('搜索只保留匹配项，无匹配时提示', (tester) async {
      await seedTag('t-math', '数学', questions: 2);
      await seedTag('t-english', '英语');
      final read = pumpPicker(tester);
      await read();

      await tester.enterText(find.byType(TextField), '英');
      await tester.pump();
      expect(find.text('英语 · 0 道'), findsOneWidget);
      expect(find.text('数学 · 2 道'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(
        find.text(zh.settingsQuestionPackTagPickerNoMatch),
        findsOneWidget,
      );
    });

    testWidgets('初始选中即使已从题库消失也保留且可取消', (tester) async {
      final read = pumpPicker(
        tester,
        initialSelection: const <String>{'已删路径'},
      );
      await read();

      expect(find.text('已删路径 · 0 道'), findsOneWidget);
      final CheckboxListTile tile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(tile.value, isTrue);

      await tester.tap(find.text('已删路径 · 0 道'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, zh.commonConfirm));
      await tester.pumpAndSettle();

      expect(await read(), isEmpty);
    });

    testWidgets('有用途声明时只列「纳入题库」的标签，并说明范围', (tester) async {
      // 时间表那棵树显式声明 time：题库包导出不该再列它（§10 标签边界）。
      await seedTag('t-time', '时间表', usageCodes: 'time');
      await seedTag('t-time-child', '时间表/专注', parentId: 't-time');
      await seedTag('t-question', '题库/物理', usageCodes: 'question');
      final read = pumpPicker(tester);
      await read();

      expect(find.text('题库/物理 · 0 道'), findsOneWidget);
      expect(find.text('时间表 · 0 道'), findsNothing);
      expect(find.text('时间表/专注 · 0 道'), findsNothing);
      expect(
        find.text(zh.tagUsageScopeHintNamed(zh.tagUsageQuestion)),
        findsOneWidget,
      );

      await tester.tap(find.text('题库/物理 · 0 道'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, zh.commonConfirm));
      await tester.pumpAndSettle();
      expect(await read(), unorderedEquals(<String>{'题库/物理'}));
    });

    testWidgets('整棵树没有声明用途时全部列出并给默认提示', (tester) async {
      await seedTag('t-math', '数学');
      await seedTag('t-time', '时间表');
      final read = pumpPicker(tester);
      await read();

      expect(find.text('数学 · 0 道'), findsOneWidget);
      expect(find.text('时间表 · 0 道'), findsOneWidget);
      expect(find.text(zh.tagUsageScopeDefaultHint), findsOneWidget);
      expect(
        find.text(zh.tagUsageScopeHintNamed(zh.tagUsageQuestion)),
        findsNothing,
      );
    });

    testWidgets('整棵树有标签但都只用于别的域时说明用途边界', (tester) async {
      await seedTag('t-time', '时间表', usageCodes: 'time');
      final read = pumpPicker(tester);
      await read();

      expect(
        find.text(zh.tagUsageScopeEmptyNamed(zh.tagUsageQuestion)),
        findsOneWidget,
      );
      expect(find.text('时间表 · 0 道'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    });
  });
}
