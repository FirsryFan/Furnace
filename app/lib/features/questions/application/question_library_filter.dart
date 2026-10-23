/// 题库页筛选的纯逻辑：学科 + 标签子树 + 搜索文字。
///
/// 题库页（`question_bank_page.dart`）已有学科下拉，接下来要加「搜索框 + 标签
/// 多选」。筛选判定必须能脱离界面单独测：界面只负责收集输入、渲染命中的行，
/// 判定规则（尤其标签按子树匹配）只该有一份实现，所以抽成本文件。
///
/// 四层条件之间是 **AND**；每一层内部：
/// * 学科：空 = 不限；否则按 `entry.subjectKey` 精确相等（大小写敏感）。
/// * 标签：空集 = 不限；否则多选 **ANY**，且按**子树**匹配——命中条件为
///   `q == p` 或 `q.startsWith('$p/')`（p 是筛选路径，q 是题目直挂的标签路径），
///   即选了 `文化课/学科` 也会命中挂在 `文化课/学科/数学` 的题；反向不成立。
/// * 文字：空 = 不限；先按**多段题号清单**解析（`1-3` / `TR-2, 4` / `1,3-4`），
///   规则完全复用 [parseQuestionSerialBatch]（本文件不重写解析；清单里有一段认
///   不出时整段不算命中），题号在清单里即真；再按单号解析（复用
///   [parseQuestionNumberQuery] 与 [matchQuestionSerial]，认 `TR-42` / `#42` /
///   `42` / 全角数字），题号命中即真；否则对题名、题干、题号标签、学科、来源、
///   标签路径做大小写不敏感子串匹配（行为只增不改：`2023` 这类输入仍能搜题干）。
/// * 错题本：关 = 不限；开则只留 `hasWrongAttempt` 为真的题（自测答错过至少一次）。
///   作答记录来自 `question_attempts`，由读表层投影成 [QuestionLibraryEntry.wrongAttemptCount]。
///
/// 纯逻辑：不读库、不依赖时间/随机数、不 import 界面或 `dart:io`；任何输入都
/// 不抛异常。输入字段不在构造时归一（保持 `const` 可用），判定时按需 trim。
library;

import '../../../domain/services/questions/question_number_query.dart';
import '../../../domain/services/questions/question_serial_batch.dart';
import 'question_library_reader.dart';

/// 题库列表的筛选条件（不可变值对象）。
///
/// 字段是用户原始输入，不在构造时归一：`subjectKey` / `text` 在判定时 trim，
/// `tagPaths` 在判定时 trim、去空。`isEmpty` 按归一后的语义算，所以
/// `QuestionLibraryFilter(subjectKey: '  ')` 与默认构造等价（都是不限）。
class QuestionLibraryFilter {
  const QuestionLibraryFilter({
    this.subjectKey = '',
    this.tagPaths = const <String>{},
    this.text = '',
    this.onlyWrong = false,
  });

  /// 不限任何条件。
  static const QuestionLibraryFilter empty = QuestionLibraryFilter();

  /// 学科键；trim 后空 = 不限学科。
  final String subjectKey;

  /// 标签路径多选（ANY）；空集（或用空白项凑出的空集）= 不限标签。
  final Set<String> tagPaths;

  /// 搜索框原文；trim 后空 = 不搜索。
  final String text;

  /// 错题本模式：只看自测答错过的题。
  final bool onlyWrong;

  /// 是否没有任何有效筛选条件：学科、标签（去空白后）、文字都为空、错题本关。
  bool get isEmpty =>
      subjectKey.trim().isEmpty &&
      _normalizedPaths(tagPaths).isEmpty &&
      text.trim().isEmpty &&
      !onlyWrong;

  /// [isEmpty] 的取反。
  bool get isNotEmpty => !isEmpty;

