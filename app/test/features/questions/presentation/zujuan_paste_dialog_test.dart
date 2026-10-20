/// 粘贴组卷网题面对话框：解析预览、勾选、改题干、批量入库与汇总。
///
/// 入库走真实仓储 + 内存库；只有「单条失败不中断」用替身仓储注入异常。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paste.dart';
import 'package:furnace/features/questions/application/zujuan_paste_import.dart';
import 'package:furnace/features/questions/presentation/zujuan_paste_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

const String _oneQuestion = '''
1.（2024·湖南·长沙·一模）已知函数 f(x)=x^2+1，求 f(2)。
A. 3
B. 4
C. 5
D. 6
【答案】C
''';

const String _twoQuestions = '''
1.（2024·湖南·长沙·一模）已知函数 f(x)=x^2+1，求 f(2)。
A. 3
B. 4
C. 5
D. 6
【答案】C
【解析】f(2)=5。

2.（2023·湖北·武汉）下列哪项正确？
A. 甲
B. 乙
【答案】B
''';

const String _twoWithBadSecond = '''
1.（2024·湖南·长沙·一模）已知函数 f(x)=x^2+1，求 f(2)。
A. 3
B. 4
C. 5
D. 6
【答案】C

2.（2023·湖北·武汉）坏题：判断下列说法。
A. 甲
B. 乙
【答案】B
''';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('「全部入库」只看勾选数与是否正在入库', () {
    expect(zujuanPasteCanImport(selectedCount: 0, importing: false), isFalse);
    expect(zujuanPasteCanImport(selectedCount: 1, importing: false), isTrue);
    expect(zujuanPasteCanImport(selectedCount: 2, importing: true), isFalse);
    expect(zujuanPasteCanImport(selectedCount: 0, importing: true), isFalse);
  });

  testWidgets('解析两题：预览题数、选项数、来源与年份、默认全勾', (tester) async {
    final summaries = <ZujuanPasteSummary?>[];
    final strings =
        await _pumpDialog(tester, database: db, summaries: summaries);

    await _parse(tester, _twoQuestions);

    expect(find.text(strings.zujuanPastePreviewTitle(2)), findsOneWidget);
    expect(find.text(strings.zujuanPasteItemOptions(4)), findsOneWidget);
    expect(find.text(strings.zujuanPasteItemOptions(2)), findsOneWidget);
    expect(
      find.textContaining(strings.zujuanPasteItemSource('2024·湖南·长沙·一模')),
      findsOneWidget,
    );
    expect(
      find.textContaining(strings.zujuanPasteItemYear(2024)),
      findsOneWidget,
    );
    final checkbox0 = tester.widget<Checkbox>(
      find.byKey(zujuanPasteCheckboxKey(0)),
    );
    final checkbox1 = tester.widget<Checkbox>(
      find.byKey(zujuanPasteCheckboxKey(1)),
    );
    expect(checkbox0.value, isTrue);
    expect(checkbox1.value, isTrue);
  });

  testWidgets('取消勾选第二题：只入库第一题', (tester) async {
    final summaries = <ZujuanPasteSummary?>[];
    await _pumpDialog(tester, database: db, summaries: summaries);
    await _parse(tester, _twoQuestions);

    await tester.tap(find.byKey(zujuanPasteCheckboxKey(1)));
    await tester.pumpAndSettle();
    await _import(tester);

    final summary = summaries.single!;
    expect(summary.saved, 1);
    expect(summary.duplicates, 0);
    expect(summary.failed, 0);
    final rows = await db.select(db.questions).get();
    expect(rows, hasLength(1));
    expect(rows.single.stem, contains('求 f(2)'));
  });

  testWidgets('题干指纹重复：计入「重复」，不新增行', (tester) async {
    final parsed = parseZujuanPaste(_oneQuestion);
    await QuestionRepository(db).ingest(
      zujuanDraftFromPasted(parsed.single, subjectKey: 'math'),
    );
    final summaries = <ZujuanPasteSummary?>[];
    await _pumpDialog(tester, database: db, summaries: summaries);
    await _parse(tester, _oneQuestion);

    await _import(tester);

    final summary = summaries.single!;
    expect(summary.saved, 0);
    expect(summary.duplicates, 1);
    expect(summary.failed, 0);
    expect(await db.select(db.questions).get(), hasLength(1));
  });

  testWidgets('改过题干再入库：库里是改后的文本', (tester) async {
    final summaries = <ZujuanPasteSummary?>[];
    await _pumpDialog(tester, database: db, summaries: summaries);
    await _parse(tester, _oneQuestion);

    await tester.enterText(
      find.byKey(zujuanPasteStemFieldKey(0)),
      '改过的题干：求 f(2)',
    );
    await tester.pumpAndSettle();
    await _import(tester);

    expect(summaries.single!.saved, 1);
    final rows = await db.select(db.questions).get();
    expect(rows.single.stem, '改过的题干：求 f(2)');
  });

  testWidgets('识别不完整：标出提示但仍可入库', (tester) async {
    final strings = await _pumpDialog(tester,
        database: db, summaries: <ZujuanPasteSummary?>[]);
    await _parse(tester, '这里是一段没有题目结构的文字。');

    expect(find.text(strings.zujuanPastePartial), findsOneWidget);
    expect(find.text(strings.zujuanPastePreviewTitle(1)), findsOneWidget);
  });

  testWidgets('解析不出题：空态文案，没有入库按钮', (tester) async {
    final strings = await _pumpDialog(tester,
        database: db, summaries: <ZujuanPasteSummary?>[]);
    await _parse(tester, '   ');

    expect(find.byKey(zujuanPasteEmptyKey), findsOneWidget);
    expect(find.text(strings.zujuanPasteParseEmpty), findsOneWidget);
    expect(find.byKey(zujuanPasteImportKey), findsNothing);
  });

  testWidgets('全部取消勾选：提示先勾选，入库按钮禁用', (tester) async {
    final strings = await _pumpDialog(tester,
        database: db, summaries: <ZujuanPasteSummary?>[]);
    await _parse(tester, _twoQuestions);

    await tester.tap(find.byKey(zujuanPasteCheckboxKey(0)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(zujuanPasteCheckboxKey(1)));
    await tester.pumpAndSettle();

    expect(find.text(strings.zujuanPasteNothingSelected), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(zujuanPasteImportKey),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('单条入库抛异常：不中断整批，计入失败', (tester) async {
    final summaries = <ZujuanPasteSummary?>[];
    await _pumpDialog(
      tester,
      database: db,
      summaries: summaries,
      repository: _FlakyRepository(db),
    );
    await _parse(tester, _twoWithBadSecond);

    await _import(tester);

    final summary = summaries.single!;
    expect(summary.saved, 1);
    expect(summary.duplicates, 0);
    expect(summary.failed, 1);
    final rows = await db.select(db.questions).get();
    expect(rows, hasLength(1));
    expect(rows.single.stem, contains('求 f(2)'));
  });

  testWidgets('直接关闭：不写库，汇总为 null', (tester) async {
    final summaries = <ZujuanPasteSummary?>[];
    final strings =
        await _pumpDialog(tester, database: db, summaries: summaries);
    await _parse(tester, _twoQuestions);

    await tester.tap(find.byTooltip(strings.commonClose));
    await tester.pumpAndSettle();

    expect(summaries, hasLength(1));
    expect(summaries.single, isNull);
    expect(await db.select(db.questions).get(), isEmpty);
    expect(find.byKey(zujuanPasteDialogKey), findsNothing);
  });
}

Future<void> _parse(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(zujuanPasteInputKey), text);
  await tester.pump();
  await tester.tap(find.byKey(zujuanPasteParseKey));
  await tester.pumpAndSettle();
}

Future<void> _import(WidgetTester tester) async {
  await tester.tap(find.byKey(zujuanPasteImportKey));
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _pumpDialog(
  WidgetTester tester, {
  required AppDatabase database,
  required List<ZujuanPasteSummary?> summaries,
  QuestionRepository? repository,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        if (repository != null)
          questionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-paste'),
                onPressed: () async {
                  summaries.add(
                    await showZujuanPasteDialog(
                      context,
                      l10n: AppLocalizations.of(context),
                      initialSubjectKey: 'math',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-paste')));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
    tester.element(find.byKey(const Key('open-paste'))),
  );
}

/// 入库时按题干内容注入一次失败：验证批量不中断。
class _FlakyRepository extends QuestionRepository {
  _FlakyRepository(super.db);

  @override
  Future<({Question question, bool created})> ingest(
    QuestionDraft draft, {
    DateTime? now,
  }) {
    if (draft.stem.contains('坏题')) {
      throw StateError('这条题数据坏了');
    }
    return super.ingest(draft, now: now);
  }
}
