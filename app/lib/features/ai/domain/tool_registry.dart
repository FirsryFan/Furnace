import 'dart:io';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/material_intake_repository.dart';
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../domain/ai_tool.dart';
import '../domain/model_adapter.dart';
import '../tools/card_group_tools.dart';
import '../tools/cognitive_tools.dart';
import '../tools/tag_tools.dart';
import '../tools/content_query_tools.dart';
import '../tools/deletion_tools.dart';
import '../tools/document_tools.dart';
import '../tools/knowledge_tools.dart';
import '../tools/metrics_tools.dart';
import '../tools/paper_tools.dart';
import '../tools/question_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/task_tools.dart';
import '../tools/ingest_tools.dart';
import '../tools/today_tools.dart';
import '../tools/web_tools.dart';

/// The complete, static list of tools the model may use.
///
/// "Static" is the whole point (docs/AI_DESIGN.md §10 C2): there is no plugin
/// registry, no runtime extension point, no dependency-injection container. A
/// tool exists because it is in this list, and adding one is a code change.
/// That is what "no cordis" means in practice.
///
/// Platform gating lives on the tool itself (`availableOnCurrentPlatform`), so
/// a Windows-only capability is simply absent from [forCurrentPlatform] on
/// Android rather than failing at call time.
class ToolRegistry {
  ToolRegistry(this._tools);

