import 'run_executor.dart';

/// 把整份演练折成一段人话：每条动作一行 `text`，下面缩进一行为它的读数（没有读数就
/// 只有那行）。
///
/// `run/1` 那条路落提案时把这段一起存进批次（schema v23 的 `detail_text`）——
/// 演练本身不落库，但"我对这一跑点头时它当时做了什么"这句话得留得住。
String runDetailTextOf(RunExecutionReport report) => <String>[
      for (final trace in report.traces)
        traceReadingOf(trace).isEmpty
            ? trace.text
            : '${trace.text}\n  ${traceReadingOf(trace)}',
    ].join('\n');

/// 把一条动作**回报的增量**（`RunActionTrace.delta`）折成人话一行。
///
/// 存在的理由：执行层每一条动作都把"改了什么"回报进了 `delta` —— 记忆层是那段
/// `R/S/D` 变化、时间推进是每个节点的可提取度、新建是节点/边的形状、扩散是起点与
/// 目标；可 `RunActionTrace.text` 只有一句 `summary`，这些读数一直没有出口。
/// 这里给它们一个出口。
///
/// 两条纪律：
/// 1. **只摆引擎真回报的东西**：这一条没跑成（`error != null`）、或者机制根本没装
///    （`delta` 是空表）时返回空串 —— 不编一行"看起来像变化"的话。
/// 2. **认不出来也要说**：`delta` 里有东西但形状不认识时，兜底把键值列出来，而不是
///    悄悄吞掉（将来换机制时这条兜底就是出口）。
String traceReadingOf(RunActionTrace trace) {
  if (!trace.ok) {
    return '';
  }
  final delta = trace.delta;
  if (delta.isEmpty) {
    return '';
  }

  final memory = _memoryReading(delta);
  if (memory != null) {
    return memory;
  }
  final added = delta['added'];
  if (added == 'node') {
    return _nodeReading(delta['node']);
  }
  if (added == 'edge') {
    return _edgeReading(delta['edge']);
  }
  final time = _timeReading(delta);
  if (time != null) {
    return time;
  }
  final goal = _goalReading(delta);
  if (goal != null) {
    return goal;
  }
  return _fallbackReading(delta);
}

/// 记忆层那段读数（`FastEngine.review` 的回报）。
String? _memoryReading(Map<String, Object?> delta) {
  final rAfter = delta['R_after'];
  if (rAfter is! num) {
    return null;
  }
  final rAtReview = delta['R_at_review'];
  final sAfter = delta['S_after'];
  final parts = <String>[
    rAtReview is num
        ? 'R ${_n(rAtReview)} → ${_n(rAfter)}'
        : 'R → ${_n(rAfter)}',
    if (sAfter is num) 'S ${_n(sAfter)}（${_signed(delta['S_increase'])}）',
  ];
  final r0 = delta['R0_after'];
  if (r0 is num) {
    parts.add('R0 ${_n(r0)}');
  }
  final sigma = delta['Sigma_after'];
  if (sigma is num) {
    parts.add('Σ ${_n(sigma)}');
  }
  final d = delta['D_after'];
  if (d is num) {
    parts.add('D ${_n(d)}');
  }
  final kind = delta['kind'];
  return '记忆层读数（${kind is String ? kind : '复习'}）：${parts.join('，')}';
}

/// 造一个新节点时它长什么样。
String _nodeReading(Object? raw) {
  if (raw is! Map) {
    return '新增了一个节点';
  }
  final node = raw.cast<String, Object?>();
  final id = _s(node['id']);
  final name = _s(node['name']);
  final type = _s(node['type']);
  final ms = node['ms'];
  final bits = <String>[
    if (name.isNotEmpty && name != id) name,
    if (type.isNotEmpty) type,
    if (ms is num) 'ms ${_n(ms)}',
  ];
  return '新增节点 $id${bits.isEmpty ? '' : '（${bits.join(' / ')}）'}';
}

/// 连一条新边时它长什么样。
String _edgeReading(Object? raw) {
  if (raw is! Map) {
    return '新增了一条连接';
  }
  final edge = raw.cast<String, Object?>();
  final from = _s(edge['from']);
  final to = _s(edge['to']);
  final ls = edge['ls'];
  final id = _s(edge['id']);
  final bits = <String>[
    if (ls is num) 'ls ${_n(ls)}',
    if (id.isNotEmpty) id,
  ];
  return '新增边 $from → $to${bits.isEmpty ? '' : '（${bits.join('，')}）'}';
}

/// 时间前进那一跑的读数：时钟走到哪、每个节点现在的可提取度是多少。
String? _timeReading(Map<String, Object?> delta) {
  final ms = delta['ms'];
  if (ms is! Map) {
    return null;
  }
  final synced = delta['synced_nodes'];
  final total = delta['nodes'];
  final entries = ms.entries.toList()
    ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
  const shown = 4;
  final listing = entries
      .take(shown)
      .map((entry) => '${entry.key} ${_n(entry.value)}')
      .join('、');
  final more = entries.length > shown ? '、…（共 ${entries.length} 个）' : '';
  return '可提取度：$listing$more'
      '（同步 ${synced ?? '?'}/${total ?? entries.length} 个）';
}

/// 扩散起点与目标的读数。
String? _goalReading(Map<String, Object?> delta) {
  final starts = delta['starts'];
  final targets = delta['targets'];
  if (starts is! List && targets is! List) {
    return null;
  }
  final from = starts is List
      ? starts.map(_s).where((s) => s.isNotEmpty)
      : const <String>[];
  final to = targets is List
      ? targets.map(_s).where((s) => s.isNotEmpty)
      : const <String>[];
  return '扩散：起点 ${from.isEmpty ? '（没给，用图里原来的）' : from.join('、')}'
      ' → 目标 ${to.join('、')}'
      '${delta['rounds_reset'] == true ? '（轮次归零）' : ''}';
}

/// 兜底：`delta` 里有东西，但形状不认识 —— 把键值列出来，不吞。
String _fallbackReading(Map<String, Object?> delta) {
  final parts = delta.entries
      .map((entry) => '${entry.key}=${_value(entry.value)}')
      .toList()
    ..sort();
  return '增量：${parts.join('、')}';
}

String _value(Object? raw) {
  if (raw is num) {
    return _n(raw);
  }
  if (raw is List) {
    return '[${raw.map(_value).join('、')}]';
  }
  if (raw is Map) {
    return '{${raw.entries.map((e) => '${e.key}=${_value(e.value)}').join('、')}}';
  }
  return _s(raw);
}

String _s(Object? raw) => raw is String ? raw : (raw == null ? '' : '$raw');

/// 读数里的小数：留三位、去掉尾部的零（`0.800` → `0.8`、`3.000` → `3`）。
String _n(Object? raw) {
  if (raw is! num) {
    return '—';
  }
  final value = raw.toDouble();
  if (!value.isFinite) {
    return '$raw';
  }
  var text = value.toStringAsFixed(3);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  return text;
}

/// `+0.9` / `-0.4`（数字之外原样）。
String _signed(Object? raw) {
  if (raw is! num) {
    return _n(raw);
  }
  final text = _n(raw);
  return raw.toDouble() >= 0 ? '+$text' : text;
}
