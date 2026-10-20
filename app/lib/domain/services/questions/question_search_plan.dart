/// 题库搜索框输入解析：一段输入 → 「多个题号（可区间）」+「题干关键词」。
///
/// 背景：题库列表搜索框原先只支持「单个题号」或「题干 LIKE」。整卷校对/
/// 清洗时需要一次贴入多个题号或区间（`1..20`、`TR-1~TR-5`），同时允许在
/// 题号旁边附带题干关键词做串联过滤。本文件只做纯逻辑解析，不改 UI /
/// provider，也不读数据库。
///
/// 解析管线（确定性、纯函数、同一输入永远同一输出、永不抛异常）：
/// 1. 原始输入原样保留到 [QuestionSearchPlan.raw]（回显用；空输入也保留原
///    样），语义判断都用 trim 空白（含全角空格 U+3000、NBSP U+00A0 等
///    Unicode 空白）之后的文本；
/// 2. 先按清单分隔符切成「块」：半角逗号 `,`、全角逗号 `，`、顿号 `、`、
///    半角分号 `;`、全角分号 `；`；块内再按 Unicode 空白切成 token；
/// 3. 每个 token 依次尝试：单题号（复用 `parseQuestionNumberQuery`，
///    `TR-00042` / `tr-42` / `TR42` / `#42` / `＃７` / `00042` / `42` /
///    全角数字都认）→ 区间（连接符按 `..` → `~` → `—` → `-` 的顺序；
///    `-` 只在连接符两侧都是纯数字时才当区间，避免把 `TR-42` 拆坏）；
///    另外支持连接符单独成 token 的写法，如 `1 - 5`、`1 .. 5`（与
///    `question_serial_batch.dart` 的区间口径一致）；
/// 4. 认成题号的进 [QuestionSearchPlan.serialNos]（去重、升序，相邻区间合
///    并）；认不出且不像区间的 token 原样拼进题干关键词（单个半角空格连
///    接，内部字符不重排）；形如区间但一端非法（至少一端能解析成题号、另
///    一端不能，或连接符在 token 首尾）的整段进
///    [QuestionSearchPlan.rejectedSegments]，不当题干关键词；
/// 5. 回填题干关键词：题号为空 → 整段 trim 后的输入（保持「搜索框就是题
///    干关键词」的旧行为）；题号非空且题干部分为空 → `null`；两者都有 →
///    列表页做「题号命中 ∩ 题干包含」的串联过滤；
/// 6. 题号超过 `maxSerialCount`（或硬上限
///    [kQuestionSearchPlanSerialHardLimit]）时只保留最小的若干个并置
///    [QuestionSearchPlan.truncated]，不展开超大区间、不抛异常；
///    `maxSerialCount <= 0` 时输出空题号清单（若输入里有可认题号则
///    `truncated = true`）。
///
/// 与 `question_serial_batch.dart` 的关系：区间连接符、升降序归一、去重升
/// 序、`maxCount` 截断口径一致；差别是本文件把「认不出的文字」当题干关键
/// 词（而不是拒绝段），并额外产出 `stemContains` 供列表页串联过滤。
///
/// 已明确的边界行为：
/// - 含 `-` 但两侧不都是纯数字的 token（`abc-def`、`TR-1-2`）当题干关键词，
///   不当区间、不进拒绝段；
/// - `1..x` / `x..1` / `1..` / `..5` / `1..5..9` 这类「像区间但坏掉」的
///   token 整段进拒绝段；但如果最后题号为空，`stemContains` 按第 5 条回退
///   成整段输入（旧搜索行为），否则纯坏区间输入会变成「什么都没搜」；
/// - 只有分隔符的输入（如 `,,,`）没有 token，等价于「题干关键词是 `,,,`」
///   （同样按第 5 条回退），不会返回空计划；
/// - 空白分隔的区间只支持「数字 连接符 数字」三个 token 的写法，
///   `1 xxx 5` 不会猜成区间。
library;

import 'question_number_query.dart';

/// 搜索输入最多产出多少个题号的硬上限。
///
/// 调用方可以给 [parseQuestionSearchPlan] 传更大的 `maxSerialCount`，但输出
/// 不会超过这个数：避免 `1..999999999` 这类输入把内存撑爆；超过时结果里的
/// `truncated` 为 true。
const int kQuestionSearchPlanSerialHardLimit = 100000;

/// 题号清单的默认上限（与 `QuestionSerialBatch` 的默认值一致）。
const int kQuestionSearchPlanDefaultMaxSerialCount = 200;

