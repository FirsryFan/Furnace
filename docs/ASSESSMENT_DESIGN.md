# 测评层设计（抽象参数 × 板块化 instrument）

> 状态：设计定稿，代码开始落地（轮次二十三起）。
> 上游：用户 2026-10-14 的三条口径——① **自评起步、客观抽检逐步**；② **不从卡片出题，要测"抽象参数"，且物理和语文不能用同一套方法**；③ **同步不做实时，Windows 出一个可发布 release 版本时同步**。
> 相关：[MINDNET_ROADMAP.md](MINDNET_ROADMAP.md)（认知模型切片）、[MINDNET_CONTRACT.md](MINDNET_CONTRACT.md)（参数语义）、[MILESTONES.md](MILESTONES.md)（产品里程碑）、[DATA_MODEL.md](DATA_MODEL.md)。

---

## 0. 这份文档回答什么

三件事，别的不管（UI 细节留给实现轮次）：

1. 认知模型真正消费的**抽象参数**有哪些，现在各自从哪来；
2. 每个参数**能不能用测评直接测**，用什么信号测；
3. 测出来的数**怎么进模型**（先验 + 不确定度，而不是伪装成观测）。

---

## 1. 为什么必须测抽象参数

`app/lib/domain/services/srs/dsr_card_state.dart:6-13` 已经写死了一件事：认知模型的记忆状态就是 `card_states` 的那四列——`encoding_strength`(R0) / `stability`(S) / `savings`(Σ) / `difficulty`(D)。四列**现在只有一种来源：真实复习行为**（`ReviewLogs` → `DsrMemory`）。

后果是两条，都在本会话被实测到：

- **冷启动没有输入**。新用户（或新知识点）在第一次复习之前，R0/S/Σ/D 全是 NULL，模型只能按默认值转，读数页给出的"发展区/危险区"因此没有个体信息。
- **主观量与客观量分不开**。元认知层的 `fluency` 是信念公式的输入（`w_fluency·f`），但 App 里没有 f 的真实来源，实现时只能用 `encodingStrength` 当代理；于是"自信但记不住（危险）"这件事无法真正成立——危险的定义需要"主观流畅 − 客观可提取"两个独立来源，只有一个来源时它必然退化成同一个数。

**测评层的职责**：在复习行为之外，提供 `fluency`（主观）、`R0`/`D`（客观先验）这两类信号的**独立来源**，并显式标注不确定度。

---

## 2. 抽象参数清单

| # | 参数 | 符号 | 模型里的位置 | 现状来源 | 测评能否直接测 | 首版怎么给 |
|---|---|---|---|---|---|---|
| 1 | 编码强度/可提取上限 | `R0` | `card_states.encoding_strength` | 复习行为（无→NULL） | 部分（要靠客观抽检） | 自评 → 先验区间 |
| 2 | 记忆稳定性 | `S` | `card_states.stability` | 复习行为 | 不能（需时间跨度） | 自评 → 先验，靠复习校正 |
| 3 | 节省效应 | `Σ` | `card_states.savings` | 复习行为（重学增益） | 不能 | 不给先验（保持 NULL） |
| 4 | 难度 | `D` | `card_states.difficulty` | 复习行为 | 可以（错题率） | 抽检错误率 → 先验 |
| 5 | **主观流畅度** | `fluency` | 元认知信念 `b_v` | **没有**（曾用 R0 代理） | **可以（自评/即时判断）** | 自评 0–5 直接映射 |
| 6 | 校准偏置 | `belief − R` | 危险区/焦虑区判据（`delta=0.2`） | 元认知层推 | 可以（自评 vs 抽检差） | 每轮测评累计 |
| 7 | 事件"接近度" | `closeness` | 复习事件参数 | 复习 UI（差点想起） | 不适用 | 不动 |
| 8 | 注意力/可用性 | `α(τ)` | 节律层（未实现） | 没有 | 可以（时点问卷） | 后续切片 |
| 9 | 作答速度 | — | 尚无消费方 | 没有 | 可以（计时） | 先记录，不建模 |

**纪律**：所有测评产出的参数一律带 `calibrated: false` 与样本数 `n`；`Σ` 明确**不**给先验——宁可保持 NULL（`tables.dart:311-313` 的既定态度："NULL 表示从未设置，不是 0"）。

---

## 3. 三种信号（自评起步的顺序就是它们的代价顺序）

