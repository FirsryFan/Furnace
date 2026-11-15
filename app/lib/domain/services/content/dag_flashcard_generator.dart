/// DAG / 错因 → 闪存卡生成器（task-79，2026-11-15）。
///
/// 为什么需要它：内容包的 Thinking DAG 与 `error_causes` 已经是「解析正文」，
/// 但闪存卡（`card_templates`）此前只有手写与知识包导入两条来源。本类把可自测
/// 的 DAG 节点与错因压成卡面，落成 `card_templates` 行，只通过 `external_id`
/// 与 `content_refs(role=card_seed)` 回溯到内容包；**不写内容正文**，也不复制
/// `card_states` / `review_logs`（FSRS 状态归复习，不归生成）。
///
/// 规则（`INTEGRATION-CONTRACT-2026-11-15.md` §6.2）：
///
///  * 可生成：DAG 节点 `kind ∈ {formula_or_model, check, decision, conclusion}`
///    与错因 `EC-*`；
///  * 不生成：`kind=computation`（纯爆算）、`role=read_question`（审题），以及
///    `condition/goal/insight/dead_end/branch_try/...` 这类不能自测的步骤；
///    变式/扩展/额外任务/提示/证据不是本类输入，从接口上就不会变成卡；
///  * 节点 `body` 是解析正文，**不整段**进 answer：最多摘要 120 字作「依据」；
///  * 每张卡 `external_id = content:<content-id>#<seed-id>`（DAG 节点 id 或错因
///    code），同 id 幂等：只建新模板，不覆盖/不复制既有模板、卡状态与复习记录；
///  * 缺目标知识点 → 每张卡记 `skipped:missing_knowledge_point`（不伪造 KP、不建
///    标签）；`knowledge_point_id` 已给但库里不存在 → `unknown_knowledge_point`；
///  * `dryRun` 默认 true：只返回计划（question/answer/hint 预览），apply 才写。
///
/// 卡类型只用既有词表（不改 UI 契约）：公式卡 `fill_blank`（可填空作答），
/// 判断/决策/结论/错因卡 `essay`（自查自判）。**不生成 mcq**：DAG 节点没有选项
/// 字段，而 `result`（如 `A 假、B 真`）是「多个选项的判定」，把它读成「这个判断
/// 成立/不成立」会生成一张语义错误的二选一卡。详见
/// `DAG-FLASHCARD-GENERATION-2026-11-15.md`。
///
/// 未接线：没有 UI/Provider 调用本类（task-79 只要求 service + tests）；调用方
/// 应把内容包解析出的节点/错因与目标产品知识点 id 传进来。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/content_ref_repository.dart';
import 'content_ref_vocab.dart';

/// 一张生成卡的内容类别（不是 `card_templates.type` 词表的值）。
///
/// 落库的 `type` 仍然只有 `fill_blank` / `essay` 等既有值；这个类别只用于生成
/// 报告、`content_refs.metadata_json.card_kind` 与测试断言。
enum DagCardKind {
  formula('formula'),
  check('check'),
  decision('decision'),
  conclusion('conclusion'),
  errorCause('error_cause');

  const DagCardKind(this.wireValue);

  final String wireValue;
}

/// 一个种子在一次生成中的结局。
enum DagCardStatus {
  /// dry run：会新建（库里还没有这个 `external_id`）。
  wouldCreate,

  /// apply：本次真的插入了 `card_templates` 行。
  created,

  /// 有意不生成（不可自测的类型、缺 KP、内容空、已存在……）。
  skipped,

  /// 输入本身不合法（内容 id/种子 id 非法、同批重复），没有生成。
  blocked,
}

/// `skipped` 的原因词表（可被测试与报告直接引用）。
abstract final class DagCardSkipReason {
  /// 没有给目标产品知识点：不伪造 KP，整批卡跳过。
  static const String missingKnowledgePoint = 'missing_knowledge_point';

