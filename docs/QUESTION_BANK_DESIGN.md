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

**入口（轮次一百一十五起）**：底部导航「题库」（`question_bank_page.dart`）—— 收题是那里的
第一个按钮，同页还有组卷 / 拍照整理 / 材料入库；设置页只保留一个通往「题库」的条目。
题库本身是 `paperCorpusProvider` + `readQuestionStems` 的只读总览（按学科筛、点行进题目详情）。

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
3. 产出**四类待确认产物**：① 补充标签（挂到既有标签树）② 闪存卡（进复习队列前先确认）
   ③ MindNet 知识点节点（`knowledge_points` + 与标签的边）④ **题目**（轮次一百二十八新增：题面只誊写照片里
   真实内容、不改写题意、不补全缺失选项、不做题；确认后经 `QuestionRepository.ingest` 入库，
   `sourceLabel='拍照整理'`、`origin='ai_scan'`、`state='structured'`，指纹去重）。
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
| ③ 拍照手写整理 → 四类待确认产物（标签 / 知识点 / 闪存卡 / 题目） | `handwriting_proposals.dart`（标签/闪存卡/知识点三类提案 + 严格解析）、`handwriting_proposal_service.dart`、`handwriting_queue_page.dart`、schema v13 落盘 | `handwriting_proposals_test`、`handwriting_proposal_repository_test`、`handwriting_proposal_service_test`、`handwriting_intake_store_test`、`handwriting_queue_page_test` |
| ④ 解题链 → 步骤 → 能力动作 → 卡点评估 | `question_reasoning_service.dart`、`capability_action.dart`、`stuck_point_evaluator.dart`、详情页展示与评估 | `question_reasoning_service_test`、`capability_action_test`、`stuck_point_evaluator_test`、`question_detail_page_test` |
| ⑤ threadflow 两段式 | `time_window_engine.dart`（算法定时段/截止匹配）、`domain_balance.dart`（领域配额）、`thread_balance_inputs.dart`（MindNet 有效性）→ `thread_rank_service.dart` | `time_window_engine_test`、`domain_balance_test`、`thread_balance_inputs_test`、`thread_balance_provider_test` |

**仍未做（诚实清单）**：

1. ~~**②的"拖拽"（A 方案，可选）**~~ —— **已做（轮次一百二十一，用户明确要求「拖动添加照片的功能
   一定要支持微信的聊天记录」）**：引入 `desktop_drop: 0.8.4`（sdk ^3.5.0，兼容本机 Dart 3.13.2 /
   Flutter 3.47.2；0.9.1 要求 sdk ^3.13.5 装不上），收题页整页是投放区（`DropTarget` 包
   `Stack[ListView, 高亮层]`），一次可拖多张；Windows 通道只给路径，所以按扩展名白名单 + 前 12
   字节魔数双保险识别，同批去重（Windows/macOS 忽略大小写），非图片逐张跳过不整批失败，
   中文/空格/微信临时目录路径按原样处理。真机 OS 拖拽（尤其微信聊天记录）**未手测**（未验证）。
   详见 `docs/HANDWRITING_INTAKE_DESIGN.md` §4 与 `question_intake_page.dart`。
2. **④的能力动作词表用户可编辑**：**纯逻辑层已做（轮次一百二十一，reasoning-core）**——
   `capability_action_overlay.dart` 提供内置 + 自定义合并词表（key 规范、内置优先拒绝覆盖、
   issue 收集、`fromJson` 坏数据永不抛、空 overlay 零行为变化）、`parseChain` 支持注入
   lookup 映射自定义动作。**持久化与接线已做**：轮次一百二十三 schema v25 加了
   `local_settings.capability_action_overlay_json`（NULL = 出厂词表）并接进 `QuestionReasoningService`
   （提示词与 `parseChain` lookup 同源）；轮次一百二十五再加了编辑操作层与保存/放弃状态机
   （`capability_vocabulary_editor_provider.dart`）。**用户编辑 UI 已做**（轮次一百二十五 task-29，
   question-intake）：设置页「能力动作词表」入口 → `capability_vocabulary_page.dart`（内置只读分组、
   自定义条目增删改/上下移、粘贴 JSON 导入、issues 卡片、保存/放弃与退出确认，l10n 34 key）；
   见 `docs/REASONING_LAYER_DESIGN.md` §4/§4.1/§17/§19。
