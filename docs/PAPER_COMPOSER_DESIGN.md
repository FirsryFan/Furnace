# 组卷器设计（Q9：按"练什么最值"凑一份卷子）

> 用户口径（历史记录）：
> * 组卷要**按薄弱/危险区知识点精准凑题**，而不是按时间或随机抽；
> * 每题要附**提升点建议**与**知识背景**，让人知道"为什么做这道、做完下一步做什么"；
> * **AI 不能自己出题，只能找相似题**——所以凑不出题时如实报缺口，绝不用模型生成题填空；
> * 高价值题源是**高考真题 / 部分名校测试 / 强省强市诊断的高质量模拟**，重点在"选择与加工"。

## 1. 这一层负责什么、不负责什么

| 负责 | 不负责 |
|---|---|
| 从**已有**候选里挑题、排序、配额分散 | 读数据库（由调用方把行转成 `PaperCandidate`） |
| 每题给出**理由**、提升点建议、知识背景 | 生成题干/答案/解析（AI 只解题、拆题、找相似题） |
| 如实报出**凑不出来的知识点**与**被挤掉的薄弱点** | 标定权重（当前取值是显式的先验，见 §4） |
| 确定性：同样输入永远同样卷子 | 决定"今天练哪些知识点"（那是 threadflow/认知模型的事） |

实现：`app/lib/domain/services/paper/paper_composer.dart`（纯逻辑：不 import drift、不 import Flutter）。

## 2. 输入契约

- `PaperCandidate`：题库里一行的投影 —— `questionId`、`subjectKey`、`sourceLevel`、
  `questionType`、`difficulty`、`aiQuality`、`trapNote`、`matchedKnowledgePointIds`。
  - `matchedKnowledgePointIds` 由 **共享标签规则**推出：
    `TaskKnowledgePointResolver.resolveFromTagLinks(links, sourceObjectType: kQuestionObjectType)`。
    题目挂不上任何知识点 → 空列表 → 该题按"未标注"参与（不会被丢掉，但排在未知之后）。
  - `sourceLevel` 的 [0,1] 优先级表 `kSourceLevelPriority` 与仓储
    `kSourceLevelWeight` **同序**，由单测钉住（`question_repository.dart` 那张是检索排序用的分值）。
- `KnowledgePointReading`：直接复用 threadflow 的读数类型（`scheduling/domain_balance.dart`），
  由 `CognitiveReadingsAdapter.readingsFor` 从"认知页诊断 + 测评先验"拼出来
  （键是**知识点 id**；`BottleneckType.danger → inDangerZone`、`.weak → inDevelopmentZone`）。
- `PaperSpec`：`targetCount`、`subjectKeys`、`perKnowledgePointCap`、`targetDifficulty`、`minSourceLevel`。

## 3. 三步：过滤 → 打分 → 带配额的贪心

1. **过滤**：学科白名单、来源分级下限（`kSourceLevelPriority` 比较）。
2. **打分**（归一化权重 `need / quality / difficultyFit`）：
   - `need = paperNeedOf(reading)`：危险区 `1.0` > 发展区 `0.6` > **没有读数 `0.35`** > 已知健康 `0.15`。
     "不知道"排在"已知健康"之前是刻意的：缺数据不许冒充好数据（与 D2 口径一致）。
   - `quality = sourcePriority * 0.7 + qualityScore * 0.3`（来源分级为主，AI 加工质量为辅）。
   - `difficultyFit`：给了 `targetDifficulty` 才区分（`1 - |d - target| / 9`），否则恒为中性 `1.0`。
   - 一道题挂多个知识点时：`need` 取**最该练的那个**，它就是这道题的 `knowledgePointId`（"最主要在补哪个点"）。
   - **能力动作偏好（轮次一百零三）**：候选带着"最新一条解题链的动作序列"（`PaperCandidate.actionTypes`），
     调用方再传"我最该练的动作"（`preferredActionTypes`，来自能力动作画像，最多取 3 个）。命中比例
     `actionFit = 命中数 / 偏好数`，总分乘 `1 + kPreferredActionBoost * actionFit`（`kPreferredActionBoost = 0.15`）。
     命中的动作会写进 `PaperItem.matchedPreferredActions`，理由行补一句"这题会练到「分类讨论」这类动作"。
     没有偏好时乘数恒为 1，历史行为一个字节不变。
   - **可关（轮次一百零四）**：`PaperSpec.preferCapabilityActions`（默认 `true`）。组卷页给一个
     `SwitchListTile`（标题带"未标定"、副标题说明"没有解题链时不起作用"），关掉后 provider 传空的偏好列表，
     卷子与"没有画像"逐字段一致；`PaperPlan.preferredActionTypes` 如实回报这一卷到底参考了哪些动作
     （空 = 没参考），页面据此显示/隐藏"这一卷按「…」这类动作排过（未标定，可关）"那一行。
3. **配额 + 贪心**：`perKnowledgePointCap` 缺省时按 `ceil(targetCount / 有候选的知识点数)` 自动算，
   下限 1。按分数降序选（tie-break：分数 → 来源分级 → AI 质量 → 题目 id），
   候选挂的每个知识点都算过配额；**全部**挂载点都到配额才跳过它。`items` 的顺序就是贪心选择顺序
   （配额会消耗，所以它不是单纯的分数降序，界面**不许**按 `score` 重排渲染）。

## 4. 刻意未标定 / 已知缺口

