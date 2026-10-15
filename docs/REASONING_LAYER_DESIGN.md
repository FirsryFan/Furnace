# 推理层设计（第一步：管道）

> 代码：`app/lib/domain/services/reasoning/capability_action.dart`、
> `app/lib/domain/services/reasoning/reasoning_prompt.dart`
> 测试：`app/test/domain/services/reasoning/`
>
> 本文只描述**已经写进代码**的东西；没验证过的判断都标了「未验证」。

## 1. 这一步要解决的问题

MindNet 现在建模的是**记忆**：一个知识点学生记不记得住、什么时候会忘。
但学生做不出题，很多时候不是「没记住」，而是**在某一个思考动作上卡住**了：
没想起要构造反例、没意识到可以分类讨论、想不到用不变量把动态过程压扁。

所以推理层的第一段管道只做三件事，且**不做别的**：

1. 让 AI **亲自把题解出来**（它绝不能出题）；
2. 把它的自述思维链切成步骤，每步贴一个跨学科的**能力动作**标签；
3. 把这份结构化数据交给 MindNet，用来定位「学生最可能卡在哪一步」。

出题是另一条产品线。如果让同一个模型既出题又解题，诊断出的「卡点」里会混进
出题偏差，无法归因——这是把「不得自造题目」写进提示词最高优先级规则的原因。

## 2. 什么算「一步」（step）

一步 = **一个可独立判断对错、且能对应到一个能力动作的最小推理单元**。

具体判据（提示词里对模型的要求，也是后续人工复核的标准）：

- 它有**目标**（这一步要达成什么，`goal`）；
- 它有**理由**（为什么这一步成立、为什么可以这么做，`justification`）；
- 它**能被贴上一个词表里的动作**（`actionType`）；
- 它可以有**自检方式**（`checkMethod`，可以为空）；
- 它带一个**卡点风险** `stuckRisk ∈ [0,1]`，含义是「学生最可能卡在这一步」的概率，
  **不是**「这一步有多难」；两者经常不一致：难但必然的变形不卡人，简单但需要
  灵光一闪的动作才卡人。

不算一步的：「答案是 2」（结论不是步骤）；「由①得②」（纯抄写，没有新动作）；
整段心算过程（应该按动作切开，而不是按长度切）。

`steps` 至少 1 步。零步的思维链没有任何诊断价值，解析器直接判为格式错误——
宁可让上游看到「模型今天没按契约输出」，也不要往数据库里写一条空链。

## 3. 为什么 `actionType` 是跨学科的桥

同一条思维链，如果只按**知识点**标注，那么数学的链和历史的链互不相干，在 OI /
强基题上训练出来的东西无法迁移到高考——因为知识点本身不迁移。

按**动作**标注就不同了：识别不变量、分类讨论、极端化、反证、构造反例、量纲检验
这些动作，在数学、物理、化学、生物、语文、历史、信息学竞赛、强基里反复出现，
只是穿着不同的外衣。`CapabilityAction.subjectHints` 就是「这个动作在哪些轨道上
真的会出现」的记录，`transferable` 由它推出（至少出现在
`CapabilityAction.transferableSubjectThreshold = 4` 条轨道上）。

于是这张表同时给了我们两样东西：

- 一张**训练/诊断的公共坐标系**：所有学科的链都落在同一组动作上，才谈得上「迁移」；
- 一条**迁移性的先验**：`transferable == true` 的动作是重点，只覆盖 2–3 条轨道的
  动作（如 `amortized_argument`、`information_bound`）是竞赛特有的技巧。

**注意**：`subjectHints` 是判断，不是测量。它是人写下的先验，会错；它的价值在于
——它是显式的、可测试的、可被数据推翻的（见 §7 开放问题）。

## 4. 词表 v1：种子动作的增删

v1 **保留了任务给定的全部 20 个种子动作，一个都没删，也没有新增**。理由：

- 20 个动作已经覆盖「识别结构 / 变换问题 / 论证 / 检验」四类，新增只会稀释
  模型的选择质量（词表越长，模型越容易挑一个似是而非的）；
- 删任何一个都会丢掉一类卡点，而 v1 还没有数据来决定该删谁——等有了真实
  思维链的 `actionType` 分布，再决定合并或删除，才是有依据的。

已经被记下、但**故意没有在 v1 动**的疑似重叠（见开放问题 1）：
`invariant_recognition`（识别不变量）与 `invariant_decomposition`（分解并维护不变量）、
`case_split`（分类讨论）与 `extreme_case`（边界/极端化）、
`counterexample_construction`（构造反例）与 `proof_by_contradiction`（反证）。
它们在真实解题里常常一步同时触发，是否要合并需要分布数据。

排序规则（有测试守着，不是排版偏好）：

1. `transferable == true` 的排在前面；
2. 组内按 `subjectHints.length` 从多到少；
3. 数量相同时按文件里的书写顺序，即 `sortOrder`（0 起连续递增，等于下标）。

`key` 是稳定标识：snake_case、永不本地化、永不改名。中文只出现在 `labelZh` /
`descriptionZh`。数据库里存的是 `key`，改 key 等于让历史数据失去意义。

## 5. 解析器期待的 JSON 契约（逐字，与 `chainJsonContract` 一致）

```json
{
  "summary": "一句话概括整条思路",
  "steps": [
    {
      "index": 1,
      "goal": "这一步要达成的小目标",
      "actionType": "first_principles",
      "justification": "为什么这一步成立、为什么可以这么做",
      "checkMethod": "这一步做完后怎么自检（没有就写空字符串）",
      "stuckRisk": 0.5,
      "knowledgeHints": ["涉及的知识点或符号"]
    }
  ]
}
```

