/// 内容包（工作区 `content-store/<subject>/Q-…/`）到产品域的只读模型。
///
/// 为什么单独一层：内容包是工作区的 JSON 契约（`content-schema/schema/
/// base-question.schema.json` + `panel-common.schema.json`），产品代码不能到处
/// 直接 `jsonDecode` 后随手取键；把「字段读法 + 缺省值」收在一个纯 Dart 类里，
/// 导入服务、阅读器与测试才对同一份契约说话。
///
/// 三条边界（`CONTENT-PACKAGE-IMPORT-2026-11-15.md` §2）：
///
///  * **只读**：这里不写库、不碰文件；读目录由 `data/content/
///    content_package_reader.dart` 负责，写库由 `ContentPackageImportService`。
///  * **答案只来自 Source**：`answerParts` 逐字取 `answer.parts[].value`；
///    `solutions` 保留 `kind` 与 `render_student_analysis` 原值，导入侧据此
///    决定是否写入产品 `questions.solution`（AI 生成的解析不进产品）。
///  * **不复制正文进引用**：本模型只在导入过程中使用；落库的 `content_refs`
///    只放 id / hash / 摘要，正文仍只在内容包与产品 `questions` 各存一份。
///
/// DAG 节点与错因直接复用 `DagFlashcardGenerator` 的输入契约
/// （[DagFlashcardNode] / [DagFlashcardErrorCause]）：卡片生成的输入只有一种
/// 形状，避免在内容包模型里再造一套再逐字段搬运。
library;

import 'dag_flashcard_generator.dart';

/// 产品支持的内容包 schema 版本（`question.json.schema_version`）。
const String kContentPackageBaseQuestionSchema =
    'furnace.content.base-question/1';

/// 一条答案分项（`answer.parts[]`）。
class ContentPackageAnswerPart {
  const ContentPackageAnswerPart({
    required this.part,
    required this.value,
    required this.format,
  });

  /// 小问标签：`all` 表示单问，其余如 `(1)` / `16`。
  final String part;

  /// 答案值（LaTeX 原样保留）。
  final String value;

  /// `latex` / `text` / `selection`。
  final String format;

  bool get isBlank => value.trim().isEmpty;
}

/// 一条解析记录（`solutions[]`）。
class ContentPackageSolution {
  const ContentPackageSolution({
    required this.id,
    required this.kind,
    required this.bodyMd,
    required this.usePolicy,
    required this.renderStudentAnalysis,
    this.sourceKind,
  });

  final String id;

  /// `official_source` / `ai_generated` / `multi_method`。
  final String kind;

  final String bodyMd;

  /// `source_reference_only` / `teaching_reference`。
  final String usePolicy;

  /// 内容包是否允许在学生视图渲染这段原文（只有《高考试题分析》来源为 true）。
  final bool renderStudentAnalysis;

  /// `gaokao_analysis_book` / `exam_paper_analysis` / `third_party_answer` / `ai`。
  final String? sourceKind;

  bool get isSourceDerived => kind == 'official_source';
}

/// 一张配图（`figures[]`，`media_asset`）。
class ContentPackageFigure {
  const ContentPackageFigure({
    required this.id,
    required this.role,
    required this.path,
    this.placeholderN,
  });

  final String id;
  final String role;
  final String path;

  /// 替换题干里的 `[图N]` 占位（可空）。
  final int? placeholderN;
}

/// 一个内容知识节点（`classification.knowledge[]`）。
class ContentPackageKnowledgeNode {
  const ContentPackageKnowledgeNode({
    required this.nodeId,
    required this.label,
    required this.role,
    required this.source,
  });

  /// C 层内容知识节点 id（`kp-<slug>`）。它是 `content_refs.content_id`。
  final String nodeId;

  final String label;

  /// `primary` / `prerequisite` / `upper` / `related`。
  final String role;

  /// `mindnet` / `manual` / `extracted` / `ai`。
  final String source;
}

/// 一个子问（`classification.subquestions[]`）。
class ContentPackageSubquestion {
  const ContentPackageSubquestion({required this.part, required this.points});

  final String part;

  /// Source 未给分值时为 null（内容契约允许 null，禁止猜分）。
  final double? points;
}