- 权重 `PaperWeights(need .55, quality .25, difficultyFit .20)`、`kSourceLevelPriority` 的档位间距、
  以及 `kUnknownNeed = 0.35`，都是**显式但未标定**的先验。它们的相对大小有理由（见 §3），
  具体数值要靠真实使用后的读数回填（标定协议仍未做）。
- `aiQuality` 假定 0..1 并 clamp；题库里目前大多数题这个字段是空的，于是 `quality` 只剩来源分级。
- "找相似题"没有做：本层只在**已有候选**里选，缺口只报不补。
- 中文文案（`reasonZh` / `improvementNote` / `backgroundZh`）是领域层的一部分，
  故意不放在 ARB：措辞要能跟着规则一起改，且界面不许另写一套。l10n 化留后轮（同 threadflow 的 `reasonZh`）。
- **能力动作加成 `kPreferredActionBoost = 0.15` 也是未标定的**：刻意保守（只让命中项排前面一点），
  不做硬过滤——当成过滤会把"没解过链的题"整体排除，那就不是"练得准"，而是"只练解过的题"。
  命中上限 3 个动作：再多会让整份卷子被同一类动作占满，挤掉"按薄弱知识点凑题"这条更硬的依据。
- 调用方（组卷页 UI）还没做：Q10。它依赖的**输入拼装**已经做完（§7，Q11）：
  `paperPlanProvider` 给出 `PaperPlan`，页面只负责渲染与改 `paperSpecProvider`。

## 5. 输出契约

`PaperPlan`：
- `items`：`PaperItem{questionId, subjectKey, sourceLevel, questionType, knowledgePointId?, matchedKnowledgePointIds, zone, need, quality, score, reasonZh, improvementNote, backgroundZh, matchedPreferredActions}`（最后一项 = 命中的"最该练的动作"，空 = 没命中）。
- `uncoveredKnowledgePointIds`：危险/发展区**但题库里一道候选都没有**的知识点 → 这是"该去收题"的清单。
- `deferredKnowledgePointIds`：有候选但这轮没排进来（数量/配额限制）。
- `byKnowledgePoint`：每个知识点实际排了几道（含被第二知识点"顺带覆盖"的）。
- `candidateCount`、`requestedCount`、`isShort`、`overallNeed`、`weights`、`preferredActionTypes`（这一卷参考了哪些"最该练的动作"，空 = 没参考）。
- `toJson()` schema `mindnet.paper_plan/1`，所有 double 过 `DsrMemory.round6`。

## 6. 验收记录（本轮）

- `app/test/domain/services/paper/paper_composer_test.dart` → **16 例全绿**，覆盖：
  来源表同序、危险区压过高来源题、同分比来源、输入顺序无关、显式配额、缺省配额跨点分散、
  缺口上报、被挤掉上报、缺读数当未知且优先于健康、学科/来源过滤、目标难度、理由/提升点/背景
  （含 `trapNote` 与 R0 后缀）、背景回退链（标签路径 → 名字 → id → "未标注知识点"）、
  空库不抛、`toJson`、以及"题目→知识点走 `kQuestionObjectType` 共享标签规则"的跨层一条。
- 全量测试见 `docs/PROGRESS.md` 轮次三十一。

## 7. 接线：从数据库到一份卷子（Q11）

`app/lib/features/questions/application/paper_plan_provider.dart` 是本层唯一的 IO 点，
顺序是**读表 → 拼候选 → 取读数 → 交给纯逻辑**：

| provider | 作用 |
| --- | --- |
| `paperCorpusProvider` | 读一次题库：`Questions` → `PaperCandidate`；`KnowledgePoints` → 名字；`Tags.path` + `ObjectTags` → 知识点直挂的标签路径。**题干为空的题不进卷**（没有题干就没法出卷）。 |
| `paperCandidatesProvider` / `paperKnowledgePointLabelsProvider` / `paperSubjectOptionsProvider` | 从语料投影出的三项，供页面显示候选数、名字与学科 chip——一个语料 provider，避免同一个页面读三次表。 |
| `paperSpecProvider`（`PaperSpecNotifier`） | 用户手上的要求（题量 / 学科 / 来源下限 / 目标难度 / 每点上限），默认 10 题、不筛学科。 |
| `paperPlanProvider` | 当前要求下的 `PaperPlan`；题库为空时给空卷（`items` 空、`candidateCount` 0），页面据此显示"题库还没有题"而不是报错。 |

三条纪律：

1. **题目 → 知识点走"共享标签"**：`TaskKnowledgePointResolver.resolveFromTagLinks(links, sourceObjectType: kQuestionObjectType)`。
   同一标签既挂题目又挂知识点，才认为这道题覆盖那个点（`docs/QUESTION_BANK_DESIGN.md` §5）。
2. **诊断复用认知页的那一次**（`cognitiveLibraryDiagnosisProvider`，D2：一个数字一个来源）。
   `fastLayerRan == false` 是"这轮没跑"，传 `null` 给投影层，全部按未知处理——**不**当作健康。
   键空间已由 Q8 在 `LibraryDiagnosisRunner.run` 的边界统一成知识点 id，这里不需要再翻译
   （`domain/services/cognitive/knowledge_point_tag_bridge.dart`）。
3. **只有诊断结论（`danger` / `weak`）才进打分读数**。`CognitiveReadingsAdapter` 会为"只有测评先验"
   的点也产出读数，而组卷器把"不是危险区也不是发展区"读成 `healthy`（need 0.15，**低于**未知的 0.35）
   ——直接喂进去等于把"没测过"当成"学得好"。过滤后：没有结论的点按未知，先验仍作为已诊断点的
   R0 补充（理由行带 `R0≈…、置信度 …`）。

