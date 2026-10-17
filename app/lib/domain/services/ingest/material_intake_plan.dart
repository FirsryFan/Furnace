/// 材料摄取的**应用侧计划**：把 INGEST 的图补丁翻译成"要建哪些知识点、哪些连接"，
/// 每条都带出处（roadmap §2-C ① / §3 第 6 行）。
///
/// 上游（[MaterialIngest]，Q33）已经把材料信封变成确定性的图补丁与 `mindnet.run/1`
/// 请求；这一层不重算那件事，只回答**本仓库要动什么**：哪些节点该在 `knowledge_points`
/// 里出现、哪些边该成为连接、哪些条目因为角色或重复而留在清单外。
///
/// 为什么是"计划"而不是"写入"：与 `intake/handwriting_proposals.dart` 同一条先例 ——
/// 材料是用户的数据，AI 的判读必须先摆出来让人确认；写库由上层在确认时做。所以这一层
/// **纯 Dart**：不 import drift、不 import Flutter、不碰数据库、不发请求。
///
/// 三条纪律：
///  * **不重复建**：同名知识点（[normalizeTitle] 归一后）已存在时提案照出，但标
///    [MaterialIntakeProposal.exists]，由调用方决定"跳过还是合并"。节点 id 仍带在提案上
///    （`node_id`），写库时可以写进 `knowledge_points.external_id` —— 那一列在表里存在，
///    只是领域实体 `KnowledgePoint` 还没读它，所以这一层不拿它去重。
///  * **不进图 ≠ 丢弃**：`question` / `known` / `note` / 不认识的记号原样留在 [MaterialIntakePlan.skipped]
///    里并带原因（INGEST §5 第三条不变量）。
///  * **没定的事不偷偷定**：主题 hub（`en::topic::…`）是分组而不是知识点，默认只进
///    `skipped` 并写明"主题分组默认不建"（会把每个节点都连到同一个 hub）；想让审计看到它
///    请显式传 [MaterialIntakePlanner.plan] 的 `includeTopicHubs: true`。
///
/// 幂等来自上游：节点 id 内容确定（`en::w::resilient`），所以提案 id（`kp:<nodeId>` /
/// `edge:<edgeId>`）同一页拍两次完全一样。
library;

import 'material_ingest.dart';

/// 一条提案要动的东西。
enum MaterialIntakeKind {
  /// 在 `knowledge_points` 里建一个知识点。
  knowledgePoint('knowledge_point'),

  /// 建一条连接（两个知识点之间的**线索边**，落在 `knowledge_edges`；见 §2-C ④）。
  connection('connection');

  const MaterialIntakeKind(this.id);

  /// 稳定值（进 JSON，不给模型翻译）。
  final String id;
}

/// 一条提案的出处：材料权威性原则要求"任何字段都能追回哪一页哪一行"（INGEST §5）。
class MaterialIntakeEvidence {
  const MaterialIntakeEvidence({
    this.source,
    this.page,
    required this.region,
    this.quote,
    required this.batchId,
  });

  /// 来源材料（`source.material`，或 `refs` 的第一项）。
  final String? source;

  /// 页码（材料里 AI 抄下来的那一页）。
  final double? page;

  /// 区域，人话：`第 3 页` / `边：contains`。
  final String region;

  /// 页边那一行（原样，不解释）。
  final String? quote;

  /// 幂等键（同一批材料）。
  final String batchId;

  Map<String, Object?> toJson() => <String, Object?>{
        if (source != null) 'source': source,
        'page': MaterialIngest.integral(page),
        'region': region,
        if (quote != null) 'quote': quote,
        'batch_id': batchId,
      };

  /// 从 [toJson] 的输出还原（持久化用）。
  ///
  /// 缺 `region` / `batch_id` 就抛 [FormatException]：库里存坏一行时宁可报错，
  /// 也不让一条不知道出处的提案混进清单 —— 出处正是材料摄取的意义所在。
  factory MaterialIntakeEvidence.fromJson(Map<String, Object?> json) {
    final region = json['region']?.toString().trim() ?? '';
    final batchId = json['batch_id']?.toString().trim() ?? '';
    if (region.isEmpty || batchId.isEmpty) {
      throw const FormatException('提案出处缺少 region 或 batch_id');
    }
    return MaterialIntakeEvidence(
      source: json['source']?.toString(),
      page: switch (json['page']) {
        final num value => value.toDouble(),
        _ => null,
      },
      region: region,
      quote: json['quote']?.toString(),
      batchId: batchId,
    );
  }
}

/// 一条待确认的动作。
class MaterialIntakeProposal {
  const MaterialIntakeProposal({
    required this.id,
    required this.kind,
    required this.title,
    this.nodeId,
    this.from,
    this.to,
    this.ls,
    this.origin,
    required this.body,
    required this.why,
    required this.exists,
    required this.evidence,
  });

