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