已知的保守取值：除 `danger` / `weak` 之外的诊断结论（`empty` / `slow` / `overload` / `offGoal` /
`deadEnd`）本轮也落进"未知"档（0.35），拿不到"健康"分。要不要给它们单独成档，等有真实读数再定。

## 8. 验收记录（接线，Q11）

- `app/test/features/questions/application/paper_plan_provider_test.dart` → **9 例全绿**：空库给空卷、
  共享标签 → 危险区进卷且理由行念名字（断言里不含 `kp-`）、诊断没跑 → 未知而非健康、没挂点的题也进卷、
  **只有先验的点不当作健康**（并留一条对照断言钉住"不过滤就会变健康"）、学科/题量/来源下限真的进卷、
  目标难度生效、**危险区知识点库里没候选 → 进 `uncoveredKnowledgePointIds`**、
  `PaperSpecNotifier` 的钳位/清空/二次点击取消/`reset()`。
- 写这组测试时抓到并修掉一个真 bug：`setMinSourceLevel` / `setTargetDifficulty` /
  `setPerKnowledgePointCap` 曾经**无条件**清空可空字段（`clearX: true` 恒真），等于三个 setter
  都只会把值设成 `null`；测试先失败，改成分支后转绿。
- 全量：`flutter test --concurrency=1` → `+1321 ~2 All tests passed!`（见 `docs/PROGRESS.md` 轮次三十二）。

## 9. AI 工具面：`compose_paper`（Q14）

组卷能力不只给页面用：agent 也能"按薄弱点凑一份卷子"，但**只读、不编题**。
`app/lib/features/ai/tools/paper_tools.dart` 的 `ComposePaperTool`（注册在 `ToolRegistry.forApp`）：

| 入参 | 默认 | 说明 |
| --- | --- | --- |
| `target_count` | 10 | 想要几道；钳 1..50，真实生效值在 `modelResult.requested_count` |
| `subject_keys` | 空 = 不限 | 只从这些学科凑 |
| `min_source_level` | 不限 | 必须是 `kSourceLevelPriority` 的键（`gaokao` / `provincial_diagnostic` / `elite_school` / `school` / `personal` / `unknown`），否则失败并列出可用值 |
| `per_knowledge_point_cap` | 不限 | 每个知识点最多几道；< 1 → 失败 |
| `target_difficulty` | 不限 | 1..10；越界 → 失败 |
| `use_capability_profile` | `true` | 要不要参考"我最该练的动作"（未标定）；`false` 时卷子与没有画像一致 |

- `readOnly => true`（测试用整库指纹证明），`riskFor => ToolRisk.write`（无 action 的中性值，ApprovalEngine 不逐条询问）。
- 读数走 `library_diagnosis_reader.dart`（`readLibraryDiagnosis` + `readPaperReadings`）——**与组卷页同源**，
  所以同一个知识点不会这边危险、那边健康；`diagnosis_ran == false` 时摘要明说"按没有读数处理，**不是**健康"。
- `modelResult`：`requested_count` / `item_count` / `is_short` / `candidate_count` / `bank_size` / `overall_need` /
  `diagnosis_ran` / `readings_used` / `preferred_action_types`（能力动作偏好，轮次一百零三）/
  `uncovered_knowledge_point_ids`（带中文名）/ `deferred_knowledge_point_ids` /
  `by_knowledge_point` / `items[]`（题号、知识点、学科、来源、`zone` + `zone_zh`、`need` / `quality` / `score`、
  `reason` / `improvement_note` / `background`、命中时的 `matched_preferred_actions`）。
- 凑不够时**不生成题目**：摘要直说"题库不够，缺口去收题页补"，把未覆盖/被挤掉的清单原样回给模型。

## 10. 验收记录（AI 工具面）

- `app/test/features/ai/paper_tools_test.dart` → **13 例全绿**（见 `docs/PROGRESS.md` 轮次三十五；轮次一百零三
  加 1 例：工具挑卷子同样用能力动作偏好，`preferred_action_types` 与 `items[].matched_preferred_actions` 都摆出来）。
- `app/test/features/cognitive/application/library_diagnosis_reader_test.dart` → **4 例全绿**，含一条 parity：
  非 Riverpod 读取与页面三个 provider 逐字段一致。
- 回归：`flutter test test/features/ai test/features/questions test/features/cognitive --concurrency=1` → **+430 全绿**。

## 11. 能力动作偏好接线（轮次一百零三）

页面与工具**同源**地接上了"我最该练的动作"：

- **页面**：`paperPlanProvider` 读 `capabilityProfileProvider`（推理层画像）取"平均风险 ≥ 0.6"的前 3 个动作，
  再从 `readChainActionTypes(db)` 给每个候选补 `actionTypes`，一起传给 `compose(preferredActionTypes:)`。
- **工具**：`ComposePaperTool` 走同一份纯函数（`CapabilityProfile.of` + `readChainActionTypes`），
  `modelResult.preferred_action_types` 与 `items[].matched_preferred_actions` 都如实带出。
- **没画像时**：偏好为空 → 乘数恒为 1 → 卷子与轮次一百零二之前逐字段一致（有回归测试钉住）。
- 验收：`paper_composer_test.dart` **18 例**（含"偏好只影响次序不过滤""命中两个 > 命中一个"、
  "没有偏好时同分"）；`paper_plan_provider_test.dart` **10 例**（含真库链 → 页面 provider 的排序与理由）；
  `paper_tools_test.dart` **13 例**。

