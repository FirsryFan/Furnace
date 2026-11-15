/// 内容包 → 产品题库（Questions / KnowledgePoints / ObjectTags / ContentRefs）
/// 的导入服务（task-80，2026-11-15）。
///
/// 为什么需要它：内容包（工作区 `content-store/`）有题目、答案、知识点与
/// Thinking DAG，产品库的 `questions` 却一条 `Q-` 题都没有（契约 §1.6）。真正
/// 缺的不是字段映射，而是一条**受控的写入口**：幂等、可回滚、答案只来自
/// Source、不自动造标签、不把内容正文复制进引用表。
///
/// 输入有两种：
///  * 已解析的 [ContentPackage]（`ContentPackage.fromJson`，或
///    `data/content/content_package_reader.dart` 读目录）；
///  * 本服务不做文件 IO，也不做 UI/Provider 接线（任务明确不改 UI）。
///
/// 写库映射（`CONTENT-PACKAGE-IMPORT-2026-11-15.md` §3 是完整表）：
///
///  * `question.json.answer.parts[].value` → `questions.answer`（逐字；AI 不补写）；
///  * `stem.text` → `questions.stem`；`stem.format` → `questions.text_format`；
///  * `classification.content_type.paper_form` → `questions.question_type`；
///  * `meta.*` → `subject_key` / `source_level` / `source_label` / `year` /
///    `region` / `source_url`；`meta.difficulty` → `difficulty` + `difficulty_source`；
///  * `classification.knowledge[].node_id` → `knowledge_points`
///    （幂等：先按 `content_refs(content_id=node_id, object_type=knowledge_point)`
///    复用，绝不用标题去猜产品已有的知识点）；
///  * `content_refs`：`(Q-id, question, q-id, source_package)` +
///    `(kp-node-id, knowledge_point, kp-uuid, node)`；只存 id/版本/hash/摘要，
///    **不存题干/答案/解析正文**；
///  * 解析原文（`questions.solution`）只在内容包 `analysis_render_policy.
///    source_analysis_visible=true` 且该条 `render_student_analysis=true` 时写入
///    ——用户 2026-11-15 规则「除《高考试题分析》外不单独显示解析，DAG 即解析」；
///  * 标签只**引用已有** `Tags.path`/`Tags.id`：解析不到就记 `missing_tag`
///    跳过，绝不自动建标签；
///  * DAG 卡（可选）调用 [DagFlashcardGenerator]：只对已导入且有产品知识点的
///    题生成；`dryRun` 默认 true，apply 也不建 `card_states` / `review_logs`。
///
/// 幂等与换版：
///  * 同一 `content_id` 第二次导入不会新增题目（指纹去重）或重复引用；
///  * `provenance.version/content_hash` 变了 = 内容换版：引用**原地更新**
///    （`ContentRefRepository` 把旧值写进 `metadata_json.previous_*`）；
///  * 若换版导致题干变了（产品题只追加，不能原地改题干），新题入库后旧
///    `source_package` 引用会被删掉、改指向新题——引用跟着内容走，不复制正文。
///
/// 事务与安全：
///  * 整个导入（题目/知识点/标签/引用/卡片）在一个 `db.transaction` 里；任一步
///    抛错全部回滚，不留半批；
///  * 本类不是 CLI、不被 UI/Provider 调用；调用方必须传**临时库或用户明确授权
///    且已备份的库**（测试一律 `AppDatabase.forTesting(NativeDatabase.memory())`）。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/content_ref_repository.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import 'content_package.dart';
import 'content_ref_vocab.dart';
import 'dag_flashcard_generator.dart';

/// 默认「学科 → 标签路径」候选。只是**候选**：库里没有这条路径就跳过，绝不建。
const Map<String, String> kDefaultSubjectTagPaths = <String, String>{
  'physics': '文化课/学科/物理',
  'math': '文化课/学科/数学',
  'chinese': '文化课/学科/语文',
  'chemistry': '文化课/学科/化学',
  'biology': '文化课/学科/生物',
  'english': '文化课/学科/英语',
};

/// 默认「卷面题型 → 标签路径」候选（同样只引用、不创建）。
const Map<String, String> kDefaultQuestionTypeTagPaths = <String, String>{
  'single_choice': '文化课/题型/单选题',
  'multi_choice': '文化课/题型/多选题',
  'fill_blank': '文化课/题型/填空题',
  'solution': '文化课/题型/解答题',
  'open': '文化课/题型/开放题',
};

/// `skipped` 的原因词表（报告与测试直接引用这些常量）。
abstract final class ContentPackageSkipReason {
  /// 内容包声明不渲染来源解析：产品 `solution` 留空（DAG 承担解析）。
  static const String solutionSuppressed =
      'solution_suppressed_by_analysis_policy';