3. **组卷/相似题的措辞与配额打磨**：**领域层已完成（轮次一百二十七，threadflow-engine task-61）**——
  相似题 `rank(detailedReasons: true)` 在有共用知识点 / 同型动作 / 已知来源档位时追加「可核实依据：…」；
  组卷 `compose(detailedNotes: true)` 写「本卷第 N 题。」+ 排序依据 + 下一步，并新增 `PaperGapNote` 缺口解释
  （题库里没有 → 先收题；有候选但被题数/配额挤掉 → 调大上限）。**两个开关默认关闭**，默认 JSON / 分数 /
  理由逐字节不变（测试钉住）。**界面接线已做（轮次一百二十九，Lead task-78）**：`paperPlanProvider` →
  `buildPaperPlan(detailedNotes: true)`、`similarQuestionsProvider` → `rank(detailedReasons: true)`；
  AI 工具（`compose_paper` 等）**有意保持短文案**。详细文案仍是中文硬编码未接 l10n；
  `PaperGapNote` 仍只在领域层与测试里，没有单独界面块。见 `docs/REASONING_LAYER_DESIGN.md` §31/§32。
4. ~~**拍照整理的主入口**~~ —— **已解决（轮次一百一十五，用户反馈 m29290）**：收题 / 组卷 /
   拍照整理 / 材料入库四个入口从设置页收进新的顶层目的地「题库」（`QuestionBankPage`），
   设置页只留一个「题库」门；知识库仍是一级目的地，是否降级见 `FEATURE_MATRIX.md` D4/R5。

## 11. 题目编号与题目图片（轮次一百二十一，schema v24）

用户的原始要求（本轮 m00340 重申，属 HANDOFF §3 待办）：

> 我建议给每个题目一个独有的编号，就像 SCP 对异常有编号一样……这个编号要不要跨学科我不知道，
> 我建议搞成一个整体的吧。
>
> 题库的一个重要因素就是图片。题目肯定需要大量图片，每个科目都是，所以要支持图片格式。

### 11.1 题目编号：跨学科整体序列

- 口径：**一个题库一条序列**，不按学科分段。显示 `TR-00001`（`kQuestionSerialPrefix = 'TR'`、
  `kQuestionSerialMinDigits = 5`，超过 5 位不截断）；库里存整数 `questions.serial_no`。
- 发放：`QuestionRepository.ingest` 事务内 `MAX(serial_no) + 1`（`nextQuestionSerial`），
  调用方不能指定。指纹去重命中老题时**沿用老题号**，不消耗新号。
- 老库：v23 → v24 迁移 + `_ensureColumns` 自愈都调 `backfillQuestionSerialNumbers()`，
  按 `(created_at, id)` 升序补 1..N。
- 包：`.tfpkg` 导入后回填，老包里的题也拿到号；v24 包自带号。
- **未做（诚实清单）**：① 编号不加 UNIQUE（`append` 导入会撞号，宁重复不丢题），跨库合并后
  可能看到两个同一编号——要真唯一得引入来源前缀/命名空间；② "发出即永久保留"未做到：
  分配规则是"现存最大 + 1"，删掉最大号那题后号会被下一题接手，持久计数器留待后续。
- UI（轮次一百二十一，question-intake 交付）：新增 `question_media_view.dart` 的
  `QuestionSerialBadge` / `questionSerialProvider` / `questionSerialText`，题号在收题清单、题目详情、
  题库列表三处展示；徽章可点击复制（`Clipboard.setData` + SnackBar）。题库行用的是
  `PaperCandidate`（没有 serialNo），所以按 id 异步读 `questions.serial_no`，读回来前不占位。
  另有纯函数 `questionSerialLabel` / `tryParseQuestionSerial`（`TR-00042`、`tr-42`、`00042`、`42`
  都能认，不是编号返回 null），留给搜索框按号找题。
