/// 题库包（.tqb）导入的合并计划与包内媒体路径（纯逻辑）。
///
/// 只做三件确定性的事：
/// 1. 给包里每道题一个决策：[QuestionPackAction.create]、
///    [QuestionPackAction.update] 或 [QuestionPackAction.skipDuplicate]；
/// 2. 汇总包内标签路径里题库还没有的路径（去重排序），并给可读告警；
/// 3. 生成包内媒体文件的规范路径 `media/q<题号>/<序号>.<扩展名>`。
///
/// 不读文件、不连数据库、不碰 Flutter：调用方负责解码 [QuestionPackRecord]，
/// 并提供题干指纹函数与题库现状（已有指纹、已有标签路径、组卷网题号到题库题目 id 的映射）。
///
/// 口径：
/// - 重复只看调用方给的指纹，不自己猜题干相似度；指纹函数对每道题恰好调用一次；
/// - 更新只靠组卷网题号认题（见 [questionPackSourceKey]）：
///   包里记录带题号、且调用方给出的映射里有同题号时，更新题库里那道题，
///   而不是按题干指纹跳过或新建一条重复题；
/// - 判定顺序（每道题）：① 按题号命中题库 → update；② 题库已有指纹 → skipDuplicate；
///   ③ 包内前面已有同题号 → skipDuplicate；④ 包内前面已有同指纹 → skipDuplicate；
///   ⑤ 以上都不命中 → create；
/// - 同一个题号在包内重复出现时，只有第一次出现的那条参与 ① 的更新判定，
///   后面的按 ②–⑤ 判定（通常落到「包内同题号」跳过），避免同一道题被计划两次更新；
/// - [planQuestionPackImport] 的 `updateExisting=false` 完全走旧语义（不认题号），
///   输出与升级前逐字段一致；
/// - 不静默丢题：每道题都有决策，跳过原因写进决策，缺失标签写进计划；
/// - 告警顺序固定：跳过重复的简短告警（按题序）→ 缺失标签告警（按路径字典序）
///   → 缺失标签超过 20 条时的截断说明；
/// - 永不抛异常：空包返回空计划（[QuestionPackImportPlan.isEmpty] 为 true）。
library;

import 'question_pack_record.dart';

/// 导入动作：新建、更新或跳过重复。
///
/// 只列合法值；写成 String 常量是为了让 [QuestionPackDecision.toJson]
/// 直接输出稳定的机器可读字符串。
class QuestionPackAction {
  const QuestionPackAction._();

  /// 新建这道题。
  static const String create = 'create';

  /// 更新题库里已有的同一道题（靠组卷网题号认题，见 [questionPackSourceKey]）。
  static const String update = 'update';

  /// 跳过重复题（题库已有同一道，或包内前面已经出现过）。
  static const String skipDuplicate = 'skip_duplicate';

  /// 动作的中文标签；未知值原样返回（不抛异常，方便展示历史数据）。
  static String labelZh(String action) {
    switch (action) {
      case create:
        return '新建';
      case update:
        return '更新';
      case skipDuplicate:
        return '跳过重复';
      default:
        return action;
    }
  }
}

/// 一道题的导入决策。
class QuestionPackDecision {
  const QuestionPackDecision({
    required this.index,
    required this.action,
    required this.stemPreview,
    this.serialNo,
    this.skipReason,
    this.existingQuestionId,
  });

  /// 在包内 questions.json 里的下标（0 起）。
  final int index;

  /// [QuestionPackAction.create]、[QuestionPackAction.update] 或
  /// [QuestionPackAction.skipDuplicate]。
  final String action;

  /// 题干预览：连续空白压成一个空格、trim、最多 40 个字符（超出加 '…'）。
  final String stemPreview;

  /// 题目编号，原样透传（可为空）。
  final int? serialNo;

  /// 跳过原因；新建与更新时为 null。
  final String? skipReason;

  /// 更新时 = 题库里被更新那道题的 id（调用方映射里的值原样透传）；
  /// 新建与跳过时为 null。
  final String? existingQuestionId;