  /// 有来源解析，但内容包不允许在学生视图渲染它。
  static const String solutionNotRenderable = 'solution_not_renderable';

  /// 内容包里没有来源解析（只有 AI 生成的解析不算）。
  static const String solutionMissingSource = 'solution_missing_source';

  /// 内容包给的是 AI 生成/多解解析：不进产品 `questions.solution`。
  static const String solutionNotSource = 'solution_not_source_derived';

  /// 内容包没有可用的答案分项。
  static const String answerMissing = 'answer_missing';

  /// `provenance.version` 与 `content_hash` 只给了一个（契约禁止半对）。
  static const String incompleteProvenance = 'incomplete_content_provenance';

  /// 难度不在产品 1–10 区间，未写入（不夹取、不猜）。
  static const String difficultyOutOfRange = 'difficulty_out_of_range';

  /// 产品 `questions` 没有配图列 / 本服务不复制图片：图片只留在内容包。
  static const String figureNotImported = 'figure_not_imported';

  /// 图片条目没有路径。
  static const String figurePathMissing = 'figure_path_missing';

  /// 请求的标签路径/ id 在 `tags` 里不存在（只记录，不创建）。
  static const String missingTag = 'missing_tag';

  /// 产品知识点里没有这个显式映射的目标（不建悬空引用）。
  static const String unknownMappedKnowledgePoint =
      'unknown_mapped_knowledge_point';

  /// 内容知识节点没有 `label`，不能建产品知识点。
  static const String knowledgeLabelMissing = 'knowledge_label_missing';

  /// 内容知识节点没有产品知识点映射，且调用方不允许自动创建。
  static const String knowledgePointUnmapped = 'knowledge_point_unmapped';

  /// 换版后旧题引用被删除并改指向新题。
  static const String staleQuestionRefRemoved = 'stale_question_ref_removed';

  /// 产品题只追加：同名题干但新版本答案/解析不同时，`questions` 不原地改写。
  static const String questionBodyNotUpdated = 'question_body_not_updated';

  /// 产品题名已存在且与内容包建议名不同：不覆盖用户改过的题名。
  static const String titleNotOverwritten = 'title_not_overwritten';

  /// 要求生成卡，但没有可挂的产品知识点。
  static const String cardMissingKnowledgePoint =
      'card_missing_knowledge_point';

  /// 显式指定的生成卡知识点在产品库里不存在。
  static const String cardUnknownKnowledgePoint =
      'card_unknown_knowledge_point';

  /// 内容是 L1-only：没有 DAG 节点/错因可生成卡。
  static const String boardEmpty = 'board_empty';
}

/// 一次导入的结局。
enum ContentPackageImportStatus {
  /// 全部映射完成，没有跳过项。
  imported,

  /// 题目已导入，但有被有意跳过/只记录的部分（缺失标签、被策略抑制的解析…）。
  importedWithSkips,

  /// 输入不合法（id/题干），没有写任何一行。
  blocked;

  String get wireValue => name;
}

/// 一个被跳过的映射项。
class ContentPackageImportSkip {
  const ContentPackageImportSkip({required this.code, required this.detail});

  final String code;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'detail': detail,
      };

  @override
  String toString() => '$code（$detail）';
}

/// 一条标签引用的解析结果：命中 = `tagId` 非空；缺失 = `missing` 为 true。
class ContentPackageTagImport {
  const ContentPackageTagImport({
    required this.dimension,
    required this.requested,
    required this.objectType,
    required this.objectId,
    this.tagId,
    this.missing = false,
  });

  /// `subject` / `question_type` / `explicit` / `knowledge:<node-id>`。
  final String dimension;

  /// 请求的标签路径或 id（trim 后原样保留，便于人工对照）。
  final String requested;

  /// 挂载对象类型（`question` / `knowledge_point`）。
  final String objectType;

  final String objectId;

  final String? tagId;

  final bool missing;

  Map<String, Object?> toJson() => <String, Object?>{
        'dimension': dimension,
        'requested': requested,
        'object_type': objectType,
        'object_id': objectId,
        'tag_id': tagId,
        'missing': missing,
      };
}

/// 一条内容知识节点 → 产品知识点的映射结果。
class ContentPackageKnowledgeImport {
  const ContentPackageKnowledgeImport({
    required this.contentNodeId,
    required this.label,
    required this.role,
    required this.productKnowledgePointId,
    required this.created,
    required this.mapped,
  });

  final String contentNodeId;
  final String label;
  final String role;

  /// 产品 `knowledge_points.id`（`kp-<uuid>`），不是内容节点 id。
  final String productKnowledgePointId;

  /// 本次是否新建了产品知识点（false = 复用已有/显式映射）。
  final bool created;

