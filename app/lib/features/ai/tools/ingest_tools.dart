/// 材料摄取 in the AI tool layer: 一份页边记号信封 → 待确认的"要建什么"
/// （roadmap §2-C ① / §3 第 6 行）。
///
/// 这一步是**接线**：Q33 的 `MaterialIngest`（纯函数，图补丁 + `mindnet.run/1`）本身
/// 没人能碰到；这个工具把它交给模型，并把结果翻译成应用侧计划
/// （[MaterialIntakePlanner]：要建哪些知识点、哪些连接、每条出处）。
///
/// **只读**：提案只是提案，不写库。写不写由用户在界面上确认 —— 与
/// `intake/handwriting_proposals.dart` 那条通路同一条纪律（"确认前不写库"）。
///
/// 时间基：材料入库也要一个时刻（INGEST 的 `run_request` 不许默默用"现在"，
/// `docs/IO_PROTOCOL.md` §3.3），所以工具把 `now` 或注入的时钟翻成**模型小时**
/// （[modelHoursOf]）再交给转化层 —— 这也是唯一需要"现在几点"的地方。
library;

import 'dart:convert';

import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/material_intake_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';
import '../domain/ai_tool.dart';

/// 信封 → 转化 → 应用侧计划。
///
/// 两个工具共用这一段：`ingest_material` 只看结果，`apply_material_intake` 看完再落库。
/// 复用不是为了省几行，而是为了**保证"确认的"就是"看到的"**：计划由内容确定（INGEST
/// 契约），同一份信封算两次得到同一批提案 id，所以确认时只需要再走一遍同一条推导。
({
  MaterialEnvelope envelope,
  MaterialConversion conversion,
  MaterialIntakePlan plan
}) buildMaterialPlan(
  Map<String, Object?> json, {
  required Set<String> existingTitles,
  required DateTime moment,
  bool includeTopicHubs = false,
}) {
  final envelope = MaterialEnvelope.fromJson(json);
  final conversion = MaterialIngest.convert(
    envelope,
    nowHours: modelHoursOf(moment),
  );
  final plan = MaterialIntakePlanner.plan(
    conversion,
    envelope: envelope,
    existingTitles: existingTitles,
    includeTopicHubs: includeTopicHubs,
  );
  return (envelope: envelope, conversion: conversion, plan: plan);
}

/// 把 `mindnet.material/1` 信封变成应用侧的待确认提案。
class IngestMaterialTool extends AiTool {
  IngestMaterialTool({
    required AnkiRepository ankiRepository,
    DateTime Function()? clock,
  })  : _anki = ankiRepository,
        _clock = clock ?? DateTime.now;

  final AnkiRepository _anki;

  /// 注入时钟：材料入库的时刻要可复现（测试里钉住同一个 `now`）。
  final DateTime Function() _clock;

  @override
  String get name => 'ingest_material';

  @override
  String get description => '把一份"页边记号"材料信封（`mindnet.material/1`：AI 从照片/材料上'
      '照抄下来的 items）转成**待确认的提案**：要建哪些知识点、哪些连接，每条都带出处'
      '（哪一页、页边原文、批次号）。它先按 INGEST 契约整份校验（不合规就整份拒绝并说清'
      '第几条错）；同名知识点已存在时照旧列出但标"不重复建"；疑问/已知/提醒这些不进图的'
      '条目留在清单外并给原因（不会被丢掉）。**只读**：不写库、不建卡片、不改任何数据 —— '
      '写不写由用户看到提案后确认。材料里"几张卡"是呈现层的事，这个工具不管。';