  /// 给了知识点 id，但 `knowledge_points` 里没有这一行：不建悬空外键。
  static const String unknownKnowledgePoint = 'unknown_knowledge_point';

  /// 同 `external_id` 已有模板：幂等跳过（不覆盖）。
  static const String alreadyExists = 'already_exists';

  /// 审题步骤（`role=read_question`）：不是可自测的知识/判断。
  static const String readQuestionRole = 'read_question_role';

  /// 纯爆算节点（`kind=computation`）：算一遍不等于记住一个可复用的点。
  static const String pureComputation = 'pure_computation';

  /// 其它不可成卡的节点类型（condition/goal/insight/dead_end/branch_try/…）。
  static const String notCardableKind = 'not_cardable_kind';

  /// `formula_or_model` 节点没有 `formulas`：不把模型节点伪装成公式卡。
  static const String noFormula = 'no_formula';

  /// 节点没有 `result`：无法给出可对照的卡面答案。
  static const String noResult = 'no_result';

  /// 节点/错因没有任何可用内容（label/body/formulas/result 全空）。
  static const String noCardableContent = 'no_cardable_content';

  /// 错因缺 symptom，或根因与改法都为空。
  static const String errorCauseIncomplete = 'error_cause_incomplete';
}

/// `blocked` 的原因词表。
abstract final class DagCardBlockReason {
  /// `content_id` 为空/带空白/含 `#` 等，不能构成可回溯的 `external_id`。
  static const String invalidContentId = 'invalid_content_id';

  /// 节点 id / 错因 code 为空或含非法字符，无法构成 `external_id`。
  static const String invalidSeedId = 'invalid_seed_id';

  /// 同一批输入里两个种子算出同一个 `external_id`：只生成第一条。
  static const String duplicateSeedId = 'duplicate_seed_id';
}

/// 一个可参与生成的 DAG 节点（内容包 `thinking_dag.nodes[]` 的可成卡子集）。
///
/// 与 `features/design_board/domain/design_board.dart` 的 `DagNode` 字段一一对应
/// （id / kind / role / label / body / formulas / keyQuantities / result），但本类
/// 是生成器的**输入契约**：内容包解析层负责映射，域服务不反向依赖查看器 feature。
/// `step_type`（thinking/derivation/meta_decision）不参与成卡判断，故不取。
class DagFlashcardNode {
  const DagFlashcardNode({
    required this.id,
    required this.kind,
    this.role = '',
    this.label = '',
    this.body = '',
    this.formulas = const <String>[],
    this.keyQuantities = const <String>[],
    this.result = '',
  });

  /// 内容包节点 id（`N-Q1-02` 形态），是 `external_id` 的种子 id。
  final String id;

  /// 内容包 `kind`：`formula_or_model` / `check` / `decision` / `conclusion` /
  /// `computation` / `condition` / …（词表见 `panel-common.schema.json`）。
  final String kind;

  /// 语义角色：`read_question` / `judge` / `compute` / `conclude` / `exclude` /
  /// `construct` / `verify`。只有 `read_question` 会被单独跳过。
  final String role;

  final String label;

  /// 这一步的推导正文。只用于截断后的「依据」，不整段进卡。
  final String body;

  /// 展示用公式（LaTeX，不带 `$`）。公式卡必填。
  final List<String> formulas;

  /// 关键量（如 `v_x=v_0：水平分速度`），用作卡面提示。
  final List<String> keyQuantities;

  /// 这一步的判定/结论（如 `B 真`、`答案 B`）。判断/决策/结论卡必填。
  final String result;
}

/// 一条错因（内容包 `error_causes.items[]` 的可成卡子集）。
///
/// 与 `panel-common.schema.json#/$defs/error_cause_board` 对齐；`prevalence_source`
/// 与 `evidence_refs` 是开发者字段，不进卡面，故不取。
class DagFlashcardErrorCause {
  const DagFlashcardErrorCause({
    required this.code,
    this.category = '',
    this.symptom = '',
    this.rootCause = '',
    this.diagnosticQuestion = '',
    this.remediation = '',
    this.locateNode,
  });

