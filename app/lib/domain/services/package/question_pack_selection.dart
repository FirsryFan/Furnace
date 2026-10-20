/// 题库包（.tqb）「选择性导出」的筛选条件（纯逻辑）。
///
/// 只回答一个问题：**这条题目记录该不该进这次导出的题库包**。
/// 不读数据库、不读文件、不碰 Flutter：导出流程先用
/// [questionPackFieldsMatchSelection] 在数据层筛 `questions` 行，
/// 避免为未选中的题目读配图/答案截图字节，再把选中的行解码成
/// [QuestionPackRecord] 交给 zip 容器层写包。
///
/// 口径（与测试一一对应）：
/// - 空条件（[QuestionPackSelection.isEmpty]）匹配全部；某个集合为空表示
///   该维度不约束；多个维度之间是 AND。
/// - 学科 key 与来源等级比较前两边都 `trim`，区分大小写（内部是 ASCII key）。
/// - 标签路径按「每题标签集合与条件标签集合求交集，非空即命中」判断；
///   两边都先 `trim`，空串一律忽略（条件里的空串不约束任何题）。
/// - 题号区间含两端；只给 [QuestionPackSelection.serialFrom] 是 `>=`，只给
///   [QuestionPackSelection.serialTo] 是 `<=`；区间反向时匹配内部交换归一；
///   边界 `<= 0` 视为该端未给。题目没有题号（`serialNo == null`）时，只要
///   存在有效区间就不命中。
/// - 不修改入参、永不抛异常（调用方传错类型除外）。
library;

import 'question_pack_record.dart';

final RegExp _kAsciiDigitsPattern = RegExp(r'^[0-9]+$');

/// 题库包选择性导出的筛选条件。
///
/// 值对象：集合按内容比较、与迭代顺序无关；[toJson] 输出排序后的集合，
/// 保证同一条件永远得到同一份 JSON。
class QuestionPackSelection {
  const QuestionPackSelection({
    this.subjectKeys = const <String>{},
    this.sourceLevels = const <String>{},
    this.tagPaths = const <String>{},
    this.serialFrom,
    this.serialTo,
  });

  /// 学科 key 集合，例如 `{'math', 'physics'}`；空集合表示不按学科约束。
  final Set<String> subjectKeys;

  /// 来源等级集合，例如 `{'exam', 'textbook'}`；空集合表示不按来源约束。
  final Set<String> sourceLevels;

  /// 标签路径集合，例如 `{'数学', '数学/函数'}`；空集合表示不按标签约束。
  final Set<String> tagPaths;

  /// 题号下界（含）；`null` 或 `<= 0` 表示不限下界。
  final int? serialFrom;

  /// 题号上界（含）；`null` 或 `<= 0` 表示不限上界。
  final int? serialTo;

  /// 三个集合都空且没有题号区间时，这个条件匹配全部记录。
  bool get isEmpty =>
      subjectKeys.isEmpty &&
      sourceLevels.isEmpty &&
      tagPaths.isEmpty &&
      !hasSerialRange;

  /// 是否给了题号区间的一端（哪怕该端值 `<= 0` 实际不生效）。
  bool get hasSerialRange => serialFrom != null || serialTo != null;

  /// snake_case 机器可读形式；五个键始终存在，集合元素升序排序。
  Map<String, Object?> toJson() => <String, Object?>{
        'subject_keys': _sortedValues(subjectKeys),
        'source_levels': _sortedValues(sourceLevels),
        'tag_paths': _sortedValues(tagPaths),
        'serial_from': serialFrom,
        'serial_to': serialTo,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackSelection &&
        _setEquals(other.subjectKeys, subjectKeys) &&
        _setEquals(other.sourceLevels, sourceLevels) &&
        _setEquals(other.tagPaths, tagPaths) &&
        other.serialFrom == serialFrom &&
        other.serialTo == serialTo;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(subjectKeys),
        Object.hashAllUnordered(sourceLevels),
        Object.hashAllUnordered(tagPaths),
        serialFrom,
        serialTo,
      );

  @override
  String toString() => 'QuestionPackSelection('
      'subjectKeys: ${_sortedValues(subjectKeys)}, '
      'sourceLevels: ${_sortedValues(sourceLevels)}, '
      'tagPaths: ${_sortedValues(tagPaths)}, '
      'serialFrom: $serialFrom, serialTo: $serialTo)';
}

/// 一条已解码的题目记录是否命中筛选条件。
///
/// 导出流程通常直接用 [questionPackFieldsMatchSelection] 在数据层筛行；
/// 这个函数用于对已经组装好的 [QuestionPackRecord] 再判一次。
bool questionPackRecordMatchesSelection(
  QuestionPackRecord record,
  QuestionPackSelection selection,
) {
  return _SelectionMatcher(selection).matches(
    subjectKey: record.subjectKey,
    sourceLevel: record.sourceLevel,
    serialNo: record.serialNo,
    tagPaths: record.tagPaths,
  );
}

