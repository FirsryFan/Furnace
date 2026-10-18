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

**词表可扩展（轮次一百二十一，纯逻辑层）**：内置 20 个动作不变，新增
`capability_action_overlay.dart` 提供"内置 + 用户自定义"的合并词表，用户以后能自己加动作，
而不用等发版改内置表：

- `CustomCapabilityAction`：`key` / `labelZh` / `labelEn` / `descriptionZh` / `subjectHints`；
- `CapabilityActionOverlay`：`const` 构造（`empty` 是空 overlay）、`fromJson` **永不抛**
  （坏数据只丢条目）、`toJson` 写回 `{'version': 1, 'customActions': [...]}`；
- `CapabilityActionCatalog`：`CapabilityActionCatalog.builtIn` 与
  `CapabilityActionCatalog.merge(customActions)`；`actions` / `customActions` / `issues`、
  `byKey` / `isKnownKey` / `isBuiltInKey` / `isCustomKey`、`keys` / `length`。
- 合并规则（有测试钉住）：内置条目**在前且保持对象同一性**（不是复制），自定义按输入顺序追加，
  `sortOrder` = 合并后下标；空 overlay 的 `actions` 与内置 `CapabilityAction.catalog` 逐项
  `identical`——默认零行为变化。
- key 校验：trim；空 → `missingKey`；长度 > 48 → `keyTooLong`；
  须匹配 `^[a-z][a-z0-9]*(_[a-z0-9]+)*$` 否则 `keyNotSnakeCase`（大小写敏感，
  `Force_Diagram` 视为未知）；撞内置 key → `keyReserved`（**拒绝覆盖**，内置展示不变）；
  自定义之间重复 → `duplicateKey`（先到先得）；缺 `labelZh` → `missingLabelZh`。
- 展示兜底：`labelEn` 空用 key、`descriptionZh` 空用 `labelZh`；`subjectHints` 只保留合法
  `subjectKeys`、去重、保序，`transferable` 仍按"合法 hints 数 ≥ 4"推。
- 被拒的条目**不进** `catalog.actions`，但 issue 全部收集；`overlay.customActions` 保留原始
  条目（序列化时不替用户丢数据）。
- **持久化与接线（轮次一百二十三，schema v25）**：overlay 存 `local_settings.capability_action_overlay_json`
  （NULL = 出厂词表），迁移 v24→v25 只加列不写默认值；`CapabilityVocabularyStore` 负责读写
  （坏 JSON 读作空、空词表写回 NULL），`questionReasoningServiceProvider` 把 `store.load` 作为
  `overlayLoader` 注入管道，每次解题取的词表同时喂提示词与解析器；细节见 `docs/DATA_MODEL.md` §14。
- **仍未做**：词表编辑 UI 与 l10n 文案没做（编辑操作层、未知动作发现器是纯逻辑交付）；
  `CapabilityAction` 内置表本身零改动。

### 4.1 编辑层与未知动作发现（轮次一百二十三，纯逻辑）

在 §4 的合并层之上再叠两层纯函数，给以后"用户自己改词表"的界面供 API：

- **编辑层** `capability_action_overlay_editor.dart`：`add` / `update` / `remove` / `reorder` /
  `mergeImport`，全部静态纯函数，输入 overlay + 编辑意图 → `OverlayEditResult{overlay, issues, changed}`；
  **不抛异常、不做 IO**，失败返回同一个 overlay 对象（`identical`）+ 单条 issue，调用方零副作用。
  硬上限 `maxCustomActions = 100`；`mergeImport` 接受 `toJson` 产物或裸数组，逐条"归整→校验→去重→上限"。
- 校验入口只有一处：`validateCustomCapabilityAction` / `normalizeCustomCapabilityAction` 复用合并层的
  私有 `_validate` / `_sanitizeSubjectHints`，保证"表单提示的理由"与"合并拒绝的理由"逐字一致。
  issue 枚举本轮追加 4 值：`keyNotFound` / `indexOutOfRange` / `customActionLimitExceeded` /
  `importNotRecognized`——**只由编辑层产生**，合并层永不产生这 4 个。
- 编辑语义：`update` 的 null = 保持原值、空串 = 清空（`labelEn`/`descriptionZh` 由合并层兜底，
  `labelZh` 空被 `missingLabelZh` 拒收）；key 不可改；`remove` 清掉 trim 后同 key 的**全部**条目；
  `reorder` 的 `newIndex` 是移动后下标，严格 `0..len-1`，原位是 no-op。
- **未知动作发现** `capability_action_discovery.dart`：`discover(samples, catalog, highRiskThreshold: 0.6,
  maxSampleQuestionIds: 5)` 只输出词表不认识的 `actionType`，按"步数 desc → 题数 desc → actionType asc"
  排序，返回不可变列表；空白 actionType 丢弃、trim 后大小写敏感；questionCount 按去重 questionId；
  样本题目默认最多 5 条按首次出现；`averageStuckRisk` 无读数时 **null 不插补 0**（沿用卡点风险评估的
  缺读数原则）；风险值/阈值夹 0..1，非有限值忽略或退回 0.6。
- 生产接线提醒：`catalog` 参数建议始终传当前生效的 `overlay.catalog`（默认只认内置），否则用户已加的
  自定义动作会再次出现在"未知动作"候选里。持久化/UI/provider 均未做，等后续切片。
- 验收：`app/test/domain/services/reasoning` → +59（编辑层 34 + 发现器 25），目录 analyze 干净。

### 4.2 词表 JSON 文件编解码（轮次一百二十五，纯逻辑）

编辑页要做到「从文件导入 / 导出成 .json」之前，先有纯逻辑编解码层：

- 文件：`app/lib/domain/services/reasoning/capability_vocabulary_codec.dart`（456 行）。API：
  `String encodeCapabilityVocabularyJson(CapabilityActionOverlay overlay, {bool pretty = true})`
  （键顺序固定的 `{"version":1,"customActions":[...]}`，pretty 两空格缩进 + 结尾换行，compact 无空白；
  **不做语义去重**，交给 overlay 校验）、
  `String? tryEncodeOverlayForSharing(...)`（空词表返回 null）、
  `CapabilityVocabularyDecodeResult decodeCapabilityVocabularyText(String text)` —— **永不抛异常**。
- 解码口径：strip UTF-8 BOM、容忍 CRLF 与首尾空白；两种顶层形状（带 version 对象 / 裸 customActions
  数组，后者 version 按 1）；version 缺省 = 1、整数 > 1 报 `unsupportedVersion` 但**尽力解析**、
  整数 < 1 报 `invalidVersion`、非整数报 `versionNotInteger`；未知顶层键记 `unknownTopLevelKey`
  不报错；原始 UTF-8 字节 > **64 KB**（先于 JSON 语法判断）、空文档、坏 JSON、顶层非对象/数组为
  **fatal**（返回空 overlay）；`customActions` 缺失/非列表为非 fatal；条目级（非对象 / 缺 key /
  key 非字符串）逐条记账并带原始 index；结构合格条目交给 `CapabilityActionOverlay.fromJson`，
  其既有 catalog issues 合并为 `entryRejected`（带 `overlayReason`，重复 key 时 index = null）。
