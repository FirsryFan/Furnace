/// 整卷 `paper.json` → 产品题库（Questions / QuestionOptions / ContentRefs /
/// Attachments）的导入服务（task-87，2026-11-15）。
///
/// 为什么需要它：工作区 `exam-papers/*/paper.json` 是"按题抽取"的整卷产物，
/// 与 `content-store/` 的内容包 schema 不同（字段名、答案/解析结构、图片位置、
/// 分值来源全都不一样），不能直接喂 [ContentPackageImportService]。这个服务只
/// 做一件事：把**一套卷子**按题导入产品库，并且：
///
///  * 幂等：`content_refs.content_id = '<paperKey>#Q<number>'`；第二次导入
///    复用同一个 content_id 指向的题，不新建题、不重复选项、不重复配图；
///  * 不伪造：不建知识点/标签、不写 AI 初标能力点、不猜分值；`paper.json`
///    给的 `score` 原样进引用摘要（产品 `questions` 没有分值列），缺分值写
///    `null` 并保留 `score_source`；`score_inferred` 只记录不采用；
///  * 图：题干图按产品既有约定落 `attachments`（role=stem，题干里写成
///    `［图N］` 占位，详情页按占位图文混排——`question_stem_segments.dart`）；
///    解析图落 role=answer（答案区图库）。图文件缺失、公式未转换、题干里的
///    图引用对不上任何图 → 该题 `blocked`，不把坏题写进库；
///  * 事务：整卷一个 `db.transaction`，任一步抛错全部回滚，不留半批；
///  * 安全：本类不做 UI/Provider 接线，调用方必须传**临时库**或用户明确授权
///    的库（测试一律 `AppDatabase.forTesting(NativeDatabase.memory())`）。
///
/// 输入两类：
///  * [ExamPaperDocument.fromJson]：调用方自己解析 `paper.json`（+ 同目录
///    `manifest.json` 补 subject/year/region）；
///  * [ExamPaperDocument.loadDirectory]：直接读一个卷目录（`paper.json` +
///    可选 `manifest.json`），图路径相对该目录解析。
///
/// 六科差异（task-89，2026-11-15）在本文件内收敛，不额外开服务：
///  * 数学 / 生物：顶层 `questions`，`stem_md` / `stem` 字符串；生物图是
///    字符串路径、选项是 map、解析在 `explanation`；模块卷按来源 `stage`
///    标 `non_gaokao`（`source_level=school`）；
///  * 语文：顶层 `questions` + `sections[].materials[]`；`material_ids` 指向的
///    材料原文并入题干（产品没有 materials 表），并记 `material_ids` 摘要；
///  * 化学：`stem` 是 block 列表（`kind=p/table` + `tokens[k=t/img/eq]`）；
///    选项图/公式图并入题干「【选项配图】」区，答案/解析图落 role=answer；
///    公式是图片（`formula_image_not_latex`），文件缺失 → 该题 blocked；
///  * 物理：`stem_blocks`（text/formula/figure）按原顺序重建成题干，公式图与
///    插图一样落 role=stem 并用「［图N］」占位——**不假装文本、不伪造 LaTeX**；
///    选项里的公式/图并入「【选项配图】」区；
///  * 英语：顶层没有 `questions`，从 `sections`（listening/reading/
///    seven_choose_five/cloze/grammar/writing）摊平成题；听力原文、阅读语篇、
///    七选五/完形/语法语篇并入题干；作文答案标 `answer_non_unique`（参考样例，
///    不是唯一标准答案），听力无音频标 `audio_unavailable`。
///
/// 仍未接：CLI/host 入口由 `content_import_cli.dart` / `content_import_host.dart`
/// 包装（task-88）；分值列（产品没有）；知识点/标签（`paper.json` 里只有 AI
/// 初标，不采用）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../data/database/database.dart';
import '../../../data/repositories/content_ref_repository.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../domain/services/content/content_ref_vocab.dart';
import '../data/question_media_store.dart';

// ---------------------------------------------------------------------------
// 跳过 / 拦截词表（报告与测试直接引用这些常量）
// ---------------------------------------------------------------------------

/// 一道题被**跳过**（题仍导入，但某一项没写）的原因。
abstract final class ExamPaperSkipReason {
  /// 客观题没有答案：`questions.answer` 留空，不造答案。
  static const String answerMissing = 'answer_missing';

  /// 没有来源解析：`questions.solution` 留空，不造解析。
  static const String solutionMissing = 'solution_missing_source';

  /// 分值缺失：`metadata.scoring.points = null`，来源照记。
  static const String scoreMissing = 'score_missing';

  /// 有分值但 `paper.json` 没写 `score_source`。
  static const String scoreSourceMissing = 'score_source_missing';

  /// `paper.json` 只给了推断分值：记录，但不采用（不伪造）。
  static const String scoreInferredNotUsed = 'score_inferred_not_used';

  /// 题型值不认识：按 `solution` 落库并记录。
  static const String questionTypeUnknown = 'question_type_unknown';

  /// 解析/答案里的图引用被去掉（图本身进答案图库，正文不再内嵌）。
  static const String figureReferenceRemovedFromText =
      'figure_reference_removed_from_text';

  /// 解析/答案里的图引用找不到对应图：去掉引用并记录。
  static const String figureReferenceUnresolved =
      'figure_reference_unresolved';

  /// 解析图文件缺失：题仍导入，图记跳过。
  static const String figureMissingAnswer = 'figure_missing_answer';

  /// 没有传 [QuestionMediaStore]：答案图不落盘，只去掉引用。
  static const String figureNotImported = 'figure_not_imported';

  /// 同一 content_id 的旧引用指向的题已不存在，删旧引用并重建。
  static const String staleQuestionRefRemoved = 'stale_question_ref_removed';

  /// 题干指纹撞到既有题（非本卷引用）：复用该题并建本卷引用。
  static const String questionFingerprintReused = 'question_fingerprint_reused';

  /// 选项内容含图片（本轮不导入选项图），只记录。
  static const String optionImageNotImported = 'option_image_not_imported';

  /// `paper.json` 里的 AI 初标（知识点/能力/难度）整卷忽略一次。
  static const String aiLabelsIgnored = 'ai_initial_labels_ignored';

  /// `paper.json` 里的知识点/标签不写产品库（`verified=false`，不采用）。
  static const String knowledgePointsNotImported =
      'knowledge_points_not_imported';

  /// 卷面来源分级无法从来源字段确认（不猜）。
  static const String sourceLevelUnknown = 'source_level_unknown';

  /// 卷里重复的题号：后出现的那道 blocked。
  static const String duplicateQuestionNumber = 'duplicate_question_number';

  /// 语文材料：`material_ids` 指向的材料原文并入题干（产品没有 materials 表）。
  static const String materialInlinedIntoStem = 'material_inlined_into_stem';

  /// 公式是图片（源 docx 的 OMML/OLE 导出 PNG），没有 LaTeX/OMML 文本；
  /// 以附件 + 「［图N］」占位保存，不假装成文本公式。
  static const String formulaImageNotLatex = 'formula_image_not_latex';

  /// 选项里的图/公式并入题干末尾「【选项配图】」区（产品选项是纯文本，
  /// 不能内嵌图片），选项正文只留「见［图N］」交叉引用。
  static const String optionImageInlinedIntoStem =
      'option_image_inlined_into_stem';

  /// 题干图没有对应占位（生物/语文的「如图」类）：图会由详情页追加到题干末尾。
  static const String stemFigureAppendedAtEnd = 'stem_figure_appended_at_end';

  /// 听力音频不可用（只有原文脚本），不假装有音频。
  static const String audioUnavailable = 'audio_unavailable';

  /// 分值的来源是卷面「分部说明」（如英语 `meta.sections[].score_note`），
  /// 不是逐题标注；原分值照记，来源照标。
  static const String scoreSourceFromSectionNote =
      'score_source_from_section_note';

  /// 答案非唯一（作文/开放性默写等）：答案原样保存，但不是唯一标准答案。
  static const String answerNonUnique = 'answer_non_unique';

  /// 来源明确没有官方答案（如 2025 语文作文）：不生成、不替代。
  static const String answerNoOfficialSource = 'answer_no_official_source';
}

/// 一道题被**拦截**（不导入）的原因。
abstract final class ExamPaperBlockReason {
  /// 题号缺失或非法（content_id 需要题号）。
  static const String invalidQuestionNumber = 'invalid_question_number';

  /// 题干为空。
  static const String emptyStem = 'empty_stem';

  /// `paper.json` 明确有未转换的 OMML 公式：题干会缺公式。
  static const String formulaUnsupported = 'unsupported_formula';

  /// 题干公式只剩公式图片（如物理卷的 `stem_blocks`）：文本缺公式。
  static const String formulaNotConverted = 'formula_not_converted';

  /// 题干图路径为空。
  static const String figurePathMissing = 'figure_path_missing';

  /// 题干图文件在卷目录里找不到（题干正文引用了图，不能裸导入）。
  static const String figureMissingStem = 'figure_missing_stem';

  /// 有题干图但调用方没传 [QuestionMediaStore]：图进不了产品库，题不能裸导入。
  static const String figureNotImportable = 'figure_not_importable_no_media_store';

  /// 题干里还有对不上的本地图引用：不猜它对应哪张图。
  static const String figureReferenceUnresolved = 'figure_reference_unresolved';

  /// `material_ids` 里的材料在卷里找不到：题依赖材料，不能裸导入。
  static const String materialMissing = 'material_missing_source';

  /// 题干里公式图片的文件找不到：公式缺了，不能假装文本公式入库。
  static const String formulaImageMissingStem = 'formula_image_missing_stem';
}

// ---------------------------------------------------------------------------
// 解析后的卷子模型（纯 JSON → 值对象，文件 IO 只在 loadDirectory / 图片）
// ---------------------------------------------------------------------------

/// 一道题的配图（卷内相对路径）。
class ExamPaperFigure {
  const ExamPaperFigure({
    required this.relativePath,
    this.role = 'stem',
    this.sha256,
    this.sourceMedia,
    this.bytes,
    this.isFormula = false,
  });

  /// 卷目录内的相对路径（`images/q06-image1.png`，POSIX 分隔）。
  final String relativePath;

  /// `stem`（题干图）或 `answer`（解析/答案图）。
  final String role;

  /// `paper.json` 里记的 sha256（只进引用摘要，Dart 侧不重算）。
  final String? sha256;

  /// `paper.json` 里的来源 media 名（`word/media/image1.png`）。
  final String? sourceMedia;

  /// `paper.json` 里记的字节数（排障用）。
  final int? bytes;

  /// 这张图是「公式图片」（源 docx 的 OMML/OLE 公式导出成 PNG），不是插图。
  ///
  /// 物理/化学的公式没有文本或 LaTeX，只能以图片附件 + 占位保存；导入结果里
  /// 记 [`ExamPaperSkipReason.formulaImageNotLatex`]，不假装文本公式。
  final bool isFormula;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': relativePath,
        'role': role,
        if (sha256 != null) 'sha256': sha256,
        if (sourceMedia != null) 'source_media': sourceMedia,
        if (bytes != null) 'bytes': bytes,
        if (isFormula) 'formula': true,
      };
}

/// 一道选择题的选项。
class ExamPaperOption {
  const ExamPaperOption({
    required this.label,
    required this.content,
    this.hasImage = false,
  });

  final String label;
  final String content;

  /// 选项内容里带图（化学材料题那种）。图片本身进题干「【选项配图】」区。
  final bool hasImage;
}

/// 选项里的图/公式（物理选项 blocks、化学选项 tokens）。
///
/// 产品 `question_options` 只有 label/content 两列文本，不能内嵌图片；这些图
/// 会作为 role=stem 附件落在题干末尾「【选项配图】」区，选项正文留
/// `（选项配图见［图N］）` 交叉引用。
class ExamPaperOptionFigure {
  const ExamPaperOptionFigure({required this.label, required this.figure});

  /// 所属选项的 label（A/B/C/D…）。
  final String label;

  final ExamPaperFigure figure;
}

/// 一道题的解析文本：原文 + 来源标记。
class ExamPaperAnalysis {
  const ExamPaperAnalysis({required this.text, this.source});

  final String text;
  final String? source;
}

