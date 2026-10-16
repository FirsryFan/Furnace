/// `run/1` 的**执行**那一半：把校验过的动作一条条真跑进引擎。
///
/// 三层分工（`docs/archive/TRANSCRIBE.md`、`src/io/run.js`）：
///  1. [decodeRunRequest] / [reviewTranscribedRun]（`transcribe_run.dart`）**只看不碰**：
///     "这份请求合法吗、它会做什么"；
///  2. 这一层按顺序真的去改引擎 —— `time` / `review` / `exposure` / `knowledge` / `goal`，
///     与 `src/io/run.js` 的 `applyOne()` 同义，每一步留一条可核对的痕迹
///     （时间前后、机制路径、增量）；
///  3. 把结果写进 `knowledge_points` / `knowledge_edges` 是**别的层**的事：这里只动
///     内存里的图（[FastGraph]）与那个模拟时钟（[FastEngine.hours]）。
///
/// 刻意不做的事：
///  * 不读写库、不调 AI（与 `transcribe_run.dart` 同一条纪律）；
///  * 不 `step()` 推进扩散轮次 —— JS 的 `applyOne` 也不推，`goal` 只是 `startDiffusion`；
///  * **失败不抛异常**：报告里写清"第几条没跑成、为什么"，已经跑过的动作**不撤销**
///    （引擎是内存态，原请求还在用户手里，重跑一次就是重放）；
///  * 上游校验该拦的（缺时间基、节点不在图里）这里**仍然再拦一次** —— 执行层不该
///    默认"一定有人校验过"，这一层也可能被别处直接调用。
///
/// 时间基（`resolveAt`）：`at.model_hours` 优先；只给 `at.wall` 时用锚点换算出
/// model_hours 并把这次换算记进 [RunExecutionReport.assumptions]；都没有就停在那一条
/// —— **不许默默用"现在"**，那是"时间戳漂移"类 bug 的唯一防线。
///
/// `time` 推进时钟，并把**已经有记忆态**的节点的 `ms` 重新同步（JS 的 `synced()`：
/// 慢层的"曲线推进"，不改 `S` 本身）；没有记忆态的节点一个都不动 —— 不替它编一个状态。
library;

import '../cognitive/fast_engine.dart';
import '../srs/dsr_memory.dart';
import 'material_ingest.dart';

/// wall ↔ model_hours 的换算依据（JS `ctx.state.anchor`）。
///
/// 只有带 `wall` 的 `time` 动作会更新它：之后的动作若只给 `at.wall`，就用它换算。
class RunAnchor {
  const RunAnchor({required this.modelHours, this.wall});

  /// 锚点上的模型时刻（小时）。
  final double modelHours;

  /// 锚点上的真实时刻。
  final DateTime? wall;

  Map<String, Object?> toJson() => <String, Object?>{
        'model_hours': modelHours,
        if (wall != null) 'wall': wall!.toIso8601String(),
      };
}

/// 一条动作跑完之后的痕迹。
class RunActionTrace {
  const RunActionTrace({
    required this.index,
    required this.kind,
    required this.mechanism,
    required this.summary,
    this.node,
    this.atModelHours,
    this.atWall,
    this.hoursBefore,
    this.hoursAfter,
    this.elapsedHours,
    this.outcome,
    this.delta = const <String, Object?>{},
    this.error,
  });

  /// 0 基下标（人话里说成"第 index+1 条"）。
  final int index;
  final String kind;

  /// 落到哪条机制路径 —— 与 [reviewTranscribedRun] 预告用的**同一套名字**，
  /// 所以"预告的那条路"与"真跑的那条路"可以直接对账。
  final String mechanism;

  /// 人话一句（每种动作自己的说法）。
  final String summary;

  final String? node;
  final double? atModelHours;
  final String? atWall;
  final double? hoursBefore;
  final double? hoursAfter;
  final double? elapsedHours;
  final String? outcome;

  /// 机制自己回报的增量（记忆层就是那段 `R/S/D` 变化）；没装机制时是空表，
  /// **不编**一个假的增量出来。
  final Map<String, Object?> delta;

