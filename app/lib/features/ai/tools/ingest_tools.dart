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

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/material_intake_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';
import '../../../domain/services/ingest/run_executor.dart';
import '../../../domain/services/ingest/run_knowledge_plan.dart';
import '../../../domain/services/ingest/run_reading.dart';
import '../../../domain/services/ingest/transcribe_run.dart';
import '../../cognitive/application/run_intake.dart';
import '../../cognitive/application/run_rehearsal.dart';
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
/// **写**：`knowledge_points` 会真的多出几行，选中的连接也会落成 `knowledge_edges`
/// 里的**线索边**（严格有向、`origin` 记住它是材料里的哪种关系，`ls` 带"未标定"标记）。
/// 可撤销的理由是 `afterJson` 里带着新建的知识点 id（与 `create_knowledge_cards` 同一个
/// 口径）。连接的两端必须都在库里（本批刚建的或原有的）—— 缺一端就落不了，如实报
/// `deferred` 并留在待办里，绝不编一条边出来。
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
      '新建知识点（标题/正文/出处进 `knowledge_points`，节点 id 进 `external_id`），'
      '选中的连接落成 `knowledge_edges` 里的**线索边**（严格有向；`origin` 记住它是材料里'
      '的哪种关系，`ls` 带未标定标记）。'
      '入库是幂等的：批次主键就是信封的 `batch_id`，同一条提案确认两次不会建出两个知识点'
      '或两条边，同名的也不会重复建（结果里如实报"已存在"）。连接的**两端都必须已经在库里**'
      '（本批刚建的或原有的）—— 缺一端就落不了，报成 `deferred` 留在待办里，绝不编一条边。'
      '信封不合规就整份拒绝，绝不写半份。'
      '点头之前可以先改一改**知识点**提案的标题（`renames`）：界面上那颗铅笔（轮次九十四）'
      '在这条工具路上也有 —— 改的还是提案本身，确认之后建出来的就是改过的标题。';

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
          'renames': <String, Object?>{
            'type': 'object',
            'description': '可选：点头之前改一改**知识点**提案的标题（`{"kp:en::w::rely-on": '
                '"rely on（依靠）"}`）。只改知识点提案（连接的标题是按两端 id 现算的），'
                '已经点头过的不许改；改完再确认，建出来的就是改过的标题。',
            'additionalProperties': <String, Object?>{'type': 'string'},
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

    // 点头之前改一改标题（与界面那颗铅笔同一件事）。参数是"提案 id → 新标题"的对象。
    final rawRenames = invocation.arguments['renames'];
    final renames = <String, String>{};
    if (rawRenames is Map) {
      for (final entry in rawRenames.entries) {
        final id = entry.key.toString().trim();
        if (id.isEmpty) {
          return const ToolResult.failure('`renames` 里有空的提案 id：键不能是空的');
        }
        renames[id] = entry.value?.toString().trim() ?? '';
      }
    } else if (rawRenames != null) {
      return const ToolResult.failure('`renames` 应该是一个对象（提案 id → 新标题）');
    }

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
    // 先改名字，再点头：改的是提案本身（`payload_json` 里那个标题），知识点仍然要等
    // `apply` 才建 —— 与界面上那颗铅笔同一条口径。
    final renamed = <Map<String, Object?>>[];
    for (final entry in renames.entries) {
      try {
        await _repository.renamePointProposal(
          batchId: batch.batchId,
          proposalId: entry.key,
          title: entry.value,
        );
      } on MaterialApplyException catch (error) {
        return ToolResult.failure(
          error.message,
          summary: '先改标题那一步没成 —— 提案已经记下来了，但还没点头，所以一个知识点都'
              '没建：${error.message}',
        );
      }
      renamed.add(<String, Object?>{
        'proposal_id': entry.key,
        'title': entry.value,
      });
    }
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
      if (renamed.isNotEmpty)
        '- 先改过 ${renamed.length} 条知识点提案的标题：'
            '${[
          for (final row in renamed)
            '`${row['proposal_id']}` → 「${row['title']}」'
        ].join('、')}',
      for (final point in outcome.created)
        '- 建了知识点「${point.title}」'
            '${point.nodeId == null ? '' : '（${point.nodeId}）'}',
      for (final edge in outcome.createdEdges)
        '- 建了连接 ${edge.fromId} → ${edge.toId}'
            '${edge.origin == null ? '' : '（${edge.origin}）'}',
      if (outcome.existing.isNotEmpty)
        '- 已存在，没重复建：${outcome.existing.join('、')}',
      if (outcome.existingEdges.isNotEmpty)
        '- 连接已存在，没重复建：${outcome.existingEdges.join('、')}',
      if (outcome.deferred.isNotEmpty)
        '- 连接落不了（有一端还不在库里）：${outcome.deferred.join('、')}',
    ];

    return ToolResult(
      ok: true,
      summary: '${outcome.text}。\n${lines.join('\n')}\n'
          '出处写在每个知识点的正文与 `source` 里，提案表里留着完整的 `evidence`；'
          '线索边的 `ls` 带"未标定"标记（没有标定来源的数不许当真）。'
          '${outcome.deferred.isEmpty ? '' : '落不了的连接留在待确认清单里，等端点补齐。'}',
      modelResult: <String, Object?>{
        'batch': updated.toJson(),
        'outcome': outcome.toJson(),
        if (renamed.isNotEmpty) 'renamed': renamed,
      },
      afterJson: jsonEncode(<String, Object?>{
        'batch_id': batch.batchId,
        'knowledge_point_ids': [
          for (final point in outcome.created) point.knowledgePointId,
        ],
        'edge_ids': [
          for (final edge in outcome.createdEdges) edge.edgeId,
        ],
      }),
    );
  }
}

