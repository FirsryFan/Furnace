/// 材料摄取 INGEST 第 ③ 步的 Dart 版：`mindnet.material/1` → 标准清单 + 图补丁 + `mindnet.run/1`。
///
/// 契约在外部只读文档 `E:\Document\MindNet\docs\INGEST.md`（§2 数据流、§3 清单格式、
/// §4 转化产物、§5 三步法），参考实现是 `E:\Document\MindNet\src\ingest.js`。这一层是
/// **确定性纯函数**：同一份信封进去，同样的清单/图/请求出来 —— 不读照片、不调模型、
/// 不猜内容（记号由人在页边写，判读由上游模型做）。
///
/// 产出三样（INGEST §4 说的"正产品"）：
///  * [MaterialStandardItem]：规范后的条目清单（记号、角色、出处、含义、是否进图、节点 id）；
///  * [MaterialGraphPatch]：进知识图的节点与边（先节点后边）；
///  * [MaterialRunRequest]：可直接交给 MindNet `tools/io_run.js` 的 `mindnet.run/1`。
///    INGEST §4 里的 `cards.json` / `tts.tsv` / `anki/` 是**可选的呈现层**（"本步之外，
///    想要卡片就拿走"），本层不做 —— 本仓库的卡片通路另有入口（`intake/handwriting_proposals.dart`）。
///
/// 三条不变量（INGEST §5）：原始材料是权威（手写只用于消歧）；AI 的每个字段都能追回
/// "哪一页哪一行"（所以每条动作都带 `evidence`）；不认识的输入不会被丢掉，只会被标成"待归类"。
///
/// 与 JS 参考实现**有意不同**的五处，各自有测试钉住（不假装逐字节相同）：
///  1. `evidence.quote` 真的带上页边那一行：JS 的节点 `meta` 里没有 `margin_note`，
///     所以它的 `quote` **恒为 null**；这一层把 `margin_note` 带进 `meta` 并让 `quote` 用它。
///     （`meta` 不是模型状态：MindNet 的 `Node.from_object` 根本不读这个键，加它不破坏协议。）
///  2. 主题 hub 的 `region`：JS 对没有 `page` 的 hub 会插值出字符串 `第 undefined 页`，
///     这里写 `第 ? 页`。
///  3. 不做 NFC 归一化：JS 的 `normalize` 先 `.normalize('NFC')`，而 Dart 标准库没有这个函数、
///     `pubspec.yaml` 里也没有相应依赖。输入若已是 NFC（绝大多数情形），slug 与 hash 与 JS 逐位相同。
///  4. 数字强制转换按 JS 的 `Number()` 语义实现（见 [MaterialIngest.numberOrNull]），
///     但 `[]` / `{}` 这类在 JS 里会得到 0 / NaN 的输入在这里一律算"不是数字"。
///  5. 汇总文案不报"几张卡"：JS 的 `summary.text` 会写 `/ C 张卡`，而卡片是 INGEST §4 的
///     可选呈现层、本层不产出，所以这里只报"几条 → 几节点 / 几边 · 几动作 · 几告警"。
///
/// 对拍：`app/tool/ingest_parity_reference.cjs` → `dart run app/tool/ingest_dump.dart` →
/// `node app/tool/ingest_parity_compare.cjs`（需要外部 MindNet 检出与 node）。第三步会把上面
/// 五处差异规约掉再逐字段比较，实测在示例信封上是 `PARITY OK`：6 节点 / 7 边 / 14 动作 / 6 条目。
library;

/// 材料信封或请求不合法时抛出；文案与 `src/ingest.js` 对齐（人话 + 第几条）。
class MaterialIngestException implements Exception {
  const MaterialIngestException(this.message);

  /// 给人看的原因。
  final String message;

  @override
  String toString() => message;
}

/// 信封 `marks` 块里对某个自定义记号的声明（`{role, means}`，或只写一个角色名）。
class DeclaredMark {
  const DeclaredMark({this.role, this.means});

  /// 声明它扮演什么角色（`item` / `method` / `passage` / 自定义）。
  final String? role;

  /// 这个记号是什么意思（原样进 `mark_means`）。
  final String? means;
}

/// 材料出处（照片、书名、录音…）。
class MaterialSource {
  const MaterialSource({
    this.kind,
    this.refs = const <String>[],
    this.material,
    this.capturedAt,
  });

  factory MaterialSource.fromJson(Map<String, Object?> json) {
    final refs = json['refs'];
    return MaterialSource(
      kind: json['kind'] == null ? null : '${json['kind']}',
      refs: refs is List
          ? <String>[for (final ref in refs) '$ref']
          : const <String>[],
      material: json['material'] == null ? null : '${json['material']}',
      capturedAt: json['captured_at'] == null ? null : '${json['captured_at']}',
    );
  }

  final String? kind;
  final List<String> refs;
  final String? material;
  final String? capturedAt;

  /// `evidence.source` 用的那一个出处：`refs` 的第一项（JS 也只取 `refs[0]`）。
  String? get primaryRef => refs.isEmpty ? null : refs.first;

  Map<String, Object?> toJson() => <String, Object?>{
        if (kind != null) 'kind': kind,
        'refs': refs,
        if (material != null) 'material': material,
        if (capturedAt != null) 'captured_at': capturedAt,
      };
}

