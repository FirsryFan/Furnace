/// 复习卡组键：按「专题标签 + 能力 A」生成稳定、可读、可排序的卡组键（纯逻辑）。
///
/// 背景：`FURNACE-PIPELINE-SPEC-v1.md` §7 M3 要求把「错题 / 变式」按
/// 「专题标签 + 能力 A」挂到复习队列（A1–A10 见 §5.6，字段建议见 §5.9）。
/// 本文件只做**键的生成与解析**，不读写数据库、不 import drift/Flutter：
/// 后续由服务层用这些键把题挂进 FSRS 卡组，本层不决定卡组怎么落库。
///
/// 键格式（`|` 分隔四个字段，标签路径内部仍用 `/`）：
///
///     review_deck|<subjectKey>|<capabilityCode>|<tagPath>
///     review_deck|physics|A3|物理/高中物理/力学
///
/// * `subjectKey`：学科键（trim 后非空；不能含分隔符 `|`，否则无法安全编码）；
/// * `capabilityCode`：通用能力 A1–A10（大小写不敏感，统一成大写）；
/// * `tagPath`：专题标签路径（按 `/` 切段，逐段 trim、丢空段、重新拼；
///   任一段含 `|` 的整条路径丢弃，不猜）；
/// * 同一专题标签 + 同一能力 = 一个卡组；多标签 / 多能力产出**交叉积**，
///   重复输入先去重；输出顺序固定为「能力编号升序（A1…A10）→ 标签路径字典序」，
///   与输入顺序无关；
/// * 学科键、标签路径、能力任一缺失（清洗后为空）→ 返回空列表：卡组必须同时有
///   专题与能力，只有一边不建卡组；
/// * 纯函数：不读 IO、不依赖时间/随机数，同一输入永远同一输出，不抛异常。
///
/// 解析用 [parseReviewDeckKey]：只接受**规范形式**（字段没有多余空白、标签路径没有
/// 空段/重复斜杠），脏数据返回 null，**不抛异常**；最外层空白（复制粘贴带的）会先
/// trim 掉。排序用 [compareReviewDeckKeys]：能力按编号而不是字符串比较，
/// 所以 A2 排在 A10 前面；非法键排在合法键之后，都非法时按原文比较，保证严格全序。
library;

/// 卡组键的固定前缀。
const String kReviewDeckKeyPrefix = 'review_deck';

/// 卡组键的字段分隔符（标签路径内部仍用 `/`）。
const String kReviewDeckKeySeparator = '|';

/// 通用能力编号（`FURNACE-PIPELINE-SPEC-v1.md` §5.6 的 A1–A10），顺序即能力序号。
const List<String> kReviewDeckCapabilityCodes = <String>[
  'A1',
  'A2',
  'A3',
  'A4',
  'A5',
  'A6',
  'A7',
  'A8',
  'A9',
  'A10',
];

/// 一条解析成功的卡组键（不可变值对象）。
///
/// 一般只用 [parseReviewDeckKey] 构造；直接调用构造函数时调用方要保证
/// [subjectKey]/[tagPath] 已是规范形式、[capabilityCode] 在
/// [kReviewDeckCapabilityCodes] 里。
class ReviewDeckKey {
  const ReviewDeckKey({
    required this.subjectKey,
    required this.capabilityCode,
    required this.tagPath,
  });

  /// 学科键（如 `physics` / `数学`）。
  final String subjectKey;

  /// 通用能力编号（`A1`–`A10`）。
  final String capabilityCode;

  /// 专题标签路径（`/` 分段，规范形式）。
  final String tagPath;

  /// 标签路径的段（`物理/高中物理/力学` → 三段）。
  List<String> get tagSegments => List<String>.unmodifiable(tagPath.split('/'));

  /// 能力序号（`A3` → 3，`A10` → 10）；不在 A1–A10 里时为 0。
  int get capabilityIndex =>
      kReviewDeckCapabilityCodes.indexOf(capabilityCode) + 1;

  /// 能力编号是否在 A1–A10 里（构造函数不校验，这里给出只读判断）。
  bool get isKnownCapability => capabilityIndex > 0;

  /// 重新拼成规范键（与 [parseReviewDeckKey] 互为逆运算）。
  String toDeckKeyString() => _buildReviewDeckKey(
        subjectKey: subjectKey,
        capabilityCode: capabilityCode,
        tagPath: tagPath,
      );

  @override
  bool operator ==(Object other) =>
      other is ReviewDeckKey &&
      other.subjectKey == subjectKey &&
      other.capabilityCode == capabilityCode &&
      other.tagPath == tagPath;

  @override
  int get hashCode => Object.hash(subjectKey, capabilityCode, tagPath);

  @override
  String toString() => 'ReviewDeckKey($subjectKey, $capabilityCode, $tagPath)';
}

