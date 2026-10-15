/// 拍照整理的「三类待确认产物」服务与队列（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 领域层（`domain/services/intake/handwriting_proposals.dart`）只负责**把模型
/// 回复变成结构化提案**，一句话都不写库。这一层负责另外两件事：
///
///  * [HandwritingProposalService.proposeFor]：读照片 → 问模型 → 得到提案。
///    与解题管道同一条失败哲学：**不抛异常**，成功失败都返回一个结果对象，
///    把「没配模型」「文件不在了」「格式不认识」「回复不合契约」分开告诉用户。
///  * [HandwritingProposalService.applyAll]：用户点确认之后才写库。三类产物的
///    写法都照抄既有规矩：标签挂在**已有**路径下；知识点进 `knowledge_points`；
///    闪存卡建模板后**必须**建卡状态（否则卡片进不了复习队列）。
///
/// 提案本身**只存在内存里**（[HandwritingQueueState]）：用户说"确认前不写库"，
/// 那连"待确认的东西"也不该偷偷落盘。重启丢一次整理是可以接受的——照片还在
/// 磁盘上（[HandwritingIntakeStore]），重新整理一次即可；要持久化提案得加一张
/// 表（记为已知缺口，见 `docs/PROBLEM_INTAKE_DESIGN.md`）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/intake/handwriting_proposals.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart'
    show kKnowledgePointObjectType;
import '../../ai/application/ai_providers.dart';
import '../../ai/domain/model_adapter.dart';
import '../data/handwriting_intake_store.dart';

/// app support 目录。单独成一个 provider，测试才能把它指到临时目录，
/// 不去碰真实的 app 数据目录。
final questionIntakeSupportDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return getApplicationSupportDirectory;
});

/// 拍照/选图落到哪个 store。
///
/// 单一实例：页面写、清单读、整理读，多个实例就是多套"文件在哪儿"的想法。
final handwritingIntakeStoreProvider = Provider<HandwritingIntakeStore>((ref) {
  return HandwritingIntakeStore(
    database: ref.watch(appDatabaseProvider),
    supportDirectory: ref.watch(questionIntakeSupportDirectoryProvider),
  );
});

/// 一次「看照片 → 拿提案」的结果。永远可用，不需要 try/catch。
class HandwritingProposalRun {
  const HandwritingProposalRun({
    required this.sourceRef,
    this.set,
    this.failureReason,
    this.rawReply,
  });

  /// 来源照片的相对路径。
  final String sourceRef;

  /// 解析成功的提案集；失败时为 `null`。
  final HandwritingProposalSet? set;

  /// 失败原因；成功时为 `null`。
  final String? failureReason;

  /// 已经收到的模型原文（排查用）。
  final String? rawReply;

  bool get ok => failureReason == null && set != null;

  factory HandwritingProposalRun.missingFile(String sourceRef) =>
      HandwritingProposalRun(
        sourceRef: sourceRef,
        failureReason: '照片不在了：$sourceRef（可能已经被删除）',
      );

  factory HandwritingProposalRun.unsupportedFormat(
    String sourceRef,
    String fileName,
  ) =>
      HandwritingProposalRun(
        sourceRef: sourceRef,
        failureReason: '认不出这是什么图片格式：$fileName（支持 jpg/png/gif/webp/heic/bmp）',
      );

  factory HandwritingProposalRun.modelFailure(
    String sourceRef,
    String reason, {
    String? rawReply,
  }) =>
      HandwritingProposalRun(
        sourceRef: sourceRef,
        failureReason: reason,
        rawReply: rawReply,
      );

  factory HandwritingProposalRun.parseFailure(
    String sourceRef,
    HandwritingProposalParseException error,
    String rawReply,
  ) =>
      HandwritingProposalRun(
        sourceRef: sourceRef,
        failureReason: '模型回复不符合契约：${error.message}',
        rawReply: rawReply,
      );
}

/// 一条提案写库后的结果。
class HandwritingApplyOutcome {
  const HandwritingApplyOutcome({
    required this.proposalId,
    required this.kind,
    required this.titleZh,
    required this.ok,
    this.targetId,
    this.detailZh = '',
    this.failureReason,
  });

  final String proposalId;
  final HandwritingProposalKind kind;
  final String titleZh;
  final bool ok;

  /// 写进去的东西的 id（标签 id / 知识点 id）。
  final String? targetId;

