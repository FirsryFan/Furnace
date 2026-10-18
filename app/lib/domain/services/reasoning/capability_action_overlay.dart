/// 能力动作词表的用户可编辑 overlay —— 让词表长大不必发版。
///
/// [CapabilityAction.catalog] 是编译期常量：加一个动作、改一个 key 都得发一次
/// 版。但词表本来就是会被用户的题喂大的——老师想加「画受力图」，学生整理出
/// 「配平」，这些动作在种子 20 个里没有，不代表它们不能用于诊断。overlay 把
/// 用户条目放在**数据**里，内置词表一个字不动。
///
/// 三条规则（都有测试守着）：
/// 1. **内置优先**：自定义 key 与内置 key 相同 → **拒绝**（不是覆盖）。key 是
///    已经写进 reasoning_steps.actionType 并参与统计的稳定标识；允许用户覆盖
///    它，等于让历史数据的含义在某一天悄悄改变。要改内置动作请改代码并发版。
/// 2. **先到先得**：自定义条目之间重复 key → 保留第一条，后面的记 issue。
/// 3. **坏数据不崩**：[CapabilityActionOverlay.fromJson] 只做类型归整，永不抛
///    异常；语义校验发生在合并时（[CapabilityActionOverlay.catalog]），被拒的
///    条目连原因一起记进 [CapabilityActionCatalog.issues]，界面才能说清「哪个
///    条目为什么没生效」。
///
/// 合并结果 [CapabilityActionCatalog] 是只读视图：内置动作按原顺序在前，自定义
/// 动作按用户顺序追加；[CapabilityAction.sortOrder] 仍然等于它在合并词表里的
/// 下标。提示词（reasoning_prompt.dart 的 solveThenDecompose）与解析器
/// （parseChain 的 lookup 参数）吃的是同一份合并结果，不会出现「提示词让模型
/// 用自定义动作、解析器却不认识」的分叉。
///
/// 纯 Dart：不 import Flutter / 数据库 / 网络。
library;

import 'capability_action.dart';

/// 自定义动作被拒绝的原因。用枚举而不是字符串，测试才能断言「具体是哪条规则」。
enum CapabilityActionOverlayIssueReason {
  /// key 缺失或只有空白。
  missingKey,

  /// key 超过 [CapabilityActionOverlay.maxKeyLength]。
  keyTooLong,

  /// key 不是小写蛇形（^[a-z][a-z0-9]*(_[a-z0-9]+)*$）。
  keyNotSnakeCase,

  /// key 与内置词表冲突：内置优先，不允许覆盖。
  keyReserved,

  /// key 与前面已经接受的自定义条目冲突：先到先得。
  duplicateKey,

  /// 缺中文展示名（[CustomCapabilityAction.labelZh]）。
  missingLabelZh,

  /// 编辑操作找不到目标 key（更新 / 移动 / 删除时这个词表里没有它）。
  ///
  /// 合并层永远不会产生这个原因：合并是「逐条尽量收」，没有「目标条目」的概念；
  /// 它只由编辑层（capability_action_overlay_editor.dart）产生。
  keyNotFound,

  /// 移动的目标下标越界：合法范围是 0 .. 自定义条目数 - 1。
  indexOutOfRange,

  /// 自定义条目总量会超过 [CapabilityActionOverlayEditor.maxCustomActions]。
  customActionLimitExceeded,

  /// 导入源不是可识别的 overlay JSON。
  ///
  /// 合法来源是 [CapabilityActionOverlay.toJson] 的产物，或直接给出条目数组。
  importNotRecognized,
}

/// 一条被拒绝的自定义动作，以及可读的原因。
class CapabilityActionOverlayIssue {
  const CapabilityActionOverlayIssue({
    required this.reason,
    required this.key,
    required this.message,
  });

  final CapabilityActionOverlayIssueReason reason;

  /// 被拒条目的 key（原样，可能为空）。
  final String key;

  /// 给人看的一句话解释；界面直接显示它，不必自己翻译枚举。
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'reason': reason.name,
        'key': key,
        'message': message,
      };

  @override
  String toString() =>
      'CapabilityActionOverlayIssue(${reason.name}, "$key"): $message';
}