/// `paper.json` 里的一道题（已按跨科差异做了容错解析）。
class ExamPaperQuestion {
  const ExamPaperQuestion({
    required this.number,
    required this.questionType,
    required this.stem,
    required this.options,
    required this.answer,
    required this.analysis,
    required this.stemFigures,
    required this.answerFigures,
    this.optionFigures = const <ExamPaperOptionFigure>[],
    this.materialText,
    this.materialIds = const <String>[],
    this.materialMissingSource = false,
    this.answerNonUnique = false,
    this.answerNonUniqueNote,
    this.answerNoOfficialSource = false,
    this.audioUnavailable = false,
    this.sourceQuestionType,
    this.answerSource,
    this.section,
    this.score,
    this.scoreSource,
    this.scoreConfirmedInSource,
    this.scoreInferred,
    this.unsupportedFormulaCount = 0,
    this.formulaNotConverted = false,
    this.hasAiLabels = false,
    this.hasKnowledgePoints = false,
  });

  final int number;
  final String questionType;
  final String stem;
  final List<ExamPaperOption> options;
  final String? answer;
  final ExamPaperAnalysis? analysis;
  final List<ExamPaperFigure> stemFigures;
  final List<ExamPaperFigure> answerFigures;

  /// 选项里的图/公式（物理选项 blocks、化学选项 tokens）。产品选项是纯文本，
  /// 导入时这些图落到题干末尾「【选项配图】」区，选项正文只留交叉引用。
  final List<ExamPaperOptionFigure> optionFigures;

  /// 材料原文（语文 `material_ids` / 英语 section 语篇），已带【材料】标题。
  final String? materialText;

  /// 材料 id（语文 `material_ids`），只进引用摘要。
  final List<String> materialIds;

  /// `material_ids` 有值但卷里找不到对应材料：题依赖材料，导入时 blocked。
  final bool materialMissingSource;

  /// 答案非唯一（作文参考样例 / 开放性默写）：答案原样保存，但不是唯一答案。
  final bool answerNonUnique;
  final String? answerNonUniqueNote;

  /// 来源明确没有官方答案（不生成、不替代）。
  final bool answerNoOfficialSource;

  /// 听力音频不可用（只有原文脚本）。
  final bool audioUnavailable;

  /// 来源题型原文（`type` / `question_type` 归一前）。
  final String? sourceQuestionType;

  final String? answerSource;
  final String? section;
  final num? score;
  final String? scoreSource;
  final bool? scoreConfirmedInSource;
  final num? scoreInferred;

  /// `unsupported_omml` 里没转换的公式数。
  final int unsupportedFormulaCount;

  /// 题干公式被抽成公式图片、正文里没有 LaTeX（物理卷那种）。
  final bool formulaNotConverted;

  /// 有 AI 初标（知识点/能力/难度），本轮不使用。
  final bool hasAiLabels;

  /// 显式写了知识点清单，本轮不写产品知识点。
  final bool hasKnowledgePoints;

  /// 选项里有图。
  bool get hasOptionImage => optionFigures.isNotEmpty;

  int get optionImageCount => optionFigures.length;

  /// 题干图 + 选项图按相对路径去重后的数量（= 实际落 role=stem 的附件数）。
  int get uniqueStemFigureCount => <String>{
        for (final figure in stemFigures) figure.relativePath,
        for (final option in optionFigures) option.figure.relativePath,
      }.length;

  /// 公式图片数（题干 + 选项 + 答案/解析）；公式没有 LaTeX 文本。
  int get formulaImageCount => <ExamPaperFigure>[
        ...stemFigures,
        ...answerFigures,
        ...optionFigures.map((option) => option.figure),
      ].where((figure) => figure.isFormula).length;

  /// 从一道题的 JSON 解析；缺失/畸形字段不抛错，交给导入阶段拦截。
  ///
  /// [materials] 是卷级 `materialId → 原文` 索引（语文 `sections[].materials[]`）；
  /// 英语的 section 语篇不需要它（`fromJson` 直接吃 `material` 字符串）。
  factory ExamPaperQuestion.fromJson(
    Map<String, Object?> json, {
    Map<String, String> materials = const <String, String>{},
  }) {
    final number = _intOf(json['number']) ?? _intOf(json['no']) ?? 0;

    // 题干：三种形态。block 形态（物理 stem_blocks / 化学 stem）按原始 block
    // 顺序重建，公式图与插图统一编号成「［图N］」；其余学科读字符串字段。
    final stemImages = <ExamPaperFigure>[];
    final blockStem = _blockStemOf(json, stemImages);
    final stem = blockStem ??
        _firstText(<Object?>[
          json['stem_md'],
          json['stem_text'],
          json['stem'],
          json['stem_lines'],
          json['prompt'],
        ]) ??
        '';
    if (blockStem == null) {
      stemImages.addAll(_figuresOf(json));
    }

    final optionFigures = <ExamPaperOptionFigure>[];
    final options = _optionsOf(
      json['options'],
      optionFigures: optionFigures,
    );
    final answerImages = <ExamPaperFigure>[];
    final answer = _answerOf(json, number, answerImages);
    final analysis = _analysisOf(json, answerImages);

    final materialIds = <String>[
      for (final raw in _asList(json['material_ids']) ?? const <Object?>[])
        if (_strOf(raw) case final id?) id,
    ];
    final materialParts = <String>[];
    var materialMissing = false;
    for (final id in materialIds) {
      final text = materials[id];
      if (text == null || text.trim().isEmpty) {
        materialMissing = true;
        continue;
      }
      materialParts.add('【材料 $id】\n${text.trim()}');
    }
    final directMaterial = _strOf(json['material'])?.trim();
    final materialText = directMaterial != null && directMaterial.isNotEmpty
        ? directMaterial
        : (materialParts.isEmpty ? null : materialParts.join('\n\n'));

    final formulaBlocks = _hasFormulaBlocks(json);
    final unsupported = _mapLength(json['unsupported_omml']) +
        _mapLength(json['unsupported_formulas']);
    final rawType = _rawTypeOf(json);
    final normalizedType = _normalizeQuestionType(rawType);
    final answerStatus = _strOf(json['answer_status'])?.trim() ?? '';
    return ExamPaperQuestion(
      number: number,
      questionType: normalizedType,
      stem: stem,
      options: options,
      answer: answer,
      analysis: analysis,
      stemFigures: stemImages,
      answerFigures: answerImages,
      optionFigures: optionFigures,
      materialText: materialText,
      materialIds: materialIds,
      materialMissingSource: materialMissing,
      answerNonUnique: _boolOf(json['answer_non_unique']) ?? false,
      answerNonUniqueNote: _strOf(json['answer_non_unique_note']),
      answerNoOfficialSource:
          _boolOf(json['official_answer_available']) == false ||
              answerStatus == 'no_official_answer_in_source',
      audioUnavailable: _boolOf(json['audio_available']) == false,
      sourceQuestionType: rawType.trim().isEmpty ? null : rawType,
      answerSource: _strOf(json['answer_source']) ??
          _mapStr(json['answer'], 'source') ??
          _mapStr(json['analysis'], 'source'),
      section: _strOf(json['section']) ?? _strOf(json['section_name']),
      score: _numOf(json['score']),
      scoreSource: _strOf(json['score_source']),
      scoreConfirmedInSource: _boolOf(json['score_confirmed_in_source_docx']) ??
          _boolOf(json['score_confirmed_in_source']),
      scoreInferred: _numOf(json['score_inferred']),
      unsupportedFormulaCount: unsupported,
      formulaNotConverted: blockStem == null &&
          formulaBlocks &&
          !stem.contains(r'$') &&
          !stem.contains(r'\('),
      hasAiLabels: json['ai_labels'] is Map ||
          json['ai_tags'] is Map ||
          json['ai_annotation'] is Map ||
          json['tagging'] is Map ||
          json['abilities'] is List ||
          json['difficulty_initial'] != null,
      hasKnowledgePoints: json['knowledge_points'] is List ||
          json['knowledge_points'] is Map,
    );
  }
}

/// 一卷 `paper.json`（+ 可选 `manifest.json`）。
class ExamPaperDocument {
  const ExamPaperDocument({
    required this.paperKey,
    required this.title,
    required this.subjectKey,
    required this.sourceLevel,
    required this.sourceLevelBasis,
    required this.questions,
    this.year,
    this.region,
    this.scoreTotalStated,
    this.directoryPath,
    this.examScope,
    this.sourceStage,
  });

  /// 内容 id 前缀（`2025-math-national1`）；每题 content_id = `<paperKey>#Q<n>`。
  final String paperKey;
  final String title;

  /// 产品学科键：`math` / `physics` / `chinese` / `chemistry` / `biology` /
  /// `english`；无法确认时为空串（不猜科目）。
  final String subjectKey;

  /// 产品来源分级词表（`gaokao` 等）。
  final String sourceLevel;

  /// `explicit`（卷面字段）/ `inferred_from_title` / `unknown`。
  final String sourceLevelBasis;

  final List<ExamPaperQuestion> questions;
  final int? year;
  final String? region;

  /// `paper.json` 自己写的卷面总分（只报告，不写库、不据此算每题分值）。
  final num? scoreTotalStated;

  /// 卷目录绝对路径；图路径相对它解析。
  final String? directoryPath;

  /// `gaokao` / `non_gaokao`；来源 `stage` 明确写「非高考」时为 `non_gaokao`
  /// （生物模块卷），不猜。
  final String? examScope;

  /// 来源 `stage` 原文（如「高二模块检测（非高考真题）」「高考」）。
  final String? sourceStage;

  bool get anyAiLabels => questions.any((question) => question.hasAiLabels);

  bool get anyKnowledgePoints =>
      questions.any((question) => question.hasKnowledgePoints);

  /// 解析 `paper.json`；[manifestJson] 是可选 `manifest.json`（数学卷的
  /// subject/year/region 只在 manifest 里，[读] 2025-math-national1/manifest.json）。
  factory ExamPaperDocument.fromJson(
    Map<String, Object?> paperJson, {
    Map<String, Object?>? manifestJson,
    String? directoryPath,
  }) {
    final meta = _PaperMeta.from(paperJson, manifestJson);
    return ExamPaperDocument(
      paperKey: meta.paperKey,
      title: meta.title,
      subjectKey: meta.subjectKey,
      sourceLevel: meta.sourceLevel,
      sourceLevelBasis: meta.sourceLevelBasis,
      questions: meta.questions,
      year: meta.year,
      region: meta.region,
      scoreTotalStated: meta.scoreTotalStated,
      directoryPath: directoryPath,
      examScope: meta.examScope,
      sourceStage: meta.sourceStage,
    );
  }

  /// 从卷目录读 `paper.json` 与可选 `manifest.json`；同时把目录记为图路径根。
  ///
  /// 文件不存在/不是 JSON 时抛 [StateError]（这是调用方输入错误，不是跳过项）。
  factory ExamPaperDocument.loadDirectory(String directoryPath) {
    final paperFile = File(p.join(directoryPath, 'paper.json'));
    if (!paperFile.existsSync()) {
      throw StateError('paper.json 不存在：${paperFile.path}');
    }
    final manifestFile = File(p.join(directoryPath, 'manifest.json'));
    return ExamPaperDocument.fromJson(
      _decodeJsonObject(paperFile, 'paper.json'),
      manifestJson: manifestFile.existsSync()
          ? _decodeJsonObject(manifestFile, 'manifest.json')
          : null,
      directoryPath: Directory(directoryPath).absolute.path,
    );
  }
}

/// 卷级 meta 的解析结果（内部用）。
class _PaperMeta {
  const _PaperMeta({
    required this.paperKey,
    required this.title,
    required this.subjectKey,
    required this.sourceLevel,
    required this.sourceLevelBasis,
    required this.questions,
    this.year,
    this.region,
    this.scoreTotalStated,
    this.examScope,
    this.sourceStage,
  });

  final String paperKey;
  final String title;
  final String subjectKey;
  final String sourceLevel;
  final String sourceLevelBasis;
  final List<ExamPaperQuestion> questions;
  final int? year;
  final String? region;
  final num? scoreTotalStated;
  final String? examScope;
  final String? sourceStage;

