/// 收题页（`docs/QUESTION_BANK_DESIGN.md` §6 收题入口 B、§7 拍照手写整理入口）。
///
/// 一段收题 = **先落库，再确认**，而且落到库里的是 `state='raw'`：
///
///  1. 粘贴题干 → 当场 `ingest()`，写 `questions` / `question_options`；
///     指纹重复时不新增，返回既有题目并提示（§2 去重）。
///  2. 拍照/选图 → 图片复制进 `handwriting_intake/`，`attachments` 记一行，
///     并建一条 `origin='ai_scan'`、`state='raw'` 的题，题干是"待识别（图片）：<文件名>"。
///     OCR 与结构化（§6 步骤 2）由推理层接上之后改写这条题，本页不做。
///  3. 题库列表 → 一条题一行，带筛选、搜索、删除。
///
/// **本页不做 AI 解题按钮。** 推理管道（`features/questions/application/**`）由
/// Lead 落地；这里只留出 `_IntakeLibrarySection` 之后的位置，等管道就绪后由
/// Lead 接上，避免两边同时改一个文件。
///
/// 所有写入都走既有仓储，因此 `DbWriteInterceptor` → `DataChangeBus` 会把列表
/// 自动刷新一遍，本页不需要手动 invalidate。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../data/handwriting_intake_store.dart';
import 'question_intake_providers.dart';

/// `QuestionDraft` 的字段是裸字符串（表里也是 `text()`），仓储没有导出常量，
/// 这里给本页用到的取值一个名字，免得字符串在页面里飘。
const String _typeSolution = 'solution';
const String _typeSingleChoice = 'single_choice';
const String _originManual = 'manual';
const String _originAiScan = 'ai_scan';
const String _stateRaw = 'raw';

/// 收题页。
class QuestionIntakePage extends ConsumerStatefulWidget {
  const QuestionIntakePage({super.key});

  @override
  ConsumerState<QuestionIntakePage> createState() => _QuestionIntakePageState();
}

class _QuestionIntakePageState extends ConsumerState<QuestionIntakePage> {
  // ── 粘贴建题的草稿。只在内存里，直到按「入库」。 ────────────────────────────
  final _stemController = TextEditingController();
  final _answerController = TextEditingController();
  final _solutionController = TextEditingController();
  final _sourceLabelController = TextEditingController();
  final _yearController = TextEditingController();
  final _regionController = TextEditingController();
  final _difficultyController = TextEditingController();
  final _stemSearchController = TextEditingController();

  final List<_OptionDraft> _options = <_OptionDraft>[
    _OptionDraft(label: 'A'),
    _OptionDraft(label: 'B'),
  ];

  String? _subjectKey;
  String _questionType = _typeSolution;
  String _sourceLevel = 'unknown';
  bool _saving = false;
  bool _picking = false;

