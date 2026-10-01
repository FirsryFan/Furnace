# 待议清单（我替你做的决定 + 需要你定夺的地方）

> 用户离场时授权："按你觉得最好的方案做，有问题值得商讨的地方列出来我后续再看。"
> 本文就是那份清单。每条都写明**我做了什么、依据是什么、你可以怎么推翻**。

---

## A. 我替你决定的（已落地，有测试）

### A1. 背景图：把颜色从 Scaffold 挪到图片之上，做成"纱罩"

**问题**：你说"就是加载不出来"。真实原因不是文件读不到——我实测过：`forest` 主题存了
`imagePath`、文件存在且可解码（3000×2083）。抓到的是**图层顺序**：`_AppearanceScope` 是
`MaterialApp` 的 builder，包住的是 Navigator→Scaffold，而我当初把背景色设成
`scaffoldBackgroundColor = 背景色 alpha 0.9`。Scaffold 在图片**上面**，0.9 的近乎不透明
就把图整个盖住了——**与图片在不在无关**。

**决定**：有背景图时 Scaffold 完全透明，背景色改为画在图片**之上**的半透明纱罩。
透明度语义因此成立：颜色越透明，图越清楚。

**你可以推翻**：如果你想要的其实是"图片本身半透明"（而不是"颜色盖在图上"），
那语义要反过来。我选现在这样，是因为它同时解决"图被盖住"和"图上文字看不清"两个问题。

### A2. 背景层抽成独立 widget 并做成公开的

`lib/app/background_layer.dart` 的 `Backdrop`。理由是图层顺序就是它的全部行为，
放在私有位置没法测。**代价**：多一个文件。

### A3. 认知模型的 Dart 移植放在复习调度目录，不是 AI 目录

`lib/domain/services/srs/dsr_memory.dart`，与 `fsrs_scheduler.dart` 并列。它的接入路径
是对拍——43 个 MindNet 公开值全部在 `rel <= 1e-12` 内复现（round6 后逐位相等）。

**你可以推翻**：如果你希望认知模型是"AI 功能的一部分"，位置可以挪；但算法层与
AI 功能耦合会让两边都更难改，我不建议。

### A4. 数据统一：不引入第二份真相

`R0/S/Σ/D` 恰好落在**已存在**的四个列上（`encoding_strength`/`stability`/`savings`/
`difficulty`），所以接入认知模型**不需要新表、新列或迁移**；两边读写同一行，
**结构上不可能不同步**。这不是靠约定，是靠没有第二份数据。

### A5. 两个容易"顺手改错"的读法

| 决定 | 依据 |
| --- | --- |
| 没记录的 `R0` 读作 **1.0**，不是 0.8 | FSRS 曲线无上限；`R0 = 1` 时两条曲线完全相同（已验证 `t = S` 都精确给 0.9）。读成 0.8 会让记得很牢的条目在模型眼里变成半生不熟 |
| `lapses` **不**转成模型的 `F` | 前者是终身计数，后者是**会衰减的证据**；从计数反推衰减历史等于编造数据 |

### A6. 抓到的 bug：时钟单位会让模型静默失效

我原本把"没有复习记录"读作 `lastReview = 当前时间`。结果 `dt` 恒为 0、`R` 恒为 1、
稳定度增益恒为 1.0 —— **模型完全不工作，且不报错**。

真实语义：MindNet 的时钟是**纪元起算小时数**，`ensureState` 里
`lastReview: node.last_review_time || now` 的 `now` 默认 **0**。所以"没有复习记录" =
从纪元开始就在遗忘。

**更值得记的**：我把这个 bug 写进了测试——当时断言"没复习过的卡应该 R=1"，
它**通过了**，因为实现和断言犯的是同一个错误。测试通过不等于行为正确。已把该测试
反过来钉住真实语义，并写清为什么反直觉。

---

## B. 需要你定夺的（2026-10-01 更新：**B1–B4 已定案并落地**，B5 仍未做）

> 每条给**结论 + 依据 + 你可以怎么推翻**。协议正文：`docs/MINDNET_CONTRACT.md` §9；
> 接入地图与证据台账：`docs/MINDNET_INTEGRATION.md`。

### B1. 认知模型在复习流程里的角色 —— **定案 (a) 顾问**

**已实现**：队列段序 `forced → boosted → model → unseen`；`model` 段的顺序**唯一**由
`CognitiveModel.orderAdvisory` 给出（`app/lib/features/anki/application/review_advisory.dart:263`，本文件不写比较器）。
全序键：目标集命中 → 增益 ↓ → `dueAt` ↑（`null` 排最后）→ 知识点 id ↑ → 卡 id ↑。

**依据**：契约 §6.3 的顾问配方 + 决定 D1；数据上 FSRS 仍是 `stability`/`difficulty`/`dueAt` 的唯一写者，
模型只写 `encoding_strength`/`savings`（窄写 `app/lib/data/repositories/anki_repository.dart:388`）——
所有权表见 `docs/MINDNET_INTEGRATION.md` §2。

