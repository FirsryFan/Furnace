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
- **缩略图解码尺寸（轮次一百三十，task-79 纯逻辑）**：`domain/services/media/thumbnail_spec.dart` 的
  `thumbnailDecodeSpec(logicalWidth:, logicalHeight:, devicePixelRatio:)` 把显示尺寸 × DPR 换成
  `cacheWidth/cacheHeight`（长边默认封顶 1024、非法尺寸返回空 spec 让调用方不传 cache、DPR 非法归一、
  防 int 溢出上限 16）；让 Flutter 在**解码阶段**就缩图，而不是解码整张 4000×3000 再显示。
  已接 UI（task-82）：`question_media_view.dart:251` 用显示边长算 spec、`:287-288` 传 `cacheWidth/cacheHeight`
  （空 spec 传 null，大图查看器不限制解码）；详情页 96、列表/收题清单 48 两个尺寸。纯逻辑 +27 例、UI +2 例。
- **未做**：不做图片重编码/不生成磁盘缩略图（磁盘上仍是原图，只在解码时缩）；真机系统文件选择器
  （Windows 对话框 / Android 选择器）与真实磁盘增删**未手测**（widget test 全用替身）；
  OCR 不读题目配图（拍照整理仍是独立入口）。
- **答案与解析截图（轮次一百三十四，schema v27）**：`attachments.role` 区分用途（NULL/空 = 旧行按
  题干配图读，stem = 题干配图，answer = 答案/解析截图，solution 预留），`QuestionMediaStore` 的
  `save(role:) / list(role:)` 按角色分开排号与读取；题目详情页题干配图区之后新增「答案与解析截图」区
  （复用 `QuestionImagesSection`，`kind: answer`，没有图只留一行入口）；导出的 Word 把答案截图放进
  **卷末附录**（解析之后），AI 读题工具的 `image_count` 只数题干配图、新增 `answer_image_count`。
  详细口径见 §19、`docs/DATA_MODEL.md` §16、`docs/DOCX_EXPORT_DESIGN.md` §15。

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
- 已做（task-65，v26）：`questions` 加 `sourceUrl` / `zujuanQuestionId` / `zujuanBankId`，粘贴入库时写详情页链接。
- 写入/纠错数据层（轮次一百三十二，task-87）：`QuestionRepository.updateSourceLinks(id, {sourceUrl,
  zujuanQuestionId, zujuanBankId})` 返回是否真改到行；约定 `null` = 这一列不动、空串/全空白 = 清空该列
  （写回 null），外层空白归一；不碰来源分级 / 题干 / 答案 / 加工列，不存在的 id 返回 false。8 例测试。
  界面上的「改原题链接」入口待接（下一片）。
- 题源链接纯逻辑（task-80，轮次一百三十）：`domain/services/questions/question_source.dart` 的
  `questionSourceFor({sourceUrl, zujuanQuestionId, zujuanBankId})` 返回 `QuestionSourceRef{url, host,
  fromStoredUrl, isZujuan}`；只认绝对 http(s)（javascript:/data:/file:/相对路径一律 null）、scheme/host 小写、
  去 fragment 与默认端口、path/query 逐字节保留；库里有链接优先，没有则用两个 id 走
  `zujuanQuestionDetailUrl` 重建（`fromStoredUrl=false`），都拿不到返回 null。验收 +46 例。
  已接 UI（task-82）：详情页来源行 `_QuestionSourceLine`（`question_detail_page.dart:768`）显示「组卷网原题」
  或其它 host + 「复制原题链接」按钮，只复制规范化后的 `source.url`（不加 url_launcher）；无链接整块零高度。
  验收详情页 +4 例（无链接不出现 / 普通站 host / 仅有 id 时重建 / 组卷网不显示 host）。
- 未做：候选质量受
  "领域词表只有生物"限制；没有"我是否已在组卷网找到这道题"的记录。

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
  超长题干没有分页；批量读题已由 §14.2 的 `read_questions_by_serials` 补上（只回摘要，不进全文）。
- 整卷题号批量解析（task-81，轮次一百三十，纯逻辑）：`domain/services/questions/question_serial_batch.dart`
  的 `parseQuestionSerialBatch(raw, {maxCount = 200})` 支持半/全角逗号、顿号、半/全角分号、Unicode 空白
  分隔，区间 `1..5` / `3-7` / `1~5` / `1—5`（升降序统一升序、重叠相邻合并、去重升序、超限截断并置
  `truncated`、超大区间有 `kQuestionSerialBatchHardLimit` 防撑爆内存），认不出的段进 `rejectedSegments`
  （区间一端非法整段拒绝，不猜一半），永不抛异常；+51 例。批量读题工具下一步接它。

### 14.2 AI 工具 `read_questions_by_serials`（只读，轮次一百三十一）

用户贴出"整卷题号"（"1..20 里我录了几道""5 到 9 号都找出来"）时的工具面。一个号一个号调
`read_question` 既慢又会把整段题干塞满上下文，所以这个工具只回**摘要**：

- 文件：`app/lib/features/ai/tools/question_tools.dart` 的 `ReadQuestionsBySerialsTool`，注册在
  `tool_registry.dart`（紧跟 `ReadQuestionTool`）；清单解析完全复用 §16.3 的
  `parseQuestionSerialBatch`（工具自己不做字符串处理）。
- 参数：`serials`（必填，如 `1..20`、`TR-00001, 3, 5-8`）、`max_count`（默认 50，上限 200；
  <=0 回落默认；超上限钳到 200）。解析器负责区间/分隔符/去重升序/截断（`truncated`）。
- 返回：`requested_count/found_count/missing_count/truncated/rejected_segments`、
  `questions[]`（`serial_no/serial_label/id/subject/subject_key/source_level_zh/source_label/
  year/region/stem_preview/has_answer/has_solution/option_count/image_count`）、`missing[]`（补零题号）。
- 口径：一个题号对应多条时按 `QuestionRepository.search` 的价值序取第一条（题号跨设备 append 导入
  可能撞号，§11.1）；库里没有的号进 `missing`，认不出的段原样进 `rejected_segments`，
  整段清单都没可用题号时返回可读失败——**不猜、不生成题干**（AI 不出题）。
- 只读：`readOnly=true`，`riskFor/reversibleFor` 与 `read_question` 同一中性组合，任何权限模式
  都不逐条询问；测试逐表比对调用前后快照不变。
- 验收：`flutter test test/features/ai/read_questions_by_serials_tool_test.dart` → 16 例全绿
  （只读 2、清单口径 4、摘要 6、边界 3、注册与 schema 1）；
  `dart analyze lib/features/ai/tools/question_tools.dart lib/features/ai/domain/tool_registry.dart test/features/ai/read_questions_by_serials_tool_test.dart` → No issues。
- 未做：不返回知识点/解题链动作（要这两样请对单题调 `read_question`）；没有分页（超 200 道截断）。

### 14.3 组卷页手工指定 / 排除（question-intake 交付）

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
- 已做（task-70，轮次一百二十八）：队列卡片上题目提案有「编辑后保存」入口——应用层
  `questionDraftForIntake(proposal)` 只装配 `QuestionDraft` 不写库，页面把草稿带到收题页校对后再入库
  （`handwriting_queue_page.dart:496` 起）；其它三类产物确认即入库，没有这个入口。

### 15.3 确认前预检（用户说的「确认逻辑有待提升」）

- 纯逻辑：`domain/services/intake/handwriting_proposal_preview.dart`——每条提案输出
  `verdict`（ready 可以确认 / needsReview 确认前看一眼 / blocked 不能确认）、`targetPath`、
  `willCreate` / `willReuse`、`previewLines`（2–5 行中文）、`warnings`、`blockers`、
  同批重复的 `duplicateOfProposalId`；整批给 ready/needsReview/blocked 计数、`hasBlocked`、`canApplyAll`。
  规则例：标签父层不存在 → blocked；完整路径已存在 → 复用；知识点标题已在 → 复用；题目缺答案/解析 →
  警告；题干空 → blocked。
- 应用层：`HandwritingProposalService.previewFor(set)` 读库里现有标签路径与知识点标题后判定（只读），
  `HandwritingQueueNotifier.previewFor(relPath)` 供页面调用。42 例域层单测 + 4 例应用层单测。
- 已做（task-74，轮次一百二十八）：卡片把 `previewLines` / `warnings` / `blockers` 渲染在确认按钮前，
  blocked 时整批「全部确认」按钮禁用（`handwriting_queue_page.dart:337/409/684` 起）；实测 42 例域层 +
  4 例应用层 + widget 测试。

### 15.4 标签树同层三种排序

- 纯逻辑：`domain/services/tags/tag_tree_sort.dart`（三口径 `TagTreeSortMode` + `sortTagTreeSiblings`，
  全序、不改入参）与 `tag_tree_view.dart`（孤儿、环、path、子树计数 `countDescendants`、
  偏好编解码 `tagTreeSortModeFromStorage/ToStorage`）。
- 计数数据源：`TagRepository.objectCountByTagId({includeDescendants=false, Set<String>? objectTypes})`
  ——默认只算直接挂在标签上的对象，子树累计要显式打开。
- 已做（task-73，轮次一百二十八）：页面顶部 `PopupMenuButton<TagTreeSortMode>` 选三种排序，偏好存在
  `tagTreeSortModeProvider`（会话内，`tagTreeSortModeToStorage/FromStorage` 可编码持久化但还没写盘）；
  每层用 `sortTagTreeSiblings`，内容量角标走 `objectCountByTagId`。完整口径见 `docs/TAG_TREE_SORT_DESIGN.md`。
- 未做：排序偏好没有持久化到磁盘（重启回到字典序）。

## 16. 题源链接、缩略图解码尺寸、整卷题号清单（轮次一百三十，2026-10-21）

goal round 7 的第一批：三块纯逻辑并行（Lead / threadflow-engine / reasoning-core），
为三处一直缺的界面入口铺路——「点回去核对原题」「列表缩略图别解码整张照片」「按题号列整卷」。

### 16.1 题源链接：`question_source.dart`（threadflow-engine，task-80）

- `QuestionSourceRef? questionSourceFor({String? sourceUrl, String? zujuanQuestionId, String? zujuanBankId})`；
  `QuestionSourceRef{url, host, fromStoredUrl, isZujuan, toJson, ==/hashCode, toString}`，157 行。
- 信任边界：只认绝对 http(s) URL；`javascript:` / `data:` / `file:` / `mailto:` / 协议相对 `//host/a` /
  相对路径 / 空 host 一律返回 null（库里可能是历史脏数据，不猜、不打开）。
- 规范化（只做能证明的变换）：scheme 与 host 小写、去 fragment、去默认端口（http:80/https:443）、
  非默认端口保留、path/query 逐字节保留（不 decode、不重排参数）、空 path 不补 `/`；
  不升级 scheme、不补 www、不补尾斜杠。组卷网判定 = `zujuan.xkw.com` 与 `*.zujuan.xkw.com`
  （`zujuan.xkw.com.evil.com`、`notzujuan.xkw.com` 有反例测试）。
- 重建分支完全复用 `zujuan_link.dart` 的 `zujuanQuestionDetailUrl`（不重复实现数字校验）：
  只有 id 时重建、`fromStoredUrl=false`；链接与 id 都有时链接优先。
- 验收：`flutter test test/domain/services/questions/question_source_test.dart` → +46 全绿；
  同目录全量 +244 无回归；`dart analyze lib/domain/services/questions test/domain/services/questions` → No issues。
- 已接 UI（task-82）：详情页来源行「组卷网原题 / 复制原题链接」。
- 已做（task-92，轮次一百三十三）：详情页「改原题链接」（无来源行时「添加原题链接」），
  保存走 `updateSourceLinks`，见 §18.4。未做：打开器/真实浏览器验证。

### 16.2 缩略图解码尺寸：`thumbnail_spec.dart`（Lead，task-79）

- `ThumbnailDecodeSpec thumbnailDecodeSpec({required int logicalWidth, required int logicalHeight,
  double devicePixelRatio = 1.0, int maxDecodeSide = 1024})`；返回
  `ThumbnailDecodeSpec{cacheWidth, cacheHeight, devicePixelRatio, capped, isEmpty, toJson}`。
- 口径：先乘 DPR 再 ceil（宁可多解一行，别拉糊）；长边 > `maxDecodeSide` 按比例压、两边至少 1、
  `capped=true`；`maxDecodeSide<=0` 不设上限；DPR 非有限/<=0 按 1.0、>16 钳到 16（防 int 溢出）；
  逻辑尺寸任一边 <=0 返回 0×0 空 spec（`isEmpty=true`）——Image 断言 cache 必须 >0，调用方必须判空后再传。
- 为什么：题库列表/收题清单的缩略图只有 48–96 逻辑像素，`Image.memory` 默认按原始像素解码，
  一张 4000×3000 照片解 48 MB，一屏十几张会卡、低端机会被系统杀（§11.2 记的「48×48 是解码整图后缩放」）。
- 纯逻辑：不 import Flutter、不读文件、不探测原图尺寸（解码器不会放大，多算无害）。
- 验收：`flutter test test/domain/services/media/thumbnail_spec_test.dart` → +27 全绿。

### 16.3 整卷题号清单：`question_serial_batch.dart`（reasoning-core，task-81）

- `QuestionSerialBatch parseQuestionSerialBatch(String raw, {int maxCount = 200})`；
  `QuestionSerialBatch{serials, rejectedSegments, truncated, isEmpty, count, toJson}`，330 行。
- 分隔符：半角逗号、全角逗号、顿号、半/全角分号先切块，块内再按 Unicode 空白切 token；
  单 token 复用 `parseQuestionNumberQuery`（TR-00042 / tr-42 / #42 / 00042 / 42 / 全角数字都认）。
- 区间连接符按 `..` → `~` → `—` → `-` 顺序尝试（`-` 最后，避免把 `TR-42` 自己的连字符当区间）；
  两端都是合法单号才展开，升降序统一升序，重叠与相邻区间合并；一端非法整段进 `rejectedSegments`（不猜一半）。
- 超 `maxCount` 只保留最小的若干个并置 `truncated=true`；`kQuestionSerialBatchHardLimit=100000` 防
  `1..999999999` 撑爆内存；`maxCount<=0` 返回空题号 + truncated；空输入/纯拒绝段 truncated=false；永不抛。
- 验收：`flutter test test/domain/services/questions/question_serial_batch_test.dart` → +51 全绿。

### 16.4 本轮门禁与在途

