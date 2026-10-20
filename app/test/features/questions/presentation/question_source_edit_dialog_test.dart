/// 改原题链接对话框的界面级测试：输入 → 预览 → 保存 / 清空 → 写库口径。
///
/// 解析规则本身在 domain 层单测过，这里只钉住「对话框把解析结果如实写进哪几列」：
///  * 完整组卷网 URL / 裸路径 → 三列都写；
///  * 别站 URL → 只写 source_url，已有组卷网 id 不动；
///  * 认不出 → 保存禁用；清空 → 二次确认后三列变 null；
///  * 行不存在 → 如实失败，不假装保存成功。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/questions/presentation/question_source_edit_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';
const String _zujuanUrl = 'https://zujuan.xkw.com/10q35583902.html';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  testWidgets('初值用已有链接，预览同时给出组卷网两个 id', (WidgetTester tester) async {
    final question = await _seed(db, sourceUrl: _zujuanUrl);
    await _pumpAndOpen(tester, db, question);

    final field = tester.widget<TextField>(
      find.byKey(questionSourceEditInputKey),
    );
    expect(field.controller!.text, _zujuanUrl);
    // 输入框与预览行都显示同一条规范化链接。
    expect(find.text(_zujuanUrl), findsNWidgets(2));
    expect(find.text('35583902'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.byKey(questionSourceEditEmptyHintKey), findsNothing);
  });

  testWidgets('粘贴完整组卷网 URL：保存写回三列并提示', (WidgetTester tester) async {
    final question = await _seed(db);
    await _pumpAndOpen(tester, db, question);

    expect(find.text(_zh.questionSourceEditPreviewNoUrl), findsOneWidget);
    await _enter(tester, _zujuanUrl);
    expect(find.text(_zujuanUrl), findsNWidgets(2));
    expect(find.text('35583902'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await _tapSave(tester);

    expect(find.byKey(questionSourceEditDialogKey), findsNothing);
    expect(find.text(_zh.questionSourceEditSaved), findsOneWidget);
    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, _zujuanUrl);
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
  });

  testWidgets('粘贴 /10q<id>.html 路径：补全成组卷网详情页再保存', (WidgetTester tester) async {
    final question = await _seed(db);
    await _pumpAndOpen(tester, db, question);

    await _enter(tester, '/10q35583902.html');
    expect(find.text(_zujuanUrl), findsOneWidget);
    expect(find.text('35583902'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await _tapSave(tester);

    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, _zujuanUrl);
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
  });

  testWidgets('粘贴别的站 URL：只写 source_url，已有组卷网 id 不动',
      (WidgetTester tester) async {
    final question = await _seed(
      db,
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );
    await _pumpAndOpen(tester, db, question);

    await _enter(tester, 'https://Example.com:443/p/1?x=1#frag');
    final normalized = find.text('https://example.com/p/1?x=1');
    expect(normalized, findsOneWidget);
    // 两个组卷网 id 预览为空（不会写）。
    expect(find.text('—'), findsNWidgets(2));

    await _tapSave(tester);

    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, 'https://example.com/p/1?x=1');
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
  });

  testWidgets('认不出的输入：保存禁用并说明原因', (WidgetTester tester) async {
    final question = await _seed(db);
    await _pumpAndOpen(tester, db, question);

    await _enter(tester, '随便一段没有链接的文字');
    expect(find.byKey(questionSourceEditEmptyHintKey), findsOneWidget);
    expect(find.text(_zh.questionSourceEditEmptyHint), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('空白输入同样禁用保存', (WidgetTester tester) async {
    final question = await _seed(db);
    await _pumpAndOpen(tester, db, question);

    expect(find.byKey(questionSourceEditEmptyHintKey), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('清空链接：二次确认后三列变 null 并提示', (WidgetTester tester) async {
    final question = await _seed(
      db,
      sourceUrl: _zujuanUrl,
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );
    await _pumpAndOpen(tester, db, question);

    await tester.tap(find.byKey(questionSourceEditClearKey));
    await tester.pumpAndSettle();
    expect(find.text(_zh.questionSourceEditClearConfirm), findsOneWidget);

    await tester.tap(find.byKey(questionSourceEditClearConfirmKey));
    await tester.pumpAndSettle();

    expect(find.byKey(questionSourceEditDialogKey), findsNothing);
    expect(find.text(_zh.questionSourceEditCleared), findsOneWidget);
    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, isNull);
    expect(row.zujuanQuestionId, isNull);
    expect(row.zujuanBankId, isNull);
  });

  testWidgets('清空的二次确认可以取消：不改库，编辑框还开着', (WidgetTester tester) async {
    final question = await _seed(
      db,
      sourceUrl: _zujuanUrl,
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );
    await _pumpAndOpen(tester, db, question);

    await tester.tap(find.byKey(questionSourceEditClearKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_zh.questionSourceCancel),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(questionSourceEditDialogKey), findsOneWidget);
    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, _zujuanUrl);
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
  });

  testWidgets('行已被删：保存如实失败，不假装成功', (WidgetTester tester) async {
    final question = await _seed(db);
    await QuestionRepository(db).deleteQuestion(question.id);
    await _pumpAndOpen(tester, db, question);

    await _enter(tester, _zujuanUrl);
    await _tapSave(tester);

    expect(find.byKey(questionSourceEditDialogKey), findsOneWidget);
    expect(
      find.text(
        _zh.questionSourceEditFailed(_zh.questionDetailQuestionMissing),
      ),
      findsOneWidget,
    );
    expect(find.text(_zh.questionSourceEditSaved), findsNothing);
  });

  testWidgets('取消对话框不写库', (WidgetTester tester) async {
    final question = await _seed(db);
    await _pumpAndOpen(tester, db, question);

    await tester.tap(find.byKey(questionSourceEditCancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(questionSourceEditDialogKey), findsNothing);
    final row = await QuestionRepository(db).byId(question.id);
    expect(row!.sourceUrl, isNull);
    expect(row.zujuanQuestionId, isNull);
  });
}

/// 往内存库塞一道题，返回入库后的快照。
Future<Question> _seed(
  AppDatabase db, {
  String? sourceUrl,
  String? zujuanQuestionId,
  String? zujuanBankId,
}) async {
  final result = await QuestionRepository(db).ingest(
    QuestionDraft(
      stem: _stem,
      answer: '5',
      solution: '韦达定理：两根之和等于 -b/a。',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
      difficulty: 4,
      sourceUrl: sourceUrl,
      zujuanQuestionId: zujuanQuestionId,
      zujuanBankId: zujuanBankId,
    ),
  );
  return result.question;
}

/// 打开页面并把对话框点开（真实 provider 链路 + 内存库）。
Future<void> _pumpAndOpen(
  WidgetTester tester,
  AppDatabase db,
  Question question,
) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-source-dialog'),
                onPressed: () => showQuestionSourceEditDialog(
                  context,
                  question: question,
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
  await tester.tap(find.byKey(const Key('open-source-dialog')));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(questionSourceEditInputKey), text);
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(questionSourceEditSaveKey));
  await tester.pumpAndSettle();
}

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(questionSourceEditSaveKey));
