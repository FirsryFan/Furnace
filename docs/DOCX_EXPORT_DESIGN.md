# DOCX 导出设计（题目卷 → Word）

> 轮次一百二十二。用户指令（m00726）：**「docx 文档的构建和组卷网的链接可以借鉴 dsh skill」**。
> 本文只讲 .docx 导出；组卷网链接见 `docs/ZUJUAN_LINKS_DESIGN.md`。
> 借鉴对象：`D:\dsh-data\skills\paper-composer`（scripts/papercompose/docx.py、config.py、omml.py、
> assets/templates/exam.json）与同目录 SKILL.md 的验收纪律。

## 1. 目标与纪律

把组卷页算好的 `PaperPlan`（题号、知识点、理由、缺口）加上题库里每道题的题干/选项/答案/解析/配图，
装成一份 Word 能直接打开、能打印、公式还能改的 `.docx`。

硬约束：

1. **纯 Dart、离线、不调模型、不经 Python**。docx 是 OOXML zip，自己写；zip 用仓库已有的
   `archive ^3.6.1`（`tfpkg` 导出同款），不新增依赖。
2. **不静默丢内容**：题干空、答案/解析缺、配图嵌不进、公式编译失败，全部计数并写进「导出提示」，
   同时用 `PaperDocxBuildResult` 报给界面层。少一段内容不报，比导出失败更糟。
3. **公式是 Word 原生 OMML**（可编辑），失败才退回 LaTeX 原文并计数——不许变成图片，也不许丢掉。
4. **图片只随文、不浮动**：`wp:inline`。受控环绕 `wp:anchor` 需要逐份实测分页，本功能没有那个验证预算。

## 2. 分层与文件

| 层 | 文件（app/ 相对） | 职责 |
| --- | --- | --- |
| 文档构造 | `lib/domain/services/export/docx_writer.dart` | 文档对象模型（段落/run/图片/页脚）→ OOXML XML → zip 字节。不碰 dart:io、不碰 Flutter。 |
| 公式 | `lib/domain/services/export/omml/omml.dart`（reasoning-core 移植） | LaTeX 子集 → `<m:oMath>` 片段；`compileLatexToOmml(tex, {int? sizeHalfPt})`。 |
| 卷面装配 | `lib/domain/services/export/paper_docx.dart` | `PaperPlan` + 题目素材 → 标题/题号/meta/题干/选项/配图/附录/缺口/导出提示 + 统计。纯逻辑。 |
| 图片尺寸 | `lib/data/media/image_size.dart` | PNG/JPEG/GIF/BMP/WEBP 像素尺寸解析（决定等比缩放；域层不碰文件字节，由应用层读）。 |
| 应用装配 | `lib/features/questions/application/paper_docx_export.dart` | 读库（`readQuestionDocxRows`/`readKnowledgePointNames`）+ 读配图字节（`QuestionMediaStore`）→ `buildPaperDocx`；建议文件名、默认页脚。 |
| 数据读取 | `lib/features/questions/application/question_corpus_reader.dart` | 新增 `QuestionDocxRow`、`readQuestionDocxRows(db, {ids})`、`readKnowledgePointNames(db)`。 |
| 界面（task-10） | `lib/features/questions/presentation/paper_docx_export_button.dart` + `question_paper_page.dart` | 「导出 Word」按钮、FilePicker 保存、成功/告警/失败提示、l10n。 |

依赖方向是单向的：界面 → 应用 → 领域/数据；`paper_docx.dart` 不 import 数据库、不 import dart:io，
这样测试可以直接喂假素材，不必起 sqflite。

## 3. 借鉴 paper-composer 的哪几条

保留（并写进 docx_writer 的 library doc）：

1. **页面几何四边独立**：左窄（装订）、右宽（批注栏），左右不等宽会改变折行，事后不能改 `pgMar` 糊。
2. **图片默认受控缩放**：宽度/高度双上限 + 放大上限，先按栏宽、再按页高，取更严的那个。
3. **页脚放页码域 + 左侧时期代号**，不做页首标题（页首会和卷面标题打架）。
4. **公式必须原生可编辑**，未知 LaTeX 命令报错、不静默退化。
5. **真测而不是估算分页**：生成后必须用 Word 打开、导出 PDF、量页数（见 §11）。这条是整个 skill 的核心教训。

没移植：表格、浮动图（`wp:anchor`）、页眉、多栏、目录。题库导出暂时用不到；需要时再加，
但**不要**从 paper-composer 里贴一段浮动图进来——那需要重新实测分页。

## 4. 版面参数（exam 模板，来自 paper-composer 实测）