  /// 是否来自调用方的显式映射（`knowledgePointIdByNodeId`）。
  final bool mapped;

  Map<String, Object?> toJson() => <String, Object?>{
        'content_node_id': contentNodeId,
        'label': label,
        'role': role,
        'product_knowledge_point_id': productKnowledgePointId,
        'created': created,
        'mapped': mapped,
      };
}

/// 一次导入的完整报告（不写日志文件、不建第二份状态表）。
class ContentPackageImportResult {
  const ContentPackageImportResult({
    required this.contentId,
    required this.status,
    required this.questionId,
    required this.serialNo,
    required this.questionCreated,
    required this.questionRefId,
    required this.contentVersion,
    required this.contentHash,
    required this.knowledgePoints,
    required this.tags,
    required this.skipped,
    required this.blocked,
    this.cardPlan,
  });

  /// 输入不合法：没有写任何一行。
  factory ContentPackageImportResult.blocked({
    required String contentId,
    required List<String> blocked,
  }) {
    return ContentPackageImportResult(
      contentId: contentId,
      status: ContentPackageImportStatus.blocked,
      questionId: null,
      serialNo: null,
      questionCreated: false,
      questionRefId: null,
      contentVersion: null,
      contentHash: null,
      knowledgePoints: const <ContentPackageKnowledgeImport>[],
      tags: const <ContentPackageTagImport>[],
      skipped: const <ContentPackageImportSkip>[],
      blocked: List<String>.unmodifiable(blocked),
    );
  }

  final String contentId;
  final ContentPackageImportStatus status;

  /// 产品 `questions.id`（`q-<uuid>`）；blocked 时为 null。
  final String? questionId;

  final int? serialNo;
  final bool questionCreated;

  /// `content_refs.id`（`cref-<uuid>`）的 source_package 引用。
  final String? questionRefId;

  final int? contentVersion;
  final String? contentHash;

  final List<ContentPackageKnowledgeImport> knowledgePoints;
  final List<ContentPackageTagImport> tags;
  final List<ContentPackageImportSkip> skipped;

  final List<String> blocked;

  /// 可选生成的 DAG 卡计划/结果（`generateCards=false` 时为 null）。
  final DagFlashcardPlan? cardPlan;

  /// 本次「应存在」的内容引用数量：题目 1 + 知识点 N + apply 时新建的卡。
  int get contentRefCount =>
      (questionRefId == null ? 0 : 1) +
      knowledgePoints.length +
      (cardPlan?.created ?? 0);

  List<ContentPackageTagImport> get missingTags => <ContentPackageTagImport>[
        for (final tag in tags)
          if (tag.missing) tag,
      ];

  Map<String, Object?> toJson() => <String, Object?>{
        'content_id': contentId,
        'status': status.wireValue,
        'question_id': questionId,
        'serial_no': serialNo,
        'question_created': questionCreated,
        'question_ref_id': questionRefId,
        'content_version': contentVersion,
        'content_hash': contentHash,
        'content_ref_count': contentRefCount,
        'knowledge_points': <Map<String, Object?>>[
          for (final point in knowledgePoints) point.toJson(),
        ],
        'tags': <Map<String, Object?>>[
          for (final tag in tags) tag.toJson(),
        ],
        'skipped': <Map<String, Object?>>[
          for (final skip in skipped) skip.toJson(),
        ],
        'blocked': blocked,
        'card_plan': cardPlan?.toJson(),
      };
}

/// 导入选项。默认值只做**只读候选**：所有标签路径都必须已在 `tags` 里。
class ContentPackageImportOptions {
  const ContentPackageImportOptions({
    this.createKnowledgePoints = true,
    this.knowledgePointIdByNodeId = const <String, String>{},
    this.deriveTagPaths = true,
    this.subjectTagPaths = kDefaultSubjectTagPaths,
    this.questionTypeTagPaths = kDefaultQuestionTypeTagPaths,
    this.extraQuestionTagPaths = const <String>[],
    this.extraKnowledgeTagPathsByNodeId = const <String, List<String>>{},
    this.generateCards = false,
    this.cardsDryRun = true,
    this.cardKnowledgePointId,
    this.now,
  });

  /// 内容节点没映射时是否新建产品知识点。
  ///
  /// 默认 true（任务要三题 → KnowledgePoints）；但只对**内容包里真的写了
  /// `classification.knowledge[]` 的节点**建，无节点就不造。设 false 时只认
  /// [knowledgePointIdByNodeId]。
  final bool createKnowledgePoints;

  /// 人工映射：内容节点 id（`kp-*`）→ 已有产品 `knowledge_points.id`。
  /// 给了就优先用它，不新建。
  final Map<String, String> knowledgePointIdByNodeId;

  /// 是否从内容包推导默认标签候选（学科/题型/知识点）。
  final bool deriveTagPaths;