  @override
  Map<String, Object?> get parameters => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'material': <String, Object?>{
            'type': 'object',
            'description':
                'INGEST 的材料信封本体（`protocol` / `batch_id` / `source` / '
                    '`topic` / `items[]`…）。也可以给它的 JSON 文本。',
          },
          'include_topic_hubs': <String, Object?>{
            'type': 'boolean',
            'description': '可选：把主题分组（`#主题`）也当知识点提案。默认 false —— 主题是分组，'
                '而且"资料挂在卡片上算线索边还是包含边"还没定（roadmap §2-C ④）。',
          },
          'now': <String, Object?>{
            'type': 'string',
            'description': '可选 ISO-8601 时刻（材料入库的模型时间基）；默认当前时间',
          },
        },
        'required': <String>['material'],
      };

  /// 只读查询：不写任何东西。中性 `write` + `reversible` 让审批引擎不会逐次询问
  /// （与 `evaluate_problem_fit` / `plan_today` 同一个选择）。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final json = _materialJson(invocation.arguments['material']);

    final nowMs = args.optEpochMs('now');
    final moment =
        nowMs == null ? _clock() : DateTime.fromMillisecondsSinceEpoch(nowMs);
    final includeTopicHubs = args.optBool('include_topic_hubs') ?? false;

    final MaterialConversion conversion;
    final MaterialIntakePlan plan;
    try {
      (envelope: _, conversion: conversion, plan: plan) = buildMaterialPlan(
        json,
        existingTitles: await _existingTitles(),
        moment: moment,
        includeTopicHubs: includeTopicHubs,
      );
    } on MaterialIngestException catch (error) {
      return ToolResult.failure(
        error.message,
        summary: '材料信封不合规，整份拒绝（材料入库是"要么整批进、要么不进"）：'
            '${error.message}',
      );
    }

    final check = MaterialIngest.checkRunRequest(conversion.runRequest);
    final modelResult = <String, Object?>{
      'plan': plan.toJson(),
      'material': conversion.summary.toJson(),
      'warnings': <Object?>[
        for (final warning in conversion.warnings) warning.toJson(),
      ],
      'run_request': conversion.runRequest.toJson(),
      'run_check': <String, Object?>{
        'ok': check.ok,
        'errors': check.errors,
        'evidence_count': check.evidenceCount,
        'summary': check.summary,
      },
    };

    if (plan.isEmpty) {
      return ToolResult(
        ok: true,
        summary: '这份材料没有要动的东西：${plan.skippedCount} 条留在清单外'
            '（疑问/已知/提醒或被标为待归类，原因都在 payload 里）。'
            '提案是空的，所以没有任何东西需要确认。',
        modelResult: modelResult,
      );
    }

    final lines = <String>[];
    for (var i = 0; i < plan.proposals.length; i += 1) {
      final proposal = plan.proposals[i];
      final kind =
          proposal.kind == MaterialIntakeKind.knowledgePoint ? '知识点' : '连接';
      final existing = proposal.exists ? '（同名已存在，不重复建）' : '';
      lines.add(
          '${i + 1}. [$kind] ${proposal.title}$existing —— ${proposal.why}');
    }

    return ToolResult(
      ok: true,
      summary: '${plan.text}：\n'
          '${lines.join('\n')}\n'
          '只读：上面是提案，还没有写库（确认后才写）。每条出处与页边原文在 payload 的 '
          '`evidence` 里。',
      modelResult: modelResult,
    );
  }

  /// 库里现有知识点的标题（算 `exists` 用）。
  Future<Set<String>> _existingTitles() async => <String>{
        for (final point in await _anki.getKnowledgePoints()) point.title,
      };
}

/// 用户确认之后：把提案落库（roadmap §2-C ① 的后半段）。
///
/// 参数里给的是**同一份信封**，不是"提案清单"：提案由它确定性推导出来（INGEST 契约），
/// 所以"确认"只需要说清确认哪一批、哪几条。落库分两步走（`record` → `apply`），与界面上
/// "先看到清单、再逐条确认"是同一条路 —— 差别只在于这里的"看到"发生在上一轮对话里。
///
/// **写**：`knowledge_points` 会真的多出几行。可撤销的理由是 `afterJson` 里带着新建的
/// 知识点 id（与 `create_knowledge_cards` 同一个口径）。**连接不写**：资料与卡片是"线索
/// 边"还是"包含边"还没定（roadmap §2-C ④），落点不存在的写入只能是编的，所以它们在结果
/// 里如实报成 `deferred`，留在待办里等那个决定。
class ApplyMaterialIntakeTool extends AiTool {
  ApplyMaterialIntakeTool({
    required MaterialIntakeRepository repository,
    DateTime Function()? clock,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now;

  final MaterialIntakeRepository _repository;
  final DateTime Function() _clock;

  @override
  String get name => 'apply_material_intake';

  @override
  String get description => '用户确认后，把一份材料信封推导出来的提案**真的写进库**：'
      '新建知识点（标题/正文/出处进 `knowledge_points`，节点 id 进 `external_id`）。'
      '入库是幂等的：批次主键就是信封的 `batch_id`，同一条提案确认两次不会建出两个知识点，'
      '同名的也不会重复建（结果里如实报"已存在"）。**连接现在不写** —— 资料与卡片是'
      '"线索边"还是"包含边"还没定（roadmap §2-C ④），没有落点，所以它们在结果里报成 '
      '`deferred` 留在待办里。信封不合规就整份拒绝，绝不写半份。';

  @override
  Map<String, Object?> get parameters => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'material': <String, Object?>{
            'type': 'object',
            'description': '**同一份** `mindnet.material/1` 信封（上一步 '
                '`ingest_material` 用过的那一份）。也可以给它的 JSON 文本。',
          },
          'proposal_ids': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': '可选：只确认这几条（`kp:…` / `edge:…`）。默认处理这一批'
                '还没处理的全部。',
          },
          'include_topic_hubs': <String, Object?>{
            'type': 'boolean',
            'description': '可选：与上一步保持一致。默认 false（主题分组不建）。',
          },
          'now': <String, Object?>{
            'type': 'string',
            'description': '可选 ISO-8601 时刻（入库的模型时间基）；默认当前时间',
          },
        },
        'required': <String>['material'],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// 可以不带用户那次输入就撤销：`afterJson` 里带着这一轮新建的知识点 id。
  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final json = _materialJson(invocation.arguments['material']);