- issue：`enum CapabilityVocabularyDecodeIssueCode` 13 值；`CapabilityVocabularyDecodeIssue` 有
  code / message / fatal / index / key / overlayReason 与 `toJson`；结果对象暴露 `version` / `hadBom` /
  `byteLength` / `hasFatal` / `isUsable`（无 fatal 且 overlay 非空）；issue 排序确定性：fatal 在前 →
  index 升序（文档级 null 视作 -1）→ code 枚举序 → key → message。
- 用途：导入 = 读文件文本 → `decodeCapabilityVocabularyText`，fatal 直接展示、非 fatal 逐条列
  `message + index`；导出 = `encodeCapabilityVocabularyJson`。文件 IO / 导入导出按钮 / l10n 仍未做
  （归后续词表编辑页切片）；issue message 是中文硬编码。
- 验收：新建 `test/domain/services/reasoning/capability_vocabulary_codec_test.dart` **80 例**（8 组：
  编码稳定、往返保真含中文/emoji/subjectHints、BOM/CRLF/裸数组、version 四态、未知顶层键、fatal 四类、
  条目级 issue 与 `entryRejected` 映射、`isUsable` 与排序）；`test/domain/services/reasoning`
  **+344**（264 → 344，无回归）；目录 analyze 干净。

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
| `steps[].actionType` | 非空 String | 抛错 | **未知 key 不抛错**：保留原串，`knownAction=false`（注入 lookup 后见下） |
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

**注入 lookup（轮次一百二十一）**：`parseChain` 与 `ParsedChain.fromJson` 多了可选
`lookup` 参数（默认 `CapabilityAction.byKey`，类型 `typedef CapabilityActionLookup =
CapabilityAction? Function(String actionType)`）。传 `CapabilityActionOverlay(...).catalog.byKey`
之后，自定义动作会被映射成 `CapabilityAction`：`knownAction = true` 且 `customAction = true`，
`unknownActionTypes` 为空。步骤上有了三态：

- `knownAction`：能映射到（内置或自定义）词表；
- `builtInAction` / `customAction`：映射到内置条目 / 用户条目；
- 原始 `actionType` 字符串**永远保留**；lookup 也不认识才算未知。

默认行为不变：不传 lookup 时与旧版逐字节一致（未知 key 仍保留原串、不进异常）。
注意 `ParsedStep.toJson` 里的 `knownAction` 是"解析当次按 lookup 派生"的字段：入库时没注入
lookup 就会存 `false`，读回时若注入同一 lookup 会重算为 `true`——字符串与步骤本身不丢，
只是重新判定，所以读写路径要传同一份 lookup。

结构错误（缺 `goal` / `actionType`、类型错、`stuckRisk` 越界等）的异常文案现在指认
「第 N 步（`steps[position]`，`index=X`）的 `字段`」+ 实际值，`rawSnippet` 附该步整段
JSON（例如 `"actionType": 42`），不再出现 `xxx.stuckRisk.stuckRisk` 这种重复拼接。

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
   候选动作、走人工确认流程？未定（**基础设施已备，策略未定**）：`ParsedChain.unknownActionTypes`
   可直接作为该管道的输入，`CapabilityActionOverlay` 也提供了程序化写入口（`fromJson` /
   `toJson` / key 校验 / issue 列表），缺的是持久化与 UI。
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
  → `All tests passed!`（轮次一百二十一的词表 overlay 之后：99 例。此前基线 62 例；
  本层最初交付时是 46 例）
- 轮次一百二十一的实测：`dart analyze lib/domain/services/reasoning
  test/domain/services/reasoning` → `No issues found!`；`flutter test
  test/domain/services/reasoning` → `+99: All tests passed!`

**未验证**：没有用真实模型回复跑过 `parseChain`（本机离线，不调用 provider）。
解析器的行为只由手工构造的 JSON 用例覆盖；真实输出的分布（尤其是模型自创
`actionType` 的频率）需要接入模型后统计。

## 9. 备注

`analysis_options.yaml` 采用 `package:flutter_lints/flutter.yaml` 并追加
`prefer_single_quotes`、`sort_child_properties_last`；info 级 lint 在仓库里允许存在。

## 10. 管道：从「链的对象」到「库里的一行」（Q4）

文件：`app/lib/features/questions/application/question_reasoning_service.dart`。

`QuestionReasoningService` 的两个依赖（`QuestionRepository` + `ModelAdapter?`）都是**注入**的，
不依赖 Riverpod 容器，所以测试塞一个 `FakeModelAdapter` 就能跑，不需要网络也不需要 provider override。

`solveAndDecompose(questionId, {modelId, save = true})` 的固定顺序：

1. `byId` —— 题目不存在直接返回 `notFound`；
2. `optionsOf` —— 选项按 `label. content` 顺序拼进 user 消息（label 为空时只用 content）；
3. `solveThenDecompose(questionStem: question.stem, options: …, subjectKey: question.subjectKey)`
   —— 题干**原文直传**，不摘要、不改写；
4. `adapter.runTurn(messages: …, tools: [])` —— 传**空工具表**：这一步不需要工具，给空表比给一份
   用不上的工具表更诚实（模型不会以为自己能做别的事）；
5. `parseChain` → `saveChain(source: 'ai', model: modelId)`，并把 `question.state` 置 `processed`
   （由 `saveChain` 内部完成）。

**失败一律返回结果对象、不抛异常**，四种失败态都有 `failureReason`：

| 情况 | 触发 | 是否带原文 |
| --- | --- | --- |
| 离线/未配置 | `adapter == null` | 否 |
| 模型报错 | `ModelFailure(message)` | 有（已收到的增量） |
| 回复不符合契约 | `ReasoningParseException` | 有（完整原文） |
| 题目不存在 | `byId` 返回 null | 否 |

理由：这条链路是 UI 同步等待的，抛异常意味着每个调用点都要写 try/catch，而且大概率有人把栈
直接显示给学生。

`questionReasoningServiceProvider` 把 `questionRepositoryProvider` 和 `modelAdapterProvider`
接起来；后者可以是 `null`（离线是本 App 的默认态）。

## 11. 卡点评估：模型先验 × 学生状态（Q5）

文件：`app/lib/domain/services/reasoning/stuck_point_evaluator.dart`。纯逻辑：没有数据库、没有时钟、
没有 Flutter；`nowHours`（自 Unix 纪元起的小时数）由调用方传入，与 `dsr_memory.dart` 的约定一致。

两份证据**分开存、分开暴露**，不混成一个数：

* `modelRisk`：模型声明的群体先验（`ParsedStep.stuckRisk`）——「一般学生最容易卡哪一步」；
* `stateRisk`：由 `DsrState` 算出的个体读数——「这个学生在这些知识点上现在记得怎么样」；
* `hasStateEvidence`：这一步到底有没有个体证据。**没有就明说没有**。