  /// 学科 → 标签路径候选（默认 `文化课/学科/<中文>`；按学科键覆盖）。
  final Map<String, String> subjectTagPaths;

  /// 卷面题型 → 标签路径候选（默认 `文化课/题型/<中文题型>`）。
  final Map<String, String> questionTypeTagPaths;

  /// 额外挂到题目上的标签路径（或 `tag-<uuid>`）。
  final List<String> extraQuestionTagPaths;

  /// 额外挂到某个内容知识节点对应产品知识点上的标签路径。
  final Map<String, List<String>> extraKnowledgeTagPathsByNodeId;

  /// 是否尝试 DAG/错因 → 闪存卡。
  final bool generateCards;

  /// 卡片生成默认 dry run（只计划，不写 `card_templates`）。
  final bool cardsDryRun;

  /// 显式指定卡片要挂的产品知识点；不传则用内容包 `role=primary` 知识节点。
  final String? cardKnowledgePointId;

  /// 注入时钟（测试固定 `updated_at` 用）。
  final DateTime? now;
}

/// 内容包 → 产品题库的导入服务。
///
/// 注入的仓储/生成器必须与 [db] 是同一个库：事务回滚只对同一个数据库连接生效。
class ContentPackageImportService {
  ContentPackageImportService(
    AppDatabase db, {
    QuestionRepository? questions,
    TagRepository? tags,
    ContentRefRepository? contentRefs,
    AnkiRepository? anki,
    DagFlashcardGenerator? cards,
  })  : _db = db,
        _questions = questions ?? QuestionRepository(db),
        _tags = tags ?? TagRepository(db),
        _contentRefs = contentRefs ?? ContentRefRepository(db),
        _anki = anki ?? AnkiRepository(db),
        _cards = cards ?? DagFlashcardGenerator(db);

  final AppDatabase _db;
  final QuestionRepository _questions;
  final TagRepository _tags;
  final ContentRefRepository _contentRefs;
  final AnkiRepository _anki;
  final DagFlashcardGenerator _cards;

  /// 产品只认 `Q-…` 形态的内容题 id；`QSET-…` 是套卷，不是一道题。
  static final RegExp _questionContentId =
      RegExp(r'^Q-[A-Za-z0-9][A-Za-z0-9-]*$');

  /// 导出一份内容包。整体一个事务：失败抛错并回滚，不返回半批报告。
  Future<ContentPackageImportResult> importPackage(
    ContentPackage package, {
    ContentPackageImportOptions options = const ContentPackageImportOptions(),
  }) {
    final contentId = package.contentId.trim();
    final blocked = <String>[];
    if (!_questionContentId.hasMatch(contentId)) {
      blocked.add('invalid_question_content_id: $contentId');
    }
    if (package.stem.trim().isEmpty) {
      blocked.add('empty_stem');
    }
    if (blocked.isNotEmpty) {
      return Future<ContentPackageImportResult>.value(
        ContentPackageImportResult.blocked(
          contentId: contentId,
          blocked: blocked,
        ),
      );
    }
    return _db.transaction(
      () => _import(package, contentId: contentId, options: options),
    );
  }