  /// The app's single tool list, assembled in one place.
  ///
  /// Registration and construction belong together: a tool that is not in this
  /// list is not reachable by the model at all (it would be dead code), and
  /// keeping the list here - rather than inside a Riverpod callback - is what
  /// lets a test assert membership and schemas without a widget tree.
  factory ToolRegistry.forApp({
    required AppDatabase db,
    required TaskRepository tasks,
    required TimeBlockRepository blocks,
    required AnkiRepository anki,
    required TagRepository tags,
    CognitiveModel model = const MindNetCognitiveModel(),
    DateTime Function()? clock,
  }) {
    final reviewPlans = ReviewPlanRepository(db, anki);
    return ToolRegistry([
      FetchPageTool(),
      QueryTasksTool(tasks, db),
      ManageTaskTool(tasks, db),
      QueryScheduleTool(blocks),
      ManageTimeBlockTool(blocks, db),
      // 用途 1 (docs/MINDNET_CONTRACT.md §6.3): read-only problem evaluation.
      EvaluateProblemFitTool(
        ankiRepository: anki,
        tagRepository: tags,
        database: db,
        model: model,
        clock: clock,
      ),
      // 控制层（roadmap §1 控制层行 / §3 第 5 行）：把到期卡与候选题合成一份
      // 「今天做这几件事」的清单，按 V(π)=ΔR/cost 排序，每条带度量与人话理由。
      // 纯逻辑在 `domain/services/scheduling/today_plan.dart`（Q32a），
      // 这个工具只读、不写、不改到期日（tools/today_tools.dart）。
      PlanTodayTool(
        ankiRepository: anki,
        tagRepository: tags,
        database: db,
        model: model,
        clock: clock,
      ),
      // 材料摄取（roadmap §2-C ① / §3 第 6 行）：一份 `mindnet.material/1` 信封
      // 经过确定性转化（`domain/services/ingest/material_ingest.dart`，Q33）变成
      // "要建哪些知识点/连接、每条出处"的**待确认提案**。只读：写不写由用户确认
      // （与拍照整理那条通路同一条纪律）。
      IngestMaterialTool(ankiRepository: anki, clock: clock),
      // 材料摄取的后半段（roadmap §2-C ①）：确认之后才真的写库 —— 批次主键就是信封的
      // `batch_id`（INGEST 幂等键），同一条提案确认两次不会建出两个知识点；连接现在
      // 不写（资料与卡片是"线索边"还是"包含边"未定，§2-C ④），在结果里如实报 deferred。
      // 提案表 `material_intake_proposals` 是 v17（`data/database/tables.dart`）。
      ApplyMaterialIntakeTool(
        repository:
            MaterialIntakeRepository(db, ankiRepository: anki, clock: clock),
        clock: clock,
      ),
      // 转写规程的确定性那一半（roadmap §2-C ③）：照片转写出的 `mindnet.run/1` 请求
      // 先过一遍自检（`domain/services/ingest/transcribe_run.dart`，Q37）——只校验、
      // 不执行，说清"错在哪"与"它会做什么"。图清单来自库里知识点的 `external_id`，
      // 所以模型不会去发明节点 id。`execute: true` 时走一步**演练**：把库里已有的
      // 节点按 `ms` 摆进仿真图、真的 apply 一遍动作，只跑不落库
      // （`cognitive/application/run_rehearsal.dart`，Q56）。
      CheckTranscribeRunTool(
        repository:
            MaterialIntakeRepository(db, ankiRepository: anki, clock: clock),
        database: db,
        model: model,
        clock: clock,
      ),
      // 用途 1 的兄弟 (Q12): 「这道题还有哪些同型邻居」。同一个题库投影
      // (`questions/application/question_corpus_reader.dart`) 上的只读排序，
      // 找不到就如实说没有——AI 不出题 (tools/question_tools.dart)。
      FindSimilarQuestionsTool(db: db),
      // 用途 1 的第三个问法 (轮次一百零六): 「我老在某类动作上卡，该练哪几道」——
      // 与认知模型页的「能力动作画像」同源：画像回答"哪个动作最该练"，这个工具回答
      // "练哪几道"（`readQuestionsForAction`，只认每道题最新一条链；AI 不出题）。
      FindQuestionsByCapabilityTool(db: db),
      // 用途 1 的另一半 (Q9/Q11/Q13): 「现在该练什么」——按危险/发展区读数从题库凑卷，
      // 凑不齐就如实报缺哪些知识点。读数与页面同源
      // (`cognitive/application/library_diagnosis_reader.dart`)，
      // 所以同一个知识点不会这边说危险、那边说健康 (tools/paper_tools.dart)。
      ComposePaperTool(db: db),
      // 用途 1 的裁判 (Q16 标定协议 v1): 「我记得到底行不行、模型是不是过度自信」。
      // 它读的只有 `review_logs`，是全 app 唯一一条**外部**检查——数字不来自模型的
      // 自我叙述。样本不足时它照原话拒绝给系数（tools/metrics_tools.dart）。
      ReviewMetricsTool(db: db),
      // The write half of the photo flow: an attached page of notes becomes a
      // real knowledge point plus cards, optionally in a card group (see
      // tools/knowledge_tools.dart).
      CreateKnowledgeCardsTool(anki, tags),
      // 卡组（卡组就是标签，轮次十七）的两个写口：把闪存卡挂进卡组，以及给卡组设
      // 每日新卡/复习量。用户现场留下的缺口就在这里——269 张卡、114 个标签、
      // object_tags 空，没有任何工具能把两边接上（tools/card_group_tools.dart）。
      LinkCardTagsTool(db: db, anki: anki, tags: tags),
      ManageReviewPlanTool(tags: tags, plans: reviewPlans),
      // The only destructive tool. Deleting a tag takes its whole subtree with
      // it, and deleting a flashcard takes its review history, so every call is
      // per-item confirmed and snapshotted for undo (tools/deletion_tools.dart).
      DeleteContentTool(db: db, anki: anki, tags: tags),
      // The pair of the tool above: the model cannot delete what it cannot
      // name, and before this pair existed the only way to address a tag or a
      // flashcard was to guess its name from the conversation
      // (tools/content_query_tools.dart). Read-only, so no mode asks about it.
      // Also the read half of the card-group pair above: flashcard rows now say
      // which tags they carry, tag rows say how many flashcards they hold, and
      // kind=review_plan reports the daily targets plus ungrouped-card count.
      QueryContentTool(
        db: db,
        anki: anki,
        tags: tags,
        plans: reviewPlans,
      ),
      // Building the tag tree is a normal reversible write; deleting from it is
      // delete_content (destructive, per-item confirmed).
      CreateTagsTool(tags),
      // The AI's document output: an answer the user wants to keep becomes a
      // file under <appSupport>/documents, with a real undo (tools/document_tools.dart).
      CreateDocumentTool(),
    ]);
  }

  final List<AiTool> _tools;

  /// Every registered tool, including ones this platform cannot offer. Used by
  /// the settings screen to explain what is missing and why.
  List<AiTool> get all => List.unmodifiable(_tools);

  /// The tools this platform may actually offer.
  List<AiTool> get forCurrentPlatform => [
        for (final tool in _tools)
          if (tool.availableOnCurrentPlatform) tool
      ];

  /// Tools that are registered but unavailable here.
  List<AiTool> get unavailableHere => [
        for (final tool in _tools)
          if (!tool.availableOnCurrentPlatform) tool
      ];

  AiTool? byName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    return null;
  }

  /// The provider-facing declarations. Sent on every turn rather than cached,
  /// because the list depends on the platform and would otherwise be wrong on
  /// whichever platform it was not built for.
  List<ModelToolSpec> get modelSpecs => [
        for (final tool in forCurrentPlatform)
          ModelToolSpec(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
          ),
      ];

  /// True when the current platform can offer nothing at all, which the UI says
  /// out loud instead of showing an AI that cannot act.
  bool get isEmptyHere => forCurrentPlatform.isEmpty;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