  /// 人话说明：到底建了什么、哪些部分没做。
  final String detailZh;

  final String? failureReason;

  Map<String, Object?> toJson() => {
        'proposal_id': proposalId,
        'kind': kind.storageKey,
        'title': titleZh,
        'ok': ok,
        'target_id': targetId,
        'detail': detailZh,
        'failure': failureReason,
      };
}

/// 一次确认的汇总。
class HandwritingApplyReport {
  const HandwritingApplyReport({
    required this.sourceRef,
    required this.outcomes,
  });

  final String sourceRef;
  final List<HandwritingApplyOutcome> outcomes;

  int get appliedCount => outcomes.where((outcome) => outcome.ok).length;

  int get failedCount => outcomes.where((outcome) => !outcome.ok).length;

  bool get allOk => outcomes.every((outcome) => outcome.ok);

  List<String> get appliedIds => <String>[
        for (final outcome in outcomes)
          if (outcome.ok) outcome.proposalId,
      ];

  Map<String, Object?> toJson() => {
        'source_ref': sourceRef,
        'applied': appliedCount,
        'failed': failedCount,
        'outcomes': [for (final outcome in outcomes) outcome.toJson()],
      };
}

/// 整理 + 写库。依赖全部注入，测试不需要网络、不需要 Riverpod 容器。
class HandwritingProposalService {
  HandwritingProposalService({
    required HandwritingIntakeStore store,
    required TagRepository tags,
    required AnkiRepository anki,
    required ModelAdapter? adapter,
  })  : _store = store,
        _tags = tags,
        _anki = anki,
        _adapter = adapter;

  final HandwritingIntakeStore _store;
  final TagRepository _tags;
  final AnkiRepository _anki;

  /// 唯一出网点；`null` 表示这台设备上没有可用模型（离线默认）。
  final ModelAdapter? _adapter;

  /// 看一张照片，拿回三类待确认产物。
  Future<HandwritingProposalRun> proposeFor(String relPath) async {
    final bytes = await _store.readBytes(relPath);
    if (bytes == null) {
      return HandwritingProposalRun.missingFile(relPath);
    }

    final fileName = _fileNameOf(relPath);
    final mime = HandwritingIntakeStore.mimeForName(fileName);
    if (mime == null) {
      return HandwritingProposalRun.unsupportedFormat(relPath, fileName);
    }

    final adapter = _adapter;
    if (adapter == null) {
      return HandwritingProposalRun.modelFailure(
        relPath,
        '没有可用的模型适配器（离线或未配置）',
      );
    }

    // 把"现在有什么"写进提示词：模型才知道标签该挂哪儿、哪个知识点已经有了。
    final tags = await _tags.getAllTags();
    final points = await _anki.getKnowledgePoints();

    final messages = handwritingProposalMessages(
      fileName: fileName,
      mime: mime,
      base64: base64Encode(bytes),
      existingTagPaths: <String>[
        for (final tag in tags)
          if ((tag.path ?? '').trim().isNotEmpty) tag.path!.trim(),
      ],
      existingKnowledgePointTitles: <String>[
        for (final point in points) point.title,
      ],
    );

    final buffer = StringBuffer();
    String? failure;
    await for (final event in adapter.runTurn(
      messages: messages,
      tools: const <ModelToolSpec>[],
    )) {
      switch (event) {
        case ModelTextDelta(:final text):
          buffer.write(text);
        case ModelFailure(:final message):
          failure = message;
        case ModelToolCall():
        case ModelTurnDone():
          break;
      }
    }

    final raw = buffer.toString();
    if (failure != null) {
      return HandwritingProposalRun.modelFailure(
        relPath,
        '模型调用失败：$failure',
        rawReply: raw.isEmpty ? null : raw,
      );
    }

    final HandwritingProposalSet set;
    try {
      set = parseHandwritingProposals(raw, sourceRef: relPath);
    } on HandwritingProposalParseException catch (error) {
      return HandwritingProposalRun.parseFailure(relPath, error, raw);
    }

    return HandwritingProposalRun(sourceRef: relPath, set: set, rawReply: raw);
  }