  factory _PaperMeta.from(
    Map<String, Object?> paperJson,
    Map<String, Object?>? manifestJson,
  ) {
    final title = _firstText(<Object?>[
          paperJson['title'],
          manifestJson?['title'],
        ]) ??
        '';
    final subjectRaw =
        _metaValue(paperJson, manifestJson, const <String>['subject']) ?? '';
    final yearRaw = _metaValue(
      paperJson,
      manifestJson,
      const <String>['year', 'exam_year'],
    );
    final regionRaw = _metaValue(
      paperJson,
      manifestJson,
      const <String>['region', 'province', 'area'],
    );
    final scoreRaw = _metaValue(
      paperJson,
      manifestJson,
      const <String>[
        'score_total',
        'full_score',
        'full_score_from_source',
        'full_score_stated_in_source',
      ],
    );
    final stage = _strOf(_metaValue(
      paperJson,
      manifestJson,
      const <String>['stage'],
    ));
    final level = _sourceLevelOf(paperJson, manifestJson, title);
    final examScope = switch (level.basis) {
      'stage_non_gaokao' => 'non_gaokao',
      'explicit_stage' || 'inferred_from_title' || 'inferred_from_exam_type' =>
        'gaokao',
      _ => null,
    };
    return _PaperMeta(
      paperKey: (_firstText(<Object?>[
                paperJson['paper_id'],
                manifestJson?['paper_id'],
              ]) ??
              '')
          .trim(),
      title: title.trim(),
      subjectKey: _normalizeSubject(subjectRaw),
      sourceLevel: level.level,
      sourceLevelBasis: level.basis,
      questions: _questionsOf(paperJson),
      year: _intOf(yearRaw),
      region: _strOf(regionRaw),
      scoreTotalStated: _numOf(scoreRaw),
      examScope: examScope,
      sourceStage: stage,
    );
  }
}

// ---------------------------------------------------------------------------
// 导入结果
// ---------------------------------------------------------------------------

/// 一个被跳过/拦截的映射项。
class ExamPaperImportIssue {
  const ExamPaperImportIssue({
    required this.code,
    required this.detail,
    this.questionNumber,
  });

  final String code;
  final String detail;
  final int? questionNumber;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'detail': detail,
        if (questionNumber != null) 'question_number': questionNumber,
      };

  @override
  String toString() => '$code（$detail）';
}

/// 一道题的导入结局。
class ExamPaperQuestionImport {
  const ExamPaperQuestionImport({
    required this.number,
    required this.contentId,
    required this.questionId,
    required this.serialNo,
    required this.created,
    required this.reused,
    required this.optionCount,
    required this.figureCount,
    required this.figuresImported,
    this.score,
    this.scoreSource,
  });

  final int number;
  final String contentId;

  /// 产品 `questions.id`（`q-<uuid>`）；blocked 的题不出现在这里。
  final String questionId;
  final int? serialNo;
  final bool created;
  final bool reused;
  final int optionCount;
  final int figureCount;
  final int figuresImported;
  final num? score;
  final String? scoreSource;

  Map<String, Object?> toJson() => <String, Object?>{
        'number': number,
        'content_id': contentId,
        'question_id': questionId,
        'serial_no': serialNo,
        'created': created,
        'reused': reused,
        'option_count': optionCount,
        'figure_count': figureCount,
        'figures_imported': figuresImported,
        'score': score,
        'score_source': scoreSource,
      };
}

/// 一次整卷导入的结局。
enum ExamPaperImportStatus {
  /// 全部题映射完成，没有跳过/拦截项。
  imported,

  /// 有题导入成功，但有被跳过或拦截的项。
  importedWithSkips,

  /// 输入不合法或全部题被拦截：没有写任何一行。
  blocked;

  String get wireValue => name;
}

/// 一次整卷导入的完整报告（不写日志文件、不建第二份状态表）。
class ExamPaperImportResult {
  const ExamPaperImportResult({
    required this.paperKey,
    required this.status,
    required this.questions,
    required this.skipped,
    required this.blocked,
    required this.scoreSumFromQuestions,
    required this.scoreTotalStated,
    this.title = '',
    this.subjectKey = '',
    this.sourceLevel = 'unknown',
    this.sourceLevelBasis = 'unknown',
    this.year,
    this.region,
    this.examScope,
    this.sourceStage,
  });

  /// 整卷被拒（paperKey/题干/题号不合法等）：没有写任何一行。
  factory ExamPaperImportResult.blocked({
    required String paperKey,
    required List<ExamPaperImportIssue> blocked,
    String title = '',
    String subjectKey = '',
    String sourceLevel = 'unknown',
    String sourceLevelBasis = 'unknown',
    int? year,
    String? region,
    num? scoreTotalStated,
    String? examScope,
    String? sourceStage,
  }) {
    return ExamPaperImportResult(
      paperKey: paperKey,
      status: ExamPaperImportStatus.blocked,
      title: title,
      subjectKey: subjectKey,
      sourceLevel: sourceLevel,
      sourceLevelBasis: sourceLevelBasis,
      year: year,
      region: region,
      questions: const <ExamPaperQuestionImport>[],
      skipped: const <ExamPaperImportIssue>[],
      blocked: List<ExamPaperImportIssue>.unmodifiable(blocked),
      scoreSumFromQuestions: 0,
      scoreTotalStated: scoreTotalStated,
      examScope: examScope,
      sourceStage: sourceStage,
    );
  }

  final String paperKey;
  final ExamPaperImportStatus status;
  final String title;
  final String subjectKey;
  final String sourceLevel;

  /// `explicit` / `inferred_from_title` / `unknown`。
  final String sourceLevelBasis;

  final int? year;
  final String? region;

  /// `gaokao` / `non_gaokao`；来源 `stage` 明确写「非高考」时为 `non_gaokao`。
  final String? examScope;

  /// 来源 `stage` 原文。
  final String? sourceStage;

  final List<ExamPaperQuestionImport> questions;
  final List<ExamPaperImportIssue> skipped;
  final List<ExamPaperImportIssue> blocked;

  /// 实际写进引用摘要的分值之和（缺分值的题按 0 计，只用于对账）。
  final num scoreSumFromQuestions;

  /// `paper.json` 自己写的卷面总分（原样报告，不参与写库）。
  final num? scoreTotalStated;

  int get questionCount => questions.length;
  int get createdCount => questions.where((question) => question.created).length;
  int get reusedCount => questions.where((question) => question.reused).length;
  int get blockedCount => blocked.length;
  int get skippedCount => skipped.length;
  int get optionCount =>
      questions.fold(0, (sum, question) => sum + question.optionCount);
  int get figureCount =>
      questions.fold(0, (sum, question) => sum + question.figureCount);
  int get figuresImported =>
      questions.fold(0, (sum, question) => sum + question.figuresImported);
  int get contentRefCount => questions.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'paper_key': paperKey,
        'title': title,
        'status': status.wireValue,
        'subject': subjectKey,
        'source_level': sourceLevel,
        'source_level_basis': sourceLevelBasis,
        if (examScope != null) 'exam_scope': examScope,
        if (sourceStage != null) 'source_stage': sourceStage,
        'year': year,
        'region': region,
        'question_count': questionCount,
        'created': createdCount,
        'reused': reusedCount,
        'blocked_count': blockedCount,
        'skipped_count': skippedCount,
        'option_count': optionCount,
        'figure_count': figureCount,
        'figures_imported': figuresImported,
        'content_ref_count': contentRefCount,
        'score_sum_from_questions': scoreSumFromQuestions,
        'score_total_stated': scoreTotalStated,
        'questions': <Map<String, Object?>>[
          for (final question in questions) question.toJson(),
        ],
        'skipped': <Map<String, Object?>>[
          for (final issue in skipped) issue.toJson(),
        ],
        'blocked': <Map<String, Object?>>[
          for (final issue in blocked) issue.toJson(),
        ],
      };
}

// ---------------------------------------------------------------------------
// 导入服务
// ---------------------------------------------------------------------------

/// 整卷 `paper.json` → 产品题库的导入服务。
///
/// 注入的仓储必须与 [db] 是同一个库：事务回滚只对同一个数据库连接生效。
class ExamPaperQuestionImporter {
  ExamPaperQuestionImporter(
    AppDatabase db, {
    QuestionRepository? questions,
    ContentRefRepository? contentRefs,
    QuestionMediaStore? mediaStore,
    DateTime? now,
  })  : _db = db,
        _questions = questions ?? QuestionRepository(db),
        _contentRefs = contentRefs ?? ContentRefRepository(db),
        _mediaStore = mediaStore,
        _now = now;

  final AppDatabase _db;
  final QuestionRepository _questions;
  final ContentRefRepository _contentRefs;

  /// 图片落盘口（`QuestionMediaStore`）。不传时：题干图题 blocked（图进不了
  /// 产品库就不能裸导入），解析图只去掉正文引用并记跳过。
  final QuestionMediaStore? _mediaStore;

  final DateTime? _now;

  /// paperKey 不许带空白/#：content_id 是 `<paperKey>#Q<n>`。
  static final RegExp _paperKeyPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// 导入整卷。整体一个事务：失败抛错并回滚，不返回半批报告。
  Future<ExamPaperImportResult> importPaper(ExamPaperDocument paper) {
    final blocked = <ExamPaperImportIssue>[];
    if (!_paperKeyPattern.hasMatch(paper.paperKey)) {
      blocked.add(ExamPaperImportIssue(
        code: 'invalid_paper_key',
        detail: '"${paper.paperKey}"',
      ));
    }
    if (paper.questions.isEmpty) {
      blocked.add(const ExamPaperImportIssue(
        code: 'no_questions',
        detail: 'paper.json.questions 为空或没有可解析的题号',
      ));
    }
    if (blocked.isNotEmpty) {
      return Future<ExamPaperImportResult>.value(
        ExamPaperImportResult.blocked(
          paperKey: paper.paperKey,
          blocked: blocked,
          title: paper.title,
          subjectKey: paper.subjectKey,
          sourceLevel: paper.sourceLevel,
          sourceLevelBasis: paper.sourceLevelBasis,
          year: paper.year,
          region: paper.region,
          scoreTotalStated: paper.scoreTotalStated,
          examScope: paper.examScope,
          sourceStage: paper.sourceStage,
        ),
      );
    }
    return _db.transaction(() => _import(paper));
  }