  /// 稳定 id：`kp:<nodeId>` / `edge:<edgeId>`。
  final String id;

  final MaterialIntakeKind kind;

  /// 人话标题（知识点：正文；连接：`句子 → 词`）。
  final String title;

  /// 知识点提案：上游的节点 id（`en::w::resilient`）。
  final String? nodeId;

  /// 连接提案的两端（节点 id）。
  final String? from;
  final String? to;

  /// 连接强度（**未标定**，INGEST §3.1）。
  final double? ls;

  /// 连接提案：这条边来自材料里的哪种关系（`contains` / `produce` / `topic`）。
  ///
  /// 只是出处，不是语义类别 —— 落库时它进 `knowledge_edges.origin`，
  /// 而"线索 vs 包含"的分工由表本身定（roadmap §2-C ④）。
  final String? origin;

  /// 知识点提案的正文（释义 / 音标 / 原文 / 出处），直接可以当 `content`。
  final String body;

  /// 为什么有它（人话）。
  final String why;

  /// 同名知识点已存在 ⇒ 不重复建。
  final bool exists;

  final MaterialIntakeEvidence evidence;

  /// 用户点头之前改过的字段：标题（自己起的名字）、正文（释义/例句，机器常读不全）、
  /// 以及"库里已经有一个同名的了"。
  ///
  /// 只开这几个口子：其余字段都是上游算出来的（id、两端、`ls`、出处），让它们能被
  /// 就地改就等于把"这条提案从哪来"改掉了。
  MaterialIntakeProposal copyWith(
          {String? title, bool? exists, String? body}) =>
      MaterialIntakeProposal(
        id: id,
        kind: kind,
        title: title ?? this.title,
        nodeId: nodeId,
        from: from,
        to: to,
        ls: ls,
        origin: origin,
        body: body ?? this.body,
        why: why,
        exists: exists ?? this.exists,
        evidence: evidence,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.id,
        'title': title,
        if (nodeId != null) 'node_id': nodeId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (ls != null) 'ls': MaterialIngest.integral(ls),
        if (origin != null) 'origin': origin,
        'body': body,
        'why': why,
        'exists': exists,
        'evidence': evidence.toJson(),
      };

  /// 从 [toJson] 的输出还原（持久化用）。
  ///
  /// 与入库同一套严格口径：缺 `id` / `title` / 认不出的 `kind` / 没有 `evidence`
  /// 都抛 [FormatException]，而不是降级成一条空提案。
  factory MaterialIntakeProposal.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString().trim() ?? '';
    final title = json['title']?.toString() ?? '';
    final kindId = json['kind']?.toString().trim() ?? '';
    MaterialIntakeKind? kind;
    for (final candidate in MaterialIntakeKind.values) {
      if (candidate.id == kindId) {
        kind = candidate;
        break;
      }
    }
    final evidence = json['evidence'];
    if (id.isEmpty || title.isEmpty || kind == null || evidence is! Map) {
      throw FormatException('提案缺少 id/title/evidence 或 kind 不认识（kind=$kindId）');
    }
    return MaterialIntakeProposal(
      id: id,
      kind: kind,
      title: title,
      nodeId: json['node_id']?.toString(),
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      ls: switch (json['ls']) {
        final num value => value.toDouble(),
        _ => null,
      },
      origin: json['origin']?.toString(),
      body: json['body']?.toString() ?? '',
      why: json['why']?.toString() ?? '',
      exists: json['exists'] == true,
      evidence:
          MaterialIntakeEvidence.fromJson(evidence.cast<String, Object?>()),
    );
  }
}

/// 留在清单外的条目（与原因）。
class MaterialIntakeSkip {
  const MaterialIntakeSkip({required this.ref, required this.reason});

  /// 上游条目 id 或边 id。
  final String ref;

  /// 人话原因。
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'ref': ref,
        'reason': reason,
      };

  /// 从 [toJson] 的输出还原（持久化用）。
  factory MaterialIntakeSkip.fromJson(Map<String, Object?> json) {
    final ref = json['ref']?.toString().trim() ?? '';
    if (ref.isEmpty) {
      throw const FormatException('留在清单外的条目缺少 ref');
    }
    return MaterialIntakeSkip(
      ref: ref,
      reason: json['reason']?.toString() ?? '',
    );
  }
}

/// 一份材料的应用侧计划。
class MaterialIntakePlan {
  const MaterialIntakePlan({
    required this.batchId,
    this.topic,
    this.sourceRef,
    required this.proposals,
    required this.skipped,
  });

  final String batchId;
  final String? topic;