  /// 这一条没跑成的原因（人话）；null 表示跑成了。
  final String? error;

  bool get ok => error == null;

  String get text =>
      ok ? '${index + 1} [$kind] $summary' : '${index + 1} [$kind] ✗ $error';

  Map<String, Object?> toJson() => <String, Object?>{
        'index': index + 1,
        'kind': kind,
        'mechanism': mechanism,
        if (node != null) 'node': node,
        if (atModelHours != null) 'at_model_hours': atModelHours,
        if (atWall != null) 'at_wall': atWall,
        if (hoursBefore != null) 'hours_before': hoursBefore,
        if (hoursAfter != null) 'hours_after': hoursAfter,
        if (elapsedHours != null) 'elapsed_hours': elapsedHours,
        if (outcome != null) 'outcome': outcome,
        if (error == null) 'delta': delta,
        if (error != null) 'error': error,
      };
}

/// 一次执行的结果：跑过哪些、停在哪、时间走到哪。
class RunExecutionReport {
  const RunExecutionReport({
    required this.runId,
    required this.traces,
    required this.assumptions,
    required this.hoursBefore,
    required this.hoursAfter,
    this.stoppedAt,
    this.anchor,
  });

  final String runId;

  /// 按顺序的痕迹：跑成了的 + （若有）那条没跑成的。
  final List<RunActionTrace> traces;

  /// `wall → model_hours` 的换算记录（与 JS 的 `state.assumptions` 同义）——
  /// 换算过的时刻是**推出来的**，值得让用户看见。
  final List<String> assumptions;

  final double hoursBefore;
  final double hoursAfter;

  /// 停在第几条（0 基下标）；null = 全部跑完。
  final int? stoppedAt;

  /// 跑完之后的时间锚点（没有任何带 `wall` 的 `time` 动作就是原来的那个）。
  final RunAnchor? anchor;

  bool get ok => stoppedAt == null;

  int get appliedCount {
    var count = 0;
    for (final trace in traces) {
      if (trace.ok) {
        count += 1;
      }
    }
    return count;
  }

  RunActionTrace? get failure {
    final at = stoppedAt;
    return at == null ? null : traces[at];
  }

  /// 人话多行（与 [TranscribeReport.text] 同一个排版口味）。
  String get text {
    final buffer = StringBuffer();
    if (ok) {
      buffer.writeln('✓ 跑完 ${traces.length} 条动作：$runId'
          '（hours ${FastEngine.round6(hoursBefore)}'
          ' → ${FastEngine.round6(hoursAfter)}）');
    } else {
      buffer.writeln('✗ 第 ${stoppedAt! + 1} 条动作没跑成：${failure!.error}');
      buffer.writeln('  已经跑过的 $appliedCount 条不撤销'
          '（引擎是内存态，重跑就是重放）');
    }
    for (final trace in traces) {
      buffer.writeln('  ${trace.text}');
    }
    if (assumptions.isNotEmpty) {
      buffer.writeln('  换算（记下来）：');
      for (final assumption in assumptions) {
        buffer.writeln('    · $assumption');
      }
    }
    return buffer.toString().trimRight();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'run_id': runId,
        'hours_before': FastEngine.round6(hoursBefore),
        'hours_after': FastEngine.round6(hoursAfter),
        'actions': traces.length,
        'applied': appliedCount,
        if (stoppedAt != null) 'stopped_at': stoppedAt! + 1,
        if (failure != null) 'error': failure!.error,
        'assumptions': assumptions,
        if (anchor != null) 'anchor': anchor!.toJson(),
        'traces': <Map<String, Object?>>[
          for (final trace in traces) trace.toJson(),
        ],
      };
}