/// 一份内容包（L1 Base Question + 可选 L2 学科板）。
class ContentPackage {
  const ContentPackage({
    required this.contentId,
    required this.subject,
    required this.title,
    required this.stem,
    required this.stemFormat,
    required this.answerParts,
    required this.questionType,
    required this.sourceLevel,
    required this.sourceLabel,
    required this.solutions,
    required this.figures,
    required this.knowledge,
    required this.capability,
    required this.subquestions,
    required this.dagNodes,
    required this.errorCauses,
    this.schemaVersion,
    this.version,
    this.contentHash,
    this.boardVersion,
    this.boardHash,
    this.answerTrust,
    this.answerSourceId,
    this.difficulty,
    this.difficultySource,
    this.year,
    this.region,
    this.sourceUrl,
    this.reviewStatus,
    this.sourceAnalysisVisible = false,
    this.scoringTotalPoints,
    this.scoringSource,
  });

  /// C 层题目 id（`Q-PH0001`）。
  final String contentId;

  /// 学科键（`physics` / `math` / `chinese`）。
  final String subject;

  /// 题名建议（内容包 `title.suggested`）。导入时只填空，不覆盖用户改过的题名。
  final String title;

  final String stem;

  /// `markdown+latex` / `plain` 等原值。
  final String stemFormat;

  final List<ContentPackageAnswerPart> answerParts;

  /// 卷面题型（`single_choice` / `multi_choice` / `fill_blank` / `solution` /
  /// `open`），来自 `classification.content_type.paper_form`。
  final String questionType;

  final String sourceLevel;
  final String sourceLabel;
  final List<ContentPackageSolution> solutions;
  final List<ContentPackageFigure> figures;
  final List<ContentPackageKnowledgeNode> knowledge;

  /// 能力点代码（`A1`…`A10`）。
  final List<String> capability;

  final List<ContentPackageSubquestion> subquestions;

  /// Thinking DAG 节点（可成卡子集，形状与卡片生成器一致）。
  final List<DagFlashcardNode> dagNodes;

  /// 错因（可成卡子集）。
  final List<DagFlashcardErrorCause> errorCauses;

  final String? schemaVersion;

  /// `provenance.version`（整数，单调 +1）。
  final int? version;

  /// `provenance.content_hash`（sha256）。与 [version] 成对或都不给。
  final String? contentHash;

  /// `panels.board_refs.<subject>.version`。
  final int? boardVersion;

  /// `panels.board_refs.<subject>.content_hash`。
  final String? boardHash;

  /// `answer.official_trust`（A/B/C/D 分级），只进引用摘要，不参与排序。
  final String? answerTrust;

  /// `answer.answer_source.id`（`E-*` 证据 id）。
  final String? answerSourceId;

  final double? difficulty;

  /// `prior` / `ai` / `manual` / `test`；产品只认前三个。
  final String? difficultySource;

  final int? year;
  final String? region;
  final String? sourceUrl;
  final String? reviewStatus;

  /// 内容包的解析渲染策略：只有 `true` 时来源解析原文才允许进产品 `solution`。
  final bool sourceAnalysisVisible;

  final double? scoringTotalPoints;

  /// `official` / `ai_derived` / `human_derived` / `none`。
  final String? scoringSource;

  /// 单问用原值；多问按「小问标签 + 值」逐行拼（不补写任何 Source 没有的文字）。
  String? get formattedAnswer {
    final parts = [
      for (final part in answerParts)
        if (!part.isBlank) part,
    ];
    if (parts.isEmpty) {
      return null;
    }
    if (parts.length == 1) {
      // 单问不补小问标签：`part` 可能是卷面题号（语文第 16 题），补上去会像
      // 自己造了一个 Source 没有的编号。
      return parts.single.value.trim();
    }
    return [
      for (final part in parts)
        '${part.part.trim()} ${part.value.trim()}'.trim(),
    ].join('\n');
  }

  /// 题干是否声明为 markdown / LaTeX（产品 `questions.text_format`）。
  bool get isMarkdown =>
      stemFormat.contains('markdown') || stemFormat.contains('latex');

