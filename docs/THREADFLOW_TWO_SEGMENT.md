# ThreadFlow 两段式：算法段 A 与 MindNet 段 B 的边界

状态：段 B 已实现并测试通过（见文末「证据」）。
代码：`app/lib/domain/services/scheduling/domain_balance.dart`
测试：`app/test/domain/services/scheduling/domain_balance_test.dart`

## 1. 为什么要分两段

业主对 MindNet（认知模型）在**任务排序**里的职责定义得很窄：

> 给一段时间，决定**做什么最有效**，并**把工作量摊到各个学科**。

而下面这些问题被明确划给"普通算法"，**不允许** MindNet 参与：

| 问题 | 归属 | 现成实现 |
| --- | --- | --- |
| 哪些时间窗可用 | 算法 | `app/lib/domain/services/scheduling/time_window_engine.dart` |
| 时长够不够（estimate 塞不进 deadline 前） | 算法 | `app/lib/domain/services/scheduling/thread_ranker.dart:286-291` |
| 截止时间是否已过 | 算法 | `app/lib/domain/services/scheduling/thread_ranker.dart:268-277` |
| 是否被忙碌块占用 | 算法 | `app/lib/domain/services/scheduling/thread_ranker.dart:279-284` |
| 该不该做它、先做哪个、各科怎么分配 | MindNet 语义 | `app/lib/domain/services/scheduling/domain_balance.dart` |

所以本仓库里排序被拆成两段，**段 B 只吃段 A 的可行输出**：

```
RankEvent + RankContext
        │
        ▼
【段 A】ThreadRanker.rank(...)            ← 纯算法，硬约束（红名单）
        │  RankOutput{ ready, insufficient, overdue }
        ▼
   ready（可行候选）
        │
        ▼
【段 B】DomainBalanceRanker.rank(...)     ← 语义段：有效性 + 学科均衡 + 中文理由
        │  DomainBalanceOutput{ ranked, insufficient, overdue, domainQuota }
        ▼
   BalancedTask{ taskId, score, reasonZh, domainKey, balanceNote, ... }
```

关键点：**段 B 不能把红名单捞回来**。一个任务即便处在危险区，只要它塞不进
deadline（段 A 判 `insufficient`），它就不会出现在 `ranked` 里；`insufficient`
与 `overdue` 两个桶由段 B 原样带出（`domain_balance.dart` 里
`DomainBalanceRanker.feasible` 直接转调 `ThreadRanker.rank`，**不复制、不覆盖**
其逻辑）。

## 2. 调用契约（UI / service 层要调的函数）

```dart
DomainBalanceOutput DomainBalanceRanker.rank({
  required List<RankEvent> events,              // 同 thread_ranker.dart 的输入类型
  required RankContext context,                 // now / energy / blocks / goal / weights
  Map<String, List<String>> taskKnowledgePoints = const {}, // taskId -> 知识点 id
  List<KnowledgePointReading> readings = const [],          // 危险区/发展区/先验
  List<DomainTag> tags = const [],              // Tags 树（纯数据）
  List<TaskTagLink> taskTagLinks = const [],    // ObjectTags 链接（objectType=='task'）
  DomainBalanceWeights weights = const DomainBalanceWeights(),
  EffectivenessTuning tuning = const EffectivenessTuning(),
  int? windowSlots,                             // 本窗口能装几个任务（可空）
  Map<String, int> explicitQuotas = const {},   // 按学科显式配额（正数才生效）
});
```

返回值：

```dart
class DomainBalanceOutput {
  final List<BalancedTask> ranked;   // 推荐顺序（贪心选择顺序，不一定等于 score 降序）
  final List<RankedEvent> insufficient; // 段 A 红名单：塞不进 deadline
  final List<RankedEvent> overdue;      // 段 A 红名单：deadline 已过
  final Map<String, int> domainQuota;   // 每个学科的配额
}
```

`ranked` 里每个 `BalancedTask` 都带 `score / baseScore / effectiveness /
urgency / goal / balanceBonus / overQuotaPenaltyApplied / reasonZh /
domainKey / balanceNote / domainQuota / domainOrderInWindow / source`，
以及 `source`（原始 `RankedEvent`，含完整分数分解，供属性页展示）。

