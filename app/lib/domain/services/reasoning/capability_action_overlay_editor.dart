/// 能力动作词表 overlay 的**编辑操作层**：把用户的「加一条 / 改一条 / 删一条 /
/// 挪一下 / 导入一份」变成新的不可变 overlay。
///
/// 分工：
/// - [CapabilityActionOverlay] 是数据（不可变 + 宽容反序列化）；
/// - 本文件是操作（同步、无 IO、无异常逃逸）；
/// - 仓储层负责把 [CapabilityActionOverlay.toJson] 落库，UI 层负责展示
///   [OverlayEditResult.issues]。
///
/// 四条规则（都有测试守着）：
/// 1. **失败不改数据**：任何被拒绝的编辑都返回原 overlay 对象（identical），
///    UI 用 `identical(result.overlay, overlay)` 就能判断这次点击只是提示。
/// 2. **校验只有一套**：key 小写蛇形、内置保留、中文名必填、subjectHints 只留
///    合法学科，全部走 overlay 文件的 [validateCustomCapabilityAction]；新增
///    与导入不能绕过它。
/// 3. **key 不可变**：update 按 key 命中，签名里没有改 key 的入口。key 已经
///    写进 reasoning_steps.actionType，改它等于改历史数据的含义。
/// 4. **总量有上限**：自定义条目最多 [CapabilityActionOverlayEditor.maxCustomActions]
///    条；overlay 会整份进 DB / 导出 JSON，词表再长也不该让一次读取变成无界
///    数据。
///
/// 纯 Dart：不 import Flutter / 数据库 / 网络。
library;

import 'capability_action_overlay.dart';

/// 一次编辑操作的结果。
class OverlayEditResult {
  const OverlayEditResult({
    required this.overlay,
    required this.issues,
    required this.changed,
  });

  /// 编辑后的 overlay；失败或空操作时就是调用方传进来的原对象。
  final CapabilityActionOverlay overlay;

  /// 本次被拒绝的操作/条目，按发生顺序排列；空表示全部生效。
  final List<CapabilityActionOverlayIssue> issues;

  /// 数据是否真的变了。空操作（比如 update 传入完全相同的值、reorder 到
  /// 原位）为 false，且不带 issue。
  final bool changed;

  /// 是否至少有一条被拒绝。
  bool get hasIssues => issues.isNotEmpty;

  @override
  String toString() =>
      'OverlayEditResult(changed: $changed, issues: ${issues.length}, '
      'actions: ${overlay.length})';
}

/// overlay 的编辑操作集合。纯静态：不持有状态，每次调用都从传入的 overlay 出发。
class CapabilityActionOverlayEditor {
  const CapabilityActionOverlayEditor._();

  /// 自定义条目数量上限。
  static const int maxCustomActions = 100;

  /// 追加一条自定义动作。
  ///
  /// 校验顺序与合并层一致：缺 key → key 超长 → key 不是小写蛇形 → 与内置 key
  /// 冲突 → 缺中文名；通过后再查「与已有自定义条目重复」与总量上限。
  static OverlayEditResult add(
    CapabilityActionOverlay overlay,
    CustomCapabilityAction draft,
  ) {
    final normalized = normalizeCustomCapabilityAction(draft);
    final rejection = validateCustomCapabilityAction(normalized);
    if (rejection != null) {
      return _rejected(overlay, rejection);
    }
    if (_containsKey(overlay, normalized.key)) {
      return _rejected(
        overlay,
        _duplicateIssue(
          normalized.key,
          '「${normalized.key}」已经在自定义词表里：追加请换一个 key，'
          '修改已有动作请用 update。',
        ),
      );
    }
    if (overlay.length >= maxCustomActions) {
      return _rejected(overlay, _limitIssue(normalized.key));
    }
    return OverlayEditResult(
      overlay: _overlayWith(overlay, <CustomCapabilityAction>[
        ...overlay.customActions,
        normalized,
      ]),
      issues: const <CapabilityActionOverlayIssue>[],
      changed: true,
    );
  }