  /// 把 [set] 里（默认全部）的提案写库。
  ///
  /// 逐条返回结果：一条失败不影响后面的条目——用户确认了三样，其中标签路径
  /// 不存在，那就只报告这一条，另外两样照写。
  Future<HandwritingApplyReport> applyAll(
    HandwritingProposalSet set, {
    Set<String> onlyIds = const <String>{},
  }) async {
    final outcomes = <HandwritingApplyOutcome>[];
    for (final proposal in set.proposals) {
      if (onlyIds.isNotEmpty && !onlyIds.contains(proposal.id)) {
        continue;
      }
      outcomes.add(await _applyOne(proposal));
    }
    return HandwritingApplyReport(
      sourceRef: set.sourceRef,
      outcomes: List<HandwritingApplyOutcome>.unmodifiable(outcomes),
    );
  }

  Future<HandwritingApplyOutcome> _applyOne(
    HandwritingProposal proposal,
  ) async {
    try {
      switch (proposal.kind) {
        case HandwritingProposalKind.tag:
          return await _applyTag(proposal);
        case HandwritingProposalKind.knowledgePoint:
          return await _applyKnowledgePoint(proposal);
        case HandwritingProposalKind.flashcard:
          return await _applyFlashcard(proposal);
      }
    } on Object catch (error) {
      return HandwritingApplyOutcome(
        proposalId: proposal.id,
        kind: proposal.kind,
        titleZh: proposal.titleZh,
        ok: false,
        failureReason: '写库失败：$error',
      );
    }
  }

  /// 标签：已存在就直接认领，不存在才建；**父路径不存在就报错**，
  /// 不替用户凭空造一棵新树。
  Future<HandwritingApplyOutcome> _applyTag(
    HandwritingProposal proposal,
  ) async {
    final parentPath = (proposal.fields['parent_path'] ?? '').trim();
    final fullPath = parentPath.isEmpty
        ? proposal.titleZh
        : '$parentPath/${proposal.titleZh}';

    final existing = await _tags.getTagByPath(fullPath);
    if (existing != null) {
      return HandwritingApplyOutcome(
        proposalId: proposal.id,
        kind: proposal.kind,
        titleZh: proposal.titleZh,
        ok: true,
        targetId: existing.id,
        detailZh: '标签树里已经有「$fullPath」，直接采用（没有新建）',
      );
    }

    String? parentId;
    if (parentPath.isNotEmpty) {
      final parent = await _tags.getTagByPath(parentPath);
      if (parent == null) {
        return HandwritingApplyOutcome(
          proposalId: proposal.id,
          kind: proposal.kind,
          titleZh: proposal.titleZh,
          ok: false,
          failureReason: '标签树里没有 `$parentPath`，先建这一层（或改挂别处）再确认',
        );
      }
      parentId = parent.id;
    }

    final created = await _tags.createTag(
      name: proposal.titleZh,
      parentId: parentId,
      description: proposal.fields['description'],
    );
    return HandwritingApplyOutcome(
      proposalId: proposal.id,
      kind: proposal.kind,
      titleZh: proposal.titleZh,
      ok: true,
      targetId: created.id,
      detailZh: '新建标签「${created.path ?? proposal.titleZh}」',
    );
  }

  /// 知识点：建点；`tag_path` 存在就挂边，不存在只说这一件事没做
  /// （知识点本身是有效的内容，不因为标签路径拼错就整条丢弃）。
  Future<HandwritingApplyOutcome> _applyKnowledgePoint(
    HandwritingProposal proposal,
  ) async {
    final point = await _anki.createKnowledgePoint(
      title: proposal.titleZh,
      content: proposal.fields['content'] ?? '',
      source: 'handwriting_intake',
    );

    final tagPath = (proposal.fields['tag_path'] ?? '').trim();
    if (tagPath.isEmpty) {
      return HandwritingApplyOutcome(
        proposalId: proposal.id,
        kind: proposal.kind,
        titleZh: proposal.titleZh,
        ok: true,
        targetId: point.id,
        detailZh: '建了知识点「${proposal.titleZh}」（没有指定标签，未挂边）',
      );
    }

    final tag = await _tags.getTagByPath(tagPath);
    if (tag == null) {
      return HandwritingApplyOutcome(
        proposalId: proposal.id,
        kind: proposal.kind,
        titleZh: proposal.titleZh,
        ok: true,
        targetId: point.id,
        detailZh: '建了知识点「${proposal.titleZh}」，但标签 `$tagPath` 不存在，没挂边',
      );
    }

    await _tags.addTagToObject(
      tagId: tag.id,
      objectType: kKnowledgePointObjectType,
      objectId: point.id,
    );
    return HandwritingApplyOutcome(
      proposalId: proposal.id,
      kind: proposal.kind,
      titleZh: proposal.titleZh,
      ok: true,
      targetId: point.id,
      detailZh: '建了知识点「${proposal.titleZh}」并挂到 `$tagPath`',
    );
  }

