/// 题库批量打标签对话框的「用途边界」：只列声明了题库用途的标签。
///
/// 这里只测对话框自己的取数/空态/提示；把选中的路径写进 object_tags 的
/// 流程由 `question_bank_bulk_test.dart` 覆盖。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/presentation/question_bulk_tag_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:furnace/l10n/app_localizations_zh.dart';

/// 最近一次对话框的返回值（host 在 await 返回后写入）。
Set<String>? _lastResult;

class _DialogHost extends StatelessWidget {
  const _DialogHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('open-bulk-tag'),
          onPressed: () async {
            _lastResult = await showQuestionBulkTagDialog(context);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<AppDatabase> _openDatabase() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<void> _seedTag(
  AppDatabase db, {
  required String id,
  required String path,
  String? usageCodes,
}) async {
  await db.into(db.tags).insert(TagsCompanion.insert(
        id: id,
        name: path.split('/').last,
        path: Value(path),
        usageCodes:
            usageCodes == null ? const Value.absent() : Value(usageCodes),
        createdAt: 1,
        updatedAt: 1,
      ));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('the dialog is still loading after 30 pumps');
}

Future<void> _pumpAndOpen(WidgetTester tester, AppDatabase db) async {
  _lastResult = null;
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _DialogHost(),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.byKey(const Key('open-bulk-tag')));
  await _settle(tester);
}

void main() {
  final l10n = AppLocalizationsZh();

  testWidgets('有用途声明时只列题库标签，并说明范围', (tester) async {
    final db = await _openDatabase();
    await _seedTag(
      db,
      id: 't-math',
      path: '文化课/数学',
      usageCodes: 'question',
    );
    await _seedTag(
      db,
      id: 't-english',
      path: '文化课/英语',
      usageCodes: 'flashcard',
    );
    // 整条链都没声明 = 不限制，仍然可见。
    await _seedTag(db, id: 't-undeclared', path: '文化课/物理');

    await _pumpAndOpen(tester, db);

    expect(find.text('文化课/数学'), findsOneWidget);
    expect(find.text('文化课/物理'), findsOneWidget);
    expect(
      find.text('文化课/英语'),
      findsNothing,
      reason: '声明了闪卡用途的标签不该出现在题库选择器里',
    );
    expect(
      find.text(l10n.tagUsageScopeHintNamed(l10n.tagUsageQuestion)),
      findsOneWidget,
    );

    await tester.tap(find.text('文化课/数学'));
    await _settle(tester);
    await tester.tap(find.byKey(questionBulkTagConfirmKey));
    await _settle(tester);

    expect(_lastResult, {'文化课/数学'});
  });

  testWidgets('只有别的用途的标签时说明空态且不能确认', (tester) async {
    final db = await _openDatabase();
    await _seedTag(
      db,
      id: 't-english',
      path: '文化课/英语',
      usageCodes: 'flashcard',
    );

    await _pumpAndOpen(tester, db);

    expect(
      find.text(l10n.tagUsageScopeEmptyNamed(l10n.tagUsageQuestion)),
      findsOneWidget,
    );
    expect(find.text('文化课/英语'), findsNothing);
    expect(
      find.byKey(questionBulkTagSearchKey),
      findsNothing,
      reason: '没有可选标签时搜索框没有意义',
    );
    final confirm = tester.widget<FilledButton>(
      find.byKey(questionBulkTagConfirmKey),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('整棵树没有声明用途时全部可选并提示默认全列', (tester) async {
    final db = await _openDatabase();
    await _seedTag(db, id: 't-math', path: '文化课/数学');
    await _seedTag(db, id: 't-physics', path: '文化课/物理');

    await _pumpAndOpen(tester, db);

    expect(find.text(l10n.tagUsageScopeDefaultHint), findsOneWidget);
    expect(find.text('文化课/数学'), findsOneWidget);
    expect(find.text('文化课/物理'), findsOneWidget);

    await tester.tap(find.text('文化课/数学'));
    await _settle(tester);
    await tester.tap(find.text('文化课/物理'));
    await _settle(tester);
    await tester.tap(find.byKey(questionBulkTagConfirmKey));
    await _settle(tester);

    expect(_lastResult, {'文化课/数学', '文化课/物理'});
  });
}