认知读数的来源对象（纯数据）：`KnowledgePointReading{ knowledgePointId,
inDangerZone, inDevelopmentZone, priorR0, priorConfidence }`。DB → 这个结构的
适配是调用方的活（本文件不 import drift）。

## 3. 权重：选了哪些数、为什么

`DomainBalanceWeights`（默认值即实际生效值，全部显式暴露、可被 UI 编辑）：

| 分量 | 权重 | 为什么 |
| --- | --- | --- |
| `effectiveness`（认知有效性，**MindNet 项**） | **0.50** | "做什么最有效"是这一段的主题，所以给最大的一项；但它**不能压过学科保底**（见 `overQuotaPenalty` 的取值论证）。 |
| `urgency`（紧迫度） | 0.25 | 直接复用段 A 已经算好的 `RankScore.urgency`，不再自造一套。段 A 的 urgency 已经是"越近越高"的衰减值，段 B 只做加权。 |
| `goal`（目标匹配） | 0.10 | 同样复用段 A 的 `RankScore.goalMatch`。业主明确说过目标是自由文本、不是 MindNet 节点，所以这里只给一个小权重。 |
| `balance`（学科分散奖励） | 0.15 | 配额**内**的奖励，见下文配额设计。 |
| `overQuotaPenalty`（超配额罚分） | 1.00 | 不在归一化里，是**硬性优先级保证**：`超过配额的任务` 一定排在 `配额内的任务` 之后，见下文。 |

前四项在计算前用 `normalized()` 归一化到和为 1（默认本来就是 1.00：0.50+0.25+
0.10+0.15），这样用户改任意一个权重都不会让分数跑出 [0,1]——沿用
`thread_ranker.dart` 的 `RankWeights.normalized()` 同一条纪律。

### 学科配额（dispersion / quota 项）

* 领域键 = 任务的**顶层标签祖先**（不是叶子标签）。路径 `语文/阅读/文言文`
  的领域键是 `语文`；一个任务挂了多个标签时，取"路径最短优先、同长度取字典
  序最小顶层段"——规则写死、纯确定、偏保守（越靠近顶层越像学科）。
* 没有标签（或标签解析不出来）→ 归入 `未分类` 这一组，不丢弃、不报错。
* 配额：`quotaFor(windowSlots, domainCount) = max(1, ceil(windowSlots / domainCount))`。
  * 只有一个学科时配额 = 全部槽位（单科不会因为配额被砍）。
  * 学科越多，每科保底越少，但**永远不为 0**。
  * `windowSlots` 为空/≤0 时按候选个数算。
  * `explicitQuotas` 里给了正数的学科，覆盖自动配额。
* 配额**内**：奖励 `1 - used/quota`（第 1 个 +1.00，第 2 个 +0.50……），乘以
  `balance` 权重（0.15）。
* 配额**外**：奖励归 0，并罚 `overQuotaPenalty × 超出者序号`（第 1 个超出者
  罚 1.00，第 2 个罚 2.00……）。

`overQuotaPenalty = 1.0` 的取值理由：归一化后的基础分 ≤ 1.0（四项权重和为 1、
每个分量 ≤ 1），所以"罚 1.0"必然大于任何两个任务之间可能出现的基础分差。
这等价于一条**可读的硬保证**：先给每个学科保底，再谈谁更有效。它和
`balance` 一样是显式参数，不藏在代码里。

### 认知有效性分量的整定值

`EffectivenessTuning`：

| 项 | 值 | 为什么 |
| --- | --- | --- |
| `neutral` | 0.50 | 没有任何读数时的中性分。**缺数据不等于低价值**——沿用 `thread_ranker.dart` 里 `_fitOf` 的同一条纪律（缺失分量不假装成一半匹配）。 |
| `dangerBoost` | +0.35 | 危险区（自信高、实际提取不出来）是最该立刻练的，加成最大。 |
| `developmentBoost` | +0.20 | 发展区（差点想起来，合意难度）收益高，但低于危险区。 |
| `priorWeight` | 0.30 | 先验项 `0.30 × (1 - R0) × confidence`：编码越弱越该现在补；`confidence = 0` 时先验完全不参与。 |