  Future<ExamPaperImportResult> _import(ExamPaperDocument paper) async {
    final now = _now ?? DateTime.now();
    final skipped = <ExamPaperImportIssue>[];
    final blocked = <ExamPaperImportIssue>[];
    final imported = <ExamPaperQuestionImport>[];
    num scoreSum = 0;
    var anyScore = false;

    // 整卷级跳过项：只记一次，够人工核对，不按题刷屏。
    if (paper.anyAiLabels) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.aiLabelsIgnored,
        '${paper.questions.where((question) => question.hasAiLabels).length} 道题带 AI 初标；'
            '未写知识点/能力点/难度',
      );
    }
    if (paper.anyKnowledgePoints) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.knowledgePointsNotImported,
        '${paper.questions.where((question) => question.hasKnowledgePoints).length} 道题显式带知识点；'
            '已验证性未知，未建产品知识点',
      );
    }
    if (paper.sourceLevelBasis == 'unknown') {
      _addIssue(
        skipped,
        ExamPaperSkipReason.sourceLevelUnknown,
        'paper.json 没有可确认的来源分级；按 unknown 入库，不猜 gaokao',
      );
    }

    // 六科结构差异的整卷级事实：各记一次，报告里能逐条核对。
    final materialQuestions = paper.questions
        .where((question) =>
            question.materialText != null &&
            question.materialText!.trim().isNotEmpty)
        .length;
    if (materialQuestions > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.materialInlinedIntoStem,
        '$materialQuestions 道题的材料原文并入题干（产品没有 materials 表）',
      );
    }
    final optionFigureQuestions =
        paper.questions.where((question) => question.optionFigures.isNotEmpty).length;
    if (optionFigureQuestions > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.optionImageInlinedIntoStem,
        '$optionFigureQuestions 道题的选项图/公式图并入题干「【选项配图】」区',
      );
    }
    final formulaImageCount = paper.questions
        .fold<int>(0, (sum, question) => sum + question.formulaImageCount);
    if (formulaImageCount > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.formulaImageNotLatex,
        '$formulaImageCount 处公式以图片附件保存（未转 LaTeX/OMML，不假装文本）',
      );
    }
    final audioUnavailableCount =
        paper.questions.where((question) => question.audioUnavailable).length;
    if (audioUnavailableCount > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.audioUnavailable,
        '$audioUnavailableCount 道听力题音频不可用（只有原文脚本）',
      );
    }
    final sectionScoreCount = paper.questions
        .where((question) => question.scoreSource == 'section_score_note')
        .length;
    if (sectionScoreCount > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.scoreSourceFromSectionNote,
        '$sectionScoreCount 道题的分值来源是卷面分部说明（section_score_note），不是逐题标注',
      );
    }
    final placeholderPattern = RegExp(r'[［\[【]\s*图\s*[0-9]');
    final inlineRefPattern = RegExp(r'!\[[^\]\n]*\]\(|\[IMG:');
    final unplacedFigureCount = paper.questions
        .where((question) =>
            question.stemFigures.isNotEmpty &&
            !placeholderPattern.hasMatch(question.stem) &&
            !inlineRefPattern.hasMatch(question.stem))
        .length;
    if (unplacedFigureCount > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.stemFigureAppendedAtEnd,
        '$unplacedFigureCount 道题的题干图没有占位（如「如图」），详情页会把图追加到题干末尾',
      );
    }

    final seenNumbers = <int>{};
    for (final question in paper.questions) {
      if (question.number < 1) {
        blocked.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.invalidQuestionNumber,
          detail: '题号 ${question.number}',
          questionNumber: question.number,
        ));
        continue;
      }
      if (!seenNumbers.add(question.number)) {
        blocked.add(ExamPaperImportIssue(
          code: ExamPaperSkipReason.duplicateQuestionNumber,
          detail: '题号 ${question.number} 在本卷已出现',
          questionNumber: question.number,
        ));
        continue;
      }
      final contentId = '${paper.paperKey}#Q${question.number}';

      // ---- 1) 幂等：同 content_id 已有引用 → 复用，不新建题/选项/图 ----
      final existing = await _existingQuestionRef(contentId);
      if (existing != null) {
        final questionRow = await _questions.byId(existing.objectId);
        if (questionRow != null) {
          imported.add(ExamPaperQuestionImport(
            number: question.number,
            contentId: contentId,
            questionId: questionRow.id,
            serialNo: questionRow.serialNo,
            created: false,
            reused: true,
            optionCount: (await _questions.optionsOf(questionRow.id)).length,
            figureCount: question.uniqueStemFigureCount +
                question.answerFigures.length,
            figuresImported: 0,
            score: question.score,
            scoreSource: question.scoreSource,
          ));
          if (question.score != null) {
            scoreSum += question.score!;
            anyScore = true;
          }
          continue;
        }
        // 引用还在、题被删了：删旧引用，走重新入库。
        await _contentRefs.delete(
          contentId: existing.contentId,
          objectType: existing.objectType,
          objectId: existing.objectId,
          role: existing.role,
        );
        _addIssue(
          skipped,
          ExamPaperSkipReason.staleQuestionRefRemoved,
          '$contentId -> ${existing.objectId}',
          questionNumber: question.number,
        );
      }

      // ---- 2) 逐题拦截检查（坏题不入库） ----
      final fatal = <ExamPaperImportIssue>[];
      if (question.stem.trim().isEmpty) {
        fatal.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.emptyStem,
          detail: contentId,
          questionNumber: question.number,
        ));
      }
      if (question.unsupportedFormulaCount > 0) {
        fatal.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.formulaUnsupported,
          detail: '${question.unsupportedFormulaCount} 处公式未转换（unsupported_omml）',
          questionNumber: question.number,
        ));
      }
      if (question.formulaNotConverted) {
        fatal.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.formulaNotConverted,
          detail: '题干公式只有图片、正文没有 LaTeX（stem_blocks.formula）',
          questionNumber: question.number,
        ));
      }
      if (question.materialMissingSource) {
        // 题依赖材料（阅读/语篇），材料找不到就不能只导题目。
        fatal.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.materialMissing,
          detail: '$contentId material_ids=${question.materialIds.join(',')} 在卷里没有对应材料',
          questionNumber: question.number,
        ));
      }
      final figurePlan = await _planFigures(
        question: question,
        paper: paper,
        fatal: fatal,
        skipped: skipped,
      );
      if (fatal.isNotEmpty) {
        blocked.addAll(fatal);
        continue;
      }

      // ---- 3) 文本：材料/选项配图并入题干、题干图换占位、解析图引用去掉 ----
      final optionContents = _optionContents(question);
      final stem = _rewriteStemFigures(
        question: question,
        stem: _assembleStem(question),
        plan: figurePlan,
        fatal: fatal,
      );
      if (fatal.isNotEmpty) {
        blocked.addAll(fatal);
        continue;
      }
      final answerRaw = question.answer;
      final answer = _stripFigureReferences(
        answerRaw,
        skipped: skipped,
        questionNumber: question.number,
        field: 'answer',
      );
      final analysisRaw = question.analysis?.text;
      final solution = _stripFigureReferences(
        analysisRaw,
        skipped: skipped,
        questionNumber: question.number,
        field: 'analysis',
      );
      if (answer == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.answerMissing,
          contentId,
          questionNumber: question.number,
        );
      }
      if (solution == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.solutionMissing,
          contentId,
          questionNumber: question.number,
        );
      }
      if (question.score == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.scoreMissing,
          question.scoreSource ?? 'no score_source',
          questionNumber: question.number,
        );
      } else if (question.scoreSource == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.scoreSourceMissing,
          '$contentId score=${question.score}',
          questionNumber: question.number,
        );
      }
      if (question.score == null && question.scoreInferred != null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.scoreInferredNotUsed,
          '$contentId score_inferred=${question.scoreInferred}',
          questionNumber: question.number,
        );
      }
      if (question.answerNonUnique) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.answerNonUnique,
          question.answerNonUniqueNote?.trim().isNotEmpty == true
              ? '$contentId ${question.answerNonUniqueNote!.trim()}'
              : '$contentId 答案非唯一（参考样例/开放性作答）',
          questionNumber: question.number,
        );
      }
      if (question.answerNoOfficialSource) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.answerNoOfficialSource,
          '$contentId 来源明确没有官方答案，未生成答案',
          questionNumber: question.number,
        );
      }

      // ---- 4) 入库题目本体（答案/解析只来自 paper.json） ----
      final ingested = await _questions.ingest(
        QuestionDraft(
          stem: stem,
          answer: answer,
          solution: solution,
          subjectKey: paper.subjectKey,
          questionType: question.questionType,
          sourceLevel: paper.sourceLevel,
          sourceLabel: paper.title,
          year: paper.year,
          region: paper.region,
          textFormat: 'markdown',
          origin: 'exam_paper',
          state: 'structured',
          options: <QuestionOptionDraft>[
            for (var i = 0; i < question.options.length; i++)
              QuestionOptionDraft(
                label: question.options[i].label,
                content: optionContents[i],
                isCorrect: _isCorrectOption(
                  question.options[i].label,
                  answer,
                  question.questionType,
                ),
                sortOrder: i,
              ),
          ],
        ),
        now: now,
      );
      if (!ingested.created &&
          ingested.question.stem != stem.trim()) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.questionFingerprintReused,
          '$contentId 撞到既有题 ${ingested.question.id}（题干不同，未覆盖）',
          questionNumber: question.number,
        );
      }

      // ---- 5) 图落盘（题干图 role=stem；解析图 role=answer） ----
      var figuresImported = 0;
      final figureSummaries = <Map<String, Object?>>[];
      for (final planned in figurePlan.stem) {
        final saved = await _saveFigure(
          questionId: ingested.question.id,
          planned: planned,
          role: QuestionImageRole.stem,
          fatal: fatal,
          skipped: skipped,
          questionNumber: question.number,
        );
        if (saved) {
          figuresImported += 1;
        }
        figureSummaries.add(<String, Object?>{
          'path': planned.figure.relativePath,
          'role': 'stem',
          'imported': saved,
          if (planned.figure.sha256 != null) 'sha256': planned.figure.sha256,
        });
      }
      for (final planned in figurePlan.answer) {
        final saved = await _saveFigure(
          questionId: ingested.question.id,
          planned: planned,
          role: QuestionImageRole.answer,
          fatal: fatal,
          skipped: skipped,
          questionNumber: question.number,
        );
        if (saved) {
          figuresImported += 1;
        }
        figureSummaries.add(<String, Object?>{
          'path': planned.figure.relativePath,
          'role': 'answer',
          'imported': saved,
          if (planned.figure.sha256 != null) 'sha256': planned.figure.sha256,
        });
      }
      if (fatal.isNotEmpty) {
        // 图写失败由抛错回滚；这里只为防御性保留（正常不会走到）。
        blocked.addAll(fatal);
        continue;
      }

      // ---- 6) content_refs：<paperKey>#Q<n> ↔ question ----
      await _contentRefs.upsert(
        contentId: contentId,
        objectType: ContentObjectType.question,
        objectId: ingested.question.id,
        role: ContentRefRole.sourcePackage,
        subject: paper.subjectKey,
        metadata: _questionMetadata(
          paper: paper,
          question: question,
          figures: figureSummaries,
        ),
      );
      imported.add(ExamPaperQuestionImport(
        number: question.number,
        contentId: contentId,
        questionId: ingested.question.id,
        serialNo: ingested.question.serialNo,
        created: ingested.created,
        reused: !ingested.created,
        optionCount: question.options.length,
        figureCount:
            question.uniqueStemFigureCount + question.answerFigures.length,
        figuresImported: figuresImported,
        score: question.score,
        scoreSource: question.scoreSource,
      ));
      if (question.score != null) {
        scoreSum += question.score!;
        anyScore = true;
      }
    }

    final status = imported.isEmpty && blocked.isNotEmpty
        ? ExamPaperImportStatus.blocked
        : (skipped.isEmpty && blocked.isEmpty
            ? ExamPaperImportStatus.imported
            : ExamPaperImportStatus.importedWithSkips);
    return ExamPaperImportResult(
      paperKey: paper.paperKey,
      status: status,
      title: paper.title,
      subjectKey: paper.subjectKey,
      sourceLevel: paper.sourceLevel,
      sourceLevelBasis: paper.sourceLevelBasis,
      year: paper.year,
      region: paper.region,
      examScope: paper.examScope,
      sourceStage: paper.sourceStage,
      questions: List<ExamPaperQuestionImport>.unmodifiable(imported),
      skipped: List<ExamPaperImportIssue>.unmodifiable(skipped),
      blocked: List<ExamPaperImportIssue>.unmodifiable(blocked),
      scoreSumFromQuestions: anyScore ? scoreSum : 0,
      scoreTotalStated: paper.scoreTotalStated,
    );
  }

  // -------------------------------------------------------------------------
  // 幂等 / 图 / 文本
  // -------------------------------------------------------------------------

  /// 同一 content_id 上已存在的题目引用。
  Future<ContentRefRow?> _existingQuestionRef(String contentId) async {
    final refs = await _contentRefs.listByContentId(contentId);
    for (final ref in refs) {
      if (ref.objectType == ContentObjectType.question &&
          ref.role == ContentRefRole.sourcePackage) {
        return ref;
      }
    }
    return null;
  }

  /// 算出本题要落哪些图；题干图缺失/无法落盘直接进 [fatal]。
  Future<_FigurePlan> _planFigures({
    required ExamPaperQuestion question,
    required ExamPaperDocument paper,
    required List<ExamPaperImportIssue> fatal,
    required List<ExamPaperImportIssue> skipped,
  }) async {
    final stem = <_PlannedFigure>[];
    final answer = <_PlannedFigure>[];
    final directory = paper.directoryPath;

    // 题干图 + 选项图（同一路径只落一份附件）按全局编号顺序落 role=stem；
    // 题干 block 里的「［图N］」与选项正文「（选项配图见［图N］）」共用这套编号。
    for (final figure in _orderedStemFigures(question)) {
      final resolved = _resolveFigureFile(
        figure: figure,
        directory: directory,
      );
      if (resolved == null) {
        fatal.add(ExamPaperImportIssue(
          code: figure.relativePath.trim().isEmpty
              ? ExamPaperBlockReason.figurePathMissing
              : (figure.isFormula
                  ? ExamPaperBlockReason.formulaImageMissingStem
                  : ExamPaperBlockReason.figureMissingStem),
          detail: figure.relativePath,
          questionNumber: question.number,
        ));
        continue;
      }
      if (_mediaStore == null) {
        fatal.add(ExamPaperImportIssue(
          code: ExamPaperBlockReason.figureNotImportable,
          detail: '${figure.relativePath} 需要 QuestionMediaStore',
          questionNumber: question.number,
        ));
        continue;
      }
      stem.add(_PlannedFigure(figure: figure, absolutePath: resolved));
    }

    for (final figure in question.answerFigures) {
      final resolved = _resolveFigureFile(
        figure: figure,
        directory: directory,
      );
      if (resolved == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.figureMissingAnswer,
          figure.relativePath,
          questionNumber: question.number,
        );
        continue;
      }
      if (_mediaStore == null) {
        _addIssue(
          skipped,
          ExamPaperSkipReason.figureNotImported,
          figure.relativePath,
          questionNumber: question.number,
        );
        continue;
      }
      answer.add(_PlannedFigure(figure: figure, absolutePath: resolved));
    }
    return _FigurePlan(stem: stem, answer: answer);
  }

  /// 卷内相对路径 → 绝对路径；文件不在返回 null。
  String? _resolveFigureFile({
    required ExamPaperFigure figure,
    required String? directory,
  }) {
    final relative = figure.relativePath.trim();
    if (relative.isEmpty || directory == null || directory.isEmpty) {
      return null;
    }
    final normalized = relative.replaceAll(r'\', '/');
    final candidate = File(p.joinAll(<String>[directory, ...normalized.split('/')]));
    return candidate.existsSync() ? candidate.absolute.path : null;
  }

  /// 题干里的图引用 → `［图N］` 占位（N 从 1 起，对应题干图顺序）。
  ///
  /// [stem] 是已经拼好材料/选项配图的题干正文（block 形态的题自带占位，这里
  /// 只处理 `![...](...)` / `[IMG:...]` 这类原始引用）。
  ///
  /// 对不上的本地图引用进 [fatal]（不猜它对应哪张图）；`http(s)` 外链原样保留
  /// （不是卷内图，不落 attachments）。
  String _rewriteStemFigures({
    required ExamPaperQuestion question,
    required String stem,
    required _FigurePlan plan,
    required List<ExamPaperImportIssue> fatal,
  }) {
    final byPath = <String, int>{};
    final byBasename = <String, int>{};
    for (var i = 0; i < plan.stem.length; i++) {
      final relative = plan.stem[i].figure.relativePath;
      if (relative.isEmpty) {
        continue;
      }
      byPath[_normalizeFigureKey(relative)] = i;
      byBasename[p.basename(relative)] = i;
      final media = plan.stem[i].figure.sourceMedia;
      if (media != null && media.trim().isNotEmpty) {
        byBasename[p.basename(media.trim().replaceAll(r'\', '/'))] = i;
      }
    }
    var text = stem;
    final unresolved = <String>[];
    final markdownImage = RegExp(r'!\[[^\]\n]*\]\(([^)\n]+)\)');
    text = text.replaceAllMapped(markdownImage, (match) {
      final raw = match.group(1)!.trim();
      final resolved = _figureOrderOf(raw, byPath, byBasename);
      if (resolved != null) {
        return '［图${resolved + 1}］';
      }
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return match.group(0)!;
      }
      unresolved.add(raw);
      return match.group(0)!;
    });
    final imageToken = RegExp(r'\[IMG:([^\]\n]+)\]');
    text = text.replaceAllMapped(imageToken, (match) {
      final raw = match.group(1)!.trim();
      final resolved = _figureOrderOf(raw, byPath, byBasename);
      if (resolved != null) {
        return '［图${resolved + 1}］';
      }
      unresolved.add(raw);
      return match.group(0)!;
    });
    if (unresolved.isNotEmpty) {
      fatal.add(ExamPaperImportIssue(
        code: ExamPaperBlockReason.figureReferenceUnresolved,
        detail: unresolved.join(', '),
        questionNumber: question.number,
      ));
    }
    return text;
  }

  /// 拼最终题干：材料原文 →「【题目】」→ 题干 →「【选项配图】」区。
  ///
  /// 产品没有 materials 表、选项也没有图片列，所以：
  ///  * 语文 `material_ids` / 英语 section 语篇的材料原文并入题干（带来源标题）；
  ///  * 选项里的图/公式落到 role=stem 附件，题干末尾列
  ///    `A．［图N］` 这样的对照，选项正文留「（选项配图见［图N］）」。
  String _assembleStem(ExamPaperQuestion question) {
    final buffer = StringBuffer();
    final material = question.materialText?.trim() ?? '';
    if (material.isNotEmpty) {
      buffer.write(material);
      buffer.write('\n\n【题目】\n');
    }
    buffer.write(question.stem);
    if (question.optionFigures.isNotEmpty) {
      final indexByPath = _stemFigureIndexByPath(question);
      buffer.write('\n\n【选项配图】');
      for (final optionFigure in question.optionFigures) {
        final index = indexByPath[optionFigure.figure.relativePath];
        if (index == null) {
          continue;
        }
        buffer.write('\n${optionFigure.label}．［图${index + 1}］');
      }
    }
    return _cleanText(buffer.toString());
  }

  /// 选项正文：把解析阶段的 `⟦OPT:x⟧` 标记换成「（选项配图见［图N］）」。
  List<String> _optionContents(ExamPaperQuestion question) {
    final contents = <String>[
      for (final option in question.options) option.content,
    ];
    if (question.optionFigures.isEmpty) {
      return contents;
    }
    final indexByPath = _stemFigureIndexByPath(question);
    final firstByLabel = <String, int>{};
    for (final optionFigure in question.optionFigures) {
      final index = indexByPath[optionFigure.figure.relativePath];
      if (index == null) {
        continue;
      }
      firstByLabel.putIfAbsent(optionFigure.label, () => index);
    }
    final marker = RegExp(r'⟦OPT:([^⟧\n]+)⟧');
    for (var i = 0; i < contents.length; i++) {
      contents[i] = contents[i].replaceAllMapped(marker, (match) {
        final label = match.group(1)!.trim();
        final order = firstByLabel[label];
        return order == null ? '（选项配图）' : '［图${order + 1}］';
      });
    }
    return contents;
  }

  /// 题干图 + 选项图按相对路径去重后的全局编号（先出现者拿编号）。
  ///
  /// 同一张图（化学 Q10、物理 Q6/Q10 会出现）在题干和选项里都引用时只落一份
  /// 附件、共用一个「［图N］」，不重复保存字节。
  static Map<String, int> _stemFigureIndexByPath(ExamPaperQuestion question) {
    final indexByPath = <String, int>{};
    var next = 0;
    for (final figure in <ExamPaperFigure>[
      ...question.stemFigures,
      ...question.optionFigures.map((option) => option.figure),
    ]) {
      if (indexByPath.containsKey(figure.relativePath)) {
        continue;
      }
      indexByPath[figure.relativePath] = next;
      next += 1;
    }
    return indexByPath;
  }

  /// 题干图 + 选项图去重后的有序列表（`_planFigures` 按这个顺序落盘）。
  static List<ExamPaperFigure> _orderedStemFigures(
    ExamPaperQuestion question,
  ) {
    final seen = <String>{};
    final ordered = <ExamPaperFigure>[];
    for (final figure in <ExamPaperFigure>[
      ...question.stemFigures,
      ...question.optionFigures.map((option) => option.figure),
    ]) {
      if (!seen.add(figure.relativePath)) {
        continue;
      }
      ordered.add(figure);
    }
    return ordered;
  }

  /// 解析/答案正文里的图引用：本轮不内嵌（图进答案图库），只去掉引用。
  ///
  /// 返回 null 表示这段正文本来就没有内容。
  String? _stripFigureReferences(
    String? raw, {
    required List<ExamPaperImportIssue> skipped,
    required int questionNumber,
    required String field,
  }) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    var removed = 0;
    final markdownImage = RegExp(r'!\[[^\]\n]*\]\(([^)\n]+)\)');
    var next = text.replaceAllMapped(markdownImage, (match) {
      final target = match.group(1)!.trim();
      if (target.startsWith('http://') || target.startsWith('https://')) {
        return match.group(0)!;
      }
      removed += 1;
      return '';
    });
    final imageToken = RegExp(r'\[IMG:([^\]\n]+)\]');
    next = next.replaceAllMapped(imageToken, (match) {
      removed += 1;
      return '';
    });
    if (removed > 0) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.figureReferenceRemovedFromText,
        '$field: 去掉 $removed 处图引用（图进答案图库）',
        questionNumber: questionNumber,
      );
    }
    final collapsed = next
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return collapsed.isEmpty ? null : collapsed;
  }

  /// 把一张图存进 `QuestionMediaStore`（同一题内按 role 顺序补 sortOrder）。
  Future<bool> _saveFigure({
    required String questionId,
    required _PlannedFigure planned,
    required String role,
    required List<ExamPaperImportIssue> fatal,
    required List<ExamPaperImportIssue> skipped,
    required int questionNumber,
  }) async {
    final store = _mediaStore;
    if (store == null) {
      _addIssue(
        skipped,
        ExamPaperSkipReason.figureNotImported,
        planned.figure.relativePath,
        questionNumber: questionNumber,
      );
      return false;
    }
    final file = File(planned.absolutePath);
    if (!file.existsSync()) {
      _addIssue(
        skipped,
        role == QuestionImageRole.stem
            ? ExamPaperSkipReason.figureNotImported
            : ExamPaperSkipReason.figureMissingAnswer,
        planned.figure.relativePath,
        questionNumber: questionNumber,
      );
      return false;
    }
    final Uint8List bytes = await file.readAsBytes();
    final existing = await store.list(questionId, role: role);
    final order = existing.isEmpty
        ? 0
        : existing
                .map((image) => image.sortOrder)
                .reduce((a, b) => a > b ? a : b) +
            1;
    await store.save(
      questionId: questionId,
      fileName: p.basename(planned.figure.relativePath),
      bytes: bytes,
      sortOrder: order,
      role: role,
    );
    return true;
  }

  /// 题目引用摘要：只有 id/题号/来源/分值/图摘要，**不存题干/答案/解析正文**。
  static Map<String, Object?> _questionMetadata({
    required ExamPaperDocument paper,
    required ExamPaperQuestion question,
    required List<Map<String, Object?>> figures,
  }) {
    return <String, Object?>{
      'paper_id': paper.paperKey,
      'paper_title': paper.title,
      'question_number': question.number,
      'question_type': question.questionType,
      if (question.sourceQuestionType != null &&
          question.sourceQuestionType != question.questionType)
        'original_question_type': question.sourceQuestionType,
      if (question.section != null) 'section': question.section,
      'subject': paper.subjectKey,
      'source_level': paper.sourceLevel,
      'source_level_basis': paper.sourceLevelBasis,
      if (paper.examScope != null) 'exam_scope': paper.examScope,
      if (paper.sourceStage != null) 'source_stage': paper.sourceStage,
      if (paper.year != null) 'year': paper.year,
      if (paper.region != null) 'region': paper.region,
      'scoring': <String, Object?>{
        'points': question.score,
        'source': question.scoreSource,
        if (question.scoreConfirmedInSource != null)
          'confirmed_in_source': question.scoreConfirmedInSource,
      },
      if (question.answerSource != null) 'answer_source': question.answerSource,
      if (question.materialIds.isNotEmpty) 'material_ids': question.materialIds,
      if (question.materialText != null) 'material_inlined': true,
      if (question.formulaImageCount > 0) ...<String, Object?>{
        'formula_image_not_latex': true,
        'formula_image_count': question.formulaImageCount,
      },
      if (question.optionFigures.isNotEmpty)
        'option_figure_count': question.optionFigures.length,
      if (question.answerNonUnique) 'answer_non_unique': true,
      if (question.answerNonUnique && question.answerNonUniqueNote != null)
        'answer_non_unique_note': question.answerNonUniqueNote,
      if (question.answerNoOfficialSource) 'answer_no_official_source': true,
      if (question.audioUnavailable) 'audio_available': false,
      if (figures.isNotEmpty) 'figures': figures,
      if (question.unsupportedFormulaCount > 0)
        'unsupported_formula_count': question.unsupportedFormulaCount,
    };
  }

  // -------------------------------------------------------------------------
  // 小工具
  // -------------------------------------------------------------------------

  static bool _isCorrectOption(
    String label,
    String? answer,
    String questionType,
  ) {
    if (answer == null || answer.isEmpty) {
      return false;
    }
    if (questionType != 'single_choice' &&
        questionType != 'multiple_choice') {
      return false;
    }
    final wanted = RegExp(r'[A-H]')
        .allMatches(answer.toUpperCase())
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
    return wanted.contains(label.trim().toUpperCase());
  }

  static int? _figureOrderOf(
    String raw,
    Map<String, int> byPath,
    Map<String, int> byBasename,
  ) {
    final normalized = _normalizeFigureKey(raw);
    final direct = byPath[normalized];
    if (direct != null) {
      return direct;
    }
    final base = p.basename(normalized);
    return byBasename[base];
  }

  static String _normalizeFigureKey(String raw) =>
      raw.trim().replaceAll(r'\', '/').replaceAll(RegExp(r'^\./'), '');

  static void _addIssue(
    List<ExamPaperImportIssue> issues,
    String code,
    String detail, {
    int? questionNumber,
  }) {
    for (final existing in issues) {
      if (existing.code == code &&
          existing.detail == detail &&
          existing.questionNumber == questionNumber) {
        return;
      }
    }
    issues.add(ExamPaperImportIssue(
      code: code,
      detail: detail,
      questionNumber: questionNumber,
    ));
  }
}

