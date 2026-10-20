/// 确认前预检：把「手写整理提案」翻译成「确认后会发生什么」。
///
/// 纯 Dart：不 import Flutter / drift / `dart:io`，不写库、不调模型；只读
/// [HandwritingProposalSet] 与两棵已有节点集合（已有标签完整路径、已有知识点标题），
/// 返回可直接渲染的纯数据。
///
/// 与 `handwriting_proposals.dart` 的分工：那边负责「解析模型回复 / 从库里读回」
/// 并保证结构严格；这边只负责「确认前让用户看见会写到哪里、哪些新建/复用、
/// 缺哪些字段、哪条不能确认」。字段键沿用 JSON 契约：
/// `parent_path` / `content` / `tag_path` / `stem` / `answer` / `solution`。
///
/// 判定口径（确定性，无随机、无 `DateTime.now`）：
/// * 有 blocker → [HandwritingPreviewVerdict.blocked]；
/// * 否则有 warning → [HandwritingPreviewVerdict.needsReview]；
/// * 否则 → [HandwritingPreviewVerdict.ready]。
///
/// 本文件**不改**提案本身、不改传入的集合；同一输入永远得到同一输出。
library;

import 'package:furnace/domain/services/intake/handwriting_proposals.dart';

/// 一条提案在确认前的预检结论。
enum HandwritingPreviewVerdict {
  ready('ready', '可以确认'),
  needsReview('needs_review', '确认前看一眼'),
  blocked('blocked', '不能确认');

  const HandwritingPreviewVerdict(this.storageKey, this.labelZh);

  /// 给日志/测试用的稳定键（不进中文界面）。
  final String storageKey;

  /// 界面上的中文名。
  final String labelZh;
}

/// 单条提案的预检结果。
class HandwritingProposalPreview {
  const HandwritingProposalPreview({
    required this.proposalId,
    required this.kind,
    required this.verdict,
    this.targetPath,
    this.willCreate = false,
    this.willReuse = false,
    this.previewLines = const <String>[],
    this.warnings = const <String>[],
    this.blockers = const <String>[],
    this.duplicateOfProposalId,
  });

  /// 对应 [HandwritingProposal.id]。
  final String proposalId;

  final HandwritingProposalKind kind;

  final HandwritingPreviewVerdict verdict;

  /// 会写到哪里（标签完整路径 / 知识点或题目要挂的标签路径）；没有则是 `null`。
  final String? targetPath;

  /// 确认后会新建目标节点。
  final bool willCreate;

  /// 确认后会复用已有节点（标签复用已有路径；知识点/闪存卡复用已有知识点）。
  final bool willReuse;

  /// 卡片上直接显示的行，2–5 条，全中文。
  final List<String> previewLines;

  /// 可以确认、但建议先看一眼的问题。
  final List<String> warnings;

  /// 不解决就不能确认的原因。
  final List<String> blockers;

  /// 同一批里重复出现时，指向最先出现的那条提案 id。
  final String? duplicateOfProposalId;

  bool get isBlocked => verdict == HandwritingPreviewVerdict.blocked;

  Map<String, Object?> toJson() => {
        'proposal_id': proposalId,
        'kind': kind.storageKey,
        'verdict': verdict.storageKey,
        'target_path': targetPath,
        'will_create': willCreate,
        'will_reuse': willReuse,
        'preview_lines': previewLines,
        'warnings': warnings,
        'blockers': blockers,
        'duplicate_of_proposal_id': duplicateOfProposalId,
      };

  @override
  String toString() =>
      'HandwritingProposalPreview(${kind.storageKey}, $proposalId, '
      '${verdict.storageKey})';
}

/// 整批提案的预检结果。
class HandwritingIntakePreview {
  HandwritingIntakePreview({
    required this.sourceRef,
    required List<HandwritingProposalPreview> previews,
  })  : previews = List<HandwritingProposalPreview>.unmodifiable(previews),
        readyCount = previews
            .where(
                (preview) => preview.verdict == HandwritingPreviewVerdict.ready)
            .length,
        needsReviewCount = previews
            .where(
              (preview) =>
                  preview.verdict == HandwritingPreviewVerdict.needsReview,
            )
            .length,
        blockedCount = previews
            .where(
              (preview) => preview.verdict == HandwritingPreviewVerdict.blocked,
            )
            .length;