- `flutter test test/domain/services/media test/domain/services/questions --concurrency=1` → **+271 All tests passed**；
  `dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）。
- 已交付（task-82，question-intake，轮次一百三十一）：题目详情页「题目来源」入口（+4 例）、缩略图
  `cacheWidth/cacheHeight` 接线（+2 例）、3 个 l10n key；详情页目录全量 +291 通过。
- 未做（下一批）：缩略图磁盘缓存、题库列表（非收题页）的多号/区间搜索。此前记的「来源链接写入/纠错的 UI」
  已由 task-92 补齐（§18.4）；收题页多号搜索并集见 §17.4。
- 轮次一百三十一已补：批量读题 AI 工具 `read_questions_by_serials`（§14.2），task-82 接线已验收。
- 轮次一百三十一还补：docs 回填本节四处在途说明（§11.2 / §13 / §16.1 / §16.4）为已交付。

## 17. 题库搜索输入、题源链接写入、整卷页粘贴抽取（轮次一百三十二，2026-10-21）

本轮的共同目标还是"少让用户手敲"：搜索框一次贴多号/区间/关键词、题源链接能改、
组卷网试卷页整段粘进来就能拿到整套题号清单。三块都是纯逻辑/数据层；搜索框的 UI 接线已由 task-86
交付（见 §17.4），整卷页粘贴与题源链接写入的界面入口仍未做。

### 17.1 搜索输入解析：`question_search_plan.dart`（reasoning-core，task-84）

- `QuestionSearchPlan parseQuestionSearchPlan(String raw, {int maxSerialCount = 200})` 返回
  `QuestionSearchPlan{raw, stemContains, serialNos, rejectedSegments, truncated}` +
  `isEmpty / isSerialOnly / isStemOnly / serialCount / toJson`；484 行，`kQuestionSearchPlanSerialHardLimit=100000`。
- 单号复用 `parseQuestionNumberQuery`；分隔符半/全角逗号、顿号、半/全角分号与 Unicode 空白（含全角空格）；
  区间连接符 `..`→`~`→`—`→`-`（`-` 只当两端都是数字），支持 `1 - 5` 三段写法；重叠/相邻区间合并去重升序；
  超大区间按上限截断（truncated=true）不真展开。
- 认不出的文字按输入顺序用单空格拼进 `stemContains`（题库搜索=题号命中 ∪ 题干 LIKE 的关键词来源）；
  坏区间（`1..x`、`1..`、`1..5..9`）整段进 `rejectedSegments`，不混进题干；纯号时 `stemContains=null`；
  没有题号时回退「整段输入当题干」（保持旧搜索框行为）；永不抛。
- 相等性只比语义字段（不含 `raw`）；`raw` 永远是调用方原串。
- 验收：`question_search_plan_test.dart` +81 例；`test/domain/services/questions` 目录 +325 全绿。

### 17.2 题源链接写入数据层：`QuestionRepository.updateSourceLinks`（Lead，task-87）

- `Future<bool> updateSourceLinks(String id, {String? sourceUrl, String? zujuanQuestionId, String? zujuanBankId, DateTime? now})`：
  `null` = 这一列不动；空串/全空白 = 清空该列（写回 null）；外层空白归一；返回是否真改到行
  （不存在的 id 返回 false，不抛）；不碰来源分级/题干/答案/加工列。
- 为什么与 [updateSource] 分开：来源分级是封闭词表、写错会弄歪排序；链接是用户粘贴的外部字符串，
  只需归一空白、不参与排序。UI 上的「改原题链接」入口待接。
- 验收：`question_repository_source_links_test.dart` 8 例。

### 17.3 组卷网整卷页粘贴抽取：`zujuan_paper_extract.dart`（threadflow-engine，task-85）

- `ZujuanPaperExtract parseZujuanPaperText(String raw)` 返回
  `{paperId, bankId, title, questionIds, questionLinks, warnings, truncated}` + `isEmpty / questionCount / toJson`；
  262 行、`kZujuanMaxExtractedQuestions=200`、纯 Dart 只 import `zujuan_link.dart`。
- 只认站点 URL 形状：试卷 `/<bank>p<paper>.html`（只有 `p<paper>.html` 时 bankId=null），
  题目 `q<digits>.html`（可带 bank 前缀）；前导边界防 `/abcq123` 误认；顺序去重不重排；
  超过 200 个唯一 id → truncated +「超过 200 道，只取前 200 道」。
- `questionLinks` 一律调 `zujuanQuestionDetailUrl` 生成（缺 bank 跳过并汇总 warning）；
  `title` 只认 `<title>` → `<h1>` → null（不猜），解常见 HTML 实体并折叠空白；不联网、不解析答案、永不抛。
- 未做：粘贴入口 UI / 预览 / 批量入库、真实浏览器「保存页面」HTML 端到端验证、跨页试卷。
- 验收：`zujuan_paper_extract_test.dart` +44 例；`test/domain/services/zujuan` 目录 +212 全绿。

### 17.4 UI 接线、门禁与未做

- task-86（question-intake，已交付 rev5）：收题页题库区搜索改接 `parseQuestionSearchPlan`——
  `QuestionLibraryFilter.serialNo:int?` → `serialNos:List<int>` + 新增 `serialFallbackStem`；混合搜索 =
  题号查 + 题干查两次取并集（题号命中在前、按 id 去重、各自保仓储序）；纯号 0 命中保留旧「回落题干」
  行为；清空搜索时题号与回落一起清；hint 改为「搜题干或题号（可多个：TR-00001, 2-5）」（l10n 五文件手改）。
  测试：providers 15 例 + 页面 5 例，`test/features/questions/presentation` **+298** 全绿（基线 291）。
- 门禁：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量
  `flutter test --concurrency=1` → **+4374 ~2 All tests passed**，8 分 52 秒（EXIT=0；日志
  `E:/dsh-tmp-aot/test-132-full.txt`）；四目录组合 → **+1005** 全绿（日志 `E:/dsh-tmp-aot/test-132-slices.txt`）。
- 门禁事故：第一次全量跑在 `+3324 loading review_page_test.dart` 处 CPU 冻结 5 分钟，手动 kill；怀疑与
  teammate 并发跑测试争用，改为同一时刻只跑一个 `flutter test` 后重跑通过。
- 未做（部分已在轮次一百三十三补上，见 §18）：整卷页粘贴的界面入口（预览 / 批量入库，§18.3 已做对话框）；题源链接的
  「改原题链接」UI（§18.4，task-92）；搜索框多号结果顺序只由代码顺序保证（测试断言命中与去重）；真机输入法未手测。

## 18. 整卷页对照题库、题源链接解析与编辑（轮次一百三十三，2026-10-21）

这一轮把「手上有整页试卷、但不知道库里有没有」做成一条可用的链路：粘贴整卷页 → 对照 → 缺题清单 → 逐题补录；
顺带把「原题链接」从只读变成可改可清。四个切片（task-88/89/90/91，task-92 在途）。

### 18.1 整卷对照的数据与应用层（Lead，task-88）

- 数据层 `QuestionRepository.byZujuanQuestionIds(Set<String>)`：逐项 trim 去空，空集返回空 map；
  只查 `zujuan_question_id` 非空的题，按 `updatedAt` 降序 / `id` 升序，结果按 zujuan id 分组；
  同一 zujuan id 若有多行（历史重复入库）原样保留，由调用方取第一行（最新）。
- 应用层 `features/questions/application/zujuan_paper_progress.dart`：
  `loadZujuanPaperProgress({required QuestionRepository repository, required ZujuanPaperExtract extract})`
  返回 `ZujuanPaperProgress{extract, matched, missingQuestionIds, missingLinks}`——
  按试卷页题号顺序逐 id 取库中最新一行，命中进 `matched`（`serialLabel` 用全仓一致的
  `questionSerialLabel`，未编号显示「TR-未编号」；`stemPreview` 压空白取前 60 个 rune，多了加 …），
  缺题进 `missingQuestionIds`；`missingLinks` 逐 id 用 `zujuanQuestionDetailUrl` 重算（缺 bankId 跳过）。
  `extract` 为空时直接返回空 progress、**不查库**。为什么不放 UI 层：AI 工具要复用同一套匹配与预览口径。
- 测试 +20 例（仓储 8 / 应用层 12）：空集、trim 精确、不做前导零归一、同 id 多行降序、顺序跟试卷页、
  预览截断、未编号占位、无 bankId 无链接、warnings/truncated 透传。

### 18.2 AI 只读工具 `read_zujuan_paper`（threadflow-engine，task-90）

- 工具 26 → 27：参数 `text`（必填）+ `max_count`（默认 50、硬上限 200）；
  流程 `parseZujuanPaperText` → 空则 `ToolArgError`（说明要整卷页/题页形状）→ `loadZujuanPaperProgress`。
- 只读：结果带 `rule: 'library_only'`、计数、`truncated`、`warnings`、
  `matched`（4 键：zujuan_question_id / question_id / serial_no / stem_preview）、
  `missing`（zujuan_question_id + 可空 link）、条件 `missing_omitted`；摘要写明
  「我只读题库，不会去组卷网抓页面」，缺题题号最多列 3 个。
- 测试 +17 例；`read_questions_by_serials` 无回归（+16）。

### 18.3 收题页「整卷对照」对话框（question-intake，task-91）

- 收题页第三个入口（Key `zujuan-paper-open`）打开 `zujuan_paper_dialog.dart`：粘贴整卷页 URL / 整页文字 →
  解析 → 显示「共 N 道 · 已收录 M 道 · 缺 K 道」+ 已收录行（题号 + 题干预览）+ 缺题行（有链接显示链接、
  无链接显示「（无链接）」+ 原因说明）+ 一键复制缺题链接。空白或认不出显示空态文案且不查库；
  全部已收录或缺题无链接时复制按钮禁用。
- l10n 18 个 `zujuanPaper*` key（zh/en 五文件手改，未跑 gen-l10n）。
- 测试 +11（对话框）+ 1（入口）：纯函数链接判定、空态两次不查库（计数仓储断言）、全缺/部分命中、
  复制写剪贴板、无 bankId 提示与禁用、入口打开。presentation 目录 +310 全绿（基线 298）。

### 18.4 题源链接的输入解析与「改原题链接」（reasoning-core task-89 + question-intake task-92）

- 域层 `parseZujuanSourceInput(raw)` → `ZujuanSourceInput{sourceUrl?, zujuanQuestionId?, zujuanBankId?}`：
  接受完整 http(s) 组卷网题目页 URL（先 `questionSourceFor` 归一，**只有组卷网 host 才抽两个 id**）、
  裸路径 `/10q<id>.html`、别的站 URL（只存 sourceUrl）；纯数字 / 相对路径 / `javascript:` 等 → null；
  拒绝口径与已知边界见 `docs/ZUJUAN_LINKS_DESIGN.md` §10（+40 例，zujuan 目录 +252）。
- 详情页「原题链接」编辑（task-92，已完成）：来源行复制按钮旁「改原题链接」，无来源行时低权重「添加原题链接」（同一 Key）；
  对话框初值=现有 sourceUrl，输入实时预览三个字段，三行全空/认不出禁用保存；保存走 `updateSourceLinks`
  （null=该列不动，别站 URL 只写 sourceUrl、不冲掉已有 zujuan id），「清空链接」二次确认后三列清空；+10 + 3 例。提交 `86ab39d`。

### 18.5 未做（本轮之后）

- 整卷对照的「批量补录缺失题」：目前只有缺题清单与链接复制，逐题录入仍要走粘贴题面 / 定点找题。
- 真实组卷网整页文本/浏览器「保存页面」HTML 的端到端手测（各层有构造样本测试，未实测真页面）。
- 三按钮同排的窄屏（<400dp）溢出未验证，后续可换 `Wrap`。
- 同一题在题库里重复入库时，read_zujuan_paper 只取最新一行、不做合并提示。

## 19. 答案与解析截图随题保存（轮次一百三十四，schema v27）

用户口径（m05424）：「注意用户可以人工登录组卷网账号获取答案」——组卷网的答案/解析要登录才看得到，
而且是**一整张 JPEG**，App 不做自动下载、也不代持登录态。这一轮把「用户自己截下来的答案图」变成
题目的一部分：随题保存、详情页可增删、导出 Word 进附录、AI 读题时能分开数。

### 19.1 数据层：attachments.role（Lead，task-93）

- `attachments` 加一列可空 `role`（v27）：`NULL` / 空串 = 旧数据与别处附件，读作题干配图（**不回填**，
  避免把别的 owner 多态附件误标）；`stem` = 题干配图；`answer` = 答案/解析截图；`solution` = 预留
  （读侧先与 answer 同桶）。
- `QuestionMediaStore`：`QuestionImageRole` 常量 + `effectiveQuestionImageRole(String?)` 折叠空/空白→stem；
  `save(role:)` 按角色内排 `sort_order`（两类各自 0,1,2…）；`list(questionId, {String? role})` 不传=全部、
  stem 同时匹配 `role IS NULL OR role='stem'`（旧行不丢）、其它精确匹配；`deleteForQuestion` 两类一起清；
  返回的 `QuestionImage.role` 已折算（旧行读出 stem，不写回库）。
- 应用层 `loadQuestionDocxImages` 显式只读 `role: stem`，答案图不再混进题干位置。
- 迁移 `_upgradeV26ToV27`（attachments 存在才 addColumn）+ `_ensureColumns` 同款自愈（老文件被盖成 v27
  会 `no such column: role`）；`database.g.dart` 用 build_runner 重生成。
- 测试 +20：`v27_migration_test` 3 例（真实 v26 升级、被盖成 v27 缺列自愈、带角色关库重开）+
  `question_media_store_test` 角色组 7 例（折算、缺省/显式角色、list 过滤、各自排号、删全部、未知角色原样落库），
  以及既有用例的角色回归。提交 `7211858`。

### 19.2 详情页「答案与解析截图」区（question-intake，task-95）

- `QuestionImagesSection` 抽 `QuestionImagesSectionKind { stem, answer }`（默认 stem）：按 kind 切 provider
  （`questionImagesProvider` 只读 stem / 新增 `questionAnswerImagesProvider` 读 answer）、标题、空态、
  添加按钮、删除确认与 section key；写入 `save(role: …)`；新 4 个 key
  （`questionImagesSectionKey` / `questionAnswerImagesSectionKey` / 添加 / 删除确认）。
- 详情页位置：题干配图区之后、组卷网入口之前；没有答案图时**不摆空相框**，只留一行「添加答案截图」入口。
- HEIC/非图片/0 字节/读失败逐文件跳过规则与题干配图完全一致（复用既有计数与 SnackBar）。
- l10n 五文件手改 5 个 `questionAnswerImage*` key（未跑 gen-l10n）：标题「答案与解析截图」、添加、空态
  （「在组卷网登录后截下答案/解析整图存进来（HEIC 暂不支持）」）、删除确认、已删提示。
- 测试 +7（`question_image_edit_test` 新 group）：空态入口、落盘 role=answer 且题干区不动、两区各读各的、
  删除两区互不影响、HEIC 跳过、只读区无增删入口、provider 层分流；测试替身同步 role 语义。
  `flutter test test/features/questions --concurrency=1` → +600 全绿。

### 19.3 导出 Word 与 AI 读题（reasoning-core task-94 + Lead 接线 + threadflow-engine task-96）

- 纯逻辑 `paper_docx.dart`：`PaperDocxQuestion.answerImages`（默认空）、`PaperDocxBuildResult.answerImageCount`、
  `imageCount` 收窄为题干配图数（`imageSkippedCount` 仍两类合计）、`PaperDocxLabels.answerImagesLabel`
  （默认「答案与解析截图」）；附录里答案/解析/理由之后渲染小标题 + 等比缩放嵌图，跳过规则与题干图一致、
  note 带「第 N 题答案截图」前缀；答案区三个开关全 false 时不渲染截图。+12 例（目录 +169 全绿）。
- 应用层 `paper_docx_export.dart`：新增 `loadQuestionDocxAnswerImages`（role=answer，notePrefix='答案截图：'），
  与 stem 加载器共用参数化实现；`QuestionDocxRow.toPaperDocxQuestion({images, answerImages})`；
  `PaperDocxExportResult.answerImageCount` 透出；两类跳过告警都收。+5 例（`paper_docx_export_test` → +24 全绿）。
- AI 工具：`read_question` / `read_questions_by_serials` 的 `image_count` 只数题干配图，新增
  `answer_image_count`（answer/solution 同桶，未知 role 两桶都不计、每行两键恒在）；摘要分别报
  「配图 N 张」「答案/解析截图 M 张」。分类 helper 刻意不 import 带 dart:io 的 store。+5 例，两文件 +36 全绿。
- Word COM 真测：探针样张加一张 620×860 答案截图 → **2 页 / 553 字 / 3 图 / 29 OMath / PDF 208,132 B**，
  正文含「答案与解析截图」标签（详见 `docs/DOCX_EXPORT_DESIGN.md` §15.4）。提交 `9489fc6`、`a4f3646`。

### 19.4 未做 / 未验证

- 真机 FilePicker 选答案截图与真实磁盘落盘/删除未手测（widget test 用内存假 store）。
- 真实 v27 库的 role 往返只由 Lead 的 store 测试覆盖，UI 层经假 store 验证。
- 大图查看器不看 role（答案截图与题干配图共用同一查看器，不显示角色标签）。
- 小屏上「题干配图区 + 答案截图区」连续摆放的版面未真机看；英文文案未母语校对。
- 答案 JPEG 仍不自动下载（不做 WAF/登录态代持）；没有「截图自动裁边/压缩」。

## 20. 题库包（.tqb）：题库的导出/导入（轮次一百三十六，2026-10-21）

Word 是给人看的，题库包是给另一台 Furnace 用的：把**题目 + 选项 + 标签路径 + 配图/答案截图 +
组卷网来源链接**打成一个 zip 搬走。它和工作区备份（.tfpkg）刻意分工：.tfpkg 是整个工作区、replace
模式、导入前自动备份；.tqb 只含题库子集、**只追加不覆盖**，所以导入前不备份（没有东西会被改写）。

### 20.1 包格式

- zip 内三条目：`manifest.json`、`questions.json`、`media/q<题序>/<图序>.<ext>`
  （题序 1 起、图序 0 起，例 `media/q3/0.png`）。
- manifest：`format='furnace-question-bank'`、`version=1`、`exported_at`（ISO8601）、`app_version`、
  `question_count`、`media_count`、`generated_by`。format 不匹配报「不是题库包」，版本非 1 报
  「不认识的题库包版本」。
- questions.json 每条：题干/答案/解析、学科/题型/来源档位/来源标注/年份/地区/难度/难度来源/易错点、
  origin/state、**题号 serial_no（只作参考，导入时不用）**、来源三元组 `source_url` /
  `zujuan_question_id` / `zujuan_bank_id`、选项 `options[]`（label/content/is_correct/sort_order）、
  标签路径 `tag_paths[]`、媒体 `media[]`（pack_path/file_name/mime/role/sort_order）。
- 媒体扩展名白名单 png/jpg/jpeg/gif/webp/bmp/heic（统一分派到配图与答案截图两种 role，
  未知 role 折成 stem）；**不导出**知识点、思维导图、卡片/复习状态、主题、应用外观。
- 上限 5000 条（`kQuestionPackMaxRecords`），超了整包拒绝解码而不是截断。

### 20.2 纯逻辑层（task-102 reasoning-core / task-103 threadflow-engine）

- `lib/domain/services/package/question_pack_manifest.dart`（232 行）：`QuestionPackManifest` +
  encode/decode + `QuestionPackException{message, path}`。record.dart 不 re-export 它，容器层要自己 import。
- `question_pack_record.dart`（732 行）：`QuestionPackMedia` / `QuestionPackOption` /
  `QuestionPackRecord`。校验在**解码时**做：题干非空、年份 1900..2100、题号 >=1、难度有限数值、
  选项 label 去空格大写后单个 A-Z 且同题唯一、媒体 path 不许绝对路径/反斜杠/`..`、role 三选一；
  错误带路径（`questions[1].options[0].label`）而不是「解析失败」。81 例。
- `question_pack_plan.dart`（283 行）：`planQuestionPackImport({records, fingerprintOf,
  existingFingerprints, existingTagPaths})` -> 每题一个 create / skip_duplicate 决策 + warnings +
  missingTagPaths。判定顺序：先比目标题库已有指纹，再比包内前序重复；跳过与缺标签都进 warnings
  （跳过按题序、缺标签按字典序、缺标签最多列 20 条再补一行「还有 N 条」）；`questionPackMediaPath`
  生成/校验包内媒体路径。永不抛。53 例。
- 目录内 `flutter test test/domain/services/package --concurrency=1` -> +134 全绿。

### 20.3 数据层与应用层（task-104 Lead）

- `lib/data/package/question_pack_source.dart`（247 行）：`readQuestionPackSource({database, readMedia})`
  一次读 questions/question_options/tags/object_tags/attachments，按题号（无号排最后、再 id）与
  sort_order 排好，配图按题序生成 `media/qN/M.ext`；扩展名不认识或读不到字节 -> 不进包、记
  `skippedMedia` + warning（导出不因一张坏图整体失败）。
- `lib/data/package/question_pack_codec.dart`（194 行）：`encodeQuestionPackArchive` /
  `decodeQuestionPackArchive` / `readQuestionPackManifest`（peek 只解 manifest，不解题库体）。
  缺 manifest/缺 questions.json/题目引用的媒体不在包里 -> 整包失败并指出 path；多余媒体条目忽略；
  zip 解析异常包成 `QuestionPackException`。
- `lib/features/questions/application/question_pack_service.dart`（332 行）：`exportBytes({now})` /
  `peek(bytes)` / `importPack(bytes,{now})` + `questionPackServiceProvider`。导入流程：
  decode -> 读目标库已有指纹与标签路径 -> plan -> 只对 create 决策 `ingest`（题号由目标库 MAX+1
  重新分配；**标签只挂目标库已存在的路径**，缺的不新建只告警）-> 媒体 `store.save(role/sortOrder)`。
  单题入库异常进 failures、单图落盘异常进 warnings，报告分开数 created/skipped/media。
  13 + 12 例（含内存库端到端 round-trip：题 + 选项 + 标签 + 答案截图真实落盘往返）。
- 设计取舍：不做「导入前自动备份」——additive 模式没有覆盖面；不保留来源题号——同号在目标库
  可能已被别人占用，题号是「本库身份」不是「内容身份」；重复题按题干指纹跳过，不合并标签/图片。

### 20.4 设置页 UI（task-105 question-intake）

- 设置 -> 数据区末尾新增「题库包（.tqb）」小节（`_QuestionPackSection`，`data_section.dart` +272）：
  导出 tile -> 空题库只提示不弹保存框 -> `FilePicker.saveFile` 写 `furnace-<yyyyMMddTHHmm>.tqb`；
  导入 tile -> 只收 `.tqb` -> `peek` 坏包只提示不写库 -> 预览对话框（题数/图数 + 「只新增不覆盖」）
  -> `importPack` -> 结果对话框（created/skipped/media + warnings 条数 + 前 3 条 failures）。
  操作期间两行禁用防重入；成功后 invalidate 题库列表/计数/体检共四个 provider。（导出 warnings 的展示在轮次一百三十七补上，见 §21.4。）
- l10n 13 个 key 五文件手改（未跑 gen-l10n）；12 例 widget test（导出/取消/空库/抛错、导入取消/
  坏包/预览/结果/抛错、防重入、插值与大小格式化）。settings + presentation 两目录 +376 全绿。

### 20.5 验收与未做

- 门禁：`dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）；全量
  `flutter test --concurrency=1` -> **+4792 ~2 All tests passed，9 分 43 秒，EXIT=0**
  （日志 `E:/dsh-tmp-aot/test-136-full.txt`）。
