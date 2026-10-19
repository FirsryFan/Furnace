/// 题库入库体检接进 AI 工具层（只读）。
///
/// 判据、阈值、排序全在 domain/services/questions/question_intake_audit.dart；
/// 读表在 features/questions/application/question_audit_reader.dart。这个文件只做
/// 一件事：把体检报告压成模型看得懂、用户读得懂的一句摘要 + 结构化 JSON。
///
/// 纪律（与 compose_paper 同一条）：只报不改。工具**不能**修数据、不能删题、
/// 不能改写题干；它只回答"题库里现在有哪些硬伤、分别在哪些题上"。
library;

import '../../../data/database/database.dart';
import '../../../domain/services/questions/question_audit_summary.dart';
import '../../../domain/services/questions/question_intake_audit.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../questions/application/question_audit_reader.dart';
import '../domain/ai_tool.dart';

/// 体检题库现状（H1 题干 / H2 答案 / H3 元数据 / H4 重复四大类判据）。
class AuditQuestionIntakeTool extends AiTool {
  AuditQuestionIntakeTool({required AppDatabase db, DateTime Function()? clock})
      : _db = db,
        _clock = clock;

  final AppDatabase _db;

  /// 年份判据要用「今年」。不隐式读 DateTime.now()：测试与报告都要可复现，
  /// 生产由工具注册处把同一个 clock 传进来。
  final DateTime Function()? _clock;

  /// 默认返回多少条结论（模型一次读太多没用，先给最前面的）。
  static const int defaultLimit = 20;

  /// 一次最多返回多少条：再多就该按严重度/学科过滤后再问。
  static const int maxLimit = 100;

  @override
  String get name => 'audit_question_intake';

