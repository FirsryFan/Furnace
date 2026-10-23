# 拍照 → 四类待确认产物（手写整理）

`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4 的落地设计。一句话：**一张（或一组）手写照片进来，
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
| 不做多图之外的发散动作 | 多图 run 可逐条确认、也可整批确认/忘掉（见 §4）；逐条**编辑**仍走单图卡片与收题页 |

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
| `handwritingProposalMessages(...)` | 单图：返回 `[system, user]`，system 写铁律 + JSON 契约 + 已有标签路径/知识点标题（各最多 60 条，超出注明省略数），user 带**一张** `ChatImagePart` |
| `HandwritingPhotoInput{fileName, mime, base64}` | 多图提示词的输入原子（一张照片的元数据 + 字节） |
| `handwritingProposalMessagesForPhotos({photos, ...})` | 多图/多页：system 与单图**共用同一个 builder**（铁律/契约只写一处），user 文本说明「这是第 1..N 页，按顺序看，跨页的同一道题可以合并」，再按序带 N 个 `ChatImagePart`；`assert(photos.length >= 2)` |
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
| `HandwritingProposalService.proposeForMany(relPaths)` | 多图/多页整理：一次请求把 N 张照片按选择顺序交给模型（`handwritingProposalMessagesForPhotos`），返回同一个 `HandwritingProposalRun`；少于 2 张直接失败「合并整理至少要两张照片」。`set.sourceRef` 是 `multiSourceRefFor(relPaths)`，不是任何一张照片的路径 |
| `HandwritingMultiRun{sourceRef, photoRelPaths, set, analyzedAt}` | 多图 run 的内存形态：`photoRelPaths` 按用户选择顺序；`sourceRef` 是 `multi:<16 位十六进制>` |
| `multiSourceRefFor(List<String> relPaths)`（顶层） | 多图 run 的稳定 id：路径排序后用 NUL 连接做 63 位 FNV-1a，输出 `multi:<16 hex>`。**同一组照片与顺序无关**，所以重新整理同一组是整批替换而不是新增一条 |
| `HandwritingProposalService.applyAll(set, {onlyIds})` | 只写被确认的那些提案，返回 `HandwritingApplyReport{outcomes, appliedCount, failedCount, allOk, appliedIds}` |
| `HandwritingQueueState` | 队列状态：`images` / `sets` / `multiRuns` / `failures` / `analyzing` / `applying` / `appliedIds` / `lastReport`；`isApplied(sourceRef, proposalId)` 的键是 `'$sourceRef#$proposalId'`；`setFor(sourceRef)` 先查单图 `sets` 再查多图 `multiRuns`；`mergedPhotoPaths` 是所有多图 run 照片的并集（批量整理会跳过它们）；`multiRunOf(sourceRef)` 查多图 run |
| `HandwritingQueueNotifier` | `refresh()`（读磁盘清单 + 从库里恢复单图/多图提案与确认状态；**多图 run 只要有一张照片不在磁盘就整条清掉**，单图 run 照片不在也清）、`analyze(relPath)`（成功后写库）、`analyzeMulti(relPaths)`（多图：同一组照片重整理整批替换，成功后写 `source_photos`）、`applyProposal(sourceRef, proposalId)`、`applyAll(sourceRef)`、`forget(sourceRef)`（从单图/多图两侧删整理记录，**照片本身不动**） |
| `handwritingProposalServiceProvider` | store / tags / anki 来自既有 provider，adapter 来自 `modelAdapterProvider` |
| `handwritingProposalRepositoryProvider` | `HandwritingProposalRepository(ref.watch(appDatabaseProvider))`（schema v13） |
| `handwritingQueueProvider` | `NotifierProvider<HandwritingQueueNotifier, HandwritingQueueState>` |
| `HandwritingProposalService.questionDraftForIntake(proposal)` | 只**装配**题目草稿、不写库：题干空返回 `null`（不查标签），否则解析 `tag_path` 填 `tagIds`，交给收题页表单预填（轮次一百二十八） |
| `HandwritingQueueNotifier.markAppliedLocally(relPath, proposalId)` | 用户在收题页手动入库后只标"已确认"，不写第二遍（`HandwritingProposalRepository.markApplied` + 内存 `appliedIds`） |

### 数据层（schema v13）

| 表 | 列 |
|---|---|
| `handwriting_intake_runs` | `source_ref`（PK；单图=照片相对路径，多图=`multi:<16 hex>`）、`source_photos?`（schema v31：多图 run 的照片 JSON 路径数组，NULL/`[]`=单图）、`analyzed_at`、`raw_reply?`、`created_at`。**零提案也留一行**——「整理过但照片里没东西」重启后不能退回「没整理过」 |
| `handwriting_proposals` | `id`（PK = `<source_ref>#<proposal_id>`）、`source_ref`、`proposal_id`、`sort_index`（不按 id 排，否则字典序把三类产物打散）、`kind`、`payload_json`（`HandwritingProposal.toJson()` 文本）、`applied_at?`（NULL = 未确认）、`created_at` / `updated_at` |