- 按号检索 API（轮次一百二十三，schema v25）：`QuestionRepository.findBySerialNo(int)`（号 < 1
  返回 null；撞号时 `limit(1)`）与 `search(serialNos: Set<int>)`（空集 = 没有命中，null = 不过滤；
  与题干/标签过滤相与）；界面侧用 `tryParseQuestionSerial` 解析输入，不要自己写正则。
- 题号进界面（task-13，question-intake 交付）：新增 `QuestionSerialBadgeById(questionId)`
  （`question_media_view.dart`，异步读号，加载/失败时 `SizedBox.shrink` 不占位），已接相似题候选行
  （`question_detail_page.dart`）与组卷页题目首行（`question_paper_page.dart`）；组卷页纯文本
  `renderPaperText` 未动。题库搜索框按号过滤**已接线**（轮次一百二十三 task-16，commit `4da1c5b`：
  输入 trim 后先 `tryParseQuestionSerial`，认得出号就优先 `search(serialNos:)`、0 命中回落题干 LIKE；
  读不出号只按题干 LIKE；纯空白不筛）。
- 题号进复制文本与搜索解析（轮次一百二十七，question-intake，task-58）：
  - `renderPaperText` 新增可选 `Map<String, int?> serialNumbers`（`question_paper_page.dart:734`），
    每行标题在「序号.」后加 `formatQuestionSerial` 结果；不传 / 该题没号时**不摆占位**，旧输出逐字不变；
    `_copyPaper` 复制前逐题 `await ref.read(questionSerialProvider(id).future)` 取号，单题失败置 null 继续。
  - 题库搜索框解析换新解析器（`question_intake_providers.dart:121` `parseQuestionLibrarySearch`：
    先 `parseQuestionNumberQuery`，读不出回退旧 `tryParseQuestionSerial`，题干原文始终保留）：
    新解析器多认大小写 `TR`、可选半角/全角连字符、`#`/`＃`、全角数字；更严处 = 拒绝 0、数字位 > 9 位，
    旧输入（`00042`、10 位前导零）由回退层继续按号检索。
- **未做**：闪存卡里未显示题号（cards 与 questions 无外键，需另开 schema 片）。

### 11.2 题目图片

- 存储：复用 `attachments` 表（`owner_type = 'question'`、`owner_id = questionId`），新增
  `attachments.sort_order`（默认 0）排同题多图；文件在
  `<application support>/question_images/<questionId>/<attId>/<原文件名>`，库里存相对 POSIX 路径。
- API：`QuestionMediaStore.save / list / readBytes / delete / deleteForQuestion`，
  provider 在 `question_media_providers.dart`。
- 与收题页拍照 store 分开（owner 不同），细节见 `docs/DATA_MODEL.md` §13。
- UI（轮次一百二十一，question-intake 交付）：详情页配图区 `QuestionImagesSection`、
  列表 48×48 首图缩略图 `QuestionCoverThumbnail`、点开 `Dialog + InteractiveViewer`（0.5–5 倍）
  的 `showQuestionImageViewer`；空清单 / 读不出都不占版面（失败只给一行文案）。
- **增删入口（轮次一百二十九，question-intake task-75）**：`QuestionImagesSection` 加
  `editable`（默认 false，列表等只读调用不变），题目详情页传 `editable: true`：
  - 添加：`FilePicker` 多选 png/jpg/jpeg/webp/gif/bmp → 逐文件校验（HEIC 提示转 JPG/PNG、
    非图片 / 0 字节 / 读失败分别计数跳过，**单文件失败不整批失败**）→ `QuestionMediaStore.save`
    → 手动 `ref.invalidate(questionImagesProvider(questionId))`（该 provider 不 watch 数据库
    revision）→ SnackBar 汇总「已添加 N 张 · 跳过 K 个」；
  - 删除：缩略图右上 `delete_outline`（不用 X，避免与大图关闭按钮撞图标）→ 确认对话框 →
    `store.delete` → invalidate → SnackBar；
  - 空清单只读仍零占位，编辑模式才留一行入口；l10n 12 个 `questionImage*` key。
  - 测试：`question_image_edit_test.dart` 6 例（替身 FilePicker / store，不碰真实磁盘）；
    详情页 22 例回归。真机 FilePicker 与真实磁盘增删**未手测**。