  @override
  String get description => '体检用户的题库：按 H1 题干（空/过短/选项矛盾/说如图却没图）、'
      'H2 答案（缺答案/缺解析/答案与选项矛盾/解析抄答案）、H3 元数据（难度/年份/学科/来源越界）、'
      'H4 重复（题干重复/题号重复）四类判据找出"入库时带进来的硬伤"，返回每类计数与具体哪几道题。'
      '用在你需要回答"我的题库质量怎么样、哪些题要修"的时候。**只读**：不改任何数据、'
      '不删题、不修题——只报问题。先用 limit 取前排，需要更多就按 severity 或 subject_key '
      '过滤后再问；一次别要超过 100 条。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'severity': {
            'type': 'string',
            'enum': <String>['error', 'warning', 'info'],
            'description': '只看这个严重度（error 硬伤 / warning 可疑 / info 提示）；'
                '不给 = 全部。',
          },
          'subject_key': {
            'type': 'string',
            'description': '只看这个学科（如 physics / math）；不给 = 全库。',
          },
          'limit': {
            'type': 'integer',
            'minimum': 1,
            'maximum': maxLimit,
            'description': '最多返回多少条结论，默认 $defaultLimit（上限 $maxLimit）。'
                '计数（counts / by_code）始终是全量，不受 limit 影响。',
          },
        },
        'required': <String>[],
      };

  /// 只读、无 action：write 风险 + 可逆，正是这个组合让审批引擎在两种权限模式
  /// 下都不会逐条询问它（同 compose_paper / find_similar_questions）。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final severityText = args.optString('severity');
    final severityFilter =
        severityText == null ? null : _severityOf(severityText);
    if (severityText != null && severityFilter == null) {
      throw ToolArgError(
        '未知的 severity: $severityText。可用：error / warning / info',
      );
    }
    final subjectKey = args.optString('subject_key')?.toLowerCase();
    var limit = args.optInt('limit') ?? defaultLimit;
    if (limit < 1) {
      throw ToolArgError('limit 必须是正整数（当前 $limit）');
    }
    if (limit > maxLimit) {
      limit = maxLimit;
    }

    final corpus = await readQuestionAuditCorpus(_db);
    final rows = subjectKey == null
        ? corpus.rows
        : <QuestionAuditRow>[
            for (final row in corpus.rows)
              if (row.subjectKey.trim().toLowerCase() == subjectKey) row,
          ];
    final report = QuestionIntakeAudit(
      currentYear: (_clock?.call() ?? DateTime.now()).year,
      knownSubjectKeys: corpus.knownSubjectKeys,
      knownSourceLevels: kQuestionAuditKnownSourceLevels,
    ).audit(rows);

    final findings = <QuestionAuditFinding>[
      for (final finding in report.findings)
        if (severityFilter == null || finding.severity == severityFilter)
          finding,
    ];
    final shown = findings.take(limit).toList(growable: false);
    final serials = <String, int?>{
      for (final row in corpus.rows) row.questionId: row.serialNo,
    };

    // 全库聚合报告与上面 findings 用同一份（已按 severity 过滤的）结论：按题分组，
    // 一道题没有结论也保留空 report，questionCount / cleanRatio 才等于体检题数。
    final findingsByQuestion = <String, List<QuestionAuditFinding>>{
      for (final row in rows) row.questionId: <QuestionAuditFinding>[],
    };
    for (final finding in findings) {
      findingsByQuestion
          .putIfAbsent(finding.questionId, () => <QuestionAuditFinding>[])
          .add(finding);
    }
    final auditSummary = QuestionAuditSummary.summarize(
      <QuestionAuditReport>[
        for (final row in rows)
          QuestionAuditReport(
            findings: findingsByQuestion[row.questionId] ??
                const <QuestionAuditFinding>[],
          ),
      ],
      maxOffenders: 10,
      maxSampleQuestionIds: 5,
    );

    // 按 (code, severity) 计数：同一个 code 只会有一个严重度，但分开计数让
    // 结构自解释，也避免以后调整严重度时两处口径打架。
    final byCodeCounts = <String, int>{};
    final byCodeSeverity = <String, String>{};
    for (final finding in findings) {
      final key = '${finding.code}|${finding.severity.name}';
      byCodeCounts[key] = (byCodeCounts[key] ?? 0) + 1;
      byCodeSeverity[key] = finding.severity.name;
    }
    final byCodeKeys = byCodeCounts.keys.toList()
      ..sort((a, b) {
        final byCount = byCodeCounts[b]!.compareTo(byCodeCounts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final byCode = <Map<String, Object?>>[
      for (final key in byCodeKeys)
        <String, Object?>{
          'code': key.split('|').first,
          'severity': byCodeSeverity[key],
          'count': byCodeCounts[key],
        },
    ];

    final filterNotes = <String>[
      if (severityFilter != null) '严重度 ${severityFilter.name}',
      if (subjectKey != null) '学科 $subjectKey',
    ];
    final filterNote =
        filterNotes.isEmpty ? '' : '（只看${filterNotes.join("、")}）';
    final String summary;
    if (rows.isEmpty) {
      summary = subjectKey == null
          ? '题库里还没有题目，没得体检。'
          : '题库里没有学科 $subjectKey 的题目，没得体检。';
    } else {
      final cleanText = '干净题 ${auditSummary.cleanQuestionCount} 道'
          '（${(auditSummary.cleanRatio * 100).toStringAsFixed(0)}%）';
      if (findings.isEmpty) {
        summary = '体检了 ${rows.length} 道题$filterNote，这个范围内没发现硬伤。'
            '$cleanText。';
      } else {
        final parts = <String>[
          if (report.errorCount > 0) '${report.errorCount} 个错误',
          if (report.warningCount > 0) '${report.warningCount} 个警告',
          if (report.infoCount > 0) '${report.infoCount} 个提示',
        ];
        final truncated = shown.length < findings.length;
        final topOffender = auditSummary.topOffenders.isEmpty
            ? null
            : auditSummary.topOffenders.first;
        final priorityText = topOffender == null
            ? ''
            : '，优先修：'
                '${questionSerialLabel(serials[topOffender.questionId])}'
                '（分数 ${topOffender.priorityScore}）';
        summary = '体检了 ${rows.length} 道题$filterNote：'
            '共 ${findings.length} 条结论（${parts.join("、")}）'
            '${truncated ? "，这里列出前 ${shown.length} 条" : ""}；'
            '$cleanText$priorityText。只报不改——要修哪道题由你决定。';
      }
    }

    final modelResult = <String, Object?>{
      'questions_checked': rows.length,
      'findings_total': findings.length,
      'counts': <String, Object?>{
        'error': report.errorCount,
        'warning': report.warningCount,
        'info': report.infoCount,
      },
      'by_code': byCode,
      'findings': <Map<String, Object?>>[
        for (final finding in shown)
          <String, Object?>{
            'question_id': finding.questionId,
            'serial_no': serials[finding.questionId],
            'code': finding.code,
            'severity': finding.severity.name,
            'message_zh': finding.messageZh,
            'evidence': finding.evidence,
          },
      ],
      'truncated': shown.length < findings.length,
      'limit': limit,
      'filters': <String, Object?>{
        'severity': severityFilter?.name,
        'subject_key': subjectKey,
      },
      'is_clean': findings.isEmpty,
      'summary': auditSummary.toJson(),
      'priority_note': '优先级分数未标定：只用于相对排序，不是质量结论。',
      'note': '只读体检：判据是确定性的，不调模型；没发现问题不代表证明没问题。',
    };

    return ToolResult(ok: true, summary: summary, modelResult: modelResult);
  }

  static QuestionAuditSeverity? _severityOf(String text) {
    switch (text.trim().toLowerCase()) {
      case 'error':
        return QuestionAuditSeverity.error;
      case 'warning':
        return QuestionAuditSeverity.warning;
      case 'info':
        return QuestionAuditSeverity.info;
    }
    return null;
  }
}
