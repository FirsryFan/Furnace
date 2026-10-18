/// 组卷卷面 → Word（.docx）的**纯逻辑装配层**。
///
/// 分工：
/// - [docx_writer.dart] 只认识 OOXML 元素，不认识"题目"；
/// - 本文件把 [PaperPlan] + 题目内容（题干/选项/答案/解析/配图）装进 docx；
/// - 读数据库、从 [QuestionMediaStore] 读图片字节、弹保存框属于应用层
///   （`lib/features/questions/application/paper_docx_export.dart`），这里一律不碰。
///
/// 几个刻意的取舍：
/// 1. **不放水**：题干为空、答案缺失、组卷缺口、图片/公式没编进去，都如实写进
///    卷面（附录"导出提示"），而不是静默省略——用户拿到卷子时就知道缺什么。
/// 2. **公式失败保留原文**：`$...$` 交给注入的 [DocxMathCompiler]（reasoning-core
///    的 LaTeX→OMML 编译器）；编译失败时把 LaTeX 原文按普通文字写回去并计数，
///    绝不丢公式。
/// 3. **图片只嵌随文图**：`wp:inline`，等比缩放、不跑位；浮动图需要逐页实测
///    才能保证不压题干，这一版不做（见 docx_writer.dart 的注释）。
library;

import 'dart:typed_data';

import '../paper/paper_composer.dart';
import '../reasoning/capability_action.dart';
import 'docx_writer.dart';

/// 把一段 LaTeX 编译成 `<m:oMath>` 片段（不带 m 命名空间声明）。
///
/// 真实实现由 reasoning-core 的 `compileLatexToOmml` 提供；这里用函数类型注入，
/// 是为了让 [buildPaperDocx] 不依赖编译器的实现细节，测试里也能塞一个假编译器。
typedef DocxMathCompiler = String Function(String tex, {int? sizeHalfPt});

/// 一道题的导出素材（应用层从 questions / question_options / attachments 读出）。
class PaperDocxQuestion {
  const PaperDocxQuestion({
    required this.questionId,
    required this.stem,
    this.serialNo,
    this.subjectKey = '',
    this.sourceLevel = '',
    this.sourceLabel = '',
    this.year,
    this.region = '',
    this.questionType = '',
    this.options = const <PaperDocxOption>[],
    this.answer,
    this.solution,
    this.images = const <PaperDocxImage>[],
  });

  final String questionId;

  /// 题目唯一编号（schema v24 的 `serialNo`，形如 TR-00012）；null = 尚未回填。
  final String? serialNo;

  /// 题干原文，可含换行与 `$...$` 行内公式。
  final String stem;

  final String subjectKey;
  final String sourceLevel;

  /// 来源文字（如"2026 届高三上期末·某中学"），可为空。
  final String sourceLabel;

  final int? year;
  final String region;
  final String questionType;

  final List<PaperDocxOption> options;

  /// 答案文本；为空时尝试从正确选项字母推导（见 [_Assembler._answerText]）。
  final String? answer;

  /// 解析原文，可含 `$...$`。
  final String? solution;

  final List<PaperDocxImage> images;
}

/// 一道选择题的选项。
class PaperDocxOption {
  const PaperDocxOption({
    required this.label,
    required this.content,
    this.isCorrect = false,
  });

  /// 选项字母（A/B/C/D…）；空串时按顺序补齐字母。
  final String label;

  final String content;
  final bool isCorrect;

  bool get isEmpty => content.trim().isEmpty;
}

/// 一张待嵌入的题目配图。
class PaperDocxImage {
  const PaperDocxImage({
    required this.bytes,
    required this.extension,
    required this.pixelWidth,
    required this.pixelHeight,
    this.fileName,
  });

  final Uint8List bytes;

  /// 扩展名（png/jpg/jpeg/gif/bmp/webp…），由应用层从文件名/魔数给出。
  final String extension;

  final int pixelWidth;
  final int pixelHeight;
  final String? fileName;

  bool get hasUSatisfactoryExtent =>
      bytes.isNotEmpty && pixelWidth > 0 && pixelHeight > 0;
}

/// 导出的统计与告警：UI 用它在 SnackBar 里说清"缺了什么"。
class PaperDocxBuildResult {
  const PaperDocxBuildResult({
    required this.bytes,
    required this.questionCount,
    required this.paragraphCount,
    required this.imageCount,
    required this.imageSkippedCount,
    required this.formulaCount,
    required this.formulaFailureCount,
    required this.missingQuestionCount,
    required this.missingStemCount,
    required this.missingAnswerCount,
    required this.missingSolutionCount,
    required this.missingQuestionLabels,
    required this.imageSkippedNotes,
    required this.formulaFailures,
  });