/// 生成卡组键（纯函数，不抛异常）。
///
/// 输入先规范化（trim / 丢弃空段 / 能力统一大写 / 去重），再按「能力编号升序 →
/// 标签路径字典序」输出交叉积；输入顺序不影响结果。
///
/// 学科键清洗后为空（或含分隔符 `|`）→ 返回空列表；没有任何有效标签路径、或
/// 没有任何有效能力编号 → 也返回空列表（卡组必须同时有专题与能力）。
List<String> reviewDeckKey({
  required String subjectKey,
  required List<String> tagPaths,
  required List<String> capabilityCodes,
}) {
  final String? subject = _normalizeSubject(subjectKey);
  if (subject == null) {
    return const <String>[];
  }

  final Set<String> tags = <String>{};
  for (final String raw in tagPaths) {
    final String? tagPath = _normalizeTagPath(raw);
    if (tagPath != null) {
      tags.add(tagPath);
    }
  }
  final Set<String> capabilities = <String>{};
  for (final String raw in capabilityCodes) {
    final String? code = _normalizeCapability(raw);
    if (code != null) {
      capabilities.add(code);
    }
  }
  if (tags.isEmpty || capabilities.isEmpty) {
    return const <String>[];
  }

  final List<String> sortedTags = tags.toList()
    ..sort((String a, String b) => a.compareTo(b));
  final List<String> sortedCapabilities = capabilities.toList()
    ..sort((String a, String b) =>
        _capabilityRank(a).compareTo(_capabilityRank(b)));
  final List<String> keys = <String>[];
  for (final String capabilityCode in sortedCapabilities) {
    for (final String tagPath in sortedTags) {
      keys.add(_buildReviewDeckKey(
        subjectKey: subject,
        capabilityCode: capabilityCode,
        tagPath: tagPath,
      ));
    }
  }
  return List<String>.unmodifiable(keys);
}

/// 解析一条卡组键；不是规范形式返回 null（不抛异常）。
///
/// 只容错最外层空白：字段两端多余空白、标签路径的空段/重复斜杠都算脏数据。
ReviewDeckKey? parseReviewDeckKey(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final List<String> parts = text.split(kReviewDeckKeySeparator);
  if (parts.length != 4) {
    return null;
  }
  if (parts[0] != kReviewDeckKeyPrefix) {
    return null;
  }
  final String subjectKey = parts[1];
  if (!_isCanonicalSubject(subjectKey)) {
    return null;
  }
  final String capabilityCode = parts[2];
  if (_capabilityRank(capabilityCode) == 0) {
    return null;
  }
  final String tagPath = parts[3];
  if (!_isCanonicalTagPath(tagPath)) {
    return null;
  }
  return ReviewDeckKey(
    subjectKey: subjectKey,
    capabilityCode: capabilityCode,
    tagPath: tagPath,
  );
}

/// 字符串是不是一条合法的卡组键。
bool isReviewDeckKey(String raw) => parseReviewDeckKey(raw) != null;

/// 比较两条卡组键（给列表排序用，严格全序）。
///
/// 合法键按「学科 → 能力编号 → 标签路径」比较（A2 在 A10 前面）；非法键排在合法
/// 键之后；两条都非法时按原文比较，保证比较结果传递且与排序算法无关。
int compareReviewDeckKeys(String a, String b) {
  final ReviewDeckKey? ka = parseReviewDeckKey(a);
  final ReviewDeckKey? kb = parseReviewDeckKey(b);
  if (ka != null && kb != null) {
    final int bySubject = ka.subjectKey.compareTo(kb.subjectKey);
    if (bySubject != 0) {
      return bySubject;
    }
    final int byCapability = ka.capabilityIndex.compareTo(kb.capabilityIndex);
    if (byCapability != 0) {
      return byCapability;
    }
    return ka.tagPath.compareTo(kb.tagPath);
  }
  if (ka != null) {
    return -1;
  }
  if (kb != null) {
    return 1;
  }
  return a.compareTo(b);
}

/// 排序卡组键列表并去重（返回不可变列表；同一列表多次排序结果相同）。
List<String> sortedReviewDeckKeys(Iterable<String> keys) {
  final List<String> sorted = keys.toSet().toList()
    ..sort(compareReviewDeckKeys);
  return List<String>.unmodifiable(sorted);
}

String _buildReviewDeckKey({
  required String subjectKey,
  required String capabilityCode,
  required String tagPath,
}) =>
    '$kReviewDeckKeyPrefix$kReviewDeckKeySeparator$subjectKey'
    '$kReviewDeckKeySeparator$capabilityCode'
    '$kReviewDeckKeySeparator$tagPath';

/// 能力编号的序号（A1 → 1，A10 → 10）；不认识返回 0。
int _capabilityRank(String capabilityCode) {
  final int index = kReviewDeckCapabilityCodes.indexOf(capabilityCode);
  return index < 0 ? 0 : index + 1;
}

String? _normalizeSubject(String raw) {
  final String subject = raw.trim();
  if (!_isCanonicalSubject(subject)) {
    return null;
  }
  return subject;
}

bool _isCanonicalSubject(String subject) {
  if (subject.isEmpty) {
    return false;
  }
  if (subject != subject.trim()) {
    return false;
  }
  if (subject.contains(kReviewDeckKeySeparator)) {
    return false;
  }
  return !subject.contains('\n') && !subject.contains('\r');
}

String? _normalizeCapability(String raw) {
  final String code = raw.trim().toUpperCase();
  return _capabilityRank(code) == 0 ? null : code;
}

String? _normalizeTagPath(String raw) {
  final List<String> segments = <String>[];
  for (final String part in raw.split('/')) {
    final String segment = part.trim();
    if (segment.isEmpty) {
      continue;
    }
    if (segment.contains(kReviewDeckKeySeparator) ||
        segment.contains('\n') ||
        segment.contains('\r')) {
      return null;
    }
    segments.add(segment);
  }
  if (segments.isEmpty) {
    return null;
  }
  return segments.join('/');
}

bool _isCanonicalTagPath(String tagPath) {
  if (tagPath.isEmpty) {
    return false;
  }
  for (final String segment in tagPath.split('/')) {
    if (segment.isEmpty || segment != segment.trim()) {
      return false;
    }
    if (segment.contains(kReviewDeckKeySeparator) ||
        segment.contains('\n') ||
        segment.contains('\r')) {
      return false;
    }
  }
  return true;
}
