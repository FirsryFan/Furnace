import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/ability_trend.dart';

/// 便于构造点：第 day 天（UTC）的分数。
AbilityTrendPoint _point(int day, double score) =>
    AbilityTrendPoint(capturedAt: DateTime.utc(2026, 1, day), score: score);

/// 便于构造同一采集时刻的点。
AbilityTrendPoint _pointAt(DateTime at, double score) =>
    AbilityTrendPoint(capturedAt: at, score: score);

/// 取分数序列，便于断言排序结果。
List<double> _scoresOf(AbilityTrendSeries series) =>
    series.points.map((point) => point.score).toList();

void main() {
  group('常量与空序列', () {
    test('常量值与契约一致', () {
      expect(kAbilityTrendFlatEpsilon, 2.0);
      expect(kAbilityTrendMaxPoints, 30);
    });

    test('empty 是空序列', () {
      final series = AbilityTrendSeries.empty;
      expect(series.isEmpty, isTrue);
      expect(series.isNotEmpty, isFalse);
      expect(series.length, 0);
      expect(series.points, isEmpty);
    });

    test('空序列各 getter 为 null / flat / 空列表', () {
      final series = AbilityTrendSeries(const <AbilityTrendPoint>[]);
      expect(series.earliest, isNull);
      expect(series.latest, isNull);
      expect(series.earliestScore, isNull);
      expect(series.latestScore, isNull);
      expect(series.delta, isNull);
      expect(series.averageScore, isNull);
      expect(series.bestScore, isNull);
      expect(series.worstScore, isNull);
      expect(series.direction, AbilityTrendDirection.flat);
      expect(series.progress01, isNull);
      expect(series.normalizedScores, isEmpty);
      expect(series.normalizedPositions, isEmpty);
    });
  });

  group('单点', () {
    test('单点的 delta 为 0.0、方向 flat、坐标只有 [0]', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[_point(1, 73.5)]);
      expect(series.length, 1);
      expect(series.earliestScore, 73.5);
      expect(series.latestScore, 73.5);
      expect(series.delta, 0.0);
      expect(series.direction, AbilityTrendDirection.flat);
      expect(series.progress01, 0.735);
      expect(series.normalizedPositions, <double>[0.0]);
    });

    test('单点的聚合分数等于该点分数', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[_point(1, 73.5)]);
      expect(series.averageScore, 73.5);
      expect(series.bestScore, 73.5);
      expect(series.worstScore, 73.5);
    });
  });

  group('排序与新旧判定', () {
    test('乱序输入被排成旧 → 新', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(3, 70),
        _point(1, 50),
        _point(2, 60),
      ]);
      expect(_scoresOf(series), <double>[50, 60, 70]);
      expect(series.earliestScore, 50);
      expect(series.latestScore, 70);
      expect(series.earliest!.capturedAt, DateTime.utc(2026, 1, 1));
      expect(series.latest!.capturedAt, DateTime.utc(2026, 1, 3));
    });

    test('同一 capturedAt 的点保持传入顺序', () {
      final sameTime = DateTime.utc(2026, 2, 1);
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _pointAt(sameTime, 40),
        _point(1, 10),
        _pointAt(sameTime, 20),
      ]);
      // 2026-01-01 在最前；两个同刻点按传入顺序 40 再 20。
      expect(_scoresOf(series), <double>[10, 40, 20]);
    });

    test('改构造用的入参列表不影响已构造的序列', () {
      final input = <AbilityTrendPoint>[_point(2, 60), _point(1, 50)];
      final series = AbilityTrendSeries(input);
      input
        ..clear()
        ..add(_point(9, 99));
      expect(series.length, 2);
      expect(_scoresOf(series), <double>[50, 60]);
    });
  });

  group('delta 与方向', () {
    test('恰 +2.0 算有方向（improving），不是 flat', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 50),
        _point(2, 52),
      ]);
      expect(series.delta, 2.0);
      expect(series.direction, AbilityTrendDirection.improving);
    });

    test('恰 -2.0 算有方向（declining），不是 flat', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 52),
        _point(2, 50),
      ]);
      expect(series.delta, -2.0);
      expect(series.direction, AbilityTrendDirection.declining);
    });

    test('+2.1 继续 improving', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 50),
        _point(2, 52.1),
      ]);
      expect(series.direction, AbilityTrendDirection.improving);
    });

    test('1.99 的差算 flat', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 50),
        _point(2, 51.99),
      ]);
      expect(series.delta, closeTo(1.99, 1e-9));
      expect(series.direction, AbilityTrendDirection.flat);
    });

    test('完全相同算 flat', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 60),
        _point(2, 60),
      ]);
      expect(series.delta, 0.0);
      expect(series.direction, AbilityTrendDirection.flat);
    });

    test('明显下降 → declining', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 80),
        _point(2, 60),
      ]);
      expect(series.delta, -20.0);
      expect(series.direction, AbilityTrendDirection.declining);
    });

    test('多点的 delta 只看最早与最新，与中间点无关', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 30),
        _point(2, 90),
        _point(3, 40),
      ]);
      expect(series.delta, 10.0);
      expect(series.direction, AbilityTrendDirection.improving);
    });
  });

  group('聚合分数', () {
    test('average / best / worst 取全部点', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 40),
        _point(2, 90),
        _point(3, 50),
      ]);
      expect(series.averageScore, 60.0);
      expect(series.bestScore, 90.0);
      expect(series.worstScore, 40.0);
    });
  });

  group('归一化坐标', () {
    test('normalizedScores 把分数夹到 0–1', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, -10),
        _point(2, 0),
        _point(3, 50),
        _point(4, 100),
        _point(5, 150),
      ]);
      expect(series.normalizedScores, <double>[0.0, 0.0, 0.5, 1.0, 1.0]);
    });

    test('normalizedScores 顺序与 points 一致', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(2, 80),
        _point(1, 20),
      ]);
      expect(series.normalizedScores, <double>[0.2, 0.8]);
    });

    test('progress01 夹到 0–1', () {
      expect(
        AbilityTrendSeries(<AbilityTrendPoint>[_point(1, 150)]).progress01,
        1.0,
      );
      expect(
        AbilityTrendSeries(<AbilityTrendPoint>[_point(1, -10)]).progress01,
        0.0,
      );
    });

    test('normalizedPositions 首 0 末 1 且均匀', () {
      final three = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 10),
        _point(2, 20),
        _point(3, 30),
      ]);
      expect(three.normalizedPositions, <double>[0.0, 0.5, 1.0]);
      final two = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 10),
        _point(2, 20),
      ]);
      expect(two.normalizedPositions, <double>[0.0, 1.0]);
    });
  });

  group('capped 与 fromNewestFirst', () {
    test('capped 只保留最新 N 个点', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 10),
        _point(2, 20),
        _point(3, 30),
        _point(4, 40),
        _point(5, 50),
      ]);
      final capped = series.capped(max: 3);
      expect(capped.length, 3);
      expect(_scoresOf(capped), <double>[30, 40, 50]);
      expect(capped.latestScore, 50);
    });

    test('capped(max <= 0) 返回空序列', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 10),
        _point(2, 20),
      ]);
      expect(series.capped(max: 0).isEmpty, isTrue);
      expect(series.capped(max: -3).isEmpty, isTrue);
      expect(series.capped(max: 0).points, isEmpty);
    });

    test('capped 长度不足时返回等价内容', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[
        _point(1, 10),
        _point(2, 20),
      ]);
      final capped = series.capped(max: 10);
      expect(capped.length, series.length);
      expect(_scoresOf(capped), _scoresOf(series));
    });

    test('fromNewestFirst 把新 → 旧反转成旧 → 新', () {
      final series = AbilityTrendSeries.fromNewestFirst(<AbilityTrendPoint>[
        _point(3, 30),
        _point(2, 20),
        _point(1, 10),
      ]);
      expect(_scoresOf(series), <double>[10, 20, 30]);
      expect(series.earliest!.capturedAt, DateTime.utc(2026, 1, 1));
      expect(series.latest!.capturedAt, DateTime.utc(2026, 1, 3));
    });

    test('fromNewestFirst 的 max 只保留最新的点', () {
      final series = AbilityTrendSeries.fromNewestFirst(<AbilityTrendPoint>[
        _point(5, 50),
        _point(4, 40),
        _point(3, 30),
        _point(2, 20),
        _point(1, 10),
      ], max: 2);
      expect(_scoresOf(series), <double>[40, 50]);
      expect(series.latestScore, 50);
    });

    test('fromNewestFirst 空输入返回空序列', () {
      final series =
          AbilityTrendSeries.fromNewestFirst(const <AbilityTrendPoint>[]);
      expect(series.isEmpty, isTrue);
      expect(series.direction, AbilityTrendDirection.flat);
    });
  });

  group('不可变与确定性', () {
    test('points 不可修改', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[_point(1, 10)]);
      expect(() => series.points.add(_point(2, 20)), throwsUnsupportedError);
      expect(() {
        series.points[0] = _point(2, 20);
      }, throwsUnsupportedError);
    });

    test('normalizedScores 不可修改', () {
      final series = AbilityTrendSeries(<AbilityTrendPoint>[_point(1, 10)]);
      expect(() => series.normalizedScores.add(1.0), throwsUnsupportedError);
    });

    test('同一输入两次构造结果一致', () {
      List<AbilityTrendPoint> input() => <AbilityTrendPoint>[
            _point(2, 80),
            _point(1, 20),
            _point(3, 50),
          ];
      final a = AbilityTrendSeries(input());
      final b = AbilityTrendSeries(input());
      expect(_scoresOf(a), _scoresOf(b));
      expect(a.delta, b.delta);
      expect(a.direction, b.direction);
      expect(a.averageScore, b.averageScore);
      expect(a.normalizedScores, b.normalizedScores);
      expect(a.normalizedPositions, b.normalizedPositions);
    });
  });
}