/// 转写规程（照片 → `mindnet.run/1`）的自检工具（roadmap §2-C ③）。
///
/// 与 MindNet 的 `tools/io_check.js` 是同一件事：**只校验、不执行**。把上游 AI 从照片
/// 产出的 run 请求过一遍，回答两个问题："错在哪"与"它会做什么"（每条动作落到哪条机制
/// 路径）。图清单默认从库里查（`knowledge_points.external_id`）—— `review` / `exposure` /
/// `goal` 只能指向图里已有的节点，而"图"在应用侧的真实来源就是这一列。
///
/// 要 `execute: true` 时多走一步**演练**（`rehearseRun`）：把请求提到的、库里已有的
/// 节点按 `ms` 摆进仿真图、只装记忆层，然后让 `executeRun` 真的把动作 apply 一遍 ——
/// **只跑不落库**（库里的知识点、边、卡片状态、记忆态一个字都不动）。这一步就是执行层
/// （轮次七十八写好的 `run_executor.dart`）的调用者。
///
/// 与 `apply_material_intake` 同一条纪律：不合规就整份拒绝，不修修补补地"挑能跑的先跑"。
class CheckTranscribeRunTool extends AiTool {
  CheckTranscribeRunTool({
    required MaterialIntakeRepository repository,
    required AppDatabase database,
    CognitiveModel model = const MindNetCognitiveModel(),
    DateTime Function()? clock,
  })  : _repository = repository,
        _database = database,
        _model = model,
        _clock = clock ?? DateTime.now;

  final MaterialIntakeRepository _repository;
  final AppDatabase _database;
  final CognitiveModel _model;
  final DateTime Function() _clock;

  @override
  String get name => 'check_transcribe_run';