有效性 = `clamp(neutral + 加成, 0, 1)`，一个任务挂多个知识点时取**最有效**的
那个（`max`），而不是平均。

这三个数是**未标定**的粗映射（和仓库其它认知层一致：没有真实数据前不假装
精确），集中放在 `EffectivenessTuning` 一处，标定之后只改一处。

## 4. 中文理由与可解释性

每个任务都带一句中文 `reasonZh`，只讲**主导**的那条依据，优先序：
危险区 → 发展区 → 测评先验偏弱 → 无读数但紧迫度高 → 中性。

例（与 `domain_balance.dart` 的 `_reasonZh` 输出逐字一致）：
* `知识点「kp-danger」 在危险区（自信高、实际提取不出来），现在练它收益最大，所以排在这里。`
* `测评先验显示 知识点「kp-weak」 的编码强度只有 R0=0.05（越弱越该现在补），所以排在这里。`

`balanceNote` 讲领域维度：配额内 + 第几个 + 奖励多少；超配额则说明"配额已排满、
这是第 N 个超出者、罚了多少分、排到配额内任务之后"。

## 5. 确定性与退化输入

* 选择过程是**贪心**：每轮重算"配额奖励/罚分"再取最优，因此 `ranked` 的顺序
  是选择顺序，`score` 也会随着奖励变化而单调下降——**不要**拿 `ranked` 当
  "score 降序"用（构建时就是对的，直接按顺序渲染即可）。
* 平局比较（`DomainBalanceRanker._isBetter`）：`score` → `baseScore` →
  `taskId` 字典序 → 原始下标。前两层决定排序，后两层保证"输入顺序不同也排得
  一样"。这就是确定性 tie-break。
* 空输入 → 空结果（`ranked/insufficient/overdue` 全空，`domainQuota` 空）。
* 退化输入不抛：`readings` 里空/未知知识点、`priorR0` 超出 [0,1]（clamp）、
  `windowSlots` 为负、`explicitQuotas` 给 0、标签 `parentId` 成环（上溯有
  `byId.length + 1` 步的防环上限）——都有测试覆盖。

## 6. 刻意**没有**做的事

1. **没有改 `thread_ranker.dart`。** 段 B 只是转调它；`rank` 的既有行为、
   既有测试一字未动（`DomainBalanceRanker.feasible` 有一个测试逐桶对比
   `ThreadRanker.rank` 的输出，作为"段 A 没被碰过"的回归哨兵）。
2. **没有引入疲劳/energy 的新逻辑。** 段 A 的 `fit`/`fatigue`/`expectedPressure`
   仍然只通过 `RankScore` 被复用（当前只用 `urgency`/`goalMatch` 两个分量）；
   段 B 不自己再算一遍，避免两处口径漂移。
3. **没有连数据库。** 不 import drift、不读 `Tags`/`ObjectTags`/`Tasks` 表；
   标签树与链接以 `DomainTag`/`TaskTagLink` 纯数据传入。DB → 纯数据的适配在
   调用方（UI/service 层）。
4. **没有碰认知引擎。** 不实例化 `FastDiagnosis`/`Metacognition`/`AssessmentPrior`，
   只消费它们的**读数**（危险区 / 发展区 / 先验）。MindNet 的推理在哪里跑、
   跑不跑，与本文件无关。
5. **没有做时间窗切分/时长分配。** `windowSlots` 是调用方给的整数，段 B 不
   计算"这段时间能塞几分钟"。
6. **没有做跨窗口/长期计划。** 只排"这一个窗口内"的候选。
7. **没有标定权重。** 上表数值是显式选定的粗映射，不是拟合结果。
8. **没有写理由到多个字段/多段文案。** `reasonZh` 一句话，属性页要看分解就读
   `BalancedTask` 上的数值字段。

## 7. 证据（本次实际运行的命令与结果）

在 `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app` 下：