字段语义与容错边界：

| 字段 | 类型 | 缺失时 | 类型/取值错误时 |
| --- | --- | --- | --- |
| `summary` | String | 空字符串（链本身仍可用） | 抛错 |
| `steps` | 非空数组 | 抛错（缺失或为空都抛） | 抛错 |
| `steps[].index` | int | 抛错 | 抛错（整数值的 double 接受） |
| `steps[].goal` | 非空 String | 抛错 | 抛错 |
| `steps[].actionType` | 非空 String | 抛错 | **未知 key 不抛错**：保留原串，`knownAction=false` |
| `steps[].justification` | String | 空字符串 | 抛错 |
| `steps[].checkMethod` | String | 空字符串 | 抛错 |
| `steps[].stuckRisk` | 0..1 的 num | `defaultStuckRisk = 0.5` | 抛错（越界、NaN、非数字） |
| `steps[].knowledgeHints` | List\<String\> | 空数组 | 抛错 |

容错（输入侧）：`parseChain` 能吃掉 ```json 代码块、代码块前后的寒暄、以及 JSON
前后多余的散文；空回复、找不到 `{...}`、JSON 语法错误、顶层不是对象等一律抛
`ReasoningParseException`（可 catch 的类型化异常，带 `rawSnippet`）。

一处刻意的取舍：**未知 `actionType` 不是错误，是信号**。词表是开放的，模型在用我们
还没建模的思考方式时，我们想看到 `knownAction == false` 的数据，而不是让整条链解析
失败。反过来，缺 `goal`、`stuckRisk` 越界这类**结构**问题会让整条链失败——因为一句
「这一步在干嘛」都不知道的步骤，进数据库只会污染诊断。

大小写敏感：`byKey('Reduction')` 返回 `null`。错大小写就是未知 key，不做静默归一化，
否则统计出来的动作分布会掩盖模型的格式问题。

## 6. 与 schema v12 的接口需求

`ReasoningSteps` 若要放下本层的输出，需要的列/字段（字段名与
`ParsedStep.toJson()` 一致，避免中间层再翻译一次）：

- `chainId` ／ 步序号 `index`（**不是**主键自增，是模型给的步号，要保留原值）
- `goal`、`justification`、`checkMethod`（TEXT，可空字符串）
- `actionType`（TEXT，**原始字符串**，未知值也照存）
- `knownAction`（BOOL）——或者等价地 `actionKey` 可空外键；两个都存是为了
  「词表升级后重新判定历史数据」时能区分「当时未知」和「现在未知」
- `stuckRisk`（REAL，0..1）
- `knowledgeHints`（TEXT/JSON 数组）
- `summary` 在 `ReasoningChains` 上，是链级字段，不是步级

`Questions` / `QuestionOptions` 侧：`reasoning_prompt.dart` 只要题干的**原文**和
选项文本列表，不读题目 ID、不读知识点。Chain 表需要记住它解的是哪道题
（`questionId`）以及用哪个 `subjectKey` 提示的模型。

## 7. 开放问题

1. **动作重叠怎么裁**：`case_split`/`extreme_case`、`invariant_recognition`/
   `invariant_decomposition`、`counterexample_construction`/`proof_by_contradiction`
   在真实链里是否经常同现？需要一个「一步只能一个动作」还是「一步可以多个动作」
   的决定——当前契约是**一步一个**（`actionType` 是单值字符串）。
2. **`transferable` 阈值 4 是否合理**：这是先验，不是测量。等有 200+ 条真实链后，
   可以用「动作在跨学科题目上被模型选中的分布」来校准。
3. **`stuckRisk` 是谁的风险**：当前语义是「学生最可能卡在这一步」，但模型并不
   认识这个学生。它现在其实是「这类学生群体的先验卡点」。要不要把学生的历史掌握度
   注入提示词（每条链一个学生画像）？这会影响隐私设计。
4. **未知 `actionType` 的处理策略**：现在只是标记。是否要在累计 N 次后自动生成
   候选动作、走人工确认流程？未定。
5. **`labelEn` 的用途**：目前只用于导出/排版，没有任何判断依赖它。若导出不需要，
   应删除以减小契约面积——**未验证**：还没有导出需求出现过。
6. **`index` 是否强制连续**：提示词要求从 1 连续递增，但解析器只要求是整数。
   若发现模型跳号，是解析器收紧还是上层重建，未定。

## 8. 验收记录

在 `app/` 下执行（工作目录 `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app`）：

- `dart analyze lib/domain/services/reasoning test/domain/services/reasoning`
  → `No issues found!`（本层文件 0 error / 0 warning / 0 info）
- `dart analyze lib test`
  → `0 error / 0 warning / 95 info`（这一次运行的实际输出；95 条 info 全部在
  本层之外。任务书给的基线是 94 条 info，仓库此刻有并行改动，因此这个数字是
  观测值而不是承诺）
- `flutter test test/domain/services/reasoning`
  → `All tests passed!`（46 个用例）

**未验证**：没有用真实模型回复跑过 `parseChain`（本机离线，不调用 provider）。
解析器的行为只由手工构造的 JSON 用例覆盖；真实输出的分布（尤其是模型自创
`actionType` 的频率）需要接入模型后统计。

## 9. 备注

`analysis_options.yaml` 采用 `package:flutter_lints/flutter.yaml` 并追加
`prefer_single_quotes`、`sort_child_properties_last`；info 级 lint 在仓库里允许存在。