- 删题清配图（轮次一百二十三，question-intake 交付）：唯一界面删题入口
  `question_intake_page.dart` 的 `_confirmDelete` 先 `QuestionMediaStore.deleteForQuestion(id)`
  再 `QuestionRepository.deleteQuestion(id)`；清图失败只 `debugPrint` 不阻断删题，SnackBar 带
  清理张数（l10n `questionIntakeDeletedWithImages`）。仓储层本身仍不碰文件系统（职责不变），
  grep 全库 `deleteQuestion` 只有这一处界面调用，无遗漏入口。
- **未做**：图片压缩/缩略图生成未做（48×48 是解码整图后缩放）；真机系统文件选择器
  （Windows 对话框 / Android 选择器）与真实磁盘增删**未手测**（widget test 全用替身）；
  OCR 不读题目配图（拍照整理仍是独立入口）。

### 11.3 与 §10 未做清单的关系

§10 第 1 条的"拖拽收题"由 question-intake 的 task-5 落地（`desktop_drop 0.8.4`，支持微信
拖拽出来的临时文件）后销账；本节 11.1 / 11.2 是新增的两片，验收门禁同 §10：`dart analyze`
0 error / 0 warning、相关单测 + 全量测试绿、docs 同步、Lead 统一提交。

## 12. 导入导出：题目卷 → Word（.docx）（轮次一百二十二）

用户指令（m00726）：「docx 文档的构建和组卷网的链接可以借鉴 dsh skill」；此前 m00340 的
「导入导出要能简单生成 Word/docx」是本片目标。设计细节见 `docs/DOCX_EXPORT_DESIGN.md`，这里只记口径：

- 纯 Dart、离线、不调模型：`domain/services/export/docx_writer.dart`（OOXML 构造 + `archive` 打包）、
  `paper_docx.dart`（`PaperPlan` + 题目素材 → 卷面）、`features/questions/application/paper_docx_export.dart`
  （读库 + 读配图字节 + 文件名/页脚）。借鉴 `paper-composer` 的页面几何（A4、左 1.2cm/右 4.0cm 批注栏/
  上下 1.8cm）、字号字体、页码域页脚、图片等比缩放、OMML 原生公式、**真测分页**六条。
- 卷面 = 标题 + 每题「`n.  TR-00001` + 学科/来源/zone/知识点 + 题干 + 选项 + 配图」+ 卷末「参考答案与解析」
  （第一个附录标题才另起一页）+ 缺口两节 + 「导出提示」（缺题/空题干/缺答案/缺解析/跳图/公式失败）。
- 公式：行内 `$...$` 用注入的 `compileLatexToOmml` 转 Word 原生公式；编译失败保留 LaTeX 原文并计数。
- 图片：只 `wp:inline`（随文不浮动），栏宽 62%/页高 22% 双上限、最多放大 1.5 倍；WEBP/HEIC 不支持就报跳过。
- 验收：新测试 +158（含 omml 层、docx_writer、paper_docx、image_size、应用层装配）；探针样张 3 题/35 段/
  2 图/29 公式/0 失败；Word 16.0 真开 → 2 页、546 字、29 个 OMath、PDF 205,630 字节（附录分页修复前 4 页）。
