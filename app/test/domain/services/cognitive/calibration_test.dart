import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:furnace/domain/services/cognitive/calibration.dart';
import 'package:furnace/domain/services/cognitive/learning_metrics.dart';

RetentionSample one(
  double? predicted,
  bool recalled, {
  int index = 0,
  String card = 'c1',
}) {
  return RetentionSample(
    cardStateId: card,
    reviewedAtMs: index * 1000,
    recalled: recalled,
    predictedR: predicted,
  );
}

/// 一批"按 [slope]/[intercept] 应验"的样本。
///
/// 每个 `r` 重复 [perBin] 次，其中 `round(σ(a·logit r + b)·perBin)` 次算"记得"。
/// 这样样本本身遵守一个已知的重标定关系，拟合能不能把它找回来就有了标准答案。
List<RetentionSample> synthetic({
  required List<double> rValues,
  int perBin = 40,
  double slope = 1.0,
  double intercept = 0.0,
}) {
  final samples = <RetentionSample>[];
  var index = 0;
  for (final r in rValues) {
    final clamped = r.clamp(kLogitEpsilon, 1 - kLogitEpsilon);
    final x = math.log(clamped / (1 - clamped));
    final z = slope * x + intercept;
    final p = 1 / (1 + math.exp(-z));
    final positives = (p * perBin).round().clamp(0, perBin);
    for (var k = 0; k < perBin; k++) {
      samples.add(one(r, k < positives, index: index, card: 'c${index % 4}'));
      index++;
    }
  }
  return samples;
}