## 12. 可关 + 可见（轮次一百零四）

轮次一百零三的加成是**自动生效**的：用户看不到"这一卷被一条没标定的先验排过"，也没法关掉。这一轮补齐
两件事（与仓库对未标定参数的一贯纪律一致：显式标注、能关）：

- **开关**：组卷页多一个 `SwitchListTile`「按能力动作画像排（未标定）」，副标题说明"命中「你最该练的动作」
  的题往前排一点；没有解题链时不起作用，可以关"。`PaperSpec.preferCapabilityActions`（默认 true）经
  `paperSpecProvider` 进入 `paperPlanProvider`；关掉时偏好列表为空，卷子与"没有画像"逐字段一致。
  「重置组卷条件」把开关也带回默认。
- **可见**：`PaperPlan.preferredActionTypes` 如实回报这一卷参考了哪些动作；页面只在非空时显示
  "这一卷按「分类讨论」这类动作排过（未标定，可关）"那一行——空的时候不摆空话。
- **工具同源**：`compose_paper` 多一个 `use_capability_profile`（默认 true），`modelResult` 里
  `preferred_action_types` 与 `capability_profile_used` 如实反映用没用；关掉时 payload 里不再出现
  命中字段。
- 验收：`question_paper_page_test.dart` 21 → **22 例**（开关/说明/说明行都在；关掉后说明行消失、
  次序回到按 id 兜底、重置把开关带回默认）；`paper_plan_provider_test.dart` 10 → **11 例**（关掉后
  `preferredActionTypes` 空、命中项全空、理由行不再提画像）；`paper_tools_test.dart` 13 → **14 例**。

## 13. 学科配额：按学科上限与保底（轮次一百二十四）

需求：一份卷子里的学科比例要可控（用户点名的「领域配额」先落在 `subjectKey` 这一层；按顶级领域标签祖先做映射仍未做——两者口径不同，见 `docs/THREADFLOW_TWO_SEGMENT.md` 的领域配额）。

- **API**：`SubjectQuota`（纯逻辑，`app/lib/domain/services/paper/subject_quota.dart`）—— 每科可给上限 `maxPerSubject` 与保底 `minPerSubject`；配置归一化（trim、排序、空键 / 负值 / 去重后重复键抛 `ArgumentError`、同科 min>max 抬上限）。`PaperSpec.subjectQuota`（默认 `null` = 不启用）进来，`PaperPlan` 新增 `bySubject` / `quotaBlockedQuestions` / `subjectShortfalls` / `subjectQuota` / `uncoveredSubjectKeys` 如实回报；`toJson` 只在启用时追加 `by_subject` / `quota_blocked_questions` / `subject_shortfalls` / `subject_quota` 四个键，schema 仍是 `mindnet.paper_plan/1`。
- **优先级与语义**：`targetCount` 是硬上限（不为保底多给题）> 保底阶段按学科键字典序补到 min（同时受 `perKnowledgePointCap` 约束）> 填充阶段按既有分数序（先知识点上限，再学科上限）。被学科上限挡下的候选、保底凑不够的缺口都写进 plan，**不静默丢题**；题库里一道都没有的学科进 `uncoveredSubjectKeys`。未列出的学科不限（空键也不限）；`maxPerSubject = 0` 表示该科不取。
- **默认关闭、旧行为逐字节不变**：`subjectQuota == null` 时不走新分支，旧 `toJson` 十个键的顺序与 `jsonEncode` 输出有回归测试钉住。
- **未做**：页面上还没展示 `bySubject` / 被挡题 / 保底缺口；配额数值**未标定**（没有真实数据支撑先给比例）。provider 与 `compose_paper` 工具的接线已在 §15 完成；按顶级领域标签祖先的映射见 §14。
- 验收：`test/domain/services/paper/subject_quota_test.dart` **33 例**（配置归一化与抛错 / 上限与保底 / 交错填充 / `targetCount` 硬上限 / 被挡与缺口回报 / `max=0` / 未列学科 / 默认 null 逐字节不变 / `toJson` 启用四键）。

## 14. 领域配额：按顶级领域标签的上限与保底（轮次一百二十五）

需求：§13 的学科配额按 `subjectKey` 控制比例，这一轮补上用户点名的另一半——按**顶级领域标签祖先**
（`knowledgePointTagPaths` 里每条标签路径的第一段，如 `物理/力学` → `物理`）设上限与保底，与
`docs/THREADFLOW_TWO_SEGMENT.md` 的领域配额口径对齐（那里是任务窗口的配额奖励，这里是组卷的选题目）。

- **API（纯逻辑，`app/lib/domain/services/paper/domain_quota.dart`）**：`DomainQuota` 每域可给上限
  `maxPerDomain` 与保底 `minPerDomain`；配置归一化（trim、键排序、空键 / 负值 / trim 后重复键抛
  `ArgumentError`、同域 min>max 抬上限 = 保底优先）。`DomainQuotaResolver.domainOfTagPath` 取一条
  标签路径的第一个非空段；`domainsByKnowledgePoint` 把每个知识点的多条标签路径汇总成领域集
  （排序去重、无领域知识点不进结果）；`questionDomains` 给一道题的领域集：**字典序第一个是主领域**，
  其余是附加领域。`PaperSpec.domainQuota`（默认 `null` = 不启用）进来，`PaperPlan` 新增 `byDomain` /
  `quotaBlockedByDomain` / `domainShortfalls` / `domainQuota` / `uncoveredDomains` 如实回报；`toJson`
  只在启用时追加 `by_domain` / `quota_blocked_by_domain` / `domain_shortfalls` / `domain_quota` 四个
  snake_case 键，schema 仍是 `mindnet.paper_plan/1`。