- 未做 / 未验证：真机 FilePicker 保存/选择未手测；未用真实 `.tqb`（跨设备/跨版本）样本端到端；
  5000 题大包的内存/耗时未测；重复题跳过不提供「合并图片/标签」；
  包内无知识点（只带标签路径，知识点要在目标库自己映射）；不做加密/分卷/压缩级别选择。

## 21. 题库包第二轮：选择性导出、导入预检、导出告警上屏（轮次一百三十七，2026-10-21）

### 21.1 筛选题库包记录（纯逻辑，task-106 reasoning-core）

- `lib/domain/services/package/question_pack_selection.dart`（247 行）：`QuestionPackSelection`
  （`subjectKeys` / `sourceLevels` / `tagPaths` / `serialFrom` / `serialTo`，`isEmpty` / `hasSerialRange` /
  `toJson` / `==`）；`questionPackRecordMatchesSelection(record, selection)`；
  `selectQuestionPackRecords({records, selection})`（保序、不可变）；
  `questionPackFieldsMatchSelection(...)`（数据层筛行版，先筛再读配图字节）；
  `normalizeSerialBound(String?) -> int?`（纯半角数字，`'0012' -> 12`、`'0' -> 0`，其余 null）。
- 口径：空选择=全部；集合空=不约束；多维 AND；学科/来源 trim 后区分大小写；标签路径任一交集
  即命中；题号区间含两端、`serialNo == null` 且有区间 -> 不命中、`from > to` 交换归一、
  `<= 0` 视为该端未给；永不抛。
- 回归 bug（Lead 的导出测试抓到）：`_SerialRange.of` 原来 `final int upper = to ?? from!;`，只给
  `serialFrom` 时区间退化成 `[from, from]`（`serialFrom: 2` 只命中题号 2，漏 3）。改成只给 from 时
  上界用无界哨兵 `_unboundedAbove = 9223372036854775807`、只给 to 时下界仍 1；补 5 例回归
  （只 from / 只 to / 反向 / null 题号 / 非正边界）。测试 838 行 9 组 59 例。

### 21.2 导入前预检聚合（纯逻辑，task-107 threadflow-engine）

- `lib/domain/services/package/question_pack_import_preview.dart`（236 行）：`QuestionPackImportPreview`
  11 字段（manifest 题数/媒体数、recordCount、mediaCount、appVersion、exportedAt、createCount、
  skipCount、missingTagCount、warnings、missingTagPaths；`isEmpty` / `hasWarnings` / `isFullyNew` /
  `hasManifestMismatch` / `summaryZh` / `toJson`）；`buildQuestionPackImportPreview({manifest, records, plan})`。
- 口径：`mediaCount = Σ record.media.length`；warnings 顺序 = manifest 层（清单数与实际数不符）->
  plan.warnings 原序，完全相同去重；`summaryZh` 固定 2–4 行、只给日志/调试，**UI 不显示**；
  `exportedAt` 在模型上可空只是方便直接构造（manifest 里必填）。34 例。

### 21.3 数据层 / 应用层（task-108 Lead）

- `lib/data/package/question_pack_source.dart`（236 行）：`readQuestionPackSource({database, readMedia,
  selection = const QuestionPackSelection()})`。先按题号排序再按 `questionPackFieldsMatchSelection`
  筛行——**未选中的题不读配图字节**；包内题号按筛选后从 1 重新编号。
- `lib/features/questions/application/question_pack_service.dart`（321 行）：`exportBytes({now,
  selection = const QuestionPackSelection()})`；新增 `planImport(Uint8List bytes) ->
  Future<QuestionPackImportPreview>`（decode -> 读目标库已有指纹/标签路径 -> `planQuestionPackImport`
  -> 聚合预览；**不写库、不落图**；坏包抛 `QuestionPackException` / `FormatException`）。
  预检与实际导入共用同一套计划函数，口径不会分叉。
- 测试 `test/features/questions/application/question_pack_selection_export_test.dart`（408 行 19 例）：
  选择性导出 12 例（空选择=全部、学科/来源/题号单边与反向、标签直接挂、多条件 AND、包内重编号、
  未选中不读媒体字节、0 命中空包、清单计数、筛选不改库）+ `planImport` 7 例（全新增、全重复、缺标签、
  坏包、筛选导出包、预检不写库、预览字段）。注意 zip 条目带生成时间戳，字节不保证逐次相同，断言比
  解包后的记录而不是字节长度。

### 21.4 设置页 UI（task-109 question-intake）

- 新增 `lib/features/settings/presentation/question_pack_export_filter_dialog.dart`（235 行）：
  `questionPackSerialRangeIssue(rawFrom, rawTo)`（`invalidFrom` / `invalidTo` / `reversed`）、
  `questionPackSelectionFromFilter(...)`、`QuestionPackExportFilterDialog`（默认全不选=全部；学科 chips
  用 `subjectLabelOf`、来源六档 chips、题号起止数字框实时校验、非法时禁用导出；取消返回 null）。
- 改 `lib/features/settings/presentation/data_section.dart`（621 行）：导出按钮先弹筛选对话框
  （取消直接 return）-> `exportBytes(selection:)` -> 0 题按「全部/筛选」两种文案提示且不弹保存框 ->
  `FilePicker.saveFile` -> warnings 非空弹「导出提示」对话框，否则 SnackBar。导入改用 `planImport`
  取代 `peek`（坏包只提示、不写库）-> 预览显示 recordCount/mediaCount + create/skip/无新题/missingTags/
  warnings（可滚）-> 确认后 `importPack` -> 刷新 4 个题库 provider。