/// 信封里的一条 item（AI 从照片上照抄下来的一行）。
class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.mark,
    required this.text,
    this.isObject = true,
    this.marginNote,
    this.context,
    this.meaning,
    this.meaningSource,
    this.ipa,
    this.role,
    this.markMeans,
    this.priority,
    this.produce,
    this.inferredFromLine = false,
    this.markedBy,
    this.dotPosition,
    this.region,
    this.uncertain = false,
    this.conflict = false,
    this.conflictDetail,
    this.duplicateOf,
    this.page,
    this.line,
    this.lines,
    this.contains,
    this.containsNotArray = false,
    this.modified,
    this.modifiedNotArray = false,
  });

  /// 解析一条 item。**不做校验**（校验在 [MaterialIngest.validate] 里按顺序报错）；
  /// 非对象的那一条会留下 [isObject] = false，好让校验说出"第 N 条 item 不是对象"。
  factory MaterialItem.fromJson(Object? raw, int index) {
    if (raw is! Map) {
      return const MaterialItem(
        id: '',
        mark: null,
        text: '',
        isObject: false,
      );
    }
    final json = raw.cast<String, Object?>();
    final lines = json['lines'];
    final contains = json['contains'];
    final modified = json['modified'];
    return MaterialItem(
      id: json['id'] == null ? '' : '${json['id']}',
      mark: json['mark'],
      text: json['text'] == null ? '' : '${json['text']}',
      marginNote: json['margin_note'] == null ? null : '${json['margin_note']}',
      context: json['context'] == null ? null : '${json['context']}',
      meaning: json['meaning'] == null ? null : '${json['meaning']}',
      meaningSource:
          json['meaning_source'] == null ? null : '${json['meaning_source']}',
      ipa: json['ipa'] == null ? null : '${json['ipa']}',
      role: json['role'] == null ? null : '${json['role']}',
      markMeans: json['mark_means'] == null ? null : '${json['mark_means']}',
      priority: json['priority'],
      produce: json['produce'],
      inferredFromLine: json['inferred_from_line'] == true,
      markedBy: json['marked_by'] == null ? null : '${json['marked_by']}',
      dotPosition:
          json['dot_position'] == null ? null : '${json['dot_position']}',
      region: json['region'] == null ? null : '${json['region']}',
      uncertain: raw['uncertain'] == null
          ? false
          : MaterialIngest.isTruthy(raw['uncertain']),
      conflict: json['conflict'] == null
          ? false
          : MaterialIngest.isTruthy(json['conflict']),
      conflictDetail:
          json['conflict_detail'] == null ? null : '${json['conflict_detail']}',
      duplicateOf:
          json['duplicate_of'] == null ? null : '${json['duplicate_of']}',
      // `page`/`line` 缺席与显式 `null` 在 JS 里结果不同（`Number(undefined)` 是 NaN，
      // `Number(null)` 是 0），所以这里也分开：缺席 → null（校验会报"缺少"），显式 null → 0。
      page: json.containsKey('page')
          ? MaterialIngest.numberOrNull(json['page'])
          : null,
      line: json.containsKey('line')
          ? MaterialIngest.numberOrNull(json['line'])
          : null,
      lines: lines is List
          ? <double?>[
              for (final value in lines) MaterialIngest.numberOrNull(value)
            ].whereType<double>().toList(growable: false)
          : null,
      contains: contains is List
          ? <String>[for (final ref in contains) '$ref']
          : null,
      containsNotArray: contains != null && contains is! List,
      modified: modified is List
          ? <String>[for (final value in modified) '$value']
          : null,
      modifiedNotArray: modified != null && modified is! List,
    );
  }

  /// 信封里的局部 id（`m1`…），只在本批次内有意义。
  final String id;

  /// 你写在页边的那一个记号（原样保留：自定义记号也算）。
  final Object? mark;

  /// 正文里的那一份（**以正文为准**，页边只用于消歧）。
  final String text;

  /// 这一条在 JSON 里是不是对象（false 时只有校验能救它）。
  final bool isObject;

  final String? marginNote;
  final String? context;
  final String? meaning;
  final String? meaningSource;
  final String? ipa;

  /// 条目级 `role`：优先级最高，直接决定它去哪。
  final String? role;

  final String? markMeans;
  final Object? priority;
  final Object? produce;
  final bool inferredFromLine;
  final String? markedBy;
  final String? dotPosition;
  final String? region;
  final bool uncertain;
  final bool conflict;
  final String? conflictDetail;
  final String? duplicateOf;
  final double? page;
  final double? line;
  final List<double>? lines;
  final List<String>? contains;

  /// `contains` 给了但不是数组（JS 会报错，这里也必须报，不能默默当成没有）。
  final bool containsNotArray;
  final List<String>? modified;

  /// `modified` 给了但不是数组（同上）。
  final bool modifiedNotArray;
}

/// 一份材料信封 `mindnet.material/1`。
class MaterialEnvelope {
  const MaterialEnvelope({
    this.protocol,
    this.batchId = '',
    this.source,
    this.topic,
    this.language,
    this.marks = const <String, Object?>{},
    this.items = const <MaterialItem>[],
  });

  factory MaterialEnvelope.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    final marks = json['marks'];
    final source = json['source'];
    return MaterialEnvelope(
      protocol: json['protocol'],
      batchId: json['batch_id'] == null ? '' : '${json['batch_id']}',
      source: source is Map
          ? MaterialSource.fromJson(source.cast<String, Object?>())
          : null,
      topic: json['topic'] == null ? null : '${json['topic']}',
      language: json['language'] == null ? null : '${json['language']}',
      marks: marks is Map
          ? marks.cast<String, Object?>()
          : const <String, Object?>{},
      items: rawItems is List
          ? <MaterialItem>[
              for (var i = 0; i < rawItems.length; i += 1)
                MaterialItem.fromJson(rawItems[i], i),
            ]
          : const <MaterialItem>[],
    );
  }

  final Object? protocol;
  final String batchId;
  final MaterialSource? source;
  final String? topic;
  final String? language;
  final Map<String, Object?> marks;
  final List<MaterialItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocol': protocol,
        'batch_id': batchId,
        if (source != null) 'source': source!.toJson(),
        if (topic != null) 'topic': topic,
        if (language != null) 'language': language,
        if (marks.isNotEmpty) 'marks': marks,
        'items': <Object?>[
          for (final item in items)
            <String, Object?>{
              'id': item.id,
              'mark': item.mark,
              'text': item.text,
              if (item.marginNote != null) 'margin_note': item.marginNote,
              if (item.context != null) 'context': item.context,
              if (item.meaning != null) 'meaning': item.meaning,
              if (item.meaningSource != null)
                'meaning_source': item.meaningSource,
              if (item.ipa != null) 'ipa': item.ipa,
              if (item.role != null) 'role': item.role,
              if (item.markMeans != null) 'mark_means': item.markMeans,
              if (item.page != null) 'page': MaterialIngest.integral(item.page),
              if (item.line != null) 'line': MaterialIngest.integral(item.line),
              if (item.lines != null)
                'lines': <Object?>[
                  for (final value in item.lines!)
                    MaterialIngest.integral(value),
                ],
              if (item.contains != null) 'contains': item.contains,
              if (item.modified != null) 'modified': item.modified,
              if (item.inferredFromLine) 'inferred_from_line': true,
              if (item.markedBy != null) 'marked_by': item.markedBy,
              if (item.dotPosition != null) 'dot_position': item.dotPosition,
              if (item.region != null) 'region': item.region,
              if (item.uncertain) 'uncertain': true,
              if (item.conflict) 'conflict': true,
              if (item.conflictDetail != null)
                'conflict_detail': item.conflictDetail,
              if (item.duplicateOf != null) 'duplicate_of': item.duplicateOf,
            },
        ],
      };
}

/// 校验时说的一句话（告警不阻止入库，见 INGEST §3.1「只是记录」）。
class MaterialWarning {
  const MaterialWarning({
    required this.item,
    required this.kind,
    required this.message,
  });

  final String item;
  final String kind;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'item': item,
        'kind': kind,
        'message': message,
      };

  @override
  String toString() => '[$kind] $item：$message';
}

/// [MaterialIngest.validate] 的结果：告警列表（不合法会直接抛，不会走到这里）。
class MaterialValidation {
  const MaterialValidation({required this.warnings});

  final List<MaterialWarning> warnings;
}

/// 图补丁里的一个节点。
class MaterialPatchNode {
  const MaterialPatchNode({
    required this.id,
    required this.name,
    required this.type,
    required this.meta,
  });

  /// 内容确定的节点 id（`en::w::resilient`），同一页拍两次得到同一个。
  final String id;

