# 题库与推理层设计（schema v12）

> 状态：schema v12 已落地，页面与服务按本文档推进。
> 上游：`docs/ASSESSMENT_DESIGN.md`（测评层）、`docs/MINDNET_ROADMAP.md`（认知模型）。
> 用户口径（必须遵守）：**AI 不出题**，只解题、拆题、找相似题；来源的价值在**选择与加工**，不在数量；
> 每天约 30 道高价值题（高考真题 / 强省强市诊断 / 名校测试）进本地库，低价值题不进。

## 0. 这套东西在架构里的位置

```
Agent（省时间的交互层：收题、拍照整理、组卷、排程都从这里发起）
        │
应用领域：flashcard      threadflow      组卷搜题
        │                    │              │
        └──── 认知模型（个性化引擎：记忆层 + 推理层）────┘
                             │
                 标签系统（共同语言：object_tags）
                             │
                 本地数据（schema v12：题目 + 推理链）
```

- **题目**是「组卷搜题」的一等公民，也是推理层的载体：一道题 → 一条思维链 → 若干步骤。
- **能力动作（actionType）**是跨学科的公共词汇：数学/物理/化学/生物/语文/历史/信息学竞赛/强基
  共享同一批"思维动作"，所以用 OI/强基题做高强度训练时，练的是高考题同样需要的那块肌肉。

## 1. 题目实体

`questions`（`@DataClassName('Question')`）：

| 列 | 说明 |
|---|---|
| `id` | `Id.next('q')` |
| `stem` | 题干（纯文本；公式保留 LaTeX 原样） |
| `answer` | 参考答案（可空：有些题先只存题干） |
| `solution` | 解析（可空；AI 解题产出的思维链另存，见 §3） |
| `subjectKey` | 学科（自由字符串，默认 `''`） |
| `questionType` | `single_choice` / `multi_choice` / `fill_blank` / `solution` / `open` |
| `sourceLevel` | `gaokao`（高考真题）/ `provincial_diagnostic`（强省强市诊断）/ `elite_school`（名校测试）/ `school`（学校题）/ `personal`（自建或 Furnace 内产生）/ `unknown` |
| `sourceLabel` | 人可读来源，如「2024 湖南师大附中月考」 |
| `year` / `region` | 可空 |
| `difficulty` | 1–10，可空；优先用认知模型的难度先验，否则 AI 估计，标注在 `difficultySource` |
| `difficultySource` | `prior` / `ai` / `manual` / null |
| `stemFingerprint` | 题干指纹（去空白 + 标点归一后的 FNV-1a 64 位十六进制，纯 Dart 实现，不引依赖） |
| `trapNote` | 易错点/常见错因（加工产物，可空） |
| `state` | `raw`（刚进来）→ `structured`（结构化过）→ `processed`（已拆考点链/标注错因） |
| `aiQuality` | 0–1，AI 预评分；`aiQualityNote` 记理由 |
| `origin` | `manual` / `ai_scan`（拍照/文本扫描）/ `furnace`（在 Furnace 内自建） |
| `createdAt` / `updatedAt` | 毫秒时间戳 |

`question_options`（`@DataClassName('QuestionOption')`）：`id`、`questionId`、`label`（A/B/C/D）、`content`、`isCorrect`、`sortOrder`、`createdAt`。
选择题的正确答案同时写进 `questions.answer`（便于判分），选项表只负责呈现。

**来源分级只在"选择"环节用**：`sourceLevel` 决定权重与去重时的保留优先级，不决定题目本身的价值。

**来源元信息事后可改（轮次一百零一）**：`QuestionRepository.updateSource(id, {sourceLevel, sourceLabel,
year, region})` —— 只写这四列，`sourceLevel` 走 `kSourceLevelWeight` 白名单（写错当场抛
`ArgumentError` 并列出可用值），题干 / 答案 / 解析 / 加工列一个字不动。入口在题目详情页的「改来源」
（对话框里留空的字段 = 不改那一列；年份非整数或越界就停在对话框里报错）。理由：来源分级是检索排序与
`aiQuality` 权重的输入，粘进来时标不准的题不该永远停在"未标注"。

