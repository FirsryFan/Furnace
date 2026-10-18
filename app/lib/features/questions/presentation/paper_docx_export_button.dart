/// 组卷页的「导出 Word」：卷面 → .docx 字节（装配层）→ 系统「另存为」。
///
/// 分工：
/// - 装配与 OOXML 全在 `application/paper_docx_export.dart` 与
///   `domain/services/export/paper_docx.dart`，这里不拼 OOXML、不重算统计；
/// - 公式由推理层注入 `compileLatexToOmml`：编译失败由装配层自己 catch 并保留
///   LaTeX 原文，界面**不再重复兜底**；
/// - 保存交给 `file_picker` 的静态 `saveFile`（字节由平台实现写盘）。静态方法
///   在 widget test 里没法替换平台通道，所以用 [paperDocxSaverProvider] 留 seam；
/// - 界面只说三件事：成功（含题目/配图数与文件名）、失败原文、告警明细。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/export/omml/omml.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_docx_export.dart';
import '../application/paper_quality_provider.dart';
import '../application/question_media_providers.dart';

/// 「导出 Word」按钮的稳定 key（widget test 与键盘/无障碍定位用）。
const Key paperDocxExportButtonKey = Key('paper-export-docx');

/// 把 [bytes] 存成用户选定的文件；返回落盘位置（`Uri`），用户取消则返回 null。
///
/// 抽成 typedef 是为了让 widget test 能截获保存动作：`FilePicker.saveFile` 是
/// 静态方法，平台通道没法在测试里被 mock。
typedef PaperDocxSaver = Future<Uri?> Function({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
});

/// 默认保存实现：弹系统「另存为」，由 file_picker 平台实现写盘。
///
/// 与 `features/settings/presentation/data_section.dart` 的 tfpkg 导出同一口径：
/// 不自己再 `File.write`，取消（null）不提示成功。
Future<Uri?> savePaperDocxWithFilePicker({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
}) {
  return FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
    type: FileType.any,
  );
}

/// 保存动作的 provider：测试 override 它，不弹真实对话框、不碰磁盘。
final paperDocxSaverProvider = Provider<PaperDocxSaver>(
  (ref) => savePaperDocxWithFilePicker,
);

// ---------------------------------------------------------------------------
// 纯逻辑（可单测，不碰 widget）
// ---------------------------------------------------------------------------

/// 一次导出的「提示」总条数：与 [PaperDocxExportResult.hasWarnings] 同一口径。
///
/// 口径 = 六类缺失计数 + 装配层读图告警条数。用它而不是
/// `hasWarnings ? 1 : 0`，SnackBar 才能说出「有 3 处提示」而不是笼统的「有提示」。
int paperDocxWarningCount(PaperDocxExportResult result) {
  final report = result.report;
  return report.imageSkippedCount +
      report.formulaFailureCount +
      report.missingQuestionCount +
      report.missingStemCount +
      report.missingAnswerCount +
      report.missingSolutionCount +
      result.imageLoadNotes.length;
}

/// 告警明细对话框里的一组提示。
enum PaperDocxWarningKind {
  missingQuestions,
  skippedImages,
  formulaFailures,
  imageLoadNotes,
}

/// 一组告警：前 [visibleItems] 条展示，剩下的用「等 N 条」收尾。
class PaperDocxWarningGroup {
  const PaperDocxWarningGroup({
    required this.kind,
    required this.visibleItems,
    required this.totalCount,
  });

  final PaperDocxWarningKind kind;
  final List<String> visibleItems;
  final int totalCount;

  int get hiddenCount => totalCount - visibleItems.length;

  bool get hasHidden => hiddenCount > 0;
}

/// 明细对话框要列的告警分组：每类最多 [maxPerGroup] 条，超出折算成隐藏条数。
///
/// 缺题干/缺答案/缺解析只有计数、没有逐题文案（领域层把它们汇总进卷末导出提示），
/// 由对话框单独补一行汇总；这里只列有逐条文案的四类。
List<PaperDocxWarningGroup> paperDocxWarningGroups(
  PaperDocxExportResult result, {
  int maxPerGroup = 3,
}) {
  final report = result.report;
  final groups = <PaperDocxWarningGroup>[];

  void add(PaperDocxWarningKind kind, List<String> items) {
    if (items.isEmpty) return;
    final visible =
        items.length <= maxPerGroup ? items : items.sublist(0, maxPerGroup);
    groups.add(
      PaperDocxWarningGroup(
        kind: kind,
        visibleItems: visible,
        totalCount: items.length,
      ),
    );
  }

  add(PaperDocxWarningKind.missingQuestions, report.missingQuestionLabels);
  add(PaperDocxWarningKind.skippedImages, report.imageSkippedNotes);
  add(PaperDocxWarningKind.formulaFailures, report.formulaFailures);
  add(PaperDocxWarningKind.imageLoadNotes, result.imageLoadNotes);
  return groups;
}