  /// 错因 code（`EC-Q1-01` 形态），是 `external_id` 的种子 id。
  final String code;

  /// 错因类别（`knowledge_gap` / `representation_error` / …），只进引用元数据。
  final String category;

  /// 学生实际会出现的样子（卡面题干）。
  final String symptom;

  /// 根因（卡面答案）。
  final String rootCause;

  /// 诊断问题（卡面提示）。
  final String diagnosticQuestion;

  /// 改法/可执行任务（卡面答案）。
  final String remediation;

  /// 关联的 DAG 节点 id；能解析到节点时，卡面提示会带上该节点 label。
  final String? locateNode;
}

/// 一次生成请求。
class DagFlashcardInput {
  const DagFlashcardInput({
    required this.contentId,
    this.questionTitle = '',
    this.knowledgePointId,
    this.nodes = const <DagFlashcardNode>[],
    this.errorCauses = const <DagFlashcardErrorCause>[],
  });

  /// C 层内容 id（`Q-PH0001` / `QSET-…`），`external_id` 的可回溯锚点。
  final String contentId;

  /// 题目短标题（学生可见），只用于给卡面补上下文（如结论卡「本题的最终结论」）。
  /// 不取整段题干：契约 §2.4 禁止把题目正文复制进卡片。
  final String questionTitle;

  /// 目标产品知识点 id；为空 → 全部 skipped（不伪造 KP）。
  final String? knowledgePointId;

  final List<DagFlashcardNode> nodes;
  final List<DagFlashcardErrorCause> errorCauses;
}

/// 一张卡在一次生成中的计划/结果行。
class DagFlashcardPlanItem {
  const DagFlashcardPlanItem({
    required this.seedId,
    required this.status,
    this.externalId,
    this.kind,
    this.cardType,
    this.reason,
    this.knowledgePointId,
    this.templateId,
    this.question,
    this.answer,
    this.hint,
    this.options = const <String>[],
  });

  /// DAG 节点 id 或错因 code；输入非法时可能是空串（见 [reason]）。
  final String seedId;

  final DagCardStatus status;

  /// `content:<content-id>#<seed-id>`；输入非法时为 null。
  final String? externalId;

  /// 生成类别；skipped/blocked 时可能为 null。
  final DagCardKind? kind;

  /// 落库的 `card_templates.type`（`fill_blank` / `essay`）。
  final String? cardType;

  /// skipped/blocked 的原因常量，见 [DagCardSkipReason] / [DagCardBlockReason]。
  final String? reason;

  final String? knowledgePointId;

  /// 已创建模板的 `tpl-…` id（仅 `created`）。
  final String? templateId;

  final String? question;
  final String? answer;
  final String? hint;
  final List<String> options;

  Map<String, Object?> toJson() => <String, Object?>{
        'seed_id': seedId,
        'status': status.name,
        'external_id': externalId,
        'kind': kind?.wireValue,
        'card_type': cardType,
        'reason': reason,
        'knowledge_point_id': knowledgePointId,
        'template_id': templateId,
        'question': question,
        'answer': answer,
        'hint': hint,
        'options': options,
      };
}

/// 一次生成的完整结果（dry run 与 apply 共用）。
class DagFlashcardPlan {
  const DagFlashcardPlan({
    required this.contentId,
    required this.dryRun,
    required this.items,
  });

  final String contentId;

  /// true = 只计划未写库；false = 已写。
  final bool dryRun;

  /// 每个被尝试的种子一行（按输入顺序：节点在前、错因在后）。
  final List<DagFlashcardPlanItem> items;

  /// dry run 下「会新建」的数量；apply 下恒为 0。
  int get wouldCreate =>
      items.where((i) => i.status == DagCardStatus.wouldCreate).length;

