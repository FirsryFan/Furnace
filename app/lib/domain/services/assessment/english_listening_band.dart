/// 英语听力子档：按「听力错几题」映射到总分档位标签。
///
/// 用户 2026-11-15 最终口径（lead 转述，原话「就按我说的做」）：
///
/// * S+/S/A = **0 错**（不错）；这三档在听力子档上不区分；
/// * B = **1 错**；
/// * C = **2 错**；D = **2 错**（C/D 同时对应 2 错）；
/// * **D 不做 3+**：3 错及以上不归入 D，本子档未定义（读数标 unmapped /
///   `above_confirmed_range`），不得静默当成 D。
///
/// 边界纪律：
///
/// * 本文件**不改、不读**英语总分 150 的 S+/S/A/B/C/D 阈值；总分分档仍在
///   `exam_score_band.dart` 的 `ExamScoreThresholds.english`
///   （150/140/130/120/110），本子档只是它的旁路记录。
/// * 负错题数抛 [ArgumentError]（调用方 bug）；0/1/2 之外没有确认口径，
///   如实返回未定义，不猜。
/// * 纯逻辑：不读时钟、不随机、不读写数据库、不 import Flutter。
library;

import 'exam_score_band.dart';

/// 英语听力子档（已确认的三种错题数）。
enum EnglishListeningSubBand {
  /// 0 错：对应总分档位 S+ / S / A。
  noneWrong(0, '0错'),

  /// 1 错：对应总分档位 B。
  oneWrong(1, '1错'),

  /// 2 错：对应总分档位 C / D（两者都对应 2 错；D 不延伸到 3+ 错）。
  twoWrong(2, '2错');

  const EnglishListeningSubBand(this.wrongCount, this.label);

  /// 该子档对应的听力错题数。
  final int wrongCount;

  /// 显示用短标签：`0错` / `1错` / `2错`。
  final String label;
}

const List<ExamScoreBand> _noneWrongBands = <ExamScoreBand>[
  ExamScoreBand.sPlus,
  ExamScoreBand.s,
  ExamScoreBand.a,
];

const List<ExamScoreBand> _oneWrongBands = <ExamScoreBand>[ExamScoreBand.b];

const List<ExamScoreBand> _twoWrongBands = <ExamScoreBand>[
  ExamScoreBand.c,
  ExamScoreBand.d,
];

/// 一次听力子档读数。
class EnglishListeningBandReading {
  const EnglishListeningBandReading({
    required this.wrongCount,
    required this.subBand,
    required this.bands,
  });

  /// 内部使用的错题数；默认不写进 JSON（见 [toJson]）。
  final int wrongCount;

  /// 命中的子档；null = 错题数超出已确认口径（>2 错，未定义）。
  final EnglishListeningSubBand? subBand;

  /// 该子档对应的总分档位标签（按高到低排列，可能多个）。
  final List<ExamScoreBand> bands;

  /// 是否命中已确认子档。
  bool get isMapped => subBand != null;

  /// 是否超出已确认口径（>2 错，未定义）。
  bool get isUnmapped => subBand == null;

  /// 未定义原因：`none` 或 `above_confirmed_range`（>2 错）。
  String get unknownReason => isMapped ? 'none' : 'above_confirmed_range';

  /// 显示串：`S+/S/A（0错）` / `B（1错）` / `C/D（2错）` / `未定义（>2错）`。
  ///
  /// 只描述听力错题数档位，不含总分、百分比或任何「预测分数」。
  String get display {
    final current = subBand;
    if (current == null) return '未定义（>2错）';
    return '${bands.map((band) => band.label).join('/')}（${current.label}）';
  }

  /// 序列化。默认**不含**错题数；内部日志需要时显式
  /// `includeWrongCount: true`。UI 层不得读取 `wrongCount`。
  Map<String, Object?> toJson({bool includeWrongCount = false}) =>
      <String, Object?>{
        'sub_band': subBand?.name,
        'sub_band_label': subBand?.label,
        'bands': bands.map((band) => band.label).toList(),
        'display': display,
        'unknown_reason': unknownReason,
        if (includeWrongCount) 'wrong_count': wrongCount,
      };
}

/// 输入听力错题数，返回子档读数。
///
/// * 0 → S+/S/A；1 → B；2 → C/D；
/// * >2 → 未定义（不按 3+ 给 D）；
/// * 负数 → [ArgumentError]。
EnglishListeningBandReading readEnglishListeningBand(int wrongCount) {
  if (wrongCount < 0) {
    throw ArgumentError.value(wrongCount, 'wrongCount', '听力错题数不能为负');
  }
  switch (wrongCount) {
    case 0:
      return const EnglishListeningBandReading(
        wrongCount: 0,
        subBand: EnglishListeningSubBand.noneWrong,
        bands: _noneWrongBands,
      );
    case 1:
      return const EnglishListeningBandReading(
        wrongCount: 1,
        subBand: EnglishListeningSubBand.oneWrong,
        bands: _oneWrongBands,
      );
    case 2:
      return const EnglishListeningBandReading(
        wrongCount: 2,
        subBand: EnglishListeningSubBand.twoWrong,
        bands: _twoWrongBands,
      );
    default:
      return EnglishListeningBandReading(
        wrongCount: wrongCount,
        subBand: null,
        bands: const <ExamScoreBand>[],
      );
  }
}