  /// 从 `question.json`（+ 可选 `boards/<subject>-board.json`）解析。
  ///
  /// 解析是**严格**的：schema 版本不认识、id 缺失、题干缺失、board 的
  /// `question_id` 与 question 不一致都抛 [FormatException]——这些错继续往下走
  /// 只会在产品库里留下对不上的题。
  factory ContentPackage.fromJson(
    Map<String, Object?> question, {
    Map<String, Object?>? board,
  }) {
    final schemaVersion = _strOrNull(question['schema_version']);
    if (schemaVersion != null &&
        schemaVersion != kContentPackageBaseQuestionSchema) {
      throw FormatException(
        '不认识的内容包 schema_version：$schemaVersion（期望 '
        '$kContentPackageBaseQuestionSchema）',
      );
    }
    final contentId = _strOrNull(question['id'])?.trim() ?? '';
    if (contentId.isEmpty) {
      throw const FormatException('question.json 缺少 id');
    }
    final subject = _strOrNull(question['subject'])?.trim() ?? '';
    if (subject.isEmpty) {
      throw FormatException('$contentId 的 question.json 缺少 subject');
    }
    final stemJson = _map(question['stem'], 'stem');
    final stem = _strOrNull(stemJson['text'])?.trim() ?? '';
    if (stem.isEmpty) {
      throw FormatException('$contentId 的题干（stem.text）为空');
    }
    if (board != null) {
      final boardQuestionId =
          _strOrNull(_map(board, 'board')['question_id'])?.trim();
      if (boardQuestionId != null &&
          boardQuestionId.isNotEmpty &&
          boardQuestionId != contentId) {
        throw FormatException(
          'board.question_id=$boardQuestionId 与 question.id=$contentId 不一致',
        );
      }
    }

    final provenance = _map(question['provenance'], 'provenance');
    final panels = _map(question['panels'], 'panels');
    final boardRefs = _map(panels['board_refs'], 'panels.board_refs');
    final boardRef = _map(boardRefs[subject], 'panels.board_refs.$subject');

    final answer = _map(question['answer'], 'answer');
    final answerSource = _map(answer['answer_source'], 'answer.answer_source');

    final classification = _map(question['classification'], 'classification');
    final contentType = _map(
      classification['content_type'],
      'classification.content_type',
    );
    final meta = _map(question['meta'], 'meta');
    final difficulty = _map(meta['difficulty'], 'meta.difficulty');
    final scoring = _map(question['scoring'], 'scoring');
    final renderPolicy = _map(
      question['analysis_render_policy'],
      'analysis_render_policy',
    );

    final boardJson = board == null ? null : _map(board, 'board');
    final dag = boardJson == null
        ? const <String, Object?>{}
        : _map(boardJson['thinking_dag'], 'thinking_dag');

    return ContentPackage(
      contentId: contentId,
      subject: subject,
      title:
          _strOrNull(_map(question['title'], 'title')['suggested'])?.trim() ??
              '',
      stem: stem,
      stemFormat: _strOrNull(stemJson['format']) ?? 'plain',
      answerParts: [
        for (final raw in _list(answer['parts']))
          ContentPackageAnswerPart(
            part: _strOrNull(_map(raw, 'answer.parts[]')['part']) ?? '',
            value: _strOrNull(_map(raw, 'answer.parts[]')['value']) ?? '',
            format: _strOrNull(_map(raw, 'answer.parts[]')['format']) ?? 'text',
          ),
      ],
      questionType: _questionTypeOf(_strOrNull(contentType['paper_form'])),
      sourceLevel: _strOrNull(meta['source_level'])?.trim() ?? 'unknown',
      sourceLabel: _strOrNull(meta['source_label'])?.trim() ?? '',
      solutions: [
        for (final raw in _list(question['solutions'])) _solutionOf(raw),
      ],
      figures: [
        for (final raw in _list(question['figures'])) _figureOf(raw),
      ],
      knowledge: [
        for (final raw in _list(classification['knowledge'])) _knowledgeOf(raw),
      ],
      capability: [
        for (final raw in _list(classification['capability']))
          if ((_strOrNull(_map(raw, 'capability[]')['code']) ?? '').isNotEmpty)
            _strOrNull(_map(raw, 'capability[]')['code'])!,
      ],
      subquestions: [
        for (final raw in _list(classification['subquestions']))
          ContentPackageSubquestion(
            part: _strOrNull(_map(raw, 'subquestions[]')['part']) ?? '',
            points: _doubleOrNull(_map(raw, 'subquestions[]')['points']),
          ),
      ],
      dagNodes: [
        for (final raw in _list(dag['nodes'])) _dagNodeOf(raw),
      ],
      errorCauses: [
        for (final raw
            in _list(_map(boardJson?['error_causes'], 'error_causes')['items']))
          _errorCauseOf(raw),
      ],
      schemaVersion: schemaVersion,
      version: _intOrNull(provenance['version']),
      contentHash: _strOrNull(provenance['content_hash']),
      boardVersion: _intOrNull(boardRef['version']),
      boardHash: _strOrNull(boardRef['content_hash']),
      answerTrust: _strOrNull(answer['official_trust']),
      answerSourceId: _strOrNull(answerSource['id']),
      difficulty: _doubleOrNull(difficulty['value']),
      difficultySource: _strOrNull(difficulty['source']),
      year: _intOrNull(meta['year']),
      region: _strOrNull(meta['region']),
      sourceUrl: _strOrNull(meta['source_url']),
      reviewStatus: _strOrNull(_map(question['review'], 'review')['status']),
      sourceAnalysisVisible: renderPolicy['source_analysis_visible'] == true,
      scoringTotalPoints: _doubleOrNull(scoring['total_points']),
      scoringSource: _strOrNull(scoring['source']),
    );
  }