  /// 给图看的人话名字（正文前 80 字）。
  final String name;

  /// `knowledge` / `logic` / `technique`。
  final String type;

  /// 材料元数据（不是模型状态）：记号、角色、释义、出处、页码…。
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'type': type,
        'meta': meta,
      };
}

/// 图补丁里的一条边。
class MaterialPatchEdge {
  const MaterialPatchEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.ls,
    required this.why,
  });

  final String id;
  final String from;
  final String to;

  /// 链接强度（**未标定**，见 INGEST §3.1 与 [MaterialIngest.lsTopicToItem]）。
  final double ls;

  /// `contains` / `produce` / `topic`。
  final String why;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'from': from,
        'to': to,
        'ls': MaterialIngest.integral(ls),
        'why': why,
      };
}

/// 没进图的条目（`question` / `known` / `note` / `other` / 重复项）与原因。
class MaterialSkippedItem {
  const MaterialSkippedItem({
    required this.item,
    required this.mark,
    required this.role,
    required this.reason,
  });

  final String item;
  final String? mark;
  final String role;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'item': item,
        'mark': mark,
        'role': role,
        'reason': reason,
      };
}

/// 一次材料 → 图的补丁：节点、边、被跳过的条目。
class MaterialGraphPatch {
  const MaterialGraphPatch({
    required this.nodes,
    required this.edges,
    required this.skipped,
  });

  final List<MaterialPatchNode> nodes;
  final List<MaterialPatchEdge> edges;
  final List<MaterialSkippedItem> skipped;

  Map<String, Object?> toJson() => <String, Object?>{
        'nodes': <Object?>[for (final node in nodes) node.toJson()],
        'edges': <Object?>[for (final edge in edges) edge.toJson()],
        'skipped': <Object?>[for (final skipped in skipped) skipped.toJson()],
      };
}

/// 标准清单里的一条（本步的**正产品**：谁想拿它做什么都行）。
class MaterialStandardItem {
  const MaterialStandardItem({
    required this.id,
    required this.mark,
    required this.markWritten,
    required this.markMeans,
    required this.customMark,
    required this.role,
    required this.roleKnown,
    required this.inGraph,
    required this.nodeId,
    required this.text,
    required this.marginNote,
    required this.meaning,
    required this.meaningSource,
    required this.ipa,
    required this.context,
    required this.page,
    required this.line,
    required this.lines,
    required this.contains,
    required this.modifiers,
    required this.scope,
    required this.uncertain,
    required this.duplicateOf,
  });

  final String id;

  /// 规范化后的记号代号（`W` / `S` / `T` / `N` / `OK`，自定义记号原样）。
  final String mark;

  /// 你写的那个字（`词` / `句` / …）。
  final String markWritten;
  final String? markMeans;
  final bool customMark;
  final String role;
  final bool roleKnown;
  final bool inGraph;
  final String? nodeId;
  final String text;
  final String? marginNote;
  final String? meaning;
  final String? meaningSource;
  final String? ipa;
  final String? context;
  final double? page;
  final double? line;
  final List<double>? lines;
  final List<String> contains;
  final List<String> modifiers;

  /// `from_line`（这行只有一处要记）/ `dot`（用点子标的）/ `margin`（抄了）。
  final String scope;
  final bool uncertain;
  final String? duplicateOf;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'mark': mark,
        'mark_written': markWritten,
        'mark_means': markMeans,
        'custom_mark': customMark,
        'role': role,
        'role_known': roleKnown,
        'in_graph': inGraph,
        'node_id': nodeId,
        'text': text,
        'margin_note': marginNote,
        'meaning': meaning,
        'meaning_source': meaningSource,
        'ipa': ipa,
        'context': context,
        'page': MaterialIngest.integral(page),
        'line': MaterialIngest.integral(line),
        'lines': lines == null
            ? null
            : <Object?>[
                for (final value in lines!) MaterialIngest.integral(value)
              ],
        'contains': contains,
        'modifiers': modifiers,
        'scope': scope,
        'uncertain': uncertain,
        'duplicate_of': duplicateOf,
      };
}

/// `mindnet.run/1` 里的一条动作。
class MaterialRunAction {
  const MaterialRunAction({
    required this.kind,
    this.node,
    this.edge,
    this.targets,
    this.starts,
    this.modelHours,
    this.wall,
    this.confidence,
    this.evidence,
  });

  final String kind;

  /// `knowledge` 的新节点（与 [edge] 二选一）。
  final Map<String, Object?>? node;

  /// `knowledge` 的新边。
  final Map<String, Object?>? edge;

  /// `goal` 的目标节点。
  final List<String>? targets;

  /// `goal` 的起点（沿用扩散起点时为 null）。
  final List<String>? starts;

  /// 时间基：模型小时（Unix 纪元起算的小时数，见 `MindNetProtocol.clockUnit`）。
  final double? modelHours;
  final String? wall;
  final double? confidence;

  /// 出处：`source` / `region` / `quote` / `batch_id`（"查得回去"的那一半）。
  final Map<String, Object?>? evidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        if (node != null) 'node': node,
        if (edge != null) 'edge': edge,
        if (targets != null) 'targets': targets,
        if (starts != null) 'starts': starts,
        'at': <String, Object?>{
          if (modelHours != null)
            'model_hours': MaterialIngest.integral(modelHours),
          if (wall != null) 'wall': wall,
        },
        if (confidence != null) 'confidence': confidence,
        if (evidence != null) 'evidence': evidence,
      };
}

/// `mindnet.run/1` 的时间块。
class MaterialRunTime {
  const MaterialRunTime({required this.modelHours, this.wall});

  final double modelHours;
  final String? wall;

  Map<String, Object?> toJson() => <String, Object?>{
        'model_hours': MaterialIngest.integral(modelHours),
        if (wall != null) 'wall': wall,
      };
}

/// 一份 `mindnet.run/1` 请求。
class MaterialRunRequest {
  const MaterialRunRequest({
    this.protocol = MaterialIngest.runProtocol,
    required this.runId,
    required this.time,
    required this.actions,
    this.meta = const <String, Object?>{},
  });

