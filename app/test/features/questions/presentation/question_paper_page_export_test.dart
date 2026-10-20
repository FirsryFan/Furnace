/// 组卷页「导出 Word」的界面契约（task-10）。
///
/// 界面层只负责四件事，测试也只断言这四件事：
/// 1. 点按钮真的把卷面装配成 docx 字节，并交给保存 seam（FilePicker 的替身）；
/// 2. 成功 / 取消 / 失败 / 告警四种结局各说各的话，不把取消说成成功；
/// 3. 导出期间按钮禁用且显示 loading，防止重复点；
/// 4. 空卷面也能导出（领域层支持只导标题与缺口说明）。
///
/// docx 内容正确性不在这里断言（只验证 zip 魔数）：OOXML 由
/// domain/services/export/paper_docx.dart 的测试与 Lead 的 Word 真测负责。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/export/paper_docx.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_docx_export.dart';
import 'package:furnace/features/questions/application/paper_quality_provider.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/features/questions/presentation/paper_docx_export_button.dart';
import 'package:furnace/features/questions/presentation/paper_quality_view.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
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

  group('告警汇总纯逻辑', () {
    test('warningCount 把六类缺失与读图告警相加', () {
      final result = _exportResult(
        imageSkippedCount: 2,
        formulaFailureCount: 1,
        missingQuestionCount: 1,
        missingStemCount: 1,
        missingAnswerCount: 1,
        missingSolutionCount: 1,
        imageLoadNotes: const ['a.png：认不出图片格式'],
      );

      expect(paperDocxWarningCount(result), 8);
    });

    test('warningGroups 每类最多 3 条，并给出隐藏条数', () {
      final result = _exportResult(
        missingQuestionLabels: const [
          '第 1 题（TR-00001）',
          '第 2 题（TR-00002）',
          '第 3 题（TR-00003）',
          '第 4 题（TR-00004）',
          '第 5 题（TR-00005）'
        ],
      );

      final groups = paperDocxWarningGroups(result);

      expect(groups, hasLength(1));
      expect(groups.single.kind, PaperDocxWarningKind.missingQuestions);
      expect(groups.single.visibleItems, hasLength(3));
      expect(groups.single.totalCount, 5);
      expect(groups.single.hiddenCount, 2);
      expect(groups.single.hasHidden, isTrue);
    });

    test('没有任何提示时不产分组', () {
      expect(paperDocxWarningGroups(_exportResult()), isEmpty);
    });
  });

  group('导出按钮', () {
    testWidgets('成功：保存 seam 收到 docx 字节与建议文件名，SnackBar 如实提示', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver();
      await _pumpPaperPage(tester, db: db, saver: saver);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      expect(saver.lastDialogTitle, zh.questionPaperExportDocx);
      expect(saver.lastFileName, isNotNull);
      expect(
        RegExp(r'^furnace-paper-\d{8}-\d{4}\.docx$')
            .hasMatch(saver.lastFileName!),
        isTrue,
        reason:
            '建议文件名应是 furnace-paper-yyyyMMdd-HHmm.docx，实际：${saver.lastFileName!}',
      );
      final bytes = saver.lastBytes!;
      expect(bytes, isNotEmpty);
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(
        find.textContaining(
          zh.questionPaperExportDocxDone(1, 0, saver.lastFileName!),
        ),
        findsOneWidget,
      );
    });

    testWidgets('取消另存为：不提示成功', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver()..target = null;
      await _pumpPaperPage(tester, db: db, saver: saver);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(
          find.textContaining(zh.questionPaperExportDocxFailed), findsNothing);
      expect(_exportButton(tester).onPressed, isNotNull);
    });

    testWidgets('保存抛错：SnackBar 带错误原文，按钮恢复', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver()..throwError = StateError('disk full');
      await _pumpPaperPage(tester, db: db, saver: saver);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(find.textContaining(zh.questionPaperExportDocxFailed),
          findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
      expect(_exportButton(tester).onPressed, isNotNull);
    });

    testWidgets('装配抛错：SnackBar 带错误原文', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver();
      await _pumpPaperPage(
        tester,
        db: db,
        saver: saver,
        mediaStore: _ThrowingMediaStore(database: db),
      );

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 0);
      expect(find.textContaining(zh.questionPaperExportDocxFailed),
          findsOneWidget);
      expect(find.textContaining('图片目录不可用'), findsOneWidget);
    });

    testWidgets('有告警：SnackBar 可打开明细对话框', (tester) async {
      // 有答案、没解析：装配层记 missingSolutionCount = 1。
      await _seedQuestion(db, id: 'q1', stem: '求 1+1 的值', answer: '2');
      final saver = _FakeSaver();
      await _pumpPaperPage(tester, db: db, saver: saver);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(
        find.textContaining(zh.questionPaperExportDocxWarnings(1)),
        findsOneWidget,
      );

      // 等 SnackBar 入场动画结束：_settle 只等异步数据落定，不等 250ms 动画；
      // 动画中途 action 还在屏幕下方，tap 会打到根视图之外（hit test 打空）。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(zh.questionPaperExportDocxWarningsAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          find.text(zh.questionPaperExportDocxWarningsTitle), findsOneWidget);
      expect(
          find.text(zh.questionPaperExportDocxMissingFields), findsOneWidget);
      expect(
        find.text('· ${zh.questionPaperExportDocxMissingSolution(1)}'),
        findsOneWidget,
      );

      await tester.tap(find.text(zh.commonClose));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(zh.questionPaperExportDocxWarningsTitle), findsNothing);
    });

    testWidgets('导出期间按钮禁用并显示 busy', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver()..gate = Completer<Uri?>();
      await _pumpPaperPage(tester, db: db, saver: saver);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      // 推进到保存 seam 被调用且仍挂着（装配是异步的，先多推几帧）。
      for (var i = 0; i < 80 && saver.calls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(saver.calls, 1);
      expect(find.text(zh.questionPaperExportDocxBusy), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_exportButton(tester).onPressed, isNull);

      saver.gate!.complete(Uri.file('/tmp/furnace-paper.docx'));
      await _settle(tester);

      expect(find.text(zh.questionPaperExportDocxBusy), findsNothing);
      expect(_exportButton(tester).onPressed, isNotNull);
    });

    testWidgets('空卷面也能导出，提示卷面是空的', (tester) async {
      final saver = _FakeSaver();
      await _pumpPaperPage(tester, db: db, saver: saver);

      expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
      expect(_exportButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      expect(saver.lastBytes, isNotNull);
      expect(saver.lastBytes, isNotEmpty);
      expect(
        find.text(zh.questionPaperExportDocxEmptyDone(saver.lastFileName!)),
        findsOneWidget,
      );
    });

    testWidgets('质量报告就绪：导出的 docx 卷末含「组卷质量」节，页面也摆出体检卡', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver();
      await _pumpPaperPage(
        tester,
        db: db,
        saver: saver,
        extraOverrides: [
          paperQualityReportProvider.overrideWith(
            (ref) async => _qualityReport(),
          ),
        ],
      );
      await _waitForQuality(tester);

      // 接线：体检卡确实插在组卷页上（不是只存在于单独测试的沙盒里）。
      expect(find.byKey(paperQualitySectionKey), findsOneWidget);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      final text = _documentText(saver.lastBytes!);
      expect(text, contains('组卷质量'));
      expect(text, contains('判据'));
    });

    testWidgets('质量报告未就绪：导出照常，卷末不带质量节', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final gate = Completer<PaperQualityReport>();
      final saver = _FakeSaver();
      await _pumpPaperPage(
        tester,
        db: db,
        saver: saver,
        extraOverrides: [
          paperQualityReportProvider.overrideWith((ref) => gate.future),
        ],
      );

      expect(find.byKey(paperQualitySectionKey), findsNothing);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      expect(_documentText(saver.lastBytes!), isNot(contains('组卷质量')));
    });

    testWidgets('质量报告算错：导出照常，卷末不带质量节', (tester) async {
      await _seedQuestion(db,
          id: 'q1', stem: '求 1+1 的值', answer: '2', solution: '1+1=2');
      final saver = _FakeSaver();
      await _pumpPaperPage(
        tester,
        db: db,
        saver: saver,
        extraOverrides: [
          paperQualityReportProvider.overrideWith(
            (ref) async => throw StateError('quality boom'),
          ),
        ],
      );

      expect(find.text(zh.paperQualityFailed), findsOneWidget);

      await tester.tap(find.byKey(paperDocxExportButtonKey));
      await _settle(tester);

      expect(saver.calls, 1);
      expect(_documentText(saver.lastBytes!), isNot(contains('组卷质量')));
    });
  });
}