  static ContentPackageSolution _solutionOf(Object? raw) {
    final json = _map(raw, 'solutions[]');
    return ContentPackageSolution(
      id: _strOrNull(json['id']) ?? '',
      kind: _strOrNull(json['kind']) ?? '',
      bodyMd: _strOrNull(json['body_md']) ?? '',
      usePolicy: _strOrNull(json['use_policy']) ?? '',
      renderStudentAnalysis: json['render_student_analysis'] == true,
      sourceKind: _strOrNull(json['source_kind']),
    );
  }

  static ContentPackageFigure _figureOf(Object? raw) {
    final json = _map(raw, 'figures[]');
    return ContentPackageFigure(
      id: _strOrNull(json['id']) ?? '',
      role: _strOrNull(json['role']) ?? '',
      path: _strOrNull(json['path']) ?? '',
      placeholderN: _intOrNull(json['place_holder_n']),
    );
  }

  static ContentPackageKnowledgeNode _knowledgeOf(Object? raw) {
    final json = _map(raw, 'classification.knowledge[]');
    return ContentPackageKnowledgeNode(
      nodeId: _strOrNull(json['node_id'])?.trim() ?? '',
      label: _strOrNull(json['label'])?.trim() ?? '',
      role: _strOrNull(json['role']) ?? '',
      source: _strOrNull(json['source']) ?? '',
    );
  }

  static DagFlashcardNode _dagNodeOf(Object? raw) {
    final json = _map(raw, 'thinking_dag.nodes[]');
    return DagFlashcardNode(
      id: _strOrNull(json['id']) ?? '',
      kind: _strOrNull(json['kind']) ?? '',
      role: _strOrNull(json['role']) ?? '',
      label: _strOrNull(json['label']) ?? '',
      body: _strOrNull(json['body']) ?? '',
      formulas: [
        for (final formula in _list(json['formulas'])) formula.toString(),
      ],
      keyQuantities: [
        for (final quantity in _list(json['key_quantities']))
          quantity.toString(),
      ],
      result: _strOrNull(json['result']) ?? '',
    );
  }

  static DagFlashcardErrorCause _errorCauseOf(Object? raw) {
    final json = _map(raw, 'error_causes.items[]');
    return DagFlashcardErrorCause(
      code: _strOrNull(json['code']) ?? '',
      category: _strOrNull(json['category']) ?? '',
      symptom: _strOrNull(json['symptom']) ?? '',
      rootCause: _strOrNull(json['root_cause']) ?? '',
      diagnosticQuestion: _strOrNull(json['diagnostic_question']) ?? '',
      remediation: _strOrNull(json['remediation']) ?? '',
      locateNode: _strOrNull(json['locate_node']),
    );
  }

  static String _questionTypeOf(String? paperForm) {
    const allowed = <String>{
      'single_choice',
      'multi_choice',
      'fill_blank',
      'solution',
      'open',
    };
    final value = paperForm?.trim() ?? '';
    return allowed.contains(value) ? value : 'solution';
  }
}

Map<String, Object?> _map(Object? value, String path) {
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw FormatException('$path 应为 JSON 对象，实际是 ${value.runtimeType}');
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String? _strOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _intOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString().trim());
}

double? _doubleOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString().trim());
}
