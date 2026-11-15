/// 开发者信息页：一道题的**全部开发侧内容**集中在这里。
///
/// 学生页（`question_detail_page.dart`）只留题干/选项/答案/自测/学习读数。
/// 开发字段与动作——内部 id、`state`、`origin`、来源分级、`aiQuality`、
/// 题名/来源编辑、原题链接、配图增删、入库体检——不再摊在学生页，统一收进本页：
///
///  * 入口只有一个：学生页页底的「开发者信息」文字按钮；
///  * 本页不写新表、不改 schema，只复用既有对话框与 provider；
///  * 开发字段的标签用技术口径（id / state / origin…），不需要 ARB：
///    这一页不是学生界面，术语越直接越好（与 `cognitiveFitLabel` 同一取舍）。
///
/// 证据口径：本文件只做展示与转调，判据/写入都在既有领域层与仓库层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/questions/question_source.dart';
import '../../../l10n/app_localizations.dart';
import 'question_audit_view.dart';
import 'question_detail_providers.dart';
import 'question_media_view.dart';
import 'question_source_edit_dialog.dart';
import 'question_title_dialog.dart';
import 'question_vocab_labels.dart';

/// 学生页「开发者信息」入口的 key（页面与测试共用）。
const Key questionDeveloperEntryKey = Key('question-developer-entry');

/// 「复制原题链接」按钮的 key（测试定位用）。
const Key questionSourceCopyButtonKey = Key('question-source-copy');

/// 开发者信息页：一道题的内部字段 + 开发侧编辑动作。
class QuestionDeveloperPage extends ConsumerWidget {
  const QuestionDeveloperPage({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detailAsync = ref.watch(questionDetailProvider(questionId));
    final detail = detailAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionDeveloperTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            l10n.questionDeveloperHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (detailAsync.isLoading && !detailAsync.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(),
            )
          else if (detailAsync.hasError)
            Text('${detailAsync.error}')
          else if (detail == null)
            Text(l10n.questionDetailQuestionMissing)
          else ...[
            _QuestionDeveloperActions(
              question: detail.question,
              onRefresh: () => ref.invalidate(questionDetailProvider(questionId)),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.questionDeveloperImagesTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            // 题干配图与答案截图共用同一套「选图/落盘/删除」流程，只是角色不同。
            QuestionImagesSection(questionId: questionId, editable: true),
            const SizedBox(height: 12),
            QuestionImagesSection(
              questionId: questionId,
              editable: true,
              kind: QuestionImagesSectionKind.answer,
            ),
            const SizedBox(height: 16),
            QuestionAuditSection(questionId: questionId),
            const SizedBox(height: 16),
            Text(
              l10n.questionDeveloperRawTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _DeveloperRawFields(
              l10n: l10n,
              question: detail.question,
            ),
          ],
        ],
      ),
    );
  }
}

/// 开发侧动作：改题名 / 改来源 / 原题链接（复制 + 编辑）。
class _QuestionDeveloperActions extends StatelessWidget {
  const _QuestionDeveloperActions({
    required this.question,
    required this.onRefresh,
  });

  final Question question;

  /// 来源元信息保存后让详情重读（题名/链接对话框自己会 invalidate）。
  final VoidCallback onRefresh;

  Future<void> _editTitle(BuildContext context) async {
    await showQuestionTitleDialog(
      context,
      questionId: question.id,
      stem: question.stem,
      currentTitle: question.title,
      subjectKey: question.subjectKey,
      questionType: question.questionType,
    );
  }

  Future<void> _editSource(BuildContext context) async {
    final edited = await showDialog<
        ({String level, String label, int? year, String? region})>(
      context: context,
      builder: (_) => _EditSourceDialog(question: question),
    );
    if (edited == null || !context.mounted) {
      return;
    }
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(questionRepositoryProvider)
          .updateSource(
            question.id,
            sourceLevel: edited.level,
            sourceLabel: edited.label,
            year: edited.year,
            region: edited.region,
          );
      onRefresh();
    } on ArgumentError catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${error.message}')));
    }
  }

  Future<void> _editSourceLinks(BuildContext context) async {
    await showQuestionSourceEditDialog(context, question: question);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 「点回去核对原题」只认可信的绝对 http(s) 链接，或组卷网两个数字 id。
    final source = questionSourceFor(
      sourceUrl: question.sourceUrl,
      zujuanQuestionId: question.zujuanQuestionId,
      zujuanBankId: question.zujuanBankId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton.icon(
              key: questionTitleEditButtonKey,
              onPressed: () => _editTitle(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(l10n.questionTitleEditTooltip),
            ),
            TextButton.icon(
              onPressed: () => _editSource(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(l10n.questionDetailEditSource),
            ),
            TextButton.icon(
              key: questionSourceEditButtonKey,
              onPressed: () => _editSourceLinks(context),
              icon: const Icon(Icons.add_link, size: 16),
              label: Text(
                source == null ? l10n.questionSourceAdd : l10n.questionSourceEdit,
              ),
            ),
          ],
        ),
        if (source != null) ...<Widget>[
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(
                Icons.link,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  source.isZujuan ? l10n.questionSourceZujuan : source.host,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                key: questionSourceCopyButtonKey,
                onPressed: () => _copyQuestionSource(context, source),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(l10n.questionSourceCopyLink),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 复制规范化后的原题链接，写进剪贴板后再提示。
Future<void> _copyQuestionSource(
  BuildContext context,
  QuestionSourceRef source,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: source.url));
  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.questionSourceCopyDone)));
}