  /// 来源材料（`source.material`，没有就用 `refs` 的第一项）。
  final String? sourceRef;

  final List<MaterialIntakeProposal> proposals;
  final List<MaterialIntakeSkip> skipped;

  /// 要新建的知识点数（已存在的不算）。
  int get newPoints => proposals
      .where((p) => p.kind == MaterialIntakeKind.knowledgePoint && !p.exists)
      .length;

  /// 同名已存在的知识点数。
  int get existingPoints => proposals
      .where((p) => p.kind == MaterialIntakeKind.knowledgePoint && p.exists)
      .length;

  /// 连接提案数。
  int get connections =>
      proposals.where((p) => p.kind == MaterialIntakeKind.connection).length;

  /// 留在清单外的条目数。
  int get skippedCount => skipped.length;

  bool get isEmpty => proposals.isEmpty;

  /// 人话一行（给工具/日志用）。
  String get text {
    if (proposals.isEmpty) {
      return '这份材料没有要动的东西（留 $skippedCount 条在外面，原因都写着）';
    }
    final existing = existingPoints > 0 ? '（其中 $existingPoints 个已存在，不重复建）' : '';
    final outside = skippedCount > 0 ? '；$skippedCount 条留在清单外' : '';
    return '批次 $batchId：要建 $newPoints 个知识点$existing、$connections 条连接$outside';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'batch_id': batchId,
        if (topic != null) 'topic': topic,
        if (sourceRef != null) 'source': sourceRef,
        'new_points': newPoints,
        'existing_points': existingPoints,
        'connections': connections,
        'skipped_count': skippedCount,
        'text': text,
        'proposals': <Object?>[for (final p in proposals) p.toJson()],
        'skipped': <Object?>[for (final s in skipped) s.toJson()],
      };
}

/// 图补丁 → 应用侧计划（纯函数）。
abstract final class MaterialIntakePlanner {
  /// 主题 hub 的节点 id 前缀（`en::topic::travel`）。
  static const String topicIdMarker = '::topic::';

  /// 知识点标题的长度上限（`knowledge_points.title` 是 `min:1, max:300`）。
  static const int titleMaxLength = 300;

  /// 每条提案的动作上限（一个标题里的人话名字，`name` 上游已截到 80）。
  static const int labelMaxLength = 80;

  /// 角色 → 人话（与 `src/ingest.js` 的 `ROLE_NODE_TYPE` 同一组键）。
  static const Map<String, String> roleLabels = <String, String>{
    'item': '要能复习的单元',
    'passage': '整句/整段',
    'method': '方法/技巧',
  };

  /// 把图补丁翻译成"要建什么"。
  ///
  /// [existingTitles] 是库里已有的知识点标题（**调用方给原文即可**，这里自己归一）。
  /// [includeTopicHubs] 默认 `false`：主题是分组，不是知识点；它会把每个节点都连到
  /// 同一个 hub，而"这批材料属于同一主题"通常看一眼标题就够了 —— 默认只报出来，不建。
  static MaterialIntakePlan plan(
    MaterialConversion conversion, {
    required MaterialEnvelope envelope,
    Set<String> existingTitles = const <String>{},
    bool includeTopicHubs = false,
  }) {
    final patch = conversion.graphPatch;
    final known = <String>{
      for (final title in existingTitles) normalizeTitle(title),
    };
    final nodesById = <String, MaterialPatchNode>{
      for (final node in patch.nodes) node.id: node,
    };

    final proposals = <MaterialIntakeProposal>[];
    final skipped = <MaterialIntakeSkip>[
      for (final item in patch.skipped)
        MaterialIntakeSkip(ref: item.item, reason: item.reason),
    ];

    if (includeTopicHubs) {
      for (final node in patch.nodes) {
        if (!node.id.contains(topicIdMarker)) {
          continue;
        }
        final title = _clip(node.name.trim(), titleMaxLength);
        proposals.add(MaterialIntakeProposal(
          id: 'kp:${node.id}',
          kind: MaterialIntakeKind.knowledgePoint,
          title: title,
          nodeId: node.id,
          body: '主题分组（材料里写了 `#${envelope.topic ?? ''}`）',
          why: '这一轮显式要求把主题也当知识点（默认不建：主题分组不落成知识点，'
              '只把每个节点连到 hub）',
          exists: known.contains(normalizeTitle(title)),
          evidence: _evidenceOf(envelope, null, '主题分组', null),
        ));
      }
    }

    for (final item in conversion.standardItems) {
      if (!item.inGraph || item.nodeId == null) {
        continue;
      }
      final node = nodesById[item.nodeId!];
      // 上游的 `name` 已经截到 80；用节点名而不是 item.text，是为了和"图里叫什么"一致。
      final title = _clip((node?.name ?? item.text).trim(), titleMaxLength);
      proposals.add(MaterialIntakeProposal(
        id: 'kp:${item.nodeId}',
        kind: MaterialIntakeKind.knowledgePoint,
        title: title,
        nodeId: item.nodeId,
        body: _bodyOf(item, envelope),
        why: _whyOf(item),
        exists: known.contains(normalizeTitle(title)),
        evidence: _evidenceOf(
            envelope, item.page, _regionOf(item.page), item.marginNote),
      ));
    }

    for (final edge in patch.edges) {
      if (edge.why == 'topic' && !includeTopicHubs) {
        skipped.add(MaterialIntakeSkip(
          ref: edge.id,
          reason: '主题分组默认不建：它会把每个节点都连到同一个 hub，'
              '而"这批材料属于同一主题"通常看一眼标题就够了；要建就打开 includeTopicHubs',
        ));
        continue;
      }
      final from = nodesById[edge.from];
      final to = nodesById[edge.to];
      proposals.add(MaterialIntakeProposal(
        id: 'edge:${edge.id}',
        kind: MaterialIntakeKind.connection,
        title: '${_clip(from?.name ?? edge.from, labelMaxLength)} → '
            '${_clip(to?.name ?? edge.to, labelMaxLength)}',
        from: edge.from,
        to: edge.to,
        ls: edge.ls,
        origin: edge.why,
        body: '',
        why: _edgeWhyOf(edge.why),
        // 连接的幂等要靠边 id（上游内容确定）；库里的去重留给写入方，这里不假装知道。
        exists: false,
        evidence: _evidenceOf(envelope, null, '边：${edge.why}', null),
      ));
    }

    return MaterialIntakePlan(
      batchId: envelope.batchId,
      topic: envelope.topic,
      sourceRef: _sourceOf(envelope),
      proposals: proposals,
      skipped: skipped,
    );
  }