/// 一次图片计划（题干图 / 解析图，已解析出绝对路径）。
class _FigurePlan {
  const _FigurePlan({required this.stem, required this.answer});

  final List<_PlannedFigure> stem;
  final List<_PlannedFigure> answer;
}

/// 一张待落盘的图：卷内相对路径 + 已经解析好的绝对路径。
class _PlannedFigure {
  const _PlannedFigure({required this.figure, required this.absolutePath});

  final ExamPaperFigure figure;
  final String absolutePath;
}

// ---------------------------------------------------------------------------
// JSON 容错解析（跨科字段名差异收敛在这里，不在导入逻辑里散落）
// ---------------------------------------------------------------------------

Map<String, Object?> _decodeJsonObject(File file, String label) {
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw StateError('$label 不是合法 JSON：${file.path}（${error.message}）');
  }
  if (decoded is! Map) {
    throw StateError('$label 顶层应为 JSON 对象：${file.path}');
  }
  return decoded.cast<String, Object?>();
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, entry) => MapEntry('$key', entry));
  }
  return null;
}

List<Object?>? _asList(Object? value) => value is List ? value : null;

String? _strOf(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num) {
    return '$value';
  }
  return null;
}

int? _intOf(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

num? _numOf(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value.trim());
  }
  return null;
}