void main() {
  group('CalibrationReport.read —— 四种"不算"', () {
    test('一条样本都没有 → noSamples', () {
      final report = CalibrationReport.read(samples: const []);
      expect(report.verdict, CalibrationVerdict.noSamples);
      expect(report.usable, isFalse);
      expect(report.fit, isNull);
      expect(report.samples, 0);
      expect(report.refusalReasonZh, isNotNull);
      expect(report.refusalReasonZh, contains('不补算'));
    });

    test('复习很多但一条预测都没有 → 仍然 noSamples（历史不补算）', () {
      final samples = [
        for (var i = 0; i < 50; i++) one(null, i.isEven, index: i),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.verdict, CalibrationVerdict.noSamples);
      expect(report.samples, 0);
    });

    test('不足 $kMinCalibrationSamples 条 → tooFewSamples（数据再漂亮也不给）', () {
      final samples = synthetic(rValues: const [0.3, 0.7], perBin: 14);
      expect(samples.length, 28);
      final report = CalibrationReport.read(samples: samples);
      expect(report.verdict, CalibrationVerdict.tooFewSamples);
      expect(report.samples, 28);
      expect(report.refusalReasonZh, contains('28'));
      expect(report.refusalReasonZh, contains('$kMinCalibrationSamples'));
      expect(report.fit, isNull);
    });

    test('全是"记得" → singleClass，理由点名缺反例', () {
      final samples = [
        for (var i = 0; i < 40; i++) one(0.8, true, index: i),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.verdict, CalibrationVerdict.singleClass);
      expect(report.refusalReasonZh, contains('反例'));
    });

    test('全是"忘记" → singleClass，理由点名缺正例', () {
      final samples = [
        for (var i = 0; i < 40; i++) one(0.2, false, index: i),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.verdict, CalibrationVerdict.singleClass);
      expect(report.refusalReasonZh, contains('正例'));
    });

    test('完全可分（完美预测）→ 没有有限 MLE，拒绝给系数', () {
      // 20 条"预测低且真的没记住" + 20 条"预测高且真的记住了"：存在一条直线把两类
      // 完全分开，似然沿那个方向还能一直变大，所以没有有限最大值。
      final samples = <RetentionSample>[
        for (var i = 0; i < 20; i++) one(0.2, false, index: i),
        for (var i = 0; i < 20; i++) one(0.8, true, index: 20 + i),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.verdict, CalibrationVerdict.notConverged);
      expect(report.fit, isNull);
      expect(report.refusalReasonZh, contains('收敛'));
    });
  });

  group('CalibrationReport.read —— 偏置与斜率', () {
    test('系统性过度自信 → 负偏置且显著', () {
      final samples = synthetic(
        rValues: const [0.6, 0.8],
        perBin: 60,
        slope: 1.0,
        intercept: -1.0,
      );
      final report = CalibrationReport.read(samples: samples);
      expect(report.usable, isTrue);
      expect(report.fit!.intercept, lessThan(-0.5));
      expect(report.biasSignificant, isTrue);
      expect(report.observedRate, lessThan(report.meanPredicted));
      expect(report.summaryZh, contains('过度自信'));
    });

    test('系统性低估 → 正偏置且显著', () {
      final samples = synthetic(
        rValues: const [0.15, 0.35],
        perBin: 60,
        slope: 1.0,
        intercept: 1.2,
      );
      final report = CalibrationReport.read(samples: samples);
      expect(report.usable, isTrue);
      expect(report.fit!.intercept, greaterThan(0.5));
      expect(report.biasSignificant, isTrue);
      expect(report.summaryZh, contains('低估自己'));
    });

    test('校准良好 → 偏置接近 0 且不显著', () {
      final samples = synthetic(
        rValues: const [0.2, 0.4, 0.6, 0.8],
        perBin: 60,
      );
      final report = CalibrationReport.read(samples: samples);
      expect(report.usable, isTrue);
      expect(report.fit!.intercept.abs(), lessThan(0.35));
      expect(report.fit!.slope, closeTo(1.0, 0.35));
      expect(report.biasSignificant, isFalse);
      expect(report.summaryZh, contains('没有系统性偏差'));
    });

    test('斜率要样本够了才标为可读', () {
      final small = CalibrationReport.read(
        samples: synthetic(rValues: const [0.3, 0.7], perBin: 40),
      );
      expect(small.usable, isTrue);
      expect(small.samples, 80);
      expect(small.slopeUsable, isFalse);

      final large = CalibrationReport.read(
        samples: synthetic(rValues: const [0.3, 0.5, 0.7], perBin: 80),
      );
      expect(large.samples, 240);
      expect(large.slopeUsable, isTrue);
      expect(large.summaryZh, contains('斜率'));
    });

    test('"预测太平"会被斜率认出来', () {
      final samples = synthetic(
        rValues: const [0.3, 0.5, 0.7],
        perBin: 80,
        slope: 2.0,
      );
      final report = CalibrationReport.read(samples: samples);
      expect(report.usable, isTrue);
      expect(report.fit!.slope, greaterThan(1.5));
    });

    test('预测正好 0 / 1 时不发散（logit 夹住了）', () {
      final samples = <RetentionSample>[
        // 0.0 / 1.0 会被夹到 0.1% / 99.9%；每组都混着两类结果，
        // 所以数据不是"几乎可分"，拟合必须给出有限的系数。
        for (var i = 0; i < 12; i++) one(0.0, i >= 10, index: i),
        for (var i = 0; i < 12; i++) one(0.5, i < 6, index: 12 + i),
        for (var i = 0; i < 12; i++) one(1.0, i < 10, index: 24 + i),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.samples, 36);
      expect(report.verdict, CalibrationVerdict.ok);
      expect(report.fit!.intercept.isFinite, isTrue);
      expect(report.fit!.interceptStdError.isFinite, isTrue);
      expect(
        report.fit!.intercept.abs(),
        lessThan(kMaxUsableCoefficientMagnitude),
      );
    });
  });

  group('CalibrationReport —— 统计与序列化', () {
    test('样本数 / 正例数 / 均值 / 实际比例如实统计', () {
      final samples = <RetentionSample>[
        one(0.2, false, index: 0),
        one(0.4, false, index: 1),
        one(0.6, true, index: 2),
        one(0.8, true, index: 3),
      ];
      final report = CalibrationReport.read(samples: samples);
      expect(report.samples, 4);
      expect(report.positives, 2);
      expect(report.meanPredicted, closeTo(0.5, 1e-9));
      expect(report.observedRate, closeTo(0.5, 1e-9));
      expect(report.observedMinusPredicted, closeTo(0.0, 1e-9));
    });

    test('同输入两次 → 同一个结果（没有随机初始化）', () {
      final samples = synthetic(
        rValues: const [0.3, 0.5, 0.7],
        perBin: 40,
        intercept: -0.6,
      );
      final a = CalibrationReport.read(samples: samples);
      final b = CalibrationReport.read(samples: samples);
      expect(a.toJson().toString(), b.toJson().toString());
      expect(a.fit!.iterations, b.fit!.iterations);
    });

    test('toJson 带 schema / verdict / 拟合细节', () {
      final samples = synthetic(rValues: const [0.3, 0.7], perBin: 40);
      final json = CalibrationReport.read(samples: samples).toJson();
      expect(json['schema'], 'mindnet.calibration/1');
      expect(json['verdict'], 'ok');
      expect(json['verdict_zh'], '可以看');
      expect(json['usable'], isTrue);
      expect(json['samples'], 80);
      expect(json['slope_usable'], isFalse);
      final fit = json['fit']! as Map<String, Object?>;
      expect(
          fit.keys,
          containsAll(<String>[
            'intercept',
            'intercept_std_error',
            'slope',
            'slope_std_error',
            'log_likelihood',
            'iterations',
          ]));
    });

    test('不算的结论也带得上理由（给模型/界面原样展示）', () {
      final json = CalibrationReport.read(samples: const []).toJson();
      expect(json['verdict'], 'no_samples');
      expect(json['usable'], isFalse);
      expect(json['fit'], isNull);
      expect(json['refusal'], isNotNull);
      expect(json['bias_significant'], isFalse);
    });

    test('verdict 与 wire 键来回一致', () {
      for (final verdict in CalibrationVerdict.values) {
        expect(CalibrationVerdict.byKey(verdict.wireValue), verdict);
      }
      expect(CalibrationVerdict.byKey('nope'), isNull);
      expect(CalibrationVerdict.byKey(null), isNull);
    });
  });
}