| 项 | 值（OOXML 单位） | 换算 |
| --- | --- | --- |
| 纸张 | `w:pgSz w=11906 h=16838` | A4 竖版 |
| 左边距 | 680 twips | 1.2 cm（装订） |
| 右边距 | 2268 twips | 4.0 cm（批注栏） |
| 上下边距 | 1020 twips | 1.8 cm |
| 正文栏宽 | 11906−680−2268 = 8958 twips | 15.8 cm |
| 页脚距 | `max(425, 1020−283) = 737` twips | 与 paper-composer 同口径 |
| 正文行距 | `lineTw=252`，`lineRule=auto` | ≈1.05 倍（compact） |

字体/字号（半磅为单位）：

| 用途 | 中/西文字体 | 字号 |
| --- | --- | --- |
| 正文 | 宋体 / Times New Roman | 21（10.5pt，五号） |
| 题号行 | 黑体 + 粗体 | 24（12pt，小四） |
| 卷面标题 | 黑体 + 粗体 + 居中 | 30（15pt） |
| meta（学科/来源/导出时间/页码） | 宋体 / Times New Roman，灰 | 18（9pt，小五） |
| OMML run | Cambria Math | 随正文 21（可选传 `sizeHalfPt`） |

常量集中在 `docx_writer.dart` 顶部：`kDocxBodyHalfPt`、`kDocxHeadHalfPt`、`kDocxTitleHalfPt`、
`kDocxMetaHalfPt`、`kDocxBodyFontCn`、`kDocxBodyFontEn`、`kDocxHeadFontCn`、`kDocxMathFont`；
不要在下层散落字号字符串。

## 5. 包结构与样式

`DocxDocumentBuilder.build()` 产出的 zip 条目：

| 条目 | 内容 |
| --- | --- |
| `[Content_Types].xml` | 默认扩展名（rels/xml/png/jpeg/gif/bmp）+ document/styles/settings/footer 的 Override |
| `_rels/.rels` | 指向 `word/document.xml` |
| `word/document.xml` | 根元素声明 w/m/r/wp/a/pic 六个命名空间（OMML 片段因此不用自带 xmlns） |
| `word/_rels/document.xml.rels` | styles/settings/footer + 每张图的 `rIdImgN` 关系 |
| `word/styles.xml` | `docDefaults`（rFonts + sz + 行距）+ Normal 样式 |
| `word/settings.xml` | `w:compat` 等最小设置 |
| `word/footer1.xml` | 页脚（仅当有 footerText 或页码模板时生成） |
| `word/media/imageN.<ext>` | 内嵌配图，扩展名已归一化（jpg→jpeg） |

页脚：左侧 `footerText`（默认 `Furnace · yyyy-MM-dd`），右侧页码域；
`PAGE`/`NUMPAGES` 用 `fldChar begin/instrText/separate/fldChar end` 三件套写，
中间夹一个右对齐制表位；上方一条 `pBdr` 顶细分隔线。两个参数都为空时不生成 `footer1.xml`。

## 6. 段落模型（docx_writer 的公开契约）

- `sealed class DocxInline`：`DocxText`（文本 run：size/bold/italic/underline/sub/sup/color/font）与
  `DocxMath`（已编译好的 `<m:oMath>…` 片段，原样写入，不二次校验——编译器在 `omml` 层测）。
- `DocxParagraph`：`inlines`、`align`（left/center/right/justify）、`spacingBeforeTw`/`spacingAfterTw`/
  `lineTw`、`lineRule`、`keepNext`、`keepLines`、`pageBreakBefore`、缩进、`borderBottomHex`、`shadeHex`。
- 文本序列化规则：`& < > " '` 转义；XML 非法控制字符丢弃（不把文档写坏）；`w:t xml:space="preserve"`
  保住首尾空格；文本内换行拆成 `<w:br/>`。
- 生命周期：先 append 后 `build()`；build 之后再 append/再 build 抛 `StateError`（防止"改完没生效"的假象）。
- 统计：`paragraphCount`、`imageCount`、`mathCount`、`imagePlacements`（每张图最终 cx/cy EMU），
  测试和排版报告都断言这些，不看二进制。

## 7. 图片策略

`DocxImageSpec`：`bytes`、`extension`、`pixelWidth`/`pixelHeight`、`align`、
`maxWidthFraction=0.62`、`maxHeightFraction=0.22`、`maxUpscale=1.5`、`keepNext`、`note`。

等比缩放（`computeInlineImageExtent`）：

```
自然尺寸 twips = 像素 × 15（96dpi）
maxW = 正文栏宽 8958 × 0.62 ≈ 5553 twips
maxH = 正文可用高 14798 × 0.22 ≈ 3255 twips
scale = min(maxW / 自然宽, maxH / 自然高)
scale 上限 1.5（小图不放大到半页）；下限不限制（小图原样）
EMU = twips × 635
```

