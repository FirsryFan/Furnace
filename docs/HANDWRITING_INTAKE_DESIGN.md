# 拍照 → 四类待确认产物（手写整理）

`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4 的落地设计。一句话：**一张手写照片进来，
一份提案出去，用户点过之后才写库。**

轮次一百二十八把产物从三类扩到四类（加了**题目**）：照片里的题干、选项、答案、解析
本来就该能直接变成一道题库里的题，而不是让用户抄一遍。

## 1. 它做什么 / 不做什么

做什么：

- 从磁盘上已经存在的照片（`HandwritingIntakeStore.pending()` 里那些 `relPath`）出发，
  把「图 + 铁律 + 现在库里有什么」一起递给视觉模型；
- 把模型回复解析成结构化提案：**标签 / 知识点 / 闪存卡 / 题目**四类；

题目这一类的边界（用户口径 m05023）：**题面必须来自照片**，模型只誊写不改写、不补全缺失
选项、不做题；识别不清就降 `confidence`，宁可不给也不编。
- 用户逐个（或整批）确认后，按下面 §3 的规矩真正写库。

不做什么（每条都有理由，不是"还没做"）：

| 不做 | 为什么 |
|---|---|
| 不在整理阶段写任何东西 | §7.4「确认前不写库」。`proposeFor` 只读磁盘与库，测试用写库计数证明 |
| 不做"部分成功"的静默降级 | 提案解析**严格**：结构性错误一律抛 `HandwritingProposalParseException`。少写一条而用户以为整理完了，比直接报错更糟 |
| 不自己造标签树 | 父路径不存在 → 只报这一条。标签树是几个系统共用的语言（见 `docs/QUESTION_BANK_DESIGN.md` §5），凭空加一层会让别人的路径分类失效 |
| 不做兜底猜测 | 图片格式认不出来就说"认不出"；模型没配就说"没有可用的模型适配器"；照片不在了就说"照片不在了" |
| 本轮不持久化提案 | 见 §4 |

## 2. 输入 / 输出契约

### 领域层 `app/lib/domain/services/intake/handwriting_proposals.dart`

纯 Dart（唯一外部依赖是 `ChatMessage`，先例：`reasoning_prompt.dart`），不碰 Riverpod、
不碰数据库。

| 符号 | 形状 |
|---|---|
| `HandwritingProposalKind` | `tag('tag','标签')` / `knowledgePoint('knowledge_point','知识点')` / `flashcard('flashcard','闪存卡')` / `question('question','题目')`，带 `storageKey` / `labelZh` |
| `HandwritingProposal` | `id`（确定性 `'${kind.storageKey}-$index'`）、`kind`、`titleZh`、`rationaleZh`、`confidence`、`fields: Map<String,String>`、`cards`、`options`（只有题目用）、`sourceRef` |
| `HandwritingOptionDraft` | `label`（A–Z，trim + 大写后必须单字母）、`content`（非空）；JSON 解析的错误里带字段路径（`options[1].label`） |
| `HandwritingCardDraft` | `question`、`answer`、`type`（缺省 `essay`，只认 `fill_blank` / `mcq` / `essay`） |
| `HandwritingProposalSet` | `sourceRef` + `proposals`，`isEmpty` / `countOf(kind)` |
| 缺省置信度 | `defaultProposalConfidence = 0.5`——模型没说就是"不知道"，不是"很确定" |
| `handwritingProposalMessages(...)` | 返回 `[system, user]`：system 写铁律 + JSON 契约 + 已有标签路径/知识点标题（各最多 60 条，超出注明省略数），user 带 `ChatImagePart` |
| `parseHandwritingProposals(raw, {sourceRef})` | 取最外层 `{...}`（容忍 ```json 代码块与前后寒暄），空 `proposals` 合法 |

必填字段（缺了就是异常，异常文案直接给用户看）：

| kind | 必填 |
|---|---|
| `tag` | 无（可选 `fields.parent_path`） |
| `knowledge_point` | `fields.content` |
| `flashcard` | `fields.content` + `cards` 非空（每张卡要 `question` + `answer`） |
| `question` | `fields.stem`（题面必须来自照片，不能留空） |

### 应用层 `app/lib/features/questions/application/handwriting_proposal_service.dart`

