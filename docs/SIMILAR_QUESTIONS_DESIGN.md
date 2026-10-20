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
- 四个基础信号分开算、可调权：共用知识点、同型思维链动作、同学科、难度接近。
- 可选的第五信号：**MindNet 有效性**（`quality`）——候选与基准题共用的知识点越「该练」，排序越靠前；默认权重 0（未标定），开启后仍全离线、确定性。
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
| `SimilarityWeights` | `knowledgePoint` 0.50 / `actionType` 0.30 / `subject` 0.10 / `difficulty` 0.10 / `quality` **0.0（默认关闭，未标定）**（`normalized()` 归一化） |
| `SimilarQuestion` | `questionId`、`score`、`components`（四个基础分量 + `quality` 各自的值）、`sharedKnowledgePointIds`、`sharedActionTypes`、`crossSubjectTransfer`、`reasonZh`、`toJson()` |
| `SimilarQuestionFinder.rank({focus, candidates, limit = 10, minScore = kMinSimilarityScore, weights, knowledgePointNames, knowledgePointReadings = const {}, qualityTuning = const EffectivenessTuning()})` | `List<SimilarQuestion>` |
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

四个基础分量各自落在 `[0, 1]`，缺失一律取**中性 0.5**，绝不因为「不知道」而扣分：

- **共用知识点** = 交集大小 / focus 的知识点数（focus 没有知识点 → 0）。
- **同型动作** = **最长公共子序列**长度 / focus 的动作数（截断到 50 步防长链）。
  用 LCS 而不是集合交集：解题是一串**有顺序**的动作，顺序不同就是不同的解法。
- **学科**：相同 → 1.0；都非空且不同 → 0.0；任一侧为空 → 0.5（"不知道"不惩罚）。
- **难度**：两侧都有读数 → `1 - |Δ| / 9`（钳 0..1）；任一为空 → 0.5。
- **MindNet 有效性（可选）** = `questionQuality(基准题与候选的共用知识点, MindNet 读数)`：
  取共用知识点中有效性最高者（多知识点取 max，不取平均，避免「有一个弱点就拉平」）；**只用共用知识点**，
  跨学科纯动作迁移（没有共用知识点）一律中性 0.5，不拿候选题自己的弱点带偏榜单；
  没有任何读数 / 空知识点 → 0.5（缺失不惩罚）。公式与 `DomainBalanceRanker` 同口径，集中在
  `domain/services/paper/question_quality.dart`（`kNeutralQuestionQuality = 0.5`），未标定默认值仍是
  `EffectivenessTuning`：neutral 0.5 / dangerBoost 0.35 / developmentBoost 0.20 / priorWeight 0.30。

`score = Σ wᵢ · componentᵢ / Σ wᵢ`。排序：`score` → 共用知识点多 → 同型动作多 → 来源分级高 → 题目 id 升序
（同输入必同输出，与候选顺序无关）。`limit > 0` 才截断。

理由行（`reasonZh`，确定性中文模板，与 `PaperComposer` 同规矩）依次讲：共用知识点（有名字用名字，最多列 2 个）、
同型步骤（用词表的中文标签，词表外的 key **原样显示**不隐藏）、跨学科迁移、难度、来源分级。
一个弱信号都没有时兜底成"同学科、难度接近，但还没有可对照的知识点或思维链"。

## 4. 刻意未标定 / 已知缺口

- **权重与阈值是显式但未标定的取值**（0.50/0.30/0.10/0.10/0.00、`0.25`）。标定需要真实使用数据，另开协议（与 Q9 的权重同一处境）。
- **`quality` 默认 0.0 = 显式关闭**：接口、公式、`components`、理由句都已就位，但权重不打开时既有 14 例分数逐字节不变；打开前要先标定，否则等于拿一个没验证的信号压过知识点与动作。
- **provider 尚未接线**：`similarQuestionsProvider` 还没把 `CognitiveReadingsAdapter.readingsFor` 的读数传进 `rank`；接线只加一个可选参数，不改变页面行为（权重仍为 0）。页面接线与标定同批做。
- `actionSequenceOverlap` 是 O(n·m) 的 LCS，链长上限 50；题库量级（每天 30 道）远不够触发性能问题，**没有索引**。
- 相似题只按"库内线性扫描"找；将来要更快，先加索引/缓存，不先引向量库。
- 找不到相似题时页面只说"库里还没有相似的题"，并给出收题入口——**不给"看着像"的题凑数**。
- UI（题目详情页的"找相似题"区块）尚未完成；本片只到 provider，AI 工具面见 §6。
- 相似结果**没有题干字段**（`SimilarQuestion.stem` 不存在）：领域层不搬运文案，谁展示谁按 id 读题干
  （AI 工具用 `question_corpus_reader.dart` 的 `readQuestionStems`，UI 复用 `questionLibraryProvider`）。

## 5. 验收记录

