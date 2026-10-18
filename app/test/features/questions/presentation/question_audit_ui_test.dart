/// 入库体检的界面契约：详情页把结论摊开，题库列表只在脏题上挂徽标。
///
/// 三件事：
///  1. 每条 finding 的严重度标签、中文说明与可展开的 evidence 都看得见，
///     并且按 error → warning → info 的分组顺序排；
///  2. 干净题给「未发现硬伤」+「只报不改」，列表页不挂徽标；
///  3. 体检读失败不挡题面：区块零高度、题面照常渲染。
///
/// 报告全部用 `questionAuditReportProvider.overrideWith` 注入：这里测的是 UI
/// 怎么摊开结论，不是审计算法本身（算法有自己的纯逻辑测试）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_audit_reader.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_audit_view.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const int _ts = 1700000000000;
const String _stem = '已知 x^2-5x+6=0，求两根之和。';
const String _detailQuestionId = 'q-detail';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('详情页：按 error→warning→info 分组，中文说明与判定依据都在',
      (WidgetTester tester) async {
    final database = _newDatabase();
    await _seedDetailQuestion(database);
    const errorFinding = QuestionAuditFinding(
      questionId: _detailQuestionId,
      code: 'h2_answer_missing',
      severity: QuestionAuditSeverity.error,
      messageZh: '这道题没有答案',
    );
    const warningFinding = QuestionAuditFinding(
      questionId: _detailQuestionId,
      code: 'h4_duplicate_stem',
      severity: QuestionAuditSeverity.warning,
      messageZh: '题干可能和另一道题重复',
      evidence: <String, String>{
        'stem_fingerprint': 'abc123',
        'duplicate_of': 'TR-00007',
      },
    );
    const infoFinding = QuestionAuditFinding(
      questionId: _detailQuestionId,
      code: 'local_no_knowledge_points',
      severity: QuestionAuditSeverity.info,
      messageZh: '还没有挂知识点',
    );
    const report = QuestionAuditReport(
      findings: <QuestionAuditFinding>[
        errorFinding,
        warningFinding,
        infoFinding,
      ],
    );

    await _pumpDetail(tester, database, report: report);
    await _waitForText(tester, _zh.questionAuditSectionTitle);

    // 三条 finding 的中文说明都可见，严重度标签由 labelZh 拼在说明前面。
    expect(find.text(_zh.questionAuditSectionTitle), findsOneWidget);
    for (final finding in report.findings) {
      expect(
        find.text('${finding.severity.labelZh} · ${finding.messageZh}'),
        findsOneWidget,
      );
    }

    // 分组标题与顺序：error 在最上，info 在最下。
    final errorHeader = find.text(_zh.questionAuditGroupHeader(
      QuestionAuditSeverity.error.labelZh,
      1,
    ));
    final warningHeader = find.text(_zh.questionAuditGroupHeader(
      QuestionAuditSeverity.warning.labelZh,
      1,
    ));
    final infoHeader = find.text(_zh.questionAuditGroupHeader(
      QuestionAuditSeverity.info.labelZh,
      1,
    ));
    expect(errorHeader, findsOneWidget);
    expect(warningHeader, findsOneWidget);
    expect(infoHeader, findsOneWidget);
    expect(
      tester.getTopLeft(errorHeader).dy < tester.getTopLeft(warningHeader).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(warningHeader).dy < tester.getTopLeft(infoHeader).dy,
      isTrue,
    );

    // 只报不改：区块里给出说明，且没有改题按钮。
    expect(find.text(_zh.questionAuditReadOnly), findsOneWidget);

    // evidence 默认收起，展开后键值原样显示。
    expect(find.textContaining('abc123'), findsNothing);
    final evidenceToggle = find.text(_zh.questionAuditEvidence);
    expect(evidenceToggle, findsOneWidget);
    await tester.ensureVisible(evidenceToggle);
    await tester.pumpAndSettle();
    await tester.tap(evidenceToggle);
    await tester.pumpAndSettle();
    expect(
      find.text('stem_fingerprint: abc123'),
      findsOneWidget,
    );
    expect(find.text('duplicate_of: TR-00007'), findsOneWidget);
  });

  testWidgets('详情页：本次检查没有该题的 findings 时显示干净文案', (WidgetTester tester) async {
    final database = _newDatabase();
    await _seedDetailQuestion(database);
    const report = QuestionAuditReport(
      findings: <QuestionAuditFinding>[
        QuestionAuditFinding(
          questionId: 'q-someone-else',
          code: 'h2_answer_missing',
          severity: QuestionAuditSeverity.error,
          messageZh: '这道题没有答案',
        ),
      ],
    );

    await _pumpDetail(tester, database, report: report);
    await _waitForText(tester, _zh.questionAuditSectionTitle);

    expect(find.text(_zh.questionAuditClean), findsOneWidget);
    expect(find.text(_zh.questionAuditReadOnly), findsOneWidget);
    // 别的题的 finding 不该借到这道题上。
    expect(find.textContaining('这道题没有答案'), findsNothing);
    expect(find.text(_zh.questionAuditEvidence), findsNothing);
  });

  testWidgets('题库列表：脏题挂带数量的徽标，干净题不占位', (WidgetTester tester) async {
    final database = _newDatabase();
    await _seedBankQuestion(
      database,
      id: 'q-dirty',
      stem: '这道题缺答案，体检会报错',
      serialNo: 1,
    );
    await _seedBankQuestion(
      database,
      id: 'q-clean',
      stem: '这道题很干净，没有体检问题',
      serialNo: 2,
    );
    const report = QuestionAuditReport(
      findings: <QuestionAuditFinding>[
        QuestionAuditFinding(
          questionId: 'q-dirty',
          code: 'h2_answer_missing',
          severity: QuestionAuditSeverity.error,
          messageZh: '这道题没有答案',
        ),
        QuestionAuditFinding(
          questionId: 'q-dirty',
          code: 'h4_duplicate_stem',
          severity: QuestionAuditSeverity.warning,
          messageZh: '题干可能和另一道题重复',
        ),
      ],
    );

    await _pumpBank(tester, database, report: report);

    // 两行都渲染出来了，但只有脏题挂了徽标。
    expect(find.text('这道题缺答案，体检会报错'), findsOneWidget);
    expect(find.text('这道题很干净，没有体检问题'), findsOneWidget);
    expect(find.byKey(questionAuditBadgeKey), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.byKey(questionAuditBadgeKey),
    );
    expect(tooltip.message, _zh.questionAuditBadgeTooltip(1, 1));
  });

  testWidgets('体检读失败：详情页题面照常渲染，体检区块零高度', (WidgetTester tester) async {
    final database = _newDatabase();
    await _seedDetailQuestion(database);

    await _pumpDetail(tester, database, reportFails: true);
    await _waitForText(tester, _stem);

    expect(find.text(_zh.questionAuditSectionTitle), findsNothing);
    expect(find.byKey(questionAuditSectionKey), findsNothing);
    expect(find.text(_zh.questionAuditClean), findsNothing);
  });
}

