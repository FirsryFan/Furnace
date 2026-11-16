/// 逐知识点预设矩阵 seed 的只读模型。
///
/// 数据来源：`assets/leaf-preset-matrix.json`，110 个三级 tag × A1–A10 ×
/// S/A/B/C/D，全部 `preset_global`、`n_obs=0`。
///
/// 这是**骨架**，不是逐点实测；UI 不得把它显示成“已测”。
library;

class LeafPresetMatrixSeed {
  const LeafPresetMatrixSeed({
    required this.nodeCount,
    required this.cellCount,
    required this.bands,
    required this.abilityCodes,
    required this.source,
    required this.note,
  });

  factory LeafPresetMatrixSeed.fromJson(Map<String, Object?> json) {
    final counts = json['counts'];
    final countMap = counts is Map
        ? counts.cast<String, Object?>()
        : const <String, Object?>{};
    final presets = json['presets'];
    final presetMap = presets is Map
        ? presets.cast<String, Object?>()
        : const <String, Object?>{};
    return LeafPresetMatrixSeed(
      nodeCount: _int(countMap['nodes']),
      cellCount: _int(countMap['cells']),
      bands: presetMap.keys.whereType<String>().toList(growable: false),
      abilityCodes: (json['ability_codes'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      source: (json['source'] as String? ?? '').trim(),
      note: (json['notes'] as List?)?.whereType<String>().join('；') ?? '',
    );
  }

  final int nodeCount;
  final int cellCount;
  final List<String> bands;
  final List<String> abilityCodes;
  final String source;
  final String note;

  bool get isSkeleton => cellCount > 0 && nodeCount > 0;
  bool get allPresetGlobal =>
      note.contains('preset_global') || note.contains('not measured');
}

int _int(Object? value) => value is num ? value.toInt() : 0;