融合：`fusedRisk = modelWeight * modelRisk + (1 - modelWeight) * stateRisk`，`modelWeight = 0.5`。
**0.5 是刻意的**：两份证据谁更准还没有标定数据（`docs/CALIBRATION.md` 的协议还没跑过），
偏向任何一边都是无依据调参；标定跑完之前，这个常量连同它「看起来不够聪明」这一点都是正确的选择。

状态风险：`stateRisk = 0.6 * (1 - R) + 0.4 * (D - 1) / 9`，`R` 由 `DsrMemory.retrievability` 现算。
两项都留是因为「难」和「忘了」的干预手段完全不同：难要多花时间讲，忘要及时复习。

匹配规则：`knowledgeHints` 两侧 trim 后**精确**匹配状态表 key（不做模糊匹配——猜错的匹配比没有匹配
更坏）；查不到的进 `unmatchedHints` 并原样保留，**绝不当成正面证据**：把「没有数据」读成「记得很好」
是这一层最容易犯的错。

输出 `StuckPointReport`：`steps`（按步号升序）、`mostLikely`（平手取步号小的）、`byRisk`
（按融合风险降序，给「先补哪一步」排序）、`evidenceCoverage`（有证据的步数占比，UI 用它交代
这份诊断有多少依据）。

建议文案分三档（`suggestFor`）：`≥0.6` 先停下补这一步、`≥0.35` 做完用自检确认、其余可以快过；
**没有个体证据时每一档都会追加「（暂无你的状态数据）」**，而不只是高风险那一档——低风险同样可能
只是「这个学生没数据」。

注意：提示词里仍然**不含**学生画像（`§7` 开放问题 3 未定，涉及隐私设计），所以 `modelRisk` 始终是
群体先验，个体信息只在融合环节进入。

验收：`dart analyze lib/domain/services/reasoning lib/features/questions/application
test/domain/services/reasoning test/features/questions/application` → `No issues found!`；
`flutter test test/domain/services/reasoning/stuck_point_evaluator_test.dart
test/features/questions/application/question_reasoning_service_test.dart` → `+16 All tests passed!`
（评估器 9 + 管道 7）。

## 12. 能力动作画像：从「这道题卡在哪」到「我卡在哪种动作上」（轮次一百零二）

文件：`app/lib/domain/services/reasoning/capability_profile.dart`（纯逻辑）+
`app/lib/features/questions/application/capability_profile_provider.dart`（唯一 IO：读
`reasoning_steps`）+ 认知模型页的「能力动作画像」卡片。

为什么要有它：§11 的卡点评估回答的是"**这道题**这一步他能不能走下去"；但同一类动作在多道题上
反复高风险，才是"这块肌肉没练出来"。§3 已经论证过能力动作是跨学科公共词汇，所以按动作聚合出来的
画像可以直接指导下一份卷子练什么（与组卷器/找相似题共用同一个词表 key，不改 schema）。

聚合口径（三条诚实规则）：

1. **只聚合真有的读数**：`stuckRisk` 为 null 的步骤只计入条数，**不进平均**——把"模型没给判断"
   当成 0 会把风险摊薄；输出里平均风险为 null 的动作排在最后，界面显示"没有风险读数（未给判断）"。
2. **未知动作不吞**：词表里没有的 key 按原串显示（`known == false`），界面额外说明"那不是没问题，
   是这个词表还不认识它"——词表会长，静默归类会掩盖契约漂移。
3. **没有样本就说没有**：空输入返回空列表，页面显示"还没有解题链：先去题目详情页按一次「AI 解题」"，
   不编一行"暂无异常"。

排序：有平均风险的在前（沿风险降序），平手看高风险条数、再看条数、最后按展示名——即"最该练的排在最
上面"。高风险门槛沿用 §11 的 0.6（与详情页红条同一口径）。

评估结果**不落库**（派生计算，和 §11 一样）：每次从 `reasoning_steps` 现算，样本永远跟着解题链走。

验收：`test/domain/services/reasoning/capability_profile_test.dart` 7 例（归并/只信真读数/
无读数垫底/排序/未知动作原样/空输入/`toJson`）+ 认知模型页 1 例（真库两条步骤聚合出
"分类讨论：2 步，其中 1 步高风险，平均风险 0.50"，未知动作原样出现）。

**与组卷的接线（轮次一百零三）**：画像取"平均风险 ≥ 0.6"的前 3 个动作，作为组卷器的
`preferredActionTypes`；候选带着自己最新一条链的动作序列（`PaperCandidate.actionTypes`），
命中比例只**乘一个 0.15 的透明加成**（不做过滤——过滤会把"没解过链的题"整体排除，
那就不是练得准而是只练解过的题）。命中的动作写进 `PaperItem.matchedPreferredActions`，
理由行补一句"这题会练到「分类讨论」这类动作"。页面（`paperPlanProvider`）与 AI 工具
（`compose_paper`）走同一份纯函数，口径见 `docs/PAPER_COMPOSER_DESIGN.md` §11。

## 13. 动作 → 题目：按能力动作找题（轮次一百零五）

画像只回答"我最该练哪个动作"，用户看完还是得回题库自己翻。这一节把"动作 → 题目"接上：

- **读表**：`readQuestionsForCapabilities(db, CapabilityQuestionQuery(...))`（`question_corpus_reader.dart`，
  纯 Dart；单动作走简写 `readQuestionsForAction(db, actionType)`）—— 复用 `readChainActionTypes` 的
  **"只认最新一条链"**口径，筛出链上含动作的题；查询可以组合：一组动作（`requireAll` 任一 / 全部）+
  学科；排序 = 来源分级高的在前、平手按题目 id（同一份库刷两次顺序一样）；动作与学科都空返回空表
  （不把整个题库倒出来）；命中项写进 `CapabilityQuestionRow.matchedActionTypes`，与"链上有什么"分开。
- **页面**：`CapabilityActionQuestionsPage`（`features/questions/presentation/`）—— 标题用词表
  `labelZh`（词表外原样）；每行是题干 + "学科 · 来源 · 链上动作"；点一行进题目详情页（那里有
  AI 解题与卡点评估）。只读，不写任何表。
  **学科筛选（轮次一百零八）**：学科 chip 来自"这个动作下真实出现过的学科"（没出现过的学科不摆出来
  骗点击），选中后走**读表**（`questionsForCapabilitiesProvider`，与工具面同一份 `readQuestionsForCapabilities`）
  而不是在前端过滤已加载结果 —— 否则"页面上看到的"和"模型查到的"迟早分叉。`CapabilityQuestionQuery`
  是值对象（`==`/`hashCode` 按归一化后的动作集合 + 学科 + `requireAll` 比），可以直接当 Riverpod
  family 的键，页面重建不会重复读表。
  **再叠加一个动作（轮次一百零九）**：页面多一个「再叠加一个动作（可选）」下拉（词表里除入口动作外的
  所有 key），选了一个动作后出现「两个动作都得出现在同一条链里」开关 —— 下拉对应工具的 `action_type` /
  `action_types`，开关对应 `match`；清回「不叠加」时开关自动收起、`requireAll` 复位。也就是说
  **工具能问的组合查询，页面上现在都能问**（学科 × 第二个动作 × 任一/全部）。