  /// 标题归一：去首尾空白、把连续空白压成一个、转小写。
  ///
  /// 刻意**不做** NFC 归一（与 [MaterialIngest] 同一条理由：标准库没有这个函数），
  /// 也刻意不删标点 —— "同名"是给用户看的判断，宽松到把 `resilient` 和 `resilience`
  /// 当同一个会更糟。
  static String normalizeTitle(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String? _sourceOf(MaterialEnvelope envelope) {
    final source = envelope.source;
    if (source == null) {
      return null;
    }
    return source.material ?? source.primaryRef;
  }

  static MaterialIntakeEvidence _evidenceOf(
    MaterialEnvelope envelope,
    double? page,
    String region,
    String? quote,
  ) =>
      MaterialIntakeEvidence(
        source: _sourceOf(envelope),
        page: page,
        region: region,
        quote: quote,
        batchId: envelope.batchId,
      );

  static String _regionOf(double? page) =>
      page == null ? '第 ? 页' : '第 ${MaterialIngest.integral(page)} 页';

  static String _whyOf(MaterialStandardItem item) {
    final role = roleLabels[item.role] ?? item.role;
    final buffer = StringBuffer('材料里标了「${item.markWritten}」（$role）');
    if (item.modifiers.contains('star')) {
      buffer.write('，★ 高优先级');
    }
    if (item.uncertain) {
      buffer.write('；模型对这一条拿不准，先按"待核对"收下');
    }
    if (item.duplicateOf != null) {
      buffer.write('；与 ${item.duplicateOf} 重复，复用同一个节点');
    }
    return buffer.toString();
  }

  static String _edgeWhyOf(String why) => switch (why) {
        'contains' => '句子里包含它（子句 → 词）',
        'produce' => '用它造出这句话（词 → 句）',
        'topic' => '主题分组（默认不建）',
        _ => why,
      };

  /// 知识点的正文：释义 / 音标 / 原文 / 出处。空行不写（不给库塞空壳）。
  static String _bodyOf(MaterialStandardItem item, MaterialEnvelope envelope) {
    final lines = <String>[];
    final meaning = item.meaning?.trim();
    if (meaning != null && meaning.isNotEmpty) {
      final check = item.meaningSource == 'ai' ? '（待核对）' : '';
      lines.add('释义：$meaning$check');
    }
    final ipa = item.ipa?.trim();
    if (ipa != null && ipa.isNotEmpty) {
      lines.add('音标：$ipa');
    }
    final context = item.context?.trim();
    if (context != null && context.isNotEmpty) {
      lines.add('原文：$context');
    }
    final source = _sourceOf(envelope);
    final from = source == null ? '' : '$source，';
    lines.add('出处：$from${_regionOf(item.page)}'
        '${item.marginNote == null ? '' : '，页边：${item.marginNote}'}');
    return lines.join('\n');
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