  final Uint8List bytes;
  final int questionCount;
  final int paragraphCount;
  final int imageCount;
  final int imageSkippedCount;
  final int formulaCount;
  final int formulaFailureCount;
  final int missingQuestionCount;
  final int missingStemCount;
  final int missingAnswerCount;
  final int missingSolutionCount;

  /// 形如「第 3 题（TR-00012）」。
  final List<String> missingQuestionLabels;
  final List<String> imageSkippedNotes;
  final List<String> formulaFailures;

  bool get hasWarnings =>
      imageSkippedCount > 0 ||
      formulaFailureCount > 0 ||
      missingQuestionCount > 0 ||
      missingStemCount > 0 ||
      missingAnswerCount > 0 ||
      missingSolutionCount > 0;
}

/// 卷面上的中文文案。默认值就是中文；英文/其他语言由应用层用 l10n 覆盖。
class PaperDocxLabels {
  const PaperDocxLabels({
    this.title = '组卷卷面',
    this.generatedAtPrefix = '导出时间：',
    this.answerSectionTitle = '参考答案与解析',
    this.exportNotesHeading = '导出提示',
    this.uncoveredKnowledgePointHeading = '未覆盖的知识点',
    this.deferredHeading = '被上限挡下的知识点',
    this.answerLabel = '答案：',
    this.solutionLabel = '解析：',
    this.reasonLabel = '理由：',
    this.improvementLabel = '提升点：',
    this.backgroundLabel = '背景：',
    this.knowledgePointPrefix = '知识点：',
    this.noSubject = '未标注学科',
    this.noSourceLevel = '未标注来源',
    this.noKnowledgePoint = '未标知识点',
    this.emptyStem = '（题干为空，请回到题目详情页补全）',
    this.noAnswer = '（无答案）',
    this.noSolution = '（无解析）',
    this.missingQuestionLine = '题库中找不到这道题的内容，只保留了题号与组卷信息。',
    this.uncoveredEmpty = '（目标知识点都已覆盖）',
    this.deferredEmpty = '（没有被上限挡下的知识点）',
    this.missingQuestionHeading = '缺失题目',
    this.sectionHeading = '组卷说明',
    this.bySubjectHeading = '学科分布',
    this.byDomainHeading = '领域分布',
    this.manualHeading = '手工指定',
    this.quotaHeading = '配额',
    this.shortfallHeading = '保底缺口',
    this.uncoveredHeading = '未覆盖',
    this.nonePlaceholder = '无',
    this.headlineBuilder = defaultPaperDocxHeadline,
    this.subjectLabel,
    this.sourceLevelLabel,
    this.zoneLabel,
  });

  final String title;
  final String generatedAtPrefix;
  final String answerSectionTitle;
  final String exportNotesHeading;

  /// 知识点缺口小节标题（默认「未覆盖的知识点」）。
  ///
  /// 早先这个字段叫 `uncoveredHeading`；组卷说明的领域未覆盖子块需要同名 getter
  /// 后改名，默认文案与版式不变。
  final String uncoveredKnowledgePointHeading;
  final String deferredHeading;
  final String answerLabel;
  final String solutionLabel;
  final String reasonLabel;
  final String improvementLabel;
  final String backgroundLabel;
  final String knowledgePointPrefix;
  final String noSubject;
  final String noSourceLevel;
  final String noKnowledgePoint;
  final String emptyStem;
  final String noAnswer;
  final String noSolution;
  final String missingQuestionLine;
  final String uncoveredEmpty;
  final String deferredEmpty;
  final String missingQuestionHeading;

  /// 卷末「组卷说明」分节标题。只有 plan 里带配额/手工指定/保底缺口数据时才出现。
  final String sectionHeading;

  /// 组卷说明里的「学科分布」子块标题。
  final String bySubjectHeading;

  /// 组卷说明里的「领域分布」子块标题。
  final String byDomainHeading;

  /// 组卷说明里的「手工指定」子块标题。
  final String manualHeading;

  /// 组卷说明里的「配额」子块标题（被学科/领域上限挡下的计数）。
  final String quotaHeading;

  /// 组卷说明里的「保底缺口」子块标题。
  final String shortfallHeading;

  /// 领域未覆盖子块标题（默认「未覆盖」）。
  ///
  /// 与知识点缺口的 [uncoveredKnowledgePointHeading] 是两回事：这里指领域配额
  /// 一个都没凑到的领域。
  final String uncoveredHeading;

  /// 名单为空时的占位文案（默认「无」）。
  final String nonePlaceholder;

  /// 「想要 N 道，凑到 M 道」；与组卷页复制卷面的口径保持一致。
  final String Function(int want, int got) headlineBuilder;

  /// 学科轨道中文名；不传则用 [CapabilityAction.subjectLabelsZh]。
  final String Function(String subjectKey)? subjectLabel;