/// 内部字段（只读）：开发者核对数据用，不参与学生阅读。
class _DeveloperRawFields extends StatelessWidget {
  const _DeveloperRawFields({required this.l10n, required this.question});

  final AppLocalizations l10n;
  final Question question;

  static String _time(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${pad(at.month)}-${pad(at.day)} '
        '${pad(at.hour)}:${pad(at.minute)}:${pad(at.second)}';
  }

  static String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <({String label, String value, bool mono})>[
      (label: '内部 ID', value: question.id, mono: true),
      (
        label: '题号',
        value: question.serialNo == null
            ? '未编号'
            : formatQuestionSerial(question.serialNo!),
        mono: false,
      ),
      (label: '题名', value: _value(question.title), mono: false),
      (label: '学科', value: _value(question.subjectKey), mono: false),
      (label: '题型', value: _value(question.questionType), mono: false),
      (
        label: '状态',
        value: '${question.state}（${stateLabel(l10n, question.state)}）',
        mono: false,
      ),
      (
        label: '来源',
        value: '${question.origin}（${_originLabel(l10n, question.origin)}）',
        mono: false,
      ),
      (
        label: '来源分级',
        value: '${question.sourceLevel}'
            '（${sourceLevelLabel(l10n, question.sourceLevel)}）',
        mono: false,
      ),
      (label: '来源说明', value: _value(question.sourceLabel), mono: false),
      (label: '年份', value: _value(question.year), mono: false),
      (label: '地区', value: _value(question.region), mono: false),
      (label: '文本格式', value: _value(question.textFormat), mono: false),
      (label: '难度', value: _value(question.difficulty), mono: false),
      (
        label: '难度来源',
        value: _value(question.difficultySource),
        mono: false,
      ),
      (label: 'AI 质量', value: _value(question.aiQuality), mono: false),
      (label: 'AI 质量说明', value: _value(question.aiQualityNote), mono: false),
      (label: '题干指纹', value: question.stemFingerprint, mono: true),
      (label: '原题链接', value: _value(question.sourceUrl), mono: true),
      (
        label: '组卷网题号',
        value: _value(question.zujuanQuestionId),
        mono: false,
      ),
      (label: '组卷网 bankId', value: _value(question.zujuanBankId), mono: false),
      (label: '创建时间', value: _time(question.createdAt), mono: false),
      (label: '更新时间', value: _time(question.updatedAt), mono: false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 104,
                  child: Text(
                    row.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // 不指定 monospace：界面字体缺 monospace 时（例如测试环境）
                  // 会退化成方块；内部 ID / 指纹用正文字体同样可读可选中。
                  child: SelectableText(
                    row.value,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 来源（`origin`）：手工 / 拍照扫描 / Furnace 内建。
String _originLabel(AppLocalizations l10n, String origin) => switch (origin) {
      'manual' => l10n.questionIntakeOriginManual,
      'ai_scan' => l10n.questionIntakeOriginAiScan,
      'furnace' => l10n.questionIntakeOriginFurnace,
      _ => origin.trim().isEmpty ? l10n.questionIntakeOriginManual : origin,
    };

/// 「改来源」对话框：来源分级（白名单下拉）+ 来源说明/年份/地区。
///
/// 三条纪律：① 只改来源元信息（题干/答案/选项一个字不动）；② 留空的字段 =
/// **不改**那一列；③ 年份写错就停在对话框里说清楚，不悄悄当"没填"。
class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.question});

  final Question question;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late String _level = widget.question.sourceLevel;
  late final TextEditingController _labelController =
      TextEditingController(text: widget.question.sourceLabel);
  late final TextEditingController _yearController =
      TextEditingController(text: widget.question.year?.toString() ?? '');
  late final TextEditingController _regionController =
      TextEditingController(text: widget.question.region ?? '');
  String? _yearProblem;

  @override
  void dispose() {
    _labelController.dispose();
    _yearController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final rawYear = _yearController.text.trim();
    int? year;
    if (rawYear.isNotEmpty) {
      year = int.tryParse(rawYear);
      if (year == null || year < 1900 || year > 2200) {
        setState(() => _yearProblem = l10n.questionDetailEditSourceYearBad);
        return;
      }
    }
    final label = _labelController.text.trim();
    final region = _regionController.text.trim();
    Navigator.of(context).pop((
      level: _level,
      label: label,
      year: year,
      region: region.isEmpty ? null : region,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.questionDetailEditSourceTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLevelLabel,
              ),
              items: <DropdownMenuItem<String>>[
                for (final level in kSourceLevelWeight.keys)
                  DropdownMenuItem<String>(
                    value: level,
                    child: Text(sourceLevelLabel(l10n, level)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _level = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLabelLabel,
                hintText: l10n.questionIntakeSourceLabelHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yearController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeYearLabel,
                errorText: _yearProblem,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _regionController,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeRegionLabel,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailEditSourceHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