/// 用户填写的一条能力动作（持久化格式，尚未合并进词表）。
///
/// 字段对应 [CapabilityAction] 的展示字段，但**故意不包含** [CapabilityAction.transferable]
/// 与 [CapabilityAction.sortOrder]：
/// * transferable 由 subjectHints 的数量按
///   [CapabilityAction.transferableSubjectThreshold] 推出（与内置词表同一条
///   判据），用户手写的布尔值会和学科提示矛盾；
/// * sortOrder 在合并时按位置分配，用户填了也没有意义。
class CustomCapabilityAction {
  const CustomCapabilityAction({
    required this.key,
    required this.labelZh,
    this.labelEn = '',
    this.descriptionZh = '',
    this.subjectHints = const <String>[],
  });

  /// 宽容解析：非对象返回空条目，类型错误的字段退化成默认值，**永不抛异常**。
  ///
  /// 空条目不会静默消失：合并时它会以 [CapabilityActionOverlayIssueReason.missingKey]
  /// 被拒并记进 issues，用户看得到「这一条没生效」。
  factory CustomCapabilityAction.fromJson(Object? raw) {
    if (raw is! Map) {
      return const CustomCapabilityAction(key: '', labelZh: '');
    }
    final map = raw.cast<Object?, Object?>();
    return CustomCapabilityAction(
      key: _readText(map['key']),
      labelZh: _readText(map['labelZh']),
      labelEn: _readText(map['labelEn']),
      descriptionZh: _readText(map['descriptionZh']),
      subjectHints: List<String>.unmodifiable(_readHints(map['subjectHints'])),
    );
  }

  /// 稳定标识，小写蛇形；合并前由 [CapabilityActionCatalog.merge] 校验。
  final String key;

  /// 中文展示名，必填（缺了这条动作在界面上没有名字，合并时会被拒绝）。
  final String labelZh;

  /// 英文展示名；留空时合并词表用 key 兜底。
  final String labelEn;

  /// 一句话说明这个动作在干什么；留空时合并词表用 labelZh 兜底。
  final String descriptionZh;

  /// 会出现这个动作的学科轨道（取值见 [CapabilityAction.subjectKeys]）；
  /// 非法学科在合并时被丢弃，不因此拒绝整条（界面可以先填 key 再补学科）。
  final List<String> subjectHints;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'labelZh': labelZh,
        'labelEn': labelEn,
        'descriptionZh': descriptionZh,
        'subjectHints': subjectHints,
      };
}

/// 内置词表 + 用户自定义条目合并后的**只读**词表。
///
/// 这是提示词渲染（`solveThenDecompose(capabilityCatalog: ...)`）与解析器
/// （`parseChain(lookup: catalog.byKey)`）共同吃的对象：一处合并、两处同源。
class CapabilityActionCatalog {
  CapabilityActionCatalog._({
    required this.actions,
    required this.customActions,
    required this.issues,
  }) : _byKey = <String, CapabilityAction>{
          for (final action in actions) action.key: action,
        };

  /// 只有内置词表：与 [CapabilityAction.catalog] 逐项相同（含对象身份），issues 为空。
  static final CapabilityActionCatalog builtIn =
      CapabilityActionCatalog.merge(const <CustomCapabilityAction>[]);