  @override
  void dispose() {
    for (final controller in [
      _stemController,
      _answerController,
      _solutionController,
      _sourceLabelController,
      _yearController,
      _regionController,
      _difficultyController,
      _stemSearchController,
    ]) {
      controller.dispose();
    }
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  bool get _isChoice => _questionType == _typeSingleChoice;

  // ── 入库 ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final stem = _stemController.text.trim();
    if (stem.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionIntakeStemRequired)),
      );
      return;
    }

    double? difficulty;
    final difficultyText = _difficultyController.text.trim();
    if (difficultyText.isNotEmpty) {
      difficulty = double.tryParse(difficultyText);
      if (difficulty == null || difficulty < 1 || difficulty > 10) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.questionIntakeDifficultyInvalid)),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      // 空选项不入库：表单里总有两个空行（「加一个选项」也先给空行），空白选项
      // 落库就是日后要清理的垃圾。留下的那些重新编号，选项标签里不留空档。
      final optionDrafts = <QuestionOptionDraft>[];
      if (_isChoice) {
        for (final option in _options) {
          final content = option.controller.text.trim();
          if (content.isEmpty) {
            continue;
          }
          optionDrafts.add(QuestionOptionDraft(
            label: String.fromCharCode(65 + optionDrafts.length),
            content: content,
            isCorrect: option.isCorrect,
            sortOrder: optionDrafts.length,
          ));
        }
      }

      final draft = QuestionDraft(
        stem: stem,
        answer: _emptyToNull(_answerController.text),
        solution: _emptyToNull(_solutionController.text),
        subjectKey: _subjectKey ?? '',
        questionType: _questionType,
        sourceLevel: _sourceLevel,
        sourceLabel: _sourceLabelController.text.trim(),
        year: int.tryParse(_yearController.text.trim()),
        region: _emptyToNull(_regionController.text),
        difficulty: difficulty,
        difficultySource: difficulty == null ? null : 'manual',
        origin: _originManual,
        options: optionDrafts,
      );

      final result = await ref.read(questionRepositoryProvider).ingest(draft);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(result.created
            ? l10n.questionIntakeSaved(stem)
            : l10n.questionIntakeDuplicate(stem)),
      ));
      // 清掉的只有题干：学科/来源/年份通常是同一批题共用的，重打一遍最费事。
      _stemController.clear();
      _answerController.clear();
      _solutionController.clear();
      for (final option in _options) {
        option.controller.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ── 拍照 / 选图 ─────────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(handwritingIntakeStoreProvider);
    try {
      // 手写照片不压缩：`VisionImageEncoder` 的 1280 长边是为"发给模型看"服务的，
      // 用在这里会把小字压没；OCR 要的是原始笔迹。
      //
      // file_picker 12：`pickFiles` 默认就允许多选（`allowMultiple` 已废弃，单选用
      // `pickFile`），所以这里把参数留空。
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'heic', 'bmp'],
      );
      if (picked.isEmpty) {
        return;
      }
      setState(() => _picking = true);
      final repository = ref.read(questionRepositoryProvider);
      var saved = 0;
      for (final file in picked) {
        final image = await store.save(file);
        await repository.ingest(QuestionDraft(
          stem: l10n.questionIntakePhotoStem(image.fileName),
          origin: _originAiScan,
          // 图片还没有 OCR，题干只是占位，所以是 `raw`：`structured` 意味着
          // 已经结构化过（粘贴建题那条路），这里还不是。
          state: _stateRaw,
        ));
        saved++;
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionIntakePhotoAdded(saved))),
      );
    } catch (error) {
      // 选图打不开（缺平台实现、权限被撤）要说出来，不能让按钮看起来是死的。
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionIntakePhotoFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _removePhoto(PendingHandwritingImage image) async {
    await ref.read(handwritingIntakeStoreProvider).delete(image);
  }

  // ── 题库列表 ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(Question question) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.questionIntakeDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.questionIntakeCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.questionIntakeDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(questionRepositoryProvider).deleteQuestion(question.id);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.questionIntakeDeleted(question.stem))),
    );
  }

  void _setFilter(
    QuestionLibraryFilter Function(QuestionLibraryFilter current) update,
  ) {
    final current = ref.read(questionLibraryFilterProvider);
    ref.read(questionLibraryFilterProvider.notifier).state = update(current);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionIntakeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.questionIntakeSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _IntakeFormCard(
            stemController: _stemController,
            answerController: _answerController,
            solutionController: _solutionController,
            sourceLabelController: _sourceLabelController,
            yearController: _yearController,
            regionController: _regionController,
            difficultyController: _difficultyController,
            options: _options,
            subjectKey: _subjectKey,
            questionType: _questionType,
            sourceLevel: _sourceLevel,
            isChoice: _isChoice,
            saving: _saving,
            onSubjectChanged: (value) => setState(() => _subjectKey = value),
            onQuestionTypeChanged: (value) =>
                setState(() => _questionType = value),
            onSourceLevelChanged: (value) =>
                setState(() => _sourceLevel = value),
            onOptionChanged: () => setState(() {}),
            onAddOption: _addOption,
            onRemoveOption: _removeOption,
            onSubmit: _submit,
          ),
          const SizedBox(height: 12),
          _HandwritingCard(
            picking: _picking,
            onPick: _pickImages,
            onRemove: _removePhoto,
          ),
          const SizedBox(height: 12),
          _IntakeLibrarySection(
            searchController: _stemSearchController,
            onSearchChanged: (value) => _setFilter(
              (current) => current.copyWith(stemContains: value),
            ),
            onClearSearch: () {
              _stemSearchController.clear();
              _setFilter((current) => current.copyWith(clearStem: true));
            },
            onDelete: _confirmDelete,
          ),
        ],
      ),
    );
  }

  void _addOption() {
    if (_options.length >= 26) {
      return;
    }
    setState(() {
      _options.add(_OptionDraft(
        label: String.fromCharCode(65 + _options.length),
      ));
    });
  }

  void _removeOption(int index) {
    if (_options.length <= 1) {
      return;
    }
    setState(() {
      _options.removeAt(index).dispose();
      // 删了中间一个之后标签要重新排（A/B/C…），否则会出现 A、C 这种空白。
      for (var i = 0; i < _options.length; i++) {
        _options[i].label = String.fromCharCode(65 + i);
      }
    });
  }
}