/// 告警明细对话框：缺题 / 跳过配图 / 公式失败 / 读图提示 + 缺字段汇总。
///
/// [maxPerGroup] 透传给 [paperDocxWarningGroups]；测试用它验证「等 N 条」。
Future<void> showPaperDocxWarningsDialog(
  BuildContext context,
  AppLocalizations l10n,
  PaperDocxExportResult result, {
  int maxPerGroup = 3,
}) {
  final theme = Theme.of(context);
  final groups = paperDocxWarningGroups(result, maxPerGroup: maxPerGroup);
  final report = result.report;
  final missingFieldLines = <String>[
    if (report.missingStemCount > 0)
      l10n.questionPaperExportDocxMissingStem(report.missingStemCount),
    if (report.missingAnswerCount > 0)
      l10n.questionPaperExportDocxMissingAnswer(report.missingAnswerCount),
    if (report.missingSolutionCount > 0)
      l10n.questionPaperExportDocxMissingSolution(report.missingSolutionCount),
  ];

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final bodyStyle = theme.textTheme.bodySmall;
      return AlertDialog(
        title: Text(l10n.questionPaperExportDocxWarningsTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in groups) ...[
                  Text(
                    _warningGroupTitle(l10n, group.kind),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  for (final item in group.visibleItems)
                    Text('· $item', style: bodyStyle),
                  if (group.hasHidden)
                    Text(
                      l10n.questionPaperExportDocxMoreItems(group.hiddenCount),
                      style: bodyStyle,
                    ),
                  const SizedBox(height: 8),
                ],
                if (missingFieldLines.isNotEmpty) ...[
                  Text(
                    l10n.questionPaperExportDocxMissingFields,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  for (final line in missingFieldLines)
                    Text('· $line', style: bodyStyle),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      );
    },
  );
}

String _warningGroupTitle(AppLocalizations l10n, PaperDocxWarningKind kind) {
  return switch (kind) {
    PaperDocxWarningKind.missingQuestions =>
      l10n.questionPaperExportDocxMissingQuestions,
    PaperDocxWarningKind.skippedImages =>
      l10n.questionPaperExportDocxSkippedImages,
    PaperDocxWarningKind.formulaFailures =>
      l10n.questionPaperExportDocxFormulaFailures,
    PaperDocxWarningKind.imageLoadNotes =>
      l10n.questionPaperExportDocxImageLoadNotes,
  };
}

// ---------------------------------------------------------------------------
// 按钮
// ---------------------------------------------------------------------------

/// 组卷页的「导出 Word」按钮。
///
/// 空卷面也**可以**点：领域层能导出「标题 + 缺口说明」，所以这里不学「复制卷面」
/// 的禁用语义；提示语改用 [AppLocalizations.questionPaperExportDocxEmptyDone]
/// 说清楚「卷面是空的」。
class PaperDocxExportButton extends ConsumerStatefulWidget {
  const PaperDocxExportButton({super.key, required this.plan});

  /// 当前卷面（页面从 `paperPlanProvider` 拿到后传进来）。
  final PaperPlan plan;

  @override
  ConsumerState<PaperDocxExportButton> createState() =>
      _PaperDocxExportButtonState();
}

class _PaperDocxExportButtonState extends ConsumerState<PaperDocxExportButton> {
  /// 导出中（装配/保存都是异步的）：防重入，也用来禁用按钮 + 显示 loading。
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 订阅质量报告：只取「已经算好的」那份给导出用（没算完/报错就是 null，
    // 导出照常、卷末不出现质量节，与旧版一致）。这里不 await，不阻塞导出。
    ref.watch(paperQualityReportProvider);
    return FilledButton.tonalIcon(
      key: paperDocxExportButtonKey,
      onPressed: _exporting ? null : _export,
      icon: _exporting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.description_outlined),
      label: Text(
        _exporting
            ? l10n.questionPaperExportDocxBusy
            : l10n.questionPaperExportDocx,
      ),
    );
  }

  Future<void> _export() async {
    if (_exporting) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      // 质量报告可能仍在算：只取当前值，不等待（拿不到就按旧行为导出）。
      final qualityReport = ref.read(paperQualityReportProvider).valueOrNull;
      final result = await buildPaperDocxExport(
        db: ref.read(appDatabaseProvider),
        mediaStore: ref.read(questionMediaStoreProvider),
        plan: widget.plan,
        mathCompiler: compileLatexToOmml,
        qualityReport: qualityReport,
      );
      final target = await ref.read(paperDocxSaverProvider)(
        dialogTitle: l10n.questionPaperExportDocx,
        fileName: result.suggestedFileName,
        bytes: result.bytes,
      );
      // 取消另存为 = 什么都没发生：不提示成功，也不提示失败。
      if (!mounted || target == null) return;
      _showSuccess(messenger, l10n, result);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.questionPaperExportDocxFailed}: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSuccess(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    PaperDocxExportResult result,
  ) {
    final warningCount = paperDocxWarningCount(result);
    final base = widget.plan.items.isEmpty
        ? l10n.questionPaperExportDocxEmptyDone(result.suggestedFileName)
        : l10n.questionPaperExportDocxDone(
            result.report.questionCount,
            result.imageCount,
            result.suggestedFileName,
          );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          warningCount > 0
              ? '$base · ${l10n.questionPaperExportDocxWarnings(warningCount)}'
              : base,
        ),
        action: warningCount > 0
            ? SnackBarAction(
                label: l10n.questionPaperExportDocxWarningsAction,
                onPressed: () {
                  if (!mounted) return;
                  showPaperDocxWarningsDialog(context, l10n, result);
                },
              )
            : null,
      ),
    );
  }
}
