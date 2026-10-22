/// 组卷卷面 → .docx 字节：应用层装配（读库 + 读配图字节 + 调纯逻辑层）。
///
/// 分工：
/// - `domain/services/export/paper_docx.dart` 只认数据，不碰文件系统；
/// - 这里把 `question_corpus_reader` 读出的题干/选项/答案/解析，加上
///   `QuestionMediaStore` 读出的配图字节与像素尺寸，装成 `PaperDocxQuestion`；
/// - 保存到磁盘（FilePicker）与 l10n 文案归界面层，不在这里。
///
/// 图片纪律：读不出像素尺寸、或格式 Word 打不开（HEIC/WEBP）的图，不在这一层
/// 悄悄丢——记进 [imageLoadNotes]，同时 `PaperDocxBuildResult.imageSkippedNotes`
/// 还会由装配层再报一次（那里知道是第几题）。
library;

import 'dart:typed_data';

import '../../../data/database/database.dart';
import '../../../data/media/image_size.dart';
import '../../../domain/services/export/docx_writer.dart';
import '../../../domain/services/export/paper_docx.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/paper/paper_quality_report.dart';
import '../../../domain/services/questions/question_snapshot_summary.dart';
import '../../../domain/services/questions/question_stem_image_plan.dart';
import '../data/question_media_store.dart';
import 'question_corpus_reader.dart';

/// 一次导出：字节 + 统计数据 + 建议文件名 + 读图时的告警。
class PaperDocxExportResult {
  const PaperDocxExportResult({
    required this.report,
    required this.suggestedFileName,
    required this.imageLoadNotes,
  });

  final PaperDocxBuildResult report;

  /// 建议文件名（ASCII，`furnace-paper-20261019-0500.docx`）。
  final String suggestedFileName;

  /// 图片读不出来/不认识的告警（装配层还会报「第 N 题」，这里只报文件名与原因）。
  final List<String> imageLoadNotes;

  Uint8List get bytes => report.bytes;

  int get imageCount => report.imageCount;

  /// 答案/解析截图张数（附录里渲染的那些，独立于题干配图）。
  int get answerImageCount => report.answerImageCount;

  bool get hasWarnings => report.hasWarnings || imageLoadNotes.isNotEmpty;
}

/// 组装一份卷子的 .docx。
///
/// [mathCompiler] 由推理层注入（LaTeX → OMML）；不传则 `$...$` 保留原文。
/// [qualityReport] 由界面层从 `paperQualityReportProvider` 取（组卷质量体检），透传给
/// [buildPaperDocx] 追加「组卷质量」节；不传则该节整段不出现，docx 与旧版逐字节一致。
/// 其余可选参数直接透传给 [buildPaperDocx]（答案/解析/理由/缺口开关、标题、页脚）。
Future<PaperDocxExportResult> buildPaperDocxExport({
  required AppDatabase db,
  required QuestionMediaStore mediaStore,
  required PaperPlan plan,
  DocxMathCompiler? mathCompiler,
  PaperQualityReport? qualityReport,
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
}) async {
  final now = generatedAt ?? DateTime.now();
  final questionIds = <String>{
    for (final item in plan.items)
      if (item.questionId.trim().isNotEmpty) item.questionId.trim(),
  };
  final rows = await readQuestionDocxRows(db, ids: questionIds);
  final knowledgePointNames = await readKnowledgePointNames(db);
  final loaded = await loadQuestionDocxImages(mediaStore, questionIds);
  final loadedAnswer =
      await loadQuestionDocxAnswerImages(mediaStore, questionIds);

  final questions = <String, PaperDocxQuestion>{
    for (final entry in rows.entries)
      entry.key: _paperDocxQuestionFor(
        entry.value,
        images:
            loaded.imagesByQuestionId[entry.key] ?? const <PaperDocxImage>[],
        answerImages: loadedAnswer.imagesByQuestionId[entry.key] ??
            const <PaperDocxImage>[],
      ),
  };

  final report = buildPaperDocx(
    plan: plan,
    questions: questions,
    knowledgePointNames: knowledgePointNames,
    labels: labels,
    qualityReport: qualityReport,
    mathCompiler: mathCompiler,
    page: page,
    footerText: footerText ?? defaultPaperDocxFooter(now),
    generatedAt: now,
    includeAnswers: includeAnswers,
    includeSolutions: includeSolutions,
    includeReasons: includeReasons,
    includeGaps: includeGaps,
    title: title,
    subtitle: subtitle,
  );
  return PaperDocxExportResult(
    report: report,
    suggestedFileName: paperDocxFileName(now),
    imageLoadNotes: List<String>.unmodifiable(<String>[
      ...loaded.notes,
      ...loadedAnswer.notes,
    ]),
  );
}