  /// 来源档位中文名；不传则用 [paperDocxSourceLevelLabel] 的默认表。
  final String Function(String sourceLevel)? sourceLevelLabel;

  /// 组卷区域中文名；不传则用 [PaperZone.labelZh]。
  final String Function(PaperZone zone)? zoneLabel;

  String subjectName(String subjectKey) {
    final custom = subjectLabel?.call(subjectKey);
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    final known = CapabilityAction.subjectLabelsZh[subjectKey];
    if (known != null) return known;
    return subjectKey.trim().isEmpty ? noSubject : subjectKey.trim();
  }

  String sourceLevelName(String level) {
    final custom = sourceLevelLabel?.call(level);
    if (custom != null) return custom.trim();
    return paperDocxSourceLevelLabel(level, emptyLabel: noSourceLevel);
  }

  String zoneName(PaperZone zone) {
    final custom = zoneLabel?.call(zone);
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return zone.labelZh;
  }
}

/// 默认的「想要 N 道，凑到 M 道」。
String defaultPaperDocxHeadline(int want, int got) => '想要 $want 道，凑到 $got 道';

/// 来源档位中文名（与收题页 `question_vocab_labels.dart` 的档位一一对应）。
const Map<String, String> kPaperDocxSourceLevelLabelsZh = <String, String>{
  'gaokao': '高考真题',
  'provincial_diagnostic': '强省强市诊断',
  'elite_school': '名校测试',
  'school': '学校题',
  'personal': '自建',
  'unknown': '未标注',
};

String paperDocxSourceLevelLabel(String level, {String emptyLabel = '未标注来源'}) {
  final trimmed = level.trim();
  if (trimmed.isEmpty) return emptyLabel;
  return kPaperDocxSourceLevelLabelsZh[trimmed] ?? trimmed;
}

/// 把一份组卷方案 + 题目内容装配成 .docx 字节。
///
/// [questions] 按 questionId 索引；缺项不会让导出失败，而是记进
/// [PaperDocxBuildResult.missingQuestionLabels] 并在附录里如实说明。
///
/// [includeCompositionNotes] 控制卷末是否渲染「组卷说明」；只有 [plan] 里带了
/// 配额、手工指定或保底缺口数据时才会出现该节，默认 plan 的卷面不因此变化。
PaperDocxBuildResult buildPaperDocx({
  required PaperPlan plan,
  required Map<String, PaperDocxQuestion> questions,
  required Map<String, String> knowledgePointNames,
  PaperDocxLabels labels = const PaperDocxLabels(),
  DocxMathCompiler? mathCompiler,
  DocxPageConfig page = const DocxPageConfig.a4Exam(),
  String? footerText,
  DateTime? generatedAt,
  bool includeAnswers = true,
  bool includeSolutions = true,
  bool includeReasons = true,
  bool includeGaps = true,
  bool includeCompositionNotes = true,
  String? title,
  String? subtitle,
}) {
  final builder = DocxDocumentBuilder(page: page, footerText: footerText);
  final assembler = _Assembler(
    builder: builder,
    page: page,
    plan: plan,
    questions: questions,
    knowledgePointNames: knowledgePointNames,
    labels: labels,
    mathCompiler: mathCompiler,
    generatedAt: generatedAt,
  );
  assembler.addPreamble(title: title ?? labels.title, subtitle: subtitle);
  assembler.addBody();
  assembler.addAppendix(
    includeAnswers: includeAnswers,
    includeSolutions: includeSolutions,
    includeReasons: includeReasons,
    includeGaps: includeGaps,
    includeCompositionNotes: includeCompositionNotes,
  );
  final bytes = builder.build();
  return assembler.result(bytes);
}

class _Assembler {
  _Assembler({
    required this.builder,
    required this.page,
    required this.plan,
    required this.questions,
    required this.knowledgePointNames,
    required this.labels,
    required this.mathCompiler,
    required this.generatedAt,
  });

  final DocxDocumentBuilder builder;
  final DocxPageConfig page;
  final PaperPlan plan;
  final Map<String, PaperDocxQuestion> questions;
  final Map<String, String> knowledgePointNames;
  final PaperDocxLabels labels;
  final DocxMathCompiler? mathCompiler;
  final DateTime? generatedAt;

  final List<String> missingQuestionLabels = <String>[];
  final List<String> imageSkippedNotes = <String>[];
  final List<String> formulaFailures = <String>[];
  int missingStemCount = 0;
  int missingAnswerCount = 0;
  int missingSolutionCount = 0;
  int imageSkippedCount = 0;
  int formulaFailureCount = 0;

  /// 附录里是否已经出过标题：只有第一个标题另起一页。
  bool _appendixStarted = false;

  // ---------------------------------------------------------------- 页首

