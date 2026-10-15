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
4. 全部走"待确认任务"清单，用户逐个确认；确认前不写库。

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
| Q13 | 组卷页之外：拍照整理的"三类待确认产物"队列（§7.4） | 待做（未开工） |
| Q14 | AI 工具面：`find_similar_questions`（`0ec1798`）+ `compose_paper`（本轮）——agent 能调用同一套领域逻辑，但**只读、不编题**，读数与页面同源（`library_diagnosis_reader.dart`） | 已完成 |

每片的验收不变：`dart analyze` 0 error / 0 warning；相关单测 + 全量 `flutter test` 绿；
同步本文档与 `docs/PROGRESS.md` / `docs/DATA_MODEL.md`；commit 并由 Lead 统一 push。