  @override
  String get description => '自检一份（从照片/文本转写出的）`mindnet.run/1` 请求：'
      '**只校验、不执行**（默认）。逐条说明"错在哪"（协议、幂等键、时间基、动作字段、'
      '图里有没有这个节点、同一节点有没有矛盾的结论）与"它会做什么"'
      '（每条动作落到哪条机制路径：复习的三种 outcome、失败后对答案的学习路径、'
      '再读、建节点/边、重开扩散、时间前进）。另按 TRANSCRIBE 规程给出**不拦**的建议：'
      '每条都该带 evidence 与 confidence、`review` 的 quote 不该空、'
      '`reviewed_solution` 只对 wrong 有意义。需要的话把给上游模型的转写提示词'
      '（含【图清单】）一起返回。'
      '`execute: true` 时再走一步**演练**：把请求提到、库里已有的节点摆进仿真图'
      '（`ms` 用库里代表卡片的模型读数）并真的把动作 apply 一遍 —— 只跑不落库，'
      '库里的知识点/边/卡片状态/记忆态都不变。'
      '`record: true`（要连同 `execute: true`）时，演练完把这一跑要新建的节点/边'
      '交给人确认：落成待确认提案（两张清单表），仍然不建任何知识点或边；'
      '提案 id 会摆在结果的 `recorded_proposals` 里，还能先用 `edits` 在点头之前'
      '改一改知识点提案的标题/正文（`run/1` 那条路的正文常常是空的，正好在这儿补）。';