- UI（task-10，question-intake 交付）：组卷页复制按钮旁新增「导出 Word」按钮
  （`paper_docx_export_button.dart`，key `paper-export-docx`），`FilePicker.saveFile` 另存为，
  成功/空卷/失败 SnackBar，有告警时弹「导出提示」明细（缺题/跳图/公式失败等，每类最多列 3 条）；
  空卷面也能导出（只有标题与缺口），复制按钮同时禁用。真机另存为对话框**未手测**（未验证）。
  英文界面下 docx 内部标签仍是域层默认中文——刻意不扩 25+ l10n key，记为已知限制。
- 未做：PDF 直出、表格/浮动图/页眉/多栏、WPS/LibreOffice 兼容未验证、docx 内部标签国际化。

## 13. 组卷网链接（找同类题的入口，轮次一百二十二）

设计规则、编码证据与已知局限见 `docs/ZUJUAN_LINKS_DESIGN.md`。口径：

- 纯逻辑：`domain/services/zujuan/zujuan_link.dart`（URL）与 `zujuan_keywords.dart`（检索词候选），
  移植 `zujuan-source-standards` skill 的 `bridge.mjs` / `keywords.mjs` / `extract.mjs` / `paper.mjs`。
- 文本搜题：`https://zujuan.xkw.com/quessearch?keyword=<base64>&intent=question&b=0&urlSource=0`；
  keyword 必须先 UTF-8 base64（标准、非 URL-safe）再百分号编码；`intent` 必须 `question`。
- 详情页 `/<bankId>q<id>.html`、试卷页 `/<bankId>p<id>.html`；缺 id 或非纯数字返回 `null`，不猜。
- 检索词：剔除公式/图片/〔标记〕、保留拉丁字母数字、标点分隔、长度 4–28、按内容词密度排序，默认 ≤8 条；
  领域词表只有生物学科（原样移植的已知局限）。
- 学科提醒：站点按 bankId cookie 过滤，学科不对会静默 0 条——UI 文案必须提示用户先切学科。
- 验收：`flutter test test/domain/services/zujuan` → +25 通过（编码与 skill CLI 逐条一致、候选规则、确定性）。
- UI（task-11，question-intake 交付）：题目详情页题面/配图下方「去组卷网搜这道题」入口
  （`question_zujuan_search.dart`，key `question-zujuan-search`），候选空则零高度；底部表只显示前 5 条，
  每条「复制检索词 / 打开搜索页」，表头常驻「先切学科」提示；打开搜索页 = 复制 URL（不新增 url_launcher）。
  验收：`flutter test test/features/questions/presentation` → +133 通过（详情页 22 例含剪贴板断言）。
  真机剪贴板与浏览器粘贴**未手测**（未验证）。
- 未做：题库无 bankId/questionId/sourceUrl 字段，详情/试卷链接暂用不上；候选质量受"领域词表只有生物"限制；
  没有"我是否已在组卷网找到这道题"的记录。

## 14. 读题工具与组卷手工指定/排除（轮次一百二十五）

### 14.1 AI 工具 `read_question`（只读）

用户口径（m00340）：AI **不出题**，只解题 / 拆题 / 找相似题。此前对话里只能靠
`find_similar_questions` 拿题干摘要，模型讲不清一道具体题的选项与解析；本轮补上「先读题」：

- 文件：`app/lib/features/ai/tools/question_tools.dart` 的 `ReadQuestionTool`，注册在
  `tool_registry.dart`（`ReadQuestionTool(db: db)`）；题号解析直接复用
  `domain/services/questions/question_number.dart` 的 `tryParseQuestionSerial`，与题库页同一口径。
- 定位：`question_id` 或 `serial`（`TR-00042` / `tr-42` / `00042` / `42` 都认），两个都给时以 id 为准；
  缺参、读不出题号、查无此号/此 id 都返回可读的失败结果，不猜、不生成题干。
- 返回：完整题干、选项（按 `sort_order` 升序）、答案、解析、学科/来源档位/来源文字/年份/地区/难度/
  题型/加工状态/AI 分、知识点 id + 标题（与组卷页同一「题目与知识点共享同一标签」口径）、
  最新一条链的能力动作 key + 中文名、配图数（`attachments` 里 `owner_type='question'` 的行数）。