  /// 按 key 更新一条自定义动作；只替换目标条目，其余条目保持原对象与原顺序。
  ///
  /// 可选参数传 null 表示「保持原值」：
  /// - [labelZh] 传空串会被 missingLabelZh 拒绝（中文名必填）；
  /// - [labelEn] / [descriptionZh] 传空串表示清空，合并词表会用 key / labelZh
  ///   兜底；
  /// - [subjectHints] 传空列表表示清空；非法学科键会被丢弃，不会因此整条
  ///   拒绝。
  ///
  /// 归整后与现有内容完全相同时返回 changed=false（不产生新对象）。
  static OverlayEditResult update(
    CapabilityActionOverlay overlay, {
    required String key,
    String? labelZh,
    String? labelEn,
    String? descriptionZh,
    List<String>? subjectHints,
  }) {
    final targetKey = key.trim();
    if (targetKey.isEmpty) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    final index = _indexOf(overlay, targetKey);
    if (index < 0) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    final current = overlay.customActions[index];
    final normalized = normalizeCustomCapabilityAction(
      CustomCapabilityAction(
        key: current.key,
        labelZh: labelZh ?? current.labelZh,
        labelEn: labelEn ?? current.labelEn,
        descriptionZh: descriptionZh ?? current.descriptionZh,
        subjectHints: subjectHints ?? current.subjectHints,
      ),
    );
    final rejection = validateCustomCapabilityAction(normalized);
    if (rejection != null) {
      return _rejected(overlay, rejection);
    }
    if (_sameContent(normalized, current)) {
      return OverlayEditResult(
        overlay: overlay,
        issues: const <CapabilityActionOverlayIssue>[],
        changed: false,
      );
    }
    final next = <CustomCapabilityAction>[...overlay.customActions];
    next[index] = normalized;
    return OverlayEditResult(
      overlay: _overlayWith(overlay, next),
      issues: const <CapabilityActionOverlayIssue>[],
      changed: true,
    );
  }

  /// 删除一条自定义动作。
  ///
  /// 若历史数据里存在重复 key（宽容反序列化可能带进来），会删掉**所有**同 key
  /// 条目，让结果与「key 唯一」一致。key 不存在时返回 keyNotFound。
  static OverlayEditResult remove(
    CapabilityActionOverlay overlay,
    String key,
  ) {
    final targetKey = key.trim();
    if (targetKey.isEmpty) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    final next = <CustomCapabilityAction>[];
    var removed = 0;
    for (final action in overlay.customActions) {
      if (action.key.trim() == targetKey) {
        removed++;
      } else {
        next.add(action);
      }
    }
    if (removed == 0) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    return OverlayEditResult(
      overlay: _overlayWith(overlay, next),
      issues: const <CapabilityActionOverlayIssue>[],
      changed: true,
    );
  }

  /// 把一条自定义动作移动到新的下标。
  ///
  /// [newIndex] 是移动**之后**在自定义条目列表里的下标，合法范围
  /// 0 .. 自定义条目数 - 1；越界返回 indexOutOfRange，移到原位返回
  /// changed=false。
  static OverlayEditResult reorder(
    CapabilityActionOverlay overlay, {
    required String key,
    required int newIndex,
  }) {
    final targetKey = key.trim();
    if (targetKey.isEmpty) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    final index = _indexOf(overlay, targetKey);
    if (index < 0) {
      return _rejected(overlay, _notFoundIssue(targetKey));
    }
    final length = overlay.customActions.length;
    if (newIndex < 0 || newIndex >= length) {
      return _rejected(
        overlay,
        CapabilityActionOverlayIssue(
          reason: CapabilityActionOverlayIssueReason.indexOutOfRange,
          key: targetKey,
          message: '「$targetKey」不能移到下标 $newIndex：'
              '合法范围是 0..${length - 1}（共 $length 条自定义动作）。',
        ),
      );
    }
    if (newIndex == index) {
      return OverlayEditResult(
        overlay: overlay,
        issues: const <CapabilityActionOverlayIssue>[],
        changed: false,
      );
    }
    final next = <CustomCapabilityAction>[...overlay.customActions];
    final moved = next.removeAt(index);
    next.insert(newIndex, moved);
    return OverlayEditResult(
      overlay: _overlayWith(overlay, next),
      issues: const <CapabilityActionOverlayIssue>[],
      changed: true,
    );
  }