* `dart analyze lib test`
  → `0` 条 error、`0` 条 warning、`96` 条 info（`96 issues found.`）。
  其中与 `scheduling` 相关的 4 条 info 全部落在**本就存在、本次未修改**的
  `lib/domain/services/scheduling/thread_ranker.dart:503` 与
  `test/domain/services/scheduling/thread_ranker_test.dart:309/372/406`；
  新增的两个文件各自 `dart analyze` 均为 `No issues found!`。
* `flutter test test/domain/services/scheduling`
  → `All tests passed!`（50 个用例，含 `thread_ranker_test.dart` 与
  `time_window_engine_test.dart` 的全部既有用例）。

## 8. 接线：从数据库到 Thread feed（Q6）

§6.3 说"DB → 纯数据的适配在调用方"。这一节就是那个调用方，写下来是因为**键空间**
在这里出过一次真实的错。

### 8.1 谁读表、谁排序

| 层 | 文件 | 责任 |
| --- | --- | --- |
| 纯数据 | `app/lib/domain/services/scheduling/thread_balance_inputs.dart` | `ObjectTagLink`、任务→知识点解析（共享标签才算挂载）、`ThreadBalanceInputs` |
| 纯投影 | `app/lib/domain/services/scheduling/cognitive_readings.dart` | 诊断/先验 → `KnowledgePointReading`（`danger`→危险区、`weak`→发展区、先验→`priorR0`） |
| 读表 | `app/lib/features/thread/application/thread_balance_provider.dart` | 唯一 IO 点：`Tags`/`ObjectTags`/`KnowledgePoints` + 认知页的诊断 provider + 测评先验 |
| 排序 | `app/lib/domain/services/scheduling/domain_balance.dart` | 段 A 可行域 + 段 B 有效性/配额/理由 |
| 编排 | `app/lib/features/thread/application/thread_rank_service.dart` | `build()` 同时拿段 A 与段 B 结果，`ThreadFeed.balanced` / `reasonFor(taskId)` |
| 展示 | `app/lib/features/thread/presentation/thread_page.dart` | 每张卡下面一行 `reasonZh`（不改 ARB） |

### 8.2 一条纪律：段 A 的输出不动

`ThreadFeed.ranked` 仍然是 `ThreadRanker.rank` 的结果，`readyTasks` 只在段 B 有结果时
改用段 B 的顺序（段 B 缺人时按段 A 顺序补齐，绝不丢任务）。这样"红名单/超期桶由算法段
决定"这条边界保留在**类型**上，而且 `thread_rank_service_test.dart` 既有的 5 个用例
一行不用改。段 B 永远跑：空输入时它退化成中性排序，仍然给出领域配额与理由。

### 8.3 键空间：`kp-…` 与 `tag-…` 不是一回事（真实缺陷，已实测）

* `KnowledgePoints.id` = `_newId('kp')`（`app/lib/data/repositories/anki_repository.dart:25`）；
  `Tags.id` = `_newId('tag')`（`app/lib/data/repositories/tag_repository.dart:27`）。
* 快层的图节点是**标签**：`app/lib/domain/services/cognitive/cognitive_graph.dart:105`
  的 `CognitiveTag.fromTag(Tag row)` 直接取 `row.id`。诊断也按 `tag.id` 去查
  `rowsByKnowledgePoint`（`app/lib/domain/services/cognitive/library_diagnosis.dart:147-157`），
  并且 `starts`/`targets` 会被"不在图里的 id 直接丢掉"（同文件 `:163-174`）。
* 但 `app/lib/features/cognitive/presentation/cognitive_model_page.dart:768-810`
  传进去的 `rowsByKnowledgePoint` / `starts` / `targets` 全是**知识点 id**。
  在真实数据（含 `DemoDataService`）上两者不相等，于是三者全被丢掉。

实测（临时探针，用真实仓储建 `tag-…` + `kp-…` 各一个、一行 `card_states`，跑的就是页面
那条 provider）：

```
PROBE tagIds=[tag-15384e3e-…] kpId=kp-cbcb7d1a-…
PROBE page        fastLayerRan=false byKnowledgePoint={} starts=[] targets=[] nodesWithoutMs=[3 个 tag]
PROBE tag-keyed   fastLayerRan=true  byKnowledgePoint={tag-15384e3e-…: empty, tag-2839568a-…: empty}
```