  void addPreamble({required String title, String? subtitle}) {
    builder.addParagraph(
      DocxParagraph(
        inlines: <DocxInline>[
          DocxText(
            title,
            sizeHalfPt: kDocxTitleHalfPt,
            bold: true,
            fontCn: kDocxHeadFontCn,
          ),
        ],
        align: DocxAlign.center,
        spacingAfterTw: 120,
      ),
    );
    final headline =
        labels.headlineBuilder(plan.requestedCount, plan.items.length);
    final metaParts = <String>[headline];
    if (generatedAt != null) {
      metaParts
          .add('${labels.generatedAtPrefix}${_formatDateTime(generatedAt!)}');
    }
    builder.addParagraph(
      DocxParagraph(
        inlines: <DocxInline>[
          DocxText(
            metaParts.join(' '),
            sizeHalfPt: kDocxMetaHalfPt,
            colorHex: '595959',
          ),
        ],
        align: DocxAlign.center,
        spacingAfterTw: 60,
        borderBottomHex: 'BFBFBF',
      ),
    );
    final tail = subtitle?.trim() ?? '';
    if (tail.isNotEmpty) {
      builder.addParagraph(
        DocxParagraph(
          inlines: <DocxInline>[
            DocxText(
              tail,
              sizeHalfPt: kDocxMetaHalfPt,
              colorHex: '595959',
            ),
          ],
          align: DocxAlign.center,
          spacingAfterTw: 180,
        ),
      );
    }
  }

  // ---------------------------------------------------------------- 题干区

  void addBody() {
    for (var index = 0; index < plan.items.length; index++) {
      _addQuestion(index + 1, plan.items[index]);
    }
  }

  void _addQuestion(int number, PaperItem item) {
    final question = questions[item.questionId];
    final serial = question?.serialNo?.trim() ?? '';
    final numberText = serial.isEmpty ? '$number.' : '$number.  $serial';
    builder.addParagraph(
      DocxParagraph(
        inlines: <DocxInline>[
          DocxText(
            numberText,
            sizeHalfPt: kDocxHeadHalfPt,
            bold: true,
            fontCn: kDocxHeadFontCn,
          ),
        ],
        spacingBeforeTw: 140,
        spacingAfterTw: 20,
        keepNext: true,
      ),
    );
    builder.addParagraph(
      DocxParagraph(
        inlines: <DocxInline>[
          DocxText(
            _metaText(item, question),
            sizeHalfPt: kDocxMetaHalfPt,
            colorHex: '595959',
          ),
        ],
        spacingAfterTw: 40,
        keepNext: true,
      ),
    );
    if (question == null) {
      missingQuestionLabels.add('第 $number 题（${item.questionId}）');
      builder.addParagraph(
        DocxParagraph(
          inlines: <DocxInline>[
            DocxText(labels.missingQuestionLine, sizeHalfPt: kDocxBodyHalfPt),
          ],
          spacingAfterTw: 100,
        ),
      );
      return;
    }
    _addStem(question);
    _addOptions(question);
    _addImages(number, question);
  }

  void _addStem(PaperDocxQuestion question) {
    final lines = _splitLines(question.stem);
    if (lines.isEmpty) {
      missingStemCount++;
      builder.addParagraph(
        DocxParagraph(
          inlines: <DocxInline>[
            DocxText(
              labels.emptyStem,
              sizeHalfPt: kDocxBodyHalfPt,
              colorHex: '808080',
            ),
          ],
          spacingAfterTw: 60,
        ),
      );
      return;
    }
    for (var index = 0; index < lines.length; index++) {
      builder.addParagraph(
        DocxParagraph(
          inlines: _inlines(lines[index], sizeHalfPt: kDocxBodyHalfPt),
          spacingAfterTw: 40,
          keepLines: true,
          keepNext: index < lines.length - 1,
        ),
      );
    }
  }

  void _addOptions(PaperDocxQuestion question) {
    var fallbackLetter = 0;
    final options = <PaperDocxOption>[];
    for (final option in question.options) {
      if (option.isEmpty) continue;
      options.add(option);
    }
    for (final option in options) {
      fallbackLetter++;
      final label = option.label.trim().isEmpty
          ? _optionLetter(fallbackLetter)
          : option.label.trim();
      builder.addParagraph(
        DocxParagraph(
          inlines: _inlines(
            '$label. ${option.content.trim()}',
            sizeHalfPt: kDocxBodyHalfPt,
          ),
          leftIndentTw: 240,
          spacingAfterTw: 20,
          keepLines: true,
        ),
      );
    }
  }

