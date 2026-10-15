# 找相似题（Q12）设计

> 口径来自用户（原始要求，非本文件改写）：**AI 不能自己出题，只能找相似题**。相似题的用处在两处：
> ① 组卷时某个知识点缺口（`PaperPlan.uncoveredKnowledgePointIds`）除了"去收题"，还可以用库里已有的同型题顶上；
> ② 跨学科抽象训练——同一个解题动作（`CapabilityAction`）在不同学科里的样子不同，找到"动作同型"的题就是把抽象迁移练一遍。
>
> 本文件是这一片的冻结契约：领域层 `app/lib/domain/services/paper/similar_questions.dart`（纯逻辑）
> + 应用层 `app/lib/features/questions/application/similar_question_provider.dart`（唯一的 IO 点）。

## 1. 它做什么 / 不做什么

做：

- 给**一道已有题目**当基准（focus），在**题库已有题目**里排序，给出"为什么像"的一句话。
- 四个信号分开算、可调权：共用知识点、同型思维链动作、同学科、难度接近。
- 跨学科但动作同型 → 明确标成迁移候选（`crossSubjectTransfer`），而不是偷偷给个高分。

不做：

- **不出题**：没有候选就返回空列表。缺口要么去收题，要么用库里已有的题，模型不生成。
- 不做语义相似（不引向量库、不调模型）：本片只用**库里已有的结构化信号**，可离线、可复现、可解释。
- 不落库：相似结果不写表（和 Q5 卡点评估一样，是读数不是事实；将来若要缓存，另开切片）。

## 2. 输入 / 输出

领域层（`domain/services/paper/similar_questions.dart`）：

| 类型 | 字段 |
|---|---|
| `SimilarityFocus` | `questionId`（必填）、`knowledgePointIds`、`subjectKey`、`questionType`、`difficulty`、`actionTypes`（思维链动作，按步骤顺序） |
| `SimilarityCandidate` | `questionId`（必填）、`knowledgePointIds`、`subjectKey`、`questionType`、`sourceLevel`、`difficulty`、`actionTypes`、`sourcePriority` |
| `SimilarityWeights` | `knowledgePoint` 0.50 / `actionType` 0.30 / `subject` 0.10 / `difficulty` 0.10（`normalized()` 归一化） |
| `SimilarQuestion` | `questionId`、`score`、`components`（四个分量各自的值）、`sharedKnowledgePointIds`、`sharedActionTypes`、`crossSubjectTransfer`、`reasonZh`、`toJson()` |
| `SimilarQuestionFinder.rank({focus, candidates, limit = 10, minScore = kMinSimilarityScore, weights, knowledgePointNames})` | `List<SimilarQuestion>` |
| `SimilarQuestionFinder.knowledgePointOverlap` / `actionSequenceOverlap` | 两个分量的单独入口（测试与 UI 可复用） |

`kMinSimilarityScore = 0.25`：只是同学科、同难度的"陌生人"（0.20）**不进榜**——阈值调低就不是"相似"而是"随便给一道"。

应用层（`features/questions/application/similar_question_provider.dart`）：

| provider | 读什么 |
|---|---|
| `chainActionTypesProvider` | `reasoning_chains` + `reasoning_steps` 各查一次；每题取**最新一条链**（`createdAt` 毫秒，平手比 id）的步骤 `actionType`（`idx` 升序） |
| `similarCandidatesProvider` | 复用 Q11 的 `paperCandidatesProvider`（题干为空的题不进题库）+ 上面的动作序列 |
| `similarQuestionFocusProvider(questionId)` | 先从候选快照里找；找不到（题干为空的脏行 / 刚被删）回落到直接读 `Questions` 一行 |
| `similarQuestionsProvider(questionId)` | focus + candidates + `paperKnowledgePointLabelsProvider`（知识点名字）→ `rank(...)`，默认上限 10 |

题目的覆盖知识点一律走 Q11 那条桥：`TaskKnowledgePointResolver.resolveFromTagLinks(links, sourceObjectType: kQuestionObjectType)`
（题目与知识点挂**同一个标签**才算相连）。来源中文名不在这里重复实现：`question_vocab_labels.dart` 的
`sourceLevelLabel(l10n, …)` 是全 app 唯一一份。

## 3. 怎么打分

四个分量各自落在 `[0, 1]`，缺失一律取**中性 0.5**，绝不因为"不知道"而扣分：

- **共用知识点** = 交集大小 / focus 的知识点数（focus 没有知识点 → 0）。
- **同型动作** = **最长公共子序列**长度 / focus 的动作数（截断到 50 步防长链）。
  用 LCS 而不是集合交集：解题是一串**有顺序**的动作，顺序不同就是不同的解法。
- **学科**：相同 → 1.0；都非空且不同 → 0.0；任一侧为空 → 0.5（"不知道"不惩罚）。
- **难度**：两侧都有读数 → `1 - |Δ| / 9`（钳 0..1）；任一为空 → 0.5。

`score = Σ wᵢ · componentᵢ / Σ wᵢ`。排序：`score` → 共用知识点多 → 同型动作多 → 来源分级高 → 题目 id 升序
（同输入必同输出，与候选顺序无关）。`limit > 0` 才截断。