- 只读：`readOnly = true`，`riskFor` 与 `reversibleFor` 用与 `find_similar_questions` 相同的中性组合，
  `ApprovalEngine` 在任何权限模式下都不逐条询问；有测试逐表比对调用前后快照不变。
- 验收：`flutter test test/features/ai/read_question_tool_test.dart` → 15 例全绿（定位 8、内容 6、只读 1）；
  `dart analyze lib/features/ai test/features/ai` → 0 error / 0 warning。
- 未做：工具面返回的是**整段**题干/解析（只读工具默认摘要原则的例外，因为解题必须看全文），
  超长题干没有分页；未做「按题号列出整卷」的批量读题工具。

### 14.2 组卷页手工指定 / 排除（question-intake 交付）

`compose_paper` 与组卷 provider 早就有 `manualIncludeQuestionIds` / `manualExcludeQuestionIds`（轮次一百二十五
上游切片，task-32/34 的语义：排除 > 必收 > 保底 > 填充），本轮补 UI：

- 新增 `app/lib/features/questions/presentation/paper_manual_selection_view.dart`：组卷页题目列表上方的
  「必收 / 排除」入口与名单区、选择题对话框（内存候选过滤，不走仓储查询）、三类结果卡；
  纯函数（排序、题干摘要、同批过滤、名单分组、可见性）与 widget 同文件，便于单测。
- `question_paper_page.dart` 在领域配额区之后挂入口与名单区，空卷与非空卷两个分支都渲染结果卡：
  收下几道 + `missing` / `skipped` / `conflict` 三类名单各前 3 条，其余只报数量（不静默丢）。
- l10n 五文件手改 18 个 key（`paperManualSelection*`，zh/en arb + 三个生成 dart）；未跑 gen-l10n。
- 验收：`flutter test test/features/questions/presentation/question_paper_manual_selection_test.dart` → 15 例全绿；
  该目录回归 +202 通过；`dart analyze lib/features/questions/presentation lib/l10n test/features/questions/presentation`
  → No issues found。
- 未做 / 未验证：真机弹窗与小屏滚动未手测；英文文案未母语校对；对话框搜索只过滤内存候选；
  题目详情页没有「一键设为必收/排除」入口（本轮只要求组卷页）。

## 15. 定点找题、拍照整理出题目、确认前预检与标签树排序（轮次一百二十八，2026-10-20）

用户这一轮的口径（m05023 / m05115 / m05424）：「定点组卷网找题」要真能用；拍照整理不能只产出
标签/知识点/闪存卡，**要能直接存成题目**；待确认内容要说清楚「确认后会发生什么」；标签树同层
要能按字典序 / 按内容量 / 按添加时间排。git 仍由 Lead 统一提交，成员只写各自作用域。

### 15.1 定点组卷网找题（链接 + 粘贴入库）

组卷网对非浏览器请求返回阿里云 WAF JS 挑战（纯 Dart HTTP 拿不到真页面），所以 App 不抓页面，
改成两条腿：**把条件拼成可打开的链接** + **把用户粘回来的题面解析入库**。

- 筛选链接：`domain/services/zujuan/zujuan_query.dart`（学科 / 知识点 id / 难度 / 年份 / 省份 /
  年级 / 排序 → 组卷网查询串）与 `zujuan_link.dart`（搜索页 URL、题目详情 URL、试卷详情 URL，
  base64 关键词编码与 skill 口径一致）。UI 是 `features/questions/presentation/zujuan_pick_panel.dart`
  （底部表实时显示 URL、复制链接写剪贴板，学科默认 math，非法值不拼坏链接）。
- 粘贴导入：`domain/services/zujuan/zujuan_paste.dart` 的 `parseZujuanPaste(raw)` 支持**整卷多题**
  （按题号切块，去〔加点〕〔波浪线〕〔着重号〕标记，答案/解析/知识点/来源/详情页 id 都认；
  永不抛异常，识别不出按单题兜底并标 `isPartial`）；应用层 `features/questions/application/zujuan_paste_import.dart`
  转 `QuestionDraft`（origin 'zujuan'、state 'raw'、补详情页 sourceUrl）；UI `zujuan_paste_dialog.dart`
  解析 → 勾选 → 改题干 → 批量入库 → 汇总 saved/duplicates/failed。