/// 一个选项的编辑态。
class _OptionDraft {
  _OptionDraft({required this.label});

  String label;
  final controller = TextEditingController();
  bool isCorrect = false;

  void dispose() => controller.dispose();
}

/// 粘贴建题的校对表（§6 步骤 2/3：改的是内存，按「入库」才写库）。
class _IntakeFormCard extends StatelessWidget {
  const _IntakeFormCard({
    required this.stemController,
    required this.answerController,
    required this.solutionController,
    required this.sourceLabelController,
    required this.yearController,
    required this.regionController,
    required this.difficultyController,
    required this.options,
    required this.subjectKey,
    required this.questionType,
    required this.sourceLevel,
    required this.isChoice,
    required this.saving,
    required this.onSubjectChanged,
    required this.onQuestionTypeChanged,
    required this.onSourceLevelChanged,
    required this.onOptionChanged,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onSubmit,
  });

  final TextEditingController stemController;
  final TextEditingController answerController;
  final TextEditingController solutionController;
  final TextEditingController sourceLabelController;
  final TextEditingController yearController;
  final TextEditingController regionController;
  final TextEditingController difficultyController;
  final List<_OptionDraft> options;
  final String? subjectKey;
  final String questionType;
  final String sourceLevel;
  final bool isChoice;
  final bool saving;
  final ValueChanged<String?> onSubjectChanged;
  final ValueChanged<String> onQuestionTypeChanged;
  final ValueChanged<String> onSourceLevelChanged;
  final VoidCallback onOptionChanged;
  final VoidCallback onAddOption;
  final ValueChanged<int> onRemoveOption;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionIntakePasteSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stemController,
              maxLines: 4,
              minLines: 3,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeStemLabel,
                hintText: l10n.questionIntakeStemHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: subjectKey,
                    decoration: InputDecoration(
                      labelText: l10n.questionIntakeSubjectLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.questionIntakeSubjectNone),
                      ),
                      for (final key in CapabilityAction.subjectKeys)
                        DropdownMenuItem<String?>(
                          value: key,
                          child: Text(
                            CapabilityAction.subjectLabelsZh[key] ?? key,
                          ),
                        ),
                    ],
                    onChanged: onSubjectChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: questionType,
                    decoration: InputDecoration(
                      labelText: l10n.questionIntakeQuestionTypeLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: _typeSolution,
                        child: Text(l10n.questionIntakeTypeSolution),
                      ),
                      DropdownMenuItem(
                        value: _typeSingleChoice,
                        child: Text(l10n.questionIntakeTypeSingleChoice),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onQuestionTypeChanged(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (isChoice) ...[
              const SizedBox(height: 12),
              Text(
                l10n.questionIntakeOptionsLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      // `Checkbox` 自己没有 tooltip 参数，但"这个框是勾正确答案的"
                      // 不说清楚就只是一个没有标签的方框。
                      Tooltip(
                        message: l10n.questionIntakeCorrectTooltip,
                        child: Checkbox(
                          value: options[i].isCorrect,
                          onChanged: (value) {
                            options[i].isCorrect = value ?? false;
                            onOptionChanged();
                          },
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: options[i].controller,
                          decoration: InputDecoration(
                            labelText:
                                l10n.questionIntakeOptionLabel(options[i].label),
                            hintText: l10n.questionIntakeOptionContentHint,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.questionIntakeRemoveOption,
                        icon: const Icon(Icons.close),
                        onPressed: options.length <= 1
                            ? null
                            : () => onRemoveOption(i),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAddOption,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.questionIntakeAddOption),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: answerController,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeAnswerLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: solutionController,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSolutionLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: sourceLevel,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLevelLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final level in const [
                  'gaokao',
                  'provincial_diagnostic',
                  'elite_school',
                  'school',
                  'personal',
                  'unknown',
                ])
                  DropdownMenuItem(value: level, child: Text(_sourceLevelLabel(l10n, level))),
              ],
              onChanged: (value) {
                if (value != null) {
                  onSourceLevelChanged(value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sourceLabelController,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLabelLabel,
                hintText: l10n.questionIntakeSourceLabelHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.questionIntakeYearLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: regionController,
                    decoration: InputDecoration(
                      labelText: l10n.questionIntakeRegionLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: difficultyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.questionIntakeDifficultyLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: saving ? null : onSubmit,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(l10n.questionIntakeSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 拍照/选图 + 待整理清单。
class _HandwritingCard extends ConsumerWidget {
  const _HandwritingCard({
    required this.picking,
    required this.onPick,
    required this.onRemove,
  });

  final bool picking;
  final Future<void> Function() onPick;
  final Future<void> Function(PendingHandwritingImage image) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingHandwritingImagesProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionIntakePhotoSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: picking ? null : onPick,
                  icon: picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    picking ? l10n.questionIntakePicking : l10n.questionIntakePickImages,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.questionIntakePhotoPending,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            pending.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('$error'),
              ),
              data: (images) => images.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l10n.questionIntakeNoPhotos),
                    )
                  : Column(
                      children: [
                        for (final image in images)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.image_outlined),
                            title: Text(image.fileName),
                            subtitle: Text(
                              l10n.questionIntakePhotoSummary(
                                image.mime ?? '?',
                                image.extension,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: l10n.questionIntakeRemovePhoto,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onRemove(image),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 题库列表：筛选 + 搜索 + 删除。
class _IntakeLibrarySection extends ConsumerWidget {
  const _IntakeLibrarySection({
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onDelete,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Future<void> Function(Question question) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(questionLibraryFilterProvider);
    final library = ref.watch(questionLibraryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionIntakeLibrarySection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: l10n.questionIntakeSearchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: onClearSearch,
                      ),
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(l10n.questionIntakeFilterAll),
                  selected: filter.subjectKey == null &&
                      filter.sourceLevel == null &&
                      filter.state == null,
                  onSelected: (_) => _applyFilter(
                    context,
                    ref,
                    const QuestionLibraryFilter(),
                  ),
                ),
                for (final state in const ['raw', 'structured', 'processed'])
                  FilterChip(
                    label: Text(_stateLabel(l10n, state)),
                    selected: filter.state == state,
                    onSelected: (selected) => _applyFilter(
                      context,
                      ref,
                      selected
                          ? QuestionLibraryFilter(state: state)
                          : const QuestionLibraryFilter(),
                    ),
                  ),
                for (final level in const [
                  'gaokao',
                  'provincial_diagnostic',
                  'elite_school',
                  'school',
                ])
                  FilterChip(
                    label: Text(_sourceLevelLabel(l10n, level)),
                    selected: filter.sourceLevel == level,
                    onSelected: (selected) => _applyFilter(
                      context,
                      ref,
                      selected
                          ? QuestionLibraryFilter(sourceLevel: level)
                          : const QuestionLibraryFilter(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            library.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('$error'),
              ),
              data: (entries) => entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l10n.questionIntakeNoQuestions),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.questionIntakeListLimitNote(questionLibraryLimit),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        for (final entry in entries)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry.question.stem,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _librarySubtitle(l10n, entry),
                            ),
                            trailing: IconButton(
                              tooltip: l10n.questionIntakeDelete,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onDelete(entry.question),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _librarySubtitle(
    AppLocalizations l10n,
    QuestionListEntry entry,
  ) {
    final parts = <String>[];
    final subject = entry.question.subjectKey;
    if (subject.isNotEmpty) {
      parts.add(CapabilityAction.subjectLabelsZh[subject] ?? subject);
    }
    parts.add(_sourceLevelLabel(l10n, entry.question.sourceLevel));
    parts.add(_stateLabel(l10n, entry.question.state));
    if (entry.optionCount > 0) {
      parts.add(l10n.questionIntakeOptionCount(entry.optionCount));
    }
    return parts.join(' · ');
  }
}

/// 筛选是一次性动作（chip 已表现选中态），所以直接写状态而不是再包一层。
void _applyFilter(
  BuildContext context,
  WidgetRef ref,
  QuestionLibraryFilter filter,
) {
  ref.read(questionLibraryFilterProvider.notifier).state = filter;
}

String _sourceLevelLabel(AppLocalizations l10n, String level) =>
    switch (level) {
      'gaokao' => l10n.questionIntakeSourceGaokao,
      'provincial_diagnostic' => l10n.questionIntakeSourceProvincialDiagnostic,
      'elite_school' => l10n.questionIntakeSourceEliteSchool,
      'school' => l10n.questionIntakeSourceSchool,
      'personal' => l10n.questionIntakeSourcePersonal,
      _ => l10n.questionIntakeSourceUnknown,
    };

String _stateLabel(AppLocalizations l10n, String state) => switch (state) {
      'structured' => l10n.questionIntakeStateStructured,
      'processed' => l10n.questionIntakeStateProcessed,
      _ => l10n.questionIntakeStateRaw,
    };