bool? _boolOf(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

int _mapLength(Object? value) {
  if (value is Map) {
    return value.length;
  }
  if (value is List) {
    return value.length;
  }
  return 0;
}

String? _mapStr(Object? value, String key) {
  final map = _asMap(value);
  if (map == null) {
    return null;
  }
  return _strOf(map[key]);
}

/// 依次尝试多个候选字段，返回第一个非空文本。
String? _firstText(List<Object?> candidates) {
  for (final candidate in candidates) {
    final text = _textOf(candidate);
    if (text != null && text.trim().isNotEmpty) {
      return text;
    }
  }
  return null;
}

/// 一个字段可能是字符串、字符串数组或 block 列表；收敛成正文文本。
String? _textOf(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is num) {
    return '$value';
  }
  final list = _asList(value);
  if (list != null) {
    final parts = <String>[];
    for (final entry in list) {
      final text = _textOf(entry);
      if (text != null && text.trim().isNotEmpty) {
        parts.add(text.trim());
      }
    }
    return parts.isEmpty ? null : parts.join('\n');
  }
  final map = _asMap(value);
  if (map != null) {
    final tokens = _asList(map['tokens']);
    if (tokens != null) {
      final parts = <String>[];
      for (final token in tokens) {
        final tokenMap = _asMap(token);
        if (tokenMap == null) {
          continue;
        }
        final kind = _strOf(tokenMap['k']);
        if (kind == 't') {
          final text = _strOf(tokenMap['v']);
          if (text != null) {
            parts.add(text);
          }
        } else if (kind == 'img') {
          final id = _strOf(tokenMap['id']);
          if (id != null) {
            parts.add('⟦图:$id⟧');
          }
        }
      }
      if (parts.isNotEmpty) {
        return parts.join();
      }
    }
    return _firstText(<Object?>[
      map['text_plain'],
      map['text'],
      map['value'],
      map['stem'],
      map['content'],
      map['body_md'],
      map['summary_md'],
    ]);
  }
  return null;
}

/// 题号字段：数学/语文/生物用 `number`，英语用 `no`。
String _rawTypeOf(Map<String, Object?> json) =>
    _strOf(json['question_type']) ??
    _strOf(json['type']) ??
    _strOf(json['questionType']) ??
    '';

String _normalizeQuestionType(String raw) {
  final normalized = raw.trim().toLowerCase();
  const aliases = <String, String>{
    'single_choice': 'single_choice',
    'single-choice': 'single_choice',
    'singlechoice': 'single_choice',
    'choice': 'single_choice',
    '单项选择题': 'single_choice',
    '单选题': 'single_choice',
    'multiple_choice': 'multiple_choice',
    'multiple-choice': 'multiple_choice',
    'multiplechoice': 'multiple_choice',
    'multi_choice': 'multiple_choice',
    'multiple': 'multiple_choice',
    '多项选择题': 'multiple_choice',
    '多选题': 'multiple_choice',
    'fill_in': 'fill_in',
    'fill_in_blank': 'fill_in',
    'fill_blank': 'fill_blank',
    'fill': 'fill_in',
    '填空题': 'fill_in',
    '名篇名句默写（填空）': 'fill_in',
    'solution': 'solution',
    'subjective': 'solution',
    '解答题': 'solution',
    '非选择题': 'solution',
    'non_choice': 'solution',
    'nonchoice': 'solution',
    'open': 'open',
    '简答题': 'open',
    '写作（材料作文）': 'open',
    '名篇名句默写': 'fill_in',
    'seven_choose_five': 'single_choice',
    'applied_writing': 'open',
    'continuation_writing': 'open',
  };
  final exact = aliases[normalized] ?? aliases[raw.trim()];
  if (exact != null) {
    return exact;
  }
  // 复合题型名（「单项选择题（…）」「名篇名句默写（填空）」等）按关键词归并；
  // 仍然认不出时按 `solution` 落库（导入报告不再逐题刷 question_type_unknown，
  // 原始题型写进引用摘要的 `original_question_type`）。
  final value = raw.trim();
  if (value.contains('多选')) {
    return 'multiple_choice';
  }
  if (value.contains('选择')) {
    return 'single_choice';
  }
  if (value.contains('填空') || value.contains('默写')) {
    return 'fill_in';
  }
  if (value.contains('写作') ||
      value.contains('作文') ||
      value.contains('writing')) {
    return 'open';
  }
  if (value.contains('简答') ||
      value.contains('概括') ||
      value.contains('分析') ||
      value.contains('翻译') ||
      value.contains('赏析')) {
    return 'open';
  }
  return 'solution';
}

/// 从卷面/来源字段确认学科；中文名与英文键都认，认不出返回空串（不猜）。
String _normalizeSubject(Object? raw) {
  final value = _strOf(raw)?.trim() ?? '';
  if (value.isEmpty) {
    return '';
  }
  const aliases = <String, String>{
    'math': 'math',
    'mathematics': 'math',
    '数学': 'math',
    'physics': 'physics',
    '物理': 'physics',
    'chinese': 'chinese',
    '语文': 'chinese',
    'chemistry': 'chemistry',
    '化学': 'chemistry',
    'biology': 'biology',
    '生物': 'biology',
    'english': 'english',
    '英语': 'english',
  };
  return aliases[value.toLowerCase()] ?? aliases[value] ?? '';
}

/// 来源分级：先认显式字段；再用来源**自己写的** `stage` / `exam_type` / 标题
/// 证明高考身份；都证明不了就 `unknown`（不猜）。
///
///  * `stage` 含「非高考」→ `school`，basis=`stage_non_gaokao`（生物模块卷）；
///  * `stage` 就是「高考」（化学 manifest）→ `gaokao`，basis=`explicit_stage`；
///  * 标题含「普通高等学校招生全国统一考试 / 高考」→ `gaokao`；
///  * `exam_type` 含「普通高中学业水平选择性考试 / 新高考」（物理/化学广东卷）
///    → `gaokao`，basis=`inferred_from_exam_type`。
({String level, String basis}) _sourceLevelOf(
  Map<String, Object?> paperJson,
  Map<String, Object?>? manifestJson,
  String title,
) {
  const allowed = <String>{
    'gaokao',
    'provincial_diagnostic',
    'elite_school',
    'school',
    'personal',
    'unknown',
  };
  for (final key in const <String>[
    'source_level',
    'sourceLevel',
    'exam_level',
  ]) {
    final value = _strOf(paperJson[key])?.trim() ?? '';
    if (allowed.contains(value)) {
      return (level: value, basis: 'explicit');
    }
  }
  final stage = _strOf(_metaValue(
        paperJson,
        manifestJson,
        const <String>['stage'],
      ))?.trim() ??
      '';
  if (stage.contains('非高考') || stage.contains('模块检测')) {
    return (level: 'school', basis: 'stage_non_gaokao');
  }
  if (stage.contains('高考')) {
    return (level: 'gaokao', basis: 'explicit_stage');
  }
  final normalizedTitle = title.replaceAll(RegExp(r'\s+'), '');
  if (normalizedTitle.contains('普通高等学校招生全国统一考试') ||
      normalizedTitle.contains('高考')) {
    return (level: 'gaokao', basis: 'inferred_from_title');
  }
  final examType = _strOf(_metaValue(
        paperJson,
        manifestJson,
        const <String>['exam_type', 'paper_type', 'examType'],
      ))?.trim() ??
      '';
  if (examType.contains('普通高中学业水平选择性考试') ||
      examType.contains('新高考')) {
    return (level: 'gaokao', basis: 'inferred_from_exam_type');
  }
  return (level: 'unknown', basis: 'unknown');
}

/// 题号列表：顶层的 `questions`；英语没有顶层 `questions`，从 `sections` 摊平。
List<ExamPaperQuestion> _questionsOf(Map<String, Object?> paperJson) {
  final raw = _asList(paperJson['questions']);
  if (raw != null) {
    final materials = _materialIndex(paperJson);
    final questions = <ExamPaperQuestion>[];
    for (var i = 0; i < raw.length; i++) {
      final map = _asMap(raw[i]);
      if (map == null) {
        continue;
      }
      final question = ExamPaperQuestion.fromJson(map, materials: materials);
      if (question.number <= 0) {
        // 缺题号的条目仍保留（导入阶段会 blocked 并报错），但需要占位号避免
        // 与真实题号相撞：用 -(i+1) 表示"第 i 条缺题号"。
        questions.add(_withNumber(question, -(i + 1)));
        continue;
      }
      questions.add(question);
    }
    return questions;
  }
  final sections = _asMap(paperJson['sections']);
  if (sections != null) {
    return _englishQuestions(sections);
  }
  return const <ExamPaperQuestion>[];
}

/// 语文材料索引：`sections[].materials[]`（id → 原文）。
Map<String, String> _materialIndex(Map<String, Object?> paperJson) {
  final index = <String, String>{};
  for (final raw in _asList(paperJson['sections']) ?? const <Object?>[]) {
    final section = _asMap(raw);
    if (section == null) {
      continue;
    }
    for (final rawMaterial
        in _asList(section['materials']) ?? const <Object?>[]) {
      final material = _asMap(rawMaterial);
      if (material == null) {
        continue;
      }
      final id = _strOf(material['id']);
      if (id == null) {
        continue;
      }
      final text =
          _textOf(material['text']) ?? _textOf(material['lines']) ?? '';
      if (text.trim().isEmpty) {
        continue;
      }
      index[id] = text.trim();
    }
  }
  return index;
}