/// 一段搜索框输入的结构化解析结果（不可变值对象）。
///
/// 一般只用 [parseQuestionSearchPlan] 构造；直接调用构造函数时调用方要保证
/// 列表元素合法（元素本身不做运行时校验）。相等性只按语义字段（题干关键词、
/// 题号清单、拒绝段、截断标记），不看 [raw]：`  7 ` 与 `7` 解析结果相等。
class QuestionSearchPlan {
  const QuestionSearchPlan({
    required this.raw,
    this.stemContains,
    this.serialNos = const <int>[],
    this.rejectedSegments = const <String>[],
    this.truncated = false,
  });

  /// 调用方传入的原始输入（回显用，不参与相等性；空输入也保留原样）。
  final String raw;

  /// 题干关键词：题号为空时是整段输入的 trim；否则是认不出的 token 用单
  /// 个半角空格拼接（没有题干部分时为 null）。
  final String? stemContains;

  /// 命中的题号：去重、升序、相邻区间已合并，最多 `maxSerialCount` 个。
  final List<int> serialNos;

  /// 形如区间但一端非法、无法展开的 token（按输入顺序，原样去首尾空白）。
  final List<String> rejectedSegments;

  /// 题号是否被截断（可认题号总数超过 `maxSerialCount` 或硬上限）。
  final bool truncated;

  /// 两者都没有：既没有题号也没有题干关键词（只可能是空/纯空白输入）。
  bool get isEmpty => stemContains == null && serialNos.isEmpty;

  /// 只有题号、没有题干关键词。
  bool get isSerialOnly => serialNos.isNotEmpty && stemContains == null;

  /// 只有题干关键词、没有题号。
  bool get isStemOnly => serialNos.isEmpty && stemContains != null;

  /// 题号个数。
  int get serialCount => serialNos.length;

  /// 序列化成 JSON 友好结构（键名固定，供 AI 工具/日志使用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'raw': raw,
        'stem_contains': stemContains,
        'serial_nos': serialNos,
        'rejected_segments': rejectedSegments,
        'truncated': truncated,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuestionSearchPlan &&
        other.stemContains == stemContains &&
        other.truncated == truncated &&
        _sameInts(other.serialNos, serialNos) &&
        _sameStrings(other.rejectedSegments, rejectedSegments);
  }

  @override
  int get hashCode => Object.hash(
        stemContains,
        truncated,
        Object.hashAll(serialNos),
        Object.hashAll(rejectedSegments),
      );

  @override
  String toString() => 'QuestionSearchPlan(serialCount: $serialCount, '
      'stemContains: $stemContains, '
      'rejected: ${rejectedSegments.length}, truncated: $truncated)';
}

/// 解析题库搜索框的一段输入；永不抛异常。
///
/// [maxSerialCount] 是题号清单上限（默认
/// [kQuestionSearchPlanDefaultMaxSerialCount]）；超过时只保留最小的若干个并
/// 置 [QuestionSearchPlan.truncated]。负数/0 等价于「不要题号」，但只要输入
/// 里有可认题号，`truncated` 仍为 true。
QuestionSearchPlan parseQuestionSearchPlan(
  String raw, {
  int maxSerialCount = kQuestionSearchPlanDefaultMaxSerialCount,
}) {
  final String trimmed = _trimWhitespace(raw);
  if (trimmed.isEmpty) {
    return QuestionSearchPlan(raw: raw);
  }

  final List<_SerialSpan> spans = <_SerialSpan>[];
  final List<String> stemTokens = <String>[];
  final List<String> rejected = <String>[];
  final List<String> tokens = _tokenize(trimmed);

  var index = 0;
  while (index < tokens.length) {
    final _TripletAttempt triplet = _readTriplet(tokens, index);
    if (triplet.isHandled) {
      final _SerialSpan? span = triplet.span;
      if (span != null) spans.add(span);
      final String? rejectedText = triplet.rejectedText;
      if (rejectedText != null) rejected.add(rejectedText);
      index = triplet.nextIndex;
      continue;
    }

    final String token = tokens[index];
    final QuestionNumberQuery? single = parseQuestionNumberQuery(token);
    if (single != null) {
      spans.add(_SerialSpan(single.serialNo, single.serialNo));
      index += 1;
      continue;
    }

    final _RangeAttempt attempt = _readRange(token);
    if (attempt.isRange) {
      spans.add(_SerialSpan(attempt.start!, attempt.end!));
    } else if (attempt.malformed) {
      rejected.add(token);
    } else {
      stemTokens.add(token);
    }
    index += 1;
  }

  final List<_SerialSpan> merged = _mergeSpans(spans);
  final int total = _spanCount(merged);
  final int limit = _effectiveLimit(maxSerialCount);
  final List<int> serialNos = limit <= 0
      ? const <int>[]
      : List<int>.unmodifiable(_expand(merged, limit));
  final bool truncated = total > limit;
  final String? stemContains = serialNos.isEmpty
      ? trimmed
      : (stemTokens.isEmpty ? null : stemTokens.join(' '));

  return QuestionSearchPlan(
    raw: raw,
    stemContains: stemContains,
    serialNos: serialNos,
    rejectedSegments: List<String>.unmodifiable(rejected),
    truncated: truncated,
  );
}