- l10n 五文件各 +16 key（13 无参 + 3 个 `count:int` 有参），手改未跑 gen-l10n。
- 测试：`question_pack_section_test.dart` 19 例（含筛选后 selection 断言、内联错、warnings 对话框、导入
  预览各态），新增 `question_pack_export_filter_test.dart` 12 例（纯函数 + 对话框 widget）；
  `flutter test test/features/settings` -> 65 全绿。
- 已知限制：en 界面学科 chip 仍显示中文词表名（沿用 `subjectLabelOf`，本轮不加学科 l10n key）；
  导出 warnings 用对话框展示（比 SnackBar 更能列全）；真机 FilePicker 仍未手测。

### 21.5 门禁与未做

- 组合测试：`flutter test test/data/package test/domain/services/package test/features/settings
  test/features/questions/application --concurrency=1` -> +600 All tests passed；
  `dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）；全量
  `flutter test --concurrency=1` -> +4923 ~2 All tests passed，9 分 54 秒（日志 `E:/dsh-tmp-aot/test-137-full.txt`）。
- 未做 / 未验证：仍未用真实 `.tqb`（跨设备/跨版本）端到端；真机 FilePicker 未手测；
  筛选对话框没有「按标签路径」与「按题号多段」输入（纯逻辑已支持 tagPaths；标签路径已在一百三十八补，见 §22.2，题号多段仍未暴露）；
  导入后不合并重复题的图片/标签；不做导入前自动备份（append 模式）。

## 22. 题库包第三轮：按标签路径筛选与排序偏好落盘（轮次一百三十八，2026-10-21）

### 22.1 标签路径选项纯逻辑（task-111 reasoning-core）

- `lib/domain/services/package/question_pack_tag_options.dart`（157 行）：`QuestionPackTagPathOption`
  （`path` / `questionCount` / `selected` / `weight` / `isEmpty` / `toJson` / `==` / `hashCode` / `toString`）；
  `questionPackTagPathOptions({tagPaths, questionCountByPath, selectedPaths, maxOptionCount = 200})`；
  `normalizeQuestionPackTagPath`；`selectedQuestionPackTagPaths`。
- 口径：路径 trim、去空、按归一路径去重保序；计数缺省 0、负数归 0；排序 = 题数降序 -> 路径
  UTF-16 升序；`selected` 精确匹配、不改动顺序、超上限也补回（结果总数可超过上限）；
  `maxOptionCount <= 0` 只留已选；返回不可变列表、永不抛。43 例。

### 22.2 设置页标签路径筛选（task-112 question-intake）

- 新增 `lib/features/settings/presentation/question_pack_tag_path_picker.dart`（221 行）：
  `questionPackTagPathOptionsProvider`（`watchDatabaseRevision` + `getAllTags` +
  `objectCountByTagId(objectTypes: {'question'})`）、`questionPackTagPathOptionsFromTags`（路径为空
  退化 `tag.name`、空名字丢弃、同一路径题数相加）、`QuestionPackTagPathPickerDialog`（搜索框 +
  复选列表，行文案「路径 · N 道」；空库与无匹配分开提示；取消返回 null 且不动旧选择；确认返回
  选中集合；已选但已从题库消失的路径计 0，仍能取消勾选）。
- `question_pack_export_filter_dialog.dart`（235 -> 299 行）：`questionPackSelectionFromFilter` 增
  `tagPaths` 参数，经 `selectedQuestionPackTagPaths` 归一并进 `QuestionPackSelection`；主对话框新增
  「标签路径」按钮（key `question-pack-filter-tag-paths`），未选显示「选择标签路径」、已选显示
  「标签：已选 N 条」。
- l10n 五文件各 +8 key（`settingsQuestionPackFilterTags` / `FilterTagSelect` / `FilterTagsSelected`
  (`count:int`) / `TagPickerTitle` / `TagPickerSearch` / `TagPickerEmpty` / `TagPickerNoMatch` /
  `settingsQuestionPackTagQuestionCount`(`count:int`)），手改未跑 gen-l10n。
- 测试：新增 `question_pack_tag_path_picker_test.dart` 10 例（纯逻辑 4 + 对话框 6）、导出筛选 +3、
  section +8 键断言、tag tree +5。

### 22.3 标签树排序偏好落盘（task-110 Lead + task-112 question-intake）

- schema v29：`local_settings.tag_tree_sort_mode`（TEXT nullable，NULL = 出厂字典序；存域层 code
  `alphabetical` / `object_count` / `created_at`，不存中文）。`database.dart` schemaVersion 28 -> 29 +
  `_upgradeV28ToV29` + `_ensureColumns` 自愈补列；`SettingsRepository.getTagTreeSortMode` /
  `updateTagTreeSortMode`（trim；空白写 NULL；null = 恢复出厂；未知 code 不拒绝，读侧降级为字典序）。
  迁移与读写口径见 `docs/DATA_MODEL.md` §18。
- `tag_tree_page.dart`（559 行）：`tagTreeSortModeProvider` 改为
  `AsyncNotifierProvider<TagTreeSortModeController, TagTreeSortMode>`；启动读库恢复偏好，切换时先更新
  内存态再写库，写失败只 `debugPrint` 不影响本次会话；偏好加载期间树按字典序渲染不空白。
- 测试：`v29_migration_test.dart` 4 例（真实 v28 升级、缺列自愈、空白/未知 code/null 清回出厂、
  新库无行）+ `settings_repository_test.dart` +3 例；`tag_tree_page_test.dart` +5 例（启动恢复、
  切换写库、写失败仍生效）。

### 22.4 门禁与未做

- 组合测试：`flutter test test/data/database test/data/repositories/settings_repository_test.dart
  test/domain/services/package test/features/tags test/features/settings --concurrency=1` ->
  +459 All tests passed；`dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）。
- 未做：标签树只有三档排序，没有手动拖拽排序；en 界面排序菜单与标签路径按钮仍是中文；
  标签路径筛选是平面多选，没有子树级联（选父不自动选子）；题号多段筛选仍未做。


## 23. 题库的「可读」一面：题名、总览、图文混排（轮次一百三十九，schema v30）

这一轮不是加数据，而是把已经存在的题**读起来像题库**：给题一个名字、总览只留必要信息、
详情页图文混排并把公式渲染出来。用户反馈原话（m09439）：「题目图片应该直接呈现大图与文字
放在一起」「很多文字不需要放在一个卡片底座上」「题库整体预览……呈现必要信息、标签和题目
命名」「让鼠标移动尽量减少」。

### 23.1 题名列（schema v30，Lead）

- `questions.title` TEXT nullable：NULL = 还没名字，界面回落题干摘要；自动命名只填空，
  **不覆盖用户改过的名字**。长度与去重归域层（见 §23.2），仓库不截断。
- `database.dart` schemaVersion 29 -> 30 + `_upgradeV29ToV30` + `_ensureColumns` 自愈；
  迁移不回填（旧题保持 NULL，等用户/批量命名）。迁移口径与测试见 `docs/DATA_MODEL.md` §19。
- `QuestionRepository.setQuestionTitle(id, title?)`（返回是否命中）与
  `setQuestionTitles(Map<String, String?>)`（一次事务、返回命中行数；key trim 后为空跳过；
  title null/空白 -> 写 NULL）。

### 23.2 题名生成纯逻辑（reasoning-core，task-116）

`app/lib/domain/services/questions/question_title_suggestion.dart`（538 行）：

- `QuestionTitleSuggestion suggestQuestionTitle({stem, subjectKey, questionType,
  knowledgePointNames, existingTitles, maxLength = 32})`：核心短语 = 题干首句（全角
  。！？；与换行切）-> 去题号/来源括号（小数 2.5 不误剥、条件括号不剥）-> 删 Markdown 图与
  `［图N］` -> 去 `$` 定界符保留内部 -> 压空白去尾标点；再按「知识点名 · 核心短语」或
  「学科中文名 · 核心短语」拼总长 <= maxLength（runes）。
- `normalizeQuestionTitle` / `isValidQuestionTitle(maxLength = 80)` / `uniqueQuestionTitle`
  （冲突加「（2）」…「（99）」）；空题干兜底「未命名题目」。
- **自动命名只在长度/冲突上做保证，不承诺语义一定准确**——用户随时改名，名字优先于摘要。
- 测试 55 例。

### 23.3 题库总览读表与 provider（Lead，task-120）

- `app/lib/features/questions/application/question_library_reader.dart`：一次读
  questions（updatedAt 降序 / id 升序，limit+1 判 truncated）+ attachments（ownerType='question'，
  role NULL 视作 stem，按 sortOrder -> attachmentId）+ object_tags/tags（objectType='question'）。
  纯读表、不 import `dart:io`。
  - `QuestionLibraryImage`（role/isStem/isAnswer/isSolution）、`QuestionLibraryEntry`
    （serialLabel「TR-00042」或「未编号」、displayTitle（无名字回落题干摘要）、stemPreview
    压空白截 60 字、coverImage 题干图 -> 答案图 -> 解析图、tagPaths、imageCount）、
    `QuestionLibrarySnapshot`（totalCount/truncated/untitledCount/subjectKeys/tagPaths）。
- `question_library_provider.dart`：`questionLibraryOverviewProvider`（autoDispose，
  watchDatabaseRevision -> 库一改就重读）。测试 12 例。

### 23.4 题库页重做（question-intake，task-121）

`app/lib/features/questions/presentation/question_bank_page.dart`（619 行）——从「一堆 Card 列表」
改成「少信息 + 大图 + 名字 + 标签」：

- 空态只两行文字，没有 Card 底座；统计行 + truncated 提示 + 学科 ChoiceChip 筛选 + 无匹配态。
- 每行 `_EntryRow`：封面 128x96（`thumbnailDecodeSpec` 按 DPR 解码，不整图解码）+
  题名（无则题干摘要）+ 题号（dense）+ 学科 + 前 3 个标签叶子 + 「+N」+ 体检徽标 +
  ⋮ 菜单（改名 / 自动命名 / 复制题号）。
- AppBar 批量自动命名：只为未命名题生成（`suggestBulkQuestionTitles`），一次事务写出，
  完成 SnackBar 报「命名了 N 道 / 部分失败」。
- 测试 14 例（原 7 + 新 7）。

### 23.5 题名对话框（question-intake）

`app/lib/features/questions/presentation/question_title_dialog.dart`（294 行）：

- `showQuestionTitleDialog` 返回 `QuestionTitleDialogResult`；输入框预填当前名字，旁边
  「自动生成」用 `suggestQuestionTitleForEntry`（题目行）+ `suggestBulkQuestionTitles`；
  「清除」= 写 NULL 回到摘要兜底；保存前 `normalizeQuestionTitle` + `isValidQuestionTitle`
  （80 上限），失败就地提示不写库。
- 写库成功后 invalidate `questionLibraryOverviewProvider` 与 `questionDetailProvider`。
- 测试 8 例。

### 23.6 详情页图文混排与公式（question-intake，task-118；Lead 提供切分器）

- 题干图片占位切分纯逻辑（Lead）`app/lib/domain/services/questions/question_stem_segments.dart`：
  `splitQuestionStemImages(stem, {imageCount})` 认 `［图1］`/`[图 1]`/`【图１】`（全角数字、
  括号不必配对）；N 从 1 对应第 N 张题干图；越界/重复 N 原文保留不吞字；返回
  `QuestionStemLayout{segments, unplacedImageOrders, referencedImageCount}`，另给
  `questionStemPlainText`。测试 33 例。
- `question_media_view.dart` 新增 `QuestionRichText`（无公式走纯 `SelectableText`；含成对
  `$…$`/`\(…\)` 才用 `GptMarkdown(useDollarSignsForLatex: true)`）与 `QuestionInlineImage`
  （全宽、圆角、maxHeight=屏高 60%、按 DPR 只传 cacheWidth、占位框、点击看大图、可删）。
- `question_detail_page.dart`：`_QuestionBody` 去掉 Card 底座（间距 + 小节标题 + 分隔线）；
  `_QuestionStemView` 按占位把大图插进题干流、未被引用的图按顺序接末尾；答案截图放在
  「答案」段之后；题名行未命名回退「未命名题目」+ 笔形按钮改名。测试 +3 例（图文顺序且公式
  不残留字面 $、无占位图接末尾、答案截图位置）。

### 23.7 门禁与未做

- 各片门禁见 `docs/PROGRESS.md` 轮次一百三十九；全量数字以 Lead 收尾跑的真实输出为准。
- 未做 / 未验证：大图从占位高度到真实高度的跳变、SVG 图不支持、相似题等下方区块仍是 Card、
  平板真机滚动手感与 500 条列表性能未测；en 界面题名相关文案已进 l10n，但排序模式名仍是中文。

## 24. 题库批量操作：按 id 导出、批量打标签（轮次一百四十）

轮次一百四十解决用户反馈「处理几个题要一道道点开、鼠标来回跑」：题库页进入多选后，
一次选中多道题做三件事——打标签、导出选中、删除。数据层与纯逻辑先行，UI 最后接线。

### 24.1 题库包按题目 id 集合导出（task-122，Lead）

- `app/lib/data/package/question_pack_source.dart`：`readQuestionPackSource` 新增
  `Set<String> questionIds = const <String>{}`。非空时只保留这些题（trim 后比较，未知 id
  安静忽略），空集合 = 不按 id 约束；与 `QuestionPackSelection` 取交集。过滤发生在读配图
  字节之前，未选中题的图片不会从磁盘读出来、更不会进包；包内题序按筛选后从 1 重新编号。
- `app/lib/features/questions/application/question_pack_service.dart`：`exportBytes` 透传
  `questionIds`（设置页的「按标签路径筛选导出」与此互不影响）。
- 测试 `app/test/features/questions/application/question_pack_selection_export_test.dart`
  新增 8 例：只导出选中且保留原题号、未知/空白 id 忽略、空集合全量、与 selection 交集、
  包内序号从 1 重排、未选中题不读配图字节、清单计数按选中后、导出不改库行数。该文件合计 27 例。

### 24.2 TagRepository 批量挂/摘标签（task-123，threadflow-engine）

- `addTagToObjects({tagId, objectIds, objectType = 'question'})`：一次事务，先查已存在的
  `(tagId, objectType, objectId IN ids)`，只插缺失行（`insertOrIgnore`），返回**真实新增数**；
  重复调用返回 0 而不是报错。`removeTagFromObjects` 同口径，返回真实删除行数。
  输入统一 trim/去空/保序去重；空输入立即返回 0。