**你可以推翻**：改成 (b) 调度器或 (c) 设置项，只需改变 `cognitiveModelProvider`
（`app/lib/domain/services/cognitive/cognitive_model.dart:485`）的消费方式，接口不用动；
但 (b) 要先处理老数据缺 `S/D` 的情形，成本最高。

### B2. 新卡（模型眼里"遗忘已久"）—— **定案：不交给模型打分（D4）**

**已实现**：新卡单独成组 `unseen`，排在 `forced`/`boosted`/`model` 之后，顺序确定；
**不伪造 `lastReviewedAt`**（段定义 `review_advisory.dart:49`）。

**依据**：`lastReview = 0` 的语义（纪元起算小时）会让 `R → 0`，若交给模型排序会把所有新卡挤到最前；
而无历史时模型无从判断——D4 把这条不确定性显式化，而不是用假数据喂它。

**你可以推翻**：若你希望新卡优先，只需把 `unseen` 段提到 `model` 段之前（一行位置的改动），
代价是排序不再完全由模型解释。

### B3. 图投影（标签树 → 认知图）与未标定边权 —— **定案：按量级实现 + 全程标注未标定**

**已实现**：`CognitiveGraph.fromTags`（`app/lib/domain/services/cognitive/cognitive_graph.dart:315`）；
父子边 `ls = 0.7`（`:238`）、兄弟边 `ls = 0.4`（`:242`），**两者都标 [未标定]**；
`ms` 是**必填**参数（忘传编译不过），缺条目进 `nodesWithoutMs`（`:266`），MindNet 的 0.8 兜底只以
具名常量 `mindNetDefaultMs`（`:259`）存在、绝不隐式套用。

**依据**：契约 §6.4 明确"`ls` 没有标定来源"、只给量级；§6.6/§8.2 要求参数不写死、并标注未标定。
未标定参数清单见 `docs/MINDNET_INTEGRATION.md` §6.2。

**你可以推翻**：用一段时间的数据再定权重的做法仍然可行——把 `parentChildLs`/`siblingLs` 传成你的值即可，
接口已经把它们做成参数而不是常量。

### B4. tierB（快层）要不要做 —— **定案：已做（移植 + 对拍 + 接入）**

**已实现**：`fast_engine.dart`（驱动/激活/容量/点火/目标偏置 + `v2/engine.js` 的 `step` 管线）与
`fast_diagnosis.dart`（7 类卡点 + 反事实可达性）；随机源按契约建议掐掉（`T_ign = 0`、不装 `rhythm.gate`）。

**对拍证据**：本会话实跑 `flutter test test/domain/services/srs/mindnet_dsr_conformance_test.dart
test/domain/services/cognitive/mindnet_fast_conformance_test.dart
test/domain/services/cognitive/fast_diagnosis_conformance_test.dart
test/domain/services/cognitive/mindnet_protocol_guard_test.dart --concurrency=1` → `All tests passed! (+46)`；
**B01 只有 1 条用例、5 个快照同值**（只证明第 1 轮 + 停止语义），补强证据是诊断 fixture 的
`multiround_progression`（6 轮互异）——见 `docs/MINDNET_INTEGRATION.md` §3.4。

**你可以推翻**：若"目标激活/死角诊断"类功能近期不做，可以停用 tierB（`problem_evaluator` 在无 tierB 时
退化为仅 tierA 判定，有测试），已移植的代码不必删。

### B5. Android 未重构建（你之前说先不急）—— **仍未做**

本轮 Dart 层改动与平台无关；Windows release 已构建并验证（见 `docs/MINDNET_INTEGRATION.md` §0），
Android 未重跑。**网络恢复后我可以补**。

---

## C. 还没做但已知的窟窿

| 项 | 状态 |
| --- | --- |
| Thread 事件流永不自动刷新 | **已确认是真问题**（全仓只有一处 invalidate，在"载入示例数据"里）。新任务在重新点排序前完全不可见；蓝图 Q2.7 承诺的"未参与排序"标记**一个字都没实现** |
| .tfpkg 导出排除密钥 | 已完成 |
| 字体：系统字体族下拉 + 桌面 Word 式预览菜单 | 未做（有 `system_fonts` 包，但未认证发布者、两年未更新；直接读注册表会拿到一半是样式变体的垃圾项） |
| 图标按语义槽位可换 | 未做 |
| 主题色扩到四个语义色 + 24 色板 + 对比度 | 未做 |
| "背景图可见"的**最终视觉确认** | **未完成**：像素级 widget 测试会死锁（`Image.file` 需要真实异步解码，而 widget 测试跑在 fake-async 里，`runAsync` 也没解决），窗口截屏在本会话拿到全黑。装饰部分是结构性验证的，**渲染部分需要你用眼睛确认** |
