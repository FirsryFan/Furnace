import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/assessment/exam_score_band.dart';

/// 默认策略下某科某分数 → 档位（简写）。
ExamScoreBand _band(
  ExamSubject subject,
  num score, {
  ExamScoreBandPolicy policy = ExamScoreBandPolicy.gaokao,
}) {
  return policy.bandFor(subject, score);
}

/// 默认策略下某科某分数 → 完整读数（简写）。
ExamScoreBandReading _read(ExamSubject subject, num score) {
  return readExamScoreBand(subject: subject, score: score);
}

/// 断言闭区间边界：`at` 落 [expected]，`at - step` 落下一档（或指定档）。
void _expectBoundary(
  ExamSubject subject,
  double at,
  ExamScoreBand expected,
  double step,
  ExamScoreBand below,
) {
  expect(_band(subject, at), expected, reason: '$subject @ $at');
  expect(_band(subject, at - step), below, reason: '$subject @ ${at - step}');
}

void main() {
  group('ExamSubject 学科与满分', () {
    test('六科齐全且编码顺序固定', () {
      expect(ExamSubject.values, hasLength(6));
      expect(
        ExamSubject.values.map((s) => s.code).toList(),
        const <String>[
          'math',
          'english',
          'chinese',
          'physics',
          'chemistry',
          'biology',
        ],
      );
    });

    test('数学/英语/语文满分为 150', () {
      expect(ExamSubject.math.fullScore, 150);
      expect(ExamSubject.english.fullScore, 150);
      expect(ExamSubject.chinese.fullScore, 150);
    });

    test('物理/化学/生物满分为 100', () {
      expect(ExamSubject.physics.fullScore, 100);
      expect(ExamSubject.chemistry.fullScore, 100);
      expect(ExamSubject.biology.fullScore, 100);
    });

    test('中文名固定', () {
      expect(ExamSubject.math.labelZh, '数学');
      expect(ExamSubject.english.labelZh, '英语');
      expect(ExamSubject.chinese.labelZh, '语文');
      expect(ExamSubject.physics.labelZh, '物理');
      expect(ExamSubject.chemistry.labelZh, '化学');
      expect(ExamSubject.biology.labelZh, '生物');
    });

    test('tryFromCode 与编码往返一致（大小写/空白容错）', () {
      for (final subject in ExamSubject.values) {
        expect(ExamSubject.tryFromCode(subject.code), subject);
      }
      expect(ExamSubject.tryFromCode(' MATH '), ExamSubject.math);
      expect(ExamSubject.tryFromCode('Physics'), ExamSubject.physics);
    });

    test('tryFromCode 认不出的编码返回 null（不猜）', () {
      for (final code in const <String?>[
        'history',
        'biology2',
        '',
        '   ',
        null,
      ]) {
        expect(ExamSubject.tryFromCode(code), isNull, reason: '$code');
      }
    });
  });

  group('ExamScoreBand 档位', () {
    test('六个档位与显示字 S+/S/A/B/C/D', () {
      expect(ExamScoreBand.values, hasLength(6));
      expect(ExamScoreBand.sPlus.label, 'S+');
      expect(ExamScoreBand.s.label, 'S');
      expect(ExamScoreBand.a.label, 'A');
      expect(ExamScoreBand.b.label, 'B');
      expect(ExamScoreBand.c.label, 'C');
      expect(ExamScoreBand.d.label, 'D');
    });

    test('档位由高到低排列（S+ 在前，D 在最后）', () {
      expect(ExamScoreBand.values.first, ExamScoreBand.sPlus);
      expect(ExamScoreBand.values.last, ExamScoreBand.d);
    });

    test('只有 S+ 是参考档', () {
      for (final band in ExamScoreBand.values) {
        expect(band.isReference, band == ExamScoreBand.sPlus);
      }
    });

    test('只有 D 表示「低于 C」', () {
      for (final band in ExamScoreBand.values) {
        expect(band.isBelowC, band == ExamScoreBand.d);
      }
    });
  });

  group('默认阈值表（用户确认口径）', () {
    test('六科阈值表与 task-63 完全一致', () {
      final expected = <ExamSubject, List<double>>{
        ExamSubject.math: <double>[150, 145, 135, 125, 110],
        ExamSubject.english: <double>[150, 140, 130, 120, 110],
        ExamSubject.chinese: <double>[150, 130, 115, 110, 100],
        ExamSubject.physics: <double>[100, 96, 86, 75, 60],
        ExamSubject.chemistry: <double>[100, 94, 86, 75, 60],
        ExamSubject.biology: <double>[100, 94, 86, 75, 60],
      };
      for (final entry in expected.entries) {
        final thresholds =
            ExamScoreBandPolicy.gaokao.thresholdsFor(entry.key);
        final values = <double>[
          thresholds.sPlus,
          thresholds.s,
          thresholds.a,
          thresholds.b,
          thresholds.c,
        ];
        expect(values, entry.value, reason: entry.key.code);
      }
    });

    test('数学边界：150 S+，149.9 S，145 S，144.9 A，135 A，125 B，110 C，109.9 D',
        () {
      const s = ExamSubject.math;
      expect(_band(s, 150), ExamScoreBand.sPlus);
      expect(_band(s, 149.9), ExamScoreBand.s);
      _expectBoundary(s, 145, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 135, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 125, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 110, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 109.9), ExamScoreBand.d);
    });

    test('英语边界：150 S+，149.9 S，140 S，139.9 A，130 A，120 B，110 C，109.9 D',
        () {
      const s = ExamSubject.english;
      expect(_band(s, 150), ExamScoreBand.sPlus);
      expect(_band(s, 149.9), ExamScoreBand.s);
      _expectBoundary(s, 140, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 130, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 120, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 110, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 109.9), ExamScoreBand.d);
    });

    test('语文边界：150 S+，149.9 S，130 S，129.9 A，115 A，110 B，100 C，99.9 D',
        () {
      const s = ExamSubject.chinese;
      expect(_band(s, 150), ExamScoreBand.sPlus);
      expect(_band(s, 149.9), ExamScoreBand.s);
      _expectBoundary(s, 130, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 115, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 110, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 100, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 99.9), ExamScoreBand.d);
    });

    test('物理边界：100 S+，99.9 S，96 S，95.9 A，86 A，75 B，60 C，59.9 D', () {
      const s = ExamSubject.physics;
      expect(_band(s, 100), ExamScoreBand.sPlus);
      expect(_band(s, 99.9), ExamScoreBand.s);
      _expectBoundary(s, 96, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 86, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 75, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 60, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 59.9), ExamScoreBand.d);
    });

    test('化学边界：100 S+，99.9 S，94 S，93.9 A，86 A，75 B，60 C，59.9 D', () {
      const s = ExamSubject.chemistry;
      expect(_band(s, 100), ExamScoreBand.sPlus);
      expect(_band(s, 99.9), ExamScoreBand.s);
      _expectBoundary(s, 94, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 86, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 75, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 60, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 59.9), ExamScoreBand.d);
    });

    test('生物边界：100 S+，99.9 S，94 S，93.9 A，86 A，75 B，60 C，59.9 D', () {
      const s = ExamSubject.biology;
      expect(_band(s, 100), ExamScoreBand.sPlus);
      expect(_band(s, 99.9), ExamScoreBand.s);
      _expectBoundary(s, 94, ExamScoreBand.s, 0.1, ExamScoreBand.a);
      _expectBoundary(s, 86, ExamScoreBand.a, 0.1, ExamScoreBand.b);
      _expectBoundary(s, 75, ExamScoreBand.b, 0.1, ExamScoreBand.c);
      _expectBoundary(s, 60, ExamScoreBand.c, 0.1, ExamScoreBand.d);
      expect(_band(s, 59.9), ExamScoreBand.d);
    });
  });

  group('每科通用边界（闭区间 + 端点）', () {
    test('每科满分默认都是 S+', () {
      for (final subject in ExamSubject.values) {
        expect(
          _band(subject, subject.fullScore),
          ExamScoreBand.sPlus,
          reason: subject.code,
        );
      }
    });

    test('每科 S 下界闭区间：s 是 S，s-0.1 是 A', () {
      for (final subject in ExamSubject.values) {
        final s = ExamScoreBandPolicy.gaokao.thresholdsFor(subject).s;
        expect(_band(subject, s), ExamScoreBand.s, reason: subject.code);
        expect(_band(subject, s - 0.1), ExamScoreBand.a, reason: subject.code);
      }
    });

    test('每科 C 下界闭区间：c 是 C，c-0.1 是 D', () {
      for (final subject in ExamSubject.values) {
        final c = ExamScoreBandPolicy.gaokao.thresholdsFor(subject).c;
        expect(_band(subject, c), ExamScoreBand.c, reason: subject.code);
        expect(_band(subject, c - 0.1), ExamScoreBand.d, reason: subject.code);
      }
    });

    test('每科 0 分都是 D（D=低于 C）', () {
      for (final subject in ExamSubject.values) {
        expect(_band(subject, 0), ExamScoreBand.d, reason: subject.code);
      }
    });

    test('每科满分-0.1 都还是 S（未到 S+ 门槛但远高于 s）', () {
      for (final subject in ExamSubject.values) {
        expect(
          _band(subject, subject.fullScore - 0.1),
          ExamScoreBand.s,
          reason: subject.code,
        );
      }
    });
  });

  group('S+ 可配置', () {
    test('默认 S+ 门槛等于该科满分', () {
      for (final subject in ExamSubject.values) {
        final thresholds = ExamScoreBandPolicy.gaokao.thresholdsFor(subject);
        expect(thresholds.sPlus, thresholds.fullScore, reason: subject.code);
        expect(ExamScoreBandPolicy.gaokao.sPlusMode, ExamSPlusMode.derived);
      }
    });

    test('onlyReference：满分落在 S，不输出 S+', () {
      const policy = ExamScoreBandPolicy.gaokaoReferenceSPlus;
      expect(policy.sPlusMode, ExamSPlusMode.onlyReference);
      for (final subject in ExamSubject.values) {
        expect(
          policy.bandFor(subject, subject.fullScore),
          ExamScoreBand.s,
          reason: subject.code,
        );
      }
    });

    test('onlyReference：任何合法分数都不会得到 S+', () {
      const policy = ExamScoreBandPolicy.gaokaoReferenceSPlus;
      for (final subject in ExamSubject.values) {
        final full = subject.fullScore;
        for (final score in <double>[
          0.0,
          full * 0.5,
          full - 0.1,
          full.toDouble(),
        ]) {
          expect(
            policy.bandFor(subject, score),
            isNot(ExamScoreBand.sPlus),
            reason: '${subject.code}@$score',
          );
        }
      }
    });

    test('S+ 门槛可调低：数学 148 即 S+，147.9 是 S', () {
      const lowered = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 148,
        s: 145,
        a: 135,
        b: 125,
        c: 110,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(lowered);
      expect(policy.bandFor(ExamSubject.math, 148), ExamScoreBand.sPlus);
      expect(policy.bandFor(ExamSubject.math, 147.9), ExamScoreBand.s);
    });

    test('replaceThreshold 只影响该科，其它科阈值不变', () {
      const lowered = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 148,
        s: 145,
        a: 135,
        b: 125,
        c: 110,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(lowered);
      expect(policy.bandFor(ExamSubject.english, 150), ExamScoreBand.sPlus);
      expect(policy.bandFor(ExamSubject.english, 140), ExamScoreBand.s);
    });

    test('replaceThreshold 不改原策略（不可变）', () {
      const lowered = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 148,
        s: 145,
        a: 135,
        b: 125,
        c: 110,
      );
      ExamScoreBandPolicy.gaokao.replaceThreshold(lowered);
      expect(
        ExamScoreBandPolicy.gaokao.thresholdsFor(ExamSubject.math).sPlus,
        150,
      );
    });

    test('copyWith 切换 S+ 口径与校准标记', () {
      final reference = ExamScoreBandPolicy.gaokao
          .copyWith(sPlusMode: ExamSPlusMode.onlyReference, calibrated: true);
      expect(reference.sPlusMode, ExamSPlusMode.onlyReference);
      expect(reference.calibrated, isTrue);
      expect(reference.bandFor(ExamSubject.math, 150), ExamScoreBand.s);
    });
  });

  group('policy 可配置与校验', () {
    test('可整体替换单科阈值', () {
      const custom = ExamScoreThresholds(
        subject: ExamSubject.physics,
        sPlus: 100,
        s: 90,
        a: 80,
        b: 70,
        c: 50,
      );
      const policy = ExamScoreBandPolicy(
        thresholds: <ExamSubject, ExamScoreThresholds>{
          ExamSubject.physics: custom,
        },
      );
      expect(policy.bandFor(ExamSubject.physics, 90), ExamScoreBand.s);
      expect(policy.bandFor(ExamSubject.physics, 89.9), ExamScoreBand.a);
      expect(policy.bandFor(ExamSubject.physics, 50), ExamScoreBand.c);
      expect(policy.bandFor(ExamSubject.physics, 49.9), ExamScoreBand.d);
    });

    test('缺某科阈值时 bandFor 抛 ArgumentError', () {
      const policy = ExamScoreBandPolicy(
        thresholds: <ExamSubject, ExamScoreThresholds>{
          ExamSubject.math: ExamScoreThresholds.math,
        },
      );
      expect(
        () => policy.bandFor(ExamSubject.physics, 90),
        throwsArgumentError,
      );
    });

    test('阈值配置的 subject 与键不一致时抛 ArgumentError', () {
      const policy = ExamScoreBandPolicy(
        thresholds: <ExamSubject, ExamScoreThresholds>{
          ExamSubject.math: ExamScoreThresholds.physics,
        },
      );
      expect(
        () => policy.bandFor(ExamSubject.math, 90),
        throwsArgumentError,
      );
    });

    test('阈值不严格递减时抛 ArgumentError', () {
      const broken = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 150,
        s: 145,
        a: 145,
        b: 125,
        c: 110,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(broken);
      expect(
        () => policy.bandFor(ExamSubject.math, 146),
        throwsArgumentError,
      );
    });

    test('S+ 门槛高于满分时抛 ArgumentError', () {
      const broken = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 160,
        s: 145,
        a: 135,
        b: 125,
        c: 110,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(broken);
      expect(
        () => policy.bandFor(ExamSubject.math, 150),
        throwsArgumentError,
      );
    });

    test('C 下界为负时抛 ArgumentError', () {
      const broken = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 150,
        s: 145,
        a: 135,
        b: 125,
        c: -10,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(broken);
      expect(
        () => policy.bandFor(ExamSubject.math, 100),
        throwsArgumentError,
      );
    });

    test('阈值含 NaN 时抛 ArgumentError', () {
      const broken = ExamScoreThresholds(
        subject: ExamSubject.math,
        sPlus: 150,
        s: double.nan,
        a: 135,
        b: 125,
        c: 110,
      );
      final policy = ExamScoreBandPolicy.gaokao.replaceThreshold(broken);
      expect(
        () => policy.bandFor(ExamSubject.math, 146),
        throwsArgumentError,
      );
    });

    test('默认策略 calibrated=false，copyWith 可置 true', () {
      expect(ExamScoreBandPolicy.gaokao.calibrated, isFalse);
      expect(ExamScoreBandPolicy.gaokao.copyWith(calibrated: true).calibrated,
          isTrue);
    });

    test('阈值 toJson 带 subject 与六个数', () {
      final json = ExamScoreThresholds.chinese.toJson();
      expect(json['subject'], 'chinese');
      expect(json['full_score'], 150.0);
      expect(json['s_plus'], 150.0);
      expect(json['s'], 130.0);
      expect(json['a'], 115.0);
      expect(json['b'], 110.0);
      expect(json['c'], 100.0);
    });
  });

  group('非法分数：越界/NaN/无穷抛 ArgumentError', () {
    test('负数抛 ArgumentError', () {
      expect(() => _band(ExamSubject.math, -0.1), throwsArgumentError);
      expect(() => _read(ExamSubject.physics, -1), throwsArgumentError);
    });

    test('超过满分抛 ArgumentError', () {
      expect(() => _band(ExamSubject.math, 151), throwsArgumentError);
      expect(() => _band(ExamSubject.physics, 101), throwsArgumentError);
    });

    test('NaN 抛 ArgumentError', () {
      expect(() => _band(ExamSubject.math, double.nan), throwsArgumentError);
    });

    test('正无穷/负无穷抛 ArgumentError', () {
      expect(
        () => _band(ExamSubject.math, double.infinity),
        throwsArgumentError,
      );
      expect(
        () => _band(ExamSubject.math, double.negativeInfinity),
        throwsArgumentError,
      );
    });

    test('刚好满分合法（S+），刚好 0 合法（D）', () {
      expect(_band(ExamSubject.chemistry, 100), ExamScoreBand.sPlus);
      expect(_band(ExamSubject.chemistry, 0), ExamScoreBand.d);
    });

    test('int 与 double 分数等价', () {
      expect(_band(ExamSubject.math, 145), _band(ExamSubject.math, 145.0));
      expect(_read(ExamSubject.math, 145).band, ExamScoreBand.s);
    });

    test('极小正数是合法 D', () {
      expect(_band(ExamSubject.biology, 0.0001), ExamScoreBand.d);
    });
  });

  group('读数 / 显示口径（内部评判，不暴露预测分）', () {
    test('band 与 policy.bandFor 一致', () {
      expect(_read(ExamSubject.math, 144.9).band, ExamScoreBand.a);
      expect(_read(ExamSubject.physics, 96).band, ExamScoreBand.s);
    });

    test('读数保留内部原始分', () {
      expect(_read(ExamSubject.chinese, 130).score, 130.0);
    });

    test('display 只输出档位字，不含数字/百分比', () {
      final reading = _read(ExamSubject.math, 145);
      expect(reading.display, 'S');
      expect(RegExp(r'\d').hasMatch(reading.display), isFalse);
      expect(reading.display.contains('%'), isFalse);
    });

    test('S+ 显示的档位字就是 S+', () {
      expect(_read(ExamSubject.math, 150).display, 'S+');
    });

    test('toJson 默认不含原始分数', () {
      final json = _read(ExamSubject.math, 145).toJson();
      expect(json.containsKey('score'), isFalse);
      expect(json['band'], 's');
      expect(json['band_label'], 'S');
      expect(json['subject'], 'math');
    });

    test('toJson includeScore=true 才带原始分数（内部日志用）', () {
      final json = _read(ExamSubject.math, 145).toJson(includeScore: true);
      expect(json['score'], 145.0);
    });

    test('toJson 的 s_plus_mode 与 policy 一致', () {
      expect(
        _read(ExamSubject.math, 150).toJson()['s_plus_mode'],
        'derived',
      );
      final reference = readExamScoreBand(
        subject: ExamSubject.math,
        score: 150,
        policy: ExamScoreBandPolicy.gaokaoReferenceSPlus,
      );
      expect(reference.toJson()['s_plus_mode'], 'only_reference');
    });

    test('toJson 的 calibrated 默认 false', () {
      expect(_read(ExamSubject.math, 145).toJson()['calibrated'], isFalse);
    });

    test('isSPlus / isBelowC 标记', () {
      expect(_read(ExamSubject.math, 150).isSPlus, isTrue);
      expect(_read(ExamSubject.math, 145).isSPlus, isFalse);
      expect(_read(ExamSubject.math, 109.9).isBelowC, isTrue);
      expect(_read(ExamSubject.math, 110).isBelowC, isFalse);
    });

    test('onlyReference 读数标记 isSPlusReferenceOnly', () {
      final reading = readExamScoreBand(
        subject: ExamSubject.physics,
        score: 100,
        policy: ExamScoreBandPolicy.gaokaoReferenceSPlus,
      );
      expect(reading.isSPlusReferenceOnly, isTrue);
      expect(reading.isSPlus, isFalse);
      expect(reading.band, ExamScoreBand.s);
    });

    test('读数带回该科阈值', () {
      final reading = _read(ExamSubject.english, 140);
      expect(reading.thresholds, ExamScoreThresholds.english);
      expect(reading.thresholds.s, 140);
    });

    test('纯函数：同一输入两次读数一致', () {
      final a = _read(ExamSubject.chinese, 114.9);
      final b = _read(ExamSubject.chinese, 114.9);
      expect(a.band, b.band);
      expect(a.display, b.display);
      expect(a.score, b.score);
    });
  });
}