  Future<ContentPackageImportResult> _import(
    ContentPackage package, {
    required String contentId,
    required ContentPackageImportOptions options,
  }) async {
    final now = options.now ?? DateTime.now();
    final skips = <ContentPackageImportSkip>[];
    final tagResults = <ContentPackageTagImport>[];

    // ---- 1) 标签候选：只解析、只引用；写挂载边在题目/知识点落库之后 ----
    final subjectTagPath = options.deriveTagPaths
        ? _nonEmpty(options.subjectTagPaths[package.subject])
        : null;
    final questionTagCandidates = <_TagCandidate>[
      if (subjectTagPath != null)
        _TagCandidate(dimension: 'subject', path: subjectTagPath),
    ];
    if (options.deriveTagPaths) {
      final typePath = _nonEmpty(
        options.questionTypeTagPaths[package.questionType],
      );
      if (typePath != null) {
        questionTagCandidates.add(
          _TagCandidate(dimension: 'question_type', path: typePath),
        );
      }
    }
    for (final path in options.extraQuestionTagPaths) {
      final explicitPath = _nonEmpty(path);
      if (explicitPath != null) {
        questionTagCandidates.add(
          _TagCandidate(dimension: 'explicit', path: explicitPath),
        );
      }
    }
    final questionTagIds = <String>{};
    final resolvedQuestionTags = <({_TagCandidate candidate, String tagId})>[];
    final missingQuestionTags = <_TagCandidate>[];
    for (final candidate in _distinctCandidates(questionTagCandidates)) {
      final tagId = await _resolveTagId(candidate: candidate, skips: skips);
      if (tagId == null) {
        missingQuestionTags.add(candidate);
      } else if (questionTagIds.add(tagId)) {
        resolvedQuestionTags.add((candidate: candidate, tagId: tagId));
      }
    }

    // ---- 2) 内容知识节点 → 产品知识点（幂等：先按 content_refs 复用） ----
    final knowledgeResults = <ContentPackageKnowledgeImport>[];
    for (final node in package.knowledge) {
      final nodeId = node.nodeId.trim();
      if (nodeId.isEmpty) {
        _addSkip(skips, ContentPackageSkipReason.knowledgeLabelMissing,
            '节点缺少 node_id');
        continue;
      }
      final label = node.label.trim();
      final mappedId = _nonEmpty(options.knowledgePointIdByNodeId[nodeId]);
      String? productId;
      var created = false;
      var mapped = false;

      if (mappedId != null) {
        final existing = await _anki.getKnowledgePointById(mappedId);
        if (existing == null) {
          _addSkip(
            skips,
            ContentPackageSkipReason.unknownMappedKnowledgePoint,
            '$nodeId -> $mappedId',
          );
          continue;
        }
        productId = existing.id;
        mapped = true;
      } else {
        productId = await _existingKnowledgePointId(nodeId);
        if (productId == null && options.createKnowledgePoints) {
          if (label.isEmpty) {
            _addSkip(
              skips,
              ContentPackageSkipReason.knowledgeLabelMissing,
              nodeId,
            );
            continue;
          }
          final point = await _anki.createKnowledgePoint(
            title: label,
            content: '来自内容包 $contentId 的知识节点（role=${node.role}，'
                'source=${node.source}）。',
            source: 'content_package',
          );
          productId = point.id;
          created = true;
        }
      }
      if (productId == null) {
        _addSkip(
            skips, ContentPackageSkipReason.knowledgePointUnmapped, nodeId);
        continue;
      }

      await _contentRefs.upsert(
        contentId: nodeId,
        objectType: ContentObjectType.knowledgePoint,
        objectId: productId,
        role: ContentRefRole.node,
        subject: package.subject,
        metadata: <String, Object?>{
          'question_id': contentId,
          'label': label,
          'knowledge_role': node.role,
          'knowledge_source': node.source,
        },
      );
      knowledgeResults.add(
        ContentPackageKnowledgeImport(
          contentNodeId: nodeId,
          label: label,
          role: node.role,
          productKnowledgePointId: productId,
          created: created,
          mapped: mapped,
        ),
      );

      // 知识节点上的标签（只挂到产品知识点，不挂题目）。
      final knowledgeCandidates = <_TagCandidate>[
        if (subjectTagPath != null && label.isNotEmpty)
          _TagCandidate(
            dimension: 'knowledge:$nodeId',
            path: '$subjectTagPath/$label',
          ),
      ];
      for (final path in options.extraKnowledgeTagPathsByNodeId[nodeId] ??
          const <String>[]) {
        final explicitPath = _nonEmpty(path);
        if (explicitPath != null) {
          knowledgeCandidates.add(
            _TagCandidate(dimension: 'knowledge:$nodeId', path: explicitPath),
          );
        }
      }
      for (final candidate in _distinctCandidates(knowledgeCandidates)) {
        final tagId = await _resolveTagId(candidate: candidate, skips: skips);
        tagResults.add(
          ContentPackageTagImport(
            dimension: candidate.dimension,
            requested: candidate.path.trim(),
            objectType: ContentObjectType.knowledgePoint,
            objectId: productId,
            tagId: tagId,
            missing: tagId == null,
          ),
        );
        if (tagId == null) {
          continue;
        }
        await _tags.addTagToObject(
          tagId: tagId,
          objectType: ContentObjectType.knowledgePoint,
          objectId: productId,
        );
      }
    }

    // ---- 3) 题目本体（答案只来自 Source） ----
    final answerText = package.formattedAnswer;
    if (answerText == null) {
      _addSkip(skips, ContentPackageSkipReason.answerMissing, contentId);
    }
    final solutionText = _sourceSolutionText(package, skips);
    final difficulty = _difficultyOf(package, skips);
    final ingested = await _questions.ingest(
      QuestionDraft(
        stem: package.stem,
        answer: answerText,
        solution: solutionText,
        subjectKey: package.subject,
        questionType: package.questionType,
        sourceLevel: _sourceLevelOf(package.sourceLevel),
        sourceLabel: package.sourceLabel,
        year: package.year,
        region: package.region,
        sourceUrl: package.sourceUrl,
        textFormat: package.isMarkdown ? 'markdown' : 'plain',
        capability: package.capability,
        difficulty: difficulty.value,
        difficultySource: difficulty.source,
        origin: 'content_package',
        state: 'structured',
      ),
      now: now,
    );
    final question = ingested.question;

    // 产品题只追加：同名题干换版时不动 questions 行；答案/解析若变了要显式记下，
    // 不能让「ref 已是新 hash」被误读成「产品题正文也是新版」。
    if (!ingested.created) {
      final storedAnswer = question.answer ?? '';
      final storedSolution = question.solution ?? '';
      if (storedAnswer != (answerText ?? '')) {
        _addSkip(
          skips,
          ContentPackageSkipReason.questionBodyNotUpdated,
          'answer 长度 ${storedAnswer.length} -> ${answerText?.length ?? 0}',
        );
      }
      if (storedSolution != (solutionText ?? '')) {
        _addSkip(
          skips,
          ContentPackageSkipReason.questionBodyNotUpdated,
          'solution 长度 ${storedSolution.length} -> ${solutionText?.length ?? 0}',
        );
      }
    }

    // 题名：内容包只给建议名；产品已有题名（用户改过）不覆盖。
    final suggestedTitle = package.title.trim();
    if (suggestedTitle.isNotEmpty) {
      final currentTitle = question.title?.trim() ?? '';
      if (currentTitle.isEmpty) {
        await _questions.setQuestionTitle(question.id, suggestedTitle,
            now: now);
      } else if (currentTitle != suggestedTitle) {
        _addSkip(
          skips,
          ContentPackageSkipReason.titleNotOverwritten,
          '$currentTitle != $suggestedTitle',
        );
      }
    }

    // 标签挂载显式做一次：题目已存在时 ingest 不会再走 _linkTags。
    for (final resolution in resolvedQuestionTags) {
      await _tags.addTagToObject(
        tagId: resolution.tagId,
        objectType: ContentObjectType.question,
        objectId: question.id,
      );
      tagResults.add(
        ContentPackageTagImport(
          dimension: resolution.candidate.dimension,
          requested: resolution.candidate.path.trim(),
          objectType: ContentObjectType.question,
          objectId: question.id,
          tagId: resolution.tagId,
        ),
      );
    }
    for (final candidate in missingQuestionTags) {
      tagResults.add(
        ContentPackageTagImport(
          dimension: candidate.dimension,
          requested: candidate.path.trim(),
          objectType: ContentObjectType.question,
          objectId: question.id,
          missing: true,
        ),
      );
    }

    // ---- 4) 内容引用：题目 ref（换版原地更新；旧题引用改指向新题） ----
    final existingRefs = await _contentRefs.listByContentId(contentId);
    for (final ref in existingRefs) {
      if (ref.objectType == ContentObjectType.question &&
          ref.role == ContentRefRole.sourcePackage &&
          ref.objectId != question.id) {
        await _contentRefs.delete(
          contentId: ref.contentId,
          objectType: ref.objectType,
          objectId: ref.objectId,
          role: ref.role,
        );
        _addSkip(
          skips,
          ContentPackageSkipReason.staleQuestionRefRemoved,
          '${ref.objectId} -> ${question.id}',
        );
      }
    }
    final provenancePaired =
        (package.version == null) == (package.contentHash == null);
    if (!provenancePaired) {
      _addSkip(
        skips,
        ContentPackageSkipReason.incompleteProvenance,
        'version=${package.version} hash=${package.contentHash}',
      );
    }
    // 图片：本服务不复制字节（产品侧落图要另走 QuestionMediaStore），只把引用
    // 摘要留在 metadata 并如实记跳过。
    for (final figure in package.figures) {
      _addSkip(
        skips,
        figure.path.trim().isEmpty
            ? ContentPackageSkipReason.figurePathMissing
            : ContentPackageSkipReason.figureNotImported,
        figure.id,
      );
    }
    final questionRef = await _contentRefs.upsert(
      contentId: contentId,
      objectType: ContentObjectType.question,
      objectId: question.id,
      role: ContentRefRole.sourcePackage,
      contentVersion: provenancePaired ? package.version : null,
      contentHash: provenancePaired ? package.contentHash : null,
      subject: package.subject,
      metadata: _questionRefMetadata(package),
    );

    // ---- 5) 可选：DAG/错因 → 闪存卡 ----
    final cardPlan = await _maybeGenerateCards(
      package: package,
      contentId: contentId,
      options: options,
      knowledge: knowledgeResults,
      skips: skips,
    );

    return ContentPackageImportResult(
      contentId: contentId,
      status: skips.isEmpty
          ? ContentPackageImportStatus.imported
          : ContentPackageImportStatus.importedWithSkips,
      questionId: question.id,
      serialNo: question.serialNo,
      questionCreated: ingested.created,
      questionRefId: questionRef.id,
      contentVersion: questionRef.contentVersion,
      contentHash: questionRef.contentHash,
      knowledgePoints: List<ContentPackageKnowledgeImport>.unmodifiable(
        knowledgeResults,
      ),
      tags: List<ContentPackageTagImport>.unmodifiable(tagResults),
      skipped: List<ContentPackageImportSkip>.unmodifiable(skips),
      blocked: const <String>[],
      cardPlan: cardPlan,
    );
  }