| 信号 | 测什么 | 噪声 | 代价 | 何时可用 |
|---|---|---|---|---|
| **自评**（JOL："这个点你会多少" 0–5） | `fluency` 本体、`R0` 的弱先验 | 系统性高估（overconfidence） | 零成本、离线 | **首版** |
| **复述抽检**（"用一句话说出它"） | `R0`/`D` 的客观锚点 | 判分噪声（AI 或人工） | 每题十几秒 | 首版（可关） |
| **板块客观题**（辨析/条件判断/层级阅读） | `D`、概念区分度、边界知识 | 依赖题源质量 | 高（要题源） | 逐步 |

关键点：**自评单独存在时会系统性高估**，所以"自评起步"必须配一个校准动作——否则 `fluency` 只是把用户的乐观编码进了模型，危险区会假阳性。首版的校准动作是**小样本抽检**（3–5 题），它的作用不是给每个点精确的 R0，而是给这一轮的 `fluency` 一个**偏置修正**。

---

## 4. 分板块 instrument

用户口径：物理和语文不能用同一套方法。所以 instrument 是**可插拔的板块适配器**，共享参数 schema、落库与 UI。

```dart
abstract class AssessmentInstrument {
  String get subjectKey;                    // 'physics' | 'chinese' | 'generic' ...
  AssessmentScope defaultScope(...);
  List<AssessmentStep> plan(AssessmentScope scope, AssessmentBudget budget);
  AssessmentObservation judge(AssessmentStep step, AssessmentResponse response);
}
```

| 板块 | 测的抽象参数 | 题型形态（该板块独有） | 判分 | 现状可行性 |
|---|---|---|---|---|
| 通用（任何板块先能用） | `fluency`、校准偏置 | 范围自评 + 复述抽检 | 自评 + 复述（AI 判分可选） | **可做**：离线、无题源 |
| 物理 | `D`、概念区分度、适用条件 | 概念辨析（速度/速率/加速度）、公式成立条件、量纲/极限情形、多步推断 | 客观 | 需题源：AI 生成或用户带回 |
| 数学 | `D`、关系推理、表征转换 | 条件判断、反例构造、多表征互译 | 客观 | 同上 |
| 化学/生物 | `D`、分类与过程 | 归属判定、结构与功能对应、过程排序 | 客观 | 同上 |
| 语文 | 表征层级（字面/推断/评价）、文体修辞意识 | 分层阅读（同一文本三级提问）、表达任务 | rubric/自评 | 判分噪声大，先只做层级诊断 |
| 历史/政治 | 时序、因果、论据 | 时序排列、因果链补全、论点—论据配对 | 客观 | 同上 |

**题源纪律（已核过的事实）**：`app/lib/data/skill/zujuan_finder_skill.dart:5-12` 写明组卷网 skill 是 prompt-only——答案与解析在登录墙后，App 只有 `fetch_page`（GET、无 cookie、无 JS）。所以**"组卷网直接供题"今天不成立**；板块客观题的首个来源是 **AI 生成 + 用户从组卷网带回**，两者都要求题目带来源与判据（沿用 zujuan skill 的四条硬伤判据）。

---

## 5. 数据模型（首版）

新表（schema v10，全部只加不删；命名沿用既有单复数风格）：

- `AssessmentSessions`：`id` / `subjectKey` / `scopeTagIds`(JSON) / `startedAt` / `finishedAt` / `budget`(JSON) / `note`
- `AssessmentResponses`：`id` / `sessionId` / `knowledgePointId` / `stepKind`(`self_report`|`recall`|`objective`) / `prompt` / `answer` / `correct`(nullable) / `selfRating`(nullable 0–5) / `confidence`(nullable 0–5) / `elapsedMs` / `judgedBy`(`self`|`ai`|`auto`) / `createdAt`
- `CognitivePriors`：`knowledgePointId` / `source`(`assessment:…`) / `r0` / `d` / `fluency` / `n` / `calibrated`(0) / `createdAt`（**先验与观测分离**：不写进 `card_states`，读模型时按"有观测用观测、无观测用先验"合并）

## 6. 同步分类（用户口径 ③）

同步不做实时；**Windows 出一个可发布 release 时同步一次**。为了让那一天的合并不做数据手术，新表从第一天就标好三类：