- 测试 `app/test/data/repositories/tag_repository_test.dart` 新增 11 例（该文件合计 27 例）：
  批量挂载计数、重复挂载 0、混合已挂只计新增、空输入、objectType 隔离、批量摘只删指定对象等。

### 24.3 纯逻辑：批量打标签计划（task-124，reasoning-core）

- `app/lib/domain/services/questions/question_bulk_tag_plan.dart`：
  `QuestionBulkTagPlan`（`usableTagPaths` / `missingTagPaths` / `questionIdsByTagPath` /
  `linkCount` / `affectedQuestionCount` / `skippedExistingLinkCount`）与
  `planQuestionBulkTag({questionIds, tagPaths, knownTagPaths, existingTagPathsByQuestionId})`。
- 口径：空输入给空计划；词表里没有的路径进 `missingTagPaths`（保序、不产生挂载）；已挂的
  (题, 路径) 对只计入跳过数；**不查库、不判未知题**（所以结果里没有 unknownQuestionCount）；
  任何输入不抛；结果列表与 map 全不可变。
- 测试 `app/test/domain/services/questions/question_bulk_tag_plan_test.dart` 6 组 37 例；
  `test/domain/services/questions` 目录 +450 全绿（基线 413 无回归）。

### 24.4 应用层：tagQuestions（task-125，Lead）

- `app/lib/features/questions/application/question_bulk_tagging.dart`：
  `kQuestionBulkTagObjectType = 'question'`；`QuestionBulkTagReport{addedLinks, skippedLinks,
  affectedQuestionCount, missingTagPaths, failedTagPaths, isEmpty, hasMissingTagPaths,
  hasFailures}`；`tagQuestions({required TagRepository tags, required Iterable<String> questionIds,
  required Iterable<String> tagPaths})`。
- 流程：读标签词表（路径取 `tag.path`，为空回落 `tag.name`）→ 逐题读 `tagsForObject` 已挂
  标签 → `planQuestionBulkTag` → 逐路径 `addTagToObjects`。某条路径抛异常只进
  `failedTagPaths`，其它路径照常写；`affectedQuestionCount` 只数真正新增过链接的题，写入
  失败时不会虚报。`isEmpty` 是「没有任何动作且没有任何问题」，全部已挂（只有 skipped）时
  仍为 false，便于界面如实报告「跳过 N 条」。
- 测试 `app/test/features/questions/application/question_bulk_tagging_test.dart` 9 例（内存库 +
  真实 TagRepository）：新增计数、已挂跳过、缺失路径不写行、重复调用新增 0、空输入不碰库、
  去空白去重、单路径写入失败不拖垮整批、路径大小写敏感、标签 path 为 NULL 回落 name。

### 24.5 题库页多选与三个批量动作（task-126，question-intake）

- `app/lib/features/questions/presentation/question_bank_page.dart`（619 → 1012 行）：多选态
  AppBar（已选 N 项 / 全选 / 清空 / 退出）、底部动作条（打标签 / 导出选中 / 删除，操作中禁用
  并显示进度条）、行首 Checkbox、长按任意行直接进多选并选中该行；普通态只有「题库里有题」时
  才出现多选入口。全选只作用于当前学科筛选下的题，不会偷偷选中被筛掉的。
  新增顶层 Key：`questionBankSelectKey` / `questionBankExitSelectionKey` /
  `questionBankSelectAllKey` / `questionBankClearSelectionKey` /
  `questionBankTagSelectedKey` / `questionBankExportSelectedKey` /
  `questionBankDeleteSelectedKey`；纯函数 `questionBankDeletePreview`（前 3 个题名用「、」
  连接，超出追加「等 N 道」）与两个本地 helper（文件大小、文件名时间戳），不跨 feature
  import 设置页。
- 打标签：新文件 `app/lib/features/questions/presentation/question_bulk_tag_dialog.dart`
  （175 行）：读 `tagRepositoryProvider.getAllTags()`，路径排序、可搜索、多选，确认直接执行
  `tagQuestions`（不再二次确认）；SnackBar 依次报告新增/跳过、缺失路径数、失败路径。
- 导出选中：`questionPackServiceProvider.exportBytes(questionIds: 选中集合)` → 0 题只提示、
  不弹保存框 → `FilePicker.saveFile` 默认名 `furnace-<时间戳>-selected.tqb`；取消保存静默，
  成功提示题数与文件大小。
- 删除：先确认（标题「删除 N 道题？」+ 前 3 个题名预览），逐题
  `questionMediaStore.deleteForQuestion` → `questionRepository.deleteQuestion`，单题失败不
  中断整批、最后汇总失败数；完成后退出多选。
- l10n 21 个新 key（11 个无参 + 10 个带参，中英都填），五个文件手改、未跑 gen-l10n。
- 测试：新文件 `app/test/features/questions/presentation/question_bank_bulk_test.dart`（541 行，
  17 例：16 widget + 1 纯函数 `questionBankDeletePreview`），既有
  `question_bank_page_test.dart` +2 处入口断言；`test/features/questions/presentation`
  目录 +368 全绿（基线 351，+17，无回归）。

### 24.6 门禁与未做（轮次一百四十）

- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（基线 92；本轮把一条历史
  info 修掉后回到 91，没有新增问题）。
- 全量 `flutter test --concurrency=1` → **+5221 ~2 All tests passed**，11 分 08 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-140-full.txt`；上一轮基线 +5139，本轮 +82）。
- 未做 / 未验证：真机 Windows 的 `FilePicker.saveFile` 与 `pickFiles` 未手测；多选态行尾
  「⋮」菜单仍可打开（改名/自动命名/复制题号在多选态下仍作用于单题，没有禁用）；导出
  warnings 在批量路径未单独上屏（只在导入侧提示）；批量打标签不提供「摘标签」入口（数据层
  `removeTagFromObjects` 已就绪，界面未接）；一次选中数千题的性能与确认框滚动未验证。

切片组合：`flutter test test/features/questions/application test/features/settings` +384、
`test/features/questions/presentation` +368（基线 351）、`test/data/repositories/tag_repository_test.dart`
+27、`test/domain/services/questions` +450（基线 413）。l10n 五个文件校验：zh/en ARB 各 1405 个
key 对齐、21 个新 key 占位符声明齐全（与 HEAD 相同的 29 条历史未声明键不是本轮引入）。

## 25. 题库页：可读摘要 + 搜索 + 标签筛选（轮次一百四十一，2026-10-23）

抓题专属 agent 产出的 `.tqb` 题干是给渲染层准备的：公式包在 `$…$` 里、题干图片只留
「［图N］」占位。题库列表此前直接显示原始题干（一堆美元符与方括号），并且只有学科 chips，
没有搜索、也不能按标签找题。本轮把这两件事拆成纯逻辑层先做扎实，UI 再接线。

### 25.1 题干可读摘要（新增纯逻辑）

- 新文件 `app/lib/domain/services/questions/question_stem_preview.dart`：
  `String questionStemPreview(String stem, {int maxLength = kQuestionStemPreviewMaxLength})`。
  常量：`kQuestionStemPreviewMaxLength = 60`、`kQuestionStemPreviewImageToken = '［图］'`。
- 口径：`$$…$$` / `$…$` 去掉**定界符**保留内部（`$x^2$` → `x^2`）；没配对的美元符直接删；
  Markdown 图片删除、Markdown 链接只留文字；`[图1]` / `［图2］` / `【图12】` / 全角数字占位统一换成
  `［图］`（没有数字的方括号与越界序号不动）；所有空白折叠成一个半角空格后 trim；按 **runes**
  截断到 `maxLength` 并在超出时补 `…`（不会把 emoji 切成半个）；`maxLength <= 0` 或空题干返回空串；
  不抛异常。
- 接入：`app/lib/features/questions/application/question_library_reader.dart` 的
  `QuestionLibraryEntry.stemPreview` 改为调用它，`displayTitle` 的兜底随之变成可读文本；
  旧的本地 `_preview`（只折空白 + 按 UTF-16 截断）删除。
- 测试：新文件 `app/test/domain/services/questions/question_stem_preview_test.dart` 25 例；
  `test/features/questions/application/question_library_reader_test.dart` 补 1 例断言公式/占位收口
  （该文件共 13 例）。两文件实跑均 All tests passed，`dart analyze` No issues。

### 25.2 筛选纯逻辑（新增）

- 新文件 `app/lib/features/questions/application/question_library_filter.dart`（195 行）：
  `class QuestionLibraryFilter { const QuestionLibraryFilter({String subjectKey = '', Set<String> tagPaths = const <String>{}, String text = ''}); }`
  （`static const empty`、`isEmpty`/`isNotEmpty`、`copyWith`、Set 顺序无关的 `==`/`hashCode`、`toString`）；
  `bool questionLibraryEntryMatches(QuestionLibraryEntry entry, QuestionLibraryFilter filter)`；
  `List<QuestionLibraryEntry> filterQuestionLibraryEntries(Iterable<QuestionLibraryEntry> entries, QuestionLibraryFilter filter)`
  （保序、返回 `List.unmodifiable`；空筛选返回全部条目的不可变副本）。
- 口径：三层之间 **AND**。学科空=不限、否则精确（大小写敏感）；标签空集=不限、否则多选 **ANY**
  且按**子树**匹配（命中条件 `q == p || q.startsWith('$p/')`，选了父路径也能找到挂在子路径的题，
  反向不成立，`文化课/学科群` 不会被 `文化课/学科` 误命中）；文字空=不限，否则先按题号解析
  （复用 `question_number_query.dart`，认 `TR-42` / `#42` / `42` / 全角数字），题号命中即真，
  未命中再对题名、题干、题号标签、学科、来源、标签路径做大小写不敏感子串匹配。
- 构造不归一字段（保持 `const`），判定时按需 trim：全空白标签项等价于空集，`subjectKey`/`text`
  的空白等价于不限；`==` 仍按原始字段比较（已知且有意的小差异，doc 已写明）。
- 测试：新文件 `app/test/features/questions/application/question_library_filter_test.dart`
  （744 行、8 组 62 例：空筛选/学科/标签子树/文字/题号/组合/copyWith 与相等性/过滤列表与健壮性）。
  实跑 `+62 All tests passed`、`dart analyze` No issues。
- 已知待办：`app/lib/features/questions/presentation/question_intake_providers.dart:35` 另有一个
  **同名旧类** `QuestionLibraryFilter`（字段为学科/来源/状态/题干/题号集合，供收题页搜索用）。
  两者目前互不 import（各自 analyze 通过），但同一文件同时 import 会命名冲突；后续把旧类改名
  （建议 `QuestionIntakeFilter`）或迁到收题页专用文件。本轮未动 presentation 旧类。

### 25.3 题库页 UI（搜索框 + 标签筛选 + 空态）

- 改 `app/lib/features/questions/presentation/question_bank_page.dart`：页面状态从单个
  `_subjectKey` 改为 `QuestionLibraryFilter _filter`（:125），另加搜索 `TextEditingController`
  `_search`（:145，initState 建、dispose 释放）。方法：`_applyFilter`、`_clearSearchText`（只清
  输入框并重筛）、`_clearFilter`（学科/标签/文字全清，并同步清空输入框）、`_selectedTagPaths`、
  `_removeTagPath`、`_openTagFilter`。列表统一走 `_visibleEntries`
  （`filterQuestionLibraryEntries(snapshot.entries, _filter)`，:320）。
- 学科 chips 现在写 `_filter.subjectKey`（:737-745），与搜索、标签三条件 **AND**；自动命名
  「缺名题」与全选都只作用于 `visibleEntries`（筛出的题），不会偷偷处理被筛掉的题；多选态改筛选
  不清空已选，但已选里看不见的项不显示。
- 新文件 `app/lib/features/questions/presentation/question_library_filter_bar.dart`（175 行）：
  搜索框（输入即筛）、标签筛选按钮、已选标签 chips（Wrap，显式 `Tooltip` 显示完整路径）、
  「筛出 X / 共 Y 道」计数、清除筛选按钮。顶层 Key：`questionBankSearchKey` /
  `questionBankSearchClearKey` / `questionBankTagFilterKey` / `questionBankClearFilterKey` /
  `questionBankFilteredCountKey` / `questionBankNoMatchClearFilterKey`；另有测试定位用
  `String questionBankTagChipKeyFor(String path)` `questionLibraryTagChipLabel(String path)`
  （已选 chip 显示叶子名，完整路径放 Tooltip）。
- 新文件 `app/lib/features/questions/presentation/question_library_tag_filter_dialog.dart`
  （190 行）：`Future<Set<String>?> showQuestionLibraryTagFilterDialog(BuildContext context, {required List<String> tagPaths, Set<String> initialSelection})`——
  返回值三态：`null` = 取消（不改），空集 = 清除标签筛选，非空 = 选中的路径集合。对话框里的候选
  路径由页面传入 `snapshot.tagPaths`（不单独读库）；可搜索的 `CheckboxListTile` 多选。
- 无命中时用 `SliverFillRemaining` 居中空态 + 「清除筛选」按钮（:759-782），不再显示空列表。
- l10n：五个文件手改、未跑 gen-l10n；新增 7 个 key：
  `questionBankSearchHint` / `questionBankTagFilterTitle` / `questionBankTagFilterSelected(int)` /
  `questionBankFilterClear` / `questionBankFilteredCount(int shown, int total)` /
  `questionBankFilterNoMatch` / `questionBankTagFilterClear`，并复用批量打标签已有的
  `questionBulkTagSearchHint` / `questionBulkTagNoMatch`。两个带参 key 都有 `@meta` 声明，
  ARB 里没有字面花括号。
- 修掉一个真实 bug：`InputChip` 自带的 tooltip 只在 `onPressed`/`onSelected` 非空时渲染
  （Flutter SDK `chip.dart:1440-1442`），已选标签 chip 原本看不到完整路径——改为显式
  `Tooltip(message: path)` 包一层。
- 测试：新文件 `app/test/features/questions/presentation/question_bank_filter_test.dart`
  （375 行、15 例：题号搜索 / 题干片段搜索 / 无命中空态与清除 / 清除筛选同步清空输入框 /
  父路径命中子孙 / 两路径并集 + chip key + tooltip / 点 chip 删除 / 对话框清除 / 对话框搜索 /
  学科 + 搜索 AND / 计数 / 多选态全选只选筛出 / 多选态改筛选保留已选 / 搜索 × 只清文字 /
  无标签库提示）。既有测试未改；`test/features/questions/presentation` 目录 **+383 全绿**
  （基线 368，+15，无回归）。

