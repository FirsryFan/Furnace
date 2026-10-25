import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_keywords.dart';

/// 复现用户 2026-10-25 反馈：旧算法只给 5–14 字，命中率不稳。
/// 新口径：理科（math/physics/chemistry/biology）15–30 字；
/// 文科（chinese/english/history/politics/geography）20–40 字且**严格短于题干**；
/// 题干短于目标下限时回退为尽量长的合法子串（≥4 字），不返回空。
///
/// 这里钉的是**行为不变量**（长度带 / 真实子串 / 不跨段 / 确定性 / 截断），
/// 不是某一次运行出来的精确列表：算法微调时这些断言仍应成立。
void main() {
  // 化学实验题干：162 字，含两处行内公式；清洗后仍有 3 个 ≥15 字的连续段。
  const longStem =
      r'某研究小组为探究温度对过氧化氢分解速率的影响设计了如下实验方案取等体积等浓度的过氧化氢溶液分别置于不同温度的水浴中并在$25\ ^\circ\mathrm{C}$条件下加入等量二氧化锰粉末测量相同时间内收集到的氧气体积重复三次取平均值，用$0.1\ \mathrm{mol/L}$的过氧化氢溶液重复上述实验步骤并记录实验现象';
  const shortStem = '下列正确的是';
  const pureFormulaStem = r'$\frac{a}{b}+\sqrt{c}=0$';

  group('长度常量与学科带', () {
    test('四个长度常量就是用户口径：理科 15–30、文科 20–40', () {
      expect(kZujuanScienceMinLength, 15);
      expect(kZujuanScienceMaxLength, 30);
      expect(kZujuanHumanitiesMinLength, 20);
      expect(kZujuanHumanitiesMaxLength, 40);
      expect(kZujuanScienceMinLength, lessThan(kZujuanScienceMaxLength));
      expect(kZujuanHumanitiesMinLength, lessThan(kZujuanHumanitiesMaxLength));
    });

    test('理科键 → science（含大小写与首尾空白容错）', () {
      const keys = <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        ' MATH ',
        'Physics',
      ];
      for (final key in keys) {
        expect(zujuanSubjectBandFor(key), ZujuanSubjectBand.science,
            reason: key);
      }
    });

    test('文科键 → humanities', () {
      const keys = <String>[
        'chinese',
        'english',
        'history',
        'politics',
        'geography',
        ' CHINESE ',
      ];
      for (final key in keys) {
        expect(zujuanSubjectBandFor(key), ZujuanSubjectBand.humanities,
            reason: key);
      }
    });

    test('null / 空白 / 非学科键 → science（宁可按更宽松的理科口径）', () {
      const keys = <String?>[
        null,
        '',
        '   ',
        'informatics',
        'qiangji',
        'unknown',
        '生物'
      ];
      for (final key in keys) {
        expect(zujuanSubjectBandFor(key), ZujuanSubjectBand.science,
            reason: '$key');
      }
    });
  });

  group('长理科题干（162 字，含行内公式）：science 15–30 字', () {
    test('返回 1..8 条，每条 15–30 字', () {
      final candidates = extractZujuanKeywords(longStem);
      expect(candidates.length, inInclusiveRange(1, 8));
      for (final candidate in candidates) {
        expect(
          candidate.length,
          inInclusiveRange(kZujuanScienceMinLength, kZujuanScienceMaxLength),
          reason: candidate,
        );
      }
    });

    test('每条都是题干文本层的真实连续子串（不跨公式拼接、不改字）', () {
      final candidates = extractZujuanKeywords(longStem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(longStem.contains(candidate), isTrue, reason: candidate);
      }
    });

    test('候选里没有公式/标记/标点残留', () {
      // 清洗规则把公式、〔〕标记、标点都变成分隔符；候选若含这些字符说明漏水。
      final banned = RegExp(r'[\s$\\〔〕]|mathrm|circ|frac|\^');
      final candidates = extractZujuanKeywords(longStem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(banned.hasMatch(candidate), isFalse, reason: candidate);
      }
    });

    test('去重、互不为子串、条数不超过 maxCandidates', () {
      final candidates = extractZujuanKeywords(longStem);
      expect(candidates.toSet().length, candidates.length);
      _expectNoMutualSubstring(candidates);
      expect(
        extractZujuanKeywords(longStem, maxCandidates: 3).length,
        lessThanOrEqualTo(3),
      );
    });

    test('确定性：同输入两次调用逐条相同', () {
      expect(extractZujuanKeywords(longStem), extractZujuanKeywords(longStem));
    });
  });

  group('同一题干 humanities：20–40 字且严格短于题干', () {
    test('至少 3 条，每条 20–40 字', () {
      final candidates = extractZujuanKeywords(
        longStem,
        band: ZujuanSubjectBand.humanities,
      );
      expect(candidates.length, greaterThanOrEqualTo(3));
      for (final candidate in candidates) {
        expect(
          candidate.length,
          inInclusiveRange(
            kZujuanHumanitiesMinLength,
            kZujuanHumanitiesMaxLength,
          ),
          reason: candidate,
        );
      }
    });

    test('每条都严格短于题干（keyword.length < stem.length）', () {
      final stemLength = longStem.trim().length;
      final candidates = extractZujuanKeywords(
        longStem,
        band: ZujuanSubjectBand.humanities,
      );
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(candidate.length, lessThan(stemLength), reason: candidate);
      }
    });

    test('真实子串、去重、互不为子串', () {
      final candidates = extractZujuanKeywords(
        longStem,
        band: ZujuanSubjectBand.humanities,
      );
      expect(candidates.toSet().length, candidates.length);
      _expectNoMutualSubstring(candidates);
      for (final candidate in candidates) {
        expect(longStem.contains(candidate), isTrue, reason: candidate);
      }
    });
  });

  group('短题干回退：不返回空，长度不超过题干', () {
    test('「下列正确的是」（6 字）：非空且每条 4..6 字', () {
      final candidates = extractZujuanKeywords(shortStem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(candidate.length, inInclusiveRange(4, shortStem.length));
        expect(shortStem.contains(candidate), isTrue, reason: candidate);
      }
    });

    test('「光合作用」（4 字）science：返回整段一条', () {
      expect(extractZujuanKeywords('光合作用'), const <String>['光合作用']);
    });

    test('「光合作用」humanities：题干无法再短，仍非空且不超过题干', () {
      final candidates = extractZujuanKeywords(
        '光合作用',
        band: ZujuanSubjectBand.humanities,
      );
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(candidate.length, lessThanOrEqualTo(4), reason: candidate);
      }
    });

    test('5 字「细胞呼吸的」：候选仍 ≥4 字且不超过题干', () {
      const stem = '细胞呼吸的';
      final candidates = extractZujuanKeywords(stem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(candidate.length, inInclusiveRange(4, stem.length));
        expect(stem.contains(candidate), isTrue, reason: candidate);
      }
    });

    test('7 字套话题干也非空', () {
      const stem = '关于细胞的说法';
      final candidates = extractZujuanKeywords(stem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(candidate.length, inInclusiveRange(4, stem.length));
      }
    });
  });

  group('空输入与没有可用文本层', () {
    test('空串 / 纯空白 → 空', () {
      expect(extractZujuanKeywords(''), isEmpty);
      expect(extractZujuanKeywords('   '), isEmpty);
      expect(extractZujuanKeywords(' \n\t '), isEmpty);
    });

    test('纯公式题干 → 空', () {
      expect(extractZujuanKeywords(pureFormulaStem), isEmpty);
    });

    test('只有标点 → 空', () {
      expect(extractZujuanKeywords('，。；：？！、'), isEmpty);
    });

    test('清洗后每段都短于 4 字 → 空', () {
      expect(extractZujuanKeywords('细胞，呼吸'), isEmpty);
    });

    test('跨公式断开后两段都 <4 字 → 空（不拼接）', () {
      expect(extractZujuanKeywords(r'细胞$\frac{a}{b}$呼吸'), isEmpty);
    });
  });

  group('maxCandidates 截断（0 / 1 / 2 / 大值）', () {
    test('0 与负数 → 空', () {
      expect(extractZujuanKeywords(longStem, maxCandidates: 0), isEmpty);
      expect(extractZujuanKeywords(longStem, maxCandidates: -3), isEmpty);
    });

    test('1 条 = 全量首条', () {
      final full = extractZujuanKeywords(longStem);
      expect(full, isNotEmpty);
      expect(
        extractZujuanKeywords(longStem, maxCandidates: 1),
        <String>[full.first],
      );
    });

    test('2 条 = 全量前 2 条（截断发生在排序去重之后）', () {
      final full = extractZujuanKeywords(longStem);
      expect(full.length, greaterThanOrEqualTo(2));
      expect(
        extractZujuanKeywords(longStem, maxCandidates: 2),
        full.take(2).toList(),
      );
    });

    test('maxCandidates 大于候选数时返回全部', () {
      expect(
        extractZujuanKeywords(longStem, maxCandidates: 100),
        extractZujuanKeywords(longStem),
      );
    });
  });

  group('不跨段拼接（标点 / 空格是分隔符）', () {
    test('「光合作用，细胞呼吸」不含跨句读拼出的「作用细胞」', () {
      const stem = '光合作用，细胞呼吸';
      final candidates = extractZujuanKeywords(stem);
      expect(candidates, isNotEmpty);
      expect(candidates.join('｜'), isNot(contains('作用细胞')));
      for (final candidate in candidates) {
        expect(stem.contains(candidate), isTrue, reason: candidate);
      }
    });

    test('空格 / 括号同样当分隔符：候选不含空白或括号', () {
      const stem = '光合作用 呼吸作用（细胞呼吸）';
      final candidates = extractZujuanKeywords(stem);
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(RegExp(r'[\s（）()]').hasMatch(candidate), isFalse,
            reason: candidate);
        expect(stem.contains(candidate), isTrue, reason: candidate);
      }
    });
  });

  group('两 band 的通用不变量（同一批题干）', () {
    const stems = <String>[
      longStem,
      shortStem,
      '光合作用',
      '细胞呼吸，光合作用',
    ];

    test('每条候选 ≥4 字、≤min(band 上限, 题干长度)、是题干子串、去重、无互为子串', () {
      for (final band in ZujuanSubjectBand.values) {
        final bandMax = band == ZujuanSubjectBand.science
            ? kZujuanScienceMaxLength
            : kZujuanHumanitiesMaxLength;
        for (final stem in stems) {
          final candidates = extractZujuanKeywords(stem, band: band);
          expect(candidates, isNotEmpty, reason: '$band / $stem');
          expect(candidates.length, lessThanOrEqualTo(8),
              reason: '$band / $stem');
          final limit =
              bandMax < stem.trim().length ? bandMax : stem.trim().length;
          for (final candidate in candidates) {
            expect(candidate.length, greaterThanOrEqualTo(4),
                reason: candidate);
            expect(candidate.length, lessThanOrEqualTo(limit),
                reason: candidate);
            expect(stem.contains(candidate), isTrue, reason: candidate);
          }
          expect(candidates.toSet().length, candidates.length,
              reason: '$band / $stem');
          _expectNoMutualSubstring(candidates);
        }
      }
    });

    test('确定性：两 band × 四题干，两次调用相等', () {
      for (final band in ZujuanSubjectBand.values) {
        for (final stem in stems) {
          expect(
            extractZujuanKeywords(stem, band: band),
            extractZujuanKeywords(stem, band: band),
            reason: '$band / $stem',
          );
        }
      }
    });
  });
}

void _expectNoMutualSubstring(List<String> candidates) {
  for (var i = 0; i < candidates.length; i++) {
    for (var j = i + 1; j < candidates.length; j++) {
      final first = candidates[i];
      final second = candidates[j];
      expect(
        first.contains(second) || second.contains(first),
        isFalse,
        reason: '互为子串: $first / $second',
      );
    }
  }
}