扩展名只认 `png/jpeg/gif/bmp`（`normalizeDocxImageExtension`）；`webp/heic` 等由调用方
`supportsDocxImageExtension` 先判、报告「跳过」后**不传进来**。`addImage` 收到不认识的扩展名抛
`ArgumentError`——静默吞图的出口在这里被堵死。

图片一律 `wp:inline`（不浮动）；元素顺序按 OOXML 要求：
`wp:inline→extent→docPr→a:graphic→a:graphicData→pic:pic→pic:nvPicPr→pic:blipFill→pic:spPr`。
配图段落 `keepNext` 让「题干末句 + 紧跟的图」不拆页。

## 8. 公式策略

- `paper_docx.dart` 定义 `typedef DocxMathCompiler = String Function(String tex, {int? sizeHalfPt});`
  调用方注入 `compileLatexToOmml`（推理层 task-8 移植）。域层**不依赖** LaTeX 解析器。
- 行内 `$...$` 由 `_inlines` 拆分：命中公式 → `DocxMath(compiler(tex))`；未注入编译器 → 保留
  `$tex$` 纯文本且**不计数**（这不是失败，是没开这个能力）。
- 编译器抛异常（`LatexError` 等任何 `Object`）：`formulaFailureCount++`、
  `formulaFailures` 记一条预览（带错误文本）、该处退回 `$tex$` 纯文本。绝不吞成空。
- OMML 命名空间由 document.xml 根元素声明，片段本身不带 `xmlns`。
- 已知覆盖缺口以 `omml` 层的 `supportedLatexCommands()` 与 task-8 报告为准；失败会在导出提示里出现，
  用户能看见哪一条公式没编译。

## 9. 卷面装配规则（paper_docx.dart）

一次导出 = **标题区 + 题目区 + 附录**。

1. 标题区：卷面标题（默认「组卷卷面」）→ headline（默认「想要 N 道，凑到 M 道」）→ 可选
   「导出时间：yyyy-MM-dd HH:mm」→ 可选 subtitle。meta 段落 9pt 灰、下边框 BFBFBF。
2. 题目区，逐题（`PaperPlan.items` 顺序，不重排、不复算分数）：
   - 题号行：`n.  TR-00001`（黑体 12pt 粗体、`keepNext`；无编号时只有 `n.`）；
   - meta 行：`学科 · 来源档位 · sourceLabel · zone · 知识点：名 · 年份 · 地区` 用 ` · ` 连接，
     空项跳过；来源档位走 `paperDocxSourceLevelLabel`（gaokao/省级诊断/名校/学校/自建/未标注）；
   - 题干：按换行拆段；空题干写占位句并计入 `missingStemCount`；
   - 选项：`A. 内容`（`leftIndentTw=240`）；
   - 配图：`wp:inline` 居中；
   - 附录前不插分页（见 3）。
3. 附录（顺序固定）：
   - 第一个附录标题「参考答案与解析」`pageBreakBefore: true`（**只有第一个**，`_appendixStarted` 控制，
     否则每个标题都另起一页，实测把 2 页撑成 4 页）；
   - 每题：`n.` → 答案（`answer` 为空时用正确选项字母 `、` 连接；仍空 → 「（无答案）」+计数）→
     解析 → 理由 / 提升点 / 背景（`includeReasons`）；
   - 缺口两节：未覆盖知识点、被上限挡下的知识点（`includeGaps`）；
   - 「导出提示」：缺失题（含题号 id）、空题干、缺答案、缺解析、跳过的配图、公式失败，全部列条目。
4. 统计回传 `PaperDocxBuildResult`：`bytes`、`questionCount`、`paragraphCount`、`imageCount`、
   `imageSkippedCount`、`formulaCount`、`formulaFailureCount`、`missingQuestionCount`、
   `missingStemCount`、`missingAnswerCount`、`missingSolutionCount`、`missingQuestionLabels`、
   `imageSkippedNotes`、`formulaFailures`、`hasWarnings`。
   `hasWarnings` = 以上任一异常计数 >0 或 notes 非空；界面必须据此显式提示。

标签全部走 `PaperDocxLabels`（默认中文）；英文/其它语言由界面层注入，不在域层写死 l10n。

## 10. 应用层装配（paper_docx_export.dart）

```dart
Future<PaperDocxExportResult> buildPaperDocxExport({
  required AppDatabase db,
  required QuestionMediaStore mediaStore,
  required PaperPlan plan,
  DocxMathCompiler? mathCompiler,
  PaperDocxLabels labels = const PaperDocxLabels(),
  DocxPageConfig page = const DocxPageConfig.a4Exam(),
  String? footerText,
  bool includeAnswers = true,
  bool includeSolutions = true,
  bool includeReasons = true,
  bool includeGaps = true,
  String? title,
  String? subtitle,
  DateTime? generatedAt,
})
```

