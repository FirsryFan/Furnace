import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// P0 复现：真实库副本 + 真实认知诊断（**不 override** 任何业务 provider）。
///
/// 旧 smoke（`real_db_bank_to_paper_test.dart`）把
/// `cognitiveLibraryDiagnosisProvider` 覆盖成 `LibraryDiagnosis.notRun` 才通过；
/// 真机上组卷按钮会跑真实诊断 + 真实画像，本文件就是补上这条真路径。
void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() {
    final source = File(r'E:\Furnace\data\furnace.db');
    if (!source.existsSync()) {
      throw StateError('real database not present: ${source.path}');
    }
    tmp = Directory.systemTemp.createTempSync('furnace-crash-repro-');
    final copied = File('${tmp.path}/furnace.db');
    source.copySync(copied.path);
    db = AppDatabase.forTesting(
      // 生产 `_openConnection` 用 `instrumentWrites` 包了同一个执行器：
      // 缺了它，测试里的写不会推进 DataChangeBus/数据版本，页面就少了一整条
      // "写 → 版本变 → provider 重跑" 的回流。复现必须和生产同构。
      instrumentWrites(NativeDatabase(copied)),
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  List<Override> overrides() => <Override>[
        appDatabaseProvider.overrideWithValue(db),
        questionMediaStoreProvider.overrideWithValue(
          QuestionMediaStore(database: db, supportDirectory: () async => tmp),
        ),
      ];

  Widget app(Widget home) => ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  /// 有界 pump（绝不 pumpAndSettle）：每步 50ms，最多 200 步 = 测试内 10s。
  /// 返回「是否在预算内安静下来」与「期间收下的全部异常」。
  Future<({bool quiet, List<Object> errors})> pumpBounded(
    WidgetTester tester, {
    int steps = 200,
  }) async {
    final errors = <Object>[];
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // 每次 pump 后立刻把异常取出来记录，避免「首个异常之后全部丢失」。
      final exception = tester.takeException();
      if (exception != null) {
        errors.add(exception);
        // ignore: avoid_print
        print('REPRO EXCEPTION at step $i: $exception');
      }
      final busy =
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!busy && i >= 4) return (quiet: true, errors: errors);
    }
    return (quiet: false, errors: errors);
  }

  testWidgets('REPRO A: direct QuestionPaperPage on real DB (real diagnosis)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final watch = Stopwatch()..start();
    await tester.pumpWidget(app(const QuestionPaperPage()));
    final result = await pumpBounded(tester);
    watch.stop();

    final titles = find.text('组卷').evaluate().length;
    final subtitle =
        find.textContaining('AI 不会替你出题').evaluate().length;
    final failed = find.textContaining('组卷没算出来').evaluate().length;
    // ignore: avoid_print
    print('REPRO A quiet=${result.quiet} elapsed=${watch.elapsedMilliseconds}ms '
        'errors=${result.errors} titles=$titles subtitle=$subtitle '
        'failed=$failed');
    // 有界预算内必须安静下来，否则就是卡死（用例会失败并打印上面一行）。
    expect(result.quiet, isTrue, reason: '页面 10s 内没有安静下来（可能卡死/无限重建）');
    expect(result.errors, isEmpty, reason: '组卷页在真实库上抛异常');
    expect(titles, greaterThan(0), reason: '组卷页 AppBar 标题没出现（白屏）');
    // 组卷页自身文案出现 = 没有白屏。
    expect(subtitle, greaterThan(0), reason: '组卷页 subtitle 没出现（白屏/卡在加载）');
    expect(failed, 0, reason: '组卷 plan 报错：应该显示错误但不能空白');
    expect(find.byType(QuestionPaperPage), findsOneWidget);
  });

  testWidgets('REPRO B: 题库页点「组卷」→ 真实诊断', (tester) async {
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const QuestionBankPage()));
    // 题库页本身先要有界加载完（最多 10s）。
    final bank = await pumpBounded(tester);
    // ignore: avoid_print
    print('REPRO B bank quiet=${bank.quiet} errors=${bank.errors}');

    expect(find.text('组卷'), findsWidgets,
        reason: '题库页上找不到「组卷」入口');
    await tester.tap(find.text('组卷').first);
    final watch = Stopwatch()..start();
    final result = await pumpBounded(tester);
    watch.stop();
    final navigated = find.byType(QuestionPaperPage).evaluate().isNotEmpty;
    // ignore: avoid_print
    print('REPRO B quiet=${result.quiet} elapsed=${watch.elapsedMilliseconds}ms '
        'errors=${result.errors} navigated=$navigated');
    expect(result.quiet, isTrue, reason: '点组卷后 10s 内没有安静下来（可能卡死）');
    expect(result.errors, isEmpty, reason: '点「组卷」抛异常');
    expect(find.byType(QuestionPaperPage), findsOneWidget);
  });

  test('REPRO C: provider 级二分（诊断 / 画像 / 组卷）', () async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);

    final diagnosisWatch = Stopwatch()..start();
    try {
      final diagnosis =
          await container.read(cognitiveLibraryDiagnosisProvider.future)
              .timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('REPRO C diagnosis ok in '
          '${diagnosisWatch.elapsedMilliseconds}ms fastLayerRan=${diagnosis.fastLayerRan}');
    } catch (error, stack) {
      // ignore: avoid_print
      print('REPRO C diagnosis FAILED in '
          '${diagnosisWatch.elapsedMilliseconds}ms: $error\n$stack');
      rethrow;
    }

    final planWatch = Stopwatch()..start();
    final plan = await container
        .read(paperPlanProvider.future)
        .timeout(const Duration(seconds: 60));
    // ignore: avoid_print
    print('REPRO C plan ok in ${planWatch.elapsedMilliseconds}ms '
        'items=${plan.items.length} candidates=${plan.candidateCount}');
    expect(plan.items, isNotEmpty);
  });
}