  /// 来源照片路径（`handwriting_intake/...`），原样保留。
  final String sourceRef;

  /// 与输入提案同序。
  final List<HandwritingProposalPreview> previews;

  final int readyCount;
  final int needsReviewCount;
  final int blockedCount;

  /// 有一条不能确认，整批就不能应用。
  bool get hasBlocked => blockedCount > 0;

  /// 没有 blocked 时才可以整批确认。
  bool get canApplyAll => !hasBlocked;

  Map<String, Object?> toJson() => {
        'source_ref': sourceRef,
        'previews': [for (final preview in previews) preview.toJson()],
        'ready_count': readyCount,
        'needs_review_count': needsReviewCount,
        'blocked_count': blockedCount,
        'has_blocked': hasBlocked,
        'can_apply_all': canApplyAll,
      };
}

/// 预检整批提案。
///
/// [existingTagPaths] 是标签树里已有节点的**完整路径**（如 `文化课/物理/力学`）；
/// [existingKnowledgePointTitles] 是已有知识点标题。两个集合只读，不会被修改。
///
/// 永不抛异常：结构合法性由 `handwriting_proposals.dart` 的解析层负责，
/// 这里只判断「确认后会发生什么」。
HandwritingIntakePreview previewHandwritingProposals(
  HandwritingProposalSet set, {
  required Set<String> existingTagPaths,
  required Set<String> existingKnowledgePointTitles,
}) {
  final tags = _normalizePathSet(existingTagPaths);
  final knowledgePoints = _normalizeTitleSet(existingKnowledgePointTitles);
  final firstSeen =
      <HandwritingProposalKind, Map<String, ({String id, int index})>>{};
  final previews = <HandwritingProposalPreview>[];
  for (var index = 0; index < set.proposals.length; index++) {
    final proposal = set.proposals[index];
    final draft = _PreviewDraft();
    switch (proposal.kind) {
      case HandwritingProposalKind.tag:
        _previewTag(proposal, existingTags: tags, draft: draft);
      case HandwritingProposalKind.knowledgePoint:
        _previewKnowledgePoint(
          proposal,
          existingTags: tags,
          existingKnowledgePointTitles: knowledgePoints,
          draft: draft,
        );
      case HandwritingProposalKind.flashcard:
        _previewFlashcard(
          proposal,
          existingTags: tags,
          existingKnowledgePointTitles: knowledgePoints,
          draft: draft,
        );
      case HandwritingProposalKind.question:
        _previewQuestion(proposal, existingTags: tags, draft: draft);
    }

    final byTitle = firstSeen.putIfAbsent(
      proposal.kind,
      () => <String, ({String id, int index})>{},
    );
    final title = proposal.titleZh.trim();
    final first = byTitle[title];
    String? duplicateOfProposalId;
    if (first == null) {
      byTitle[title] = (id: proposal.id, index: index);
    } else {
      duplicateOfProposalId = first.id;
      draft.warnings.add(
        '本批里重复出现：与第 ${first.index + 1} 条「$title」完全相同',
      );
    }

    final verdict = draft.blockers.isNotEmpty
        ? HandwritingPreviewVerdict.blocked
        : draft.warnings.isNotEmpty
            ? HandwritingPreviewVerdict.needsReview
            : HandwritingPreviewVerdict.ready;
    previews.add(
      HandwritingProposalPreview(
        proposalId: proposal.id,
        kind: proposal.kind,
        verdict: verdict,
        targetPath: draft.targetPath,
        willCreate: draft.willCreate,
        willReuse: draft.willReuse,
        previewLines: List<String>.unmodifiable(draft.lines),
        warnings: List<String>.unmodifiable(draft.warnings),
        blockers: List<String>.unmodifiable(draft.blockers),
        duplicateOfProposalId: duplicateOfProposalId,
      ),
    );
  }
  return HandwritingIntakePreview(
    sourceRef: set.sourceRef,
    previews: previews,
  );
}