/// 把 [request] 的动作按顺序跑进 [engine]。
///
/// [anchor] 是进来时的 wall ↔ model_hours 依据（第一次跑通常是 null）。
/// [engine] 会被**就地修改**：图里多出节点/边、[FastEngine.hours] 往前走、
/// 装了就有的记忆机制改节点的 DSR 状态。
RunExecutionReport executeRun(
  MaterialRunRequest request, {
  required FastEngine engine,
  RunAnchor? anchor,
}) {
  final hoursBefore = engine.hours;
  final traces = <RunActionTrace>[];
  final assumptions = <String>[];
  var current = anchor;
  int? stoppedAt;

  for (var i = 0; i < request.actions.length; i += 1) {
    final action = request.actions[i];
    final time = _resolveAt(action, i, current, assumptions);
    if (time.error != null) {
      traces.add(RunActionTrace(
        index: i,
        kind: action.kind,
        mechanism: '(未执行)',
        summary: '',
        error: time.error,
      ));
      stoppedAt = i;
      break;
    }

    RunActionTrace? failed;
    switch (action.kind) {
      case 'time':
        {
          final before = engine.hours;
          final double elapsed;
          if (action.elapsedHours != null) {
            elapsed = action.elapsedHours!;
            engine.hours = before + elapsed;
          } else {
            engine.hours = time.modelHours!;
            elapsed = engine.hours - before;
          }
          if (time.wall != null) {
            current = RunAnchor(modelHours: engine.hours, wall: time.wall);
          }
          // 时间推进把每个**已经有记忆态**的节点的 ms 重新同步（JS 的
          // `synced()`：慢层的"曲线推进"，不改 S 本身）。没有记忆态的节点
          // 连状态都没有，就不去替它编一个 —— 只如实数出同步了几个。
          var synced = 0;
          if (engine.memoryInstalled) {
            final params = engine.memoryParams ?? const DsrParams();
            for (final node in engine.graph.nodes.values) {
              if (FastEngine.dsrBagOf(node) == null) {
                continue;
              }
              FastEngine.dsrRetrievabilityOf(node,
                  u: engine.hours, params: params);
              synced += 1;
            }
          }
          final ms = <String, Object?>{
            for (final node in engine.graph.nodes.values)
              node.id: FastEngine.round6(node.ms),
          };
          traces.add(RunActionTrace(
            index: i,
            kind: 'time',
            mechanism: 'hours.advance',
            summary: '时间前进 ${FastEngine.round6(elapsed)} 小时'
                '（hours ${FastEngine.round6(before)}'
                ' → ${FastEngine.round6(engine.hours)}，'
                '同步 $synced/${ms.length} 个节点的可提取度'
                '${engine.memoryInstalled ? '' : '：没装记忆机制，一个都没动'}）',
            atModelHours: time.modelHours,
            atWall: time.wall?.toIso8601String(),
            hoursBefore: FastEngine.round6(before),
            hoursAfter: FastEngine.round6(engine.hours),
            elapsedHours: FastEngine.round6(elapsed),
            delta: <String, Object?>{
              'synced_nodes': synced,
              'nodes': ms.length,
              'ms': ms,
            },
          ));
        }
      case 'review':
        {
          final nodeId = action.nodeId;
          if (nodeId == null || nodeId.isEmpty) {
            failed = _fail(i, action.kind, '缺少 node');
            break;
          }
          if (!engine.graph.hasNode(nodeId)) {
            failed = _fail(i, action.kind, '指向图里不存在的节点 "$nodeId"');
            break;
          }
          final type = MaterialIngest.reviewMechanismOf(action);
          final closeness = action.closeness ??
              (type == MaterialIngest.reviewedSolutionMechanism
                  ? MaterialIngest.reviewedSolutionCloseness
                  : null);
          final event = <String, Object?>{
            'type': type,
            'grade': type == 'lapse' ? 1 : 3,
            if (closeness != null) 'closeness': closeness,
            'current_real_time': time.modelHours,
          };
          final raw = engine.review(nodeId, event);
          traces.add(RunActionTrace(
            index: i,
            kind: 'review',
            mechanism: type,
            summary: '复习 $nodeId（${action.outcome ?? '?'}）'
                '${raw.isEmpty ? ' —— 没有装记忆机制，只记下这次复习，没改状态' : ''}',
            node: nodeId,
            atModelHours: time.modelHours,
            atWall: time.wall?.toIso8601String(),
            outcome: action.outcome,
            delta: raw.isEmpty ? const <String, Object?>{} : raw.first,
          ));
        }
      case 'exposure':
        {
          final nodeId = action.nodeId;
          if (nodeId == null || nodeId.isEmpty) {
            failed = _fail(i, action.kind, '缺少 node');
            break;
          }
          if (!engine.graph.hasNode(nodeId)) {
            failed = _fail(i, action.kind, '指向不存在的节点 "$nodeId"');
            break;
          }
          final raw = engine.review(nodeId, <String, Object?>{
            'type': 'reread',
            'current_real_time': time.modelHours,
          });
          traces.add(RunActionTrace(
            index: i,
            kind: 'exposure',
            mechanism: 'reread',
            summary: '再读了一遍 $nodeId（只算再读增益）'
                '${raw.isEmpty ? ' —— 没有装记忆机制，没改状态' : ''}',
            node: nodeId,
            atModelHours: time.modelHours,
            atWall: time.wall?.toIso8601String(),
            outcome: 'reread',
            delta: raw.isEmpty ? const <String, Object?>{} : raw.first,
          ));
        }
      case 'knowledge':
        {
          final node = action.node;
          final edge = action.edge;
          if (node == null && edge == null) {
            failed = _fail(i, action.kind, '要么给 node（新知识点）要么给 edge（新连接）');
            break;
          }
          if (node != null) {
            final id = node['id'] is String ? node['id'] as String : '';
            if (id.isEmpty) {
              failed = _fail(i, action.kind, 'node.id 必须是非空字符串');
              break;
            }
            final type = node['type'] is String ? node['type'] as String : '';
            if (type.isEmpty) {
              failed = _fail(i, action.kind, 'node.type 必须是非空字符串');
              break;
            }
            final name =
                node['name'] is String && (node['name'] as String).isNotEmpty
                    ? node['name'] as String
                    : id;
            try {
              final created = engine.graph.addNode(FastNode(
                id: id,
                name: name,
                type: type,
                weight: node['weight'] is num
                    ? (node['weight']! as num).toDouble()
                    : 1.0,
                ms: node['ms'] is num ? (node['ms']! as num).toDouble() : 0.8,
                // 新节点的"上次复习"就是这个动作的时间基（与
                // `FastGraph.fromSpec(currentRealTime:)` 的修正同一条道理）。
                lastReviewTime: time.modelHours,
              ));
              traces.add(RunActionTrace(
                index: i,
                kind: 'knowledge',
                mechanism: 'graph.add_node',
                summary: '新增节点 $id（$name / $type）',
                node: id,
                atModelHours: time.modelHours,
                atWall: time.wall?.toIso8601String(),
                delta: <String, Object?>{
                  'added': 'node',
                  'node': created.toJson(const FastConfig()),
                },
              ));
            } on ArgumentError catch (error) {
              failed = _fail(i, action.kind, '建不了节点：${error.message}');
            }
          } else {
            final from = edge!['from'] is String ? edge['from'] as String : '';
            final to = edge['to'] is String ? edge['to'] as String : '';
            if (from.isEmpty || to.isEmpty) {
              failed = _fail(i, action.kind, 'edge 缺少 from / to');
              break;
            }
            final rawLs = edge['ls'];
            if (rawLs != null && rawLs is! num) {
              failed = _fail(i, action.kind, 'edge.ls 不是数字：$rawLs');
              break;
            }
            final id = edge['id'] is String && (edge['id'] as String).isNotEmpty
                ? edge['id'] as String
                : 'e_${i + 1}_${from}_$to';
            try {
              final created = engine.graph.addEdge(FastEdge(
                id: id,
                from: from,
                to: to,
                ls: rawLs is num ? rawLs.toDouble() : 0.8,
              ));
              traces.add(RunActionTrace(
                index: i,
                kind: 'knowledge',
                mechanism: 'graph.add_edge',
                summary: '新增边 $from → $to（ls ${created.ls}）',
                atModelHours: time.modelHours,
                atWall: time.wall?.toIso8601String(),
                delta: <String, Object?>{
                  'added': 'edge',
                  'edge': created.toJson(),
                },
              ));
            } on ArgumentError catch (error) {
              failed = _fail(i, action.kind, '建不了边：${error.message}');
            }
          }
        }
      case 'goal':
        {
          final targets = action.targets ?? const <String>[];
          if (targets.isEmpty) {
            failed = _fail(i, action.kind, '必须给非空的 targets 数组');
            break;
          }
          final starts = action.starts ?? engine.starts;
          try {
            engine.startDiffusion(starts, targets);
            traces.add(RunActionTrace(
              index: i,
              kind: 'goal',
              mechanism: 'start_diffusion',
              summary: '扩散起点 ${starts.join('、')} → 目标 ${targets.join('、')}'
                  '（轮次归零）',
              atModelHours: time.modelHours,
              atWall: time.wall?.toIso8601String(),
              delta: <String, Object?>{
                'starts': starts,
                'targets': targets,
                'rounds_reset': true,
              },
            ));
          } on ArgumentError catch (error) {
            failed = _fail(i, action.kind, '起不了扩散：${error.message}');
          }
        }
      default:
        failed = _fail(i, action.kind, '未知动作 ${action.kind}');
    }

    if (failed != null) {
      traces.add(failed);
      stoppedAt = i;
      break;
    }
  }

  return RunExecutionReport(
    runId: request.runId,
    traces: traces,
    assumptions: assumptions,
    hoursBefore: FastEngine.round6(hoursBefore),
    hoursAfter: FastEngine.round6(engine.hours),
    stoppedAt: stoppedAt,
    anchor: current,
  );
}