// ---------------------------------------------------------------------------
// 装置
// ---------------------------------------------------------------------------

Future<void> _pumpPaperPage(
  WidgetTester tester, {
  required AppDatabase db,
  required _FakeSaver saver,
  QuestionMediaStore? mediaStore,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        questionMediaStoreProvider.overrideWithValue(
          mediaStore ?? FakeQuestionMediaStore(database: db),
        ),
        paperDocxSaverProvider.overrideWith((ref) => saver.save),
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => LibraryDiagnosis.notRun,
        ),
        ...extraOverrides,
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionPaperPage(),
      ),
    ),
  );
  await _settle(tester);
}

/// 等 provider 落定：进度条消失后再多推两帧。
///
/// 不能用 pumpAndSettle——数据还没到时页面上是无限动画的进度条，会超时。
Future<void> _settle(WidgetTester tester, {int rounds = 80}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final busy = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!busy && i >= 2) {
      return;
    }
  }
}

FilledButton _exportButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(paperDocxExportButtonKey));

Future<void> _seedQuestion(
  AppDatabase db, {
  required String id,
  required String stem,
  String? answer,
  String? solution,
}) async {
  await db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: const Value(''),
          sourceLevel: const Value('unknown'),
          answer: Value(answer),
          solution: Value(solution),
        ),
      );
}