`HandwritingProposalRepository`（`app/lib/data/repositories/handwriting_proposal_repository.dart`）：

| 方法 | 口径 |
|---|---|
| `saveRun({set, analyzedAt, rawReply, sourcePhotos = const []})` | 一个 `source_ref` 只有一条 run：删旧行再写新行。`sourcePhotos` 空写 **NULL**（单图语义，不存 `[]`），非空才 `jsonEncode`。**按 `payload_json` 逐字相同的那几条保留 `applied_at`**，其余清成 NULL |
| `runs()` / `runOf(sourceRef)` | run 行按 `analyzed_at` 倒序；提案行按 `sort_index` 正序；还原走领域层 `fromJson`（JSON 契约只有一份）。`HandwritingStoredRun.sourcePhotos` / `isMulti` 由 `_decodeSourcePhotos` 解析：坏 JSON、非数组、混入非字符串/空白项一律降级成空清单（=单图语义），不抛 |
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

### 3.1 题干内联选项的确定性抽取（轮次一百二十九，task-77）

拍照回来的题目常常是这样的：题面一行，选项紧随其后写成 `A．… B．… C．…`。以前这类选项
要么靠模型在 JSON 里另给 `options`，要么就整段留在题干里、入库后没有真正的选项结构。
现在补了**纯逻辑**的兜底（`handwriting_proposals.dart` 的 `extractInlineOptions`）：

- **触发条件**：`kind == question`、模型**没给** `options`、`fields.stem` 非空。模型显式给了
  `options` 就不抽（尊重模型的产出）。
- **成功时**：`fields.stem` 换成剥离选项后的题面（只去首尾空白，内部换行与公式原样保留），
  原题面另存 `fields.stem_original` 供追溯；`options` = 抽出的选项（label 归一成半角大写）。
- **失败时零改动**：不猜、不抛异常，返回一句可直接显示的中文原因（"至少需要 2 个选项（现在只有
  1 个「A」）"、"选项必须从 A 开始"、"选项字母不连续…"、"选项「B」的内容为空…"），用户看到
  的是原题面 + 无选项，而不是一份被切坏的题。
- **认什么**：行首（允许缩进）或同一行已有已接受标记之后的 `A`–`H` 标记；字母认半角与全角，
  分隔符认 `.` `．` `、` `)` `）` `:` `：`；选项内容可跨行。
- **必须 ≥2 项、从 A 起连续、不重复、不跳号**，否则整体失败（不返回部分结果）。
- **防误伤**：`$...$`、`$$...$$`、`\(...\)`、`\[...\]` 公式区间里的字母不参与识别；
  `【答案】` / `答案：` / `【解析】` 等 18 类前缀开头的答案解析行整行不参与，也不会并进最后
  一个选项的内容；`A=1`、`B点`、`选项 A 说法正确`、`A、B两点` 这类正文不会被当成选项。
- **存量数据也会补抽**：`HandwritingProposal.fromJson` 与首次解析共用同一个 `_proposalFrom`，
  所以库里只有题干、没有 `options` 的旧提案**读回时会确定性补抽**并加 `stem_original`。
  这是幂等的（第二次读回已无内联选项，不再变化），`toJson → fromJson` 往返逐字节相等；
  旧三类产物（标签/知识点/闪存卡）的输出完全不变。
- **已知限制**（有测试钉住，明确不抽而不是猜）：题面与选项写在**同一行且第一个标记不在行首**
  （`题干（  ） A．甲 B．乙`）不抽；`（A）` 括号样式不认；`A．甲、B．乙` 里 `B` 前没有空白
  不认；`D．丁【答案】B` 这种答案不单独成行时不算答案行。

