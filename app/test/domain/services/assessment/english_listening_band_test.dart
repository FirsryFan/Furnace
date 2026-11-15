import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/assessment/english_listening_band.dart';
import 'package:furnace/domain/services/assessment/exam_score_band.dart';

/// 英语听力子档简写。
EnglishListeningBandReading _listen(int wrongCount) =>
    readEnglishListeningBand(wrongCount);

void main() {
  group('EnglishListeningSubBand 子档枚举', () {
    test('三个已确认子档：0错 / 1错 / 2错', () {
      expect(EnglishListeningSubBand.values, hasLength(3));
      expect(EnglishListeningSubBand.noneWrong.wrongCount, 0);
      expect(EnglishListeningSubBand.oneWrong.wrongCount, 1);
      expect(EnglishListeningSubBand.twoWrong.wrongCount, 2);
      expect(EnglishListeningSubBand.noneWrong.label, '0错');
      expect(EnglishListeningSubBand.oneWrong.label, '1错');
      expect(EnglishListeningSubBand.twoWrong.label, '2错');
    });
  });

  group('0 错 → S+/S/A（不区分）', () {
    test('0 错命中 noneWrong，对应 S+ / S / A 三个档位', () {
      final reading = _listen(0);
      expect(reading.isMapped, isTrue);
      expect(reading.subBand, EnglishListeningSubBand.noneWrong);
      expect(reading.bands, <ExamScoreBand>[
        ExamScoreBand.sPlus,
        ExamScoreBand.s,
        ExamScoreBand.a,
      ]);
    });

    test('0 错的显示串是 S+/S/A（0错）', () {
      expect(_listen(0).display, 'S+/S/A（0错）');
    });

    test('0 错不是已定义错误、unknown_reason 为 none', () {
      expect(_listen(0).unknownReason, 'none');
    });
  });

  group('1 错 → B', () {
    test('1 错只对应 B', () {
      final reading = _listen(1);
      expect(reading.subBand, EnglishListeningSubBand.oneWrong);
      expect(reading.bands, <ExamScoreBand>[ExamScoreBand.b]);
    });

    test('1 错的显示串是 B（1错）', () {
      expect(_listen(1).display, 'B（1错）');
    });
  });

  group('2 错 → C/D（D 也是 2 错，不延伸到 3+）', () {
    test('2 错同时对应 C 和 D', () {
      final reading = _listen(2);
      expect(reading.subBand, EnglishListeningSubBand.twoWrong);
      expect(reading.bands, <ExamScoreBand>[
        ExamScoreBand.c,
        ExamScoreBand.d,
      ]);
    });

    test('2 错的显示串是 C/D（2错）', () {
      expect(_listen(2).display, 'C/D（2错）');
    });

    test('2 错读数不把 D 当成 3+ 错', () {
      // 口径：D = 2 错；3 错及以上未定义，不能反推成 D。
      expect(_listen(2).bands, contains(ExamScoreBand.d));
      expect(_listen(3).bands, isNot(contains(ExamScoreBand.d)));
      expect(_listen(3).display, isNot(contains('D')));
    });
  });

  group('>2 错 → 未定义（D 不做 3+）', () {
    test('3 错未定义，不归任何档', () {
      final reading = _listen(3);
      expect(reading.isMapped, isFalse);
      expect(reading.isUnmapped, isTrue);
      expect(reading.subBand, isNull);
      expect(reading.bands, isEmpty);
    });

    test('3 错的 unknown_reason 是 above_confirmed_range', () {
      expect(_listen(3).unknownReason, 'above_confirmed_range');
      expect(_listen(20).unknownReason, 'above_confirmed_range');
    });

    test('3 错显示「未定义（>2错）」，不显示 D', () {
      expect(_listen(3).display, '未定义（>2错）');
      expect(_listen(3).display.contains('D'), isFalse);
    });

    test('更大的错题数（4/10/20）都未定义', () {
      for (final wrong in <int>[4, 10, 20]) {
        final reading = _listen(wrong);
        expect(reading.isUnmapped, isTrue, reason: '$wrong');
        expect(reading.bands, isEmpty, reason: '$wrong');
      }
    });
  });

  group('非法错题数', () {
    test('负错题数抛 ArgumentError', () {
      expect(() => _listen(-1), throwsArgumentError);
      expect(() => _listen(-10), throwsArgumentError);
    });
  });

  group('toJson（默认不写错题数）', () {
    test('默认不含 wrong_count', () {
      final json = _listen(2).toJson();
      expect(json.containsKey('wrong_count'), isFalse);
      expect(json['sub_band'], 'twoWrong');
      expect(json['sub_band_label'], '2错');
      expect(json['bands'], <String>['C', 'D']);
      expect(json['display'], 'C/D（2错）');
      expect(json['unknown_reason'], 'none');
    });

    test('includeWrongCount=true 才带错题数', () {
      expect(_listen(2).toJson(includeWrongCount: true)['wrong_count'], 2);
      expect(_listen(3).toJson(includeWrongCount: true)['wrong_count'], 3);
    });

    test('未定义读数序列化为 null 子档 + 空 bands + 原因', () {
      final json = _listen(3).toJson();
      expect(json['sub_band'], isNull);
      expect(json['sub_band_label'], isNull);
      expect(json['bands'], isEmpty);
      expect(json['unknown_reason'], 'above_confirmed_range');
    });
  });

  group('英语总分 150 阈值不被改变', () {
    test('英语总分阈值仍是 150/140/130/120/110', () {
      final english = ExamScoreBandPolicy.gaokao.thresholdsFor(
        ExamSubject.english,
      );
      expect(english, ExamScoreThresholds.english);
      expect(
        <double>[english.sPlus, english.s, english.a, english.b, english.c],
        <double>[150, 140, 130, 120, 110],
      );
    });

    test('英语总分分档与之前一致：150 S+，140 S，139.9 A，110 C，109.9 D', () {
      const policy = ExamScoreBandPolicy.gaokao;
      expect(policy.bandFor(ExamSubject.english, 150), ExamScoreBand.sPlus);
      expect(policy.bandFor(ExamSubject.english, 140), ExamScoreBand.s);
      expect(policy.bandFor(ExamSubject.english, 139.9), ExamScoreBand.a);
      expect(policy.bandFor(ExamSubject.english, 130), ExamScoreBand.a);
      expect(policy.bandFor(ExamSubject.english, 110), ExamScoreBand.c);
      expect(policy.bandFor(ExamSubject.english, 109.9), ExamScoreBand.d);
    });

    test('听力子档与英语总分是两条独立记录（互不改写）', () {
      // 听力 2 错 → 子档 C/D；英语总分 139.9 仍是 A。二者不联动。
      expect(_listen(2).bands, <ExamScoreBand>[
        ExamScoreBand.c,
        ExamScoreBand.d,
      ]);
      expect(
        ExamScoreBandPolicy.gaokao.bandFor(ExamSubject.english, 139.9),
        ExamScoreBand.a,
      );
    });
  });

  group('纯函数 / 显示口径', () {
    test('同一错题数两次读数一致', () {
      final a = _listen(2);
      final b = _listen(2);
      expect(a.display, b.display);
      expect(a.subBand, b.subBand);
      expect(a.bands, b.bands);
    });

    test('显示串不含总分 150、百分比或「预测」字样', () {
      for (final wrong in <int>[0, 1, 2, 3]) {
        final display = _listen(wrong).display;
        expect(display.contains('150'), isFalse, reason: '$wrong');
        expect(display.contains('%'), isFalse, reason: '$wrong');
        expect(display.contains('预测'), isFalse, reason: '$wrong');
      }
    });
  });
}