  /// 复制并替换部分字段；传入 `null` 表示保留原值（字段本身非空类型）。
  QuestionLibraryFilter copyWith({
    String? subjectKey,
    Set<String>? tagPaths,
    String? text,
    bool? onlyWrong,
  }) {
    return QuestionLibraryFilter(
      subjectKey: subjectKey ?? this.subjectKey,
      tagPaths: tagPaths ?? this.tagPaths,
      text: text ?? this.text,
      onlyWrong: onlyWrong ?? this.onlyWrong,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuestionLibraryFilter &&
      other.subjectKey == subjectKey &&
      _sameStringSet(other.tagPaths, tagPaths) &&
      other.text == text &&
      other.onlyWrong == onlyWrong;

  @override
  int get hashCode => Object.hash(
        subjectKey,
        Object.hashAllUnordered(tagPaths),
        text,
        onlyWrong,
      );

  @override
  String toString() =>
      'QuestionLibraryFilter(subjectKey: $subjectKey, tagPaths: $tagPaths, '
      'text: $text, onlyWrong: $onlyWrong)';
}

/// 判断一道题是否命中筛选条件；`filter.isEmpty` 时全部命中。
bool questionLibraryEntryMatches(
  QuestionLibraryEntry entry,
  QuestionLibraryFilter filter,
) {
  if (filter.isEmpty) {
    return true;
  }

  final String subjectKey = filter.subjectKey.trim();
  if (subjectKey.isNotEmpty && entry.subjectKey != subjectKey) {
    return false;
  }

  if (filter.onlyWrong && !entry.hasWrongAttempt) {
    return false;
  }

  final Set<String> tagPaths = _normalizedPaths(filter.tagPaths);
  if (tagPaths.isNotEmpty && !_matchesAnyTagPath(entry.tagPaths, tagPaths)) {
    return false;
  }

  final String text = filter.text.trim();
  if (text.isEmpty) {
    return true;
  }
  return _matchesText(entry, text);
}

/// 过滤并保序返回；结果不可变。`filter.isEmpty` 时返回全部条目的不可变副本。
List<QuestionLibraryEntry> filterQuestionLibraryEntries(
  Iterable<QuestionLibraryEntry> entries,
  QuestionLibraryFilter filter,
) {
  if (filter.isEmpty) {
    return List<QuestionLibraryEntry>.unmodifiable(entries);
  }
  final List<QuestionLibraryEntry> matched = <QuestionLibraryEntry>[
    for (final QuestionLibraryEntry entry in entries)
      if (questionLibraryEntryMatches(entry, filter)) entry,
  ];
  return List<QuestionLibraryEntry>.unmodifiable(matched);
}

/// 标签子树匹配：任一筛选路径 p 被某条题目路径 q 覆盖即真。
bool _matchesAnyTagPath(
  Iterable<String> entryTagPaths,
  Set<String> filterTagPaths,
) {
  for (final String raw in entryTagPaths) {
    final String q = raw.trim();
    if (q.isEmpty) {
      continue;
    }
    for (final String p in filterTagPaths) {
      if (q == p || q.startsWith('$p/')) {
        return true;
      }
    }
  }
  return false;
}

/// 文字匹配：多段题号 / 单号命中即真，否则大小写不敏感子串。
bool _matchesText(QuestionLibraryEntry entry, String text) {
  // 多段号清单（`1-3`、`TR-2, 4`、`1,3-4`）：整段都认得出才算命中；只要有一段
  // 认不出（如 `2-3 函数`）就整段不认，退回下面的单号 / 子串老路径——行为只增
  // 不改。解析规则见 [parseQuestionSerialBatch]，本文件不重写。
  final QuestionSerialBatch batch = parseQuestionSerialBatch(text);
  if (batch.serials.isNotEmpty &&
      batch.rejectedSegments.isEmpty &&
      entry.serialNo != null &&
      batch.serials.contains(entry.serialNo)) {
    return true;
  }
  final QuestionNumberQuery? query = parseQuestionNumberQuery(text);
  if (query != null && matchQuestionSerial(entry.serialNo, query)) {
    return true;
  }
  final String lower = text.toLowerCase();
  final List<String> candidates = <String>[
    entry.title ?? '',
    entry.stem,
    entry.serialLabel,
    entry.subjectKey,
    entry.sourceLabel,
    ...entry.tagPaths,
  ];
  for (final String candidate in candidates) {
    if (candidate.toLowerCase().contains(lower)) {
      return true;
    }
  }
  return false;
}

/// trim、去空后的路径集合（顺序无意义）。
Set<String> _normalizedPaths(Set<String> raw) {
  final Set<String> result = <String>{};
  for (final String path in raw) {
    final String trimmed = path.trim();
    if (trimmed.isNotEmpty) {
      result.add(trimmed);
    }
  }
  return result;
}

/// 集合内容相等（顺序无关）。
bool _sameStringSet(Set<String> a, Set<String> b) {
  if (identical(a, b)) {
    return true;
  }
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