## 2. 去重与质量

- 入库前算 `stemFingerprint`；库内已有同指纹 → 不新增，返回既有题目并提示「疑似重复」。
- 指纹只解决**完全相同**；近似重复（同题不同排版）留给后续"找相似题"（按考点链 + 题型 + 知识点标签），
  本期不做向量检索（不引依赖）。
- `aiQuality` 由 AI 按（来源等级、年份新旧、考点覆盖、题干完整度）打分，用户可一键降权；
  排序检索时 `aiQuality` 是权重不是过滤器——**低分题不删，只压后**。

## 3. 推理链与步骤（推理层第一步：管道）

`reasoning_chains`（`@DataClassName('ReasoningChain')`）：`id`、`questionId`、`source`（`ai` / `user`）、
`model`（哪个模型解的，可空）、`summary`、`stepCount`、`createdAt`。

`reasoning_steps`（`@DataClassName('ReasoningStep')`）：`id`、`chainId`、`idx`（链内序号，从 0 起）、
`goal`（这一步要达成什么）、`actionType`（能力动作 key，见 §4）、`justification`（为什么这样走）、
`checkMethod`（怎么检验这一步）、`stuckRisk`（0–1，AI 判断的卡点风险）、`knowledgeHints`（JSON 数组，
相关知识点 id）、`note`、`createdAt`。

- 一条链 = 一次「AI 亲自解题」的产物；**同题可以有多条链**（不同解法/不同模型），不覆盖。
- 链与步骤都是**派生数据**：可以随时由 AI 重跑，所以不参与跨设备合并（同步三分类里的"派生"）。
- 错因加工写在两个地方：题目级 `questions.trapNote`；步骤级 `stuckRisk` + `note`。

**卡点评估（第二步，先管道后评估）**：把链当有序子图，用**学生**的认知状态沿链算"这一步他能不能走下去"
（步骤级信念/可提取性 + 分支处"他会走的下一步"与标准步骤的偏差），产出卡点报告与锚在该步的提示。
评估结果**不落库**（派生计算），需要留档时写进 `note`。

## 4. 能力动作词表

代码种子在 `app/lib/domain/services/reasoning/capability_action.dart`（`CapabilityAction.catalog`），
key 永久稳定、不本地化；界面用 `labelZh`。候选清单（可增删）：不变量识别、构造反例、极端化/边界检验、
化归、归纳、构造与放缩、对称性、量纲/量级检验、状态追踪、分解与不变量、建模成图、摊还/均摊、反证、
分类讨论、单调性、守恒量、信息/下界论证、从定义出发、类比迁移、回代检验。

用户随后可增删——**本期不改表**：词表在代码里，用户覆盖留到 v13（避免过早为"还没用上的编辑功能"加 schema）。

**动作画像（轮次一百零二）**：词表不只用来给步骤打标，还用来**聚合**——把已入库解题链的步骤按
`actionType` 分桶，算每个动作的条数/高风险条数/平均卡点风险（`capability_profile.dart`），在认知模型页
显示"最该练的动作"。聚合只信真有的读数、未知动作原样显示、空样本说空，口径见
`docs/REASONING_LAYER_DESIGN.md` §12。

## 5. 标签怎么用

- 题目与知识点：`object_tags`，`objectType = 'question'` / `'knowledge_point'`——**复用现有标签树**，不新建连接表。
- 步骤的能力动作：直接写 `actionType`，**不进 `object_tags`**（否则标签树被推理层污染，跨领域检索会变慢变糊）。
- 领域配额（threadflow）从任务的**顶级标签祖先**判定学科。

## 6. 收题入口（B 优先：App 内粘贴/拖拽）

