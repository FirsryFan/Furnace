/// 能力动作词表编辑的 application 层：把「纯逻辑编辑操作 + 本地存储 + 当前
/// 词表」串成一个可保存的状态机，界面只调方法、看 state。
///
/// 分工：
/// - 编辑规则（校验、失败不改数据）在
///   `domain/services/reasoning/capability_action_overlay_editor.dart`；
/// - 持久化在 [CapabilityVocabularyStore]（NULL = 出厂词表）；
/// - 这里只负责：载入 → 逐步编辑 → 攒 dirty → 保存 / 放弃。
///
/// 约定：
/// 1. 编辑失败不抛异常：issue 放进 state，overlay 不动（编辑器保证返回原对象）；
/// 2. 保存成功后把 [capabilityActionOverlayProvider] 失效，下一次解题立即吃新词表；
/// 3. 不做自动保存——词表是诊断口径的一部分，用户点「保存」才算数；
/// 4. 不用 autoDispose：用户在编辑页切走再回来，未保存的草稿不该被静默丢掉。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/capability_action_overlay_editor.dart';
import 'capability_vocabulary_store.dart';

/// 词表编辑页的状态。
class CapabilityVocabularyEditorState {
  const CapabilityVocabularyEditorState({
    required this.overlay,
    required this.savedOverlay,
    this.issues = const <CapabilityActionOverlayIssue>[],
    this.isSaving = false,
  });

  /// 正在编辑的词表（未保存的改动都在这里）。
  final CapabilityActionOverlay overlay;

  /// 上次从数据库读到 / 成功保存的快照，用来判断 dirty 与「放弃修改」。
  final CapabilityActionOverlay savedOverlay;

  /// 最近一次编辑被拒绝的条目；成功的编辑会把它清空。
  final List<CapabilityActionOverlayIssue> issues;

  /// 正在写数据库；此时界面应禁用保存按钮。
  final bool isSaving;

  /// 自定义条目数。
  int get customActionCount => overlay.customActions.length;

  /// 是否还有没保存的改动。
  bool get isDirty => !_sameOverlay(overlay, savedOverlay);

  /// 最近一次操作是否有被拒绝的条目。
  bool get hasIssues => issues.isNotEmpty;

  /// 给界面直接显示的一句话（第一条 issue；没有则 null）。
  String? get firstIssueMessage => issues.isEmpty ? null : issues.first.message;