/// 空白分隔的区间：`1 - 5` 这种三个 token 的写法。
_TripletAttempt _readTriplet(List<String> tokens, int index) {
  final _TripletAttempt none = _TripletAttempt(nextIndex: index);
  if (index + 2 >= tokens.length) return none;
  final String connector = tokens[index + 1];
  if (!_isConnectorToken(connector)) return none;
  final String left = tokens[index];
  final String right = tokens[index + 2];
  final int? leftSerial = _serialOf(left);
  final int? rightSerial = _serialOf(right);
  if (leftSerial == null && rightSerial == null) return none;
  if (leftSerial != null &&
      rightSerial != null &&
      _tripletRangeAllowed(connector, left, right)) {
    final int lo = leftSerial <= rightSerial ? leftSerial : rightSerial;
    final int hi = leftSerial <= rightSerial ? rightSerial : leftSerial;
    return _TripletAttempt(
      isHandled: true,
      nextIndex: index + 3,
      span: _SerialSpan(lo, hi),
    );
  }
  return _TripletAttempt(
    isHandled: true,
    nextIndex: index + 3,
    rejectedText: '$left $connector $right',
  );
}

/// `-` 当区间连接符时要求两端都是纯数字（不认 `TR-1 - 2` 这类写法）。
bool _tripletRangeAllowed(String connector, String left, String right) {
  if (connector != '-') return true;
  return _isAllDigits(left) && _isAllDigits(right);
}

/// 把汉字/字母混合、带 `-` 的普通文字留在题干侧，别误当坏区间。
bool _isConnectorToken(String token) =>
    token == '..' || token == '~' || token == '—' || token == '-';

/// 单 token 里的区间：`1..5` / `5~1` / `TR-3—TR-5` / `1-5`。
_RangeAttempt _readRange(String token) {
  for (final String connector in _rangeConnectors) {
    final int connectorIndex = token.indexOf(connector);
    if (connectorIndex < 0) continue;
    final String left = token.substring(0, connectorIndex);
    final String right = token.substring(connectorIndex + connector.length);
    final int? leftSerial = _serialOf(left);
    final int? rightSerial = _serialOf(right);
    final bool dashBlocked =
        connector == '-' && !(_isAllDigits(left) && _isAllDigits(right));
    if (dashBlocked) continue;
    if (leftSerial != null && rightSerial != null) {
      final int lo = leftSerial <= rightSerial ? leftSerial : rightSerial;
      final int hi = leftSerial <= rightSerial ? rightSerial : leftSerial;
      return _RangeAttempt.range(lo, hi);
    }
    if (leftSerial != null ||
        rightSerial != null ||
        left.isEmpty ||
        right.isEmpty) {
      return const _RangeAttempt.malformed();
    }
    return const _RangeAttempt.text();
  }
  return const _RangeAttempt.text();
}

/// 单段文本解析成题号；不是题号返回 null（不抛异常）。
int? _serialOf(String text) {
  if (text.isEmpty) return null;
  return parseQuestionNumberQuery(text)?.serialNo;
}

/// 合并后的闭区间清单（升序、互不重叠、不相邻）。
List<_SerialSpan> _mergeSpans(List<_SerialSpan> spans) {
  if (spans.isEmpty) return const <_SerialSpan>[];
  final List<_SerialSpan> ordered = List<_SerialSpan>.of(spans);
  ordered.sort((_SerialSpan a, _SerialSpan b) {
    final int byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return a.end.compareTo(b.end);
  });
  final List<_SerialSpan> merged = <_SerialSpan>[];
  var currentStart = ordered.first.start;
  var currentEnd = ordered.first.end;
  for (var i = 1; i < ordered.length; i++) {
    final _SerialSpan span = ordered[i];
    if (span.start <= currentEnd + 1) {
      if (span.end > currentEnd) currentEnd = span.end;
    } else {
      merged.add(_SerialSpan(currentStart, currentEnd));
      currentStart = span.start;
      currentEnd = span.end;
    }
  }
  merged.add(_SerialSpan(currentStart, currentEnd));
  return List<_SerialSpan>.unmodifiable(merged);
}