/// 把一行题目素材装成装配层的题目对象：整卡快照题在这里降级。
///
/// 判定用真实像素尺寸（B1）：1 张 1640x808 的整题截图 + 多处「［图N］」占位
/// 就是快照模式，此时
/// * 题干换成占位中性化后的正文（占位变「…」），不再把 44 个 ［图N］ 打进 Word；
/// * 配图仍按原顺序放到正文后面，装配层再补「原题整图」小标题；
/// * 只有一张小图、占位一处的题不属于快照，行为与旧版一致。
PaperDocxQuestion _paperDocxQuestionFor(
  QuestionDocxRow row, {
  required List<PaperDocxImage> images,
  required List<PaperDocxImage> answerImages,
}) {
  final summary = summarizeQuestionStemSnapshot(
    stem: row.stem,
    stemImageCount: images.length,
    imageSizes: <QuestionStemImageSize>[
      for (final image in images)
        QuestionStemImageSize(image.pixelWidth, image.pixelHeight),
    ],
  );
  return row.toPaperDocxQuestion(
    images: images,
    answerImages: answerImages,
    stemOverride: summary.isSnapshot ? summary.neutralizedStem : null,
    stemIsSnapshot: summary.isSnapshot,
  );
}

/// [loadQuestionDocxImages] 的结果。
class QuestionDocxImages {
  const QuestionDocxImages({
    required this.imagesByQuestionId,
    required this.notes,
  });

  final Map<String, List<PaperDocxImage>> imagesByQuestionId;
  final List<String> notes;
}

/// 读一组题目的**题干配图**字节与像素尺寸（按题目分组、按 `sortOrder` 顺序）。
///
/// 只取 `role = stem`（含 v27 之前的 NULL 旧行）：答案/解析截图不进题目卷的题干
/// 配图位置，它们由附录单独渲染。
///
/// 三道防线，缺一不嵌：
/// 1. `QuestionMediaStore.readBytes` 返回 null（文件被清掉）→ 记 note 跳过；
/// 2. `readImageInfo` 认不出容器格式（HEIC 等）→ 记 note 跳过；
/// 3. 像素尺寸非正 → 记 note 跳过。
/// 格式能不能进 docx 由装配层再判一次（WEBP 能读尺寸但 Word 不认）。
Future<QuestionDocxImages> loadQuestionDocxImages(
  QuestionMediaStore mediaStore,
  Iterable<String> questionIds,
) {
  return _loadQuestionDocxImages(
    mediaStore,
    questionIds,
    role: QuestionImageRole.stem,
    notePrefix: '',
  );
}

/// 读一组题目的**答案/解析截图**（v27 的 `role = answer`）字节与像素尺寸。
///
/// 与题干配图同样的三道防线，只是告警文字带「答案截图：」前缀，便于用户分清
/// 是哪一类图没嵌进去。这些图由 `paper_docx` 渲染在附录该题的答案/解析之后。
Future<QuestionDocxImages> loadQuestionDocxAnswerImages(
  QuestionMediaStore mediaStore,
  Iterable<String> questionIds,
) {
  return _loadQuestionDocxImages(
    mediaStore,
    questionIds,
    role: QuestionImageRole.answer,
    notePrefix: '答案截图：',
  );
}

Future<QuestionDocxImages> _loadQuestionDocxImages(
  QuestionMediaStore mediaStore,
  Iterable<String> questionIds, {
  required String role,
  required String notePrefix,
}) async {
  final imagesByQuestionId = <String, List<PaperDocxImage>>{};
  final notes = <String>[];
  for (final rawId in questionIds) {
    final questionId = rawId.trim();
    if (questionId.isEmpty) continue;
    final stored = await mediaStore.list(questionId, role: role);
    if (stored.isEmpty) continue;
    final images = <PaperDocxImage>[];
    for (final image in stored) {
      final bytes = await mediaStore.readBytes(image.relPath);
      if (bytes == null || bytes.isEmpty) {
        notes.add('$notePrefix${image.fileName}：文件缺失，未嵌入');
        continue;
      }
      final info = readImageInfo(bytes);
      if (info == null) {
        notes.add('$notePrefix${image.fileName}：认不出图片格式，未嵌入');
        continue;
      }
      if (!info.size.isValid) {
        notes.add('$notePrefix${image.fileName}：像素尺寸无效，未嵌入');
        continue;
      }
      images.add(
        PaperDocxImage(
          bytes: bytes,
          extension: info.format.extension,
          pixelWidth: info.size.width,
          pixelHeight: info.size.height,
          fileName: image.fileName,
        ),
      );
    }
    if (images.isNotEmpty) {
      imagesByQuestionId[questionId] =
          List<PaperDocxImage>.unmodifiable(images);
    }
  }
  return QuestionDocxImages(
    imagesByQuestionId: Map<String, List<PaperDocxImage>>.unmodifiable(
      imagesByQuestionId,
    ),
    notes: List<String>.unmodifiable(notes),
  );
}

/// 建议文件名：`furnace-paper-20261019-0500.docx`（ASCII、可排序）。
String paperDocxFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp = '${time.year}${two(time.month)}${two(time.day)}'
      '-${two(time.hour)}${two(time.minute)}';
  return 'furnace-paper-$stamp.docx';
}

/// 页脚左侧的时期代号（与 paper-composer 的 footer.periodCode 同口径）。
String defaultPaperDocxFooter(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Furnace · ${time.year}-${two(time.month)}-${two(time.day)}';
}