| 符号 | 作用 |
|---|---|
| `HandwritingProposalService.proposeFor(relPath)` | 读照片 → 认格式 → 调模型 → 解析。返回 `HandwritingProposalRun{ok, set, failureReason, rawReply}`，**从不抛异常** |
| `HandwritingProposalService.applyAll(set, {onlyIds})` | 只写被确认的那些提案，返回 `HandwritingApplyReport{outcomes, appliedCount, failedCount, allOk, appliedIds}` |
| `HandwritingQueueState` | 队列状态：`images` / `sets` / `failures` / `analyzing` / `applying` / `appliedIds` / `lastReport`；`isApplied(relPath, proposalId)` 的键是 `'$relPath#$proposalId'` |
| `HandwritingQueueNotifier` | `refresh()`（读磁盘清单 + 从库里恢复提案与确认状态；照片已不在磁盘的整理记录顺手清掉）、`analyze(relPath)`（成功后写库）、`applyProposal(relPath, proposalId)`、`applyAll(relPath)`、`forget(relPath)`（库里删掉整理记录，**照片本身不动**） |
| `handwritingProposalServiceProvider` | store / tags / anki 来自既有 provider，adapter 来自 `modelAdapterProvider` |
| `handwritingProposalRepositoryProvider` | `HandwritingProposalRepository(ref.watch(appDatabaseProvider))`（schema v13） |
| `handwritingQueueProvider` | `NotifierProvider<HandwritingQueueNotifier, HandwritingQueueState>` |
| `HandwritingProposalService.questionDraftForIntake(proposal)` | 只**装配**题目草稿、不写库：题干空返回 `null`（不查标签），否则解析 `tag_path` 填 `tagIds`，交给收题页表单预填（轮次一百二十八） |
| `HandwritingQueueNotifier.markAppliedLocally(relPath, proposalId)` | 用户在收题页手动入库后只标"已确认"，不写第二遍（`HandwritingProposalRepository.markApplied` + 内存 `appliedIds`） |

### 数据层（schema v13）

| 表 | 列 |
|---|---|
| `handwriting_intake_runs` | `source_ref`（PK，照片相对路径）、`analyzed_at`、`raw_reply?`、`created_at`。**零提案也留一行**——「整理过但照片里没东西」重启后不能退回「没整理过」 |
| `handwriting_proposals` | `id`（PK = `<source_ref>#<proposal_id>`）、`source_ref`、`proposal_id`、`sort_index`（不按 id 排，否则字典序把三类产物打散）、`kind`、`payload_json`（`HandwritingProposal.toJson()` 文本）、`applied_at?`（NULL = 未确认）、`created_at` / `updated_at` |

`HandwritingProposalRepository`（`app/lib/data/repositories/handwriting_proposal_repository.dart`）：

| 方法 | 口径 |
|---|---|
| `saveRun({set, analyzedAt, rawReply})` | 一张照片只有一条 run：删旧行再写新行。**按 `payload_json` 逐字相同的那几条保留 `applied_at`**，其余清成 NULL |
| `runs()` / `runOf(sourceRef)` | run 行按 `analyzed_at` 倒序；提案行按 `sort_index` 正序；还原走领域层 `fromJson`（JSON 契约只有一份） |
| `markApplied({sourceRef, proposalId, appliedAt})` | 只更新 `applied_at IS NULL` 的行——用户手滑点第二次不改第一次的时间 |
| `deleteRun(sourceRef)` / `deleteAll()` | 删提案 + run 行；**照片不动** |

`applied_at` 为什么按"逐字相同"保留：重新整理得到的新提案里，内容逐字没变的那条就是用户
确认过的同一条（还清掉就变成"没确认过"，再确认一次会写出第二份知识点）；内容变了的则是
**新版本**，用户没确认过它，确认状态必须清掉。

`handwritingIntakeStoreProvider` 与 `questionIntakeSupportDirectoryProvider` 这一轮从
`question_intake_providers.dart` 搬到了应用层（整理服务与收题页共用同一个 store），
presentation 侧用 `export` 保住了原来的 import 路径。

## 3. 四类产物各怎么写库

| 产物 | 写什么 | 规矩 |
|---|---|---|
| 标签 | `TagRepository.createTag(name:, parentId:, description:)` | 父路径必须**已经存在**；已经存在就直接采用（detail 里说明"没有新建"）；父路径不存在 → 这一条失败，别的条照写 |
| 知识点 | `AnkiRepository.createKnowledgePoint(title:, content:, source: 'handwriting_intake')`，再可选 `addTagToObject(objectType: 'knowledge_point')` | `tag_path` 不存在时**点照建、只是没挂边**（detail 说明）——点本身是用户确认过的内容，比一条边重要 |
| 闪存卡 | 先建知识点，再每张卡 `createTemplate(...)`，**然后逐张 `getOrCreateCardState(template.id)`** | 没有卡状态的模板在复习队列里不存在（同 `features/ai/tools/knowledge_tools.dart` 里那条注释），"建了卡但复习里看不到"等于没建 |
| 题目 | `QuestionRepository.ingest(QuestionDraft(...))`：`sourceLabel: '拍照整理'`、`origin: 'ai_scan'`、`state: 'structured'`，选项转 `QuestionOptionDraft`，答案里的字母（`B` / `A、C` / `AC`）认成正确项 | `fields.stem` 空 → 这一条失败；题干指纹命中已有的题 → 返回 `created: false`，detail 写"题库里已有同题干的题目 TR-xxxxx，没有重复入库"；`tag_path` 不存在 → 题照建、只提示没挂边 |

三条横向规矩：