  CapabilityVocabularyEditorState copyWith({
    CapabilityActionOverlay? overlay,
    CapabilityActionOverlay? savedOverlay,
    List<CapabilityActionOverlayIssue>? issues,
    bool clearIssues = false,
    bool? isSaving,
  }) {
    return CapabilityVocabularyEditorState(
      overlay: overlay ?? this.overlay,
      savedOverlay: savedOverlay ?? this.savedOverlay,
      issues: clearIssues
          ? const <CapabilityActionOverlayIssue>[]
          : (issues ?? this.issues),
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

/// 载入 → 编辑 → 保存 / 放弃 的控制器。
class CapabilityVocabularyEditor
    extends AsyncNotifier<CapabilityVocabularyEditorState> {
  @override
  Future<CapabilityVocabularyEditorState> build() async {
    final overlay = await ref.watch(capabilityVocabularyStoreProvider).load();
    return CapabilityVocabularyEditorState(
      overlay: overlay,
      savedOverlay: overlay,
    );
  }

  CapabilityVocabularyEditorState? get _current => state.valueOrNull;

  /// 追加一条自定义动作。
  void add(CustomCapabilityAction draft) {
    final current = _current;
    if (current == null) {
      return;
    }
    _apply(
      current,
      CapabilityActionOverlayEditor.add(current.overlay, draft),
    );
  }

  /// 按 key 修改一条；参数为 null 表示保持原值。
  void updateAction(
    String key, {
    String? labelZh,
    String? labelEn,
    String? descriptionZh,
    List<String>? subjectHints,
  }) {
    final current = _current;
    if (current == null) {
      return;
    }
    _apply(
      current,
      CapabilityActionOverlayEditor.update(
        current.overlay,
        key: key,
        labelZh: labelZh,
        labelEn: labelEn,
        descriptionZh: descriptionZh,
        subjectHints: subjectHints,
      ),
    );
  }

  /// 删除一条自定义动作。
  void remove(String key) {
    final current = _current;
    if (current == null) {
      return;
    }
    _apply(current, CapabilityActionOverlayEditor.remove(current.overlay, key));
  }

  /// 把一条自定义动作移到 [newIndex]（移动之后的下标）。
  void reorder(String key, int newIndex) {
    final current = _current;
    if (current == null) {
      return;
    }
    _apply(
      current,
      CapabilityActionOverlayEditor.reorder(
        current.overlay,
        key: key,
        newIndex: newIndex,
      ),
    );
  }

  /// 导入一份 overlay JSON（已解码成 Dart 对象），合法条目追加到末尾。
  void importJson(Object? rawJson) {
    final current = _current;
    if (current == null) {
      return;
    }
    _apply(
      current,
      CapabilityActionOverlayEditor.mergeImport(current.overlay, rawJson),
    );
  }

  /// 清掉提示（比如界面把 issue 读走之后）。
  void clearIssues() {
    final current = _current;
    if (current == null || !current.hasIssues) {
      return;
    }
    state = AsyncData(current.copyWith(clearIssues: true));
  }

  /// 保存到 local_settings；成功后 dirty 变 false，并让推理服务下次读到新词表。
  ///
  /// 写失败会把 isSaving 复位后原样抛出（界面显示错误、草稿保留）。
  Future<void> save() async {
    final current = _current;
    if (current == null || current.isSaving || !current.isDirty) {
      return;
    }
    state = AsyncData(current.copyWith(isSaving: true));
    final saving = current;
    try {
      await ref.read(capabilityVocabularyStoreProvider).save(saving.overlay);
    } catch (_) {
      state = AsyncData(saving.copyWith(isSaving: false));
      rethrow;
    }
    ref.invalidate(capabilityActionOverlayProvider);
    state = AsyncData(
      saving.copyWith(
        savedOverlay: saving.overlay,
        isSaving: false,
        clearIssues: true,
      ),
    );
  }

  /// 放弃未保存的改动：回到上次保存 / 载入的词表。
  void revert() {
    final current = _current;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        overlay: current.savedOverlay,
        clearIssues: true,
      ),
    );
  }

  void _apply(
    CapabilityVocabularyEditorState current,
    OverlayEditResult result,
  ) {
    state = AsyncData(
      current.copyWith(
        overlay: result.changed ? result.overlay : current.overlay,
        issues: result.issues,
        clearIssues: !result.hasIssues,
      ),
    );
  }
}

/// 词表编辑控制器；保存后由它负责让推理链路失效重读。
final capabilityVocabularyEditorProvider = AsyncNotifierProvider<
    CapabilityVocabularyEditor, CapabilityVocabularyEditorState>(
  CapabilityVocabularyEditor.new,
);

bool _sameOverlay(
  CapabilityActionOverlay left,
  CapabilityActionOverlay right,
) {
  if (left.length != right.length) {
    return false;
  }
  final a = left.customActions;
  final b = right.customActions;
  for (var index = 0; index < a.length; index++) {
    final x = a[index];
    final y = b[index];
    if (x.key != y.key ||
        x.labelZh != y.labelZh ||
        x.labelEn != y.labelEn ||
        x.descriptionZh != y.descriptionZh ||
        x.subjectHints.length != y.subjectHints.length) {
      return false;
    }
    for (var hint = 0; hint < x.subjectHints.length; hint++) {
      if (x.subjectHints[hint] != y.subjectHints[hint]) {
        return false;
      }
    }
  }
  return true;
}
