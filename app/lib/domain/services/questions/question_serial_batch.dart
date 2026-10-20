/// 整卷题号批量清单：把「人写的题号清单」解析成可查询的题号列表。
///
/// 典型输入是用户或 AI 从整卷卷面抄下来的题号：
///
///     1, 2, 3
///     TR-00001 – TR-00010
///     12、15、20..25
///
/// 规则（宁缺毋滥，不猜）：
/// - 分隔符：半角/全角逗号、顿号、半角/全角分号，以及任意空白（空格、换行、
///   制表符、全角空格等）；
/// - 每一小段先按单个题号解析（复用 [parseQuestionNumberQuery]，认
///   `TR-00042` / `tr-42` / `#42` / `00042` / `42`）；
/// - 区间连接符只认 `..`、`-`、`~`、`—`（连接符两侧允许空白，例如 `1 - 5`）；
///   两端都必须是合法单号，升序/降序都展开成升序序列；有一端不合法整段拒绝；
/// - 结果去重并按题号升序；超过 `maxCount` 截断
///   （[QuestionSerialBatch.truncated] 为 true）；
/// - 认不出的段进入 [QuestionSerialBatch.rejectedSegments]，顺序与输入一致；
/// - 空串、纯分隔符返回空结果；永不抛异常；纯函数，同一输入永远同一输出。
///
/// 本文件不读数据库、不依赖时间/随机数；调用方负责把
/// [QuestionSerialBatch.serials] 交给题库查询层。
library;

import 'question_number_query.dart';

/// 单次批量解析最多返回的题号数量硬上限。
///
/// `parseQuestionSerialBatch` 的 `maxCount` 可以更小；即使调用方传入更大的数字，
/// 输出也不会超过这个值（防止 `1..999999999` 这类输入把内存撑爆）。
/// 超过时 [QuestionSerialBatch.truncated] 仍为 true。
const int kQuestionSerialBatchHardLimit = 100000;

/// 一次题号批量解析的结果。
///
/// 不可变值对象：解析器返回的 [serials] 与 [rejectedSegments] 都是
/// [List.unmodifiable] 包装；调用方直接构造时需自行遵守只读约定。
///
/// 相等性按内容判断：[serials]、[rejectedSegments]、[truncated] 都相同才相等。
class QuestionSerialBatch {
  const QuestionSerialBatch({
    required this.serials,
    required this.rejectedSegments,
    this.truncated = false,
  });

  /// 空的批量结果：没有题号、没有拒绝段、未截断。
  const QuestionSerialBatch.empty()
      : serials = const <int>[],
        rejectedSegments = const <String>[],
        truncated = false;

  /// 去重并升序排序后的题号（全部大于等于 1）。
  final List<int> serials;

  /// 认不出的原始段（去首尾空白；区间段保留为一行），顺序与输入一致。
  final List<String> rejectedSegments;

  /// 是否因为 `maxCount`（或内存硬上限）截断了题号。
  final bool truncated;

  /// 是否没有任何题号。
  bool get isEmpty => serials.isEmpty;

  /// 题号数量。
  int get count => serials.length;

  /// 稳定键（snake_case）：`serials` / `count` / `rejected_segments` /
  /// `truncated`。
  Map<String, Object?> toJson() => <String, Object?>{
        'serials': serials,
        'count': count,
        'rejected_segments': rejectedSegments,
        'truncated': truncated,
      };

  @override
  bool operator ==(Object other) =>
      other is QuestionSerialBatch &&
      other.truncated == truncated &&
      _sameInts(other.serials, serials) &&
      _sameStrings(other.rejectedSegments, rejectedSegments);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(serials),
        Object.hashAll(rejectedSegments),
        truncated,
      );

  @override
  String toString() {
    final int rejected = rejectedSegments.length;
    return 'QuestionSerialBatch(count: $count, rejected: $rejected, '
        'truncated: $truncated)';
  }
}

/// 解析「人写的题号清单」；空串/纯分隔符返回空结果，永不抛异常。
///
/// [maxCount] 是返回题号数量上限（默认 200，小于等于 0 时返回空题号列表并把
/// 有内容的结果标成截断）；实际输出还受 [kQuestionSerialBatchHardLimit] 约束。
QuestionSerialBatch parseQuestionSerialBatch(String raw, {int maxCount = 200}) {
  final List<_SerialRange> ranges = <_SerialRange>[];
  final List<String> rejected = <String>[];
  _scanPieces(raw, ranges, rejected);

  final List<_SerialRange> merged = _mergeRanges(ranges);
  final int total = _totalCount(merged);
  int effectiveMax = maxCount;
  if (effectiveMax > kQuestionSerialBatchHardLimit) {
    effectiveMax = kQuestionSerialBatchHardLimit;
  }

  if (effectiveMax <= 0) {
    return QuestionSerialBatch(
      serials: const <int>[],
      rejectedSegments: List<String>.unmodifiable(rejected),
      truncated: ranges.isNotEmpty,
    );
  }

  final bool truncated = total > effectiveMax;
  final int limit = truncated ? effectiveMax : total;
  return QuestionSerialBatch(
    serials: List<int>.unmodifiable(_expand(merged, limit)),
    rejectedSegments: List<String>.unmodifiable(rejected),
    truncated: truncated,
  );
}

/// 一个闭区间 [low]..[high]（含端点，low <= high）。
class _SerialRange {
  const _SerialRange(this.low, this.high);

  factory _SerialRange.between(int first, int second) => first <= second
      ? _SerialRange(first, second)
      : _SerialRange(second, first);

  final int low;
  final int high;
}

