/// 题库（顶部目的地）。
///
/// 用户反馈（m09439）：题库总览不需要那么多详细信息，呈现必要信息、标签和
/// 题目命名（自己命名或自动生成），图片要大一点。于是这一页：
///
/// * 上面四个按钮 = 往题库里加东西的全部入口；
/// * 搜索框 + 标签筛选 + 学科筛选 + 错题本开关（四者 AND，可一键清除）；
///   自测答错过的题在行内带「错 N 次」徽标；
/// * 一行小字统计；
/// * 每行 = 封面图（128×96）+ 题名（没题名时用题干摘要兜底）+ 题号徽章、
///   学科、标签叶子名；行尾 ⋮ 菜单可改名 / 自动命名 / 复制题号。
///
/// 数据走 `questionLibrarySnapshotProvider`：不筛选读前 500 题，筛选生效读全库
/// （否则第 500 题之后的题永远筛不到）；一次拿全题目 + 题名 + 标签 + 图片清单，
/// 见 `question_library_reader.dart`。页面只读，写库只发生在命名对话框与批量
/// 自动命名里，写完让两档数据源一起失效。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/media/thumbnail_spec.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/material_intake_page.dart';
import '../application/question_bulk_tagging.dart';
import '../application/question_library_filter.dart';
import '../application/question_library_provider.dart';
import '../application/question_media_providers.dart';
import '../application/question_pack_service.dart';
import 'handwriting_queue_page.dart';
import 'question_audit_view.dart';
import 'question_bulk_tag_dialog.dart';
import 'question_detail_page.dart';
import 'question_intake_page.dart';
import 'question_library_filter_bar.dart';
import 'question_library_tag_filter_dialog.dart';
import 'question_media_view.dart';
import 'question_paper_page.dart' show QuestionPaperPage, subjectLabelOf;
import 'question_title_dialog.dart';

/// AppBar 上「自动命名缺名的题」按钮。
const Key questionBankAutoNameKey = Key('question-bank-auto-name');

/// AppBar 上「进入多选」按钮。
const Key questionBankSelectKey = Key('question-bank-select');

/// 多选态 AppBar 左上角「退出多选」按钮。
const Key questionBankExitSelectionKey = Key('question-bank-exit-selection');

/// 多选态 AppBar「全选」按钮。
const Key questionBankSelectAllKey = Key('question-bank-select-all');

/// 多选态 AppBar「清空选择」按钮。
const Key questionBankClearSelectionKey = Key('question-bank-clear-selection');

/// 多选态底部「打标签」按钮。
const Key questionBankTagSelectedKey = Key('question-bank-tag-selected');

/// 多选态底部「导出选中」按钮。
const Key questionBankExportSelectedKey = Key('question-bank-export-selected');

/// 多选态底部「删除选中」按钮。
const Key questionBankDeleteSelectedKey = Key('question-bank-delete-selected');

/// 列表行按题 id 生成 key：`question-bank-row-<questionId>`（测试定位用）。
String questionBankRowKeyFor(String questionId) =>
    'question-bank-row-$questionId';

/// 行内「错 N 次」徽标按题 id 生成 key：`question-bank-wrong-badge-<id>`。
String questionBankWrongBadgeKeyFor(String questionId) =>
    'question-bank-wrong-badge-$questionId';

/// 行菜单「清除作答记录」项按题 id 生成 key：
/// `question-bank-clear-attempts-<id>`（只有答错过的行才出现）。
String questionBankClearAttemptsKeyFor(String questionId) =>
    'question-bank-clear-attempts-$questionId';

/// 标签路径的叶子名（`文化课/学科/数学` → `数学`），去重保序。
List<String> questionBankTagLeafNames(List<String> tagPaths) {
  final leaves = <String>[];
  for (final path in tagPaths) {
    final parts = path.split('/');
    final leaf = parts.isEmpty ? '' : parts.last.trim();
    if (leaf.isEmpty || leaves.contains(leaf)) {
      continue;
    }
    leaves.add(leaf);
  }
  return leaves;
}

/// 批量删除确认里的题目预览：取前 [max] 个题名用「、」连接；
/// 实际数量多于预览时追加「等 N 道」；没有可读题名时返回空串。
String questionBankDeletePreview(
  Iterable<String> titles, {
  int max = 3,
}) {
  final names = <String>[];
  var total = 0;
  for (final title in titles) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    total++;
    if (names.length < max) {
      names.add(trimmed);
    }
  }
  if (names.isEmpty) {
    return '';
  }
  if (total > names.length) {
    return '${names.join('、')} 等 $total 道';
  }
  return names.join('、');
}

