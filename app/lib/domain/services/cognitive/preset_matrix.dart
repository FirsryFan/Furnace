/// 读取 `assets/preset-ability-matrix.json` 的只读模型。
///
/// 这份数据是 **seed**，不是完整矩阵：
/// * `knowledge.measured`：19 个有真实复习后验的知识点；
/// * `knowledge.preset_global`：S/A/B/C/D × 581 KP 的全局先验，`n_obs=0`，
///   不是逐知识点标定；
/// * 没出现在 measured 里的 KP 不能显示成“已测”。
///
/// 纯 Dart：不读 asset、不读 DB；asset 读取由 presentation/application 层负责。
library;

/// 一个矩阵单元的最小读数。
class PresetMatrixScore {
  const PresetMatrixScore({
    required this.mean,
    required this.uncertainty,
    required this.source,
    required this.nObs,
  });

  final double mean;
  final double uncertainty;

  /// `measured` / `preset_global`
  final String source;
  final int nObs;

  bool get isMeasured => source == 'measured';

  Map<String, Object?> toJson() => <String, Object?>{
        'mean': mean,
        'uncertainty': uncertainty,
        'source': source,
        'n_obs': nObs,
      };
}

/// 解析后的 seed 矩阵。
class PresetMatrixSeed {
  const PresetMatrixSeed({
    required this.measuredByKnowledgePoint,
    required this.presetGlobalMean,
    required this.presetGlobalUncertainty,
    required this.missingMeasuredIds,
  });

  factory PresetMatrixSeed.fromJson(Map<String, Object?> json) {
    final knowledge = _map(json['knowledge']);
    final measured = <String, PresetMatrixScore>{};
    for (final raw in _list(knowledge['measured'])) {
      final row = _map(raw);
      final id = (row['kp_id'] as String? ?? '').trim();
      if (id.isEmpty) continue;
      final mastery = _map(row['mastery']);
      final evidence = _map(row['evidence']);
      final interval = _map(mastery['intervals']);
      final interval95 = _list(interval['95']);
      final mean = _double(mastery['mean']);
      if (mean == null) continue;
      final lo = interval95.isNotEmpty ? _double(interval95[0]) : null;
      final hi = interval95.length > 1 ? _double(interval95[1]) : null;
      final uncertainty =
          (lo != null && hi != null) ? ((hi - lo).abs() / 2.0) : 0.5;
      measured[id] = PresetMatrixScore(
        mean: mean,
        uncertainty: uncertainty,
        source: 'measured',
        nObs: _int(evidence['n_obs']),
      );
    }

    final presetMean = <String, double>{};
    final presetUncertainty = <String, double>{};
    for (final raw in _list(knowledge['preset_global'])) {
      final row = _map(raw);
      final band = (row['band'] as String? ?? '').trim();
      final mean = _double(row['mean']);
      if (band.isEmpty || mean == null) continue;
      presetMean[band] = mean;
      presetUncertainty[band] = _double(row['uncertainty']) ?? 0.15;
    }

    return PresetMatrixSeed(
      measuredByKnowledgePoint: Map.unmodifiable(measured),
      presetGlobalMean: Map.unmodifiable(presetMean),
      presetGlobalUncertainty: Map.unmodifiable(presetUncertainty),
      missingMeasuredIds: List.unmodifiable(
        _stringList(json['missing_measured_kp_ids']),
      ),
    );
  }

  final Map<String, PresetMatrixScore> measuredByKnowledgePoint;
  final Map<String, double> presetGlobalMean;
  final Map<String, double> presetGlobalUncertainty;
  final List<String> missingMeasuredIds;

  PresetMatrixScore? measuredFor(String knowledgePointId) =>
      measuredByKnowledgePoint[knowledgePointId];

  double? presetMeanFor(String band) => presetGlobalMean[band];

  int get measuredCount => measuredByKnowledgePoint.length;

  bool get hasGlobalPreset => presetGlobalMean.isNotEmpty;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

double? _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

int _int(Object? value) => value is num ? value.toInt() : 0;

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
