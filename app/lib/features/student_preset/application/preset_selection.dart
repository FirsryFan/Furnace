import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户选中的预设（原型）。
///
/// 只放内存：任务禁止改 DB schema，`local_settings` 也没有可安全复用的列
/// （`capabilityActionOverlayJson` 属于能力动作词表，不能挪用）。所以这个
/// provider 就是"选择生效"的边界：本页与设置页副标题读它；重启后回到未选。
/// 它**不**影响解题、评分或任何 AI 调用——那要等后续接线。
class PresetSelection {
  const PresetSelection({required this.presetId, required this.presetName});

  final String presetId;
  final String presetName;

  @override
  bool operator ==(Object other) =>
      other is PresetSelection &&
      other.presetId == presetId &&
      other.presetName == presetName;

  @override
  int get hashCode => Object.hash(presetId, presetName);

  @override
  String toString() => 'PresetSelection($presetId, $presetName)';
}

final presetSelectionProvider = StateProvider<PresetSelection?>((ref) => null);
