/// 题库页多选态（task-126）：批量打标签 / 导出选中 / 批量删除。
///
/// 多选时 AppBar 只留「已选 N 项 / 全选 / 退出」，底部出现动作条；批量动作都真的
/// 写库（标签看 object_tags、删除看 questions 行），导出走题库包服务与文件选择器
/// 替身。断言行为，不依赖内部实现。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_bulk_tag_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../settings/support/question_pack_fakes.dart';
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

  testWidgets('空题库没有多选入口', (tester) async {
    await _pump(tester, db, packService: FakeQuestionPackService());

    expect(find.text(zh.questionBankEmpty), findsOneWidget);
    expect(find.byKey(questionBankSelectKey), findsNothing);
  });

  testWidgets('进入多选：显示已选数量与三个批量动作，隐藏自动命名和刷新', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-2', stem: '求小球的加速度');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBankSelectedCount(0)), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byKey(questionBankTagSelectedKey), findsOneWidget);
    expect(find.byKey(questionBankExportSelectedKey), findsOneWidget);
    expect(find.byKey(questionBankDeleteSelectedKey), findsOneWidget);
    // 多选态只留已选/全选/退出，普通态的自动命名与刷新不再出现。
    expect(find.byKey(questionBankAutoNameKey), findsNothing);
    expect(find.byKey(questionBankSelectKey), findsNothing);
    // 没勾选时三个动作都不可点。
    expect(_action(tester, questionBankTagSelectedKey).onPressed, isNull);
    expect(_action(tester, questionBankExportSelectedKey).onPressed, isNull);
    expect(_action(tester, questionBankDeleteSelectedKey).onPressed, isNull);
  });

  testWidgets('点行切换勾选，再点取消', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-2', stem: '求小球的加速度');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    expect(find.text(zh.questionBankSelectedCount(1)), findsOneWidget);
    expect(_checkboxOf(tester, 'q-1').value, isTrue);
    expect(_checkboxOf(tester, 'q-2').value, isFalse);

    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    expect(find.text(zh.questionBankSelectedCount(0)), findsOneWidget);
    expect(_checkboxOf(tester, 'q-1').value, isFalse);
  });

  testWidgets('长按一行直接进入多选并选中该行', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-2', stem: '求小球的加速度');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.longPress(
      find.byKey(ValueKey(questionBankRowKeyFor('q-2'))),
    );
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBankSelectedCount(1)), findsOneWidget);
    expect(_checkboxOf(tester, 'q-2').value, isTrue);
    expect(_checkboxOf(tester, 'q-1').value, isFalse);
  });

  testWidgets('全选只选当前学科筛选下可见的题', (tester) async {
    await _seedQuestion(db, id: 'q-math', stem: '求二次函数最小值', subject: 'math');
    await _seedQuestion(db,
        id: 'q-physics', stem: '求小球的加速度', subject: 'physics');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.widgetWithText(ChoiceChip, '物理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();

    expect(find.text(zh.questionBankSelectedCount(1)), findsOneWidget);
    expect(_checkboxOf(tester, 'q-physics').value, isTrue);
    // 数学题被筛选挡住，不在树上，也不会被全选。
    expect(find.byKey(ValueKey(questionBankRowKeyFor('q-math'))), findsNothing);
  });

  testWidgets('清空选择把已选清零并禁用动作', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-2', stem: '求小球的加速度');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();
    expect(find.text(zh.questionBankSelectedCount(2)), findsOneWidget);

    await tester.tap(find.byKey(questionBankClearSelectionKey));
    await tester.pump();

    expect(find.text(zh.questionBankSelectedCount(0)), findsOneWidget);
    expect(_checkboxOf(tester, 'q-1').value, isFalse);
    expect(_checkboxOf(tester, 'q-2').value, isFalse);
    expect(_action(tester, questionBankDeleteSelectedKey).onPressed, isNull);
  });

  testWidgets('退出多选恢复普通 AppBar，选中不保留', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankExitSelectionKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.navQuestions), findsOneWidget);
    expect(find.byKey(questionBankSelectKey), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(questionBankTagSelectedKey), findsNothing);

    // 再进多选时不带上次的勾选。
    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.questionBankSelectedCount(0)), findsOneWidget);
  });

  testWidgets('批量打标签：对话框选中路径后写 object_tags 并报告结果', (tester) async {
    await _seedQuestion(db, id: 'q-tag', stem: '求二次函数最小值');
    await _seedTag(db, id: 'tag-math', path: '文化课/学科/数学');
    await _seedTag(db, id: 'tag-physics', path: '文化课/学科/物理');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-tag'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankTagSelectedKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBulkTagDialogTitle), findsOneWidget);
    await tester.tap(find.text('文化课/学科/数学'));
    await tester.pump();
    await tester.tap(find.byKey(questionBulkTagConfirmKey));
    await tester.pumpAndSettle();

    final links = await db.select(db.objectTags).get();
    expect(links, hasLength(1));
    expect(links.single.objectType, 'question');
    expect(links.single.objectId, 'q-tag');
    expect(links.single.tagId, 'tag-math');
    expect(find.text(zh.questionBankTagDone(1, 0)), findsOneWidget);
  });

  testWidgets('打标签对话框：没有标签时提示无匹配且确认不可点', (tester) async {
    await _seedQuestion(db, id: 'q-tag', stem: '求二次函数最小值');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-tag'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankTagSelectedKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBulkTagNoMatch), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(questionBulkTagConfirmKey))
          .onPressed,
      isNull,
    );
  });

  testWidgets('打标签对话框：搜索过滤标签路径', (tester) async {
    await _seedQuestion(db, id: 'q-tag', stem: '求二次函数最小值');
    await _seedTag(db, id: 'tag-math', path: '文化课/学科/数学');
    await _seedTag(db, id: 'tag-physics', path: '文化课/学科/物理');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-tag'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankTagSelectedKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(questionBulkTagSearchKey), '物理');
    await tester.pump();
    expect(find.text('文化课/学科/物理'), findsOneWidget);
    expect(find.text('文化课/学科/数学'), findsNothing);

    await tester.tap(find.text('文化课/学科/物理'));
    await tester.pump();
    await tester.tap(find.byKey(questionBulkTagConfirmKey));
    await tester.pumpAndSettle();

    final links = await db.select(db.objectTags).get();
    expect(links, hasLength(1));
    expect(links.single.tagId, 'tag-physics');
  });

  testWidgets('导出选中：只导出勾选的题，保存框文件名带 selected', (tester) async {
    final packService = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker();
    _usePicker(picker);
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _seedQuestion(db, id: 'q-2', stem: '求小球的加速度');
    await _seedQuestion(db, id: 'q-3', stem: '第三道不勾的题');
    await _pump(tester, db, packService: packService);

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-2'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankExportSelectedKey));
    await tester.pumpAndSettle();

    expect(packService.exportCalls, 1);
    expect(packService.lastQuestionIds, <String>{'q-1', 'q-2'});
    expect(picker.saveCalls, 1);
    expect(picker.savedDialogTitle, zh.questionBankExportSelected);
    expect(picker.savedFileName, contains('-selected.tqb'));
    expect(picker.savedBytes, hasLength(4));
    expect(find.text(zh.questionBankExportDone(2, '4 B')), findsOneWidget);
  });

  testWidgets('导出选中：用户在保存框取消时不提示成功', (tester) async {
    final packService = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker()..cancelSave = true;
    _usePicker(picker);
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _pump(tester, db, packService: packService);

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankExportSelectedKey));
    await tester.pumpAndSettle();

    expect(packService.exportCalls, 1);
    expect(picker.saveCalls, 1);
    expect(find.text(zh.questionBankExportDone(1, '4 B')), findsNothing);
    // 取消保存不会退出多选。
    expect(find.text(zh.questionBankSelectedCount(1)), findsOneWidget);
  });

  testWidgets('导出选中：服务返回 0 道题时提示已不在题库且不打开保存框', (tester) async {
    final packService = FakeQuestionPackService()
      ..exportResult = QuestionPackExportResult(
        bytes: Uint8List(0),
        questionCount: 0,
        mediaCount: 0,
      );
    final picker = FakeQuestionPackPicker();
    _usePicker(picker);
    await _seedQuestion(db, id: 'q-1', stem: '求二次函数最小值');
    await _pump(tester, db, packService: packService);

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankExportSelectedKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.questionBankExportEmpty), findsOneWidget);
    expect(picker.saveCalls, 0);
  });

  testWidgets('批量删除：确认后删掉选中题目并退出多选', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', title: '第一题');
    await _seedQuestion(db, id: 'q-2', stem: '第二题', title: '第二题');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();
    await tester.tap(find.byKey(questionBankDeleteSelectedKey));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(zh.questionBankDeleteTitle(2)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('第一题')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('第二题')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.text(zh.questionBankDeleteSelected),
      ),
    );
    await tester.pumpAndSettle();

    expect(await db.select(db.questions).get(), isEmpty);
    expect(find.text(zh.questionBankDeleteDone(2)), findsOneWidget);
    expect(find.text(zh.navQuestions), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text(zh.questionBankEmpty), findsOneWidget);
  });

  testWidgets('批量删除：取消确认框不动题库', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', title: '第一题');
    await _pump(tester, db, packService: FakeQuestionPackService());

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(questionBankRowKeyFor('q-1'))));
    await tester.pump();
    await tester.tap(find.byKey(questionBankDeleteSelectedKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(zh.commonCancel),
      ),
    );
    await tester.pumpAndSettle();

    expect(await db.select(db.questions).get(), hasLength(1));
    expect(find.text(zh.questionBankSelectedCount(1)), findsOneWidget);
  });

  testWidgets('批量删除：单题失败不中断整批，汇总失败数', (tester) async {
    await _seedQuestion(db, id: 'q-ok', stem: '能删的题', title: '能删的题');
    await _seedQuestion(db, id: 'q-bad', stem: '删不掉的题', title: '删不掉的题');
    final repository = _FailingDeleteRepository(db, failingId: 'q-bad');
    await _pump(
      tester,
      db,
      packService: FakeQuestionPackService(),
      repository: repository,
    );

    await tester.tap(find.byKey(questionBankSelectKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionBankSelectAllKey));
    await tester.pump();
    await tester.tap(find.byKey(questionBankDeleteSelectedKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(zh.questionBankDeleteSelected),
      ),
    );
    await tester.pumpAndSettle();

    final rows = await db.select(db.questions).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'q-bad');
    expect(
      find.text(
        '${zh.questionBankDeleteDone(1)} · ${zh.questionBankDeleteFailed(1)}',
      ),
      findsOneWidget,
    );
  });

  test('删除预览：空 / 三个以内 / 超过三个折叠', () {
    expect(questionBankDeletePreview(const <String>[]), '');
    expect(questionBankDeletePreview(const <String>['甲', '乙']), '甲、乙');
    expect(
      questionBankDeletePreview(const <String>['甲', '乙', '丙']),
      '甲、乙、丙',
    );
    expect(
      questionBankDeletePreview(const <String>['甲', '乙', '丙', '丁', '戊']),
      '甲、乙、丙 等 5 道',
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  required FakeQuestionPackService packService,
  QuestionRepository? repository,
}) async {
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
        // 组卷页会读诊断；快层没跑是「未知」，用 notRun 而不是空 map。
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => LibraryDiagnosis.notRun,
        ),
        questionPackServiceProvider.overrideWithValue(packService),
        if (repository != null)
          questionRepositoryProvider.overrideWithValue(repository),
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

void _usePicker(FakeQuestionPackPicker picker) {
  final original = FilePickerPlatform.instance;
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = original);
}

ButtonStyleButton _action(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key));

Checkbox _checkboxOf(WidgetTester tester, String questionId) =>
    tester.widget<Checkbox>(
      find.descendant(
        of: find.byKey(ValueKey(questionBankRowKeyFor(questionId))),
        matching: find.byType(Checkbox),
      ),
    );

Future<void> _seedQuestion(
  AppDatabase db, {
  required String id,
  required String stem,
  String subject = '',
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
          sourceLevel: const Value('gaokao'),
          serialNo: Value(serialNo),
          title: Value(title),
        ),
      );
}

Future<void> _seedTag(
  AppDatabase db, {
  required String id,
  required String path,
}) {
  return db.into(db.tags).insert(
        TagsCompanion.insert(
          id: id,
          name: path.split('/').last,
          path: Value(path),
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
}

/// 让指定题目在删除时抛错，验证「单题失败不中断整批」。
final class _FailingDeleteRepository extends QuestionRepository {
  _FailingDeleteRepository(super.db, {required this.failingId});

  final String failingId;

  @override
  Future<void> deleteQuestion(String id) {
    if (id == failingId) {
      throw StateError('delete failed: $id');
    }
    return super.deleteQuestion(id);
  }
}