RunActionTrace _fail(int index, String kind, String reason) => RunActionTrace(
      index: index,
      kind: kind,
      mechanism: '(未执行)',
      summary: '',
      error: reason,
    );

/// 解析一条动作的时间基（JS `resolveAt`）：`at.model_hours` 优先，其次用锚点换算
/// `at.wall`，`time` 动作还可以只用 `elapsed_hours`。都没有就是错误。
_ResolvedTime _resolveAt(
  MaterialRunAction action,
  int index,
  RunAnchor? anchor,
  List<String> assumptions,
) {
  final at = '第 ${index + 1} 条 action（${action.kind}）';

  if (action.modelHours != null) {
    if (!action.modelHours!.isFinite) {
      return _ResolvedTime.error('$at 的 at.model_hours 不是数字');
    }
    DateTime? wall;
    if (action.wall != null) {
      wall = DateTime.tryParse(action.wall!);
      if (wall == null) {
        return _ResolvedTime.error('$at 的 at.wall 不是可解析的时间：${action.wall}');
      }
    }
    return _ResolvedTime(modelHours: action.modelHours, wall: wall);
  }

  if (action.wall != null) {
    final wall = DateTime.tryParse(action.wall!);
    if (wall == null) {
      return _ResolvedTime.error('$at 的 at.wall 不是可解析的时间：${action.wall}');
    }
    final from = anchor?.wall;
    if (from == null) {
      return _ResolvedTime.error('$at 只给了 at.wall，而没有可用的'
          ' wall↔model_hours 锚点：请直接给 at.model_hours，'
          '或先用带 wall 的 time 动作建立锚点');
    }
    final hours =
        anchor!.modelHours + wall.difference(from).inMilliseconds / 3600000.0;
    assumptions.add('wall ${wall.toIso8601String()} → model_hours '
        '${FastEngine.round6(hours)}（锚点 ${from.toIso8601String()}'
        ' ↔ ${FastEngine.round6(anchor.modelHours)}）');
    return _ResolvedTime(modelHours: hours, wall: wall);
  }

  if (action.kind == 'time' && action.elapsedHours != null) {
    return const _ResolvedTime();
  }

  return _ResolvedTime.error('$at 缺少时间基：至少要 at.model_hours'
      '（time 动作也可以用 elapsed_hours）');
}

class _ResolvedTime {
  const _ResolvedTime({this.modelHours, this.wall}) : error = null;

  const _ResolvedTime.error(this.error)
      : modelHours = null,
        wall = null;

  final double? modelHours;
  final DateTime? wall;
  final String? error;
}