  void _addImages(int number, PaperDocxQuestion question) {
    for (final image in question.images) {
      final fileName = image.fileName?.trim() ?? '';
      final suffix = fileName.isEmpty ? '' : '（$fileName）';
      if (!image.hasUSatisfactoryExtent) {
        imageSkippedCount++;
        imageSkippedNotes.add('第 $number 题$suffix：图片字节或尺寸信息缺失');
        continue;
      }
      if (!supportsDocxImageExtension(image.extension)) {
        imageSkippedCount++;
        imageSkippedNotes.add('第 $number 题$suffix：格式 ${image.extension} 不支持嵌入');
        continue;
      }
      builder.addImage(
        DocxImageSpec(
          bytes: image.bytes,
          extension: image.extension,
          pixelWidth: image.pixelWidth,
          pixelHeight: image.pixelHeight,
          spacingBeforeTw: 60,
          spacingAfterTw: 40,
          note: '第 $number 题$suffix',
        ),
      );
    }
  }

  // ---------------------------------------------------------------- 附录

  void addAppendix({
    required bool includeAnswers,
    required bool includeSolutions,
    required bool includeReasons,
    required bool includeGaps,
    required bool includeCompositionNotes,
  }) {
    final wantsAnswers = includeAnswers || includeSolutions || includeReasons;
    final wantsComposition = includeCompositionNotes && _hasCompositionData();
    final wantsGaps = includeGaps;
    if (!wantsAnswers && !wantsComposition && !wantsGaps) return;
    if (wantsAnswers) {
      _addAppendixHeading(labels.answerSectionTitle);
      for (var index = 0; index < plan.items.length; index++) {
        _addAnswerEntry(
          number: index + 1,
          item: plan.items[index],
          includeAnswers: includeAnswers,
          includeSolutions: includeSolutions,
          includeReasons: includeReasons,
        );
      }
    }
    // 组卷说明紧跟答案区，和知识点缺口一样属于卷末对账信息。
    if (wantsComposition) {
      _addCompositionNotes();
    }
    if (wantsGaps) {
      _addGaps();
    }
    _addExportNotes();
  }

  void _addAnswerEntry({
    required int number,
    required PaperItem item,
    required bool includeAnswers,
    required bool includeSolutions,
    required bool includeReasons,
  }) {
    final question = questions[item.questionId];
    if (question == null) {
      builder.addParagraph(
        DocxParagraph(
          inlines: <DocxInline>[
            DocxText(
              '$number. ${labels.missingQuestionLine}',
              sizeHalfPt: kDocxBodyHalfPt,
            ),
          ],
          spacingBeforeTw: 80,
          spacingAfterTw: 40,
        ),
      );
      return;
    }
    if (includeAnswers) {
      final answer = _answerText(question);
      if (answer == null) missingAnswerCount++;
      builder.addParagraph(
        DocxParagraph(
          inlines: <DocxInline>[
            DocxText(
              '$number. ',
              sizeHalfPt: kDocxBodyHalfPt,
              bold: true,
            ),
            DocxText(
              labels.answerLabel,
              sizeHalfPt: kDocxBodyHalfPt,
              bold: true,
            ),
            ..._inlines(
              answer ?? labels.noAnswer,
              sizeHalfPt: kDocxBodyHalfPt,
            ),
          ],
          spacingBeforeTw: 80,
          spacingAfterTw: 20,
          keepNext: includeSolutions || includeReasons,
        ),
      );
    }
    if (includeSolutions) {
      final solution = question.solution?.trim() ?? '';
      if (solution.isEmpty) {
        missingSolutionCount++;
        // 解析缺失时仍写占位句：卷末不能静默少一段，缺失情况同时进导出提示。
        builder.addParagraph(
          DocxParagraph(
            inlines: <DocxInline>[
              DocxText(
                labels.solutionLabel,
                sizeHalfPt: kDocxBodyHalfPt,
                bold: true,
                colorHex: '404040',
              ),
              DocxText(
                labels.noSolution,
                sizeHalfPt: kDocxBodyHalfPt,
                colorHex: '808080',
              ),
            ],
            spacingAfterTw: 20,
            keepNext: includeReasons,
            keepLines: true,
          ),
        );
      } else {
        for (final line in _splitLines(solution)) {
          builder.addParagraph(
            DocxParagraph(
              inlines: <DocxInline>[
                DocxText(
                  labels.solutionLabel,
                  sizeHalfPt: kDocxBodyHalfPt,
                  bold: true,
                  colorHex: '404040',
                ),
                ..._inlines(line, sizeHalfPt: kDocxBodyHalfPt),
              ],
              spacingAfterTw: 20,
              keepLines: true,
            ),
          );
        }
      }
    }
    if (includeReasons) {
      _addReasonLines(item);
    }
  }