  /// 合并：内置词表在前（原顺序），自定义条目按用户顺序追加。
  ///
  /// 非法条目不会被塞进 [actions]，而是在 [issues] 里留下带原因的记录；
  /// 自定义之间重复 key 先到先得；与内置 key 冲突一律拒绝（内置优先）。
  factory CapabilityActionCatalog.merge(
    Iterable<CustomCapabilityAction> customActions,
  ) {
    final actions = <CapabilityAction>[...CapabilityAction.catalog];
    final accepted = <CapabilityAction>[];
    final issues = <CapabilityActionOverlayIssue>[];
    final taken = <String>{...CapabilityAction.keys};
    for (final draft in customActions) {
      final rejection = _validate(draft);
      if (rejection != null) {
        issues.add(rejection);
        continue;
      }
      final key = draft.key.trim();
      if (!taken.add(key)) {
        issues.add(
          CapabilityActionOverlayIssue(
            reason: CapabilityActionOverlayIssueReason.duplicateKey,
            key: key,
            message: '「$key」与前面已接受的自定义动作重复：先到先得，这一条被拒绝。',
          ),
        );
        continue;
      }
      final hints = _sanitizeSubjectHints(draft.subjectHints);
      final labelZh = draft.labelZh.trim();
      final labelEn = draft.labelEn.trim();
      final descriptionZh = draft.descriptionZh.trim();
      final action = CapabilityAction(
        key: key,
        labelZh: labelZh,
        labelEn: labelEn.isEmpty ? key : labelEn,
        descriptionZh: descriptionZh.isEmpty ? labelZh : descriptionZh,
        subjectHints: hints,
        transferable:
            hints.length >= CapabilityAction.transferableSubjectThreshold,
        sortOrder: actions.length,
      );
      actions.add(action);
      accepted.add(action);
    }
    return CapabilityActionCatalog._(
      actions: List<CapabilityAction>.unmodifiable(actions),
      customActions: List<CapabilityAction>.unmodifiable(accepted),
      issues: List<CapabilityActionOverlayIssue>.unmodifiable(issues),
    );
  }

  /// 内置 + 自定义的全部动作：内置在前，自定义按用户顺序追加。
  final List<CapabilityAction> actions;

  /// 通过校验、真的进了词表自定义动作（sortOrder 已按合并位置分配）。
  final List<CapabilityAction> customActions;

  /// 被拒绝的自定义条目及原因；空表示全部生效。
  final List<CapabilityActionOverlayIssue> issues;

  final Map<String, CapabilityAction> _byKey;

  /// 合并词表里的全部 key，与 [actions] 同序。
  List<String> get keys => <String>[for (final action in actions) action.key];

  int get length => actions.length;

  bool get isEmpty => actions.isEmpty;

  bool get isNotEmpty => actions.isNotEmpty;

  /// 按 key 查动作；首尾空白忽略，大小写不忽略；未知返回 null，永不抛异常。
  CapabilityAction? byKey(String key) => _byKey[key.trim()];

  /// 合并词表认不认识这个 key（含自定义动作）。
  bool isKnownKey(String key) => byKey(key) != null;

  /// 内置词表认不认识这个 key。
  bool isBuiltInKey(String key) => CapabilityAction.isKnownKey(key);

  /// 是否是用户自定义动作：内置不认识、但合并词表认识。
  bool isCustomKey(String key) {
    final trimmed = key.trim();
    return !CapabilityAction.isKnownKey(trimmed) && _byKey.containsKey(trimmed);
  }
}

/// 用户可编辑的能力动作词表（overlay）。
///
/// 只持有用户条目；内置词表永远来自 [CapabilityAction.catalog]。默认构造没有任何
/// 条目，合并结果与内置词表逐项相同（零行为变化）。
class CapabilityActionOverlay {
  const CapabilityActionOverlay({
    this.customActions = const <CustomCapabilityAction>[],
  });

  /// 没有用户条目：合并结果就是内置词表。
  static const CapabilityActionOverlay empty = CapabilityActionOverlay();

  /// key 长度上限。不是为了省空间，而是防止把一整句话填进 key——key 要出现在
  /// 提示词和数据库里，短才可读。
  static const int maxKeyLength = 48;

  /// 自定义 key 的合法形状：小写蛇形，与内置词表同一条规则。
  static final RegExp keyPattern = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

  /// 用户条目，按用户顺序；可能含非法条目（合并时才拒绝）。
  final List<CustomCapabilityAction> customActions;

  bool get isEmpty => customActions.isEmpty;

  int get length => customActions.length;

  /// 宽容解析持久化 JSON。
  ///
  /// 接受 [toJson] 的产物（{"version": 1, "customActions": [...]}），也接受
  /// 直接给出条目数组。顶层不是对象/数组、`customActions` 不是数组、条目不是
  /// 对象——一律跳过，**永不抛异常**；未知字段忽略。
  factory CapabilityActionOverlay.fromJson(Object? raw) {
    Object? entries;
    if (raw is Map) {
      entries = raw['customActions'];
    } else if (raw is List) {
      entries = raw;
    }
    if (entries is! List) {
      return empty;
    }
    return CapabilityActionOverlay(
      customActions: List<CustomCapabilityAction>.unmodifiable(
        <CustomCapabilityAction>[
          for (final entry in entries)
            if (entry is Map) CustomCapabilityAction.fromJson(entry),
        ],
      ),
    );
  }