- **领域解析口径**：`knowledgePointTagPaths` 的每个元素必须是**一条完整标签路径**（与
  `question_corpus_reader.dart` 的 `Tags.path` 形态一致，如 `数学/函数/函数单调性`），不要传已切分的
  片段（`['数学','函数']` 会被当成两条路径）。一个知识点挂多条路径、一道题有多个知识点时取领域并集；
  **主领域只用于上限判定与缺口计数**，附加领域只进 `byDomain` 回报、不参与上限判定——所以
  `byDomain` 的条目数可以大于题目数。没挂标签路径的题按无领域处理：不占上限、不报领域、不进缺口。
- **优先级与冲突（次序写死并有测试）**：`targetCount` 硬上限 > 学科保底阶段（既有算法不变，此阶段
  不强制领域上限，学科保底优先于领域上限与领域保底）> 领域保底阶段（域键字典序补到 min，同时受
  `targetCount` / `perKnowledgePointCap` / 学科上限约束，学科上限挡下的候选只跳过、不记领域 blocked）>
  填充阶段（既有分数序：先知识点上限，再学科上限，最后主领域上限）。被学科上限挡下的候选记进
  `quotaBlockedQuestions`，不再重复记进 `quotaBlockedByDomain`；被领域上限挡下的记进
  `quotaBlockedByDomain`。未列出的领域不限；`maxPerDomain = 0` 表示该域不取。
- **不静默丢题**：被挡候选（`quotaBlockedByDomain`）、保底缺口（`domainShortfalls`，`selectedCount` 按
  主领域计、`availableCount` 是候选里主领域为该域的数量）、题库一道都没有的领域
  （`uncoveredDomains` / `isUncovered = true`）原样回给调用方。
- **默认关闭、旧行为逐字节不变**：`domainQuota == null`（或空表解析后不启用）时不走新分支，旧
  `toJson` 十个键的顺序与 `jsonEncode` 输出有回归测试钉住（含候选顺序无关的确定性用例）。
- **未做**：`paperPlanProvider` / `compose_paper` 工具未透传领域配额（纯逻辑已就绪，接线留下一轮）；
  页面上还没展示 `byDomain` / 被挡题 / 保底缺口；配额数值**未标定**（没有真实数据支撑先给比例）；
  领域解析依赖上层传完整标签路径，若上层改传片段形态会解析错（口径已写进代码注释）。
- 验收：`test/domain/services/paper/domain_quota_test.dart` **44 例**（配置归一化与抛错 / 解析主领域与
  多领域 / 上限 / 保底 / 未配置 / `max=0` / 无标签题 / 学科与领域同时启用时的次序 / 默认 null 逐字节
  不变 / `toJson` 启用四键），`flutter test test/domain/services/paper` **+122 全绿**。

## 15. 接线：学科配额进组卷 provider 与 compose_paper 工具（轮次一百二十四）

§13 的学科配额纯逻辑接进两条真实入口：组卷页的 spec 状态（provider）与 AI 工具 `compose_paper`。
领域配额（§14）仍只有纯逻辑，provider / 工具透传留给下一轮。

- **provider（`app/lib/features/questions/application/paper_plan_provider.dart`）**：
  `PaperSpecNotifier` 新增 `setSubjectQuota(SubjectQuota?)`（`null` 走清空分支）、`clearSubjectQuota()`、
  `setSubjectMax(String subjectKey, int? max)`、`setSubjectMin(String subjectKey, int? min)`。
  `max` 为 `null` 或负数表示删掉该科上限、`min` 为 `null` 或 `<1` 表示删掉该科保底，其余学科原样保留；
  空白键忽略。**空 `SubjectQuota`（两张表都空）视同不启用**：内部 `_applySubjectQuota` 用
  `quota.isEnabled ? quota : null` + `clearSubjectQuota`，避免在 spec 里留一个空壳对象；`reset()`
  回到 `subjectQuota = null`。`subjectQuota` 随 `PaperSpec` 原样流进 `buildPaperPlan` →
  `PaperComposer.compose`，装配代码不用改。
- **工具（`app/lib/features/ai/tools/paper_tools.dart` 的 `ComposePaperTool`）**：`compose_paper`
  新增可选参数 `subject_quota`，形如 `{"数学": {"max": 2, "min": 3}, "物理": {"max": 2}}`
  （学科键 → `{max, min}`，两个值都是非负整数，`max = 0` 表示该科不取）。`subjectQuota` 只接
  `PaperSpec.subjectQuota`；启用时 `modelResult` 追加 `by_subject` / `quota_blocked_questions` /
  `subject_shortfalls` / `subject_quota` 四键（与 `PaperPlan.toJson` 同源），摘要另外用大白话报：
  学科分布（按数量倒序、同数按学科键）、被学科上限挡下多少道、保底没凑够哪几科差多少（最多列 5 条，
  区分「可用候选不足」与「题库里这一科没有可用题」）。**不传或传空对象时输出与接线前一致**
  （有测试钉住）。