  void _addReasonLines(PaperItem item) {
    final entries = <String, String>{
      labels.reasonLabel: item.reasonZh.trim(),
      labels.improvementLabel: item.improvementNote.trim(),
      labels.backgroundLabel: item.backgroundZh.trim(),
    };
    for (final entry in entries.entries) {
      if (entry.value.isEmpty) continue;
      for (final line in _splitLines(entry.value)) {
        builder.addParagraph(
          DocxParagraph(
            inlines: <DocxInline>[
              DocxText(
                entry.key,
                sizeHalfPt: kDocxMetaHalfPt,
                colorHex: '595959',
                bold: true,
              ),
              ..._inlines(line, sizeHalfPt: kDocxMetaHalfPt),
            ],
            spacingAfterTw: 20,
            keepLines: true,
          ),
        );
      }
    }
  }

  void _addGaps() {
    final uncovered = plan.uncoveredKnowledgePointIds
        .map(_knowledgePointName)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final deferred = plan.deferredKnowledgePointIds
        .map(_knowledgePointName)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    _addAppendixHeading(labels.uncoveredKnowledgePointHeading);
    if (uncovered.isEmpty) {
      _addBullet(labels.uncoveredEmpty);
    } else {
      for (final name in uncovered) {
        _addBullet(name);
      }
    }
    _addAppendixHeading(labels.deferredHeading);
    if (deferred.isEmpty) {
      _addBullet(labels.deferredEmpty);
    } else {
      for (final name in deferred) {
        _addBullet(name);
      }
    }
  }

  /// 组卷说明：把配额、手工指定与保底缺口的账面如实写进卷末，方便对账。
  ///
  /// 只有 [PaperPlan] 里确实带数据时才由 [addAppendix] 调用；默认 plan（没有
  /// 配额、没有手工指定）不会出现这一节，卷面与旧版逐字节一致。
  void _addCompositionNotes() {
    _addAppendixHeading(labels.sectionHeading);
    _addSubjectDistribution();
    _addDomainDistribution();
    _addManualSelectionNotes();
    _addQuotaBlockedNotes();
    _addShortfallNotes();
  }

  bool _hasCompositionData() {
    if (plan.bySubject.isNotEmpty) return true;
    if (plan.byDomain.isNotEmpty) return true;
    if (plan.uncoveredDomains.isNotEmpty) return true;
    if (plan.manualSelectionEnabled) {
      if (plan.manualIncludedCount > 0) return true;
      if (plan.manualMissingQuestionIds.isNotEmpty) return true;
      if (plan.manualSkippedQuestionIds.isNotEmpty) return true;
      if (plan.manualConflictQuestionIds.isNotEmpty) return true;
    }
    if (plan.quotaBlockedQuestions.isNotEmpty) return true;
    if (plan.quotaBlockedByDomain.isNotEmpty) return true;
    if (plan.subjectShortfalls.isNotEmpty) return true;
    if (plan.domainShortfalls.isNotEmpty) return true;
    return false;
  }

  void _addSubjectDistribution() {
    if (plan.bySubject.isEmpty) return;
    _addAppendixHeading(labels.bySubjectHeading);
    for (final entry in plan.bySubject.entries) {
      _addBullet('${labels.subjectName(entry.key)}：${entry.value} 道');
    }
  }

  void _addDomainDistribution() {
    final uncovered = plan.uncoveredDomains;
    if (plan.byDomain.isEmpty && uncovered.isEmpty) return;
    _addAppendixHeading(labels.byDomainHeading);
    for (final entry in plan.byDomain.entries) {
      _addBullet('${entry.key}：${entry.value} 道');
    }
    if (uncovered.isEmpty) return;
    _addAppendixHeading(labels.uncoveredHeading);
    for (final domain in uncovered) {
      _addBullet(domain);
    }
  }

  void _addManualSelectionNotes() {
    if (!plan.manualSelectionEnabled) return;
    final hasLists = plan.manualMissingQuestionIds.isNotEmpty ||
        plan.manualSkippedQuestionIds.isNotEmpty ||
        plan.manualConflictQuestionIds.isNotEmpty;
    if (plan.manualIncludedCount <= 0 && !hasLists) return;
    _addAppendixHeading(labels.manualHeading);
    _addBullet('进卷 ${plan.manualIncludedCount} 道');
    _addBullet('题库里找不到：${_idListText(plan.manualMissingQuestionIds)}');
    _addBullet(
      'target_count 装不下：${_idListText(plan.manualSkippedQuestionIds)}',
    );
    _addBullet(
      '与排除冲突（按排除处理）：${_idListText(plan.manualConflictQuestionIds)}',
    );
  }

  String _idListText(List<String> ids) {
    if (ids.isEmpty) return labels.nonePlaceholder;
    return ids.join('、');
  }