/// 区间连接符；`-` 放最后，避免抢在更长的连接符前面切开。
const List<String> _rangeConnectors = <String>['..', '~', '—', '-'];

/// 把输入按「清单分隔符」切成小块（空白不在这里切，留给小块内分词）。
void _scanPieces(
  String raw,
  List<_SerialRange> ranges,
  List<String> rejected,
) {
  final StringBuffer piece = StringBuffer();
  for (final int rune in raw.runes) {
    if (_isListSeparator(rune)) {
      _consumePiece(piece.toString(), ranges, rejected);
      piece.clear();
    } else {
      piece.writeCharCode(rune);
    }
  }
  _consumePiece(piece.toString(), ranges, rejected);
}

/// 处理一个清单小块：按空白分词，再拼出单号/区间。
void _consumePiece(
  String piece,
  List<_SerialRange> ranges,
  List<String> rejected,
) {
  final List<String> tokens = _tokenize(piece);
  var index = 0;
  while (index < tokens.length) {
    if (index + 2 < tokens.length && _isRangeConnector(tokens[index + 1])) {
      final QuestionNumberQuery? left = parseQuestionNumberQuery(tokens[index]);
      final QuestionNumberQuery? right =
          parseQuestionNumberQuery(tokens[index + 2]);
      if (left != null && right != null) {
        ranges.add(_SerialRange.between(left.serialNo, right.serialNo));
      } else {
        rejected.add(
          <String>[tokens[index], tokens[index + 1], tokens[index + 2]]
              .join(' '),
        );
      }
      index += 3;
      continue;
    }

    final QuestionNumberQuery? single = parseQuestionNumberQuery(tokens[index]);
    if (single != null) {
      ranges.add(_SerialRange.between(single.serialNo, single.serialNo));
      index += 1;
      continue;
    }

    final _SerialRange? range = _rangeOfToken(tokens[index]);
    if (range != null) {
      ranges.add(range);
      index += 1;
      continue;
    }

    rejected.add(tokens[index]);
    index += 1;
  }
}

/// 从「连写」的区间 token 里切出两端，例如 `1..5`、`TR-1-TR-5`、`5—1`。
_SerialRange? _rangeOfToken(String token) {
  for (final String connector in _rangeConnectors) {
    var index = token.indexOf(connector);
    while (index > 0) {
      final int end = index + connector.length;
      if (end >= token.length) break;
      final QuestionNumberQuery? left =
          parseQuestionNumberQuery(token.substring(0, index));
      final QuestionNumberQuery? right =
          parseQuestionNumberQuery(token.substring(end));
      if (left != null && right != null) {
        return _SerialRange.between(left.serialNo, right.serialNo);
      }
      index = token.indexOf(connector, index + 1);
    }
  }
  return null;
}

/// 把区间排序并合并重叠/相邻区间，得到互不相交的升序区间。
List<_SerialRange> _mergeRanges(List<_SerialRange> ranges) {
  if (ranges.isEmpty) return const <_SerialRange>[];
  final List<_SerialRange> sorted = List<_SerialRange>.of(ranges)
    ..sort((_SerialRange a, _SerialRange b) => a.low.compareTo(b.low));
  final List<_SerialRange> merged = <_SerialRange>[];
  var low = sorted.first.low;
  var high = sorted.first.high;
  for (var index = 1; index < sorted.length; index++) {
    final _SerialRange range = sorted[index];
    if (range.low <= high + 1) {
      if (range.high > high) high = range.high;
    } else {
      merged.add(_SerialRange(low, high));
      low = range.low;
      high = range.high;
    }
  }
  merged.add(_SerialRange(low, high));
  return merged;
}

/// 互不相交区间里的题号总数。
int _totalCount(List<_SerialRange> ranges) {
  var total = 0;
  for (final _SerialRange range in ranges) {
    total += range.high - range.low + 1;
  }
  return total;
}

/// 按升序展开前 [limit] 个题号。
List<int> _expand(List<_SerialRange> ranges, int limit) {
  final List<int> serials = <int>[];
  for (final _SerialRange range in ranges) {
    for (var serial = range.low; serial <= range.high; serial++) {
      if (serials.length >= limit) return serials;
      serials.add(serial);
    }
  }
  return serials;
}

/// 按空白切成 token（全角空格、不换行空格等也算空白）。
List<String> _tokenize(String piece) {
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();
  for (final int rune in piece.runes) {
    if (_isWhitespace(rune)) {
      if (current.isNotEmpty) {
        tokens.add(current.toString());
        current.clear();
      }
    } else {
      current.writeCharCode(rune);
    }
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

/// 清单分隔符：半角逗号、全角逗号、顿号、半角分号、全角分号。
bool _isListSeparator(int rune) =>
    rune == 0x2C ||
    rune == 0xFF0C ||
    rune == 0x3001 ||
    rune == 0x3B ||
    rune == 0xFF1B;

/// 连接符单独成段（两侧有空白）时也认。
bool _isRangeConnector(String token) => _rangeConnectors.contains(token);

/// 空白判定：按 Unicode 空白字符表，不依赖正则。
bool _isWhitespace(int rune) {
  if (rune == 0x20 || rune == 0xA0 || rune == 0x1680 || rune == 0x3000) {
    return true;
  }
  if (rune == 0xFEFF) return true;
  if (rune >= 0x09 && rune <= 0x0D) return true;
  if (rune >= 0x2000 && rune <= 0x200A) return true;
  return rune == 0x2028 || rune == 0x2029 || rune == 0x202F || rune == 0x205F;
}

/// 两个 int 列表内容相等。
bool _sameInts(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// 两个 String 列表内容相等。
bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