/// 合并后的题号总数（不逐个展开，避免超大区间吃内存）。
int _spanCount(List<_SerialSpan> merged) {
  var total = 0;
  for (final _SerialSpan span in merged) {
    total += span.end - span.start + 1;
  }
  return total;
}

/// 按升序展开前 [limit] 个题号（只在合并后的区间上顺序走，不展开区间全长）。
List<int> _expand(List<_SerialSpan> merged, int limit) {
  final List<int> result = <int>[];
  for (final _SerialSpan span in merged) {
    var value = span.start;
    while (value <= span.end && result.length < limit) {
      result.add(value);
      value += 1;
    }
    if (result.length >= limit) break;
  }
  return result;
}

/// `maxSerialCount` 钳到 `[0, 硬上限]`。
int _effectiveLimit(int maxSerialCount) {
  if (maxSerialCount <= 0) return 0;
  if (maxSerialCount > kQuestionSearchPlanSerialHardLimit) {
    return kQuestionSearchPlanSerialHardLimit;
  }
  return maxSerialCount;
}

/// 按清单分隔符与 Unicode 空白切 token（全角空格、NBSP 等也算空白）。
List<String> _tokenize(String text) {
  final List<String> tokens = <String>[];
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final int unit = text.codeUnitAt(i);
    final bool separator = _isWhitespace(unit) || _isListSeparator(unit);
    if (separator) {
      if (start >= 0) {
        tokens.add(text.substring(start, i));
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) tokens.add(text.substring(start));
  return List<String>.unmodifiable(tokens);
}

/// 清单分隔符：半/全角逗号、顿号、半/全角分号。
bool _isListSeparator(int unit) =>
    unit == 0x2C ||
    unit == 0xFF0C ||
    unit == 0x3001 ||
    unit == 0x3B ||
    unit == 0xFF1B;

/// Unicode 空白（含全角空格 U+3000、NBSP U+00A0、U+2000–U+200A 等）。
bool _isWhitespace(int unit) {
  if (unit >= 0x2000 && unit <= 0x200A) return true;
  switch (unit) {
    case 0x20:
    case 0x09:
    case 0x0A:
    case 0x0B:
    case 0x0C:
    case 0x0D:
    case 0x85:
    case 0xA0:
    case 0x1680:
    case 0x2028:
    case 0x2029:
    case 0x202F:
    case 0x205F:
    case 0x3000:
      return true;
  }
  return false;
}

/// 去首尾 Unicode 空白。
String _trimWhitespace(String input) {
  var start = 0;
  var end = input.length;
  while (start < end && _isWhitespace(input.codeUnitAt(start))) {
    start += 1;
  }
  while (end > start && _isWhitespace(input.codeUnitAt(end - 1))) {
    end -= 1;
  }
  return input.substring(start, end);
}

/// 半角/全角数字；其它字符返回 null。
int? _digitValue(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
  if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFF10;
  return null;
}

/// 是否全是半角/全角数字（空串返回 false）。
bool _isAllDigits(String text) {
  if (text.isEmpty) return false;
  for (final int rune in text.runes) {
    if (_digitValue(rune) == null) return false;
  }
  return true;
}

bool _sameInts(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameStrings(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const List<String> _rangeConnectors = <String>['..', '~', '—', '-'];

/// 题号闭区间 [start, end]（升序）。
class _SerialSpan {
  const _SerialSpan(this.start, this.end);

  final int start;
  final int end;
}

/// 单 token 区间解析结果：命中区间 / 形如区间但坏掉 / 不是区间（当文本）。
class _RangeAttempt {
  const _RangeAttempt.range(this.start, this.end)
      : isRange = true,
        malformed = false;

  const _RangeAttempt.malformed()
      : isRange = false,
        malformed = true,
        start = null,
        end = null;

  const _RangeAttempt.text()
      : isRange = false,
        malformed = false,
        start = null,
        end = null;

  final bool isRange;
  final bool malformed;
  final int? start;
  final int? end;
}

/// 三 token 区间解析结果。[isHandled] 为 false 表示当前 token 不是区间开头。
class _TripletAttempt {
  const _TripletAttempt({
    this.isHandled = false,
    required this.nextIndex,
    this.span,
    this.rejectedText,
  });

  final bool isHandled;
  final int nextIndex;
  final _SerialSpan? span;
  final String? rejectedText;
}