  void _addQuotaBlockedNotes() {
    if (plan.quotaBlockedQuestions.isEmpty &&
        plan.quotaBlockedByDomain.isEmpty) {
      return;
    }
    _addAppendixHeading(labels.quotaHeading);
    if (plan.quotaBlockedQuestions.isNotEmpty) {
      final counts = <String, int>{};
      for (final blocked in plan.quotaBlockedQuestions) {
        counts.update(
          blocked.subjectKey,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      _addBullet(
        '被学科上限挡下：${_quotaCountsText(counts, subjectNames: true)}',
      );
    }
    if (plan.quotaBlockedByDomain.isNotEmpty) {
      final counts = <String, int>{};
      for (final blocked in plan.quotaBlockedByDomain) {
        counts.update(blocked.domain, (value) => value + 1, ifAbsent: () => 1);
      }
      _addBullet(
        '被领域上限挡下：${_quotaCountsText(counts, subjectNames: false)}',
      );
    }
  }

  /// 键按字典序排，保证同一份 plan 每次导出的字句顺序一致。
  String _quotaCountsText(
    Map<String, int> counts, {
    required bool subjectNames,
  }) {
    final keys = counts.keys.toList(growable: false)..sort();
    return keys.map((key) {
      final name = subjectNames ? labels.subjectName(key) : key;
      return '$name ${counts[key]} 道';
    }).join('、');
  }

  void _addShortfallNotes() {
    if (plan.subjectShortfalls.isEmpty && plan.domainShortfalls.isEmpty) return;
    _addAppendixHeading(labels.shortfallHeading);
    for (final shortfall in plan.subjectShortfalls) {
      _addBullet(
        _shortfallText(
          labels.subjectName(shortfall.subjectKey),
          shortfall.minimumCount,
          shortfall.selectedCount,
          shortfall.availableCount,
        ),
      );
    }
    for (final shortfall in plan.domainShortfalls) {
      _addBullet(
        _shortfallText(
          shortfall.domain,
          shortfall.minimumCount,
          shortfall.selectedCount,
          shortfall.availableCount,
        ),
      );
    }
  }

  String _shortfallText(
    String name,
    int minimumCount,
    int selectedCount,
    int availableCount,
  ) {
    if (availableCount <= 0) {
      return '$name：题库里没有可用题（保底 $minimumCount 道）';
    }
    final missing = minimumCount - selectedCount;
    return '$name：差 $missing 道（保底 $minimumCount 道，已排 '
        '$selectedCount 道；可用候选 $availableCount 道）';
  }

  void _addExportNotes() {
    final notes = <String>[];
    if (missingQuestionLabels.isNotEmpty) {
      notes.add(
        '${labels.missingQuestionHeading}：${missingQuestionLabels.join('、')}',
      );
    }
    if (missingStemCount > 0) notes.add('题干为空：$missingStemCount 道');
    if (missingAnswerCount > 0) notes.add('答案缺失：$missingAnswerCount 道');
    if (missingSolutionCount > 0) notes.add('解析缺失：$missingSolutionCount 道');
    for (final note in imageSkippedNotes) {
      notes.add(note);
    }
    for (final failure in formulaFailures) {
      notes.add('公式未能编译（已保留 LaTeX 原文）：$failure');
    }
    if (notes.isEmpty) return;
    _addAppendixHeading(labels.exportNotesHeading);
    for (final note in notes) {
      _addBullet(note);
    }
  }

  /// 附录标题：**只有第一个**另起一页（通常是「参考答案与解析」），其后的
  /// 缺口小节与导出提示顺排。
  ///
  /// 早先每个标题都 `pageBreakBefore`，Word 实测 3 道题 + 2 个缺口小节 = 4 页，
  /// 后两页各只有一个小标题，等于把纸排空了。
  void _addAppendixHeading(String text) {
    builder.addParagraph(
      DocxParagraph(
        inlines: <DocxInline>[
          DocxText(
            text,
            sizeHalfPt: kDocxHeadHalfPt,
            bold: true,
            fontCn: kDocxHeadFontCn,
          ),
        ],
        pageBreakBefore: !_appendixStarted,
        spacingBeforeTw: 140,
        spacingAfterTw: 60,
        keepNext: true,
      ),
    );
    _appendixStarted = true;
  }

  void _addBullet(String text) {
    builder.addParagraph(
      DocxParagraph(
        inlines: _inlines('· $text', sizeHalfPt: kDocxMetaHalfPt),
        leftIndentTw: 240,
        spacingAfterTw: 20,
        keepLines: true,
      ),
    );
  }

  // ---------------------------------------------------------------- 工具

  String _metaText(PaperItem item, PaperDocxQuestion? question) {
    final parts = <String>[];
    final subjectKey = item.subjectKey.trim().isNotEmpty
        ? item.subjectKey.trim()
        : (question?.subjectKey.trim() ?? '');
    parts.add(labels.subjectName(subjectKey));
    final level = (question?.sourceLevel.trim().isNotEmpty ?? false)
        ? question!.sourceLevel.trim()
        : item.sourceLevel.trim();
    final levelName = labels.sourceLevelName(level);
    if (levelName.isNotEmpty && levelName != labels.noSourceLevel) {
      parts.add(levelName);
    }
    final sourceLabel = question?.sourceLabel.trim() ?? '';
    if (sourceLabel.isNotEmpty && sourceLabel != levelName) {
      parts.add(sourceLabel);
    }
    final zone = labels.zoneName(item.zone);
    if (zone.isNotEmpty) parts.add(zone);
    final knowledgePointName = _knowledgePointName(item.knowledgePointId ?? '');
    if (knowledgePointName.isEmpty) {
      parts.add(labels.noKnowledgePoint);
    } else {
      parts.add('${labels.knowledgePointPrefix}$knowledgePointName');
    }
    final year = question?.year;
    if (year != null) parts.add('$year 年');
    final region = question?.region.trim() ?? '';
    if (region.isNotEmpty) parts.add(region);
    return parts.join(' · ');
  }

  String _knowledgePointName(String id) {
    final name = knowledgePointNames[id]?.trim() ?? '';
    return name.isEmpty ? '' : name;
  }

  String? _answerText(PaperDocxQuestion question) {
    final answer = question.answer?.trim() ?? '';
    if (answer.isNotEmpty) return answer;
    var fallbackIndex = 0;
    final correct = <String>[];
    for (final option in question.options) {
      fallbackIndex++;
      if (!option.isCorrect) continue;
      final label = option.label.trim().isEmpty
          ? _optionLetter(fallbackIndex)
          : option.label.trim();
      correct.add(label);
    }
    if (correct.isEmpty) return null;
    return correct.join('、');
  }

  List<DocxInline> _inlines(String text, {required int sizeHalfPt}) {
    final result = <DocxInline>[];
    final plain = StringBuffer();
    final normalized = text.replaceAll('\r\n', '\n');
    var index = 0;
    while (index < normalized.length) {
      final char = normalized[index];
      if (char == r'\\' && index + 1 < normalized.length) {
        final next = normalized[index + 1];
        if (next == r'$') {
          plain.write(r'$');
          index += 2;
          continue;
        }
      }
      if (char != r'$') {
        plain.write(char);
        index++;
        continue;
      }
      final end = normalized.indexOf(r'$', index + 1);
      if (end < 0) {
        plain.write(char);
        index++;
        continue;
      }
      final tex = normalized.substring(index + 1, end);
      if (tex.trim().isEmpty) {
        plain.write(r'$$');
        index = end + 1;
        continue;
      }
      final compiler = mathCompiler;
      if (compiler == null) {
        plain.write(r'$');
        plain.write(tex);
        plain.write(r'$');
        index = end + 1;
        continue;
      }
      try {
        final omml = compiler(tex, sizeHalfPt: sizeHalfPt);
        if (plain.isNotEmpty) {
          result.add(DocxText(plain.toString(), sizeHalfPt: sizeHalfPt));
          plain.clear();
        }
        result.add(DocxMath(omml));
        index = end + 1;
      } on Object catch (error) {
        formulaFailureCount++;
        final preview = tex.length > 40 ? '${tex.substring(0, 40)}…' : tex;
        formulaFailures.add('$preview（$error）');
        plain.write(r'$');
        plain.write(tex);
        plain.write(r'$');
        index = end + 1;
      }
    }
    if (plain.isNotEmpty) {
      result.add(DocxText(plain.toString(), sizeHalfPt: sizeHalfPt));
    }
    if (result.isEmpty) {
      result.add(DocxText('', sizeHalfPt: sizeHalfPt));
    }
    return result;
  }

  List<String> _splitLines(String text) {
    if (text.trim().isEmpty) return const <String>[];
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _optionLetter(int position) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (position <= 0) return '';
    if (position <= letters.length) return letters[position - 1];
    return '#$position';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number < 10 ? '0$number' : '$number';
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  PaperDocxBuildResult result(Uint8List bytes) {
    return PaperDocxBuildResult(
      bytes: bytes,
      questionCount: plan.items.length,
      paragraphCount: builder.paragraphCount,
      imageCount: builder.imageCount,
      imageSkippedCount: imageSkippedCount,
      formulaCount: builder.mathCount,
      formulaFailureCount: formulaFailureCount,
      missingQuestionCount: missingQuestionLabels.length,
      missingStemCount: missingStemCount,
      missingAnswerCount: missingAnswerCount,
      missingSolutionCount: missingSolutionCount,
      missingQuestionLabels: List<String>.unmodifiable(missingQuestionLabels),
      imageSkippedNotes: List<String>.unmodifiable(imageSkippedNotes),
      formulaFailures: List<String>.unmodifiable(formulaFailures),
    );
  }
}