- **参数校验（全都给可执行的报错，不静默忽略）**：不是对象 / 学科键 trim 后为空 / 值不是对象 /
  字段不是 `max` 或 `min`（`{limit: 2}` 会被拒）/ 值不是非负整数 / 学科键 trim 后重复
  （`" math"` 与 `"math"`）/ 字段 trim 后重复，都抛 `ToolArgError` 写明原因；
  `SubjectQuota.resolve()` 抛的 `ArgumentError` 也转成 `ToolArgError`。
- **未做**：领域配额（§14）未接进 provider / 工具；组卷页还没有配额编辑控件与 `bySubject` /
  被挡题 / 保底缺口展示；配额数值**未标定**（没有真实数据先给比例）；`max` 与 `target_count` 的
  相互作用只靠测试覆盖，没在真库里手测。
- 验收：`paper_tools_test.dart` 14 → **22 例**（不传时四键缺席且摘要不变 / 上限生效 / 保底缺口 /
  保底学科无题 / `max = 0` / 空对象 / 形状与重复键报错 / schema 含 `subject_quota`）；
  `paper_plan_provider_test.dart` 11 → **14 例**（setter 语义与清空 / 空表视同不启用 / 真卷按配额）；
  两个文件全绿，`dart analyze lib test` 92 issues / 0 error / 0 warning（基线不变）。

下一轮（轮次一百二十五）在同一对入口上补领域配额透传，然后才是页面控件。

## 16. 接线：领域配额进组卷 provider 与 compose_paper 工具（轮次一百二十五）

§14 的领域配额纯逻辑接进两条真实入口（与 §15 的学科配额接线对称）：组卷页的 spec 状态（provider）
与 AI 工具 `compose_paper`。

- **provider（`app/lib/features/questions/application/paper_plan_provider.dart`）**：`PaperSpecNotifier`
  新增 `setDomainQuota(DomainQuota?)`（`null` 走清空分支）、`clearDomainQuota()`、
  `setDomainMax(String domain, int? max)`、`setDomainMin(String domain, int? min)`。`max` 为 `null` 或
  负数表示删掉该域上限、`min` 为 `null` 或 `<1` 表示删掉该域保底，其余领域原样保留；空白键忽略；
  `reset()` 回到 `domainQuota = null`。**空 `DomainQuota`（两张表都空）视同不启用**：内部
  `_applyDomainQuota` 用 `quota.isEnabled ? quota : null` + `clearDomainQuota`，不留空壳对象。
  `domainQuota` 随 `PaperSpec` 原样流进 `buildPaperPlan` → `PaperComposer.compose`，装配代码不用改。
- **工具（`app/lib/features/ai/tools/paper_tools.dart` 的 `ComposePaperTool`）**：`compose_paper` 新增
  可选参数 `domain_quota`，形如 `{"物理": {"max": 2}, "数学": {"min": 3}}`（领域键 → `{max, min}`，
  两个值都是非负整数，`max = 0` 表示该域不取，`min > max` 时保底优先）。启用时 `modelResult` 追加
  `by_domain` / `quota_blocked_by_domain` / `domain_shortfalls` / `domain_quota` 四键（与
  `PaperPlan.toJson` 同源）；摘要另外用大白话报：领域分布（按数量倒序、同数按领域键）、被领域上限
  挡下多少道、保底没凑够哪几域差多少（最多列 5 条，区分「可用候选不足」与「题库里这一领域没有可用
  题」）。**不传或传空对象时输出与接线前一致**（有测试钉住）。
- **参数校验（全都给可执行的报错，不静默忽略）**：不是对象 / 领域键 trim 后为空 / 值不是对象 /
  字段不是 `max` 或 `min` / 值不是非负整数 / 领域键 trim 后重复（`" 物理"` 与 `"物理"`）/ 字段
  trim 后重复，都抛 `ToolArgError` 写明原因；`DomainQuota.resolve()` 抛的 `ArgumentError` 也转成
  `ToolArgError`。空对象（或只有 `{"物理": {}}`）解析为 `null` = 不启用。
- **接线口径（领域从哪来）**：领域 = 知识点标签路径的第一段（`物理/力学` → `物理`）。组卷页与工具
  两条路都从 `PaperCorpus` 取 `knowledgePointTagPaths`（`app/lib/features/questions/application/
  question_corpus_reader.dart` 里由 `Tags.path` 拼出的**完整**路径），`buildPaperPlan` 原样传给
  `compose`（`app/lib/features/questions/application/paper_plan_builder.dart` 的 `knowledgePointTagPaths:
  corpus.knowledgePointTagPaths`）。任务书里提到的 `paperKnowledgePointTagPathsProvider` 在仓库中
  **不存在**（全库 grep 无匹配）；实际来源是 `paperCorpusProvider` 的 `knowledgePointTagPaths` 字段。
- **默认关闭、旧输出逐字节不变**：`domainQuota == null` 时不走新分支，旧 `toJson` 十键顺序与
  `modelResult` 输出不变（provider 与工具测试各有一条回归用例钉住）。
- **未做**：组卷页还没有领域配额编辑控件与 `byDomain` / 被挡题 / 保底缺口展示；配额数值**未标定**
  （没有真实数据支撑先给比例）；领域键与学科键是两套命名空间（领域键是中文标签第一段如 `物理`，
  学科键是 `math` / `physics`），不要混用。