  factory MaterialRunRequest.fromJson(Map<String, Object?> json) {
    final time = json['time'];
    final actions = json['actions'];
    final meta = json['meta'];
    return MaterialRunRequest(
      protocol: json['protocol'],
      runId: json['run_id'] == null ? '' : '${json['run_id']}',
      time: MaterialRunTime(
        modelHours: time is Map
            ? (MaterialIngest.numberOrNull(time['model_hours']) ?? double.nan)
            : double.nan,
        wall: time is Map && time['wall'] != null ? '${time['wall']}' : null,
      ),
      actions: actions is List
          ? <MaterialRunAction>[
              for (final action in actions)
                if (action is Map)
                  MaterialRunAction(
                    kind: action['kind'] == null ? '' : '${action['kind']}',
                    node: action['node'] is Map
                        ? (action['node'] as Map).cast<String, Object?>()
                        : null,
                    edge: action['edge'] is Map
                        ? (action['edge'] as Map).cast<String, Object?>()
                        : null,
                    targets: action['targets'] is List
                        ? <String>[
                            for (final target in action['targets'] as List)
                              '$target',
                          ]
                        : null,
                    starts: action['starts'] is List
                        ? <String>[
                            for (final start in action['starts'] as List)
                              '$start',
                          ]
                        : null,
                    modelHours: action['at'] is Map
                        ? MaterialIngest.numberOrNull(
                            (action['at'] as Map)['model_hours'],
                          )
                        : null,
                    wall: action['at'] is Map &&
                            (action['at'] as Map)['wall'] != null
                        ? '${(action['at'] as Map)['wall']}'
                        : null,
                    confidence:
                        MaterialIngest.numberOrNull(action['confidence']),
                    evidence: action['evidence'] is Map
                        ? (action['evidence'] as Map).cast<String, Object?>()
                        : null,
                  ),
            ]
          : const <MaterialRunAction>[],
      meta: meta is Map
          ? meta.cast<String, Object?>()
          : const <String, Object?>{},
    );
  }

  final Object? protocol;
  final String runId;
  final MaterialRunTime time;
  final List<MaterialRunAction> actions;
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocol': protocol,
        'run_id': runId,
        'time': time.toJson(),
        'actions': <Object?>[for (final action in actions) action.toJson()],
        'meta': meta,
      };
}

/// `io_check` 类校验的结果（**结构 + 影子图端点自洽**，不预报机制路径）。
class MaterialRunCheck {
  const MaterialRunCheck({
    required this.ok,
    required this.errors,
    required this.previews,
    required this.evidenceCount,
  });

  final bool ok;
  final List<String> errors;
  final List<String> previews;
  final int evidenceCount;

  /// 人话单行（给工具/日志用）。
  String get summary => ok
      ? '✓ 请求合法：$evidenceCount/${previews.length} 条带 evidence'
      : '✗ 请求不合法：${errors.join('；')}';
}

/// 一次材料转化的全部产物。
class MaterialConversion {
  const MaterialConversion({
    required this.standardItems,
    required this.graphPatch,
    required this.runRequest,
    required this.warnings,
    required this.summary,
  });

  final List<MaterialStandardItem> standardItems;
  final MaterialGraphPatch graphPatch;
  final MaterialRunRequest runRequest;
  final List<MaterialWarning> warnings;
  final MaterialSummary summary;
}

/// 一行摘要（与 JS 的 `summary` 同义）。
class MaterialSummary {
  const MaterialSummary({
    required this.batchId,
    required this.items,
    required this.nodes,
    required this.edges,
    required this.actions,
    required this.skipped,
    required this.warnings,
    required this.text,
  });

  final String batchId;
  final int items;
  final int nodes;
  final int edges;
  final int actions;
  final int skipped;
  final int warnings;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
        'batch_id': batchId,
        'items': items,
        'nodes': nodes,
        'edges': edges,
        'actions': actions,
        'skipped': skipped,
        'warnings': warnings,
        'text': text,
      };
}

/// INGEST 第 ③ 步（确定性转化）的全部入口与常量。
abstract final class MaterialIngest {
  /// 材料信封的协议号。
  static const String materialProtocol = 'mindnet.material/1';

  /// 请求的协议号。
  static const String runProtocol = 'mindnet.run/1';

  /// 节点名人话截断长度（JS 用 `slice(0, 80)`）。
  static const int nodeNameLimit = 80;

  /// slug 截断长度（JS 用 `slice(0, 48)`）。
  static const int slugLimit = 48;

  /// 内置记号 → 角色（`ROLES` 决定它是"可复习单元"还是"整句"…）。
  static const Map<String, String> builtinRole = <String, String>{
    'W': 'item',
    'S': 'passage',
    'T': 'passage',
    'N': 'question',
    'OK': 'known',
  };

  /// 内部代号 → 你写在页边的那个字。
  static const Map<String, String> markWritten = <String, String>{
    'W': '词',
    'S': '句',
    'T': '段',
    'N': '问',
    'OK': '会',
  };

  /// 你写的记号 → 内部代号（字母、数字、别名都等价：写「词」还是 `W` 得到同一个节点 id）。
  static const Map<String, String> markAliases = <String, String>{
    '词': 'W',
    '单词': 'W',
    '搭': 'W',
    '搭配': 'W',
    '短语': 'W',
    '词组': 'W',
    'w': 'W',
    'W': 'W',
    'c': 'W',
    'C': 'W',
    '句': 'S',
    '句子': 'S',
    '句型': 'S',
    's': 'S',
    'S': 'S',
    '段': 'T',
    '段落': 'T',
    '语段': 'T',
    't': 'T',
    'T': 'T',
    '问': 'N',
    '疑问': 'N',
    'n': 'N',
    'N': 'N',
    '会': 'OK',
    '懂': 'OK',
    '已知': 'OK',
    'ok': 'OK',
    'OK': 'OK',
    '1': 'W',
    '2': 'W',
    '3': 'S',
    '4': 'T',
    '5': 'N',
  };

  /// 内置记号（`MARKS` 的键）：不在其中的都要当"自定义记号"处理。
  static const Set<String> builtinMarks = <String>{
    'W',
    'S',
    'T',
    'N',
    'OK',
  };

  /// 契约认识的角色（`ROLES`）；不认识的照样收下，只是不进图。
  static const List<String> knownRoles = <String>[
    'item',
    'passage',
    'question',
    'known',
    'method',
    'note',
    'other',
  ];

  /// 角色 → 图里的节点类型；null = 不进图。
  static const Map<String, String?> roleNodeType = <String, String?>{
    'item': 'knowledge',
    'passage': 'logic',
    'method': 'technique',
    'question': null,
    'known': null,
    'note': null,
    'other': null,
  };

  /// 内置修饰符；不认识的照样保留（只提示一句）。
  static const List<String> modifiers = <String>[
    'star',
    'produce',
    'needs_review',
    'exception',
  ];

  /// 边权默认值：**全部未标定**（INGEST 明说），只是"量级合理"。
  static const double lsSentenceToChunk = 0.6;
  static const double lsChunkToSentence = 0.6;
  static const double lsTopicToItem = 0.4;

  /// 动作类型（与 `src/io/run.js` 的 `ACTION_KINDS` 一致）。
  static const List<String> actionKinds = <String>[
    'review',
    'exposure',
    'knowledge',
    'goal',
    'time',
  ];

  // -------------------------------------------------------------- 文本与 id