  /// snake_case 机器可读；null 的键省略。
  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'action': action,
        'stem_preview': stemPreview,
        if (serialNo != null) 'serial_no': serialNo,
        if (skipReason != null) 'skip_reason': skipReason,
        if (existingQuestionId != null)
          'existing_question_id': existingQuestionId,
      };

  @override
  bool operator ==(Object other) =>
      other is QuestionPackDecision &&
      other.index == index &&
      other.action == action &&
      other.stemPreview == stemPreview &&
      other.serialNo == serialNo &&
      other.skipReason == skipReason &&
      other.existingQuestionId == existingQuestionId;

  @override
  int get hashCode => Object.hash(
        index,
        action,
        stemPreview,
        serialNo,
        skipReason,
        existingQuestionId,
      );

  @override
  String toString() => 'QuestionPackDecision(index: $index, action: $action, '
      'stemPreview: $stemPreview, serialNo: $serialNo, '
      'skipReason: $skipReason, existingQuestionId: $existingQuestionId)';
}

/// 整个题库包的导入计划。
class QuestionPackImportPlan {
  const QuestionPackImportPlan({
    required this.decisions,
    required this.warnings,
    required this.missingTagPaths,
  });

  /// 与包内记录一一对应（index 0 起）。
  final List<QuestionPackDecision> decisions;

  /// 导入前提示：跳过重复题（按题序）与缺失标签（按路径字典序），最多 20 条标签告警。
  final List<String> warnings;

  /// 包里出现、题库里没有的标签路径（trim 后去重、字典序排序）。
  final List<String> missingTagPaths;

  /// 会新建的题目数。
  int get createCount => decisions
      .where((QuestionPackDecision decision) =>
          decision.action == QuestionPackAction.create)
      .length;

  /// 会更新（而不是新建/跳过）的题目数。
  int get updateCount => decisions
      .where((QuestionPackDecision decision) =>
          decision.action == QuestionPackAction.update)
      .length;

  /// 会跳过的题目数（既不是新建也不是更新）。
  int get skipCount => decisions.length - createCount - updateCount;

  /// 包里一道题都没有。
  bool get isEmpty => decisions.isEmpty;

  /// 有需要用户注意的提示。
  bool get hasWarnings => warnings.isNotEmpty;

  /// 会新建的题目下标，升序。
  List<int> get createIndexes => <int>[
        for (final QuestionPackDecision decision in decisions)
          if (decision.action == QuestionPackAction.create) decision.index,
      ];

  /// 会更新的题目下标，升序。
  List<int> get updatedIndexes => <int>[
        for (final QuestionPackDecision decision in decisions)
          if (decision.action == QuestionPackAction.update) decision.index,
      ];

  /// snake_case 机器可读。
  Map<String, Object?> toJson() => <String, Object?>{
        'create_count': createCount,
        'update_count': updateCount,
        'skip_count': skipCount,
        'decisions': <Map<String, Object?>>[
          for (final QuestionPackDecision decision in decisions)
            decision.toJson(),
        ],
        'warnings': warnings,
        'missing_tag_paths': missingTagPaths,
      };
}