/// 预检过程中攒下的半成品。
class _PreviewDraft {
  String? targetPath;
  bool willCreate = false;
  bool willReuse = false;
  final List<String> lines = <String>[];
  final List<String> warnings = <String>[];
  final List<String> blockers = <String>[];
}

void _previewTag(
  HandwritingProposal proposal, {
  required Set<String> existingTags,
  required _PreviewDraft draft,
}) {
  final title = proposal.titleZh.trim();
  final parentPath = _cleanPath(proposal.fields['parent_path'] ?? '');
  final fullPath =
      parentPath.isEmpty || title.isEmpty ? null : '$parentPath/$title';
  draft.targetPath = fullPath;

  if (title.isEmpty) {
    draft.blockers.add('标签名为空，无法写进标签树');
    draft.lines.add('标签暂不能确认：标题为空');
    draft.lines.add('目标路径：未确定');
    return;
  }
  if (parentPath.isEmpty) {
    draft.blockers.add('标签树里没有父层路径（parent_path 为空），先确定挂到哪一层');
    draft.lines.add('标签「$title」暂不能确认：还没挂到任何一层');
    draft.lines.add('目标路径：未确定');
    return;
  }
  if (existingTags.contains(fullPath)) {
    draft.willReuse = true;
    draft.lines.add('会复用已有标签「$title」');
    draft.lines.add('目标路径：$fullPath');
    return;
  }
  if (!existingTags.contains(parentPath)) {
    draft.blockers.add('标签树里没有「$parentPath」这一层，先建父层或改挂别处');
    draft.lines.add('标签「$title」暂不能确认：父层不在标签树里');
    draft.lines.add('目标路径：$fullPath');
    return;
  }
  draft.willCreate = true;
  draft.lines.add('会新建标签「$title」');
  draft.lines.add('目标路径：$fullPath');
}

void _previewKnowledgePoint(
  HandwritingProposal proposal, {
  required Set<String> existingTags,
  required Set<String> existingKnowledgePointTitles,
  required _PreviewDraft draft,
}) {
  final title = proposal.titleZh.trim();
  final content = (proposal.fields['content'] ?? '').trim();
  final tagPath = _cleanPath(proposal.fields['tag_path'] ?? '');
  draft.targetPath = tagPath.isEmpty ? null : tagPath;

  if (title.isEmpty) {
    draft.blockers.add('知识点标题为空，无法建点');
    draft.lines.add('知识点暂不能确认：标题为空');
    draft.lines.add('目标路径：未确定');
    return;
  }
  final exists = existingKnowledgePointTitles.contains(title);
  draft.willReuse = exists;
  draft.willCreate = !exists;
  draft.lines.add(
    exists ? '会复用已有知识点「$title」' : '会新建知识点「$title」',
  );
  draft.lines.add(tagPath.isEmpty ? '目标路径：不挂标签' : '目标路径：$tagPath');
  if (content.isEmpty) {
    draft.warnings.add('知识点正文为空：确认后是一个没有内容的知识点');
  }
  if (tagPath.isNotEmpty && !existingTags.contains(tagPath)) {
    draft.warnings.add('标签树里没有「$tagPath」：知识点照建，但先不挂到标签');
  }
}