## 4. 刻意未做 / 已知缺口

- ~~**提案只存在内存里**~~ → 已补（schema v13，见上表）：提案与"已确认到哪一条"落在
  `handwriting_intake_runs` + `handwriting_proposals` 两张表里，重启后 `refresh()` 恢复。
  界线仍然清楚：**这三张表只存提案与确认状态，标签 / 知识点 / 闪存卡仍然只在用户点确认
  之后才写**——"确认前不写库"说的是学习数据，不是"待确认清单"。
- ~~**一次只整理一张照片**~~ → 已补（schema v31，轮次一百四十八）：队列页 AppBar 有「选择照片」
  进入合并模式，勾选 ≥2 张点「合并整理（N 张）」，一次请求把 N 张图按顺序交给模型，产出一组
  共享 `multi:<id>` 的提案（照片清单存 `handwriting_intake_runs.source_photos`）。边界与仍差的部分：
  - **不能和单图混选**：已整理出提案、正在整理、已属于某次多图 run 的照片在合并模式里禁选
    （再合一次只会多花模型调用，还可能把同一页重复入库）；已合并的照片在普通照片条上带「已合并」徽标。
  - **多图卡片可逐条确认、也可整批动作**（轮次一百四十九补）：展示 N 张缩略图 + 整组提案（带确认前
    预检），每条提案有自己的「确认」按钮（走 `HandwritingQueueNotifier.applyProposal`）、底部仍有
    「全部确认」与「忘掉」；题目提案还有「编辑后保存」（轮次一百五十二补，见下条）；没有逐条重拍某页。
  - **多图卡片也能「编辑后保存」**（轮次一百五十二补）：题目提案带编辑入口，走与单图卡片共用的
    `editProposalForIntake(context, ref, sourceRef, proposal)`；草稿预填收题页、入库后才算确认，
    sourceRef 是 `multi:<16hex>`，入库回写键仍是 `<sourceRef>#<proposalId>`。
  - **没有选张数上限、也没有重排页面顺序**：选择顺序就是提示词里的页序；选 20 张会一次性发 20 张图，
    受模型上下文限制，客户端不做拦截（失败会退回 `modelFailure` 的人话原因）。
  - **归并靠模型**：跨页同一道题合并成一条题是提示词要求（页规则第 7–9 条），不是本地算法；
    模型仍按铁律只誊写照片里有的内容。
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
- **题目卡片的编辑入口已接**（task-70，轮次一百二十八，question-intake）：队列卡片对
  `kind == question` 展开题干/选项/答案/解析摘要（超长截断），右下「编辑后保存」按钮
  （`key = handwriting-question-edit-<id>`，已确认/写库中禁用）；点它先用
  `questionDraftForIntake` 装配草稿（题干空不给入口，只提示重拍或手填），再 push
  `QuestionIntakePage(initialDraft/initialRelPath/initialProposalId)` 回填表单；保存成功后
  调 `markAppliedLocally` 把这批提案标为已确认（失败只 debugPrint 不阻断写库），SnackBar
  显示题号（无号说「未编号」）。收题页同时补了多选题型与草稿回填（选项按草稿重建）。
- **确认前的预检已接（task-74，轮次一百二十八，question-intake）**：预检纯逻辑在
  `handwriting_proposal_preview.dart`（42 例单测），应用层 `HandwritingProposalService.previewFor(set)`
  与 `HandwritingQueueNotifier.previewFor(relPath)`（队列里没有这批提案返回 `null`）读出库里现有
  标签路径与知识点标题后判定。队列页按「relPath + proposal ids」签名缓存预检，切照片或提案变化
  才重算；卡片 `_ProposalPreviewBlock` 渲染 `previewLines`，needsReview 高亮 warnings（tertiary），
  blocked 显示 blockers（error）并禁用该条「确认」；整批 `hasBlocked` 时禁用「全部确认」并显示
  ready/needsReview/blocked 计数。预检失败只 debugPrint，退回「无预检」旧行为不崩。

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

2026-10-21（轮次一百二十八收尾：队列编辑入库 + 确认前预检 UI）：

- task-70（question-intake）队列题目卡片可编辑再入库：`handwriting_queue_page_test` 新增 4 例
  （卡片展开题干/选项/答案/解析摘要、点编辑只预填不写库、入库后题库 1 行且 SnackBar 带 TR-00001、
  返回队列变已确认且编辑按钮禁用、空题干无编辑入口），`flutter test test/features/questions/presentation`
  → `+276 All tests passed`。