/// 从组卷网题号里取出「认题键」：trim 后非空的题号，否则 null。
///
/// 只按题号认题：组卷网题号在站内唯一，同一道题被反复交付时（补答案、修公式、
/// 换配图、重新打包）题号不变，所以「同题号 = 同一道题」；`zujuanBankId` 只用来
/// 重建来源链接，不参与认题——同一 bankId 下不同题号一定是不同题目，
/// 反过来同题号跨 bankId 也不会出现，因此不做任何跨字段推断。
///
/// 这里只做 trim 与空串归一，不校验格式（历史数据里可能有非数字题号）。
String? questionPackSourceKey({required String? zujuanQuestionId}) {
  final String? raw = zujuanQuestionId;
  if (raw == null) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 给包内每道题定一个导入决策（新建 / 更新 / 跳过重复）。
///
/// [fingerprintOf] 由调用方提供（通常是题干归一化后的哈希或原文），
/// [existingFingerprints] 是题库已有题目的指纹，只读不写；
/// [existingTagPaths] 是题库已有标签路径（trim 后精确比较）；
/// [existingQuestionIdByZujuanQuestionId] 是「组卷网题号 → 题库题目 id」，
/// 查表键按 [questionPackSourceKey] 归一（trim 后精确匹配，调用方负责表里键已归一），
/// 命中时更新那道题而不是跳过/新建；值原样透传进决定的 existingQuestionId。
/// [updateExisting] 为 false 时完全不认题号，走升级前的旧语义。
///
/// 永不抛异常；空记录返回空计划。
QuestionPackImportPlan planQuestionPackImport({
  required List<QuestionPackRecord> records,
  required String Function(String stem) fingerprintOf,
  required Set<String> existingFingerprints,
  required Set<String> existingTagPaths,
  Map<String, String> existingQuestionIdByZujuanQuestionId =
      const <String, String>{},
  bool updateExisting = true,
}) {
  final List<QuestionPackDecision> decisions = <QuestionPackDecision>[];
  final List<String> skipWarnings = <String>[];
  final Map<String, int> firstIndexByFingerprint = <String, int>{};
  final Map<String, int> firstIndexBySourceKey = <String, int>{};

  for (var index = 0; index < records.length; index++) {
    final QuestionPackRecord record = records[index];
    final String preview = _stemPreviewOf(record.stem);
    final String fingerprint = fingerprintOf(record.stem);
    final String? sourceKey = updateExisting
        ? questionPackSourceKey(zujuanQuestionId: record.zujuanQuestionId)
        : null;
    final int? earlierSourceKeyIndex =
        sourceKey == null ? null : firstIndexBySourceKey[sourceKey];
    if (sourceKey != null) {
      firstIndexBySourceKey.putIfAbsent(sourceKey, () => index);
    }
    // 只有第一次出现的题号参与更新判定：同一道题在包内重复时，
    // 后面的记录按「跳过」处理，避免被计划更新两次。
    final String? existingQuestionId =
        sourceKey != null && earlierSourceKeyIndex == null
            ? existingQuestionIdByZujuanQuestionId[sourceKey]
            : null;

    if (existingQuestionId != null) {
      firstIndexByFingerprint.putIfAbsent(fingerprint, () => index);
      decisions.add(QuestionPackDecision(
        index: index,
        action: QuestionPackAction.update,
        stemPreview: preview,
        serialNo: record.serialNo,
        existingQuestionId: existingQuestionId,
      ));
      continue;
    }

    if (existingFingerprints.contains(fingerprint)) {
      decisions.add(QuestionPackDecision(
        index: index,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: preview,
        serialNo: record.serialNo,
        skipReason: _existingDuplicateReason,
      ));
      skipWarnings.add(_existingDuplicateWarning(index + 1));
      continue;
    }

    if (earlierSourceKeyIndex != null) {
      decisions.add(QuestionPackDecision(
        index: index,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: preview,
        serialNo: record.serialNo,
        skipReason: _inPackSourceKeyReason(earlierSourceKeyIndex + 1),
      ));
      skipWarnings.add(
        _inPackSourceKeyWarning(index + 1, earlierSourceKeyIndex + 1),
      );
      continue;
    }

    final int? earlierIndex = firstIndexByFingerprint[fingerprint];
    if (earlierIndex != null) {
      decisions.add(QuestionPackDecision(
        index: index,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: preview,
        serialNo: record.serialNo,
        skipReason: _inPackFingerprintReason(earlierIndex + 1),
      ));
      skipWarnings.add(_inPackFingerprintWarning(index + 1, earlierIndex + 1));
      continue;
    }

    firstIndexByFingerprint[fingerprint] = index;
    decisions.add(QuestionPackDecision(
      index: index,
      action: QuestionPackAction.create,
      stemPreview: preview,
      serialNo: record.serialNo,
    ));
  }

  final List<String> missingTagPaths =
      _missingTagPathsOf(records, existingTagPaths);
  final List<String> warnings = <String>[
    ...skipWarnings,
    ..._missingTagWarnings(missingTagPaths),
  ];

  return QuestionPackImportPlan(
    decisions: List<QuestionPackDecision>.unmodifiable(decisions),
    warnings: List<String>.unmodifiable(warnings),
    missingTagPaths: List<String>.unmodifiable(missingTagPaths),
  );
}

/// 包内媒体文件的规范路径：`media/q<questionIndex>/<mediaIndex>.<extension>`。
///
/// [questionIndex] 从 1 起（人类可读的「第几道题」），[mediaIndex] 从 0 起；
/// [extension] 先 trim、去掉前导 '.'、转小写，必须属于
/// png/jpg/jpeg/gif/webp/bmp/heic，否则抛 [ArgumentError]。
String questionPackMediaPath({
  required int questionIndex,
  required int mediaIndex,
  required String extension,
}) {
  if (questionIndex < 1) {
    throw ArgumentError.value(questionIndex, 'questionIndex', '题目序号从 1 开始');
  }
  if (mediaIndex < 0) {
    throw ArgumentError.value(mediaIndex, 'mediaIndex', '媒体序号从 0 开始');
  }
  final String ext = _normalizeMediaExtension(extension);
  return 'media/q$questionIndex/$mediaIndex.$ext';
}

const String _existingDuplicateReason = '题库里已经有同一道题（题干指纹相同）';

String _inPackFingerprintReason(int earlierHumanIndex) =>
    '与包内第 $earlierHumanIndex 道题重复（题干指纹相同）';

String _inPackSourceKeyReason(int earlierHumanIndex) =>
    '与包内第 $earlierHumanIndex 道题是同一个组卷网题号';

String _existingDuplicateWarning(int humanIndex) =>
    '第 $humanIndex 道题与题库已有题目重复，导入时跳过';

String _inPackFingerprintWarning(int humanIndex, int earlierHumanIndex) =>
    '包内第 $humanIndex 道与第 $earlierHumanIndex 道是同一道题，只导入前一道';

String _inPackSourceKeyWarning(int humanIndex, int earlierHumanIndex) =>
    '包内第 $humanIndex 道与第 $earlierHumanIndex 道是同一个组卷网题号，只导入前一道';

String _missingTagWarning(String path) => '标签 $path 在题库里不存在，导入后相关题不挂这个标签';

String _truncatedMissingTagWarning(int remaining) => '还有 $remaining 条标签缺失未列出';

const int _maxMissingTagWarnings = 20;
const int _maxStemPreviewChars = 40;
const Set<String> _mediaExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
};

