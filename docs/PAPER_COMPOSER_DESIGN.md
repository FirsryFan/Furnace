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
- 调用方（组卷页 UI）还没做：Q10。届时需要把 `question_repository.search` 的行 + 标签桥 + 读数拼成输入。

## 5. 输出契约

`PaperPlan`：
- `items`：`PaperItem{questionId, subjectKey, sourceLevel, questionType, knowledgePointId?, matchedKnowledgePointIds, zone, need, quality, score, reasonZh, improvementNote, backgroundZh}`。
- `uncoveredKnowledgePointIds`：危险/发展区**但题库里一道候选都没有**的知识点 → 这是"该去收题"的清单。
- `deferredKnowledgePointIds`：有候选但这轮没排进来（数量/配额限制）。
- `byKnowledgePoint`：每个知识点实际排了几道（含被第二知识点"顺带覆盖"的）。
- `candidateCount`、`requestedCount`、`isShort`、`overallNeed`、`weights`。
- `toJson()` schema `mindnet.paper_plan/1`，所有 double 过 `DsrMemory.round6`。

## 6. 验收记录（本轮）

- `app/test/domain/services/paper/paper_composer_test.dart` → **16 例全绿**，覆盖：
  来源表同序、危险区压过高来源题、同分比来源、输入顺序无关、显式配额、缺省配额跨点分散、
  缺口上报、被挤掉上报、缺读数当未知且优先于健康、学科/来源过滤、目标难度、理由/提升点/背景
  （含 `trapNote` 与 R0 后缀）、背景回退链（标签路径 → 名字 → id → "未标注知识点"）、
  空库不抛、`toJson`、以及"题目→知识点走 `kQuestionObjectType` 共享标签规则"的跨层一条。
- 全量测试见 `docs/PROGRESS.md` 轮次三十一。