### 25.4 门禁与未做（轮次一百四十一）

- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与轮次一百四十同一基线，
  本轮没有新增问题）。
- 全量 `flutter test --concurrency=1` → **+5334 ~2 All tests passed**，10 分 34 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-141-full.txt`；上一轮基线 +5221，本轮 +113）。
- 切片组合：`test/domain/services/questions/question_stem_preview_test.dart` +
  `question_library_reader_test.dart` + `question_library_filter_test.dart` +
  `question_pack_harvest_roundtrip_test.dart` → **+110**；
  `test/features/questions/presentation` → **+383**（基线 368）。`dart format -o none
  --set-exit-if-changed` 检查本轮 11 个改动 Dart 文件 → 0 changed。
- l10n 五个文件手改（未跑 gen-l10n）：zh/en ARB key 集合一致，7 个新 key 双语齐全，
  两个带参 key 的 `@meta` 与实现里的插值对得上，ARB 没有字面花括号；生成文件的 getter
  齐全（非带参 key 不带 `@meta` 与仓库既有 1412 个 key 的惯例一致）。
- 未做 / 未验证：真机 Windows / Android 未手测筛选与筛选条布局；筛选在**已加载的**
  `readQuestionLibrary(limit: 500)` 快照上做，题库超过 500 道时界面只筛前 500 道
  （`snapshot.truncated` 为真且标签候选也只来自这 500 道）；多选态同时筛到 0 道的同屏
  交互未覆盖；旧 key `questionBankNoMatch` 已无 lib 引用但保留未删；`question_intake_providers.dart`
  的同名旧类 `QuestionLibraryFilter` 仍未改名（见 §25.2）；抓题包回归用的是合成包；外部 agent 产出的真实 30 题包已在轮次一百四十二验收（见 §26）。
## 26. 真实抓题包验收与「整卡快照包」降级（轮次一百四十二，2026-10-23）

外部抓题专属 agent 在 2026-10-22 交付了第一个真实 `.tqb` 包（30 道物理/数学/化学题）。
这一轮先做验收：包能不能无损导入、渲染层会不会把「整卡截图 + ［图N］占位」的题库渲染成
一堆裸露占位符。结论是**导入无损、渲染必须降级**——整卡快照包的题干正文不该内联整张截图。

### 26.1 真实包画像（`E:/FirsryOS/THREADRIPPER/zujuan-harvest/harvest/out/furnace-zujuan-2026-10-22T16-03-02.tqb`）

- 19,444,730 B；manifest：`format=furnace-question-bank`、`version=1`、`app_version=0.5.9+18`、
  `generated_by=zujuan-harvest/1.0`、`exported_at=2026-10-22T16:03:20.815Z`、`question_count=30`、
  `media_count=60`；记录与媒体键完全对齐（再编码 18,130,177 B，30 题/60 媒体）。
- 学科：物理 10 / 数学 10 / 化学 10；来源档位全部 `gaokao`；题型 `solution` 24、`multi_choice` 4、
  `single_choice` 2；`origin=manual`、`state=structured`、`tag_paths=[]`、`serial_no` 未填。
- 来源字段：`source_url` / `zujuan_question_id` / `zujuan_bank_id` 30 题齐全，`year` 30、`region` 23、
  `difficulty` 30；按 id 重建详情链接与 `source_url` 不一致 0 条。
- 答案与解析：文字 0 条（答案全部是**截图**：30 张 JPEG，16 竖 14 横）；选项：24 题没有选项、
  6 题各有 4 个选项且 `is_correct` 全 false。
- 题干：长度 55…768（平均 321）字符；`$` 定界符奇偶全部配对；「［图N］」占位共 **451 处**；
  每题恰好 **1 张题干图**（PNG，全部宽 1640，高 400…3046）；重复题干 0 条。
- 判定：**28 道题**「1 张题干图 + ≥2 处占位」= 整卡快照包；另外 2 道只有 1 处占位。
  实测题干图尺寸全部 ≥1640×400 → 渲染计划的尺寸规则（§26.3 B1）对 **30 道题全部** 判为 snapshot，
  覆盖了「只有 1 处占位」的两道。

### 26.2 探针工具（`app/tool/question_pack_probe.dart`，本轮入库）

- 纯 Dart 只读工具，不碰数据库、不写包：`dart run tool/question_pack_probe.dart <包.tqb> [报告.json]`。
  输出题目/学科/来源/占位/题干图/答案图/字节/清单一致性等统计并给出 alerts。
- 本轮修了一个真实 bug：`stemImageTotal` 从未累加导致「题干图 0 张」误报。新增
  `records_snapshot_like`（占位次数 ≥2 且题干图 1 张）与 alert「整卡快照包：详情页应把这张图当原题
  整图，不要内联」，原「占位溢出」alert 改为扣除快照记录后的差值提示。
- 真实包报告：`E:/dsh-tmp-aot/probe-real-tqb-1603.json`（alerts 3 条：快照 28 / 答案都是截图 / 24 题没选项）。

### 26.3 题干图片渲染计划（新增纯逻辑，task-131）

- 新文件 `app/lib/domain/services/questions/question_stem_image_plan.dart`（343 行，只 import
  `question_stem_segments.dart`）：`enum QuestionStemImageMode { none, inline, snapshot }`；
  `class QuestionStemImageSize { const QuestionStemImageSize(this.width, this.height); }`；
  `class QuestionStemRenderPlan`（`mode` / `segments` / `trailingImageOrders` / `snapshotImageOrders` /
  `imageCount` / `placeholderCount` / `referencedImageCount` / `neutralizedPlaceholderCount` + 4 个
  getter，列表不可变、`==` 深比较）；
  `QuestionStemRenderPlan planQuestionStemRender(String stem, {required int imageCount,
  List<QuestionStemImageSize?> imageSizes = const <QuestionStemImageSize?>[],
  int snapshotMinWidth = defaultStemSnapshotMinWidth, int snapshotMinHeight = defaultStemSnapshotMinHeight})`。
- 规则：**A** 无图 → none（原文不改写）；**B1** 任一已知尺寸宽 ≥1000 且高 ≥400 → snapshot；
  **B2** 尺寸全未知且 1 张图且占位 ≥2 处 → snapshot（数量兜底）；**C** 否则 inline，复用
  `splitQuestionStemImages`，越界占位中性化成「…」，没被引用的图按升序进 trailing。
- snapshot 模式：正文里每个占位替换成一个「…」（相邻文字段合并），`trailingImageOrders` = 全部题干图
  （整卡截图渲染在正文末尾），`referencedImageCount=0`；不抛异常、无 IO/随机数。
- 契约没写死的 5 个边界已写在文件 doc 里：空题干各模式段数差异、`referencedImageCount` 仅 inline 非 0、
  `placeholderCount` 与模式无关、B2 的「尺寸全为空」按字面（有任何非 null 项就不走 B2）、阈值不夹取。
- 测试：`app/test/domain/services/questions/question_stem_image_plan_test.dart`（594 行、5 组 40 例），
  覆盖 12 处占位整卡、混合尺寸、1000×400 边界与 999×399、B2 触发/不触发、越界中性化、全角数字、
  列表不可变与值语义。实跑 `+40 All tests passed`。

### 26.4 详情页接线（task-133，`question_detail_page.dart`）

- `_QuestionStemView`（:427 起）：`questionImagesProvider` 拿题干图，逐图 `questionImageBytesProvider`
  → `readImageSize(bytes)`（`app/lib/data/media/image_size.dart`，只读文件头）→ `QuestionStemImageSize?`
  （bytes 未到 / 解析失败填 null），再 `planQuestionStemRender(stem, imageCount: images.length,
  `imageSizes: ...)`。
- 渲染：`plan.segments` 按 text/image 段顺序输出（文字段 `QuestionRichText`、图段沿用原内联大图组件）；
  `plan.trailingImageOrders` 在正文后按序输出大图；`plan.isSnapshot` 时在尾图第一张前显示小标题
  `questionDetailOriginalCardImage`（zh「原题整图」/ en「Original question image」）。inline 模式与改造前
  逐段一致；个别图字节没回来不抛（plan 尺寸填 null，缺 bytes 的图跳过）。
- 效果：整卡快照包的正文从「数处 ［图N］ + 一张内联截图」变成「正文省略号 + 末尾一张原题整图」。
- l10n：五个文件手改、未跑 gen-l10n，仅新增 1 个无占位 key（`questionDetailOriginalCardImage`）。
- 测试：`question_detail_page_test.dart` +5 例（12 占位整卡→尾图+标题；2 张 400×300 内联且 y 序；
  单小图内联；单 1640×808 快照；有占位无图不崩）。`test/features/questions/presentation` → **+388**
  （基线 383，+5，无回归）。

### 26.5 导入预检识别整卡快照包（task-132，`question_pack_import_preview.dart`）

- `QuestionPackImportPreview` 新增 `snapshotLikeCount`（`toJson` 新键 `snapshot_like_count`，紧跟
  `missing_tag_count`）；判定与 §26.2 的探针同口径（占位 ≥2 次且 `role='stem'` 媒体恰好 1 张），
  占位正则与 `question_stem_segments.dart` 一致（全角/半角方括号与【】、全角数字、1~3 位）。
- warnings 顺序：清单题数不符 → 清单媒体数不符 → 快照告警 → `plan.warnings`（同文案去重）；
  `summaryZh` 命中时多一行「整卡快照：N 道题（公式在整图里）」（包内容行之后、新增/跳过行之前）。
- 测试：既有 34 例零回归 + 新增 15 例（`question_pack_import_preview_test.dart` 506→744 行）；
  `test/domain/services/package` → **+285** 全绿。真实包 `planImport` 实测 warning 文案：
  「这个包是整卡快照包：28 道题的题干只有一张整题截图，公式以「［图N］」占位显示；详情页会按原题整图展示。」
### 26.6 门禁与未做（轮次一百四十二）

- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与轮次一百四十一起同一基线，本轮没有新增问题）。
- 全量 `flutter test --concurrency=1` → **+5394 ~2 All tests passed**，11 分 18 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-142-full.txt`；上一轮基线 +5334，本轮 +60 = 计划 40 + 预检 15 + 详情页 5）。
- 切片：`question_stem_image_plan_test` +40、`test/domain/services/package` +285（含新增 15）、
  `test/features/questions/presentation` +388（基线 383）、`question_pack_import_preview_test` 单文件 +49。
  只 format 本轮改动文件（0 changed；`app_localizations_en.dart` 生成文件补 format 1 次后稳定）。
- 真实包导入验收（临时测试，跑完已删除；日志 `E:/dsh-tmp-aot/test-142-real-import.txt`）：
  `import_ms=839`、`export_ms=2255`、created 30 / skipped 0 / media 60 / warnings 0 / failures 0；
  题号 `1..30`；`untitled=30`（抓题包不带题名，可自动命名）；题干图 30 张全部宽 1640；
  答案图 16 竖 / 14 横；`export_bytes=18,128,543`；`preview_warnings=1`（即 §26.5 的快照告警文案）。
  另有单条真实结论：**30 道题的题干图最小高度正好 400**，尺寸规则 B1 的 `>=400` 把它们全部覆盖。
- 未做 / 未验证：真机（Windows / Android）上的大图渲染与性能未手测；44 处占位极限包与「大小图混合」
  包未单独断言；单图 + ≥2 占位、图字节尚未回来时 B2 会先判快照、字节到达后若尺寸小会翻回 inline
  （plan 契约如此，多图小图不受影响）；**docx 导出**对整卡快照包仍按原逻辑把题干原文（带 ［图N］）
  与截图当随文图导出，未做快照专用排版；题库总览/相似题/AI 读题工具仍显示原始占位文本；
  真实 30 题包尚未在 App 真机上手工导入点一遍。

## 27. 整卡快照包的三处降级显示：docx / AI 读题 / 题库列表（轮次一百四十三，2026-10-23）

轮次一百四十二把「整卡快照包」在详情页做对了（正文省略号 + 末尾原题整图），但另外三处仍在显示原始占位：
**Word 导出**把「［图N］」和整题截图当随文图排版；**AI 读题工具**只报 `image_count`，模型不知道题干只是
截图；**题库列表**标题是「…… ［图12］ ……」的碎片。本轮把这三处一起降到可读形态，判定统一复用轮次
一百四十二的渲染计划，不新增第二套阈值。

### 27.1 题干快照摘要（纯逻辑，task-135 reasoning-core）

- 新文件 `app/lib/domain/services/questions/question_snapshot_summary.dart`（222 行）：
  `class QuestionSnapshotSummary`（`isSnapshot` / `placeholderCount` / `imageCount` /
  `neutralizedStem` / `labelZh` / `textExcerpt` / `hasTextExcerpt` / `isEmpty`）；
  `summarizeQuestionStemSnapshot({required String stem, required int stemImageCount,
  List<QuestionStemImageSize?> imageSizes = const [], int excerptMaxLength = 60})`；
  `const kQuestionSnapshotExcerptMaxLength = 60`。
- 判定直接复用 `planQuestionStemRender`（B1 真实尺寸大图 / B2 尺寸未知 + 1 图 + 占位≥2），不重复实现。
  快照时：`neutralizedStem` = 按序拼文字段（占位已变「…」）；`labelZh` = `整题截图 · N 处公式/图`
  （无占位时 `整题截图`）；`textExcerpt` = 原 stem 删占位 → 折叠空白 → 连续省略号压一个 → 剥首尾
  标点 → runes 截 60（截断后不足 4 runes 视为没有摘录）。非快照时 `labelZh` 空、`textExcerpt` 走
  `questionStemPreview`，摘要不参与任何判定。
- 已知口径差异：快照摘录**保留 `$` 定界符**（与非快照 `questionStemPreview` 去定界符不同），
  因为摘录要如实反映正文；占位正则在 `question_stem_segments.dart` / `question_stem_preview.dart` /
  本文件各有一份私有实现，改规则需三处同步（三份都已被各自测试钉住）。
- 测试：`app/test/domain/services/questions/question_snapshot_summary_test.dart`（375 行、5 组 34 例）：
  快照判定 B1/B2、`neutralizedStem` 段落拼接、label 文案、摘录清洗/截断/不足 4 字、非快照等价
  `stemPreview`、退化输入不抛。实跑 `+34 All tests passed`。

### 27.2 Word 导出：正文降级 + 原题整图（task-137 Lead）

- `app/lib/domain/services/export/paper_docx.dart`（+63 行）：`PaperDocxQuestion.stemIsSnapshot`
  （默认 false，旧调用逐字节不变）；`PaperDocxLabels.snapshotStemNote`（默认「（本题题干是整题截图，
  正文只保留可读文字，原题见下方整图）」）与 `snapshotImageLabel`（默认「原题整图」）；
  `PaperDocxBuildResult.snapshotStemCount`。`_addStem` 在题干后追加一行 9pt 灰 meta 小字
  （keepNext）；`_addImages` 在快照且图片非空时先加「原题整图」小标题（9pt 灰加粗、keepNext）。
  空题干也走提示分支，计数不丢。
- 应用层 `app/lib/features/questions/application/paper_docx_export.dart`：新增私有
  `_paperDocxQuestionFor`，把该题题干图的**真实像素尺寸**（`readImageInfo` 已给出）组
  `List<QuestionStemImageSize?>` 调 `summarizeQuestionStemSnapshot`；快照时 `stem` 换成
  `neutralizedStem`、`stemIsSnapshot: true`。`question_corpus_reader.dart` 的
  `QuestionDocxRow.toPaperDocxQuestion` 加 `String? stemOverride, bool stemIsSnapshot = false` 透传。
- 测试：`paper_docx_test.dart` 新增 5 例（提示在「原题整图」前、小标题在 `<w:drawing` 前、
  非快照不出提示、空题干计数、无图不出标题、英文 labels）→ 该文件 `+59`；
  `paper_docx_export_test.dart` 新增 2 例（1640×808 整图 + 12 处占位 → `snapshotStemCount=1`、
  xml 含提示/原题整图、不含 `［图`、图入 zip；两张 400×240 + 2 占位 → 非快照两图都入 zip）→
  该文件 `+26`。注意 docx 图片的 note 只进 `imagePlacements`，断言图位置要用 `<w:drawing`。
- **真实包 Word 验收**（临时测试 + Word COM，脚本与产物在 `E:/dsh-tmp-aot/snapshot-docx/`）：
  导入真实 30 题包（created 30 / media 60），取前 3 道（全部快照）组卷导出：
  `bytes=2,766,181`、`snapshotStemCount=3`、`stemImages=3`、`answerShots=3`、`imageNotes=0`；
  Word 打开 `OPEN_MS=2178`、**5 页**、1746 字、6 个 InlineShapes、含「整题截图」与「原题整图」、
  **不含原始「［图1］」**、含「参考答案与解析」、PDF `530,767 B`。探针未注入 LaTeX→OMML 编译器，
  所以该样张 `OMath=0`（生产界面会注入，见轮次一百二十二）。

### 27.3 AI 读题工具标注快照题（task-136 threadflow-engine）

- `app/lib/features/ai/tools/question_tools.dart`（+53/−3）：新增顶层 `_snapshotClauseOf`；
  `read_question` 在附件分桶后按既有 `image_count` 口径（role NULL/空/stem）算快照，
  `modelResult` 末尾新增两个键——`stem_is_snapshot`（bool，**恒出现**）与
  `stem_snapshot_label`（非快照为空串，键也恒出现，schema 稳定）；摘要固定尾句前插
  「；题干是整题截图（N 处公式/图），正文可能只是占位，原题看图片」。`read_questions_by_serials`
  逐条同样两键，摘要多「其中 K 道题题干是整题截图。」（K=0 不出现）。description/参数 schema、
  `previewStem`、只读性均未改。
- 工具层只拿得到题干图**数量**、没有像素尺寸，所以只命中 **B2**（1 图 + 占位≥2）；B1 大图在工具层
  不会命中——偏保守、不误报。以后附件能提供尺寸时把 `imageSizes` 传进来即可覆盖 B1。
- 测试：`read_question_tool_test.dart` +4 例、`read_questions_by_serials_tool_test.dart` +3 例
  （快照/非快照/1 图 1 占位/2 图 2 占位、混合批摘要计数、无快照摘要不提）；两文件 `+43`，
  `test/features/ai` 目录 `+587` 零回归。

### 27.4 题库总览：快照字段 + badge + 可读标题（task-138 Lead / task-139 question-intake）

- 读表 `app/lib/features/questions/application/question_library_reader.dart`：
  `QuestionLibraryEntry` 新增 `isSnapshotStem` / `snapshotLabel` / `snapshotExcerpt`；
  读表时每题用题干图张数调 `summarizeQuestionStemSnapshot`（**不传尺寸 → 只走 B2**，列表不为判定
  去读图片字节）。`displayTitle` 优先序改为：用户题名 → 快照可读摘录 → 快照标签 → `stemPreview`
  →「（无题干）」；非快照题的 `snapshotExcerpt` 恒为 null（否则普通题会多出一个「摘录」字段）。
- 列表 `question_bank_page.dart`（+19/−11）：标题行统一 `entry.displayTitle`（有题名 titleMedium/w600、
  最多 2 行；否则 bodyMedium/onSurfaceVariant、1 行）；题号行在学科后加 badge
  `l10n.questionBankSnapshotBadge`（zh「整题截图」/en「Card image」，纯 Text 无卡片底座）。
  badge 条件 = `isSnapshotStem && (有可读摘录 || 有用户题名)`——**标题已经回落成「整题截图 · N 处
  公式/图」时不重复显示 badge**，避免同一行两个「整题截图」。
- l10n 仅新增 1 个无参 key，五文件手改、未跑 gen-l10n（zh keys=1668 / en keys=1699，ARB JSON 可解析、
  无字面花括号）。
- 测试：reader `question_library_reader_test.dart` +4 例（1 图 3 占位→快照/标签/摘录标题、
  1 图 1 占位→非快照、2 图 2 占位→非快照、有题名时题名优先），该文件 `+17`；
  `question_bank_page_test.dart` +3 例（有摘录→badge + 摘录标题、无摘录→标题即标签且无 badge、
  普通题无 badge），`test/features/questions/presentation` `+391`（基线 388，+3，无回归）。

### 27.5 门禁与未做（轮次一百四十三）

- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与轮次一百四十一起同一基线，无新增）。
- 全量 `flutter test --concurrency=1` → **+5449 ~2 All tests passed**，10 分 56 秒，EXIT=0（日志 `E:/dsh-tmp-aot/test-143-full.txt`；上轮 +5394，本轮 +55）。
- 切片：`test/domain/services/export test/domain/services/questions test/features/questions/application
  test/features/ai` 组合 → **+1695 All tests passed**（含本轮 34+5+2+4+3+4 例与全部既有用例）。
- 未做 / 未验证：真机 Windows / Android 上「正文 + 整题截图」的版面与新 badge 的长中文换行未手测；
  44 处占位极限包未单独验证；题库列表判定只有 B2（不读图片尺寸），真实库里「题目有图但 attachments
  行缺失」时不会出 badge；AI 工具同样只有 B2；`questionBankUntitled` 这个 l10n key 在列表改造后已无
  业务引用（保留未删，删 key 涉及五文件生成物）；空题干题的列表标题从「题干没读到」变成
  reader 的「（无题干）」（DB 里 stem 必填，真实数据概率低但未抽样验证）。

## 28. 其余「只有题干」的列表：快照感知的一行文本（轮次一百四十四，2026-10-23）

轮次一百四十三把整卡快照包在**题库总览 / 详情页 / Word 导出 / AI 读题**四处做对了，但还有四个界面
只有题干字符串：**组卷候选（手动名单 / 领域配额 / 学科配额）**、**详情页相似题**、**能力动作题列表**、
**收题页题库列表**。它们此前直接显示原始题干，整卡快照包在这些地方就是「…… ［图12］ ……」的碎片，
普通题的 `$…$` 公式也原样露美元符。本轮把这四处统一接到同一个纯函数上，判定仍复用轮次一百四十二的
渲染计划，不新增第二套阈值。

### 28.1 列表显示文本纯逻辑（task-140 reasoning-core）

- 新文件 `app/lib/domain/services/questions/question_stem_display.dart`（127 行，纯 Dart）：
  `class QuestionStemDisplay { text / label / isSnapshot / hasExcerpt / imageCount / placeholderCount /
  isEmpty / == / hashCode / toString }`；
  `QuestionStemDisplay resolveQuestionStemDisplay({required String stem, required int imageCount,
  int maxLength = kQuestionStemPreviewMaxLength})`。
- 口径：内部只调 `summarizeQuestionStemSnapshot(stem:, stemImageCount:, excerptMaxLength:)`，
  **不传 imageSizes → 列表只走 B2**（1 图 + 占位≥2），不为一行文本去读图片字节。快照题
  `text = hasExcerpt ? textExcerpt : labelZh`（纯占位题不会在列表留下半行省略号）；普通题
  `text = questionStemPreview(stem, maxLength:)`、`label = ''`；`imageCount < 0` 归一为 0；
  `maxLength <= 0` 不崩；永不抛异常。
- 测试：`app/test/domain/services/questions/question_stem_display_test.dart`（308 行、4 组 32 例：快照 B2、
  普通题、边界与不抛、值语义）；`test/domain/services/questions` 目录 **+581 全绿**（基线 549，无回归）。

### 28.2 读表 + provider（task-141 Lead）

- 新文件 `app/lib/features/questions/application/question_stem_display_reader.dart`（77 行，纯读表、
  不 import `dart:io`）：`Future<Map<String, QuestionStemDisplay>> readQuestionStemDisplays(AppDatabase db,
  {Set<String>? questionIds, int maxLength = 60})`。题目行查 questions（id + stem，`questionIds` trim
  后过滤、空集返回空 map、未知 id 安静忽略）；题干图张数用 drift `selectOnly(attachments)` +
  `addColumns([ownerId, count])` + `groupBy([ownerId])`，条件 `ownerType = 'question'` 且
  `role IS NULL OR role = 'stem'`——答案/解析截图不参与快照判定，v27 前 role 为 NULL 的旧行照旧算题干图。
- 新文件 `question_stem_display_provider.dart`（25 行）：`questionStemDisplayProvider`
  （`FutureProvider.autoDispose<Map<String, QuestionStemDisplay>>`，`watchDatabaseRevision` + 上面的读表，
  与 `paper_plan_provider.dart` 的 `questionStemsProvider` 同一写法）。
- 测试：`app/test/features/questions/application/question_stem_display_reader_test.dart`（156 行、11 例：
  空库 / 普通题 preview / 1 图 2 占位 B2 快照 + 摘录 / 纯占位无摘录用标签 / 答案截图不计 /
  role=NULL 计入 / 其它 ownerType 不计 / questionIds 过滤与空集 / maxLength 透传 / 多题互不影响 /
  空题干不抛）。实跑 `+11 All tests passed`，scoped analyze No issues。

### 28.3 组卷页三个 view 接上 display（task-142 threadflow-engine）

- `paper_manual_selection_view.dart`：`questionStemsProvider` **仍只喂** `paperManualFilterCandidates`
  过滤（不换成 display.text，避免只搜前 60 rune 造成召回变化）；名单卡 / 候选对话框 / 结果卡三类名单
  行改接 `questionStemDisplayProvider`，每行文本由 `_stemTextOf` 取 `display.text`，未就绪回退题号；
  `isSnapshot && hasExcerpt` 时在文本后摆 `l10n.questionBankSnapshotBadge` 小标签（无摘录时 text 本身
  已是「整题截图 · N 处公式/图」，不叠第二个「整题截图」）。
- `paper_domain_quota_view.dart` / `paper_subject_quota_view.dart`：同构接线；被挡行从单个 `Text` 改
  `Row(Expanded(文案) + 条件徽标)`；`_blockedDescription` 改收 `Map<String, QuestionStemDisplay>`，
  空文本回退题号。三个 `paper*StemPreview` 函数定义保留，只作用在 display.text 上。
- 注意：三个 view 各自复制了一份私有 `_watchStemDisplays` / `_showsSnapshotBadge` / `_snapshotBadge`
  helper（各自写作用域内无共享文件）；要合并成公共 widget 需另开任务。
- 测试：三个既有测试文件各 +3 / +2 / +2 例（`_seedStemAttachment` 插 role='stem' 的 attachments 行造
  B2 快照；钉住「有摘录摆徽标 / 无摘录不叠」两种）；`test/features/questions/presentation` **+405 全绿**
  （基线 391；本轮两片合计 +14）。

### 28.4 相似题 / 能力动作题 / 收题页列表（task-143 question-intake）

- `question_detail_page.dart`（+37/−11）：`_SimilarQuestionTile` 不再 watch `questionDetailProvider`，改
  watch `questionStemDisplayProvider`；加载中（无 value）显示 '…'，无该 id / 空文本回落
  `questionDetailQuestionMissing`，否则 `display.text`；标题 `Row` 末尾仅 `isSnapshot && hasExcerpt`
  时摆快照 badge。
- `capability_action_questions_page.dart`（+17/−3）：父级 `ConsumerState` 取一次 display map 传参，
  `_QuestionRow` 保持 StatelessWidget（新增 `QuestionStemDisplay? display`），为空时回退 `row.stem`
  （不空白）。
- `question_intake_page.dart`（+16/−1）：`_IntakeLibrarySection` 取 display map，题库列表标题走
  `_libraryStemText`（display 空回退 `entry.question.stem`）；副标题/删除/缩略图未动。
- 测试：三个测试文件合计 +7 例（快照摘录不露［图、无摘录退成标签、普通题原文无 badge；详情页另覆盖
  相似题 badge 出现一次）。l10n 未新增 key（复用 `questionBankSnapshotBadge`）。

### 28.5 门禁与未做（轮次一百四十四）

- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与轮次一百四十一起同一基线，无新增）。
- 全量 `flutter test --concurrency=1` → **+5506 ~2 All tests passed**，11 分 04 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-144-full.txt`；上一轮基线 +5449，本轮 +57 = 32+11+7+7）。
- 切片：`test/domain/services/questions` **+581**（基线 549，+32）、`question_stem_display_reader_test`
  **+11**、`test/features/questions/presentation` **+405**（基线 391，+14）。
- 未做 / 未验证：真机（Windows / Android）未手测这三个组卷 view 的徽标换行与收题页列表；provider 在
  **数据版本变化后的重读**只靠 `watchDatabaseRevision`，本轮未单测；快照摘录**保留字面 `$` 定界符**
  （域层既有口径，列表显示 `$x^2$` 而不是渲染后的公式）；无摘录标签是域层硬编码中文，en 界面仍显中文；
  provider 未就绪时先显示原文（含 ［图N］）有极短闪烁，未做骨架屏；组卷三 view 的重复 helper 未合并。

## 29. 题库包再导入：按组卷网题号更新已有题目（轮次一百四十五，2026-10-23）

### 29.1 合并计划：新增 update 动作（task-144 reasoning-core）

- `question_pack_plan.dart`（327 → 439 行）：`QuestionPackAction.update`（`labelZh`「更新」）；
  `QuestionPackDecision.existingQuestionId`（`toJson` 仅非 null 输出 `existing_question_id`，`==` 带上）；
  顶层 `String? questionPackSourceKey({required String? zujuanQuestionId})`（trim 后空 -> null；
  **只按题号认题**，bankId 只用于重建链接）；`planQuestionPackImport` 增
  `existingQuestionIdByZujuanQuestionId`（默认空 map）与 `updateExisting`（默认 true）；
  `QuestionPackImportPlan.updateCount` / `updatedIndexes` / `toJson.update_count`；
  `skipCount = decisions.length - createCount - updateCount`（update **不占**跳过数）。
- 判定顺序：**update（题号首次出现且映射命中）-> 题库指纹跳过 -> 包内同题号跳过+warning
  -> 包内同指纹跳过 -> create**。两处显式细化：同一题号在包内第二次出现不再 update（落到
  跳过分支，避免同一道题被计划更新两次）；update 记录也登记指纹，后面的同题干记录按包内指纹跳过。
- `updateExisting: false` 完全不认题号（既不 update 也不做包内题号去重），输出与升级前逐字段一致
  （有测试直接比较 `toJson`/warnings/missingTagPaths）。
- 测试 `question_pack_plan_test.dart` 721 → 1327 行，**94 例**（旧 53 保留适配 + 新 41）。

### 29.2 数据层原语（task-145 threadflow-engine）

- `question_repository.dart` 新增 `updateFromPack`（:582 起）：补丁语义——字符串 null/trim 空白
  = 不覆盖、非空 = trim 后覆盖；题干总是覆盖并重算 `stemFingerprint`（trim 空抛
  `ArgumentError`）；`options` 非空 = 事务内删旧插新、空列表 = 保留；`additionalTagIds` 只
  `insertOrIgnore` 补挂、不删旧标签；`title`/`serialNo`/`createdAt` 不动，`updatedAt = now`；
  单事务，题目不存在返回 0 不抛。
- 新增 `questionIdsByZujuanQuestionId()`（:720）：跳过 trim 空题号，同 key 多行按
  `updatedAt` 降序、id 升序取第一行。
- `question_media_store.dart` 的 `deleteForQuestion`（:263）增可选 `roles`：`null` = 旧行为删全部；
  空集合返回 0；`'stem'` 连带匹配 `role IS NULL` 的旧行；其它角色精确匹配；集合内空白折成 stem。
- 测试：`question_repository_pack_update_test.dart` 12 例 + media store 追加 5 例（17 -> 22）。

### 29.3 服务层接线（Lead task-146）

- `QuestionPackService.planImport` 与 `importPack` 都先查 `questionIdsByZujuanQuestionId()`，把
  「题号 -> 题目 id」映射传进 `planQuestionPackImport`（预检与实际导入必须同一入口，否则会出现
  「预检说更新、实际却新建」）。
- `importPack` 对 `action == update` 的决策调 `updateFromPack`：只传**包里非空**的字段（不能用
  `_draftOf` 的 create 默认值 `questionType='solution'` / `sourceLevel='unknown'` /
  `origin='manual'` / `state='structured'` 去刷掉用户已有值）；返回 0 记进 failures、不计数；
  成功后按「包里实际出现过的角色集合」`deleteForQuestion(roles:)` 再复用
  `_saveMediaFor` 落图（包里没有配图 -> 一张都不删），单张保存失败只记 warning。
- `QuestionPackImportReport.updatedCount` 新增（构造默认 0，旧测试/fakes 不用改）；preview 新增
  `updateCount` / `hasUpdates`，`isFullyNew` 改为三数都为零才算，`summaryZh` 第 3 行改
  「新增 / 更新 / 跳过」合并行，`toJson` 加 `update_count`。
- 新测试 `question_pack_update_test.dart` **9 例**：同包导两次第二次 0 新建/3 更新且题号不变、
  答案与解析文字覆盖、只带答案图时题干图保留答案图替换、无配图不删图、题名与题号不覆盖、
  无题号仍按指纹跳过、`planImport.updateCount` 与实际一致、选项非空整体替换/空保留、
  标签只补不删。

### 29.4 真实抓题包验收（本机临时测试，已删除测试文件）

- 包：`E:/FirsryOS/THREADRIPPER/zujuan-harvest/harvest/out/furnace-zujuan-2026-10-22T16-03-02.tqb`
  （19,444,730 B；30 题 / 60 媒体；`zujuan_question_id` 与 `zujuan_bank_id` **30/30 全非空**，
  所以真实包能走「按题号更新」而不是退回指纹跳过）。
- 第一次 `importPack`：created=30 / updated=0 / skipped=0 / media=60 / warnings=0 / failures=0，836 ms。
- 第二次 `planImport`：update=30 / create=0 / skip=0 / warnings=1（整卡快照包提示）。
- 第二次 `importPack`：created=0 / **updated=30** / skipped=0 / media=60 / warnings=0 / failures=0，
  678 ms；两轮后题库仍是 30 行、题号不变、用户改过的题名保留、题干图与答案图张数不变。

### 29.5 设置页提示与全量门禁（task-147 + Lead 收尾）

- 设置页 `data_section.dart` 的题库包分区：类 doc 改成「无题号追加、带题号原地更新，题号与
  用户题名保留」；预检对话框在 `preview.updateCount > 0` 时加一行「会更新 N 道题库里已有的
  组卷网原题（题号与你起的题名保留）」；「没有可导入的新题」改为
  `createCount == 0 && updateCount == 0` 才显示；确认说明在 `preview.hasUpdates` 时追加
  「更新会覆盖题干 / 答案 / 解析与配图中包里出现过的内容」；结果对话框
  `report.updatedCount > 0` 时显示「更新 N 道」。
- l10n 新增 3 个 key：`settingsQuestionPackPreviewUpdate(count:int)`、
  `settingsQuestionPackImportUpdated(count:int)`、`settingsQuestionPackImportUpdateNote`
  （五文件手改，未跑 gen-l10n）；同时修正既有 `settingsQuestionPackImportConfirm` 的
  「只会新增题目，不覆盖已有题」——有更新时这句与事实矛盾，改成「新增的题不会覆盖已有题」，
  覆盖范围由 UpdateNote 单独说明。
- 测试替身：`FakeQuestionMediaStore`（`question_media_fakes.dart`）与 `_RecordingMediaStore`
  （`question_intake_page_test.dart`）补齐 `deleteForQuestion(roles:)` 新签名；替身支持
  roles 过滤与「空集合删 0 张」语义。**全量 analyze 才抓得到 test 里的 invalid_override**。
- 抓题包往返测试改期望（`question_pack_harvest_roundtrip_test.dart`）：第二次导入同一包，
  第一条带题号 → `updatedCount = 1`，第二条无题号 → `skippedCount = 1`；`planImport` 预检与
  实际口径一致（`updateCount = 1` / `skipCount = 1`），题目 id、题号、选项与配图数量不变。
- 门禁：`dart analyze lib test` → **91 issues / 0 error / 0 warning**；全量
  `flutter test --concurrency=1` → **+5580 ~2，10:38**；相关 scoped 测试：plan 94 例、
  预检 +155（preview/plan/update 三文件）、设置 82 例、抓题包往返 10 例；`dart format` 全绿。

## 30. 待整理队列批量整理与题库筛选全库（轮次一百四十七，2026-10-23）

本轮三片并行：①拍照整理队列「整理全部」（task-148 question-intake）②按能力动作找题的学科筛选
由单选改多选（task-149 reasoning-core，口径见 `docs/REASONING_LAYER_DESIGN.md` §33）③题库页
筛选生效时读全库（task-151 threadflow-engine）。三片都只动自己的写作用域，Lead 统一审查、补文档、
跑全量门禁与提交。

### 30.1 待整理队列「整理全部」（task-148 question-intake）

- **背景**：`docs/HANDWRITING_INTAKE_DESIGN.md:144` 记「一次只整理一张照片」，而收题页拖拽入口
  可以一次放多张（轮次一百二十一）——批量进队列后仍要逐张点「整理」，微信聊天记录一次拖十张就要
  点十次。本片补「整理全部」，模型调用仍是**逐张串行**（run 身份仍是单图 source_ref，不改存储格式）。
- **汇总值对象**：`app/lib/features/questions/application/handwriting_proposal_service.dart` 的
  `HandwritingBatchReport`（:198）：`total` / `succeeded` / `failed` / `skipped` / `stopped`，
  `processed => succeeded + failed`、`isEmpty`、`toJson`。
- **状态**：`HandwritingQueueState` 增 `batchRunning` / `batchStopping` / `batchTotal` /
  `batchCurrent` / `batchDone` / `lastBatchReport`（构造 :724，字段 :766，copyWith :802）；
  批次状态放 notifier 而不是页面，离开队列页后批次照跑。
- **候选**：`batchCandidates`（:775）= 不在 `sets`、不在 `failures`、不在 `analyzing` 的照片，
  按清单顺序；`batchCandidateCount`（:785）就是按钮上的 N。已经整理过/已经失败的照片不再花
  模型调用。
- **`analyzeAll()`**（:926）：已有批次在跑时直接返回 `null`（防重入）；开始时对候选**拍快照**；
  逐张 `await analyze(relPath)`，单张失败只进 `failures`、不中断；循环里再查一次 `sets` /
  `failures`（排队期间用户自己整理了这张）→ 计入 skipped 不重复调用；结束写
  `lastBatchReport`，`batchDone = processed`。
- **`stopBatch()`**（:997）：只置停止标志，**当前这张整理完后**不再发起下一张；还没轮到的照片
  不发起、不计数，汇总里 `stopped = true`，页面另起一行说明。已完成/已失败的结果照实保留。
- **页面** `handwriting_queue_page.dart`：三个 Key（:40/:43/:46）；`_BatchBar`（:232）插在照片
  清单上方（:127）。按钮 `handwritingBatchAnalyzeAllKey` 显示「整理全部（N 张待整理）」，候选
  0 或批次运行中禁用；运行中显示「正在整理 i/N」+ `LinearProgressIndicator` +「停止」按钮
  （按下后变「正在停止…」并禁用）；结束后 `handwritingBatchSummaryKey` 显示汇总，stopped 时追加
  一行。
- **l10n**：6 个 key 五文件手改（未跑 gen-l10n，全 LF）——`handwritingQueueBatchAll(count:int)` /
  `BatchProgress(current:int,total:int)` / `BatchStop` / `BatchStopping` /
  `BatchReport(succeeded:int,failed:int,skipped:int)` / `BatchStopped`；中文文案
  「整理全部（{count} 张待整理）」「正在整理 {current}/{total}」「成功 {succeeded} 张、
  失败 {failed} 张、跳过 {skipped} 张」「已停止，剩下的照片没有整理」。
- **测试**：`handwriting_proposal_service_test.dart` 33 → **38 例**（新增「整理全部」group：顺序
  调用、失败隔离、已整理跳过、停止后不再发起、汇总口径）；`handwriting_queue_page_test.dart`
  15 → **17 例**（按钮显示待整理张数、运行中进度与停止）。presentation 目录 **+408** 全绿。
- **未做 / 风险**：Windows 真机批量+停止交互未手测；「离开页面再回来继续跑」只有 notifier 层
  保证、无 widget 测试；批次运行中新增/删除照片未测；逐张串行在 10+ 张时耗时较长（无并发、无
  失败重试）；停止语义是「当前张做完」，不是立即取消进行中的模型调用。

### 30.2 题库页筛选全库（task-151 threadflow-engine）

- **背景**：`docs/QUESTION_BANK_DESIGN.md` §25「未做」记的「筛选在已加载的前 500 道快照上做，
  题库超过 500 道时只筛前 500 道（`snapshot.truncated` 为真）」，是 v0.6.1 发布说明里的已知
  限制。本片让**筛选生效时读全库**，不筛选时仍只读前 500 道。
- **读表口径**：`app/lib/features/questions/application/question_library_provider.dart` 新增
  `kQuestionLibraryOverviewLimit = 500`（:25）与 `questionLibraryReadLimit({required bool filterActive})`
  （:29-30，false→500 / true→0，是两条读表实参的唯一来源）；`questionLibraryOverviewProvider`
  （:40，limit 500）与 `questionLibraryFullProvider`（:50，limit 0）各一档；
  `questionLibrarySnapshotProvider`（:62-67）是 `autoDispose.family<bool>`，按 filterActive
  选档并 `ref.watch(source.future)`，页面只 watch 这一个 provider，切筛选条件时自动换档。
- **页面** `question_bank_page.dart`：`_lastSnapshot`（:143-147）留住上一档最后一帧——换档
  时新 provider 在 loading，没有它整页（含搜索框）会被进度圈顶掉、输入焦点丢失；
  `_invalidateLibrary()`（:212-216）两档一起失效；`_refresh` 等当前档 future；改名/批量自动
  命名/批量打标签/批量删除全部改走双档失效；body 三分支（:619-631）：有缓存→列表、无缓存且
  error→错误页、否则进度圈。
- **改名缺口（Lead 补）**：题目命名对话框原来只失效 `questionLibraryOverviewProvider`
  （`question_title_dialog.dart:162`）——从**题目详情页**改名再返回筛选态题库会看到旧题名。
  Lead 在对话框里补 `ref.invalidate(questionLibraryFullProvider)`，两条改名入口（题库行菜单 /
  详情页笔形按钮）现在都同时失效两档。
- **测试**：新建 `test/features/questions/application/question_library_provider_test.dart`
  **8 例**（false→500 且 `kQuestionLibraryOverviewLimit==500`、true→0；501 题时总览
  entries=500/totalCount=500/truncated=true/无第 501 题；全库档 entries=501/truncated=false/
  含第 501 题且 `QuestionLibraryFilter` 能筛中；family 换档）；`question_bank_filter_test.dart`
  15 → **17 例**（第 600 题筛选命中、清筛选回 500 档且截断横幅恢复；筛选态改名后列表立刻显示
  新题名）。页面三文件（filter/page/bulk）+50 全绿。
- **未做 / 风险**：换档 loading 期间 `_lastSnapshot` 仍是旧档（筛选态首帧可能短暂看到旧档的
  筛后结果）；新档报错时有意继续显示旧数据而不是错误页；500 档滚动性能与全库（数千题）读表
  内存上限未实测；真机换档闪烁未手测；未筛选时的 500 上限与截断横幅行为不变。