理由行（`reasonZh`，确定性中文模板，与 `PaperComposer` 同规矩）依次讲：共用知识点（有名字用名字，最多列 2 个）、
同型步骤（用词表的中文标签，词表外的 key **原样显示**不隐藏）、跨学科迁移、难度、来源分级。
一个弱信号都没有时兜底成"同学科、难度接近，但还没有可对照的知识点或思维链"。

## 4. 刻意未标定 / 已知缺口

- **权重与阈值是显式但未标定的取值**（0.50/0.30/0.10/0.10、`0.25`）。标定需要真实使用数据，另开协议（与 Q9 的权重同一处境）。
- `actionSequenceOverlap` 是 O(n·m) 的 LCS，链长上限 50；题库量级（每天 30 道）远不够触发性能问题，**没有索引**。
- 相似题只按"库内线性扫描"找；将来要更快，先加索引/缓存，不先引向量库。
- 找不到相似题时页面只说"库里还没有相似的题"，并给出收题入口——**不给"看着像"的题凑数**。
- UI（题目详情页的"找相似题"区块）尚未完成；本片只到 provider，AI 工具面见 §6。
- 相似结果**没有题干字段**（`SimilarQuestion.stem` 不存在）：领域层不搬运文案，谁展示谁按 id 读题干
  （AI 工具用 `question_corpus_reader.dart` 的 `readQuestionStems`，UI 复用 `questionLibraryProvider`）。

## 5. 验收记录

- `app/test/domain/services/paper/similar_questions_test.dart` → **14 例全绿**：共用知识点排序与分量；自己不推荐自己；跨学科同型 → 迁移标记；**LCS 顺序**（逆序分更低、空序列 0）；缺学科/缺难度取中性；难度差越大分越低；弱信号不过阈值（阈值调低才进）；`limit` 语义；**调权改变排序**；tie-break 与输入顺序无关；`reasonZh` 各段（含未知动作原样显示与兜底句）；输入清洗（空白/重复）；`toJson`；空候选不抛。
- `app/test/features/questions/application/similar_question_provider_test.dart` → **6 例全绿**：共享知识点 + 同型动作入榜且理由讲同型步骤；跨学科 → 迁移候选；没链时只用结构信号；**多条链只认最新**（旧链不算数，两道结构分相同的题因此分出高下）；题干为空的脏行不进候选但仍能当基准题（回落读行）；不与自己配对 / 无相似题 / 不存在的题都返回空列表。
- `app/test/features/ai/question_tools_test.dart` → **11 例全绿**：只读构造（两种权限模式都不逐条询问 + 调用前后整库指纹相同）；
  按 `question_id` 找到并给出题干摘要/理由/中文动作名/四个分量；长题干截断；id 不存在 → `ok:false`；
  题干为空的脏行当基准 → 0 条；只给条件（知识点 + 动作）能找到；无基准 → 失败；题库空 → ok + 0 条；
  `limit` 默认 5 且钳 1..20；注册进 `ToolRegistry.forApp` 且 schema 键齐全。
- 回归：`flutter test test/domain/services/paper test/features/questions/application test/features/ai` → **+385 全绿**
  （读表抽出共享函数后，组卷/找相似题 provider 与全部 AI 工具测试都过）。
- `dart analyze lib test` → 0 error / 0 warning / 94 info（= 基线）。

## 6. AI 工具面：`find_similar_questions`

Q12 的能力不只给页面用——agent 也应该能"找题"而不是"编题"。工具
`app/lib/features/ai/tools/question_tools.dart` 的 `FindSimilarQuestionsTool`（注册在 `ToolRegistry.forApp`，
`app/lib/features/ai/domain/tool_registry.dart`）把同一套领域逻辑暴露给模型：

| 入参 | 说明 |
|---|---|
| `question_id` | 基准题（库里已有）；给了但查不到 → `ToolResult.failure`，不静默换题 |
| `knowledge_point_ids`、`action_types`、`subject_key`、`question_type`、`difficulty` | 没有基准题时的显式条件；**至少要给一个**，否则失败并说明怎么给 |
| `limit` | 默认 5，钳 1..20 |

- `readOnly => true`（不写任何表，测试用整库指纹证明）；返回 `modelResult.questions[]` 带
  `id` 与**截断到 120 字的题干摘要**、`score`、四个 `components`、`shared_knowledge_point_ids`、
  中文知识点名、`shared_action_types` + 中文动作标签、`cross_subject_transfer`、`reason`。
- 题库为空、或**一道都不够像**时也返回 `ok: true` + 明确的中文说明（"我不会自己出题，要么去收题页补题，
  要么放宽条件"）——工具不许拿"看着像"的题凑数，也不许替模型生成题干。
- **`compose_paper` 工具已补上**（原计划"本轮不做"，后由 `library_diagnosis_reader.dart` 把诊断抽成
  非 Riverpod 读取后落地）：入参、`modelResult` 字段与"没凑够就直说"的摘要口径见
  `docs/PAPER_COMPOSER_DESIGN.md` §9。`compose_paper` 与组卷页读的是**同一份** `readLibraryDiagnosis` /
  `readPaperReadings`，所以同一个知识点不可能这边说危险、那边说健康。
- 读表主体抽到 `app/lib/features/questions/application/question_corpus_reader.dart`
  （`readPaperCorpus` / `readChainActionTypes` / `readQuestionStems`，纯 Dart 无 Riverpod），
  两个 provider 变成瘦包装（仍各自 `ref.watchDatabaseRevision()`）；`paper_plan_provider.dart`
  继续 `export` 这些符号，调用方路径不变。
