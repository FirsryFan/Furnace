/// 题库（顶部目的地）。
///
/// 用户反馈（m29290）"看不到题库总览、也不知道新建题目在哪"：收题、组卷、拍照
/// 整理、材料入库的入口此前全压在「设置」里，而题库本身（有多少题、都是哪些题）
/// **没有任何页面**。这一页把两件事合起来：
///
/// * 上面四个按钮 = 往题库里加东西的全部入口（设置页只留一个指向这里的入口）；
/// * 下面的列表 = 题库总览（按学科筛，点一行进题目详情）。
///
/// 数据走组卷同一个读表路径（`paperCorpusProvider` + `questionStemsProvider`），
/// 不新增第二套"题库里有什么"的口径；页面只读，不写库。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/material_intake_page.dart';
import '../application/paper_plan_provider.dart';
import 'handwriting_queue_page.dart';
import 'question_audit_view.dart';
import 'question_detail_page.dart';
import 'question_intake_page.dart';
import 'question_media_view.dart';
import 'question_paper_page.dart' show QuestionPaperPage, subjectLabelOf;
import 'question_vocab_labels.dart';

/// 题库总览页。
class QuestionBankPage extends ConsumerStatefulWidget {
  const QuestionBankPage({super.key});

  @override
  ConsumerState<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends ConsumerState<QuestionBankPage> {
  /// 空串 = 全部学科。学科键是稳定 snake_case（`CapabilityAction.subjectKeys`），
  /// 筛选比较只用键，显示名走 `subjectLabelOf`。
  String _subjectKey = '';

  void _open(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final corpusAsync = ref.watch(paperCorpusProvider);
    final stems = ref.watch(questionStemsProvider).valueOrNull ??
        const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navQuestions),
        actions: [
          IconButton(
            tooltip: l10n.questionBankRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(paperCorpusProvider);
              ref.invalidate(questionStemsProvider);
            },
          ),
        ],
      ),
      body: corpusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.questionBankFailed('$error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (corpus) {
          final candidates = corpus.candidates;
          final subjects = corpus.subjectKeys;
          final shown = _subjectKey.isEmpty
              ? candidates
              : candidates
                  .where((candidate) => candidate.subjectKey == _subjectKey)
                  .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(paperCorpusProvider);
              ref.invalidate(questionStemsProvider);
              await ref.read(paperCorpusProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _EntryRow(
                  l10n: l10n,
                  onIntake: () => _open(const QuestionIntakePage()),
                  onPaper: () => _open(const QuestionPaperPage()),
                  onHandwriting: () => _open(const HandwritingQueuePage()),
                  onMaterial: () => _open(const MaterialIntakePage()),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidates.isEmpty
                              ? l10n.questionBankEmpty
                              : l10n.questionBankSummary(
                                  candidates.length,
                                  subjects.length,
                                ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          candidates.isEmpty
                              ? l10n.questionBankEmptyHint
                              : l10n.questionBankIntro,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.questionBankAllSubjects),
                        selected: _subjectKey.isEmpty,
                        onSelected: (_) => setState(() => _subjectKey = ''),
                      ),
                      for (final key in subjects)
                        ChoiceChip(
                          label: Text(subjectLabelOf(l10n, key)),
                          selected: _subjectKey == key,
                          onSelected: (_) => setState(() => _subjectKey = key),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (candidates.isNotEmpty && shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.questionBankNoMatch,
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final candidate in shown)
                  _QuestionTile(
                    questionId: candidate.questionId,
                    title: stems[candidate.questionId] ??
                        l10n.questionBankUntitled,
                    subtitle: [
                      subjectLabelOf(l10n, candidate.subjectKey),
                      sourceLevelLabel(l10n, candidate.sourceLevel),
                      if (candidate.matchedKnowledgePointIds.isNotEmpty)
                        l10n.questionBankPointCount(
                          candidate.matchedKnowledgePointIds.length,
                        ),
                    ].join(' · '),
                    onTap: () => _open(
                      QuestionDetailPage(questionId: candidate.questionId),
                    ),
                  ),
              ],
            ),
          );
        },
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
      children: [
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

/// 一道题：题号 + 题干两行 + 学科/来源/知识点数。点进详情页（跑解题链也在那里）。
///
/// 题号（`TR-00042`）按 id 现读：组卷的 `PaperCandidate` 只带匹配用的字段，
/// 没有编号；没编号的老题显示占位而不是空着。
class _QuestionTile extends ConsumerWidget {
  const _QuestionTile({
    required this.questionId,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String questionId;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final serialAsync = ref.watch(questionSerialProvider(questionId));
    final serialLabel = serialAsync.hasValue
        ? questionSerialText(l10n, serialAsync.value)
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            QuestionCoverThumbnail(questionId: questionId),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          serialLabel == null ? subtitle : '$serialLabel · $subtitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            QuestionAuditBadge(questionId: questionId),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