| 类 | 表 | 合并规则 |
|---|---|---|
| 只追加（日志） | `AssessmentResponses`、`ReviewLogs`、`CompletionLogs`、`DiffusionLogs` | 并集 + 按 id 去重 |
| 可合并（状态） | `AssessmentSessions`（按 `finishedAt` 取完整的一轮）、`CardStates`、`Tasks` | 字段级 last-write-wins + 冲突留痕 |
| 派生（可重算） | `CognitivePriors` | 不参与同步，导入后本地重算 |

现有 `.tfpkg` 导出/导入（`app/lib/features/settings/presentation/data_section.dart:16-21`）是这条路的现成载体：release 节点同步＝导出/导入 + 上表规则，不引入 CRDT。

---

## 7. 首版切片与验收

- **M1a（本轮起）**：纯逻辑先验层 `app/lib/domain/services/cognitive/assessment_prior.dart`——输入自评与抽检结果，输出每知识点 `r0`/`d`/`fluency` 先验 + 全局校准偏置 + 置信度。单测覆盖：高自评×全错（应压低 R0、偏置为正）、低自评×全对（应抬高、偏置为负）、无抽检（低置信、只给自评先验）、边界钳制。
- **M1b**：schema v10 三张表 + 仓储 + 迁移单测；同步三分类写进 `DATA_MODEL.md`。
- **M1c（已完成，轮次二十四）**：最小 UI——选范围 → 自评 → 3 题复述抽检 → 结果页，写 `PROGRESS.md`。
  实现落在 `app/lib/features/assessment/presentation/assessment_page.dart`，入口在读数页。两处与本文原稿不同，
  理由记在这里：①结果页不展示"先验 vs 未测评的差异"（那需要 M1d 的观测合并，本片只报本轮写了几步证据、
  重算了几个点、平均 R0/置信度）；②复述抽检取范围的两端 + 中间（确定性），不抽"最弱卡"——那会变成另一种刷卡。
- **M1d（已完成，轮次二十五）**：接进读数页（测评先验与复习观测的合并展示，标注"先验/观测"）。
  实现口径（本节即验收）：先验只改**这张卡展示的起点 R0**，且只在这张卡还没有自己的复习史
  （`repetitions == 0 && lastReviewedAt == null`）时生效；一旦复习过，观测接管、先验不再说话，
  值旁边带"（测评先验）"字样，读数页的备注行报"几张卡正在用先验"。先验**不写回** `card_states`，
  也不参与 `ReviewAdvisory` 的排序（排序仍由 D4/D5 的规则决定）。读取走
  `AssessmentRepository.priorEstimatesFor`（批量版），与逐点的 `priorFor` 用同一套来源优先级，
  避免两处各写一份合并规则。
- **M6（已完成，轮次二十六）**：留存率 + 校准曲线，用来验证 M2"记忆效果好"到底成不成立。
  口径（本节即验收）：①**留存率**按"距上次复习同一条卡多少天"分桶（默认 0/1/3/7/30/∞），只用复习结果判定
  "记得"——客观判分 > FSRS ≥Good > v1 旧评分 ≥"记住了"；`fuzzy`/`Hard` 都不算，因为校准要的是"能不能取出来"。
  历史数据立刻可算，不需要任何预测。②**校准**要求预测在判分**之前**落库（`review_logs.predicted_r`，v11），
  事后重算不算预测；老行 NULL、**历史不补算**，所以曲线从 v11 开始积累。指标为
  `Brier = mean((R−实际)²)` 与 `ECE = Σ(n_b/N)·|预测均值−实际|`，预测 `R` 按 `[0,1]` 等宽分 5 箱
  （最后一箱闭合到 1.0）。③纯逻辑在 `app/lib/domain/services/cognitive/learning_metrics.dart`，
  读数页的"学习效果"卡片是**唯一不读模型自己读数**的块（数字全来自 `review_logs`），
  没有预测样本时明说"校准曲线还没有样本"而不是画一条假设的曲线。
  未做：按知识点聚合的留存率、把度量接进 AI 工具、把 `calibrated` 从 false 变 true（需要标定协议）。

## 8. 明确不做

- 不从卡片出题（用户口径 ②）；
- 不给 `Σ`/`S` 造先验（模型会自己长出来）；
- 不把先验写进 `card_states`（先验≠观测，混写会让"复习校正"失去意义）；
- 不在首版做实时同步/账号系统。