一次收题的流程与不变量：
1. 粘贴文本或拖入图片/截图 → 先落 `attachments`（`ownerType='handwriting_intake'`）与 `state='raw'`。
2. AI 结构化（题干/选项/答案/解析/来源/年份/学科）→ 给你一张**校对表**。
3. **未点确认不入库**：校对表上的修改只在内存里，确认才写 `questions` / `question_options`。
4. 入库时算指纹、查重复；重复则提示并跳转到既有题目。
5. 确认后可选立刻「拆考点链」（调推理层）或先攒着批量拆。

## 7. 拍照 → 手写整理（用户选的第一条通路）

1. 拍照 → `attachments`（`ownerType='handwriting_intake'`）。
   §6 与本节共用**同一个** `ownerType`：进收题页的图片一律先当"待整理的手写/纸质材料"，
   整理成什么（题目 / 闪存卡 / MindNet 节点）是**下一步的产出**，不是落盘时就要决定的分类。
2. 视觉模型 OCR + 整理（复用 `features/ai/domain/vision_payload.dart` 与 `ai_attachment_store.dart`）。
3. 产出**三类待确认产物**：① 补充标签（挂到既有标签树）② 闪存卡（进复习队列前先确认）
   ③ MindNet 知识点节点（`knowledge_points` + 与标签的边）。
4. 全部走"待确认任务"清单，用户逐个确认；**确认前不写学习数据**（标签 / 知识点 / 闪存卡
   都是确认后才写）。待确认清单**自身**从 schema v13 起落盘，见下面第 5 条。
5. **落地**：§7.3–§7.4 的领域层与应用层见 `0ef0fa0`（Q13）——`handwriting_proposals.dart`
   （三类提案 + 严格解析 + 提示词）、`handwriting_proposal_service.dart`（`proposeFor` /
   `applyAll` + `handwritingQueueProvider`）；界面见 `63e04f0`（Q15，teammate `question-intake`）。
   **Q19（Lead）补上持久化**：`handwriting_intake_runs` + `handwriting_proposals` 两张表
   （schema v13）、`HandwritingProposalRepository`，`refresh()` 从库恢复提案与"已确认到哪一条"，
   重启不丢；重新整理时**内容逐字没变**的提案保留确认状态，内容变了的清掉（用户没确认过新版本）。
   界线不变：这两张表只存提案与确认状态，学习数据仍然只在确认后写。
   完整口径见 `docs/HANDWRITING_INTAKE_DESIGN.md`。

## 8. 同步三分类（新增成员）

| 分类 | 新表 | 理由 |
|---|---|---|
| 只追加 | `questions`、`question_options` | id 稳定、入库后不改；冲突时都保留 |
| 派生（不参与合并） | `reasoning_chains`、`reasoning_steps` | 可由 AI 重跑，导入后按需重算 |

同步时机不变：**Windows 出可发布 release 时做一次**（用户口径）。

## 9. 切片与验收