- **入口**：认知模型页的能力动作画像每一行现在点得开（右侧有 chevron）—— 画像回答"该练哪个"，
  点开回答"练哪几道"。
- **不越界**：这一层只从**已有题库**里找题，AI 不出题（与用户口径一致）；没有链的题不会出现在
  这里，页面明说"先去题目详情页按一次「AI 解题」"。

验收：`test/features/questions/application/capability_action_questions_reader_test.dart` **5 例**
（命中/旧链不算/排序与空输入/组合查询/查询值相等）、
`test/features/questions/presentation/capability_action_questions_page_test.dart` **4 例**
（题干 + 元信息 + 点进详情页；空态；学科筛选 chip 选中后只剩该学科、能切回全部；
叠加第二个动作 + 「都要出现」收窄列表、清掉后恢复并收起开关）、
认知模型页 +1 例（画像行点得开 → 到那一页）。

**工具面（轮次一百零六，轮次一百零七扩成组合查询）**：`find_questions_by_capability`
（`features/ai/tools/question_tools.dart`，注册在 `ToolRegistry.forApp`）—— 与页面**同一份读表函数**
（`readQuestionsForCapabilities`；页面用的 `readQuestionsForAction` 是它的单动作简写），所以
"页面上查到的"与"模型查到的"不会分叉。入参：

| 入参 | 说明 |
| --- | --- |
| `action_types`（数组）/ `action_type`（单个） | 动作 key，可只给一个；词表外的 key 直接失败并列出可用值 |
| `match` | `any`（默认，命中一个就算）/ `all`（每个动作都得出现在最新链里） |
| `subject_key` | 只要这个学科；与动作组合，或单独用（"解过链的物理题"） |
| `limit` | 默认 10、上限 50 |

- 两个条件都空 → 参数错（不把整个题库倒出来）；`readOnly => true`，`ApprovalEngine` 两种权限模式下
  都不逐条询问。
- `modelResult`：`query`（归一化后的动作/学科/match + 中文名）、`returned`、`candidates`、
  `rule: 'latest_chain_only'`、`questions[]`（id、题干摘要、学科 key + 中文名、来源分级、
  **命中动作** `matched_action_types`/`matched_actions_zh`、链上全部动作 key + 中文名）。
  空结果如实说"还没有解过含这个动作的题，我不会自己出题"。
- 验收：`test/features/ai/find_questions_by_capability_tool_test.dart` **8 例**（注册与审批、未知动作、
  参数错、命中 + 只认最新链、空结果、`limit` 钳位、整库指纹只读、组合查询 any/all/学科/空条件）；
  `test/features/questions/application/capability_action_questions_reader_test.dart` **4 例**
  （含组合查询：命中项如实回报、`requireAll`、学科筛选、空条件返回空）。

## 14. 思维链洞察聚合层：从「一条链」到「我卡在哪种动作上」（轮次一百二十四）

§12 的能力动作画像回答的是「卷子该练哪个动作」，只用了单一维度（平均风险）；轮次一百二十四补一个更通用的聚合层，给未来的「学习洞察页」和统一信号模型供数。两层都是派生计算，不落库。

### 14.1 纯聚合层（`chain_insights.dart`，task-18）

文件：`app/lib/domain/services/reasoning/chain_insights.dart`（纯 Dart，无 IO）。输入是行模型：`ChainInsightChain`（chainId / questionId / steps / occurredAt）与 `ChainInsightStep`（actionType / index / stuckRisk / knownAction / knowledgeHints / occurredAt）；工厂 `ChainInsightChain.fromParsedChain` / `ChainInsightStep.fromParsedStep` 把解析器输出转成行模型。

主入口 `ChainInsights.aggregate({chains, catalog?, highRiskThreshold = 0.6})`，输出（全部不可变）：

- 总量：chainCount / stepCount / questionCount；以及**显式异常计数**：ignoredChainCount、duplicateChainCount、ignoredStepCount、duplicateStepCount、invalidRiskStepCount、clampedRiskStepCount、highRiskStepCount、highRiskChainCount——异常不静默吞掉。
- `actions`（按动作聚合：stepCount / questionCount / knownActionRatio / highRiskStepCount / highRiskQuestionCount / highRiskChainCount / averageStuckRisk? / maxStuckRisk? / lastSeenAt）、`customActions`、`unknownActions`、`neverUsedActions`（词表里有、链里没用过，按词表顺序）。
- 卡点维度：`highRiskByQuestion`、`highRiskByKnowledgePoint`（key / 高风险步数 / 题数 / 链数）。

口径（与 §12 一脉相承）：

1. `stuckRisk` 为 null / NaN / ±inf **不进平均、不插补 0**，只计入 invalidRiskStepCount；有限但越界的夹到 0..1 并计 clampedRiskStepCount。
2. 空 chainId / 空 actionType 的行进 ignored* 计数；重复 chainId、重复 step index 只留第一条并计数。
3. `known` / `custom` 始终按**当前 catalog** 重新判定，不信任行上的 knownAction 快照（旧词表写下的行可能已过期；快照为 null 时才由 catalog 推）——词表会变，读数要跟现在一致。
4. 排序确定性：动作按 stepCount desc → questionCount desc → highRiskStepCount desc → 平均风险 desc（null 最后）→ actionType asc；卡点按 highRiskStepCount desc → chainCount desc → questionCount desc → key asc。阈值非有限回退 0.6。
5. 空输入返回空结果（`isEmpty`），`neverUsedActions` 也空——「没有数据」和「所有动作都没用」不是一回事，不编数据。

验收：`test/domain/services/reasoning/chain_insights_test.dart` **58 例**（聚合计数 / 未知与自定义动作 / neverUsed / 无效与越界风险 / 卡点分组 / 排序稳定 / 空输入 / `toJson`）。

### 14.2 数据接线（`chain_insights_reader.dart`，task-21）

文件：`app/lib/features/questions/application/chain_insights_reader.dart`（纯 Dart 读表，唯一 IO）。`readChainInsightCorpus(db)` 一次读完 `reasoning_chains` + `reasoning_steps` 并投影成行模型：链按 createdAt asc → id asc，链内步骤按 idx asc → id asc；步骤的 `knowledgeHints` JSON 容错（坏 JSON / 非数组记 null 并计 invalidKnowledgeHintsSteps，非法项丢弃）；找不到所属链的步骤计 orphanStepCount，不偷偷挂到别的链；空链保留。`knownAction` 一律置 null，交给当前 overlay 词表在聚合时重判（理由同 14.1 第 3 条）。