  /// 闪存卡：一个知识点 + N 张卡 + 每张卡的复习状态。
  Future<HandwritingApplyOutcome> _applyFlashcard(
    HandwritingProposal proposal,
  ) async {
    final point = await _anki.createKnowledgePoint(
      title: proposal.titleZh,
      content: proposal.fields['content'] ?? '',
      source: 'handwriting_intake',
    );

    for (final card in proposal.cards) {
      final template = await _anki.createTemplate(
        knowledgePointId: point.id,
        type: card.type,
        question: card.question,
        answer: card.answer,
      );
      // 没有卡状态的卡片在复习队列里是不存在的——建卡的整个意义就是让它可复习。
      await _anki.getOrCreateCardState(template.id);
    }

    final tagPath = (proposal.fields['tag_path'] ?? '').trim();
    var tagNote = '';
    if (tagPath.isNotEmpty) {
      final tag = await _tags.getTagByPath(tagPath);
      if (tag == null) {
        tagNote = '，但标签 `$tagPath` 不存在，没挂边';
      } else {
        await _tags.addTagToObject(
          tagId: tag.id,
          objectType: kKnowledgePointObjectType,
          objectId: point.id,
        );
        tagNote = '，并挂到 `$tagPath`';
      }
    }

    return HandwritingApplyOutcome(
      proposalId: proposal.id,
      kind: proposal.kind,
      titleZh: proposal.titleZh,
      ok: true,
      targetId: point.id,
      detailZh:
          '建了知识点「${proposal.titleZh}」+ ${proposal.cards.length} 张卡片（已进复习队列）$tagNote',
    );
  }
}

/// 队列状态：待整理的照片 + 内存里的提案 + 已确认过哪些。
class HandwritingQueueState {
  const HandwritingQueueState({
    this.images = const <PendingHandwritingImage>[],
    this.sets = const <String, HandwritingProposalSet>{},
    this.failures = const <String, String>{},
    this.analyzing = const <String>{},
    this.applying = const <String>{},
    this.appliedIds = const <String>{},
    this.lastReport,
    this.loading = false,
  });

  /// 磁盘上的待整理照片。
  final List<PendingHandwritingImage> images;

  /// 相对路径 → 已经整理出来的提案（**只在内存里**）。
  final Map<String, HandwritingProposalSet> sets;

  /// 相对路径 → 整理失败的原因。
  final Map<String, String> failures;

  /// 正在整理的相对路径。
  final Set<String> analyzing;

  /// 正在写库的相对路径。
  final Set<String> applying;

  /// 已经确认写库的提案，键是 `'<relPath>#<proposalId>'`。
  final Set<String> appliedIds;

  final HandwritingApplyReport? lastReport;

  final bool loading;

  bool isApplied(String relPath, String proposalId) =>
      appliedIds.contains('$relPath#$proposalId');

  HandwritingQueueState copyWith({
    List<PendingHandwritingImage>? images,
    Map<String, HandwritingProposalSet>? sets,
    Map<String, String>? failures,
    Set<String>? analyzing,
    Set<String>? applying,
    Set<String>? appliedIds,
    HandwritingApplyReport? lastReport,
    bool? loading,
    bool clearReport = false,
  }) {
    return HandwritingQueueState(
      images: images ?? this.images,
      sets: sets ?? this.sets,
      failures: failures ?? this.failures,
      analyzing: analyzing ?? this.analyzing,
      applying: applying ?? this.applying,
      appliedIds: appliedIds ?? this.appliedIds,
      lastReport: clearReport ? null : (lastReport ?? this.lastReport),
      loading: loading ?? this.loading,
    );
  }
}

/// 内存队列。写库走仓储（`DbWriteInterceptor` → `DataChangeBus`），
/// 所以刷新别的 provider 不需要这里做任何事。
class HandwritingQueueNotifier extends Notifier<HandwritingQueueState> {
  @override
  HandwritingQueueState build() => const HandwritingQueueState();