- task-74（question-intake）确认前预检 UI：`handwriting_queue_page_test` 再新增 3 例（三种结论展示 +
  blocked 单条禁点后不写库 + 整批全部确认禁用、无 blocked 时全确认一次写入、切照片重算预检），
  同目录 `+279 All tests passed`；应用层 `previewFor` 的 4 例单测见 `handwriting_proposal_service_test`。
- 各切片 `dart analyze` 作用域 `No issues found`；`dart analyze lib test` 保持 92 issues / 0 error /
  0 warning；`dart format` 只格式化改动文件。
- 未验证：真机整条链路（拍照 → 整理 → 编辑 → 入库 → 队列已确认）、预检失败降级路径的 widget 测试、
  英文文案母语校对；真实模型回复仍用样例 JSON 模拟。

2026-10-21（轮次一百二十九：题目选项的确定性兜底）：

- task-77（reasoning-core）新增 `extractInlineOptions` / `InlineOptionExtraction` 并接进
  `_proposalFrom`：`app/test/domain/services/intake/handwriting_proposals_test.dart` 新 group
  「题干内联选项抽取」**42 例**（直接抽取、防误伤、失败分支、与 JSON 契约的接线、存量读回、
  toJson/fromJson 往返、旧三类逐字节不变、同一输入同一输出）。
- `flutter test test/domain/services/intake --concurrency=1` → `+119 All tests passed`
  （基线 77 + 新 42）；`dart analyze lib/domain/services/intake test/domain/services/intake`
  → `No issues found!`。
- 未验证：真实拍照样本的端到端链路（本机没有真实整理输出，测试用合成题面）。
- 实现期修掉两个真 bug（已由测试覆盖）：1) 公式闭合符 `\)` / `\]` 被转义判断误拒，导致
  `\(A．B\)` 里的字母参与识别；2) 落单的单个 `$`（如"单价 $5"）会掩到段尾、把后面的
  真选项吞掉——现在单 `$` 找不到闭合就按字面量处理，不掩码。

2026-10-23（轮次一百四十九：多图卡逐条确认）：

- task-156（question-intake）`_MultiRunCard` 的提案由只读改成每条可单独确认：`_ProposalCard.onApply`
  变必填 `VoidCallback`，多图卡传 `() => notifier.applyProposal(sourceRef, proposal.id)`，整批
  「全部确认」仍走 `applyAll(sourceRef)`；已确认/确认中/预检 blocked 时按钮禁用。
- `handwriting_queue_page_test.dart` 25 → **28 例**：新增 3 例（逐条确认只调 `applyProposal` 且其余
  仍待确认、blocked 提案单条与整批都禁用且点击不写库、整批仍一次写全部）。
- 门禁（作用域）：`flutter test test/features/questions/presentation/handwriting_queue_page_test.dart`
  → `+28 All tests passed`；`dart format` 0 changed；`dart analyze` 两文件 `No issues found`。
- 未验证：真机多图卡逐条确认的点击手感；真实模型返回多条提案时的实际分布。

2026-10-24（轮次一百五十二：多图卡片编辑后保存）：

- task-159（question-intake）：`handwriting_queue_page.dart` 抽出顶层
  `editProposalForIntake(context, ref, sourceRef, proposal)`（:71-99），单图面板删私有 `_editForIntake`
  改调它；`_MultiRunCardState` 对题目提案传 `onEditForIntake`（sourceRef=`run.sourceRef`，
  即 `multi:<16hex>`），其它产物 null。收题页入库后按 `<sourceRef>#<proposalId>` 写回已确认，
  与队列的 `isApplied` 键一致。类注释改为「整组展示不等于只能整组操作」。
- `handwriting_queue_page_test.dart` 28 → **31 例**（入口只给题目提案；点编辑预填收题页且不写库；
  编辑后入库题目进库、提案转已确认、编辑按钮禁用而 tag 提案确认仍可用）。
- 门禁（作用域）：`flutter test test/features/questions/presentation/handwriting_queue_page_test.dart`
  → `+31 All tests passed`；format/analyze 与全量见本轮 PROGRESS。
- 未验证：真机多图卡编辑入口的点击手感；真实模型返回多条题目提案时的编辑体验。