两个 provider：`chainInsightCorpusProvider`（读表）与 `chainInsightsProvider`（读表 + 当前能力词表 overlay → `ChainInsights.aggregate`；词表读取失败退回内置词表继续，不因为偏好坏掉就看不到洞察）。

验收：`test/features/questions/application/chain_insights_reader_test.dart` **12 例**（空库 / 字段投影与 knownAction null / 链与步骤排序 / 重复 idx / 空链 / 孤立步骤 / 坏 JSON / 未知动作进 unknownActions / 自定义词表认名 / 词表失败退回）。

### 14.3 与 §12 / §10 的关系、未做

- §12 的 `capability_profile` 仍是**组卷与工具面的输入**（只取平均风险 + 已知动作），口径更窄；本节是更全的洞察读数（自定义 / 未知动作、高风险热区、从未用过的动作），面向「学习洞察」而非组卷。两者暂不合并——统一学习信号模型是候选方向，合并前不偷偷改 §12 的口径。
- 管道位置：§10 把解析结果落库 → 本节从库里多链聚合 → 未来洞察页 / 画像消费。聚合结果不落库。
- 未做：洞察页 UI / provider 未接页面；真库里 NaN / ±inf 的落库路径未实测（测试用构造数据覆盖）；与 §12 的统一信号模型未做。

### 14.4 动作 × 知识点交叉读数（轮次一百二十五，task-36）

§14.1 的卡点维度只看题目与裸知识点（高风险的 step.knowledgeHints），回答不了「我在哪个动作上、
对哪个知识点卡」。「下一步练什么」需要这种更细的坐标，所以聚合层再补一层交叉读数：

- 新增公开类 `ChainActionKnowledgePointGroup`（`chain_insights.dart`）：actionType / knowledgePointId /
  highRiskStepCount / questionCount / chainCount，`toJson` 用 snake_case。
- `aggregate` 内部按 actionType → knowledgePointId 建桶，**只统计高风险步**（stuckRisk ≥ 阈值，
  默认 0.6）且步骤的 `knowledgeHints` 非空的项；hints 去空白、去重后逐个记桶，低风险步不进交叉
  读数——把正常步摊进「卡点热区」会让人越练越偏。
- 排序确定性：highRiskStepCount desc → chainCount desc → questionCount desc → actionType asc →
  knowledgePointId asc。结果放在新字段 `highRiskByActionAndKnowledgePoint`（不可变）；`toJson`
  新增 `high_risk_by_action_and_knowledge_point` 键（纯增量，旧键全部保留，旧消费方只需容忍新键）。
- 验收：`test/domain/services/reasoning/action_knowledge_cross_test.dart` **24 例**（交叉计数 /
  低风险不计 / hints 去重 / 排序 / 空输入 / `toJson`）；reasoning 目录合计 **368 例**全绿。

## 15. 学习建议聚合层：从「读数」到「下一步做什么」（轮次一百二十五）

§12 的能力动作画像回答「卷子该练哪个动作」，§14 的洞察层回答「我卡在哪种动作上」；本节把这两层**读数**翻成一份确定性的建议清单，给未来的「学习洞察 / 首页下一步」供数。只读派生，不落库、不调模型——建议由规则算出来，可复现、可测。

### 15.1 纯聚合层（`learning_advice.dart`，task-24）

文件：`app/lib/domain/services/reasoning/learning_advice.dart`（纯 Dart，无 IO；只依赖 `chain_insights.dart` 与 `capability_profile.dart`）。主入口：

```dart
static LearningAdvicePlan build({
  required ChainInsights insights,
  List<CapabilityReading> profile = const <CapabilityReading>[],
  int highRiskMinSteps = 3,
  int maxAdvices = 5,
  int? corpusQuestionCount,
})
```

`LearningAdviceKind` 五种（枚举顺序即同类建议的排序兜底）：`practiceAction` / `collectChains` / `reviewVocabulary` / `keepGoing` / `noData`。每条 `LearningAdvice` 带 kind、priority（越小越靠前）、titleZh / detailZh，以及**能填就填的真实读数**（actionType / actionLabelZh / questionCount / stepCount / highRiskStepCount）；`knowledgePointIds` 来自动作 × 知识点交叉读数（§14.4；仅 practiceAction 填，每动作最多 3 个，高危步数降序、同数按 id 升序；无读数保持空列表，不编造）。

优先级分段：practice 从 100 起（多条按高风险步数降序编 100、101…，到 199 为止），collect 200，review 300，keep 400，noData 500；最终按 priority → kind 枚举序 → actionType 字典序 → titleZh 稳定排序，再按 maxAdvices 截断（<1 按 1 处理；截断取排序后的前缀，截断后 `isEmpty` 仍为 false）。

生成规则（诚实性优先）：

1. 练习建议只给**真读数**：洞察里 known 且 highRiskStepCount ≥ highRiskMinSteps 的动作；能力画像作为补充证据（known、riskyStepCount 达阈值且洞察里没出现过的动作，此时 questionCount 如实留空）；未知动作永远不进练习建议。阈值 <1 按 1 处理。
2. 未知动作不吞：`unknownActions` 非空时给一条 reviewVocabulary，detail 列出最多 5 个**原串**并说明总数，明说「词表还不认识它们，不是没问题」。
3. 没数据不说：只有调用方传了 `corpusQuestionCount` 且题库题数 > 洞察覆盖题数时才产出 collectChains（写清缺口）；不传题数就不猜「有题缺链」；没有任何读数且没有缺口时给一条 noData（题库 0 题与没传题数的文案分开）。
4. 不落库、不调模型：建议清单每次从读数现算，链 / 步骤写入后由上层重新聚合即可刷新。

`LearningAdvice.toJson` 与 `LearningAdvicePlan.toJson`（advice_count / is_empty / advices）供未来落 JSON 快照或测试断言；列表均 unmodifiable。

验收：`app/test/domain/services/reasoning/learning_advice_test.dart` **48 例**（枚举与序列化 / 空输入与 noData / 练习阈值 / 画像补充 / collect 缺口 / review 词表外动作 / keepGoing / 排序与截断 / NaN 与 ±inf 不参与）。

### 15.2 未做

- 洞察页 UI 与 provider 未接页面（目前只有纯函数，调用点等界面 / 首页「下一步」设计定稿）。
- 未接 AI 对话：建议只走确定性规则；「哪个动作先练」的权重标定需要真数据后再做，当前不假装个性化。
### 15.3 动作 × 知识点交叉读数接线（轮次一百二十五，task-36）

- `LearningAdvicePlan.maxKnowledgePointIds = 3`（public const）；`_practiceCandidates` 内按 actionType
  从 §14.4 的交叉读数取知识点（高危步数降序、同数按 id 升序、截断 3），洞察与画像两类候选共用
  同一函数；`LearningAdvice.knowledgePointIds` 只对 practiceAction 非空，其他 kind 与无读数时仍空。
