/// 题目详情页的「去组卷网搜这道题」入口。
///
/// 职责边界：
///
///  * 检索词是**纯逻辑**算出来的（[zujuanSearchCandidates]），这里只做展示与
///    剪贴板动作，不联网、不解析搜索结果、不依赖站点 cookie；
///  * 组卷网按站点当前学科（bankId cookie）过滤，UI 替用户切不了学科，所以每次
///    都显式提示「先在组卷网切到对应学科」——这是标准侧实测过的事故（学科不对
///    会静默 0 条）；
///  * 打开搜索页不引入 url_launcher：复制链接 + SnackBar 让用户去浏览器粘贴，
///    这是仓库「不新增依赖」约束下的既定做法。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/zujuan/zujuan_link.dart';
import '../../../l10n/app_localizations.dart';

/// 入口按钮的 key（widget test 用它定位，也方便将来埋点）。
const Key questionZujuanSearchButtonKey = Key('question-zujuan-search');

/// 底部表最多摆几条候选：纯逻辑最多给 8 条，界面只显示 5 条，避免长列表。
const int questionZujuanVisibleCandidateLimit = 5;

/// 从题干算候选检索词。
///
/// 纯同步计算（本地字符串处理），不做异步 provider：题干在页面 build 时已经从
/// 库里读出来了，再套一个 loading 态只会让入口闪一下。题干空白时返回空列表，
/// 入口因此整个不渲染。
final questionZujuanCandidatesProvider =
    Provider.family<List<ZujuanSearchCandidate>, String>((ref, stem) {
  final trimmed = stem.trim();
  if (trimmed.isEmpty) {
    return const <ZujuanSearchCandidate>[];
  }
  return zujuanSearchCandidates(trimmed);
});

/// 题面下方的「去组卷网搜这道题」按钮；候选为空时整个 widget 不占版面。
class QuestionZujuanSearchButton extends ConsumerWidget {
  const QuestionZujuanSearchButton({super.key, required this.stem});

  /// 当前题的题干（页面从 QuestionDetail 里取；本 widget 不读库）。
  final String stem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final candidates = ref.watch(questionZujuanCandidatesProvider(stem));
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = candidates
        .take(questionZujuanVisibleCandidateLimit)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: questionZujuanSearchButtonKey,
          onPressed: () => showQuestionZujuanSheet(
            context,
            l10n: l10n,
            candidates: visible,
          ),
          icon: const Icon(Icons.travel_explore, size: 18),
          label: Text(l10n.questionZujuanSearch),
        ),
      ),
    );
  }
}

/// 弹出组卷网检索词候选表。公开函数便于复用与测试。
Future<void> showQuestionZujuanSheet(
  BuildContext context, {
  required AppLocalizations l10n,
  required List<ZujuanSearchCandidate> candidates,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _QuestionZujuanSheet(
      l10n: l10n,
      candidates: candidates,
    ),
  );
}

class _QuestionZujuanSheet extends StatelessWidget {
  const _QuestionZujuanSheet({required this.l10n, required this.candidates});

  final AppLocalizations l10n;
  final List<ZujuanSearchCandidate> candidates;

  /// 复制文本 → 关掉底部表 → SnackBar 说明复制了什么。
  ///
  /// 先关表再提示：SnackBar 挂在页面 Scaffold 上，表还开着时会被挡在下面。
  Future<void> _copy(
    BuildContext context, {
    required String text,
    required String message,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          Text(l10n.questionZujuanSearch, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.questionZujuanBankHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (candidates.isEmpty)
            Text(l10n.questionZujuanNoCandidates)
          else
            for (var index = 0; index < candidates.length; index++)
              _QuestionZujuanCandidateRow(
                index: index,
                candidate: candidates[index],
                l10n: l10n,
                onCopyKeyword: () => _copy(
                  context,
                  text: candidates[index].keyword,
                  message: l10n.questionZujuanCopied(
                    candidates[index].keyword,
                  ),
                ),
                onOpenUrl: () => _copy(
                  context,
                  text: candidates[index].url,
                  message: l10n.questionZujuanUrlCopied,
                ),
              ),
        ],
      ),
    );
  }
}

class _QuestionZujuanCandidateRow extends StatelessWidget {
  const _QuestionZujuanCandidateRow({
    required this.index,
    required this.candidate,
    required this.l10n,
    required this.onCopyKeyword,
    required this.onOpenUrl,
  });

  final int index;
  final ZujuanSearchCandidate candidate;
  final AppLocalizations l10n;
  final VoidCallback onCopyKeyword;
  final VoidCallback onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(candidate.keyword, style: theme.textTheme.bodyLarge),
            Row(
              children: [
                TextButton.icon(
                  key: Key('question-zujuan-copy-$index'),
                  onPressed: onCopyKeyword,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: Text(l10n.questionZujuanCopyKeyword),
                ),
                TextButton.icon(
                  key: Key('question-zujuan-open-$index'),
                  onPressed: onOpenUrl,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(l10n.questionZujuanOpenUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