- 验收：`paper_plan_provider_test.dart` 14 → **20 例**（setter 语义与清空 / 空表视同不启用 / 默认
  不启用时四字段为空且 `toJson` 无领域键 / 真卷上限生效 / 保底缺口 / 保底领域无题）；
  `paper_tools_test.dart` 22 → **30 例**（不传时四键缺席且摘要不提领域 / 上限生效 / 保底缺口 /
  保底领域无题 / `max = 0` / 空对象 / 形状与重复键报错 / schema 含 `domain_quota`）；两个文件与
  `test/domain/services/paper`（+122）全绿；`dart analyze lib test` 94 issues / 0 error / 0 warning
  （92 条基线 + 2 条来自他人未跟踪测试文件的 info；本轮四个文件 `No issues found!`）。

## 17. 组卷页学科配额 UI（轮次一百二十五）

- **文件与入口**：新增 `app/lib/features/questions/presentation/paper_subject_quota_view.dart`（474 行）；
  `PaperSubjectQuotaSection`（:149）插在组卷页 controls 之后（`question_paper_page.dart:102`），
  `PaperSubjectQuotaOutcome` 在空卷分支（:329）与非空卷 isShort 之后（:401）按条件展示。
  纯函数与常量：`parsePaperSubjectQuotaInput`（:59）、`paperSubjectQuotaSubjects`（:73）、
  `paperSubjectDistributionSorted`（:93）、`blockedPreviewLimit`（:110）、`blockedPreview`（:113）、
  `blockedHidden`（:120）、`stemPreview`（:130）、`paperSubjectLabelOf`（:139）。
- **交互**：只对已选学科逐个显示「上限 / 保底」输入；留空 = 不限；上限 0 = 这一科一道都不取；
  非法输入标红且不提交；「清空配额」一次性回 null（空表视同不启用，不留空壳）。输入框自持
  controller（`:289 _QuotaNumberField`），外部改动（清空/重置）会回写。
- **结果展示**：学科分布（数量降序、学科名升序）、被学科上限挡下（最多列 3 条 + 「还有 N 条」）、
  保底缺口（区分「题库里这一科没有可用题」与「可用候选不足」两种文案）；题干预览异步加载，
  未加载时回退成题号。
- **回归修复**：配额区带来页面上第 2 个 `TextButton`（「清空配额」），既有测试用「页面唯一
  TextButton」定位「复制卷面」导致 5 例失败。修法：复制按钮加 `questionPaperCopyButtonKey`
  （`question_paper_page.dart:87` 定义、:443 挂载），`question_paper_page_test.dart:828-838`
  的 helper 改为 `find.byKey`；该文件 23 例复跑全绿。
- **l10n**：14 个 key（`paperSubjectQuotaTitle` / `Hint` / `NoSubjects` / `MaxLabel` / `MinLabel` /
  `Clear` / `Invalid` / `Distribution` / `Blocked(count)` / `BlockedItem` / `BlockedMore` /
  `ShortfallTitle` / `Shortfall` / `ShortfallEmpty`），五个 l10n 文件手改（未跑 gen-l10n），
  zh 与 en 同步。
- **验收**：新增 `test/features/questions/presentation/question_paper_quota_test.dart` **16 例**
  （纯函数 9 + widget 7）；`flutter test test/features/questions/presentation` **+173** 全绿
  （158 → 173）；`dart analyze lib test` 92 issues / **0 error / 0 warning**；`dart format` 只
  自己改的文件。
- **未做 / 风险**：真机未手测（数字输入法是否拦截负号/小数点、聚焦与滚动）；配额区未做折叠，
  学科很多时行数线性增长未压测；en 文案未母语校对；领域配额 UI 不在本节（排队中）。

## 18. 组卷手工指定 / 排除题目（轮次一百二十六）

- **需求**：组卷时允许按题目 id 手工「必收」或「排除」若干题。纯逻辑（`app/lib/domain/services/
  paper/paper_composer.dart`），不连 DB、不碰 UI；默认关闭时输出与历史完全一致。
- **API（`paper_composer.dart` 当前行号）**：
  - `PaperSpec.manualIncludeQuestionIds`（构造 :200、字段 :253）与 `manualExcludeQuestionIds`
    （构造 :201、字段 :260）都是 `Set<String>?`：**null = 不启用**，非 null（**含空集**）= 启用。
  - `PaperPlan.manualSelectionEnabled`（:356 / :424）、`manualIncludedCount`（:357 / :427）、
    `manualMissingQuestionIds`（:358 / :430）、`manualSkippedQuestionIds`（:359 / :433）、
    `manualConflictQuestionIds`（:360 / :436）。
  - `toJson` 仅在启用时追加四个 snake_case 键，顺序在领域配额四键（若启用）之后：
    `manual_included_count` / `manual_missing_question_ids` / `manual_skipped_question_ids` /
    `manual_conflict_question_ids`（:491-498）。schema 仍是 `mindnet.paper_plan/1`。
  - `compose` 内的接线：`_ManualSelection.resolve(spec)`（:566）、`usable` 过滤同时应用排除与
    「必收绕过过滤」（:570-572）、必收入选块（:651-673）、填充去重条件（:728）、返回计划时的五个
    新字段（:912-916）。私有解析器 `_ManualSelection`（:1125）负责 trim / 丢空 / 去重 / 排序与
    冲突集合（`resolve` :1134、`_cleanIds` :1160）。