/// 详情页用：一道真的落库的题（详情页只认库里的行，不认内存快照）。
AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<void> _seedDetailQuestion(AppDatabase database) {
  return database.into(database.questions).insert(
        QuestionsCompanion.insert(
          id: _detailQuestionId,
          stem: _stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: const Value<String>('math'),
          sourceLevel: const Value<String>('gaokao'),
          serialNo: const Value<int>(1),
        ),
      );
}

Future<void> _seedBankQuestion(
  AppDatabase database, {
  required String id,
  required String stem,
  int? serialNo,
}) {
  return database.into(database.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: const Value<String>('math'),
          sourceLevel: const Value<String>('gaokao'),
          serialNo: Value<int?>(serialNo),
        ),
      );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database, {
  QuestionAuditReport? report,
  bool reportFails = false,
}) async {
  _bigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
        if (reportFails)
          questionAuditReportProvider.overrideWith(
            (ref) async => throw StateError('体检读不出来'),
          )
        else if (report != null)
          questionAuditReportProvider.overrideWith((ref) async => report),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: _detailQuestionId),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pumpBank(
  WidgetTester tester,
  AppDatabase database, {
  required QuestionAuditReport report,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => LibraryDiagnosis.notRun,
        ),
        questionAuditReportProvider.overrideWith((ref) async => report),
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

/// 详情页很长，默认 800×600 视口里 `ListView` 只建可见的那几行。
void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 推进几帧直到没有转圈的进度条（进度指示器是无限动画，不能 pumpAndSettle）。
Future<void> _settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final spinning =
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!spinning) {
      return;
    }
  }
}

/// 等一段文字出现（异步管道 + 数据库回写需要的帧数不确定，所以轮询）。
Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这段文字：$text');
}