  @override
  Map<String, Object?> get parameters => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'request': <String, Object?>{
            'type': 'object',
            'description': '一份 `mindnet.run/1` 请求。也可以给它的 JSON 文本。',
          },
          'existing_node_ids': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': '可选：图里已有的节点 id。默认从库里知识点的 `external_id` 查。',
          },
          'include_prompt': <String, Object?>{
            'type': 'boolean',
            'description': '可选：是否把转写提示词（含【图清单】）一起返回。默认 false。',
          },
          'graph_name': <String, Object?>{
            'type': 'string',
            'description': '可选：提示词里的图名。',
          },
          'note': <String, Object?>{
            'type': 'string',
            'description': '可选：提示词末尾的补充说明。',
          },
          'execute': <String, Object?>{
            'type': 'boolean',
            'description': '可选：是否再走一步"演练"——把动作真的 apply 进仿真引擎'
                '（只跑不落库）。默认 false（只校验）。',
          },
          'record': <String, Object?>{
            'type': 'boolean',
            'description': '可选：演练完之后，把这一跑**要新建的东西**（`knowledge` 动作'
                '的节点/边）落成**待确认提案**（`material_intake_batches` / '
                '`material_intake_proposals` 两张清单表）。`knowledge_points` / '
                '`knowledge_edges` 一行都不动 —— 那是「添加资料」页上点头那一步的事。'
                '要比对得像样的东西才落得下来；只有 review/exposure/goal/time 的一跑'
                '没有可确认的东西，这一项会说人话拒绝。默认 false。',
          },
          'edits': <String, Object?>{
            'type': 'object',
            'description': '可选（要连同 `record: true`）：落成提案之后、点头之前改一改'
                '其中几条**知识点**提案：`{"kp:en::w::a": {"title": "alpha", '
                '"body": "释义：阿尔法"}}`；值给字符串就是只改标题。'
                '`run/1` 那条路的正文本来常常是空的，正好在这儿补。'
                '连接的标题是按两端名字现算的，改不了；已经点头过的也改不了。',
            'additionalProperties': <String, Object?>{'type': 'object'},
          },
        },
        'required': <String>['request'],
      };

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
    final raw = invocation.arguments['request'];
    if (raw == null) {
      throw ToolArgError(
        '缺少 `request`：需要一份 `mindnet.run/1` 请求（对象或它的 JSON 文本）',
      );
    }
    final MaterialRunRequest request;
    try {
      request = decodeRunRequest(raw);
    } on FormatException catch (error) {
      throw ToolArgError(error.message);
    }

    final inventory = await _repository.externalNodeInventory();
    final provided = args.optStringList('existing_node_ids');
    final existingNodeIds = provided == null
        ? <String>{for (final entry in inventory) entry.id}
        : provided.toSet();

    final report = reviewTranscribedRun(
      request,
      existingNodeIds: existingNodeIds,
    );

    final includePrompt = args.optBool('include_prompt') ?? false;
    final prompt = includePrompt
        ? buildTranscribePrompt(
            inventory: inventory,
            graphName: args.optString('graph_name'),
            note: args.optString('note'),
          )
        : null;

    final modelResult = <String, Object?>{
      'report': report.toJson(),
      'graph_nodes': existingNodeIds.length,
      if (prompt != null) 'prompt': prompt,
    };

    if (!report.ok) {
      return ToolResult(
        ok: false,
        summary: '${report.text}\n'
            '这份请求不能执行：整份拒绝（与材料入库同一条纪律 —— "要么整批进、要么不进"）。'
            '图清单来自库里的 ${existingNodeIds.length} 个节点。',
        modelResult: modelResult,
        error: report.errors.join('；'),
      );
    }

    final execute = args.optBool('execute') ?? false;
    final record = args.optBool('record') ?? false;
    if (record && !execute) {
      return ToolResult(
        ok: false,
        summary: '`record: true` 要跟 `execute: true` 一起用：先真的跑一遍，才知道'
            '这一跑要新建什么。',
        modelResult: modelResult,
        error: '`record` 需要 `execute: true`',
      );
    }

    // 点头之前改一改（与材料那条路的 `renames`、界面那颗铅笔同一件事）：只有给了
    // `edits` 才做，而且得先落成提案才谈得上改。
    final rawEdits = invocation.arguments['edits'];
    final edits = <String, Map<String, String>>{};
    if (rawEdits is Map) {
      for (final entry in rawEdits.entries) {
        final id = entry.key.toString().trim();
        if (id.isEmpty) {
          return const ToolResult.failure('`edits` 里有空的提案 id：键不能是空的');
        }
        final value = entry.value;
        if (value is String) {
          edits[id] = <String, String>{'title': value.trim()};
        } else if (value is Map) {
          final row = value.cast<String, Object?>();
          edits[id] = <String, String>{
            if (row['title'] != null) 'title': row['title'].toString().trim(),
            if (row['body'] != null) 'body': row['body'].toString(),
          };
        } else {
          return const ToolResult.failure(
            '`edits` 的每一项要么是字符串（只改标题），要么是对象（`title` / `body`）',
          );
        }
      }
    } else if (rawEdits != null) {
      return const ToolResult.failure('`edits` 应该是一个对象（提案 id → 改什么）');
    }
    if (edits.isNotEmpty && !record) {
      return ToolResult(
        ok: false,
        summary: '`edits` 要跟 `record: true` 一起用：先落成待确认提案，才谈得上点头之前'
            '改一改。',
        modelResult: modelResult,
        error: '`edits` 需要 `record: true`',
      );
    }
    if (!execute) {
      return ToolResult(
        ok: true,
        summary: '${report.text}\n'
            '只读：这份请求还没有被执行（要真的跑一遍，给 `execute: true`）。'
            '图清单来自库里的 ${existingNodeIds.length} 个节点。'
            '${prompt == null ? '' : '转写提示词（含图清单）在 payload 的 `prompt` 里。'}',
        modelResult: modelResult,
      );
    }

    final rehearsal = await rehearseRun(
      request: request,
      db: _database,
      model: _model,
      now: _clock(),
    );
    modelResult['rehearsal'] = rehearsal.toJson();

    // 交给人确认那一步（`record: true`）：只落待确认提案，知识点/边一行不动。
    // 只有 review/exposure/goal/time 的一跑没有可确认的东西 —— 如实说，不编空清单。
    MaterialIntakeBatch? recorded;
    String? recordProblem;
    if (record) {
      try {
        recorded = await recordRunKnowledge(
          report: rehearsal.report,
          db: _database,
          anki: AnkiRepository(_database),
          now: _clock(),
          sourceRef: 'AI 工具 check_transcribe_run',
        );
      } on RunKnowledgeException catch (error) {
        recordProblem = error.message;
      }
    }
    if (recorded != null) {
      modelResult['recorded_batch'] = <String, Object?>{
        'batch_id': recorded.batchId,
        'proposal_count': recorded.proposalCount,
        'source_kind': recorded.sourceKind,
      };
    }
    if (recordProblem != null) {
      modelResult['record_problem'] = recordProblem;
    }

    // 改的是提案本身（`payload_json`），知识点照样要等点头那一下才建。
    final editedRows = <Map<String, Object?>>[];
    if (recorded != null && edits.isNotEmpty) {
      for (final entry in edits.entries) {
        final change = entry.value;
        try {
          await _repository.editPointProposal(
            batchId: recorded.batchId,
            proposalId: entry.key,
            title: change['title'],
            body: change['body'],
          );
        } on MaterialApplyException catch (error) {
          return ToolResult.failure(
            error.message,
            summary: '先改那几条提案那一步没成 —— 提案已经记下来了，但还没点头，'
                '所以一个知识点都没建：${error.message}',
          );
        }
        editedRows.add(<String, Object?>{'proposal_id': entry.key, ...change});
      }
      modelResult['edited'] = editedRows;
    }
    // 提案 id 摆出来：下一次要改哪一条、点头时给 `apply_material_intake` 选哪几条，
    // 都靠它 —— 没有它，模型只能猜。
    if (recorded != null) {
      final pending = await _repository.pendingProposals(recorded.batchId);
      modelResult['recorded_proposals'] = <Map<String, Object?>>[
        for (final proposal in pending)
          <String, Object?>{
            'proposal_id': proposal.id,
            'kind': proposal.kind.id,
            'title': proposal.title,
          },
      ];
    }

    final lines = <String>[
      '演练（只跑不落库）：${rehearsal.text}',
      '图清单来自库里的 ${existingNodeIds.length} 个节点；'
          '其中 ${rehearsal.seedNodeIds.length} 个在库、被摆进了仿真图'
          '${rehearsal.seedEdgeIds.isEmpty ? '' : '（另有 ${rehearsal.seedEdgeIds.length} 条库里已有的边）'}。'
          '${prompt == null ? '' : '转写提示词（含图清单）在 payload 的 `prompt` 里。'}',
      for (final trace in rehearsal.report.traces) _traceLine(trace),
      if (recorded != null)
        '已交给人确认：这一跑要新建的 ${recorded.proposalCount} 样东西落成了待确认提案'
            '（批次 `${recorded.batchId}`）—— 只写了那两张清单表，'
            '`knowledge_points` / `knowledge_edges` 一行都没动；'
            '去「添加资料」那一页点头，才真的建。'
            '同一跑再记一次，落的还是这一批。'
            '提案 id 在 payload 的 `recorded_proposals` 里（拿它来查/改/点头）。',
      if (editedRows.isNotEmpty)
        '点头之前改过 ${editedRows.length} 条知识点提案：'
            '${[
          for (final row in editedRows) '`${row['proposal_id']}`'
        ].join('、')}'
            ' —— 改的是提案，知识点还是等点头才建。',
      if (recordProblem != null) '没记成：$recordProblem',
    ];

    return ToolResult(
      ok: rehearsal.report.ok && recordProblem == null,
      summary: lines.join('\n'),
      modelResult: modelResult,
      error: rehearsal.report.failure?.error ?? recordProblem,
    );
  }
}

/// 一条动作那一行：引擎自己那句 `text`，缩进一行摆它**回报的读数**（改了什么）。
/// 没装机制（空增量）或这一条没跑成时没有第二行 —— 不编。
String _traceLine(RunActionTrace trace) {
  final reading = traceReadingOf(trace);
  return reading.isEmpty ? '· ${trace.text}' : '· ${trace.text}\n  $reading';
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