void _previewFlashcard(
  HandwritingProposal proposal, {
  required Set<String> existingTags,
  required Set<String> existingKnowledgePointTitles,
  required _PreviewDraft draft,
}) {
  final title = proposal.titleZh.trim();
  final tagPath = _cleanPath(proposal.fields['tag_path'] ?? '');
  draft.targetPath = tagPath.isEmpty ? null : tagPath;

  if (proposal.cards.isEmpty) {
    draft.blockers.add('闪存卡没有卡片，无法保存');
    draft.lines.add(
      title.isEmpty ? '闪存卡暂不能确认：没有卡片' : '闪存卡「$title」暂不能确认：没有卡片',
    );
    draft.lines.add('卡片数量：0 张');
    return;
  }

  final incomplete = proposal.cards
      .where(
        (card) => card.question.trim().isEmpty || card.answer.trim().isEmpty,
      )
      .length;
  final reusesKnowledgePoint = existingKnowledgePointTitles.contains(title);
  draft.willCreate = true;
  draft.willReuse = reusesKnowledgePoint;
  draft.lines.add(
    title.isEmpty ? '会新建闪存卡（标题为空）' : '会新建闪存卡「$title」',
  );
  final types = <String>[];
  for (final card in proposal.cards) {
    if (!types.contains(card.type)) {
      types.add(card.type);
    }
  }
  draft.lines.add('卡片 ${proposal.cards.length} 张（题型：${types.join('、')}）');
  if (reusesKnowledgePoint) {
    draft.lines.add('会复用已有知识点「$title」');
  }
  if (incomplete > 0) {
    draft.warnings.add('$incomplete 张卡片缺题干或答案：确认前先补全');
  }
  if (tagPath.isNotEmpty && !existingTags.contains(tagPath)) {
    draft.warnings.add('标签树里没有「$tagPath」：闪存卡照建，但先不挂到标签');
  }
}

void _previewQuestion(
  HandwritingProposal proposal, {
  required Set<String> existingTags,
  required _PreviewDraft draft,
}) {
  final title = proposal.titleZh.trim();
  final stem = (proposal.fields['stem'] ?? '').trim();
  final answer = (proposal.fields['answer'] ?? '').trim();
  final solution = (proposal.fields['solution'] ?? '').trim();
  final tagPath = _cleanPath(proposal.fields['tag_path'] ?? '');
  draft.targetPath = tagPath.isEmpty ? null : tagPath;

  if (stem.isEmpty) {
    draft.blockers.add('题面为空，不能确认');
    draft.lines.add('题目暂不能确认：题面为空');
    draft.lines.add(
      proposal.options.isEmpty
          ? '无选项（纯文字题）'
          : '选项 ${proposal.options.length} 个、答案 ${answer.isEmpty ? '（照片里没有）' : _shorten(answer)}',
    );
    return;
  }

  draft.willCreate = true;
  draft.lines.add(
    title.isEmpty ? '会新建题目（标题为空）' : '会新建题目「$title」',
  );
  if (proposal.options.isEmpty) {
    draft.lines.add('无选项（纯文字题）');
    draft.lines.add(answer.isEmpty ? '答案：（照片里没有答案）' : '答案：${_shorten(answer)}');
  } else {
    draft.lines.add(
      '选项 ${proposal.options.length} 个、答案 ${answer.isEmpty ? '（照片里没有）' : _shorten(answer)}',
    );
  }
  if (tagPath.isNotEmpty) {
    draft.lines.add('目标路径：$tagPath');
  }
  if (answer.isEmpty) {
    draft.warnings.add('照片里没有答案：确认前补上，或确认后标记待补');
  }
  if (solution.isEmpty) {
    draft.warnings.add('照片里没有解析：确认前补上，或确认后标记待补');
  }
  if (tagPath.isNotEmpty && !existingTags.contains(tagPath)) {
    draft.warnings.add('标签树里没有「$tagPath」：题目照建，但先不挂标签');
  }
}

String _cleanPath(String raw) {
  var clean = raw.trim();
  while (clean.startsWith('/')) {
    clean = clean.substring(1);
  }
  while (clean.endsWith('/')) {
    clean = clean.substring(0, clean.length - 1);
  }
  return clean;
}

Set<String> _normalizePathSet(Set<String> raw) {
  final normalized = <String>{};
  for (final value in raw) {
    final clean = _cleanPath(value);
    if (clean.isNotEmpty) {
      normalized.add(clean);
    }
  }
  return normalized;
}

Set<String> _normalizeTitleSet(Set<String> raw) {
  final normalized = <String>{};
  for (final value in raw) {
    final clean = value.trim();
    if (clean.isNotEmpty) {
      normalized.add(clean);
    }
  }
  return normalized;
}

String _shorten(String value, {int maxLength = 24}) {
  final clean = value.trim();
  if (clean.length <= maxLength) {
    return clean;
  }
  return '${clean.substring(0, maxLength)}…';
}