  // ---------------------------------------------------------------------------
  // 解析原文 / 难度 / 标签 / 知识点
  // ---------------------------------------------------------------------------

  /// 产品 `questions.solution` 只接受「来源解析 + 内容包允许学生看」的文本。
  String? _sourceSolutionText(
    ContentPackage package,
    List<ContentPackageImportSkip> skips,
  ) {
    final sourceSolutions = <ContentPackageSolution>[
      for (final solution in package.solutions)
        if (solution.kind == 'official_source' &&
            solution.bodyMd.trim().isNotEmpty)
          solution,
    ];
    for (final solution in package.solutions) {
      if (solution.kind != 'official_source' &&
          solution.bodyMd.trim().isNotEmpty) {
        _addSkip(
          skips,
          ContentPackageSkipReason.solutionNotSource,
          solution.id,
        );
      }
    }
    if (sourceSolutions.isEmpty) {
      _addSkip(skips, ContentPackageSkipReason.solutionMissingSource,
          package.contentId);
      return null;
    }
    if (!package.sourceAnalysisVisible) {
      _addSkip(
        skips,
        ContentPackageSkipReason.solutionSuppressed,
        '${sourceSolutions.map((s) => s.id).join(',')}（内容包不渲染来源解析，DAG 承担解析）',
      );
      return null;
    }
    final renderable = <ContentPackageSolution>[
      for (final solution in sourceSolutions)
        if (solution.renderStudentAnalysis) solution,
    ];
    if (renderable.isEmpty) {
      _addSkip(
        skips,
        ContentPackageSkipReason.solutionNotRenderable,
        sourceSolutions.map((s) => s.id).join(','),
      );
      return null;
    }
    return renderable.map((solution) => solution.bodyMd.trim()).join('\n\n');
  }