- 验收：`action_knowledge_cross_test.dart` **24 例**（practice 填点 / 截断 / 排序 / 无读数空 /
  非 practice 不填）；`learning_advice_test.dart` 48 例回归；reasoning 目录 **368 例**全绿。
- 未做：界面还不显示这些知识点（只有 id，要显示名称得再读一层 knowledge_points 标题）。
## 16. 接线：学习建议 provider 与题库题数（轮次一百二十五）

### 16.1 数据接线（`learning_advice_provider.dart`）

文件：`app/lib/features/questions/application/learning_advice_provider.dart`（纯拼装，无业务口径）。

- `questionCorpusCountProvider`：对 `questions` 做一次真实 `COUNT`，并 `ref.watchDatabaseRevision()`，
  收题 / 删题后立即重算；空库返回 0。
- `learningAdviceProvider`：依次取 `chainInsightsProvider`（known 已按**当前**词表 overlay 重判，
  这里不再重复读词表）、`capabilityProfileProvider`（§12 口径，只读 `reasoning_steps`，因此
  孤立步骤也能进画像）与题数，调用 `LearningAdvicePlan.build` 的默认参数（阈值 3 步、最多 5 条）。
- 顺带补上刷新：`chainInsightCorpusProvider` 也 watch 数据库修订号——之前它只在首次读取后缓存，
  新落的链要重启才出现在洞察里；现在链 / 步骤写入后洞察与建议一起刷新。
- 诚实性延续：题数**只**用于判断缺口。洞察覆盖 0 题时文案是「但当前还没有任何解题链」；
  部分覆盖时写「当前洞察只覆盖 X 道题，还有 Y 道题没有解题链」；只有画像补充的练习建议
  `questionCount` 留空（不虚构题数）；未知动作仍不吸收进练习建议。

### 16.2 验收与未做

- 验收：`test/features/questions/application/learning_advice_provider_test.dart` **10 例**
  （题数空库 / 收题后变化；noData 不虚构题数 / 收集链缺口（全部没链与部分覆盖两种文案）/
  3 步高风险给练习且题数来自洞察 / 阈值不足返回 keepGoing / 词表外动作 reviewVocabulary /
  overlay 自定义动作算已知后进练习 / 只有画像（孤立步骤）也给练习且题数留空）；
  `chain_insights_reader_test.dart` 12 例回归通过。
- 未做：页面 UI（首页「下一步」或学习洞察页）与建议卡片未接；建议不落库、不做历史对比；
  阈值与条数**未标定**（等真实使用数据再调）；知识点只填了 id，界面尚未展示。

### 16.3 学习洞察页数据 provider（`learning_insight_provider.dart`，轮次一百二十五）

页面 UI 归 question-intake；这一层只把页面要的四份数据拼成一次快照，没有任何新口径。

- `learningInsightDataProvider`（`FutureProvider<LearningInsightData>`）：`ref.watchDatabaseRevision()`
  后依次取 `chainInsightsProvider`、`learningAdviceProvider`、`capabilityActionOverlayProvider`，
  再按需读知识点标题。词表读取失败时退回 `CapabilityActionOverlay.empty` 并把
  `vocabOverlayFallback` 置 true——用户自定义词表坏掉只影响 known / custom 判定，不该让整页打不开。
- 知识点标题：只查 `advice.knowledgePointIds ∪ insights.highRiskByKnowledgePoint.key
  ∪ insights.highRiskByActionAndKnowledgePoint.knowledgePointId` 里出现的 id（trim 去空、去重），
  空集合**不发查询**；公开 helper `readKnowledgePointTitles(AppDatabase, Set<String>)` 只返回
  title 非空的 id。读不到的 id 不在表里，界面回退显示 id（`titleOf` 兜底），不编造名称。
- `LearningInsightData` 派生视图（都为不可变 List / Map）：`actionRows`（动作行：label、known、custom、
  步数、题数、高风险步数、平均风险、最近时间，风险缺失为 null 不插补 0）、`unknownRows`、
  `neverUsedActions`、`stuckRows`（知识点卡点热区，中文名已读好）、`actionKnowledgeRows`（动作 × 知识点交叉卡点）、
  `adviceCards`（建议卡 + 知识点中文名列表）、`actionCatalog`；空态：`hasActivity` /
  `isEmpty` / `hasUnknownActions` / `hasKnowledgePointGaps`。排序全部沿用 `ChainInsights` 的确定性顺序，
  这里不重排。
- 验收：`test/features/questions/application/learning_insight_provider_test.dart` **12 例**
  （空库 noData、有题没链建议收链、孤立步骤不算活动；高风险动作进练习且平均风险按读数、无读数不插补 0、
  动作顺序沿用洞察层、未知动作单列并建议补词表；知识点中文名进卡点 / 交叉 / 建议、缺失 id 回退、
  `readKnowledgePointTitles` 只返回存在的 id 且空标题丢弃；overlay 自定义动作认名、overlay 读取失败标记 fallback），
  跑出 `+12 All tests passed`；`dart analyze` 两个文件 `No issues found`。
- 未做：学习洞察页 UI 与入口（下一片 question-intake）、「从未用过的动作」的展示样式、真库大数据滚动性能。

## 17. 词表编辑的 application 层（轮次一百二十五）

文件：`app/lib/features/questions/application/capability_vocabulary_editor_provider.dart`（Lead 交付）。

- `CapabilityVocabularyEditorState`：`overlay`（草稿）、`savedOverlay`（上次载入 / 保存的快照）、
  `issues`（最近一次被拒的条目）、`isSaving`；派生 `customActionCount`、`isDirty`（按条目逐字段
  深比较——`CapabilityActionOverlay` 没有 `==`）、`hasIssues`、`firstIssueMessage`。
- `CapabilityVocabularyEditor`（`AsyncNotifier`）：`build` 用 `CapabilityVocabularyStore.load()` 初始化；
  `add` / `updateAction` / `remove` / `reorder` / `importJson` 全部转发纯逻辑编辑层
  （`capability_action_overlay_editor.dart`），失败只写 `issues`、不动 overlay；`clearIssues`；
  `save`（写库 → `ref.invalidate(capabilityActionOverlayProvider)` → `savedOverlay` 前移；
  `isSaving` 防重入；未 dirty 直接返回、不建库行；写失败复位 `isSaving` 后原样抛出，草稿保留）；
  `revert` 回 `savedOverlay`。
- 命名坑：方法**不能叫 `update`**——`AsyncNotifier` 已有 `update(回调)` 方法，重名会编译失败；
  所以叫 `updateAction`。
- 不用 autoDispose：用户在编辑页切走再回来，未保存的草稿不该被静默丢掉；也**不做自动保存**
  ——词表直接决定诊断口径，必须由用户点「保存」才算数。