/// 英语：`sections` 是 dict，按 6 个板块摊平成 67 道题。
///
/// 材料（听力原文 / 阅读语篇 / 七选五短文 / 完形与语法语篇）并入题干；听力
/// 音频不可用、作文答案非唯一都只记录，不假装。
List<ExamPaperQuestion> _englishQuestions(Map<String, Object?> sections) {
  final questions = <ExamPaperQuestion>[];
  void add(Map<String, Object?> raw) {
    questions.add(ExamPaperQuestion.fromJson(raw));
  }

  // ---- 听力：每题带 script，第二节按 group 共享 ----
  final listening = _asMap(sections['listening']);
  final scriptByGroup = <int, String>{};
  for (final rawGroup in _asList(listening?['groups']) ?? const <Object?>[]) {
    final group = _asMap(rawGroup);
    if (group == null) {
      continue;
    }
    final id = _intOf(group['group_id']);
    final script = _textOf(group['script_lines']) ?? _strOf(group['script']);
    if (id != null && script != null && script.trim().isNotEmpty) {
      scriptByGroup[id] = script.trim();
    }
  }
  for (final rawQuestion
      in _asList(listening?['questions']) ?? const <Object?>[]) {
    final question = _asMap(rawQuestion);
    if (question == null) {
      continue;
    }
    final script = _strOf(question['script']) ??
        scriptByGroup[_intOf(question['group_id'])];
    add(<String, Object?>{
      'no': question['no'],
      'type': question['type'],
      'score': question['score'],
      'score_source': 'section_score_note',
      'stem': question['stem'],
      'options': question['options'],
      'answer': question['answer'],
      'explanation': question['explanation'],
      'audio_available': question['audio_available'] ?? false,
      if (script != null && script.trim().isNotEmpty)
        'material': '【听力原文】（音频文件不可用，以下为原文）\n${script.trim()}',
    });
  }

  // ---- 阅读：4 篇语篇，各带 3/4 道题 ----
  final reading = _asMap(sections['reading']);
  for (final rawPassage
      in _asList(reading?['passages']) ?? const <Object?>[]) {
    final passage = _asMap(rawPassage);
    if (passage == null) {
      continue;
    }
    final letter = _strOf(passage['letter']) ?? '';
    final material = _strOf(passage['material']) ?? '';
    for (final rawQuestion
        in _asList(passage['questions']) ?? const <Object?>[]) {
      final question = _asMap(rawQuestion);
      if (question == null) {
        continue;
      }
      add(<String, Object?>{
        'no': question['no'],
        'type': question['type'],
        'score': question['score'],
        'score_source': 'section_score_note',
        'stem': question['stem'],
        'options': question['options'],
        'answer': question['answer'],
        'explanation': question['explanation'],
        if (material.trim().isNotEmpty)
          'material': '【阅读材料${letter.isEmpty ? '' : ' $letter'}】\n${material.trim()}',
      });
    }
  }

  // ---- 七选五：短文 + 7 个共享选项（A–G），每个空都从 A–G 里选 ----
  final seven = _asMap(sections['seven_choose_five']);
  if (seven != null) {
    final material = _strOf(seven['material']) ?? '';
    final sharedOptions = _asList(seven['options']) ?? const <Object?>[];
    for (final rawQuestion
        in _asList(seven['questions']) ?? const <Object?>[]) {
      final question = _asMap(rawQuestion);
      if (question == null) {
        continue;
      }
      final blank = _asMap(question['blank_context']);
      final stem = StringBuffer(_strOf(question['stem']) ?? '');
      if (blank != null) {
        stem.write('\n【空格上下文】');
        final prev = _strOf(blank['prev_sentence']);
        final next = _strOf(blank['next_sentence']);
        if (prev != null && prev.trim().isNotEmpty) {
          stem.write('\n前句：${prev.trim()}');
        }
        if (next != null && next.trim().isNotEmpty) {
          stem.write('\n后句：${next.trim()}');
        }
      }
      add(<String, Object?>{
        'no': question['no'],
        'type': 'single_choice',
        'score': question['score'],
        'score_source': 'section_score_note',
        'stem': stem.toString(),
        'options': sharedOptions,
        'answer': question['answer'],
        'explanation': question['explanation'],
        if (material.trim().isNotEmpty) 'material': '【短文】\n${material.trim()}',
      });
    }
  }

  // ---- 完形 / 语法填空：整篇语篇 + 每题句子/选项 ----
  //
  // 同一句里有多个空时（46/47/48 共用一句话），题干必须带空号前缀，否则
  // 题干指纹会把不同空当成同一道题复用（丢选项）。空号前缀也方便学生定位。
  _addEnglishPassageQuestions(
    questions,
    _asMap(sections['cloze']),
    header: '【短文】',
    blankLabel: true,
  );
  _addEnglishPassageQuestions(
    questions,
    _asMap(sections['grammar']),
    header: '【语篇】',
    blankLabel: true,
  );

  // ---- 写作：答案来自解析卷，是参考样例（非唯一），不假装唯一答案 ----
  for (final rawQuestion in _asList(sections['writing']) ?? const <Object?>[]) {
    final writing = _asMap(rawQuestion);
    if (writing == null) {
      continue;
    }
    final answerType = _strOf(writing['answer_type']) ?? '';
    add(<String, Object?>{
      'no': writing['no'],
      'type': writing['type'],
      'score': writing['score'],
      'score_source': 'section_score_note',
      'stem': writing['prompt'],
      'answer': writing['answer'],
      'explanation': writing['explanation'],
      'answer_non_unique': true,
      'answer_non_unique_note': answerType == 'reference_sample'
          ? '参考样例（reference_sample），不是唯一标准答案'
          : '作文答案非唯一',
    });
  }
  return questions;
}

void _addEnglishPassageQuestions(
  List<ExamPaperQuestion> out,
  Map<String, Object?>? section, {
  required String header,
  bool blankLabel = false,
}) {
  if (section == null) {
    return;
  }
  final material = _strOf(section['material']) ?? '';
  for (final rawQuestion
      in _asList(section['questions']) ?? const <Object?>[]) {
    final question = _asMap(rawQuestion);
    if (question == null) {
      continue;
    }
    final number = _intOf(question['no']);
    final stem = _strOf(question['stem']) ?? '';
    out.add(ExamPaperQuestion.fromJson(<String, Object?>{
      'no': question['no'],
      'type': question['type'],
      'score': question['score'],
      'score_source': 'section_score_note',
      'stem': blankLabel && number != null ? '（第$number空）$stem' : stem,
      'options': question['options'],
      'answer': question['answer'],
      'explanation': question['explanation'],
      if (material.trim().isNotEmpty) 'material': '$header\n${material.trim()}',
    }));
  }
}

ExamPaperQuestion _withNumber(ExamPaperQuestion question, int number) {
  return ExamPaperQuestion(
    number: number,
    questionType: question.questionType,
    stem: question.stem,
    options: question.options,
    answer: question.answer,
    analysis: question.analysis,
    stemFigures: question.stemFigures,
    answerFigures: question.answerFigures,
    optionFigures: question.optionFigures,
    materialText: question.materialText,
    materialIds: question.materialIds,
    materialMissingSource: question.materialMissingSource,
    answerNonUnique: question.answerNonUnique,
    answerNonUniqueNote: question.answerNonUniqueNote,
    answerNoOfficialSource: question.answerNoOfficialSource,
    audioUnavailable: question.audioUnavailable,
    sourceQuestionType: question.sourceQuestionType,
    answerSource: question.answerSource,
    section: question.section,
    score: question.score,
    scoreSource: question.scoreSource,
    scoreConfirmedInSource: question.scoreConfirmedInSource,
    scoreInferred: question.scoreInferred,
    unsupportedFormulaCount: question.unsupportedFormulaCount,
    formulaNotConverted: question.formulaNotConverted,
    hasAiLabels: question.hasAiLabels,
    hasKnowledgePoints: question.hasKnowledgePoints,
  );
}

/// 选项：list（数学/语文/物理/化学/英语）与 map（生物）两种都认。
///
/// 物理选项的 `blocks`、化学选项的 `content` tokens 里可能有公式图/插图；
/// 这些图收进 [optionFigures]（导入时落题干「【选项配图】」区），选项正文
/// 留 `⟦OPT:label⟧` 标记，由导入阶段换成「（选项配图见［图N］）」。
List<ExamPaperOption> _optionsOf(
  Object? raw, {
  List<ExamPaperOptionFigure>? optionFigures,
}) {
  final figures = optionFigures ?? <ExamPaperOptionFigure>[];
  final list = _asList(raw);
  if (list != null) {
    final options = <ExamPaperOption>[];
    for (final entry in list) {
      final map = _asMap(entry);
      if (map == null) {
        continue;
      }
      final label = _strOf(map['label']) ??
          _strOf(map['letter']) ??
          _strOf(map['key']) ??
          '';
      if (label.isEmpty) {
        continue;
      }
      final local = <ExamPaperFigure>[];
      final blocks = _asList(map['blocks']);
      final tokens = _asList(map['content']);
      String text;
      if (blocks != null && blocks.isNotEmpty && _isTypedBlocks(blocks)) {
        text = _typedBlocksText(
          blocks,
          images: local,
          role: QuestionImageRole.stem,
          emitPlaceholders: false,
        );
      } else if (tokens != null &&
          tokens.isNotEmpty &&
          tokens.any((token) => _asMap(token) != null)) {
        text = _chemTokensText(
              tokens,
              images: local,
              role: QuestionImageRole.stem,
              emitPlaceholders: false,
            ) ??
            '';
      } else {
        text = _textOf(map['text']) ??
            _textOf(map['text_plain']) ??
            _textOf(map['content']) ??
            _textOf(map['value']) ??
            '';
      }
      for (final figure in local) {
        figures.add(ExamPaperOptionFigure(label: label, figure: figure));
      }
      final hasImage = local.isNotEmpty;
      options.add(ExamPaperOption(
        label: label,
        content: hasImage
            ? '${text.trim()}（选项配图见⟦OPT:$label⟧）'
            : text.trim(),
        hasImage: hasImage,
      ));
    }
    return options;
  }
  final map = _asMap(raw);
  if (map != null) {
    final options = <ExamPaperOption>[];
    for (final entry in map.entries) {
      final label = entry.key.trim();
      if (label.isEmpty) {
        continue;
      }
      final text = _textOf(entry.value) ?? '';
      options.add(ExamPaperOption(label: label, content: text));
    }
    return options;
  }
  return const <ExamPaperOption>[];
}

/// 答案：优先按 block 重建（物理 `answer_blocks`、化学 `answer.blocks`，
/// 公式图/图会变成 role=answer 附件 + 「［图N］」占位）；否则
/// `summary_md`（含分问）→ `direct` → `letter`/`text`；顶层还认
/// `answer_text` / `answer` 字符串。
String? _answerOf(
  Map<String, Object?> json,
  int number,
  List<ExamPaperFigure> answerImages,
) {
  final raw = json['answer'];
  if (raw is String) {
    return _stripLeadingNumber(raw, number);
  }
  final map = _asMap(raw);
  if (map != null) {
    // 先按 block 收答案图（即使答案是字母，图也要进答案图库），再定答案文本。
    final blocks = _asList(map['blocks']);
    String? blockText;
    if (blocks != null && blocks.isNotEmpty) {
      final text = _blocksText(
        blocks,
        images: answerImages,
        role: QuestionImageRole.answer,
      );
      if (text.trim().isNotEmpty) {
        blockText = _stripAnswerLabel(_stripLeadingNumber(text, number));
      }
    }
    // 客观题答案是字母（化学 `answer.letter`）：字母比 block 里的「［图N］」更准。
    final letter = _strOf(map['letter']);
    if (letter != null && RegExp(r'^[A-Ha-h]{1,4}$').hasMatch(letter.trim())) {
      return letter.trim().toUpperCase();
    }
    if (blockText != null) {
      return blockText;
    }
    final summary = _strOf(map['summary_md']) ?? _strOf(map['summary']);
    if (summary != null) {
      return _stripLeadingNumber(summary, number);
    }
    final direct = _strOf(map['direct']);
    if (direct != null) {
      return _stripLeadingNumber(direct, number);
    }
    final text = _textOf(map['text']);
    if (text != null) {
      return _stripLeadingNumber(text, number);
    }
  }
  final answerBlocks = _asList(json['answer_blocks']);
  if (answerBlocks != null && answerBlocks.isNotEmpty) {
    final text = _blocksText(
      answerBlocks,
      images: answerImages,
      role: QuestionImageRole.answer,
    );
    if (text.trim().isNotEmpty) {
      return _stripAnswerLabel(_stripLeadingNumber(text, number));
    }
  }
  final answerText = _textOf(json['answer_text']);
  if (answerText != null) {
    return _stripLeadingNumber(answerText, number);
  }
  return _stripLeadingNumber(_textOf(json['answer_blocks']) ?? '', number);
}

/// 去掉答案/解析正文开头的标签（`【答案】` / `【参考答案】` / `【解析】`）：
/// 产品详情页自己带「答案」「解析」标签，重复写一遍只是噪声。
String _stripAnswerLabel(String raw) => raw
    .trim()
    .replaceFirst(RegExp(r'^\s*【(?:参考)?答案】\s*'), '')
    .replaceFirst(RegExp(r'^\s*答案[:：]\s*'), '')
    .trim();

String _stripAnalysisLabel(String raw) =>
    raw.trim().replaceFirst(RegExp(r'^\s*【解析】\s*'), '').trim();

/// 去掉答案开头的题号（`1．C` → `C`，`15．(1)…` → `(1)…`）。
String _stripLeadingNumber(String raw, int number) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  if (number < 1) {
    return trimmed;
  }
  final prefix = RegExp('^\\s*$number\\s*[．.、]\\s*');
  return trimmed.replaceFirst(prefix, '');
}