/// 从记录列表里挑出命中条件的记录，保持原顺序，返回不可变列表。
///
/// 空条件返回全部记录（仍是新列表，不把 `records` 直接交出去）。
List<QuestionPackRecord> selectQuestionPackRecords({
  required List<QuestionPackRecord> records,
  required QuestionPackSelection selection,
}) {
  final _SelectionMatcher matcher = _SelectionMatcher(selection);
  final List<QuestionPackRecord> selected = <QuestionPackRecord>[];
  for (final QuestionPackRecord record in records) {
    if (matcher.matches(
      subjectKey: record.subjectKey,
      sourceLevel: record.sourceLevel,
      serialNo: record.serialNo,
      tagPaths: record.tagPaths,
    )) {
      selected.add(record);
    }
  }
  return List<QuestionPackRecord>.unmodifiable(selected);
}

/// 数据层筛行版本：只拿字段值判断，不需要组装整条 [QuestionPackRecord]。
///
/// 导出流程先对数据库查询结果调用本函数，避免为未选中的题目读媒体字节。
bool questionPackFieldsMatchSelection({
  required String subjectKey,
  required String sourceLevel,
  int? serialNo,
  required Iterable<String> tagPaths,
  required QuestionPackSelection selection,
}) {
  return _SelectionMatcher(selection).matches(
    subjectKey: subjectKey,
    sourceLevel: sourceLevel,
    serialNo: serialNo,
    tagPaths: tagPaths,
  );
}

/// 把用户在输入框里写的题号边界规整成正整数。
///
/// `trim` 后必须是纯半角数字：`'0012'` → `12`，`' 7 '` → `7`，`'0'` → `0`；
/// 空串、`null`、带符号、小数、全角数字、超出 int 范围的串都返回 `null`。
/// 返回值 `<= 0` 时由筛选逻辑视为该端未给。
int? normalizeSerialBound(String? raw) {
  if (raw == null) {
    return null;
  }
  final String trimmed = raw.trim();
  if (trimmed.isEmpty || !_kAsciiDigitsPattern.hasMatch(trimmed)) {
    return null;
  }
  return int.tryParse(trimmed);
}

/// 条件预处理后的匹配器：集合 trim、去空串，题号区间归一，每次筛选只算一次。
class _SelectionMatcher {
  _SelectionMatcher(QuestionPackSelection selection)
      : subjectKeys = _normalizedValues(selection.subjectKeys),
        sourceLevels = _normalizedValues(selection.sourceLevels),
        tagPaths = _normalizedValues(selection.tagPaths),
        serialRange = _SerialRange.of(selection);

  final Set<String> subjectKeys;
  final Set<String> sourceLevels;
  final Set<String> tagPaths;
  final _SerialRange? serialRange;

  bool matches({
    required String subjectKey,
    required String sourceLevel,
    int? serialNo,
    required Iterable<String> tagPaths,
  }) {
    if (subjectKeys.isNotEmpty && !subjectKeys.contains(subjectKey.trim())) {
      return false;
    }
    if (sourceLevels.isNotEmpty && !sourceLevels.contains(sourceLevel.trim())) {
      return false;
    }
    if (this.tagPaths.isNotEmpty) {
      final Set<String> recordTags = _normalizedValues(tagPaths);
      if (recordTags.intersection(this.tagPaths).isEmpty) {
        return false;
      }
    }
    final _SerialRange? range = serialRange;
    if (range != null) {
      if (serialNo == null ||
          serialNo < range.lower ||
          serialNo > range.upper) {
        return false;
      }
    }
    return true;
  }
}

/// 归一化后的题号区间：两端都有效才存在。
class _SerialRange {
  const _SerialRange._(this.lower, this.upper);

  final int lower;
  final int upper;

  static _SerialRange? of(QuestionPackSelection selection) {
    final int? from = _effectiveBound(selection.serialFrom);
    final int? to = _effectiveBound(selection.serialTo);
    if (from == null && to == null) {
      return null;
    }
    final int lower = from ?? 1;
    final int upper = to ?? _unboundedAbove;
    return lower <= upper
        ? _SerialRange._(lower, upper)
        : _SerialRange._(upper, lower);
  }

  /// 只给 `serialFrom` 时上界保持开放。int 在 Dart VM 上是 64 位有符号整数，
  /// 这里用 int 的最大值当无界哨兵（题号本身远小于它）。
  static const int _unboundedAbove = 9223372036854775807;

  static int? _effectiveBound(int? value) {
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }
}

Set<String> _normalizedValues(Iterable<String> values) {
  final Set<String> normalized = <String>{};
  for (final String value in values) {
    final String trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      normalized.add(trimmed);
    }
  }
  return normalized;
}

List<String> _sortedValues(Set<String> values) {
  final List<String> sorted = values.toList()..sort();
  return List<String>.unmodifiable(sorted);
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final String value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}