同一份数据、同一时刻，只把键换成标签 id 就跑起来了：**病因是键，不是数据**。
`library_diagnosis_test.dart` 没抓到它，因为它的 fixture 用 `kp-1` 同时当标签 id
和知识点 id（`:50-51` 的 `tag('kp-1')`）。

* **Q6 当场做的**：`thread_balance_provider.dart` 在**调用点**做 `kp → tags` 翻译
  （`ObjectTags` 里 `objectType == 'knowledge_point'` 的行），一个知识点有多个标签时
  取 id 最小且**有结论**的那个，保证确定性。理由行的名字另走
  `KnowledgePoints.title`，所以 UI 上不会出现 `kp-…` 这种裸 id。
  （Q8 把这件事搬进了领域入口，见 §8.5；调用点只剩“把挂载表读出来”。）
* **M1 观察层当时未修**：认知页与复习页仍按知识点 id 查标签键的结论。当时判断这是一条
  独立缺陷，不能混在 Q6 里静默改掉 —— 结论没变，但它的**影响面比想象的大**（见 §8.5）。

### 8.5 Q8：把翻译收进领域入口（已修）

Q6 只在 threadflow 这一条路上绕开了键空间，于是同一个缺陷还留在另外两条路上：
`cognitiveLibraryDiagnosisProvider`（认知页）与 `ProblemEvaluator.evaluate`（卡点评估
拿学生状态）。Q8 把桥挪到**两个领域入口**，让契约保持“进出口都是知识点 id”。

* 桥：`app/lib/domain/services/cognitive/knowledge_point_tag_bridge.dart`
  —— `tagIdsByKnowledgePoint` / `tagIdsOf` / `tagIdsOfAll` / `expandKeys` /
  `verdictsByKnowledgePoint`（一个 kp 多个标签时取**有结论且 id 最小**的，与 Q6 同规则）。
* `LibraryDiagnosisRunner.run` 新增可选 `tagIdsByKnowledgePoint`
  （`app/lib/domain/services/cognitive/library_diagnosis.dart`）：传了就先把
  `rowsByKnowledgePoint` / `startKnowledgePointIds` / `targetKnowledgePointIds`
  展开成标签键再进图，出图时把标签键的结论翻回**知识点键**。不传 = 旧行为。
* `ProblemEvaluator.evaluate` 同样新增该参数（`.../problem_evaluator.dart`）：
  学生状态行、起点、每个选项的目标都先翻译；判卷时仍用**知识点键**的 `rowsById`。
* `cognitive_model_page.dart` 的 `cognitiveLibraryDiagnosisProvider` 与
  `cognitiveReadingsProvider` 直接吃 `diagnosis.byKnowledgePoint`（已经是 kp 键）；
  新增 `knowledgePointTagIdsProvider` 只负责把挂载表读出来。
* `thread_balance_provider.dart` 不再自己翻译。
* `cognitive_tools.dart`（AI 工具）走同一个参数，三个入口一套规则。

**验收（实测）**：`test/domain/services/cognitive/knowledge_point_tag_bridge_test.dart`
（15 例，规则）+ `test/features/cognitive/knowledge_point_key_space_test.dart`（4 例，
用真实仓储建出**不同**的 `kp-…` / `tag-…`）→ `All tests passed!`（19）。其中哨兵用例
在不传映射时断言 `fastLayerRan == false`（缺陷本身）、传了之后断言 `true` 且结论键里
**没有一个** `tag-…` 漏出来 —— 旧 `library_diagnosis_test.dart` 的 fixture 两边用同一个
字符串，所以它永远看不到这个问题。

### 8.4 证据（本次实际运行）

在 `app` 下：

* `dart analyze lib test` → `error=0 warning=0 info=94`（与基线同数）。
* `flutter test test/features/thread test/domain/services/scheduling`
  → `All tests passed!`（81 个用例：段 A/B 领域 71 + Thread 服务 7 + 新增 provider 3）。
* `flutter test test/features/ai/cognitive_tools_test.dart test/domain/services/cognitive`
  → `All tests passed!`（168；Q8 后回归，见 §8.5）。