- 验收：`test/features/questions/application/capability_vocabulary_editor_provider_test.dart` **20 例**
  （载入出厂 / 已有条目不 dirty；add 合法与内置 key、非法 key、缺中文名、重复、100 条上限六类拒绝；
  update 保留未传字段 / 空中文名 / 找不到 key；remove 成功与 keyNotFound；reorder 换位、移回原位、
  空操作、越界；importJson 部分成功（重复 + 非法各一条 issue）与形状不识别；成功编辑清掉上一条 issue；
  clearIssues；save 写库 + dirty 变 false + 推理链路 invalidate 后读到新词表；删光保存写回 NULL；
  无改动 save 不建库行；revert 放弃草稿；save 失败 isSaving 复位且草稿保留）；跑出 `+20 All tests passed`；
  `dart analyze` 两个文件 `No issues found`。
- 编辑页 UI 与 l10n 已做（§19，轮次一百二十五 task-29）。
- 未做：词表导入的 `.json` 文件选择（file_picker + `jsonDecode`）仍留在 UI 层未接；不做跨设备同步。

## 18. AI 工具：下一步练什么（轮次一百二十五）

§14/§15/§16 的读数与建议原本只活在 provider 里，这个切片把它们接到 AI 对话的工具层：

- 文件：`app/lib/features/ai/tools/learning_advice_tools.dart`，类 `GetLearningAdviceTool`；
  注册在 `tool_registry.dart`（`GetLearningAdviceTool(db: db)`）。工具名 `get_learning_advice`。
- 参数：`max_advices`（默认 5、上限 10，超上限钳制、<1 抛 `ToolArgError`）、
  `high_risk_min_steps`（默认 3、上限 20，<1 抛错）。非法值用中文报错并写清当前值。
- 管道与页面**同源**：`CapabilityVocabularyStore(SettingsRepository(db)).load()` 取当前词表 overlay →
  `readChainInsightCorpus(db)` → `ChainInsights.aggregate(chains, catalog: overlay.catalog)`；
  另用 `QuestionRepository(db).allReasoningSteps()` 喂 `CapabilityProfile.of`，并用一次
  `COUNT(questions)` 得题库题数；最后 `LearningAdvicePlan.build`（阈值与条数由参数覆盖）。
  全部只读，不写库、不调模型。
- 摘要口径：noData 时直接给「还没有学习数据——…先去题库加题…」；有建议时先说第一条
  「下一步建议：标题——理由（共 N 条，完整的在 result 里）」。`modelResult` 含
  `corpus_question_count` / `reasoning_step_count` / `insights`（链数/步数/题数/高风险步数/自定义与未知动作数/
  异常计数）/ `thresholds` / `plan`（建议清单）/ `note`（确定性、阈值未标定、只作行动提示）。
- 只读声明：`readOnly => true` + `riskFor` 返回 write + `reversibleFor => true`，与 `compose_paper` /
  `audit_question_intake` 同款，审批引擎不会逐条询问只读查询。
- 验收：`app/test/features/ai/learning_advice_tools_test.dart` **10 例**（空库 noData、3 步高风险练习建议排第一、
  2 步不足阈值 keepGoing、阈值可调、未知动作 reviewVocabulary、题数缺口 collectChains 如实说还差几道、
  overlay 自定义动作被认作已知动作、max_advices 钳制与非法参数、工具声明/schema、只读跑完行数不变）。
- 未做：建议卡片 UI（首页「下一步」/学习洞察页）仍归 presentation；工具不落库、不做历史对比；
  阈值与条数未标定；`knowledgePointIds` 已由 §14.4/§15.3 填真实交叉读数（工具输出里也会带上）。

## 19. 词表编辑页 UI：设置页「能力动作词表」（轮次一百二十五，task-29）

§17 的 application 层原本没有入口。这一节把它接成设置页里的一页（question-intake 交付）：

- 入口：`settings_page.dart` 在「认知模型」之后加一个 ListTile（`app/lib/features/settings/presentation/`），
  点进 `CapabilityVocabularyPage`。
- 页面（`capability_vocabulary_page.dart`，约 800 行）：内置动作只读分组（key + 中文名 + 说明，
  不能改 — 内置词表是诊断口径的地基）；自定义条目分组可新增 / 编辑 / 删除 / 上移 / 下移；
  底部保存栏（dirty 时显示、含「放弃」与「保存」）；顶部提供「粘贴 JSON 导入」。
  `PopScope` 拦截退出：有未保存改动时弹二次确认（留下 / 放弃），不静默丢草稿。
- 错误如实回显：编辑层 / 导入层的 issues（非法 key、缺中文名、重复、超 100 条、导入形状不识别）
  显示在 issues 卡片里，可逐条关闭；保存失败 SnackBar 带**错误原文**，页面保留未保存状态。
- 一个真实 bug 的教训：粘贴 JSON 对话框最初在 `showDialog` 返回后立刻 dispose 控制器，
  路由退场动画期间 TextField 重建 → `A TextEditingController was used after being disposed`，
  导致后续 7 个测试连锁失败；现在 `_ImportJsonDialog` 自己用 State 持有控制器。
- l10n：34 个 key（前缀 `capabilityVocabulary`）手改进五个文件（含 7 个带参 key）；未跑 `gen-l10n`。
- 验收：`test/features/settings/presentation/capability_vocabulary_page_test.dart` **13 例**
  （内置只读 / 空自定义 / 种子渲染 / 新增 / 编辑 / 删除 / 上移下移 / JSON 语法错误 / 语义非法进 issues /
  保存成功写库 / 保存失败保留未保存态 / 加载失败错误态 / 设置页入口 / 退出二次确认），
  `test/features/questions/presentation` **173 例**回归；`dart analyze lib test` 92 issues / 0 error /
  0 warning（基线）。
- 未做 / 未验证：真机滚动与键盘、`PopScope` 与 Android 返回手势真机行为、导入大 JSON 的性能、
  en 文案母语校对；导入 .json **文件**（file_picker）仍未接，目前只能粘贴文本。

## 20. 思维链质量体检：ChainQualityAudit（轮次一百二十五，task-40）

§14 的洞察聚合回答「整体上哪些动作 / 知识点在卡人」，§15 的学习建议回答「接下来练什么」，
但它们都信任落库数据本身。这一节补的是单条链的可信度体检：把 `ParsedChain` 的字段
（动作 key、卡点读数、推导依据、验算方式、知识点提示）转成确定性的 findings，
供详情页 / 洞察页后续展示「这条链哪里可疑」。纯逻辑，不读库、不写库，数据读取与 UI 由后续接线。

### 20.1 文件与 API

`app/lib/domain/services/reasoning/chain_quality.dart`（882 行）：

- `enum ChainQualitySeverity { error, warning, info }`（`labelZh` 分别为 错误 / 警告 / 提示，`:29`）。
- `abstract final class ChainQualityCodes`（`:50`）：19 个 `static const String` code + `all` 列表（`:116`），
  定义顺序即文档顺序，code 与严重级的映射见 §20.2。