/// 汇总缺失标签：更新记录也算（更新时可能顺手在题库里建标签）。
List<String> _missingTagPathsOf(
  List<QuestionPackRecord> records,
  Set<String> existingTagPaths,
) {
  final Set<String> existing = <String>{
    for (final String path in existingTagPaths)
      if (path.trim().isNotEmpty) path.trim(),
  };
  final Set<String> missing = <String>{};
  for (final QuestionPackRecord record in records) {
    for (final String path in record.tagPaths) {
      final String trimmed = path.trim();
      if (trimmed.isEmpty || existing.contains(trimmed)) continue;
      missing.add(trimmed);
    }
  }
  final List<String> sorted = missing.toList()..sort();
  return sorted;
}

List<String> _missingTagWarnings(List<String> missingTagPaths) {
  final List<String> warnings = <String>[
    for (final String path in missingTagPaths.take(_maxMissingTagWarnings))
      _missingTagWarning(path),
  ];
  if (missingTagPaths.length > _maxMissingTagWarnings) {
    warnings.add(_truncatedMissingTagWarning(
        missingTagPaths.length - _maxMissingTagWarnings));
  }
  return warnings;
}

String _stemPreviewOf(String stem) {
  final String normalized = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= _maxStemPreviewChars) return normalized;
  var cut = normalized.substring(0, _maxStemPreviewChars);
  final int lastUnit = cut.codeUnitAt(cut.length - 1);
  if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) {
    cut = cut.substring(0, cut.length - 1);
  }
  return '$cut…';
}

String _normalizeMediaExtension(String extension) {
  var ext = extension.trim();
  while (ext.startsWith('.')) {
    ext = ext.substring(1);
  }
  final String normalized = ext.toLowerCase();
  if (!_mediaExtensions.contains(normalized)) {
    throw ArgumentError.value(
      extension,
      'extension',
      '不支持的图片扩展名（支持 png/jpg/jpeg/gif/webp/bmp/heic）',
    );
  }
  return normalized;
}