  ({double? value, String? source}) _difficultyOf(
    ContentPackage package,
    List<ContentPackageImportSkip> skips,
  ) {
    final value = package.difficulty;
    if (value == null) {
      return (value: null, source: null);
    }
    if (value < 1 || value > 10) {
      _addSkip(
        skips,
        ContentPackageSkipReason.difficultyOutOfRange,
        '$value',
      );
      return (value: null, source: null);
    }
    const allowedSources = <String>{'prior', 'ai', 'manual'};
    final rawSource = package.difficultySource?.trim() ?? '';
    return (
      value: value,
      source: allowedSources.contains(rawSource) ? rawSource : null,
    );
  }

  static String _sourceLevelOf(String raw) {
    const allowed = <String>{
      'gaokao',
      'provincial_diagnostic',
      'elite_school',
      'school',
      'personal',
      'unknown',
    };
    final value = raw.trim();
    return allowed.contains(value) ? value : 'unknown';
  }

  /// 一条内容知识节点已建立的产品知识点 id（经 `content_refs` 幂等反查）。
  Future<String?> _existingKnowledgePointId(String contentNodeId) async {
    final refs = await _contentRefs.listByContentId(contentNodeId);
    for (final ref in refs) {
      if (ref.objectType != ContentObjectType.knowledgePoint) {
        continue;
      }
      if (ref.role != ContentRefRole.node) {
        continue;
      }
      final existing = await _anki.getKnowledgePointById(ref.objectId);
      if (existing != null) {
        return existing.id;
      }
    }
    return null;
  }

  /// 解析一条标签候选：只查已有 `tags`；缺失记 `missing_tag`，绝不创建。
  Future<String?> _resolveTagId({
    required _TagCandidate candidate,
    required List<ContentPackageImportSkip> skips,
  }) async {
    final requested = candidate.path.trim();
    if (requested.isEmpty) {
      return null;
    }
    final tag = (await _tags.getTagByPath(requested)) ??
        (await _tags.getTagById(requested));
    if (tag == null) {
      _addSkip(
        skips,
        ContentPackageSkipReason.missingTag,
        '${candidate.dimension}: $requested',
      );
      return null;
    }
    return tag.id;
  }

  // ---------------------------------------------------------------------------
  // 引用摘要
  // ---------------------------------------------------------------------------