  /// 合并后的最终词表（内置在前 + 自定义追加），被拒条目见返回值的 [CapabilityActionCatalog.issues]。
  CapabilityActionCatalog get catalog =>
      CapabilityActionCatalog.merge(customActions);

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'customActions': <Object?>[
          for (final action in customActions) action.toJson(),
        ],
      };
}

/// 校验一条自定义动作；合法返回 null，非法返回带原因的 issue。
CapabilityActionOverlayIssue? _validate(CustomCapabilityAction draft) {
  final key = draft.key.trim();
  if (key.isEmpty) {
    return const CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.missingKey,
      key: '',
      message: '自定义动作缺 key：key 是写进数据库的稳定标识，不能为空。',
    );
  }
  if (key.length > CapabilityActionOverlay.maxKeyLength) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.keyTooLong,
      key: key,
      message: '「$key」超过 ${CapabilityActionOverlay.maxKeyLength} 个字符：'
          'key 要出现在提示词与数据库里，短才可读。',
    );
  }
  if (!CapabilityActionOverlay.keyPattern.hasMatch(key)) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.keyNotSnakeCase,
      key: key,
      message: '「$key」不是小写蛇形（只允许 a-z、0-9 与单下划线，且以字母开头），'
          '例如 force_diagram_analysis。',
    );
  }
  if (CapabilityAction.isKnownKey(key)) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.keyReserved,
      key: key,
      message: '「$key」是内置动作的 key：内置优先，用户条目不允许覆盖它。',
    );
  }
  if (draft.labelZh.trim().isEmpty) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.missingLabelZh,
      key: key,
      message: '「$key」缺中文名（labelZh）：界面上没法显示一条没有名字的动作。',
    );
  }
  return null;
}

/// 只保留合法学科轨道键、去重、保持用户顺序。
List<String> _sanitizeSubjectHints(List<String> subjectHints) {
  final allowed = CapabilityAction.subjectKeys.toSet();
  final hints = <String>[];
  for (final hint in subjectHints) {
    final key = hint.trim();
    if (key.isNotEmpty && allowed.contains(key) && !hints.contains(key)) {
      hints.add(key);
    }
  }
  return List<String>.unmodifiable(hints);
}

String _readText(Object? value) => value is String ? value.trim() : '';

List<String> _readHints(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final hints = <String>[];
  for (final hint in value) {
    final text = _readText(hint);
    if (text.isNotEmpty && !hints.contains(text)) {
      hints.add(text);
    }
  }
  return hints;
}

/// 校验一条自定义动作，但**不合并、不落库**：合法返回 null，非法返回带原因的
/// issue。
///
/// 这是编辑层（capability_action_overlay_editor.dart）与合并层共同吃的唯一
/// 校验入口：表单里提示「这个 key 为什么不行」和词表合并时拒绝它的理由完全
/// 一致。纯函数、永不抛异常。
CapabilityActionOverlayIssue? validateCustomCapabilityAction(
  CustomCapabilityAction draft,
) =>
    _validate(draft);

/// 把用户输入归整成可持久化形态：文本去首尾空白，[CustomCapabilityAction.subjectHints]
/// 只保留合法学科键并去重、保序。
///
/// 只做归整，不做语义校验（缺 key / 非法 key / 与内置冲突交给
/// [validateCustomCapabilityAction]）：因此对任意输入都永不抛异常。
CustomCapabilityAction normalizeCustomCapabilityAction(
  CustomCapabilityAction draft,
) =>
    CustomCapabilityAction(
      key: draft.key.trim(),
      labelZh: draft.labelZh.trim(),
      labelEn: draft.labelEn.trim(),
      descriptionZh: draft.descriptionZh.trim(),
      subjectHints: _sanitizeSubjectHints(draft.subjectHints),
    );