- **来源字段（schema v26）**：`questions` 加 `sourceUrl` / `zujuanQuestionId` / `zujuanBankId`，
  题库详情页可回看题源；v26 迁移测试 3 例。
- 答案口径（用户 m05424）：**用户可以自己登录组卷网看答案与解析**（整张 JPEG、免费账号每天约 30 道）。
  App 不代持登录态、不代登、不批量下载；界面文案不写「拿不到答案」，写「要你自己登录看一眼，
  把看到的文字粘回来」。粘贴框旁有同样的登录提示。
- 入口：收题页表单标题下两个等宽按钮「定点找题」「粘贴组卷网题面」。
- 未做 / 未验证：真机复制出的链接是否在当前网络可达、真实粘贴文本样本未人工核对（只用样例字符串
  模拟）；未做按题号/知识点批量抓取（WAF 阻塞），未接官方开放平台。

### 15.2 拍照整理第四类产物「题目」

- 领域层：`HandwritingProposalKind` 加 `question('question','题目')`；`HandwritingProposal.options`
  （`HandwritingOptionDraft`：label 单字母 A–Z trim+大写、content 非空、标签不重复且从 A 连续）；
  题目标必填 `fields.stem`，缺了直接解析失败；提示词加「只誊写、不改写、不补全、不做题」铁律。
- 应用层：`HandwritingProposalService.questionDraftForIntake(proposal)`（只装配 `QuestionDraft` 不写库，
  供「带到收题页编辑」）与 `_applyQuestion`（确认后 ingest；重复题干返回既有题号且不重复入库；
  tag_path 不存在题照建只提示；`markAppliedLocally` 供手动入库后只标已确认）。
- 未做（在途 task-70）：队列卡片还没有「编辑题目字段 + 带到收题页」的入口。

### 15.3 确认前预检（用户说的「确认逻辑有待提升」）

- 纯逻辑：`domain/services/intake/handwriting_proposal_preview.dart`——每条提案输出
  `verdict`（ready 可以确认 / needsReview 确认前看一眼 / blocked 不能确认）、`targetPath`、
  `willCreate` / `willReuse`、`previewLines`（2–5 行中文）、`warnings`、`blockers`、
  同批重复的 `duplicateOfProposalId`；整批给 ready/needsReview/blocked 计数、`hasBlocked`、`canApplyAll`。
  规则例：标签父层不存在 → blocked；完整路径已存在 → 复用；知识点标题已在 → 复用；题目缺答案/解析 →
  警告；题干空 → blocked。
- 应用层：`HandwritingProposalService.previewFor(set)` 读库里现有标签路径与知识点标题后判定（只读），
  `HandwritingQueueNotifier.previewFor(relPath)` 供页面调用。42 例域层单测 + 4 例应用层单测。
- 未做（在途 task-74）：卡片还没把 previewLines / warnings / blockers 渲染到确认按钮前，
  blocked 条也还没禁勾选。

### 15.4 标签树同层三种排序

- 纯逻辑：`domain/services/tags/tag_tree_sort.dart`（三口径 `TagTreeSortMode` + `sortTagTreeSiblings`，
  全序、不改入参）与 `tag_tree_view.dart`（孤儿、环、path、子树计数 `countDescendants`、
  偏好编解码 `tagTreeSortModeFromStorage/ToStorage`）。
- 计数数据源：`TagRepository.objectCountByTagId({includeDescendants=false, Set<String>? objectTypes})`
  ——默认只算直接挂在标签上的对象，子树累计要显式打开。
- 未做（在途 task-73）：页面仍是写死 `name.compareTo`，排序选择器与内容量角标未接。
  完整口径见 `docs/TAG_TREE_SORT_DESIGN.md`。