/// 题库总览页。
class QuestionBankPage extends ConsumerStatefulWidget {
  const QuestionBankPage({super.key});

  @override
  ConsumerState<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends ConsumerState<QuestionBankPage> {
  /// 搜索 + 标签 + 学科三个条件（AND）。学科键是稳定 snake_case
  /// （`CapabilityAction.subjectKeys`），筛选比较只用键，显示名走 `subjectLabelOf`。
  QuestionLibraryFilter _filter = QuestionLibraryFilter.empty;

  /// 搜索框文字；清除筛选要连输入框一起清空，所以 controller 放页面 State。
  late final TextEditingController _search;

  /// 批量自动命名进行中：防重入，也让按钮变成进度圈。
  bool _autoNaming = false;

  /// 多选态：AppBar 与底部动作条换成一整套批量操作。
  bool _selecting = false;

  /// 多选态选中的题 id（跨学科筛选保留；退出多选即清空）。
  final Set<String> _selected = <String>{};

  /// 批量操作（打标签/导出/删除）进行中：防重入并禁用动作条。
  bool _bulkBusy = false;

  /// 上一档数据源的最后一帧快照。
  ///
  /// 「不筛选 ⇄ 筛选生效」会换 provider，新 provider 加载完前有一段 loading；
  /// 留住上一档数据，整页（含搜索框）就不会被进度圈顶掉，输入焦点也不丢。
  QuestionLibrarySnapshot? _lastSnapshot;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 改筛选条件：筛选的任何变化都必须走这里 setState，列表与计数一起刷新。
  void _applyFilter(QuestionLibraryFilter filter) {
    setState(() => _filter = filter);
  }

  /// 只清搜索词（输入框里的 ×）：标签筛选保留。
  void _clearSearchText() {
    _search.clear();
    _applyFilter(_filter.copyWith(text: ''));
  }

  /// 一键清除全部筛选条件，并同步清空搜索框文字。
  void _clearFilter() {
    _search.clear();
    _applyFilter(QuestionLibraryFilter.empty);
  }

  /// 已选标签路径排序后给筛选条展示（Set 顺序不稳定）。
  List<String> get _selectedTagPaths => _filter.tagPaths.toList()..sort();

  void _removeTagPath(String path) {
    final next = <String>{..._filter.tagPaths}..remove(path);
    _applyFilter(_filter.copyWith(tagPaths: next));
  }

  /// 标签筛选：词表来自当前题库快照（只用已挂到题上的路径，避免选了查不到题）；
  /// 对话框返回 `null` = 取消，空集 = 清除标签筛选。
  Future<void> _openTagFilter(QuestionLibrarySnapshot snapshot) async {
    final picked = await showQuestionLibraryTagFilterDialog(
      context,
      tagPaths: snapshot.tagPaths,
      initialSelection: _filter.tagPaths,
    );
    if (picked == null || !mounted) {
      return;
    }
    _applyFilter(_filter.copyWith(tagPaths: picked));
  }

  void _open(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 两档数据源一起失效：不筛选读前 500 题，筛选生效读全库。
  void _invalidateLibrary() {
    ref.invalidate(questionLibraryOverviewProvider);
    ref.invalidate(questionLibraryFullProvider);
  }

  Future<void> _refresh() async {
    _invalidateLibrary();
    await ref.read(questionLibrarySnapshotProvider(_filter.isNotEmpty).future);
  }

  /// 改名：对话框自己写库并 invalidate，这里只拿题库里其它行的题名做去重参考。
  ///
  /// 写完再让两档数据源一起失效：筛选档读的是全库 provider，只失效总览会
  /// 在筛选状态下留下旧题名。
  Future<void> _rename(
    QuestionLibraryEntry entry,
    List<String> existingTitles,
  ) async {
    final result = await showQuestionTitleDialog(
      context,
      questionId: entry.questionId,
      stem: entry.stem,
      currentTitle: entry.title,
      subjectKey: entry.subjectKey,
      questionType: entry.questionType,
      existingTitles: existingTitles,
    );
    if (result != null && result.changed) {
      _invalidateLibrary();
    }
  }

  /// 单行自动命名：直接按题干生成一个建议题名写库（用户不满意可以再改名）。
  Future<void> _autoNameEntry(
    QuestionLibraryEntry entry,
    List<String> existingTitles,
  ) async {
    final l10n = AppLocalizations.of(context);
    final title = suggestQuestionTitleForEntry(
      entry,
      existingTitles: existingTitles,
    );
    if (title == null) {
      _showSnack(l10n.questionBankAutoNameNothing);
      return;
    }
    try {
      await ref
          .read(questionRepositoryProvider)
          .setQuestionTitle(entry.questionId, title);
      _invalidateLibrary();
      if (!mounted) {
        return;
      }
      _showSnack(l10n.questionTitleAutoNamed(title));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(l10n.questionBankAutoNameFailed('$error'));
    }
  }

  /// 清除某道题的自测作答记录（行菜单「清除记录」）。
  ///
  /// 错题本的唯一数据来源是 `question_attempts`；清掉后这道题不再算「答错过」，
  /// 行内「错 N 次」徽标消失，题目本身不动。确认框写明不可撤销；写库触发
  /// databaseRevision，两档题库数据源会自动重读（这里再显式失效一次，兜底）。
  Future<void> _clearAttempts(QuestionLibraryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.questionDetailAttemptClearConfirmTitle),
        content: Text(l10n.questionDetailAttemptClearConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.questionDetailAttemptClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(questionAttemptRepositoryProvider)
          .deleteForQuestion(entry.questionId);
    } catch (error) {
      if (mounted) {
        _showSnack(l10n.questionDetailAttemptClearFailed('$error'));
      }
      return;
    }
    _invalidateLibrary();
    if (!mounted) {
      return;
    }
    _showSnack(l10n.questionDetailAttemptClearDone);
  }

  /// 批量自动命名：只补没有题名的行，一次事务写库，失败按命中数汇总。
  Future<void> _autoNameMissing() async {
    if (_autoNaming) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final snapshot = ref
        .read(questionLibrarySnapshotProvider(_filter.isNotEmpty))
        .valueOrNull;
    if (snapshot == null) {
      return;
    }
    final titles = suggestBulkQuestionTitles(_visibleEntries(snapshot));
    if (titles.isEmpty) {
      _showSnack(l10n.questionBankAutoNameNothing);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.questionBankAutoNameDialogTitle(titles.length)),
        content: Text(l10n.questionBankAutoNameDialogBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.questionBankAutoNameStart),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _autoNaming = true);
    try {
      final changed =
          await ref.read(questionRepositoryProvider).setQuestionTitles(titles);
      _invalidateLibrary();
      await ref
          .read(questionLibrarySnapshotProvider(_filter.isNotEmpty).future);
      if (!mounted) {
        return;
      }
      final failed = titles.length - changed;
      _showSnack(
        failed <= 0
            ? l10n.questionBankAutoNameDone(titles.length)
            : l10n.questionBankAutoNamePartial(changed, failed),
      );
    } catch (error) {
      if (mounted) {
        _showSnack(l10n.questionBankAutoNameFailed('$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _autoNaming = false);
      }
    }
  }

  /// 当前筛选下用户看得到的路：全选/自动命名只作用于这些题，不会偷偷包含
  /// 被筛掉的。匹配口径全部在 `question_library_filter.dart`（纯逻辑、可单测）。
  List<QuestionLibraryEntry> _visibleEntries(
    QuestionLibrarySnapshot snapshot,
  ) =>
      filterQuestionLibraryEntries(snapshot.entries, _filter);

  void _enterSelection() {
    setState(() {
      _selecting = true;
      _selected.clear();
    });
  }

  void _enterSelectionWith(String questionId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(questionId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelection(String questionId) {
    setState(() {
      if (!_selected.remove(questionId)) {
        _selected.add(questionId);
      }
    });
  }

  void _selectAll(QuestionLibrarySnapshot snapshot) {
    setState(() {
      _selected
        ..clear()
        ..addAll(<String>[
          for (final entry in _visibleEntries(snapshot)) entry.questionId,
        ]);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
    });
  }

  /// 批量打标签：对话框里选路径 → 应用层 `tagQuestions` 写库 → SnackBar 报告。
  /// 不做二次确认（Lead 定：确认动作就是对话框里的「添加标签」）。
  Future<void> _bulkTag() async {
    if (_bulkBusy || _selected.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final picked = await showQuestionBulkTagDialog(context);
    if (picked == null || picked.isEmpty || !mounted) {
      return;
    }
    setState(() => _bulkBusy = true);
    try {
      final report = await tagQuestions(
        tags: ref.read(tagRepositoryProvider),
        questionIds: _selected,
        tagPaths: picked,
      );
      _invalidateLibrary();
      if (!mounted) {
        return;
      }
      final parts = <String>[
        l10n.questionBankTagDone(report.addedLinks, report.skippedLinks),
        if (report.hasMissingTagPaths)
          l10n.questionBankTagMissing(report.missingTagPaths.length),
        if (report.hasFailures)
          l10n.questionBankTagFailed(report.failedTagPaths.join('、')),
      ];
      _showSnack(parts.join(' · '));
    } catch (error) {
      if (mounted) {
        _showSnack(l10n.questionBankTagFailed('$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _bulkBusy = false);
      }
    }
  }

  /// 批量导出：只导出选中的题（`questionIds` 非空即只导这些），用户取消保存静默。
  Future<void> _bulkExport() async {
    if (_bulkBusy || _selected.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _bulkBusy = true);
    try {
      final result = await ref
          .read(questionPackServiceProvider)
          .exportBytes(questionIds: _selected.toSet());
      if (!mounted) {
        return;
      }
      if (result.questionCount == 0) {
        _showSnack(l10n.questionBankExportEmpty);
        return;
      }
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.questionBankExportSelected,
        fileName: 'furnace-${_questionBankTimestamp()}-selected.tqb',
        bytes: result.bytes,
        type: FileType.any,
      );
      if (target == null || !mounted) {
        return;
      }
      _showSnack(
        l10n.questionBankExportDone(
          result.questionCount,
          _questionBankSizeText(result.bytes.length),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showSnack(l10n.questionBankExportFailed('$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _bulkBusy = false);
      }
    }
  }

  /// 批量删除：逐题清配图 + 删题；单题失败不中断整批，最后汇总失败数。
  Future<void> _bulkDelete() async {
    if (_bulkBusy || _selected.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final snapshot = ref
        .read(questionLibrarySnapshotProvider(_filter.isNotEmpty))
        .valueOrNull;
    final titles = <String>[
      for (final entry in snapshot?.entries ?? const <QuestionLibraryEntry>[])
        if (_selected.contains(entry.questionId)) entry.displayTitle,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.questionBankDeleteTitle(_selected.length)),
        content: Text(
          l10n.questionBankDeleteBody(questionBankDeletePreview(titles)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.questionBankDeleteSelected),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final ids = _selected.toList();
    setState(() => _bulkBusy = true);
    final mediaStore = ref.read(questionMediaStoreProvider);
    final repository = ref.read(questionRepositoryProvider);
    var failed = 0;
    for (final questionId in ids) {
      try {
        try {
          await mediaStore.deleteForQuestion(questionId);
        } catch (error) {
          // 配图清不掉也继续删题：附件残留不影响题目本身。
          debugPrint('deleteForQuestion($questionId) failed: $error');
        }
        await repository.deleteQuestion(questionId);
      } catch (error) {
        failed++;
        debugPrint('deleteQuestion($questionId) failed: $error');
      }
    }
    _invalidateLibrary();
    if (!mounted) {
      return;
    }
    final done = ids.length - failed;
    setState(() {
      _bulkBusy = false;
      _selecting = false;
      _selected.clear();
    });
    _showSnack(
      failed <= 0
          ? l10n.questionBankDeleteDone(done)
          : '${l10n.questionBankDeleteDone(done)} · ${l10n.questionBankDeleteFailed(failed)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filterActive = _filter.isNotEmpty;
    final overviewAsync =
        ref.watch(questionLibrarySnapshotProvider(filterActive));
    final snapshot = overviewAsync.valueOrNull ?? _lastSnapshot;
    if (overviewAsync.valueOrNull != null) {
      _lastSnapshot = overviewAsync.valueOrNull;
    }
    final visibleEntries = snapshot == null
        ? const <QuestionLibraryEntry>[]
        : _visibleEntries(snapshot);

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                key: questionBankExitSelectionKey,
                tooltip: l10n.questionBankClearSelection,
                onPressed: _bulkBusy ? null : _exitSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _selecting
              ? l10n.questionBankSelectedCount(_selected.length)
              : l10n.navQuestions,
        ),
        actions: _selecting
            ? <Widget>[
                IconButton(
                  key: questionBankSelectAllKey,
                  tooltip: l10n.questionBankSelectAll,
                  onPressed: _bulkBusy || snapshot == null
                      ? null
                      : () => _selectAll(snapshot),
                  icon: const Icon(Icons.done_all),
                ),
                IconButton(
                  key: questionBankClearSelectionKey,
                  tooltip: l10n.questionBankClearSelection,
                  onPressed:
                      _bulkBusy || _selected.isEmpty ? null : _clearSelection,
                  icon: const Icon(Icons.deselect),
                ),
              ]
            : <Widget>[
                if (snapshot != null && snapshot.entries.isNotEmpty)
                  IconButton(
                    key: questionBankSelectKey,
                    tooltip: l10n.questionBankSelect,
                    onPressed: _enterSelection,
                    icon: const Icon(Icons.checklist),
                  ),
                if (visibleEntries.any((entry) => !entry.hasTitle))
                  IconButton(
                    key: questionBankAutoNameKey,
                    tooltip: l10n.questionBankAutoNameTooltip,
                    onPressed: _autoNaming ? null : _autoNameMissing,
                    icon: _autoNaming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                  ),
                IconButton(
                  tooltip: l10n.questionBankRefresh,
                  icon: const Icon(Icons.refresh),
                  onPressed: _invalidateLibrary,
                ),
              ],
      ),
      body: snapshot != null
          ? _buildBody(snapshot)
          : overviewAsync.hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.questionBankFailed('${overviewAsync.error}'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: _selecting ? _buildSelectionBar(l10n) : null,
    );
  }

  /// 多选态底部动作条：打标签 / 导出选中 / 删除；批量操作进行中禁用并显示进度条。
  Widget _buildSelectionBar(AppLocalizations l10n) {
    return BottomAppBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_bulkBusy) const LinearProgressIndicator(minHeight: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton.icon(
                  key: questionBankTagSelectedKey,
                  onPressed: _bulkBusy || _selected.isEmpty ? null : _bulkTag,
                  icon: const Icon(Icons.label_outline),
                  label: Text(l10n.questionBankTagSelected),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  key: questionBankExportSelectedKey,
                  onPressed:
                      _bulkBusy || _selected.isEmpty ? null : _bulkExport,
                  icon: const Icon(Icons.save_alt),
                  label: Text(l10n.questionBankExportSelected),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  key: questionBankDeleteSelectedKey,
                  onPressed:
                      _bulkBusy || _selected.isEmpty ? null : _bulkDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.questionBankDeleteSelected),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(QuestionLibrarySnapshot snapshot) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subjects = snapshot.subjectKeys;
    final shown = _visibleEntries(snapshot);
    final existingTitles = <String>[
      for (final entry in snapshot.entries)
        if (entry.hasTitle) entry.title!.trim(),
    ];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _EntryRow(
                    l10n: l10n,
                    onIntake: () => _open(const QuestionIntakePage()),
                    onPaper: () => _open(const QuestionPaperPage()),
                    onHandwriting: () => _open(const HandwritingQueuePage()),
                    onMaterial: () => _open(const MaterialIntakePage()),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.isEmpty) ...[
                    Text(
                      l10n.questionBankEmpty,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.questionBankEmptyHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    QuestionLibraryFilterBar(
                      searchController: _search,
                      selectedTagPaths: _selectedTagPaths,
                      shownCount: shown.length,
                      totalCount: snapshot.entries.length,
                      filterActive: _filter.isNotEmpty,
                      onlyWrong: _filter.onlyWrong,
                      onToggleWrongOnly: () => _applyFilter(
                        _filter.copyWith(onlyWrong: !_filter.onlyWrong),
                      ),
                      onSearchChanged: (value) =>
                          _applyFilter(_filter.copyWith(text: value)),
                      onClearSearch: _clearSearchText,
                      onOpenTagFilter: () => _openTagFilter(snapshot),
                      onRemoveTagPath: _removeTagPath,
                      onClear: _clearFilter,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.questionBankSummary(
                              snapshot.totalCount,
                              subjects.length,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (snapshot.truncated)
                          Text(
                            l10n.questionBankTruncated(snapshot.entries.length),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                      ],
                    ),
                    if (subjects.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.questionBankAllSubjects),
                            selected: _filter.subjectKey.isEmpty,
                            onSelected: (_) =>
                                _applyFilter(_filter.copyWith(subjectKey: '')),
                          ),
                          for (final key in subjects)
                            ChoiceChip(
                              label: Text(subjectLabelOf(l10n, key)),
                              selected: _filter.subjectKey == key,
                              onSelected: (_) => _applyFilter(
                                _filter.copyWith(subjectKey: key),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          if (shown.isEmpty && !snapshot.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.filter_alt_off_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.questionBankFilterNoMatch,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: questionBankNoMatchClearFilterKey,
                        onPressed: _clearFilter,
                        child: Text(l10n.questionBankFilterClear),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: shown.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = shown[index];
                  return _QuestionRow(
                    entry: entry,
                    selectionMode: _selecting,
                    selected: _selected.contains(entry.questionId),
                    onToggle: () => _toggleSelection(entry.questionId),
                    onEnterSelection: () =>
                        _enterSelectionWith(entry.questionId),
                    onOpen: () => _open(
                      QuestionDetailPage(questionId: entry.questionId),
                    ),
                    onRename: () => _rename(entry, existingTitles),
                    onAutoName: () => _autoNameEntry(entry, existingTitles),
                    onClearAttempts: () => _clearAttempts(entry),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 四个"往题库里加东西"的入口。放最上面：这一页的主要动作是加题，不是浏览。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.l10n,
    required this.onIntake,
    required this.onPaper,
    required this.onHandwriting,
    required this.onMaterial,
  });

  final AppLocalizations l10n;
  final VoidCallback onIntake;
  final VoidCallback onPaper;
  final VoidCallback onHandwriting;
  final VoidCallback onMaterial;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: onIntake,
          icon: const Icon(Icons.edit_note_outlined),
          label: Text(l10n.questionIntakeTitle),
        ),
        OutlinedButton.icon(
          onPressed: onPaper,
          icon: const Icon(Icons.playlist_add_check),
          label: Text(l10n.questionPaperTitle),
        ),
        OutlinedButton.icon(
          onPressed: onHandwriting,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.handwritingQueueTitle),
        ),
        OutlinedButton.icon(
          onPressed: onMaterial,
          icon: const Icon(Icons.library_add_outlined),
          label: Text(l10n.materialIntakeTitle),
        ),
      ],
    );
  }
}

/// 行尾 ⋮ 菜单的动作。
///
/// 「清除记录」只在自测答错过的行（[QuestionLibraryEntry.hasWrongAttempt]）出现，
/// 其它行仍是原来的三项。
enum _QuestionRowAction { rename, autoName, copySerial, clearAttempts }

/// 一道题：封面大图 + 题名/题干摘要 + 题号/学科/标签 + 体检徽章 + ⋮ 菜单。
///
/// 不套 Card：整行铺在页面背景上，行间只用一条细分隔线（用户反馈「很多文字
/// 不需要放在一个卡片底座上」）。点整行进详情页。
class _QuestionRow extends ConsumerWidget {
  const _QuestionRow({
    required this.entry,
    required this.selectionMode,
    required this.selected,
    required this.onToggle,
    required this.onEnterSelection,
    required this.onOpen,
    required this.onRename,
    required this.onAutoName,
    required this.onClearAttempts,
  });

  final QuestionLibraryEntry entry;

  /// 多选态：点整行 = 勾选/取消；行首长按也能进入多选。
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEnterSelection;

  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onAutoName;

  /// 清除这道题的自测作答记录（菜单项只在此题答错过时才出现）。
  final VoidCallback onClearAttempts;

  void _copySerial(BuildContext context, AppLocalizations l10n) {
    final serialNo = entry.serialNo;
    if (serialNo == null) {
      return;
    }
    final label = formatQuestionSerial(serialNo);
    unawaited(Clipboard.setData(ClipboardData(text: label)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.questionSerialCopied(label))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = entry.coverImage;
    final hasTitle = entry.hasTitle;
    final leaves = questionBankTagLeafNames(entry.tagPaths);

    return InkWell(
      key: ValueKey(questionBankRowKeyFor(entry.questionId)),
      onTap: selectionMode ? onToggle : onOpen,
      onLongPress: selectionMode ? null : onEnterSelection,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (selectionMode)
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
              ),
            if (cover != null) ...[
              _QuestionCover(image: cover),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.displayTitle,
                    maxLines: hasTitle ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: hasTitle
                        ? theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      QuestionSerialBadge(
                        serialNo: entry.serialNo,
                        copyable: false,
                        dense: true,
                      ),
                      if (entry.hasWrongAttempt)
                        _WrongPill(
                          questionId: entry.questionId,
                          count: entry.wrongAttemptCount,
                        ),
                      Text(
                        subjectLabelOf(l10n, entry.subjectKey),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      // 整卡截图题：只在标题没回落成「整题截图 · N 处公式/图」
                      // 时补一个小标签，避免同一行出现两个「整题截图」。
                      if (entry.isSnapshotStem &&
                          ((entry.snapshotExcerpt ?? '').trim().isNotEmpty ||
                              hasTitle))
                        Text(
                          l10n.questionBankSnapshotBadge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      for (final leaf in leaves.take(3)) _TagPill(label: leaf),
                      if (leaves.length > 3)
                        _TagPill(label: '+${leaves.length - 3}'),
                    ],
                  ),
                ],
              ),
            ),
            QuestionAuditBadge(questionId: entry.questionId),
            PopupMenuButton<_QuestionRowAction>(
              key: ValueKey(questionBankRowMenuKeyFor(entry.questionId)),
              tooltip: l10n.questionBankRowMenuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _QuestionRowAction.rename:
                    onRename();
                  case _QuestionRowAction.autoName:
                    onAutoName();
                  case _QuestionRowAction.copySerial:
                    _copySerial(context, l10n);
                  case _QuestionRowAction.clearAttempts:
                    onClearAttempts();
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<_QuestionRowAction>>[
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.rename,
                  child: Text(l10n.questionTitleRename),
                ),
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.autoName,
                  child: Text(l10n.questionBankAutoNameMenu),
                ),
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.copySerial,
                  enabled: entry.serialNo != null,
                  child: Text(l10n.questionBankCopySerial),
                ),
                // 只有答错过的题才有记录可清；没错过的行菜单保持原三项。
                if (entry.hasWrongAttempt)
                  PopupMenuItem<_QuestionRowAction>(
                    key: ValueKey(
                      questionBankClearAttemptsKeyFor(entry.questionId),
                    ),
                    value: _QuestionRowAction.clearAttempts,
                    child: Text(l10n.questionDetailAttemptClearAction),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 行首封面图：128×96 圆角 12；字节还没读出来时给同尺寸占位，不跳行。
class _QuestionCover extends ConsumerWidget {
  const _QuestionCover({required this.image});

  final QuestionLibraryImage image;

  static const int width = 128;
  static const int height = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes =
        ref.watch(questionImageBytesProvider(image.relPath)).valueOrNull;
    final decode = thumbnailDecodeSpec(
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );

    final Widget placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: bytes == null
            ? placeholder
            : Image.memory(
                bytes,
                width: width.toDouble(),
                height: height.toDouble(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: decode.isEmpty ? null : decode.cacheWidth,
                cacheHeight: decode.isEmpty ? null : decode.cacheHeight,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

/// 行内小标签 chip（标签叶子名 / 「+N」）。
class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 行内「错 N 次」徽标：自测答错过至少一次的题才有（错题本筛选的依据）。
///
/// 用错误色系与标签 pill 区分开；key 带题目 id 方便测试逐行断言。
class _WrongPill extends StatelessWidget {
  const _WrongPill({required this.questionId, required this.count});

  final String questionId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      key: ValueKey(questionBankWrongBadgeKeyFor(questionId)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        l10n.questionBankWrongCount(count),
        style: theme.textTheme.labelSmall?.copyWith(color: colors.error),
      ),
    );
  }
}

/// 导出确认里的文件大小（"3 B" / "1.5 KB" / "2.0 MB"）。
String _questionBankSizeText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(1)} KB';
  }
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

/// 导出文件名里的时间戳（`furnace-20261021T0430-selected.tqb`）。
String _questionBankTimestamp() => DateTime.now()
    .toIso8601String()
    .substring(0, 16)
    .replaceAll(':', '')
    .replaceAll('-', '');