- **口径与优先级**：
  1. 排除优先级最高：被排除的题在打分之前就从 `usable` 移除，任何阶段都不会被选，也不进
     `candidateCount`。
  2. 必收题在**学科保底 / 领域保底 / 填充之前**强制入选；绕过 `subjectKeys`、`minSourceLevel`、
     难度等过滤条件，也不受知识点上限、学科上限、领域上限约束。
  3. 必收仍受 `targetCount` 硬上限：按 id 字典序（先 `trim` 去重）取前 k 个，装不下的进
     `manualSkippedQuestionIds`，不静默丢。
  4. 候选池里没有的必收 id 进 `manualMissingQuestionIds`；与排除冲突的 id 进
     `manualConflictQuestionIds`（排除生效，不算进卷、也不算缺失）。
  5. 必收题照常打分（分数 / 危险区理由照常可解释），并照常占用知识点、学科、领域配额计数，
     因此 `bySubject` / `byDomain` 会把它算进去，保底阶段不会为它重复补题。
  6. 同一 id 有多个候选行时取排序后最优的一条（`scoredById.putIfAbsent`，:656-658）。
  7. 空集语义钉住为「启用但没有任何必收/排除」；两个集合都 null 时分支不进入，旧 `toJson` 十键
     顺序与 `jsonEncode` 逐字节不变。
- **不静默丢题**：缺失、被 `targetCount` 挤掉、与排除冲突三类都写进计划字段与 `toJson`，调用方
  可原样展示给用户。
- **未做 / 风险**：`paper_plan_provider` 还没有 setter、`compose_paper` 工具还没有参数、组卷页
  还没有编辑控件与三类名单展示（provider / 工具 / UI 由 Lead 统一接线）；题目 id 由上层提供，
  拼写错误只会进 `manualMissingQuestionIds`（这是有意行为）；`candidateCount` 仍按打分后的
  `scored` 计数——必收题绕过过滤后也在其中，排除题已提前移除。
- **验收**：新增 `app/test/domain/services/paper/manual_selection_test.dart` **36 例**（默认关闭 6 /
  必收 7 / 排除 4 / `targetCount` 4 / 缺失冲突 5 / 汇总计数 4 / 确定性 4 / 边界组合 2）；
  `flutter test test/domain/services/paper` **122 → 158** 全绿；本文件 `dart analyze` `No issues
  found!`，只 `dart format` 自己改的两个文件。

## 19. 接线：手工指定/排除进组卷 provider 与 compose_paper 工具（轮次一百二十五）

§18 的手工名单纯逻辑接进两条真实入口（与 §15/§16 的配额接线同一对入口），让组卷页与 AI 都能
"我说了算"：

- **provider（`app/lib/features/questions/application/paper_plan_provider.dart`）**：
  `PaperSpecNotifier` 新增 `setManualIncludeIds(Set<String>?)` / `setManualExcludeIds(Set<String>?)`
  （整表替换；`null` = 不启用）、`clearManualSelection()`、`toggleManualInclude(String id)` /
  `toggleManualExclude(String id)`（已在名单里则移除、不在则加入；空白 id 忽略）。`_update` 新增
  `manualInclude` / `manualExclude` 与 `clearManualInclude` / `clearManualExclude` 两个清除开关，
  `clearManualSelection()` 与 `reset()` 都回到 `null`。**整表传空集 = 启用但无操作**（与 `null` 语义
  不同，钉在测试里）；`toggle` 把名单删空时回落到 `null`，不在 spec 里留空壳。名单随 `PaperSpec`
  原样流进 `buildPaperPlan` → `PaperComposer.compose`，装配代码不用改。
- **工具（`app/lib/features/ai/tools/paper_tools.dart` 的 `ComposePaperTool`）**：`compose_paper`
  新增可选参数 `manual_include_question_ids` / `manual_exclude_question_ids`（题目 id 数组）。
  描述里写明：放**题目 id**（不是题号）、排除优先、必收绕过筛选与配额但只受 `target_count` 约束。
  `_specOf` 通过新私有 helper `_manualIdsOf(args, key)` 解析：`null` → `null`；非数组 → `ToolArgError`；
  元素非字符串 / `trim` 后空串 / 去重后空集 → 报错或 `null`（空数组 = 不启用）。启用时 `modelResult`
  追加 `manual_included_count` / `manual_missing_question_ids` / `manual_skipped_question_ids` /
  `manual_conflict_question_ids` 四键（与 `PaperPlan.toJson` 同源，**不出现 `manual_selection_enabled`
  这种布尔**——四键出现即启用）；摘要另用大白话报：手工指定入选多少道、找不到哪些 id、哪些被
  `target_count` 挤掉、哪些与排除冲突按排除处理。
- **不静默**：三类名单原样回给模型与界面；不传两个参数时输出与接线前一致（有测试钉住四键缺席、
  摘要不提手工选择）。
- **未做**：组卷页还没有手工名单编辑控件与三类名单展示（留给 question-intake 的下一片）；
  题目 id 由上层提供，拼写错误只会进 `manualMissingQuestionIds`（§18 的有意行为）；没在真库里手测
  `target_count` 与必收的交互，只有单测覆盖。
- **验收**：`paper_tools_test.dart` 30 → **37 例**（不传四键缺席 / 必收绕过学科过滤 + 排除优先 + 冲突
  如实报 / `target_count` 挤掉进 skipped / missing id 报找不到 / 形状错误三类 / 空数组不启用 /
  schema 声明两参数）；`paper_plan_provider_test.dart` 20 → **24 例**（setter 语义 / 空白 toggle 忽略 /
  真卷按名单 / 默认不启用）。两文件合计 **+61 All tests passed**；scoped `dart analyze` 无 error /
  warning（唯一 info 是既有 `ai_chat_page_test.dart:63`）。