- `class ChainQualityStepInput`（`:141`）：`{required String actionType, required int index,
  double? stuckRisk, bool? knownAction, String? justification, String? checkMethod,
  List<String> knowledgeHints = const []}`。
- `class ChainQualityChainInput`（`:179`）：`{required String chainId, required String questionId,
  List<ChainQualityStepInput> steps = const []}`。
- `class ChainQualityFinding`（`:198`）：`code / severity / messageZh / questionId / chainId / stepIndex? / evidence`，
  `evidence` 不可变；`toJson()`（`:232`）输出 `code / severity / severity_label_zh / message_zh /
  question_id / chain_id / step_index / evidence`（evidence 键字典序）。
- `class ChainQualityReport`（`:255`）：`chainCount / stepCount / findings / countsBySeverity /
  countsByCode / truncatedCounts / maxFindingsPerCode`，getter `isClean`（`:307`）、
  `isTruncated`（`:310`）、`totalFindingCount`（`:313`）、`findingsFor(code)`（`:322`）、
  `toJson()`（`:332`，snake_case，counts 键排序）；`factory ChainQualityReport.empty()`（`:271`）。
- `abstract final class ChainQualityAudit`（`:360`）：
  `static ChainQualityReport audit(List<ChainQualityChainInput> chains, {CapabilityActionCatalog? catalog,
  int minSteps = 3, double highRiskThreshold = 0.6, int maxFindingsPerCode = 50})`（`:383`）；
  常量 `defaultMinSteps = 3`、`defaultHighRiskThreshold = 0.6`、`defaultMaxFindingsPerCode = 50`、
  `unknownActionRatioThreshold = 0.5`。

### 20.2 判据表（19 条）

| code | 严重级 | 触发条件 |
| --- | --- | --- |
| `empty_chain` | error | 空链（steps 为空）；只报这一条并返回 |
| `too_few_steps` | warning | steps.length < minSteps（minSteps 小于 1 按 1） |
| `empty_chain_id` | error | chainId trim 后为空 |
| `empty_question_id` | warning | questionId trim 后为空 |
| `empty_action_type` | error | 某步 actionType trim 后为空 |
| `unknown_action_ratio_high` | warning | 未知动作步数 / 总步数 严格大于 0.5，且至少 1 个未知 |
| `no_known_action` | warning | 非空链里没有任何已知动作 |
| `high_risk_missing_justification` | warning | 高危步 justification trim 后为空 |
| `high_risk_missing_check_method` | warning | 高危步 checkMethod trim 后为空 |
| `no_risk_reading` | warning | 整链没有任何有限卡点读数（链级，理由见 §20.3） |
| `duplicate_step_index` | error | 同链 index 重复，第 2 次起每条 |
| `invalid_step_index` | error | index < 0 |
| `non_contiguous_step_index` | warning | 唯一非负 index 排序后出现缺号（允许从任意值起连续），每链最多一条 |
| `single_action` | info | 步数 >= 2 且全部非空 actionType 相同 |
| `consecutive_duplicate_action` | info | 相邻两步非空 actionType 相同（每条） |
| `missing_knowledge_hints` | info | 该步 knowledgeHints trim 后全空（每条） |
| `invalid_risk_reading` | error | stuckRisk 是 NaN 或 ±inf |
| `risk_out_of_range` | warning | 读数有限但越出 0..1（先报本条，再夹取判高危） |
| `stale_known_action_flag` | info | 落库快照 knownAction 与按当前词表重判结果不一致 |

### 20.3 口径

- 已知动作判定：`catalog != null` 用 `catalog.isKnownKey`（trim 后），否则退回内置
  `CapabilityAction.isKnownKey`；因此不传 catalog 时自定义动作会被判未知，接线时应传 overlay 合并后的 catalog。
- 高危定义：有限且夹到 0..1 后的 stuckRisk >= 阈值；只有高危步才检查 justification / checkMethod 是否为空。
- 越界 / 非法读数：NaN、±inf → `invalid_risk_reading`，不参与高危、不计入有限读数；
  有限越界报 `risk_out_of_range` 后夹到 0..1 再判高危。
- 「高危步无读数」在定义上自相矛盾（没有读数就无法判高危），所以改为链级 `no_risk_reading`：
  整链没有任何有限读数时触发。
- 空 actionType 显式报错，不当成普通未知动作静默统计；它只出现在未知判定里会稀释占比口径。
- 参数净化：minSteps < 1 → 1；阈值 NaN / ±inf → 0.6，其余夹 0..1；maxFindingsPerCode < 1 → 1。
- 排序：先按 (trim 后 questionId, trim 后 chainId, 原始输入顺序) 稳定排序链；findings 全局按
  questionId → chainId → stepIndex（null 最后）→ 严重级（error < warning < info）→ code → messageZh
  → evidence 序列化排序，保证同输入输出确定。
- 截断：countsByCode / countsBySeverity 统计截断前真实数量；每个 code 按排序后顺序保留前
  maxFindingsPerCode 条，其余计入 truncatedCounts；totalFindingCount = 截断前总数；
  report.findings / findingsFor 返回不可变列表。
- 文案口径：messageZh 只陈述读数与字段事实，不出现「可能 / 大概 / 建议」这类推测与建议措辞
  （练习建议归 §15，不在这里生成）。

### 20.4 验收

- `app/test/domain/services/reasoning/chain_quality_test.dart`（1092 行）**51 例**，分 5 组：
  严重级与 code 表 4 / 链级判据 17 / 步级判据 13 / 参数、截断与空报告 9 / 确定性与排序 8。
- `dart analyze lib/domain/services/reasoning test/domain/services/reasoning` → No issues found!；
  `flutter test test/domain/services/reasoning` → **419 例全绿**（基线 368 + 新增 51）。
- 确定性：同输入两次调用 `toJson()` 的 JSON 逐字节相等；输入链顺序颠倒不改变 JSON（内部先排序归一）。

### 20.5 未做 / 未验证

- 数据读取已接（轮次一百二十五，`features/questions/application/chain_quality_reader.dart`）：
  一次全库读 `ReasoningChains` / `ReasoningSteps` 投影成 `ChainQualityChainInput`（`knownAction` 无落库快照，
  统一传 null 让体检层按当前词表重判；空 justification / checkMethod 读作 null；坏 `knowledgeHints` 计
  `invalidKnowledgeHintsSteps` 读作空），提供 `chainQualityReportProvider`（全库）与
  `chainQualityForQuestionProvider`（单题，题目详情页用）；词表读取失败退回内置词表继续体检。
  详情页 / 洞察页展示、修复建议生成、阈值标定均未做。
- 真实历史库里 stuckRisk 出现 NaN / ±inf 的落库路径未实测；knownAction 快照与当前词表大规模漂移后的
  误报率未标定。
- `catalog` 为 null 时退回内置词表的兼容行为保留（既有调用方不传 overlay 不会被新判据改变），
  但自定义动作会被判未知——接线时必须传合并后的 catalog。

