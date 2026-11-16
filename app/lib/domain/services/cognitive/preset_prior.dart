/// 学生预设的**起点档位**（不是测量）。
///
/// 用户选 S/A/B/C/D 后，没有复习观测时学习状态从这里起步，而不是显示 `?`。
/// 这是一条设计先验：`source=preset`，`nObs=0`，永远不会被当成实测。
///
/// 真正的知识点 × 能力矩阵仍待建立；这里只解决“有没有起点”这一层，
/// 不冒充逐知识点矩阵。
library;

/// 五档预设。
enum StudentPresetBand {
  s('S', 0.90),
  a('A', 0.75),
  b('B', 0.60),
  c('C', 0.40),
  d('D', 0.25);

  const StudentPresetBand(this.label, this.mean);

  final String label;

  /// 0–1 掌握度尺度上的设计先验均值。
  final double mean;
}

/// 一个预选档的起点。
class PresetPrior {
  const PresetPrior({
    required this.presetId,
    required this.band,
    this.source = 'preset',
  });

  final String presetId;
  final StudentPresetBand band;

  /// 固定为 `preset`；测试与 UI 用它区分实测。
  final String source;

  /// 现有四个预设 id → 档位。没有映射的 id 返回 null（不猜）。
  ///
  /// * `preset-top` → S
  /// * `preset-above` → A
  /// * `preset-medium` → B
  /// * `preset-weak` → C
  ///
  /// D 目前没有对应预设；需要新增“基础”预设后才可出现。
  static PresetPrior? fromSelectionId(String? presetId) {
    final id = (presetId ?? '').trim();
    final band = switch (id) {
      'preset-top' => StudentPresetBand.s,
      'preset-above' => StudentPresetBand.a,
      'preset-medium' => StudentPresetBand.b,
      'preset-weak' => StudentPresetBand.c,
      _ => null,
    };
    if (band == null) return null;
    return PresetPrior(presetId: id, band: band);
  }
}