  /// apply 下真正新建的模板数；dry run 下恒为 0。
  int get created =>
      items.where((i) => i.status == DagCardStatus.created).length;

  int get skipped =>
      items.where((i) => i.status == DagCardStatus.skipped).length;

  int get blocked =>
      items.where((i) => i.status == DagCardStatus.blocked).length;

  /// 本次计划/新建的卡（dry run 是 wouldCreate，apply 是 created）。
  List<DagFlashcardPlanItem> get cards => <DagFlashcardPlanItem>[
        for (final item in items)
          if (item.status == DagCardStatus.wouldCreate ||
              item.status == DagCardStatus.created)
            item,
      ];

  /// skipped 的原因分布（便于报告与调用方判断这批内容是不是缺东西）。
  Map<String, int> get skippedReasons => _reasonCounts(DagCardStatus.skipped);

  Map<String, int> get blockedReasons => _reasonCounts(DagCardStatus.blocked);

  Map<DagCardKind, int> get cardsByKind {
    final counts = <DagCardKind, int>{};
    for (final item in cards) {
      final kind = item.kind;
      if (kind == null) {
        continue;
      }
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'content_id': contentId,
        'dry_run': dryRun,
        'would_create': wouldCreate,
        'created': created,
        'skipped': skipped,
        'blocked': blocked,
        'cards_by_kind': <String, int>{
          for (final entry in cardsByKind.entries)
            entry.key.wireValue: entry.value,
        },
        'skipped_reasons': skippedReasons,
        'blocked_reasons': blockedReasons,
        'items': <Map<String, Object?>>[
          for (final item in items) item.toJson(),
        ],
      };

  Map<String, int> _reasonCounts(DagCardStatus status) {
    final counts = <String, int>{};
    for (final item in items) {
      if (item.status != status) {
        continue;
      }
      final reason = item.reason;
      if (reason == null) {
        continue;
      }
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    return counts;
  }
}

/// DAG / 错因 → 闪存卡生成器。
///
/// 用法：
/// ```dart
/// final generator = DagFlashcardGenerator(db);
/// final plan = await generator.generate(input);            // dry run（默认）
/// final applied = await generator.generate(input, dryRun: false);
/// ```
///
/// 写库只发生在 `dryRun: false`，并且整批在一个事务里：任何一步抛错都不留半批。
/// 注入的 [AnkiRepository] / [ContentRefRepository] 必须与 [db] 是同一个库
/// （默认就用 [db] 构造）。
class DagFlashcardGenerator {
  DagFlashcardGenerator(
    AppDatabase db, {
    AnkiRepository? ankiRepository,
    ContentRefRepository? contentRefs,
  })  : _db = db,
        _anki = ankiRepository ?? AnkiRepository(db),
        _contentRefs = contentRefs ?? ContentRefRepository(db);

  final AppDatabase _db;
  final AnkiRepository _anki;
  final ContentRefRepository _contentRefs;

  /// 生成卡的 `external_id`：`content:<content-id>#<seed-id>`。
  ///
  /// 契约 §7.3 的「闪存卡」引用点：同一张卡既能按 `content_id` 反查内容包，
  /// 也能从内容节点反查产品卡（经 `content_refs(role=card_seed)`）。
  static String externalIdOf(String contentId, String seedId) =>
      'content:${contentId.trim()}#${seedId.trim()}';

  /// 生成（默认只做计划）。返回的 [DagFlashcardPlan] 同时含 wouldCreate/created、
  /// skipped、blocked 三类计数与逐行原因。
  Future<DagFlashcardPlan> generate(
    DagFlashcardInput input, {
    bool dryRun = true,
  }) {
    final contentId = input.contentId.trim();
    if (!_validContentId.hasMatch(contentId)) {
      return Future<DagFlashcardPlan>.value(
        DagFlashcardPlan(
          contentId: contentId,
          dryRun: dryRun,
          items: const <DagFlashcardPlanItem>[
            DagFlashcardPlanItem(
              seedId: '',
              status: DagCardStatus.blocked,
              reason: DagCardBlockReason.invalidContentId,
            ),
          ],
        ),
      );
    }
    Future<DagFlashcardPlan> run() =>
        _plan(input, contentId: contentId, dryRun: dryRun);
    return dryRun ? run() : _db.transaction(run);
  }

  Future<DagFlashcardPlan> _plan(
    DagFlashcardInput input, {
    required String contentId,
    required bool dryRun,
  }) async {
    final rawPointId = input.knowledgePointId?.trim();
    final pointId =
        rawPointId == null || rawPointId.isEmpty ? null : rawPointId;
    final pointExists =
        pointId != null && (await _anki.getKnowledgePointById(pointId)) != null;
    final nodeById = <String, DagFlashcardNode>{
      for (final node in input.nodes)
        if (node.id.trim().isNotEmpty) node.id.trim(): node,
    };

    final seeds = <_FlashcardSeed>[
      for (final node in input.nodes)
        _FlashcardSeed(id: node.id, build: () => _cardFromNode(node, input)),
      for (final cause in input.errorCauses)
        _FlashcardSeed(
          id: cause.code,
          build: () => _cardFromErrorCause(cause, input, nodeById),
        ),
    ];

    final items = <DagFlashcardPlanItem>[];
    final seenExternalIds = <String>{};
    for (final seed in seeds) {
      items.add(
        await _processSeed(
          seed: seed,
          contentId: contentId,
          knowledgePointId: pointId,
          pointExists: pointExists,
          seenExternalIds: seenExternalIds,
          dryRun: dryRun,
        ),
      );
    }
    return DagFlashcardPlan(
      contentId: contentId,
      dryRun: dryRun,
      items: List<DagFlashcardPlanItem>.unmodifiable(items),
    );
  }

  Future<DagFlashcardPlanItem> _processSeed({
    required _FlashcardSeed seed,
    required String contentId,
    required String? knowledgePointId,
    required bool pointExists,
    required Set<String> seenExternalIds,
    required bool dryRun,
  }) async {
    final seedId = seed.id.trim();
    if (!_validSeedId.hasMatch(seedId)) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        status: DagCardStatus.blocked,
        reason: DagCardBlockReason.invalidSeedId,
      );
    }
    final externalId = externalIdOf(contentId, seedId);
    if (!seenExternalIds.add(externalId)) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.blocked,
        reason: DagCardBlockReason.duplicateSeedId,
      );
    }
    // 缺 KP（没给 / 给了但库里没有）都先跳过：不伪造 KP、不建悬空外键。
    if (knowledgePointId == null) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.skipped,
        reason: DagCardSkipReason.missingKnowledgePoint,
      );
    }
    if (!pointExists) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.skipped,
        reason: DagCardSkipReason.unknownKnowledgePoint,
        knowledgePointId: knowledgePointId,
      );
    }

    final card = seed.build();
    if (card is _CardSkip) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.skipped,
        reason: card.reason,
        knowledgePointId: knowledgePointId,
      );
    }
    final ready = card as _CardReady;

    // 幂等：同 external_id 已有模板就跳过，不覆盖、不动它的 CardState/复习记录。
    final existing = await _anki.getTemplatesByExternalId(externalId);
    if (existing.isNotEmpty) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.skipped,
        reason: DagCardSkipReason.alreadyExists,
        kind: ready.kind,
        cardType: ready.cardType,
        knowledgePointId: knowledgePointId,
        templateId: existing.first.id,
        question: ready.question,
        answer: ready.answer,
        hint: ready.hint,
      );
    }

    if (dryRun) {
      return DagFlashcardPlanItem(
        seedId: seedId,
        externalId: externalId,
        status: DagCardStatus.wouldCreate,
        kind: ready.kind,
        cardType: ready.cardType,
        knowledgePointId: knowledgePointId,
        question: ready.question,
        answer: ready.answer,
        hint: ready.hint,
      );
    }

    final template = await _anki.createTemplate(
      knowledgePointId: knowledgePointId,
      type: ready.cardType,
      question: ready.question,
      answer: ready.answer,
      clozeTemplate:
          ready.cardType == _cardTypeFillBlank ? ready.question : null,
      hint: ready.hint,
      externalId: externalId,
    );
    // 引用桥：只写「卡 ↔ 内容种子」的 id 摘要，不复制正文（契约 §2.4）。
    await _contentRefs.upsert(
      contentId: contentId,
      objectType: ContentObjectType.cardTemplate,
      objectId: template.id,
      role: ContentRefRole.cardSeed,
      metadata: <String, Object?>{
        'seed_id': seedId,
        'card_kind': ready.kind.wireValue,
        'card_type': ready.cardType,
        'source_mode': 'ai_derived',
        'external_id': externalId,
        ...ready.metadata,
      },
    );

    return DagFlashcardPlanItem(
      seedId: seedId,
      externalId: externalId,
      status: DagCardStatus.created,
      kind: ready.kind,
      cardType: ready.cardType,
      knowledgePointId: knowledgePointId,
      templateId: template.id,
      question: ready.question,
      answer: ready.answer,
      hint: ready.hint,
    );
  }

  // ---------------------------------------------------------------------------
  // 节点 → 卡
  // ---------------------------------------------------------------------------

  static const String _cardTypeFillBlank = 'fill_blank';
  static const String _cardTypeEssay = 'essay';

  /// 节点分类与卡面生成。返回 [_CardSkip] 表示这个节点有意不成卡。
  _CardPlan _cardFromNode(DagFlashcardNode node, DagFlashcardInput input) {
    final kind = node.kind.trim();
    final role = node.role.trim();
    if (role == 'read_question') {
      return const _CardSkip(DagCardSkipReason.readQuestionRole);
    }
    switch (kind) {
      case 'computation':
        return const _CardSkip(DagCardSkipReason.pureComputation);
      case 'formula_or_model':
        return _formulaCard(node, input);
      case 'check':
        return _proseCard(
          node: node,
          input: input,
          kind: DagCardKind.check,
          questionTail: '这一步的判断是什么？依据是什么？',
        );
      case 'decision':
        return _proseCard(
          node: node,
          input: input,
          kind: DagCardKind.decision,
          questionTail: '这一步的关键决策是什么？为什么这样选？',
        );
      case 'conclusion':
        return _conclusionCard(node, input);
      default:
        return const _CardSkip(DagCardSkipReason.notCardableKind);
    }
  }

  /// 公式卡：`fill_blank`，题干留空，答案 = 节点 `formulas`。
  _CardPlan _formulaCard(DagFlashcardNode node, DagFlashcardInput input) {
    final formulas = _nonEmpty(node.formulas);
    if (formulas.isEmpty) {
      // 没有公式就不硬造公式卡：把模型节点伪装成结论卡会错标它是什么。
      return const _CardSkip(DagCardSkipReason.noFormula);
    }
    final label = node.label.trim();
    final body = node.body.trim();
    if (label.isEmpty && body.isEmpty) {
      return const _CardSkip(DagCardSkipReason.noCardableContent);
    }
    final prompt = label.isNotEmpty ? label : _excerpt(body, maxChars: 40);
    final question =
        '${_titlePrefix(input.questionTitle)}$prompt\n写出这一步的关键公式：______';
    return _CardReady(
      kind: DagCardKind.formula,
      cardType: _cardTypeFillBlank,
      question: question,
      answer: formulas.join('；'),
      hint: _aiHint(keyQuantities: node.keyQuantities),
      metadata: _nodeMetadata(node),
    );
  }

  /// 判断 / 决策卡：`essay`（自查自判），答案 = `result` + 截断依据。
  ///
  /// 题干里会去掉 label 末尾的判定括号（`（B 成立）`），否则题面自带答案。
  _CardPlan _proseCard({
    required DagFlashcardNode node,
    required DagFlashcardInput input,
    required DagCardKind kind,
    required String questionTail,
  }) {
    final result = node.result.trim();
    if (result.isEmpty) {
      return const _CardSkip(DagCardSkipReason.noResult);
    }
    final label = _stripVerdictLabel(node.label);
    final body = node.body.trim();
    if (label.isEmpty && body.isEmpty) {
      return const _CardSkip(DagCardSkipReason.noCardableContent);
    }
    final prompt = label.isNotEmpty ? label : _excerpt(body, maxChars: 40);
    return _CardReady(
      kind: kind,
      cardType: _cardTypeEssay,
      question: '${_titlePrefix(input.questionTitle)}$prompt——$questionTail',
      answer: '$result${_basisLine(body)}',
      hint: _aiHint(keyQuantities: node.keyQuantities),
      metadata: _nodeMetadata(node),
    );
  }

  /// 结论卡：`essay`。题干不写 label（结论节点 label 往往就是答案本身）。
  _CardPlan _conclusionCard(DagFlashcardNode node, DagFlashcardInput input) {
    final result = node.result.trim();
    if (result.isEmpty) {
      return const _CardSkip(DagCardSkipReason.noResult);
    }
    final title = _titlePrefix(input.questionTitle);
    final question =
        title.isEmpty ? '本题的最终结论（答案）是什么？' : '$title本题的最终结论（答案）是什么？';
    return _CardReady(
      kind: DagCardKind.conclusion,
      cardType: _cardTypeEssay,
      question: question,
      answer: result,
      hint: _aiHint(keyQuantities: node.keyQuantities),
      metadata: _nodeMetadata(node),
    );
  }

  /// 错因卡（陷阱卡）：题干 = symptom，答案 = 根因 + 改法，提示 = 诊断问题。
  ///
  /// 契约 §6.2：错因卡用 `hint` 承载「错因提示」，不新增 `type='trap'`。
  ///
  /// 空 code 到不了这里：`_processSeed` 的种子 id 校验先把它拦成
  /// `blocked:invalid_seed_id`（没有 id 的种子无法回溯）。
  _CardPlan _cardFromErrorCause(
    DagFlashcardErrorCause cause,
    DagFlashcardInput input,
    Map<String, DagFlashcardNode> nodeById,
  ) {
    final symptom = cause.symptom.trim();
    final rootCause = cause.rootCause.trim();
    final remediation = cause.remediation.trim();
    if (symptom.isEmpty || (rootCause.isEmpty && remediation.isEmpty)) {
      return const _CardSkip(DagCardSkipReason.errorCauseIncomplete);
    }
    final answerParts = <String>[
      if (rootCause.isNotEmpty) '根因：$rootCause',
      if (remediation.isNotEmpty) '改法：$remediation',
    ];
    final diagnostic = cause.diagnosticQuestion.trim();
    final locateNode = cause.locateNode?.trim();
    final locateLabel = locateNode == null || locateNode.isEmpty
        ? null
        : nodeById[locateNode]?.label.trim();
    final hintParts = <String>[
      if (diagnostic.isNotEmpty)
        '【AI】先自问：$diagnostic'
      else
        '【AI】由内容包错因自动生成，未经人工审核。',
      if (locateLabel != null && locateLabel.isNotEmpty) '对应步骤：$locateLabel',
    ];
    return _CardReady(
      kind: DagCardKind.errorCause,
      cardType: _cardTypeEssay,
      question:
          '${_titlePrefix(input.questionTitle)}易错点：$symptom\n错在哪、为什么、怎么改？',
      answer: answerParts.join('\n'),
      hint: hintParts.join('\n'),
      metadata: <String, Object?>{
        if (cause.category.trim().isNotEmpty)
          'error_category': cause.category.trim(),
        if (locateNode != null && locateNode.isNotEmpty)
          'locate_node': locateNode,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 卡面文本
  // ---------------------------------------------------------------------------

  /// AI 生成标记 + 可选关键量提示（契约 §6.2：`hint` 开头标【AI】）。
  static String _aiHint({List<String> keyQuantities = const <String>[]}) {
    final parts = <String>['【AI】由内容包 DAG 节点自动生成，未经人工审核。'];
    final quantities = _nonEmpty(keyQuantities);
    if (quantities.isNotEmpty) {
      parts.add('关键量：${quantities.join('；')}');
    }
    return parts.join('\n');
  }

  /// 答案的「依据」行：节点 body 只作摘要，不整段入卡。
  static String _basisLine(String body) {
    final excerpt = _excerpt(body);
    return excerpt.isEmpty ? '' : '\n依据：$excerpt';
  }

  /// 题干上下文前缀：`《题目短标题》`；没有标题就不加。
  static String _titlePrefix(String questionTitle) {
    final title = questionTitle.trim();
    return title.isEmpty ? '' : '《$title》';
  }

  /// 去掉 label 末尾带判定词的括号，避免题干自带答案。
  ///
  /// 例：`判 B：合力恒为重力 ⇒ a=g 不变（B 成立）` →
  /// `判 B：合力恒为重力 ⇒ a=g 不变`。
  static String _stripVerdictLabel(String label) {
    var result = label.trim();
    while (true) {
      final match = _trailingParen.firstMatch(result);
      if (match == null) {
        return result;
      }
      final inner = match.group(1)?.trim() ?? '';
      if (!_verdictTokens.hasMatch(inner)) {
        return result;
      }
      result = result.substring(0, match.start).trim();
    }
  }

  static final RegExp _trailingParen = RegExp(r'[（(]([^）)]*)[）)]\s*$');
  static final RegExp _verdictTokens = RegExp(r'(真|假|成立|不成立|正确|错误|对|错|答案)');

  /// 单行摘要：折叠空白，超过 [maxChars] 截断加省略号。
  static String _excerpt(String text, {int maxChars = 120}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars)}…';
  }

  static List<String> _nonEmpty(List<String> values) => <String>[
        for (final value in values)
          if (value.trim().isNotEmpty) value.trim(),
      ];

  static Map<String, Object?> _nodeMetadata(DagFlashcardNode node) =>
      <String, Object?>{
        'node_kind': node.kind.trim(),
        if (node.role.trim().isNotEmpty) 'node_role': node.role.trim(),
      };

  // ---------------------------------------------------------------------------
  // 输入校验
  // ---------------------------------------------------------------------------

  /// 内容 id 形态：`Q-PH0001` / `QSET-20261115-01` 等；拒绝空白与 `#`（会破坏
  /// `external_id` 的解析）。
  static final RegExp _validContentId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// 种子 id 形态：DAG 节点 `N-Q1-02` / 错因 `EC-Q1-01`；拒绝空白与分隔符。
  static final RegExp _validSeedId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
}

/// 一个待处理的种子（节点或错因）。
class _FlashcardSeed {
  const _FlashcardSeed({required this.id, required this.build});

  final String id;
  final _CardPlan Function() build;
}

/// 卡面生成的中间结果：可成卡 / 有意跳过。
sealed class _CardPlan {
  const _CardPlan();
}

class _CardSkip extends _CardPlan {
  const _CardSkip(this.reason);

  final String reason;
}

class _CardReady extends _CardPlan {
  const _CardReady({
    required this.kind,
    required this.cardType,
    required this.question,
    required this.answer,
    required this.hint,
    required this.metadata,
  });

  final DagCardKind kind;
  final String cardType;
  final String question;
  final String answer;
  final String hint;

  /// 进 `content_refs.metadata_json` 的引用摘要（不含正文）。
  final Map<String, Object?> metadata;
}