  /// 规范化（只用于 id 与哈希，不动展示用的原文）。JS 还先做 NFC，见 library doc。
  static String normalizeText(Object? text) {
    final raw = text == null ? '' : '$text';
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  /// 稳定 slug：只留小写字母数字与中日韩字，其余折成 `-`；非拉丁字符退化为空时由 hash 兜底。
  static String slug(Object? text) {
    final s = normalizeText(text)
        .replaceAll(RegExp("[’']"), '')
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.length > slugLimit ? s.substring(0, slugLimit) : s;
  }

  /// 32 位 FNV-1a（JS 版注释写着"Dart 那边照抄 5 行"）：字符按 UTF-16 码元喂进去。
  static String hash8(Object? text) {
    var h = 0x811c9dc5;
    final s = normalizeText(text);
    for (var i = 0; i < s.length; i += 1) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// 把写出来的记号规范成内部代号；认不出来就原样返回（由角色决定去向，不报错）。
  static String? canonMark(Object? mark) {
    if (mark == null) {
      return null;
    }
    final key = '$mark'.trim();
    if (builtinMarks.contains(key)) {
      return key;
    }
    final alias = markAliases[key];
    if (alias != null) {
      return alias;
    }
    final upper = markAliases[key.toUpperCase()];
    if (upper != null) {
      return upper;
    }
    return key;
  }

  /// 反过来：内部代号 → 你写的那一个字（文档、提示词、报错文案用）。
  static String writtenMark(Object? mark) =>
      markWritten[canonMark(mark)] ?? '${mark ?? ''}';

  /// 是不是自定义记号（不在内置表里）。
  static bool isCustomMark(Object? mark) =>
      !builtinMarks.contains(canonMark(mark));

  /// 节点 id：内容确定 ⇒ 同一页拍两次不会重复建节点。
  ///
  /// 记号先规范成代号，所以写「词」还是 `W` 是同一个 id；自定义记号按**角色**归类
  /// （`en::method::…`），所以两个不同的自定义记号只要角色与内容一样，也只有一个节点。
  static String nodeId({
    Object? language,
    Object? mark,
    required Object? text,
    Object? role,
  }) {
    final lang = (language == null ? 'en' : '$language').toLowerCase();
    final canon = canonMark(mark) ?? 'x';
    final kind = builtinRole.containsKey(canon)
        ? canon.toLowerCase()
        : (role != null && knownRoles.contains(role) ? '$role' : 'x');
    final key = canon == 'S' || canon == 'T' ? hash8(text) : slug(text);
    return '$lang::$kind::${key.isEmpty ? hash8(text) : key}';
  }

  /// 主题 hub 的节点 id（`en::topic::travel`）。
  static String topicId({Object? language, required Object? topic}) =>
      '${(language == null ? 'en' : '$language').toLowerCase()}::topic::${slug(topic)}';

  // --------------------------------------------------------------- 数字工具

  /// JS `Number(x)` 的语义：`null`/`''` → 0，`true` → 1，数字串按十进制解析，
  /// 解析不出（含 `[]`/`{}` 这类）→ null（对应 JS 的 NaN）。
  static double? numberOrNull(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return 0;
      }
      return double.tryParse(trimmed);
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    return null;
  }

  /// JS 的真值判断（`!!x`）。
  static bool isTruthy(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0 && !value.isNaN;
    }
    if (value is String) {
      return value.isNotEmpty;
    }
    return true;
  }

  /// JS `Math.round(x * 1e6) / 1e6`。
  static double round6(double value) {
    if (!value.isFinite) {
      return value;
    }
    return (value * 1e6).round() / 1e6;
  }

  /// 整数就用 int 输出（JSON 里 `1` 而不是 `1.0`，与 JS 的字面量一致）。
  static Object? integral(double? value) {
    if (value == null) {
      return null;
    }
    if (value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return value;
  }

  // ----------------------------------------------------------------- 校验

  /// 信封里某个记号声明的角色/含义（`marks` 块，字符串或对象都收）。
  static DeclaredMark? declaredMark(MaterialEnvelope env, Object? mark) {
    if (env.marks.isEmpty) {
      return null;
    }
    final key = mark == null ? '' : '$mark';
    final canon = canonMark(mark);
    final raw = env.marks.containsKey(key)
        ? env.marks[key]
        : (canon == null ? null : env.marks[canon]);
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return DeclaredMark(role: raw);
    }
    if (raw is Map) {
      final role = raw['role'];
      final means = raw['means'];
      return DeclaredMark(
        role: role == null ? null : '$role',
        means: means == null ? null : '$means',
      );
    }
    return null;
  }

  /// 一条 item 的角色（顺序即优先级）：显式 `role` → 内置记号 → `marks` 声明 → `other`。
  static String resolveRole(MaterialItem item, MaterialEnvelope env) {
    final explicit = item.role;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final builtin = builtinRole[canonMark(item.mark)];
    if (builtin != null) {
      return builtin;
    }
    final declared = declaredMark(env, item.mark)?.role;
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    return 'other';
  }

  /// 修饰符集合：`modified` 原样 + `priority: "star"` / `produce: true` 两个旧写法。
  static List<String> modifiersOf(MaterialItem item) {
    final out = <String>{...?item.modified};
    if (item.priority == 'star') {
      out.add('star');
    }
    if (item.produce == true) {
      out.add('produce');
    }
    return out.toList(growable: false);
  }

  static bool _hasText(Object? value) =>
      value is String && value.trim().isNotEmpty;