  /// 导入另一份 overlay JSON 的自定义条目，追加到当前词表末尾。
  ///
  /// [rawJson] 接受 [CapabilityActionOverlay.toJson] 的产物
  /// （{"version": 1, "customActions": [...]}）或直接给条目数组；其他形状
  /// 记 importNotRecognized。逐条处理：
  /// - 非法条目（缺 key / 非法 key / 内置 key / 缺中文名）跳过并记具体原因；
  /// - 与已有条目或本次先导入条目重复 key 的跳过并记 duplicateKey；
  /// - 合法条目按原顺序追加，直到 [maxCustomActions] 上限，超出记
  ///   customActionLimitExceeded。
  ///
  /// 成功导入至少一条时 changed=true；任何情况下都不抛异常。
  static OverlayEditResult mergeImport(
    CapabilityActionOverlay overlay,
    Object? rawJson,
  ) {
    final Object? source = rawJson is Map ? rawJson['customActions'] : rawJson;
    if (source is! List) {
      return _rejected(
        overlay,
        const CapabilityActionOverlayIssue(
          reason: CapabilityActionOverlayIssueReason.importNotRecognized,
          key: '',
          message: '导入内容不是可识别的 overlay JSON：'
              '需要 {"customActions": [...]} 或自定义动作数组。',
        ),
      );
    }
    final next = <CustomCapabilityAction>[...overlay.customActions];
    final issues = <CapabilityActionOverlayIssue>[];
    var accepted = 0;
    for (final entry in source) {
      final normalized = normalizeCustomCapabilityAction(
        CustomCapabilityAction.fromJson(entry),
      );
      final rejection = validateCustomCapabilityAction(normalized);
      if (rejection != null) {
        issues.add(rejection);
        continue;
      }
      if (_containsKeyIn(next, normalized.key)) {
        issues.add(
          _duplicateIssue(
            normalized.key,
            '「${normalized.key}」与已有或本次先导入的条目重复：'
            '先到先得，这一条被跳过。',
          ),
        );
        continue;
      }
      if (next.length >= maxCustomActions) {
        issues.add(_limitIssue(normalized.key));
        continue;
      }
      next.add(normalized);
      accepted++;
    }
    if (accepted == 0) {
      return OverlayEditResult(
        overlay: overlay,
        issues: List<CapabilityActionOverlayIssue>.unmodifiable(issues),
        changed: false,
      );
    }
    return OverlayEditResult(
      overlay: _overlayWith(overlay, next),
      issues: List<CapabilityActionOverlayIssue>.unmodifiable(issues),
      changed: true,
    );
  }

  static OverlayEditResult _rejected(
    CapabilityActionOverlay overlay,
    CapabilityActionOverlayIssue issue,
  ) {
    return OverlayEditResult(
      overlay: overlay,
      issues: <CapabilityActionOverlayIssue>[issue],
      changed: false,
    );
  }

  static CapabilityActionOverlay _overlayWith(
    CapabilityActionOverlay current,
    List<CustomCapabilityAction> customActions,
  ) {
    return CapabilityActionOverlay(
      customActions: List<CustomCapabilityAction>.unmodifiable(customActions),
    );
  }

  static bool _containsKey(
    CapabilityActionOverlay overlay,
    String key,
  ) {
    return _containsKeyIn(overlay.customActions, key);
  }

  static bool _containsKeyIn(
    List<CustomCapabilityAction> actions,
    String key,
  ) {
    for (final action in actions) {
      if (action.key.trim() == key) {
        return true;
      }
    }
    return false;
  }

  static int _indexOf(CapabilityActionOverlay overlay, String key) {
    final actions = overlay.customActions;
    for (var index = 0; index < actions.length; index++) {
      if (actions[index].key.trim() == key) {
        return index;
      }
    }
    return -1;
  }

  static bool _sameContent(
    CustomCapabilityAction left,
    CustomCapabilityAction right,
  ) {
    if (left.key != right.key ||
        left.labelZh != right.labelZh ||
        left.labelEn != right.labelEn ||
        left.descriptionZh != right.descriptionZh ||
        left.subjectHints.length != right.subjectHints.length) {
      return false;
    }
    for (var index = 0; index < left.subjectHints.length; index++) {
      if (left.subjectHints[index] != right.subjectHints[index]) {
        return false;
      }
    }
    return true;
  }

  static CapabilityActionOverlayIssue _duplicateIssue(
    String key,
    String message,
  ) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.duplicateKey,
      key: key,
      message: message,
    );
  }

  static CapabilityActionOverlayIssue _limitIssue(String key) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.customActionLimitExceeded,
      key: key,
      message: '自定义动作已达上限 $maxCustomActions 条：「$key」未加入。',
    );
  }

  static CapabilityActionOverlayIssue _notFoundIssue(String key) {
    return CapabilityActionOverlayIssue(
      reason: CapabilityActionOverlayIssueReason.keyNotFound,
      key: key,
      message: '「$key」不在自定义词表里：没有可修改 / 移动 / 删除的条目。',
    );
  }
}