  HandwritingProposalService get _service =>
      ref.read(handwritingProposalServiceProvider);

  HandwritingIntakeStore get _store => ref.read(handwritingIntakeStoreProvider);

  /// 重新读磁盘上的待整理清单。
  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    final images = await _store.pending();
    state = state.copyWith(images: images, loading: false);
  }

  /// 整理一张照片（结果同时写进 state，方便页面直接渲染）。
  Future<HandwritingProposalRun> analyze(String relPath) async {
    state = state.copyWith(
      analyzing: <String>{...state.analyzing, relPath},
      failures: _without(state.failures, relPath),
    );
    final run = await _service.proposeFor(relPath);

    final sets = Map<String, HandwritingProposalSet>.of(state.sets);
    final failures = Map<String, String>.of(state.failures);
    if (run.ok) {
      sets[relPath] = run.set!;
      failures.remove(relPath);
    } else {
      sets.remove(relPath);
      failures[relPath] = run.failureReason ?? '整理失败';
    }

    state = state.copyWith(
      sets: sets,
      failures: failures,
      analyzing: <String>{...state.analyzing}..remove(relPath),
    );
    return run;
  }

  /// 确认**一条**提案并写库。
  ///
  /// 已经确认过的提案不再重复写（返回 `null`）：写库是新建而不是更新，点两次
  /// 就会得到两个一模一样的知识点——宁可什么都不做。
  Future<HandwritingApplyReport?> applyProposal(
    String relPath,
    String proposalId,
  ) async {
    final set = state.sets[relPath];
    if (set == null || state.isApplied(relPath, proposalId)) {
      return null;
    }
    state = state.copyWith(applying: <String>{...state.applying, relPath});
    final report = await _service.applyAll(set, onlyIds: <String>{proposalId});
    return _finishApply(relPath, report);
  }

  /// 确认这张照片上**还没确认过**的全部提案。
  Future<HandwritingApplyReport?> applyAll(String relPath) async {
    final set = state.sets[relPath];
    if (set == null) {
      return null;
    }
    final remaining = <String>{
      for (final proposal in set.proposals)
        if (!state.isApplied(relPath, proposal.id)) proposal.id,
    };
    if (remaining.isEmpty) {
      return null;
    }
    state = state.copyWith(applying: <String>{...state.applying, relPath});
    final report = await _service.applyAll(set, onlyIds: remaining);
    return _finishApply(relPath, report);
  }

  HandwritingApplyReport _finishApply(
    String relPath,
    HandwritingApplyReport report,
  ) {
    final applied = <String>{...state.appliedIds};
    for (final outcome in report.outcomes) {
      if (outcome.ok) {
        applied.add('$relPath#${outcome.proposalId}');
      }
    }
    state = state.copyWith(
      appliedIds: applied,
      applying: <String>{...state.applying}..remove(relPath),
      lastReport: report,
    );
    return report;
  }

  /// 丢掉内存里的整理结果（照片还在，可以重新整理）。
  void forget(String relPath) {
    final sets = Map<String, HandwritingProposalSet>.of(state.sets)
      ..remove(relPath);
    state = state.copyWith(
      sets: sets,
      failures: _without(state.failures, relPath),
      clearReport: true,
    );
  }
}

Map<String, String> _without(Map<String, String> source, String key) {
  if (!source.containsKey(key)) {
    return source;
  }
  return Map<String, String>.of(source)..remove(key);
}

String _fileNameOf(String relPath) {
  final parts = relPath.split(RegExp(r'[/\\]'));
  return parts.isEmpty ? relPath : parts.last;
}

/// App 默认服务：store 来自内存/磁盘，仓储来自数据库，适配器来自 AI 层
/// （可能是 `null` = 离线）。
final handwritingProposalServiceProvider =
    Provider<HandwritingProposalService>((ref) => HandwritingProposalService(
          store: ref.watch(handwritingIntakeStoreProvider),
          tags: ref.watch(tagRepositoryProvider),
          anki: ref.watch(ankiRepositoryProvider),
          adapter: ref.watch(modelAdapterProvider),
        ));

/// 待确认队列。
final handwritingQueueProvider =
    NotifierProvider<HandwritingQueueNotifier, HandwritingQueueState>(
  HandwritingQueueNotifier.new,
);
