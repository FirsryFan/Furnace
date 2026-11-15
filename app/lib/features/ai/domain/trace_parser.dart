/// 确定性 TraceParser：纯规则切分 solver trace，**不调用任何模型**。
///
/// 输入是 student_run 的 raw reasoning 与 answer sheet 的 process 文本；输出是
/// 带偏移与 hash 的 [TraceStep] 列表。切分规则（全部确定性）：
///
///  * 空行分段；
///  * 行首编号/步骤标记分段（`1.`、`1、`、`1)`、`①`…`⑩`、`步骤 1`）；
///  * `$$…$$` 公式块内部不切分；
///  * 每段的 `sourceStart/sourceEnd` 是 [TraceParseResult.source] 上的精确偏移，
///    `source.substring(sourceStart, sourceEnd) == rawText`（测试断言）；
///  * `sourceHash` 是对 raw 文本的稳定 hash（`stableClaimHash`），可追溯。
///
/// 解析失败（空 trace、`$$` 不配对等）返回 [TraceParseResult.failure]，由上层
/// 转成 `PrecheckResult.parseFailure`（= unknown）回 solver；**不得让 LLM 补**。
library;

import 'claim.dart';

/// trace 中一步的原始片段与来源位置。
class TraceStep {
  const TraceStep({
    required this.id,
    required this.sourceStart,
    required this.sourceEnd,
    required this.sourceHash,
    required this.rawText,
  });

  /// 稳定 id（`trace-step-1` 起）。
  final String id;

  /// 在 [TraceParseResult.source] 中的起始偏移（含）。
  final int sourceStart;

  /// 在 [TraceParseResult.source] 中的结束偏移（不含）。
  final int sourceEnd;

  /// 对 [rawText] 的稳定 hash。
  final String sourceHash;

  /// 精确的原始片段（未改写）。
  final String rawText;

  Map<String, Object?> toJson() => {
        'id': id,
        'source_start': sourceStart,
        'source_end': sourceEnd,
        'source_hash': sourceHash,
        'raw_text': rawText,
      };

  @override
  String toString() => 'TraceStep($id [$sourceStart,$sourceEnd) $sourceHash)';
}

/// 一次切分的结果。
///
/// [source] 是 raw reasoning 与 process 拼接后的完整来源文本；step 的偏移都相对
/// 它。`sourceHash` 是整段来源的稳定 hash，作为 handoff 的 `sourceHash`。
class TraceParseResult {
  const TraceParseResult._({
    required this.steps,
    required this.source,
    required this.failure,
  });

  factory TraceParseResult.parsed({
    required List<TraceStep> steps,
    required String source,
  }) =>
      TraceParseResult._(
        steps: List<TraceStep>.unmodifiable(steps),
        source: source,
        failure: null,
      );

  factory TraceParseResult.failure({
    required String detail,
    required String source,
  }) =>
      TraceParseResult._(
        steps: const <TraceStep>[],
        source: source,
        failure: detail,
      );

  final List<TraceStep> steps;

  /// 完整来源文本（偏移的基准；trace 本身，不是摘要）。
  final String source;

  /// 失败原因；null 表示切分成功。
  final String? failure;

  bool get succeeded => failure == null;

  /// 来源 trace 快照的稳定 hash。
  String get sourceHash => stableClaimHash(source);

  Map<String, Object?> toJson() => {
        'source_hash': sourceHash,
        'steps': [for (final step in steps) step.toJson()],
        if (failure != null) 'failure': failure,
      };
}

/// 纯规则 trace 切分器。
class TraceParser {
  const TraceParser();

  /// 按空行/编号/公式块把 raw reasoning 与 process 切成步骤。
  TraceParseResult parse({
    required String rawReasoning,
    required String processText,
  }) {
    final pieces = <String>[
      if (rawReasoning.trim().isNotEmpty) rawReasoning.trimRight(),
      if (processText.trim().isNotEmpty) processText.trim(),
    ];
    final source = pieces.join('\n\n');

    if (source.trim().isEmpty) {
      return TraceParseResult.failure(
        detail: 'solver trace 为空：raw reasoning 与 answer.process 都没有内容',
        source: source,
      );
    }

    // `$$` 必须成对，否则公式块边界不可靠。
    final formulaDelimiters = RegExp(r'\$\$').allMatches(source).length;
    if (formulaDelimiters.isOdd) {
      return TraceParseResult.failure(
        detail: '公式块 \$\$ 未闭合，无法可靠切分步骤',
        source: source,
      );
    }

    final protectedRanges = <(int, int)>[
      for (final match in RegExp(r'\$\$[\s\S]*?\$\$').allMatches(source))
        (match.start, match.end),
    ];
    bool isProtected(int index) =>
        protectedRanges.any((range) => index >= range.$1 && index < range.$2);

    final separators = <(int, int)>[];
    void addSeparator(int start, int end) {
      if (isProtected(start)) {
        return;
      }
      separators.add((start, end));
    }

    for (final match in RegExp(r'\n[ \t]*\n+').allMatches(source)) {
      addSeparator(match.start, match.end);
    }
    for (final match in RegExp(
      r'\n(?=[ \t]*(?:[0-9]{1,2}[.、)．]|[①②③④⑤⑥⑦⑧⑨⑩]|步骤[ \t]*[0-9]+))',
    ).allMatches(source)) {
      addSeparator(match.start, match.end);
    }
    separators.sort((a, b) => a.$1.compareTo(b.$1));

    final segments = <(int, int)>[];
    var cursor = 0;
    for (final separator in separators) {
      if (separator.$1 < cursor) {
        continue;
      }
      if (separator.$1 > cursor) {
        segments.add((cursor, separator.$1));
      }
      cursor = separator.$2;
    }
    if (cursor < source.length) {
      segments.add((cursor, source.length));
    }

    final steps = <TraceStep>[];
    for (final segment in segments) {
      var start = segment.$1;
      var end = segment.$2;
      while (start < end && source.codeUnitAt(start) <= 0x20) {
        start++;
      }
      while (end > start && source.codeUnitAt(end - 1) <= 0x20) {
        end--;
      }
      if (start >= end) {
        continue;
      }
      final raw = source.substring(start, end);
      steps.add(TraceStep(
        id: 'trace-step-${steps.length + 1}',
        sourceStart: start,
        sourceEnd: end,
        sourceHash: stableClaimHash(raw),
        rawText: raw,
      ));
    }

    if (steps.isEmpty) {
      return TraceParseResult.failure(
        detail: 'trace 里没有可切分的非空步骤',
        source: source,
      );
    }
    return TraceParseResult.parsed(steps: steps, source: source);
  }
}