  /// 校验材料信封：不合法就整份拒绝（与 IO 层同一原则：绝不半途生效）。
  static MaterialValidation validate(MaterialEnvelope env) {
    if (env.protocol != materialProtocol) {
      throw MaterialIngestException(
        '材料信封的 protocol 必须是 "$materialProtocol"，实际 ${env.protocol}',
      );
    }
    if (env.batchId.isEmpty) {
      throw const MaterialIngestException('材料信封缺少 batch_id（幂等键）');
    }
    if (env.items.isEmpty) {
      throw const MaterialIngestException('材料信封的 items 必须是非空数组');
    }

    final warnings = <MaterialWarning>[];
    final seen = <String, MaterialItem>{};
    final byText = <String, String>{};
    for (var i = 0; i < env.items.length; i += 1) {
      final item = env.items[i];
      final at = '第 ${i + 1} 条 item';
      if (!item.isObject) {
        throw MaterialIngestException('$at 不是对象');
      }
      if (item.id.isEmpty) {
        throw MaterialIngestException('$at 缺少 id');
      }
      if (seen.containsKey(item.id)) {
        throw MaterialIngestException('$at 的 id "${item.id}" 与前面的重复');
      }
      // 缺 mark ≠ 自定义记号：那是"根本没标"，属于上游漏填，必须报错。
      if (item.mark == null || '${item.mark}'.trim().isEmpty) {
        throw MaterialIngestException(
          '$at 缺少 mark（你写的那个记号）。记号可以自己发明，但不能空着',
        );
      }
      final written = writtenMark(item.mark);
      final role = resolveRole(item, env);
      // 记号认不出来**不报错**：按角色收下（默认 other），只提示一句。
      if (isCustomMark(item.mark) &&
          declaredMark(env, item.mark) == null &&
          (item.role == null || item.role!.isEmpty)) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'unknown-mark',
            message: '记号「$written」不在内置表里，也没有在 marks 块里声明 ⇒ 先按「未分类」收下'
                '（想让它进知识图，就声明 role: "item" / "method" / "passage"）',
          ),
        );
      } else if (isCustomMark(item.mark) && !knownRoles.contains(role)) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'custom-role',
            message: '自定义角色「$role」：按"不进图"处理，只留在标准输出里',
          ),
        );
      }
      if (item.text.trim().isEmpty) {
        throw MaterialIngestException('$at 缺少 text');
      }
      if (item.page == null) {
        throw MaterialIngestException('$at 缺少 page');
      }
      final hasLine =
          item.line != null || (item.lines != null && item.lines!.length == 2);
      if (!hasLine) {
        throw MaterialIngestException('$at 缺少 line 或 lines');
      }

      // 两条"省事通道"：页边没抄也能收，但必须**显式说明为什么**（不许 AI 偷偷猜）。
      final byDot = item.markedBy == 'dot';
      final needsMargin = role == 'item' || role == 'question';
      if (needsMargin &&
          !_hasText(item.marginNote) &&
          !item.inferredFromLine &&
          !byDot) {
        throw MaterialIngestException(
          '$at（$written）缺少 margin_note：页边照抄的那一份必须给出来；或者显式说明这行只有一处要记'
          '（inferred_from_line）／你是用点子标的（marked_by: "dot"）—— 见 docs/INGEST.md §1 §3.2',
        );
      }
      if (role == 'item' && !_hasText(item.context)) {
        throw MaterialIngestException('$at（$written）缺少 context：正文里的那一句是例句来源');
      }
      if (item.modifiedNotArray) {
        throw MaterialIngestException('$at 的 modified 必须是数组');
      }
      // `modified` 里不认识的修饰符照样保留，只标注一下（修饰符也是开放的）。
      for (final modifier in item.modified ?? const <String>[]) {
        if (!modifiers.contains(modifier)) {
          warnings.add(
            MaterialWarning(
              item: item.id,
              kind: 'custom-modifier',
              message: '自定义修饰符「$modifier」：原样保留，不参与自动处理',
            ),
          );
        }
      }
      final norm = normalizeText(item.text);
      if (byText.containsKey(norm) && item.duplicateOf == null) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'duplicate-text',
            message: '与 "${byText[norm]}" 文本相同（未标 duplicate_of）',
          ),
        );
      } else if (!byText.containsKey(norm)) {
        byText[norm] = item.id;
      }
      if (item.uncertain) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'uncertain',
            message: '上游标了不确定：${item.region ?? '（未给位置）'}',
          ),
        );
      }
      if (item.conflict) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'conflict',
            message: '页边与正文冲突：${item.conflictDetail ?? '（未给细节）'}',
          ),
        );
      }
      // 省事通道要被记录，便于事后核对"AI 有没有取错词"。
      if (item.inferredFromLine) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'inferred-scope',
            message: '页边没抄，按"这一行只有一处要记"取的正文内容',
          ),
        );
      }
      if (byDot) {
        warnings.add(
          MaterialWarning(
            item: item.id,
            kind: 'dot-mark',
            message: '按你标的点子取的正文内容：${item.dotPosition ?? '（未给位置描述）'}',
          ),
        );
      }
      seen[item.id] = item;
    }

    // contains 只能指向本批次内的 id。
    for (final item in env.items) {
      if (item.containsNotArray) {
        throw MaterialIngestException('item "${item.id}" 的 contains 必须是数组');
      }
      final contains = item.contains;
      if (contains == null) {
        continue;
      }
      for (final ref in contains) {
        if (!seen.containsKey(ref)) {
          throw MaterialIngestException(
            'item "${item.id}" 的 contains 指向不存在的 id "$ref"',
          );
        }
      }
    }

    return MaterialValidation(warnings: warnings);
  }

  // ---------------------------------------------------------------- 图补丁

  /// 材料 → 图补丁（节点 + 边）。顺序：先节点后边（边要求两端存在）。
  static MaterialGraphPatch graphPatch(MaterialEnvelope env) {
    validate(env);
    final lang = env.language ?? 'en';
    final nodes = <MaterialPatchNode>[];
    final edges = <MaterialPatchEdge>[];
    final skipped = <MaterialSkippedItem>[];
    final idOf = <String, String>{};

    for (final item in env.items) {
      final mark = canonMark(item.mark);
      final role = resolveRole(item, env);
      final declared = declaredMark(env, item.mark);
      final nodeType = roleNodeType[role];
      if (nodeType == null) {
        final why = role == 'question'
            ? '疑问不进图（先答复，再决定是否建节点）'
            : role == 'known'
                ? '标记为已知'
                : role == 'note'
                    ? '提醒/坑不进图（留在标准输出里；要进图就声明 role: "method" 或 "item"）'
                    : '角色「$role」不进图（先留在标准输出里）';
        skipped.add(
          MaterialSkippedItem(
              item: item.id, mark: mark, role: role, reason: why),
        );
        continue;
      }
      if (item.duplicateOf != null) {
        final existing = idOf[item.duplicateOf];
        if (existing != null) {
          idOf[item.id] = existing;
        }
        skipped.add(
          MaterialSkippedItem(
            item: item.id,
            mark: mark,
            role: role,
            reason: '与 ${item.duplicateOf} 重复',
          ),
        );
        continue;
      }
      final id = nodeId(
        language: lang,
        mark: mark,
        text: item.text,
        role: role,
      );
      idOf[item.id] = id;
      final modifiers = modifiersOf(item);
      nodes.add(
        MaterialPatchNode(
          id: id,
          name: item.text.length > nodeNameLimit
              ? item.text.substring(0, nodeNameLimit)
              : item.text,
          type: nodeType,
          // 这些不是模型状态，只是"材料元数据"，随节点名/权重一起带过去。
          meta: <String, Object?>{
            'mark': mark,
            'mark_written': markWritten[mark] ?? mark,
            'role': role,
            'custom_mark': isCustomMark(item.mark),
            'mark_means': declared?.means ?? item.markMeans,
            'meaning': item.meaning,
            'meaning_source': item.meaningSource,
            'ipa': item.ipa,
            'context': item.context,
            // 与 JS 的差异之一：`margin_note` 也带进 meta，好让 evidence.quote 有东西可用。
            'margin_note': item.marginNote,
            'source': env.source?.material,
            'page': item.page,
            'line': item.line ?? item.lines?.first,
            'tts_text': item.text,
            'modifiers': modifiers,
            'uncertain': item.uncertain,
          },
        ),
      );
    }

    // contains：听到整句要能听出这个词块。
    for (final item in env.items) {
      final contains = item.contains;
      if (contains == null) {
        continue;
      }
      final from = idOf[item.id];
      if (from == null) {
        continue;
      }
      for (final ref in contains) {
        final to = idOf[ref];
        if (to == null || to == from) {
          continue;
        }
        edges.add(
          MaterialPatchEdge(
            id: 'e_${from}__$to',
            from: from,
            to: to,
            ls: lsSentenceToChunk,
            why: 'contains',
          ),
        );
      }
    }

    // produce：想到它要能说出整句（反向边）。
    for (final item in env.items) {
      final mark = canonMark(item.mark);
      final modifiers = modifiersOf(item);
      if (!modifiers.contains('produce') || mark == 'S' || mark == 'T') {
        continue;
      }
      final from = idOf[item.id];
      if (from == null) {
        continue;
      }
      for (final parent in env.items) {
        if (parent.contains == null || !parent.contains!.contains(item.id)) {
          continue;
        }
        final to = idOf[parent.id];
        if (to == null) {
          continue;
        }
        edges.add(
          MaterialPatchEdge(
            id: 'e_${from}__$to',
            from: from,
            to: to,
            ls: lsChunkToSentence,
            why: 'produce',
          ),
        );
      }
    }

    // 主题 hub。
    if (_hasText(env.topic)) {
      final hub = topicId(language: lang, topic: env.topic);
      nodes.add(
        MaterialPatchNode(
          id: hub,
          name: '#${env.topic}',
          type: 'knowledge',
          meta: <String, Object?>{
            'mark': 'TOPIC',
            'source': env.source?.material,
            'tts_text': null,
            'modifiers': <String>[],
            'uncertain': false,
          },
        ),
      );
      for (final node in nodes) {
        if (node.id == hub) {
          continue;
        }
        edges.add(
          MaterialPatchEdge(
            id: 'e_${hub}__${node.id}',
            from: hub,
            to: node.id,
            ls: lsTopicToItem,
            why: 'topic',
          ),
        );
      }
    }

    return MaterialGraphPatch(nodes: nodes, edges: edges, skipped: skipped);
  }

  // -------------------------------------------------------------- 标准清单

  /// 标准输出：把信封规范成一份**中立的条目清单**（本步骤的正产品）。
  static List<MaterialStandardItem> standardItems(MaterialEnvelope env) {
    validate(env);
    final lang = env.language ?? 'en';
    return <MaterialStandardItem>[
      for (final item in env.items)
        () {
          final mark = canonMark(item.mark) ?? '';
          final role = resolveRole(item, env);
          final declared = declaredMark(env, item.mark);
          final inGraph = roleNodeType[role] != null;
          return MaterialStandardItem(
            id: item.id,
            mark: mark,
            markWritten: markWritten[mark] ?? mark,
            markMeans: declared?.means ?? item.markMeans,
            customMark: isCustomMark(item.mark),
            role: role,
            roleKnown: knownRoles.contains(role),
            inGraph: inGraph,
            nodeId: inGraph
                ? nodeId(
                    language: lang,
                    mark: mark,
                    text: item.text,
                    role: role,
                  )
                : null,
            text: item.text,
            marginNote: item.marginNote,
            meaning: item.meaning,
            meaningSource: item.meaningSource,
            ipa: item.ipa,
            context: item.context,
            page: item.page,
            line: item.line ?? item.lines?.first,
            lines: item.lines,
            contains: item.contains ?? const <String>[],
            modifiers: modifiersOf(item),
            scope: item.inferredFromLine
                ? 'from_line'
                : (item.markedBy == 'dot' ? 'dot' : 'margin'),
            uncertain: item.uncertain,
            duplicateOf: item.duplicateOf,
          );
        }(),
    ];
  }

  // ------------------------------------------------------------------ 请求

  /// 材料 → `mindnet.run/1` 请求（`knowledge` 动作，先节点后边；`★` 条目额外设为目标）。
  ///
  /// [nowHours] 必填：模型时间基是"小时"，不许默默用"现在"（`docs/IO_PROTOCOL.md` §3.3）。
  static MaterialRunRequest runRequest(
    MaterialEnvelope env, {
    required double nowHours,
    List<String>? starts,
    String? runId,
    bool includeTopicGoal = true,
  }) {
    validate(env);
    if (!nowHours.isFinite) {
      throw const MaterialIngestException(
        'toRunRequest 需要 now_hours（模型时间基；不许默默用"现在"，见 docs/IO_PROTOCOL.md §3.3）',
      );
    }
    final patch = graphPatch(env);
    final sourceRef = env.source?.primaryRef;
    final actions = <MaterialRunAction>[];

    for (final node in patch.nodes) {
      // 注意这里不能用 numberOrNull：JS 的 `Number(undefined)` 是 NaN、`Number(null)` 是 0，
      // 而 hub 的 meta 里根本没有 page 这个键 —— 只有真是数字时才写页码。
      final rawPage = node.meta['page'];
      final pageLabel =
          rawPage is num ? '${integral(rawPage.toDouble())}' : '?';
      actions.add(
        MaterialRunAction(
          kind: 'knowledge',
          node: <String, Object?>{
            'id': node.id,
            'name': node.name,
            'type': node.type,
          },
          modelHours: round6(nowHours),
          confidence: node.meta['uncertain'] == true ? 0.5 : 0.9,
          evidence: <String, Object?>{
            'source': sourceRef,
            // 与 JS 的差异之二：hub 没有 page，JS 会写成 `第 undefined 页`，这里写 `第 ? 页`。
            'region': '第 $pageLabel 页',
            // 与 JS 的差异之一：JS 这里恒为 null（它的 meta 没有 margin_note）。
            'quote': node.meta['margin_note'],
            'batch_id': env.batchId,
          },
        ),
      );
    }
    for (final edge in patch.edges) {
      actions.add(
        MaterialRunAction(
          kind: 'knowledge',
          // 注意：动作里的边只有 id/from/to/ls 四个键（`why` 进 region，不进契约；
          // `mindnet.run/1` 的 Edge 没有这个字段，多给一个键就不再是逐字段对拍了）。
          edge: <String, Object?>{
            'id': edge.id,
            'from': edge.from,
            'to': edge.to,
            'ls': edge.ls,
          },
          modelHours: round6(nowHours),
          confidence: 0.8,
          evidence: <String, Object?>{
            'source': sourceRef,
            'region': '边：${edge.why}',
            'batch_id': env.batchId,
          },
        ),
      );
    }

    // ★ 条目设为目标：目标偏置会优先照亮它们（目标自身不吃偏置，见 context.goal）。
    final starred = <String>[
      for (final node in patch.nodes)
        if ((node.meta['modifiers'] as List?)?.contains('star') ?? false)
          node.id,
    ];
    if (starred.isNotEmpty && includeTopicGoal) {
      actions.add(
        MaterialRunAction(
          kind: 'goal',
          targets: starred,
          starts: (starts == null || starts.isEmpty) ? null : starts,
          modelHours: round6(nowHours),
          evidence: <String, Object?>{
            'region': '★ 高优先级条目',
            'batch_id': env.batchId,
          },
        ),
      );
    }

    return MaterialRunRequest(
      runId: runId ?? 'ingest-${env.batchId}',
      time: MaterialRunTime(
        modelHours: round6(nowHours),
        wall: env.source?.capturedAt,
      ),
      actions: actions,
      meta: <String, Object?>{
        'source': 'ingest',
        'note':
            '材料批次 ${env.batchId}：${patch.nodes.length} 节点 / ${patch.edges.length} 边',
      },
    );
  }

  /// 一次产出三样正产品 + 告警 + 摘要。
  static MaterialConversion convert(
    MaterialEnvelope env, {
    required double nowHours,
    List<String>? starts,
    String? runId,
    bool includeTopicGoal = true,
  }) {
    final validation = validate(env);
    final patch = graphPatch(env);
    final request = runRequest(
      env,
      nowHours: nowHours,
      starts: starts,
      runId: runId,
      includeTopicGoal: includeTopicGoal,
    );
    final items = standardItems(env);
    final text =
        '批次 ${env.batchId}：${env.items.length} 条 → ${patch.nodes.length} 节点 / '
        '${patch.edges.length} 边 · ${request.actions.length} 条动作 · '
        '${validation.warnings.length} 条告警';
    return MaterialConversion(
      standardItems: items,
      graphPatch: patch,
      runRequest: request,
      warnings: validation.warnings,
      summary: MaterialSummary(
        batchId: env.batchId,
        items: env.items.length,
        nodes: patch.nodes.length,
        edges: patch.edges.length,
        actions: request.actions.length,
        skipped: patch.skipped.length,
        warnings: validation.warnings.length,
        text: text,
      ),
    );
  }

  // -------------------------------------------------- `io_check` 类结构校验

  /// 请求自检（**只校验、不执行**）：对齐 `tools/io_check.js` + `src/io/run.js` 的
  /// `validateRequest`，覆盖协议/幂等键/时间基/动作字段/影子图端点自洽。
  ///
  /// 影子图是这份校验的关键：同一份请求里"先建节点、再建边、再把它们设为目标"是
  /// 材料批量入库的正常形态，所以本批次将要新建的节点/边算作"已存在"
  /// （JS 源码里写着"实测踩到过"）。[existingNodeIds] / [existingEdgeIds] 是库里已有的。
  ///
  /// 这里**不预报机制路径**（JS 的 `preview` 会打印每条动作落到哪条机制）——
  /// 那需要引擎，属于 MindNet 侧的事。
  static MaterialRunCheck checkRunRequest(
    MaterialRunRequest request, {
    Set<String> existingNodeIds = const <String>{},
    Set<String> existingEdgeIds = const <String>{},
  }) {
    final errors = <String>[];
    final previews = <String>[];
    var evidenceCount = 0;

    if (request.protocol != runProtocol) {
      errors.add('run 请求的 protocol 必须是 "$runProtocol"，实际 ${request.protocol}');
    }
    if (request.runId.isEmpty) {
      errors.add('run 请求缺少 run_id（幂等键）');
    }
    if (!request.time.modelHours.isFinite) {
      errors.add('run 请求的 time.model_hours 必须是数字');
    }

    final shadowNodes = <String>{...existingNodeIds};
    final shadowEdges = <String>{...existingEdgeIds};

    for (var i = 0; i < request.actions.length; i += 1) {
      final action = request.actions[i];
      final at = '第 ${i + 1} 条 action';
      if (action.evidence != null) {
        evidenceCount += 1;
      }
      if (!actionKinds.contains(action.kind)) {
        errors
            .add('$at 的 kind 必须是 ${actionKinds.join(' / ')}，实际 ${action.kind}');
        continue;
      }
      if (action.modelHours == null) {
        errors.add('$at（${action.kind}）缺少时间基：至少要 at.model_hours');
      } else if (!action.modelHours!.isFinite) {
        errors.add('$at 的 at.model_hours 不是数字');
      }
      switch (action.kind) {
        case 'knowledge':
          {
            final node = action.node;
            final edge = action.edge;
            if (node == null && edge == null) {
              errors.add('$at（knowledge）要么给 node（新知识点）要么给 edge（新连接）');
              break;
            }
            if (node != null) {
              final id = node['id'];
              if (id is! String || id.isEmpty) {
                errors.add('$at（knowledge）的 node.id 必须是非空字符串');
              } else if (shadowNodes.contains(id)) {
                errors.add(
                  '$at（knowledge）要建的节点 "$id" 已经存在（材料入库应当幂等：不必重复建，直接引用即可）',
                );
              } else {
                shadowNodes.add(id);
              }
              final type = node['type'];
              if (type is! String || type.isEmpty) {
                errors.add('$at（knowledge）的 node.type 必须是非空字符串');
              }
              previews.add('$at [knowledge] 新增节点 ${node['id']}');
            } else {
              final from = edge!['from'];
              final to = edge['to'];
              if (from is! String ||
                  from.isEmpty ||
                  to is! String ||
                  to.isEmpty) {
                errors.add('$at（knowledge）的 edge 缺少 from / to');
              } else {
                if (!shadowNodes.contains(from)) {
                  errors.add('$at（knowledge）的边起点 "$from" 不在图里（也不在本批次新建的节点里）');
                }
                if (!shadowNodes.contains(to)) {
                  errors.add('$at（knowledge）的边终点 "$to" 不在图里（也不在本批次新建的节点里）');
                }
              }
              final id = edge['id'];
              if (id != null) {
                if (id is! String || id.isEmpty) {
                  errors.add('$at（knowledge）的 edge.id 必须是非空字符串');
                } else if (shadowEdges.contains(id)) {
                  errors.add('$at（knowledge）要建的边 "$id" 已经存在');
                } else {
                  shadowEdges.add(id);
                }
              }
              previews.add('$at [knowledge] 新增边 $from → $to');
            }
          }
        case 'goal':
          {
            final targets = action.targets;
            if (targets == null || targets.isEmpty) {
              errors.add('$at（goal）必须给非空的 targets 数组');
            } else {
              for (final target in targets) {
                if (!shadowNodes.contains(target)) {
                  errors.add('$at（goal）的目标 "$target" 不在图里');
                }
              }
            }
            final starts = action.starts;
            if (starts != null) {
              for (final start in starts) {
                if (!shadowNodes.contains(start)) {
                  errors.add('$at（goal）的起点 "$start" 不在图里');
                }
              }
            }
            previews.add('$at [goal] 目标 ${targets?.join('、')}');
          }
        case 'review':
        case 'exposure':
          {
            // 材料批次不产出这两类；校验规则仍与 io_run 对齐，免得工具误报"合法"。
            final nodeId = action.node?['id'];
            if (nodeId is! String || nodeId.isEmpty) {
              errors.add('$at（${action.kind}）缺少 node');
            } else if (!shadowNodes.contains(nodeId)) {
              errors.add('$at（${action.kind}）指向图里不存在的节点 "$nodeId"');
            }
            previews.add('$at [${action.kind}] $nodeId');
          }
        case 'time':
          previews.add('$at [time] 时间前进');
      }
    }

    return MaterialRunCheck(
      ok: errors.isEmpty,
      errors: errors,
      previews: previews,
      evidenceCount: evidenceCount,
    );
  }
}