- `app/test/domain/services/paper/question_quality_test.dart` → **7 例全绿**：无读数/空知识点 → 中性 0.5；危险区/发展区/是否已练（priorWeight）各自抬升有效性；多知识点取 max；读数缺失不惩罚；`EffectivenessTuning` 可覆盖；与 `DomainBalanceRanker` 同口径。
- `app/test/domain/services/paper/similar_questions_test.dart` → **20 例全绿**：共用知识点排序与分量；`quality` 权重为 0 时既有 14 例分数不变；开启权重后「共用知识点更该练」的题排序上移、`components['quality']` 有值；跨学科无共用知识点保持中性不带动榜单；没有 MindNet 读数时中性；理由句只在权重开启且非中性时追加「MindNet 有效性 X.XX」；自己不推荐自己；跨学科同型 → 迁移标记；**LCS 顺序**（逆序分更低、空序列 0）；缺学科/缺难度取中性；难度差越大分越低；弱信号不过阈值（阈值调低才进）；`limit` 语义；**调权改变排序**；tie-break 与输入顺序无关；`reasonZh` 各段（含未知动作原样显示与兜底句）；输入清洗（空白/重复）；`toJson`；空候选不抛。
- `app/test/features/questions/application/similar_question_provider_test.dart` → **6 例全绿**：共享知识点 + 同型动作入榜且理由讲同型步骤；跨学科 → 迁移候选；没链时只用结构信号；**多条链只认最新**（旧链不算数，两道结构分相同的题因此分出高下）；题干为空的脏行不进候选但仍能当基准题（回落读行）；不与自己配对 / 无相似题 / 不存在的题都返回空列表。
- `app/test/features/ai/question_tools_test.dart` → **11 例全绿**：只读构造（两种权限模式都不逐条询问 + 调用前后整库指纹相同）；
  按 `question_id` 找到并给出题干摘要/理由/中文动作名/四个基础分量（`quality` 权重 0，恒中性 0.5）；长题干截断；id 不存在 → `ok:false`；
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
  `components` 现在是**五个键**：四个基础分量 + `quality`。工具面没有接认知读数、权重默认 0，
  所以 `quality` 恒为中性 0.5（存在但不参与排序）；要真启用第 5 分量得先把 `knowledgePointReadings`
  传进来（页面侧同样未接线）。
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

## 7. 应用层接线：MindNet 读数进相似题 provider（轮次一百二十五）

§3 的第五分量（`quality`）在领域层早就就位，但一直没人把 `knowledgePointReadings` 喂进来——
页面 provider 只传了 `focus / candidates / knowledgePointNames`，所以 `quality` 恒中性。这一节
把它接上，并**保持默认排序不变**：

- **新增 `similarityWeightsProvider`**（`app/lib/features/questions/application/similar_question_provider.dart`，
  `Provider<SimilarityWeights>`，默认 `const SimilarityWeights()`，`quality = 0.0`）：
  相似度权重第一次有了单一覆盖点。要启用第 5 分量，覆盖这个 provider 并给一个**标定过**的
  `quality`（领域层 `SimilarityWeights.quality` 的文档写明了前置条件）。
- **只在 `quality > 0` 时才读诊断**：默认路径连 `cognitiveLibraryDiagnosisProvider` 都不 watch，
  没有新增 IO、没有 new failure mode，排序与接线前逐字节一致（测试钉住两个候选分数相同、
  理由句不含「MindNet 有效性」）。
- **读数复用组卷那条口径**：`readPaperReadings(db, coveredKnowledgePointIds: focus.knowledgePointIds,
  diagnosis: …)`——只有诊断结论为危险区/发展区（`danger` / `weak`）的知识点才有读数，
  「这轮没跑诊断」返回空读数而不是「健康」；共用点没有读数时领域层按 `kNeutralQuestionQuality = 0.5`
  处理。所以同一知识点在组卷页说危险、在相似题榜单里也按危险抬有效性，不会两处口径打架。
- **一个要记住的数学事实**：打开第 5 分量会让权重重新归一化，即使所有读数都是中性 0.5，
  总分也会从 `0.4` 抬到 `0.433`（`0.4 / 1.5 + 0.5 × 0.5 / 1.5`）。这不是"改写了排序"——
  两边同幅抬升，候选间的**相对**先后不变（有测试断言差值仍为 0）；但任何拿绝对分数做阈值
  的调用方要先知道这件事。
- **仍未做**：`quality` 数值**未标定**（没有真实数据先给比例，默认永远 0）；AI 工具
  `find_similar_questions` 仍未传 `knowledgePointReadings`（工具面 `components.quality` 仍恒 0.5）；
  页面与工具都没把 `similarityWeightsProvider` 暴露成用户可调项。
- **验收**：`app/test/features/questions/application/similar_question_provider_test.dart` 新增 3 例
  （共 9 例全绿）：默认权重不读诊断且分数相同；`quality > 0` + 诊断给出危险区 → 共用该知识点的题
  排前且理由含「MindNet 有效性」；`quality > 0` 但诊断没跑 → 顺序与默认一致、理由句不加 MindNet。
  `dart analyze lib/features/questions/application test/features/questions/application` → `No issues found!`。

## 8. 应用层接线：详情页理由打开 `detailedReasons`（轮次一百二十九）

领域层 §6 的详细理由开关（`rank(detailedReasons: true)`）此前**零调用**——页面拿到的
始终是短理由。这一片只打开页面侧开关，不动领域层、不动 AI 工具：

- `app/lib/features/questions/application/similar_question_provider.dart`（`similarQuestionsProvider`）
  调 `SimilarQuestionFinder.rank` 时传 `detailedReasons: true`；排序、分数、候选筛选逐项不变，
  只在这条理由后追加「可核实依据：…」。
- 可核实依据仍只写算得出来的东西（领域层文档 §31.1）：共用知识点 M/N 个、同型动作命中
  M 个（聚焦题 K 步）、两侧都已知时的来源档位对比；没有证据就一个字不加。
- AI 工具 `find_similar_questions` 走自己的 `rank` 调用（默认 `false`），输出长度与之前一致；
  页面要的是「为什么说它像」（人能点开核实），工具要的是省 token，两者口径不同是有意的。
- 验收：`similar_question_provider_test.dart` 第一例补 3 条断言（理由含「可核实依据」/
  「共用知识点 1/1 个」/「同型动作命中 2 个」），既有断言未见红。