1. **一条失败不影响其它条**：单条异常被收成 `HandwritingApplyOutcome(ok: false, failureReason: '写库失败：…')`；
2. **确认过的不再写第二份**：`applyProposal` / `applyAll` 对已确认 id 返回 `null`，不重复建；
3. **写库只在确认之后**：`proposeFor` 与 `analyze` 都不落库。

## 4. 刻意未做 / 已知缺口

- ~~**提案只存在内存里**~~ → 已补（schema v13，见上表）：提案与"已确认到哪一条"落在
  `handwriting_intake_runs` + `handwriting_proposals` 两张表里，重启后 `refresh()` 恢复。
  界线仍然清楚：**这三张表只存提案与确认状态，标签 / 知识点 / 闪存卡仍然只在用户点确认
  之后才写**——"确认前不写库"说的是学习数据，不是"待确认清单"。
- **一次只整理一张照片**：提示词只带一张图；多页连拍 / 一次多图未做。**收题页的拖拽入口
  可以一次放多张照片**（轮次一百二十一），但那是"批量放进待整理队列"（每张各存一个
  `handwriting_intake_runs`），整理仍是逐张整理。
- **图片格式靠扩展名**（`HandwritingIntakeStore.mimeForName`）：认不出直接报"认不出…"。
  轮次一百二十一之后 `mimeForName` 委托给 `lib/data/media/image_mime.dart` 的
  `imageMimeForName`（扩展名白名单：jpg/jpeg/png/gif/webp/heic/bmp，大小写不敏感）；
  拖拽入口另有**前 12 字节魔数兜底**（PNG/JPEG/GIF/WEBP/BMP/HEIC-HEIF，见
  `drop_intake_filter.dart`），无扩展名的微信临时文件也能认出。手写整理这条主路仍只按
  扩展名——文件已经在 store 里，路径与 mime 落库时已定。
- **UI 已交付**（Q15，`63e04f0`）：`app/lib/features/questions/presentation/question_intake_page.dart` +
  `handwriting_queue_page.dart`；`refresh()` 现在还会从库里把整理结果读回来。
- **OCR 质量取决于模型**：解析严格意味着模型跑偏时用户看到的是"回复不符合契约"+原文，
  而不是一份残缺提案——这是有意的。
- **题目卡片的编辑入口还没接**（task-70，进行中）：`questionDraftForIntake` 已能装配草稿，
  队列卡片上点"改一下再存"回填收题页表单、保存后 `markAppliedLocally` 标已确认——UI 与
  l10n 由 question-intake 接力。
- **确认前的预检还没接**（task-71，进行中）："这条会新建还是复用""挂在哪个标签下"
  "为什么不能确认"目前只散落在确认后的 detail 里；预检纯逻辑（`handwriting_proposal_preview.dart`）
  由 reasoning-core 交付后，队列卡片会在确认按钮前先给出目标路径与阻断原因。

## 5. 验收记录

2026-10-16（Lead）：

- `app/test/domain/services/intake/handwriting_proposals_test.dart`：11 例——提示词铁律
  （"照片里没有的不许写"）、把已有标签路径/知识点标题带进提示词、超 60 条截断、
  解析严格性（坏 kind / 缺 title / fields 非对象 / 卡片缺字段 / 非法 type / 非闪存卡带 cards）、
  `confidence` 缺省 0.5 与越界钳位、id 确定性。
- `app/test/features/questions/application/handwriting_proposal_service_test.dart`：15 例——
  失败四态（文件不在 / 格式认不出 / 离线 / 回复不合契约）、三类产物的写库规矩、
  `onlyIds` 只写确认过的、队列不重复写与 `forget`。
- `flutter test test/domain/services/intake test/features/questions --concurrency=1` → `+88 All tests passed!`
  （其中这 26 例是本轮新增，其余 62 例是既有 questions 回归）。
- `dart analyze lib test` → `94 issues found.`（0 error / 0 warning，与本片之前的基线同数）。

2026-10-20（Lead，轮次一百二十八：第四类产物"题目"）：

- `app/test/domain/services/intake/handwriting_proposals_test.dart` 新增 group「题目提案（第四类产物）」20 例：
  契约里的 question 示例、`fields.stem` 必填、选项标签必须 A 起连续且不重复、非题目带
  `options` 拒绝、题目空选项/超 26 项拒绝、`confidence` 越界、旧三类输出逐字节不变；
- `app/test/features/questions/application/handwriting_proposal_service_test.dart` 新增 10 例：
  成功入库（题干/选项/答案字母/题型/题号）、`fields.stem` 空不写库、重复题干不重复入库、
  挂标签、标签不存在照建不挂边、纯文字题、答案非字母不猜正确项、多选 `A、C` 与 `AC`、
  `questionDraftForIntake` 只装配不写库、题干空拿不到草稿；
- `flutter test test/features/questions/application/handwriting_proposal_service_test.dart --concurrency=1`
  → `+29 All tests passed`；`dart analyze` 该文件 `No issues found`。
- 提交 `a004aca`："feat(intake): 拍照整理出「题目」——第四类产物可确认入库"。