| 切片 | 内容 | 状态 |
|---|---|---|
| Q1 | schema v12 四张表 + 迁移 + 仓储 | 已完成（`7c8a254`） |
| Q2 | 收题页 B（粘贴/拖拽 → 校对 → 入库） | 已完成（`ee89c0c`） |
| Q3 | 拍照手写整理（附件落盘 + 待整理清单） | 已完成（`ee89c0c`，三类产物待确认队列见 §7.4） |
| Q4 | 推理管道：AI 解题 → 思维链 → 步骤结构化 → 能力动作标注 | 已完成（`6ffcce1`） |
| Q5 | 卡点评估（沿链跑学生状态，出提示） | 已完成（`6ffcce1`） |
| Q6 | threadflow 两段式（可行域 + MindNet 有效性与领域配额） | 已完成（`b43f53a`） |
| Q7 | 题目详情页：AI 解题 + 卡点叠加（把 Q4+Q5 接出 UI） | 已完成（teammate `question-intake` 交付） |
| Q8 | 观察层键空间统一（知识点 id ↔ 标签 id 的桥进领域入口） | 已完成（`9671739`） |
| Q9 | 组卷器（纯逻辑）：按薄弱/危险区精准凑题 + 每题理由/提升点/知识背景 | 已完成（`f46b731`） |
| Q10 | 组卷页 UI（调 Q9，展示理由与缺口，不吃 ARB 之外的措辞） | 已完成（`a5f5e23`，teammate `question-intake` 交付） |
| Q11 | 组卷 provider：题库 + 读数 → `PaperPlan`（本层唯一 IO 点） | 已完成（`d85e55b`） |
| Q12 | 找相似题（纯逻辑 `similar_questions.dart` + 应用层 provider） | 已完成（`6df76e5`；UI `9be4350`，teammate `question-intake` 交付） |
| Q13 | 拍照整理的"三类待确认产物"队列（§7.4）：领域层提案/严格解析/提示词 + 应用层服务 + 内存队列 provider | 已完成（本轮，Lead；设计见 `docs/HANDWRITING_INTAKE_DESIGN.md`） |
| Q14 | AI 工具面：`find_similar_questions`（`0ec1798`）+ `compose_paper`（本轮）——agent 能调用同一套领域逻辑，但**只读、不编题**，读数与页面同源（`library_diagnosis_reader.dart`） | 已完成 |
| Q15 | 拍照整理 UI：待确认队列页（逐个确认 / 整批确认）+ 入口 + ARB + widget 测试 | 已完成（`63e04f0`，teammate `question-intake` 交付） |
| Q17 | 组卷页补三个 spec 控件（目标难度 / 每知识点上限 / 重置） | 已完成（`fe1964a`，teammate `question-intake` 交付） |
| Q19 | 拍照整理的待确认清单持久化（schema v13 两张表 + 仓储 + `refresh()` 恢复 + 迁移/仓储测试） | 已完成（本轮，Lead） |
| Q20 | 组卷页「复制卷面」：卷面渲染成可打印纯文本（`renderPaperText`）+ 剪贴板 + ARB | 已完成（本轮，teammate `question-intake` 交付） |
| Q21 | 来源元信息事后可改：`QuestionRepository.updateSource`（四列白名单）+ 详情页「改来源」对话框 + ARB + 仓储/页面测试 | 已完成（轮次一百零一，Lead） |
| Q22 | 能力动作画像：`capability_profile.dart`（按动作聚合卡点风险，纯逻辑）+ `capabilityProfileProvider`（唯一 IO）+ 认知模型页卡片 | 已完成（轮次一百零二，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §12） |
| Q23 | 画像 → 组卷联动：候选带链上动作序列、组卷器加"最该练动作"透明加成、理由行说出来；页面 provider 与 `compose_paper` 同源 | 已完成（轮次一百零三，Lead；口径见 `docs/PAPER_COMPOSER_DESIGN.md` §11） |
| Q24 | 画像加成可见且可关：组卷页开关 + `PaperSpec.preferCapabilityActions` + `PaperPlan.preferredActionTypes` 回报 + 工具 `use_capability_profile` | 已完成（轮次一百零四，Lead；口径见 `docs/PAPER_COMPOSER_DESIGN.md` §12） |
| Q25 | 按能力动作找题：`readQuestionsForAction`（只认最新链）+ `questionsForActionProvider` + `CapabilityActionQuestionsPage` + 画像行点开作为入口 | 已完成（轮次一百零五，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §13） |
| Q26 | 按能力动作找题的工具面：`find_questions_by_capability`（只读、与页面同一份读表函数、词表外 key 失败并列可用值） | 已完成（轮次一百零六，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §13 工具面） |
| Q27 | 组合查询：`CapabilityQuestionQuery`（一组动作 + `match` 任一/全部 + 学科）+ `readQuestionsForCapabilities` + 工具参数升级（`action_types` / `match` / `subject_key`）+ 命中项如实回报 | 已完成（轮次一百零七，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §13） |
| Q28 | 组合查询上屏：页面学科 chip（走读表、不是前端过滤）+ `questionsForCapabilitiesProvider` + `CapabilityQuestionQuery` 值相等（可当 family 键） | 已完成（轮次一百零八，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §13） |
| Q29 | 组合查询第二步上屏：页面「再叠加一个动作」下拉 + 「两个动作都得出现在同一条链里」开关（走同一个 `questionsForCapabilitiesProvider`） | 已完成（轮次一百零九，Lead；口径见 `docs/REASONING_LAYER_DESIGN.md` §13） |