PaperDocxExportResult _exportResult({
  int imageSkippedCount = 0,
  int formulaFailureCount = 0,
  int missingQuestionCount = 0,
  int missingStemCount = 0,
  int missingAnswerCount = 0,
  int missingSolutionCount = 0,
  List<String> missingQuestionLabels = const [],
  List<String> imageLoadNotes = const [],
}) {
  return PaperDocxExportResult(
    report: PaperDocxBuildResult(
      bytes: Uint8List.fromList(<int>[0x50, 0x4B]),
      questionCount: 1,
      paragraphCount: 1,
      imageCount: 0,
      imageSkippedCount: imageSkippedCount,
      formulaCount: 0,
      formulaFailureCount: formulaFailureCount,
      missingQuestionCount: missingQuestionCount,
      missingStemCount: missingStemCount,
      missingAnswerCount: missingAnswerCount,
      missingSolutionCount: missingSolutionCount,
      missingQuestionLabels: missingQuestionLabels,
      imageSkippedNotes: const [],
      formulaFailures: const [],
    ),
    suggestedFileName: 'furnace-paper-20261018-2300.docx',
    imageLoadNotes: imageLoadNotes,
  );
}

/// 保存 seam 的替身：记录最后一次调用，可配置返回值 / 抛错 / 挂起。
class _FakeSaver {
  int calls = 0;
  String? lastDialogTitle;
  String? lastFileName;
  Uint8List? lastBytes;
  Uri? target = Uri.file('/tmp/furnace-paper.docx');
  Object? throwError;
  Completer<Uri?>? gate;

  Future<Uri?> save({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) async {
    calls += 1;
    lastDialogTitle = dialogTitle;
    lastFileName = fileName;
    lastBytes = bytes;
    final error = throwError;
    if (error != null) {
      throw error;
    }
    final pending = gate;
    if (pending != null) {
      return pending.future;
    }
    return target;
  }
}

/// 读配图时直接抛错的替身：模拟装配层失败（不是保存失败）。
class _ThrowingMediaStore extends FakeQuestionMediaStore {
  _ThrowingMediaStore({required super.database});

  @override
  Future<List<QuestionImage>> list(String questionId, {String? role}) async {
    throw StateError('图片目录不可用');
  }
}

/// 等质量报告算完：导出前按钮必须已经 watch 到 data（否则按旧行为不带质量节）。
Future<void> _waitForQuality(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(QuestionPaperPage)),
  );
  for (var i = 0; i < 100; i++) {
    final value = container.read(paperQualityReportProvider);
    if (value is AsyncData<PaperQualityReport>) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('paperQualityReportProvider 一直没算完');
}

/// 从 docx 字节里取出正文文本（按 Word 的 `<w:t>` 片段拼接）。
///
/// 只用来断言「卷末有没有质量节」，不校验 OOXML 结构。
String _documentText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere(
    (item) => item.name == 'word/document.xml',
  );
  final dynamic content = file.content;
  final data =
      content is Uint8List ? content : List<int>.from(content as List<int>);
  final xml = utf8.decode(data);
  return RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
      .allMatches(xml)
      .map((match) => match.group(1) ?? '')
      .join();
}

/// 质量报告替身：内容对导出断言不重要，非 null 就会在卷末多出「组卷质量」节。
PaperQualityReport _qualityReport() => const PaperQualityReport(
      questionCount: 1,
      requestedCount: 1,
      fillRatio: 1,
      subjectDistribution: <PaperQualityBucket>[],
      domainDistribution: <PaperQualityBucket>[],
      difficultyDistribution: <PaperQualityBucket>[],
      sourceLevelDistribution: <PaperQualityBucket>[],
      zoneDistribution: <PaperQualityBucket>[],
      coveredKnowledgePointCount: 0,
      knowledgePointCoverage: 0,
      uncoveredKnowledgePointIds: <String>[],
      quotaSatisfied: true,
      warnings: <PaperQualityWarning>[],
      truncatedWarningCount: 0,
    );