  /// 题目引用的 metadata：只放摘要（等级/来源/hash/分值），不放题干/答案正文。
  static Map<String, Object?> _questionRefMetadata(ContentPackage package) {
    final metadata = <String, Object?>{
      'source_level': package.sourceLevel,
      'question_type': package.questionType,
      'source_analysis_visible': package.sourceAnalysisVisible,
      if (package.sourceLabel.isNotEmpty) 'source_label': package.sourceLabel,
      if (package.year != null) 'year': package.year,
      if (package.region != null) 'region': package.region,
      if (package.answerTrust != null) 'answer_trust': package.answerTrust,
      if (package.answerSourceId != null)
        'answer_source_id': package.answerSourceId,
      if (package.reviewStatus != null) 'review_status': package.reviewStatus,
      if (package.boardVersion != null) 'board_version': package.boardVersion,
      if (package.boardHash != null) 'board_hash': package.boardHash,
      if (package.subquestions.isNotEmpty)
        'subquestions': <Map<String, Object?>>[
          for (final subquestion in package.subquestions)
            <String, Object?>{
              'part': subquestion.part,
              if (subquestion.points != null) 'points': subquestion.points,
            },
        ],
    };
    if (package.scoringTotalPoints != null || package.scoringSource != null) {
      metadata['scoring'] = <String, Object?>{
        if (package.scoringTotalPoints != null)
          'total_points': package.scoringTotalPoints,
        if (package.scoringSource != null) 'source': package.scoringSource,
      };
    }
    if (package.figures.isNotEmpty) {
      metadata['figures'] = <Map<String, Object?>>[
        for (final figure in package.figures)
          <String, Object?>{
            'id': figure.id,
            'role': figure.role,
            if (figure.path.isNotEmpty) 'path': figure.path,
            if (figure.placeholderN != null)
              'place_holder_n': figure.placeholderN,
          },
      ];
    }
    return metadata;
  }

  // ---------------------------------------------------------------------------
  // 可选卡片
  // ---------------------------------------------------------------------------

  Future<DagFlashcardPlan?> _maybeGenerateCards({
    required ContentPackage package,
    required String contentId,
    required ContentPackageImportOptions options,
    required List<ContentPackageKnowledgeImport> knowledge,
    required List<ContentPackageImportSkip> skips,
  }) async {
    if (!options.generateCards) {
      return null;
    }
    final explicit = options.cardKnowledgePointId?.trim() ?? '';
    final pointId = explicit.isNotEmpty
        ? explicit
        : _primaryKnowledgePointId(package, knowledge);
    if (pointId == null) {
      _addSkip(
        skips,
        ContentPackageSkipReason.cardMissingKnowledgePoint,
        contentId,
      );
      return null;
    }
    final existing = await _anki.getKnowledgePointById(pointId);
    if (existing == null) {
      _addSkip(
        skips,
        ContentPackageSkipReason.cardUnknownKnowledgePoint,
        pointId,
      );
      return null;
    }
    if (package.dagNodes.isEmpty && package.errorCauses.isEmpty) {
      _addSkip(skips, ContentPackageSkipReason.boardEmpty, contentId);
      return null;
    }
    return _cards.generate(
      DagFlashcardInput(
        contentId: contentId,
        questionTitle: package.title,
        knowledgePointId: pointId,
        nodes: package.dagNodes,
        errorCauses: package.errorCauses,
      ),
      dryRun: options.cardsDryRun,
    );
  }

  /// 卡片挂载点：优先内容包 `role=primary` 的知识节点，其次任意已映射节点。
  static String? _primaryKnowledgePointId(
    ContentPackage package,
    List<ContentPackageKnowledgeImport> knowledge,
  ) {
    final byNodeId = <String, ContentPackageKnowledgeImport>{
      for (final point in knowledge) point.contentNodeId: point,
    };
    for (final node in package.knowledge) {
      if (node.role.trim() != 'primary') {
        continue;
      }
      final point = byNodeId[node.nodeId.trim()];
      if (point != null) {
        return point.productKnowledgePointId;
      }
    }
    return knowledge.isEmpty ? null : knowledge.first.productKnowledgePointId;
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  /// 同一个标签路径只解析一次；保留首次出现的维度。
  static List<_TagCandidate> _distinctCandidates(
    List<_TagCandidate> candidates,
  ) {
    final seen = <String>{};
    return <_TagCandidate>[
      for (final candidate in candidates)
        if (seen.add(candidate.path.trim())) candidate,
    ];
  }

  static void _addSkip(
    List<ContentPackageImportSkip> skips,
    String code,
    String detail,
  ) {
    for (final existing in skips) {
      if (existing.code == code && existing.detail == detail) {
        return;
      }
    }
    skips.add(ContentPackageImportSkip(code: code, detail: detail));
  }

  static String? _nonEmpty(String? raw) {
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}

/// 一条待解析的标签候选（只在本文件内用）。
class _TagCandidate {
  const _TagCandidate({required this.dimension, required this.path});

  final String dimension;
  final String path;
}