每片的验收不变：`dart analyze` 0 error / 0 warning；相关单测 + 全量 `flutter test` 绿；
同步本文档与 `docs/PROGRESS.md` / `docs/DATA_MODEL.md`；commit 并由 Lead 统一 push。

## 10. 验收记录（轮次一百零一，2026-10-18）

按本文档的五片逐条核过一遍，结论与证据：

| 片 | 交付物（代码位置） | 片级测试 |
|---|---|---|
| ① schema v12 题目实体 | `tables.dart` 的 `Questions` / `QuestionOptions` / `ReasoningChains` / `ReasoningSteps`；v13 两张拍照整理表；`question_repository.dart`（指纹去重、来源分级、加工列白名单） | `v12_migration_test`、`v13_migration_test`、`question_repository_test` |
| ② 收题页（粘贴优先） | `question_intake_page.dart`：粘贴 → AI/本机结构化 → 校对表 → 入库（未确认不写）；`file_picker` 选图入口 | `question_intake_page_test`、`question_repository_test` |
| ③ 拍照手写整理 → 三类待确认产物 | `handwriting_proposals.dart`（标签/闪存卡/知识点三类提案 + 严格解析）、`handwriting_proposal_service.dart`、`handwriting_queue_page.dart`、schema v13 落盘 | `handwriting_proposals_test`、`handwriting_proposal_repository_test`、`handwriting_proposal_service_test`、`handwriting_intake_store_test`、`handwriting_queue_page_test` |
| ④ 解题链 → 步骤 → 能力动作 → 卡点评估 | `question_reasoning_service.dart`、`capability_action.dart`、`stuck_point_evaluator.dart`、详情页展示与评估 | `question_reasoning_service_test`、`capability_action_test`、`stuck_point_evaluator_test`、`question_detail_page_test` |
| ⑤ threadflow 两段式 | `time_window_engine.dart`（算法定时段/截止匹配）、`domain_balance.dart`（领域配额）、`thread_balance_inputs.dart`（MindNet 有效性）→ `thread_rank_service.dart` | `time_window_engine_test`、`domain_balance_test`、`thread_balance_inputs_test`、`thread_balance_provider_test` |

**仍未做（诚实清单）**：

1. **②的"拖拽"（A 方案，可选）**：OS 级文件拖入 Flutter 没有 SDK API；要做得加 `desktop_drop` /
   `super_drag_and_drop` 一类依赖（还要平台注册）。**按本目标"B 优先"的口径，② 已经完成**：
   收题页有"粘贴文本 + `file_picker` 选图"两条路（见 §10 验收表、`question_intake_page.dart`）。
   拖拽是锦上添花的 A 方案，引依赖前需要用户拍板。
2. **④的能力动作词表用户可编辑**：按本文档 §4 的约定留到 schema v13 之后（本期不改表）。
3. **组卷/相似题的措辞与配额打磨**：功能在，但"为什么排这里/缺什么"的文案还能更具体。
4. **拍照整理的主入口**：现在在收题页的待整理清单 + 设置页各有一个入口；是否提升为顶层导航待定
   （设置页现有入口是刻意的设计选择，见 `settings_page.dart` 的注释）。