    final nowMs = args.optEpochMs('now');
    final moment =
        nowMs == null ? _clock() : DateTime.fromMillisecondsSinceEpoch(nowMs);
    final includeTopicHubs = args.optBool('include_topic_hubs') ?? false;
    final proposalIds = args.optStringList('proposal_ids');

    final MaterialEnvelope envelope;
    final MaterialConversion conversion;
    final MaterialIntakePlan plan;
    try {
      (envelope: envelope, conversion: conversion, plan: plan) =
          buildMaterialPlan(
        json,
        existingTitles: await _repository.existingTitles(),
        moment: moment,
        includeTopicHubs: includeTopicHubs,
      );
    } on MaterialIngestException catch (error) {
      return ToolResult.failure(
        error.message,
        summary: '材料信封不合规，整份拒绝（材料入库是"要么整批进、要么不进"）：'
            '${error.message}',
      );
    }

    if (plan.isEmpty) {
      return ToolResult(
        ok: true,
        summary: '这份材料没有要动的东西：${plan.skippedCount} 条留在清单外'
            '（疑问/已知/提醒或被标为待归类，原因都在 payload 里），所以一行都没写。',
        modelResult: <String, Object?>{'plan': plan.toJson()},
      );
    }

    if (proposalIds != null) {
      final known = {for (final proposal in plan.proposals) proposal.id};
      final unknown = [
        for (final id in proposalIds)
          if (!known.contains(id)) id,
      ];
      if (unknown.isNotEmpty) {
        return ToolResult.failure(
          '这些提案 id 不在这一批里：${unknown.join('、')}；'
          '这一批有：${known.join('、')}',
        );
      }
    }

    final batch = await _repository.record(
      plan,
      summaryText: conversion.summary.text,
      analyzedAt: moment,
      sourceKind: envelope.source?.kind,
      capturedAtMs: DateTime.tryParse(envelope.source?.capturedAt ?? '')
          ?.millisecondsSinceEpoch,
    );
    final MaterialApplyOutcome outcome;
    try {
      outcome = await _repository.apply(
        batchId: batch.batchId,
        proposalIds: proposalIds,
        appliedAt: moment,
      );
    } on MaterialApplyException catch (error) {
      return ToolResult.failure(error.message);
    }

    // payload 里的批次取**确认之后**的样子：`unapplied_count` 要能直接读出来还剩几条，
    // 而不是记录那一刻的旧值。
    final updated = await _repository.batch(batch.batchId) ?? batch;

    final lines = <String>[
      for (final point in outcome.created)
        '- 建了知识点「${point.title}」'
            '${point.nodeId == null ? '' : '（${point.nodeId}）'}',
      if (outcome.existing.isNotEmpty)
        '- 已存在，没重复建：${outcome.existing.join('、')}',
      if (outcome.deferred.isNotEmpty)
        '- 连接先不动：${outcome.deferred.join('、')}'
            '（资料与卡片是"线索边"还是"包含边"还没定，roadmap §2-C ④）',
    ];

    return ToolResult(
      ok: true,
      summary: '${outcome.text}。\n${lines.join('\n')}\n'
          '出处写在每个知识点的正文与 `source` 里，提案表里留着完整的 `evidence`。'
          '${outcome.deferred.isEmpty ? '' : '连接还没落点，它们留在待确认清单里。'}',
      modelResult: <String, Object?>{
        'batch': updated.toJson(),
        'outcome': outcome.toJson(),
      },
      afterJson: jsonEncode(<String, Object?>{
        'batch_id': batch.batchId,
        'knowledge_point_ids': [
          for (final point in outcome.created) point.knowledgePointId,
        ],
      }),
    );
  }
}

/// `material` 参数：对象直接用；模型给 JSON 文本时解一次。
Map<String, Object?> _materialJson(Object? raw) {
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  if (raw is String) {
    final decoded = _tryDecode(raw);
    if (decoded != null) {
      return decoded;
    }
    throw ToolArgError('`material` 是字符串，但不是合法的 JSON 对象');
  }
  throw ToolArgError(
    '缺少 `material`：需要一份 `mindnet.material/1` 信封（对象或它的 JSON 文本）',
  );
}

Map<String, Object?>? _tryDecode(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}