/// 解析：数学 `analysis.groups[]`、语文/英语/生物 `analysis`/`explanation`
/// 字符串、物理 `analysis_blocks`（formula/figure + text）、化学
/// `explanation` blocks（tokens）；图统一落 role=answer 并按顺序编号。
ExamPaperAnalysis? _analysisOf(
  Map<String, Object?> json,
  List<ExamPaperFigure> answerImages,
) {
  final analysis = json['analysis'];
  final map = _asMap(analysis);
  if (map != null) {
    // 数学解析图先收进答案图库（正文里的引用稍后由导入阶段去掉）。
    for (final raw in _asList(map['images']) ?? const <Object?>[]) {
      final figure = _figureOf(raw, role: QuestionImageRole.answer);
      if (figure != null) {
        answerImages.add(figure);
      }
    }
    final groups = _asList(map['groups']);
    if (groups != null) {
      final parts = <String>[];
      for (final group in groups) {
        final text = _textOf(_asMap(group)?['text']);
        if (text != null && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
      if (parts.isNotEmpty) {
        return ExamPaperAnalysis(
          text: parts.join('\n\n'),
          source: _strOf(map['source']),
        );
      }
    }
    final direct = _textOf(map['text']);
    if (direct != null) {
      return ExamPaperAnalysis(
        text: direct,
        source: _strOf(map['source']),
      );
    }
  }
  final analysisBlocks = _asList(json['analysis_blocks']);
  if (analysisBlocks != null && analysisBlocks.isNotEmpty) {
    final local = <ExamPaperFigure>[];
    final text = _blocksText(
      analysisBlocks,
      images: local,
      role: QuestionImageRole.answer,
    );
    answerImages.addAll(local);
    if (text.trim().isNotEmpty) {
      return ExamPaperAnalysis(text: _stripAnalysisLabel(text));
    }
  }
  final explanation = json['explanation'];
  if (explanation is List && explanation.isNotEmpty) {
    final local = <ExamPaperFigure>[];
    final text = _chemBlocksText(
      explanation,
      images: local,
      role: QuestionImageRole.answer,
    );
    answerImages.addAll(local);
    if (text.trim().isNotEmpty) {
      return ExamPaperAnalysis(text: _stripAnalysisLabel(text));
    }
  }
  final analysisString = _textOf(analysis);
  if (analysisString != null && analysisString.trim().isNotEmpty) {
    return ExamPaperAnalysis(text: analysisString.trim());
  }
  for (final key in const <String>['analysis_text', 'explanation']) {
    final text = _textOf(json[key]);
    if (text != null && text.trim().isNotEmpty) {
      return ExamPaperAnalysis(text: text.trim());
    }
  }
  return null;
}

/// 题干图：数学/语文用 `images[]`（`saved_as`/`file`）；生物用 `figures[]`
/// 字符串路径；物理 block 形态的图由 `_blockStemOf` 处理（这里的 `figures[]`
/// 是汇总清单，会被 block 形态覆盖、不重复收）。
List<ExamPaperFigure> _figuresOf(Map<String, Object?> json) {
  return <ExamPaperFigure>[
    for (final raw in _asList(json['images']) ?? const <Object?>[])
      if (_figureOf(raw, role: QuestionImageRole.stem) case final figure?)
        figure,
    for (final raw in _asList(json['figures']) ?? const <Object?>[])
      if (_figureOf(raw, role: QuestionImageRole.stem) case final figure?)
        figure,
  ];
}

ExamPaperFigure? _figureOf(
  Object? raw, {
  required String role,
  bool isFormula = false,
}) {
  // 生物 `figures` 是字符串路径（`assets/figures/q02-obj29.jpg`）。
  if (raw is String) {
    final relative = raw.trim();
    if (relative.isEmpty) {
      return null;
    }
    return ExamPaperFigure(
      relativePath: relative.replaceAll(r'\', '/'),
      role: role,
      isFormula: isFormula,
    );
  }
  final map = _asMap(raw);
  if (map == null) {
    return null;
  }
  final relative = _strOf(map['saved_as']) ??
      _strOf(map['file']) ??
      _strOf(map['asset']) ??
      _strOf(map['path']) ??
      _strOf(map['media']) ??
      '';
  if (relative.isEmpty) {
    return null;
  }
  return ExamPaperFigure(
    relativePath: relative.replaceAll(r'\', '/'),
    role: role,
    sha256: _strOf(map['sha256']),
    sourceMedia: _strOf(map['source_media']) ?? _strOf(map['media']),
    bytes: _intOf(map['bytes']),
    isFormula: isFormula,
  );
}

// ---------------------------------------------------------------------------
// block 形态（物理 stem_blocks / 化学 stem tokens）→ 带「［图N］」占位的正文
// ---------------------------------------------------------------------------

/// 物理 block 形态：`{type: text|formula|figure, ...}`。
bool _isTypedBlocks(List<Object?> blocks) {
  for (final raw in blocks) {
    final block = _asMap(raw);
    if (block == null) {
      continue;
    }
    final type = _strOf(block['type']);
    if (type == 'text' || type == 'formula' || type == 'figure') {
      return true;
    }
  }
  return false;
}

/// 化学 block 形态：`{kind: p|table, tokens: [...] | rows: [...]}`。
bool _isChemBlocks(List<Object?> blocks) {
  for (final raw in blocks) {
    final block = _asMap(raw);
    if (block == null) {
      continue;
    }
    final kind = _strOf(block['kind']);
    if (kind == 'p' || kind == 'table' || block['tokens'] is List) {
      return true;
    }
  }
  return false;
}

/// 题干 block → 正文（含「［图N］」占位）；不是 block 形态返回 null。
String? _blockStemOf(
  Map<String, Object?> json,
  List<ExamPaperFigure> images,
) {
  final typed = _asList(json['stem_blocks']);
  if (typed != null && typed.isNotEmpty && _isTypedBlocks(typed)) {
    final text = _typedBlocksText(
      typed,
      images: images,
      role: QuestionImageRole.stem,
    );
    return text.trim().isEmpty ? null : text;
  }
  final chem = _asList(json['stem']);
  if (chem != null && chem.isNotEmpty && _isChemBlocks(chem)) {
    final text = _chemBlocksText(
      chem,
      images: images,
      role: QuestionImageRole.stem,
    );
    return text.trim().isEmpty ? null : text;
  }
  return null;
}

/// 按 block 形态把任意 block 列表转成正文；公式图/插图都收进 [images]。
String _blocksText(
  List<Object?> blocks, {
  required List<ExamPaperFigure> images,
  required String role,
}) {
  if (_isTypedBlocks(blocks)) {
    return _typedBlocksText(blocks, images: images, role: role);
  }
  if (_isChemBlocks(blocks)) {
    return _chemBlocksText(blocks, images: images, role: role);
  }
  return '';
}

/// 物理 block 序列 → 正文；同段落的 block 直接拼接，换段插换行。
///
/// [emitPlaceholders] 为 false 时只收图、不写「［图N］」（选项正文用：选项
/// 不能内嵌图片，正文里留一个指不到图的占位只会误导；改用「选项配图见…」）。
String _typedBlocksText(
  List<Object?> blocks, {
  required List<ExamPaperFigure> images,
  required String role,
  bool emitPlaceholders = true,
}) {
  final buffer = StringBuffer();
  int? previousParagraph;
  for (final raw in blocks) {
    final block = _asMap(raw);
    if (block == null) {
      continue;
    }
    final type = _strOf(block['type']) ?? '';
    final paragraph = _intOf(block['paragraph']);
    if (previousParagraph != null &&
        paragraph != null &&
        paragraph != previousParagraph) {
      buffer.write('\n');
    }
    if (type == 'text') {
      final value = block['text'];
      if (value is String) {
        buffer.write(value);
      }
    } else if (type == 'formula' || type == 'figure') {
      final figure = _figureOf(
        block,
        role: role,
        isFormula: type == 'formula',
      );
      if (figure != null) {
        final order = _addFigure(images, figure);
        if (emitPlaceholders) {
          buffer.write('［图${order + 1}］');
        }
      }
    }
    previousParagraph = paragraph ?? previousParagraph;
  }
  return _cleanText(buffer.toString());
}

/// 化学 block 序列（`p` 段落 / `table` 表格）→ 正文。
///
/// 表格没有产品级表格落点，按「第N行：cell | cell」展开（单元格里的公式图
/// 仍用「［图N］」占位并渲染），不丢单元格内容。
String _chemBlocksText(
  List<Object?> blocks, {
  required List<ExamPaperFigure> images,
  required String role,
}) {
  final parts = <String>[];
  for (final raw in blocks) {
    final block = _asMap(raw);
    if (block == null) {
      continue;
    }
    final kind = _strOf(block['kind']) ?? '';
    if (kind == 'table') {
      parts.add(_chemTableText(block, images: images, role: role));
      continue;
    }
    final text = _chemTokensText(
      _asList(block['tokens']) ?? const <Object?>[],
      images: images,
      role: role,
    );
    if (text != null && text.trim().isNotEmpty) {
      parts.add(text.trim());
    }
  }
  return _cleanText(parts.join('\n'));
}

/// 化学 token 序列（`t` 文本 / `img` 插图 / `eq` 公式图）→ 正文。
String? _chemTokensText(
  List<Object?> tokens, {
  required List<ExamPaperFigure> images,
  required String role,
  bool emitPlaceholders = true,
}) {
  final buffer = StringBuffer();
  for (final raw in tokens) {
    final token = _asMap(raw);
    if (token == null) {
      continue;
    }
    final kind = _strOf(token['k']) ?? '';
    if (kind == 't') {
      final value = token['v'];
      if (value is String) {
        buffer.write(value);
      }
      continue;
    }
    if (kind != 'img' && kind != 'eq') {
      continue;
    }
    final id = _strOf(token['id']);
    if (id == null || id.trim().isEmpty) {
      continue;
    }
    final figure = ExamPaperFigure(
      relativePath: 'assets/${id.trim()}',
      role: role,
      isFormula: kind == 'eq',
      sourceMedia: id.trim(),
    );
    final order = _addFigure(images, figure);
    if (emitPlaceholders) {
      buffer.write('［图${order + 1}］');
    }
  }
  final text = _cleanText(buffer.toString());
  return text.isEmpty ? null : text;
}

String _chemTableText(
  Map<String, Object?> block, {
  required List<ExamPaperFigure> images,
  required String role,
}) {
  final rows = _asList(block['rows']) ?? const <Object?>[];
  final lines = <String>['【表格】'];
  for (var row = 0; row < rows.length; row++) {
    final cells = _asList(rows[row]) ?? const <Object?>[];
    final rendered = <String>[];
    for (final rawCell in cells) {
      final cellTokens = _asList(rawCell) ?? const <Object?>[];
      rendered.add(
        _chemTokensText(cellTokens, images: images, role: role) ?? '',
      );
    }
    lines.add('第${row + 1}行：${rendered.join(' | ')}');
  }
  return lines.join('\n');
}

/// 同一张图（同一卷内相对路径）在一道题里只占一个编号，重复引用复用编号。
int _addFigure(List<ExamPaperFigure> images, ExamPaperFigure figure) {
  for (var i = 0; i < images.length; i++) {
    if (images[i].relativePath == figure.relativePath) {
      return i;
    }
  }
  images.add(figure);
  return images.length - 1;
}

String _cleanText(String raw) => raw
    .replaceAll(RegExp(r'[ \t]+\n'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

bool _hasFormulaBlocks(Map<String, Object?> json) {  for (final key in const <String>['stem_blocks', 'blocks']) {
    final blocks = _asList(json[key]);
    if (blocks == null) {
      continue;
    }
    for (final block in blocks) {
      if (_strOf(_asMap(block)?['type']) == 'formula' ||
          _strOf(_asMap(block)?['kind']) == 'formula') {
        return true;
      }
    }
  }
  return false;
}

/// 卷级 meta：先认顶层，再认 `exam_meta` / `paper_meta` / `meta`，最后 manifest。
Object? _metaValue(
  Map<String, Object?> paperJson,
  Map<String, Object?>? manifestJson,
  List<String> keys,
) {
  for (final key in keys) {
    final direct = paperJson[key];
    if (direct != null) {
      return direct;
    }
  }
  for (final scope in const <String>['exam_meta', 'paper_meta', 'meta']) {
    final map = _asMap(paperJson[scope]);
    if (map == null) {
      continue;
    }
    for (final key in keys) {
      final value = map[key];
      if (value != null) {
        return value;
      }
    }
  }
  if (manifestJson != null) {
    for (final key in keys) {
      final value = manifestJson[key];
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}