流程：`readQuestionDocxRows(db, ids: plan 里的题目 id)` → `readKnowledgePointNames(db)` →
`loadQuestionDocxImages(mediaStore, ids)` → 每行 `toPaperDocxQuestion(images: …)` → `buildPaperDocx`。

配图三道防线，缺一不嵌、逐条记 `imageLoadNotes`：

1. `QuestionMediaStore.readBytes` 返回 null/空（文件被清掉）→ 跳过；
2. `readImageInfo(bytes)` 认不出容器（HEIC 等）→ 跳过；
3. 像素尺寸非正 → 跳过。

格式能不能进 docx 由装配层再判一次（WEBP 能读尺寸但 Word 不认，会被计入「跳过」）。

建议文件名 `furnace-paper-yyyyMMdd-HHmm.docx`（ASCII、可按时间排序；中文文件名在部分
FilePicker/系统组合下会出问题，所以不用卷名）；页脚默认 `Furnace · yyyy-MM-dd`。

## 11. 验收证据

### 11.1 单元/装配测试（本机真实输出）

- `flutter test test/domain/services/export test/data/media test/features/questions/application/paper_docx_export_test.dart`
  → **+158 All tests passed**（exit 0）。
- 含既有测试的宽范围 `... test/features/questions/application` → **+211 All tests passed**（exit 0）。
- 覆盖：zip 条目与命名空间、pgSz/pgMar/footerReference、rPr（中文字体/字号/粗体/颜色）、XML 转义与
  控制字符、换行 br、段落属性（keepNext/keepLines/pBdr/shd/ind/jc/pageBreakBefore）、页脚域与
  `pBdr`、图片 EMU（100×100px→1428750×1428750；4000×3000 保持 4:3）、图片关系与 media 名、
  HEIC 抛错、build 后写入抛 StateError、公式原样写入并计数、长卷装配（题号/meta/题干/选项/答案/
  解析/理由/缺口/缺失题/公式失败保留原文/跳图/英文标签/页脚）、图片容器尺寸解析各格式。
- `omml` 层测试由 reasoning-core 交付（≥50 断言，未知命令抛 `LatexError`、`sizeHalfPt` 写 `w:sz` 等）。

### 11.2 整链 + Word 真测（E:\dsh-tmp-aot\docx-probe）

探针 `app/tool/docx_probe.dart` 用假库数据造 3 题卷（含公式、两张图），产出
`paper-sample.docx` 6,566 字节：3 题 / 35 段 / 2 图 / 29 公式 / 0 失败 / 0 缺失 / 无告警。

Word COM（Word 16.0，**pwsh 7** 跑 `verify-word.ps1`；Windows PowerShell 5.1 会因脚本 UTF-8 无 BOM +
中文报 `Missing ')' in method call`）：

| 指标 | 值 |
| --- | --- |
| 打开耗时 | 678 ms |
| 页数 | **2**（附录分页修复前是 4） |
| 字数 | 546 |
| 内嵌图 | 2（`InlineShapes.Count`） |
| OMML 公式 | 29（`OMaths.Count`，与 `mathCount` 一致） |
| 卷面标题存在 | True |
| 答案与解析节存在 | True |
| 导出 PDF | 205,630 字节（同一 Word 实例导出） |

结论：生成的 docx 能被 Word 直接打开、公式是原生对象、图片按预期内嵌、附录只另起一页。
分页数依赖具体 Word 版本与字体，换内容要重测（这正是 paper-composer 要求真测的原因）。

## 12. 未做 / 已知限制

- **界面按钮**：task-10（组卷页「导出 Word」+ FilePicker + l10n + widget test）本轮并发进行；
  该按钮落盘前，功能只能通过 `buildPaperDocxExport` 调用（探针 `tool/docx_probe.dart` 是示例）。
- 未支持：表格、浮动图、页眉、多栏、目录、脚注、批注栏内容；只导出「题目卷」一种模板。
- 图片只从本地 `QuestionMediaStore` 读；WEBP/HEIC 不嵌入（Word 支持差），会报「跳过」。
- 公式只覆盖 omml 层认识的 LaTeX 子集；未覆盖命令退回 LaTeX 原文并计入 `formulaFailures`。
  复杂试卷若失败很多，应先补 omml 层而不是放宽计数。
- 不直接产出 PDF；需要 PDF 时用 Word/LibreOffice 打开导出（参见 office-export-pdf 流程）。
- 分页只做了 `keepNext`/`keepLines` 与附录一次分页；没有按题"绝不跨页"的强制分页——那会让
  长题留大片空白，需按真实内容再实测。
- 只在 Word 16.0 上验证；WPS/LibreOffice 未测（OOXML 标准结构 + 无浮动元素，兼容风险较低但未验证）。
- 未验证：真机上从组卷页点按钮保存到系统下载目录（依赖 task-10 完成与手测）。
