import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/review_deck_key.dart';

const String _sample = 'review_deck|physics|A3|物理/高中物理/力学';
const String _junk = 'not-a-deck-key';

void main() {
  group('reviewDeckKey 生成', () {
    test('单标签单能力生成一条键', () {
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['物理/高中物理/力学'],
          capabilityCodes: <String>['A3'],
        ),
        <String>[_sample],
      );
    });

    test('多能力按编号升序（A2 在 A10 前）', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/力学'],
        capabilityCodes: <String>['A10', 'A2', 'A1'],
      );
      expect(keys, <String>[
        'review_deck|physics|A1|物理/力学',
        'review_deck|physics|A2|物理/力学',
        'review_deck|physics|A10|物理/力学',
      ]);
    });

    test('多标签多能力生成交叉积并按能力→标签排序', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/运动学', '物理/力学'],
        capabilityCodes: <String>['A3', 'A1'],
      );
      expect(keys, <String>[
        'review_deck|physics|A1|物理/力学',
        'review_deck|physics|A1|物理/运动学',
        'review_deck|physics|A3|物理/力学',
        'review_deck|physics|A3|物理/运动学',
      ]);
    });

    test('交叉积数量 = 能力数 × 标签数且无重复', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'math',
        tagPaths: <String>['数学/函数', '数学/数列', '数学/概率'],
        capabilityCodes: <String>['A1', 'A4'],
      );
      expect(keys, hasLength(6));
      expect(keys.toSet(), hasLength(6));
    });

    test('重复输入去重', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/力学', ' 物理/力学 ', '物理/力学'],
        capabilityCodes: <String>['a3', 'A3', ' a3 '],
      );
      expect(keys, <String>['review_deck|physics|A3|物理/力学']);
    });

    test('清洗：两端空白、能力大小写、标签路径空白段', () {
      expect(
        reviewDeckKey(
          subjectKey: '  physics  ',
          tagPaths: <String>[' 物理 / 高中物理 / 力学 '],
          capabilityCodes: <String>[' a3 '],
        ),
        <String>[_sample],
      );
    });

    test('标签路径多余斜杠与空段被丢弃', () {
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['物理//高中物理/ /力学'],
          capabilityCodes: <String>['A3'],
        ),
        <String>[_sample],
      );
    });

    test('输入顺序不影响结果', () {
      final List<String> forward = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/运动学', '物理/力学'],
        capabilityCodes: <String>['A3', 'A1'],
      );
      final List<String> backward = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/力学', '物理/运动学'],
        capabilityCodes: <String>['A1', 'A3'],
      );
      expect(forward, backward);
    });

    test('同一输入两次调用结果相同', () {
      final List<String> first = reviewDeckKey(
        subjectKey: 'math',
        tagPaths: <String>['数学/函数'],
        capabilityCodes: <String>['A2', 'A7'],
      );
      final List<String> second = reviewDeckKey(
        subjectKey: 'math',
        tagPaths: <String>['数学/函数'],
        capabilityCodes: <String>['A2', 'A7'],
      );
      expect(first, second);
    });

    test('没有有效标签返回空列表', () {
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['', '   ', '///'],
          capabilityCodes: <String>['A3'],
        ),
        isEmpty,
      );
    });

    test('没有有效能力返回空列表', () {
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['物理/力学'],
          capabilityCodes: <String>['A0', 'A11', 'a', '', ' A '],
        ),
        isEmpty,
      );
    });

    test('学科为空返回空列表', () {
      for (final String subject in <String>['', '   ', '\t']) {
        expect(
          reviewDeckKey(
            subjectKey: subject,
            tagPaths: <String>['物理/力学'],
            capabilityCodes: <String>['A3'],
          ),
          isEmpty,
          reason: subject,
        );
      }
    });

    test('学科含分隔符返回空列表', () {
      expect(
        reviewDeckKey(
          subjectKey: 'ph|ysics',
          tagPaths: <String>['物理/力学'],
          capabilityCodes: <String>['A3'],
        ),
        isEmpty,
      );
    });

    test('标签段含分隔符整条丢弃', () {
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['物理/力学|x', '物理/运动学'],
          capabilityCodes: <String>['A3'],
        ),
        <String>['review_deck|physics|A3|物理/运动学'],
      );
      expect(
        reviewDeckKey(
          subjectKey: 'physics',
          tagPaths: <String>['物理/力学|x'],
          capabilityCodes: <String>['A3'],
        ),
        isEmpty,
      );
    });

    test('返回不可变列表', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/力学'],
        capabilityCodes: <String>['A3'],
      );
      expect(() => keys.add('x'), throwsUnsupportedError);
      expect(() => keys.clear(), throwsUnsupportedError);
    });
  });

  group('parseReviewDeckKey 解析', () {
    test('生成的键可反向解析', () {
      final List<String> keys = reviewDeckKey(
        subjectKey: 'physics',
        tagPaths: <String>['物理/高中物理/力学', '物理/运动学'],
        capabilityCodes: <String>['A3', 'A10'],
      );
      for (final String key in keys) {
        final ReviewDeckKey? parsed = parseReviewDeckKey(key);
        expect(parsed, isNotNull, reason: key);
        expect(parsed!.toDeckKeyString(), key);
        expect(isReviewDeckKey(key), isTrue);
      }
    });

    test('字段回读：学科、能力、标签路径分段', () {
      final ReviewDeckKey? parsed = parseReviewDeckKey(_sample);
      expect(parsed, isNotNull);
      expect(parsed!.subjectKey, 'physics');
      expect(parsed.capabilityCode, 'A3');
      expect(parsed.tagPath, '物理/高中物理/力学');
      expect(parsed.tagSegments, <String>['物理', '高中物理', '力学']);
      expect(parsed.capabilityIndex, 3);
      expect(parsed.isKnownCapability, isTrue);
    });

    test('A10 的序号是 10 而不是字符串顺序', () {
      final ReviewDeckKey? parsed =
          parseReviewDeckKey('review_deck|math|A10|数学/函数');
      expect(parsed, isNotNull);
      expect(parsed!.capabilityIndex, 10);
      expect(parsed.isKnownCapability, isTrue);
    });

    test('容忍最外层空白', () {
      final ReviewDeckKey? parsed = parseReviewDeckKey('  $_sample\t');
      expect(parsed, isNotNull);
      expect(parsed!.subjectKey, 'physics');
      expect(parsed.tagPath, '物理/高中物理/力学');
    });

    test('单段标签路径', () {
      final ReviewDeckKey? parsed =
          parseReviewDeckKey('review_deck|physics|A1|力学');
      expect(parsed, isNotNull);
      expect(parsed!.tagSegments, <String>['力学']);
    });

    test('脏数据返回 null 且不抛异常', () {
      final List<String> badInputs = <String>[
        '',
        '   ',
        'review_deck|physics|A3',
        'review_deck|physics|A3|物理/力学|extra',
        'deck|physics|A3|物理/力学',
        'REVIEW_DECK|physics|A3|物理/力学',
        'review_deck||A3|物理/力学',
        'review_deck|physics||物理/力学',
        'review_deck|physics|A11|物理/力学',
        'review_deck|physics|a3|物理/力学',
        'review_deck|physics|A 3|物理/力学',
        'review_deck|physics|A3|',
        'review_deck|physics|A3|物理//力学',
        'review_deck|physics|A3|/物理',
        'review_deck|physics|A3|物理/力学/',
        'review_deck|physics|A3| 物理/力学',
        'review_deck|physics|A3|物理 /力学',
        'review_deck| physics|A3|物理/力学',
        'review_deck|physics |A3|物理/力学',
        'review_deck|ph\nysics|A3|物理/力学',
        'review_deck|physics|A3|物理/\n力学',
        '|||',
        '   |   |   |   ',
      ];
      for (final String bad in badInputs) {
        expect(
          () => parseReviewDeckKey(bad),
          returnsNormally,
          reason: bad,
        );
        expect(parseReviewDeckKey(bad), isNull, reason: bad);
        expect(isReviewDeckKey(bad), isFalse, reason: bad);
      }
    });

    test('构造函数不校验能力编号，由只读判断兜底', () {
      const ReviewDeckKey key = ReviewDeckKey(
        subjectKey: 'physics',
        capabilityCode: 'A99',
        tagPath: '物理/力学',
      );
      expect(key.isKnownCapability, isFalse);
      expect(key.capabilityIndex, 0);
      expect(parseReviewDeckKey(key.toDeckKeyString()), isNull);
    });
  });

  group('卡组键排序', () {
    test('能力按编号比较：A2 小于 A10', () {
      const String a2 = 'review_deck|physics|A2|物理/力学';
      const String a10 = 'review_deck|physics|A10|物理/力学';
      expect(compareReviewDeckKeys(a2, a10), lessThan(0));
      expect(compareReviewDeckKeys(a10, a2), greaterThan(0));
    });

    test('学科先比较', () {
      const String math = 'review_deck|math|A10|数学/函数';
      const String physics = 'review_deck|physics|A1|物理/力学';
      expect(compareReviewDeckKeys(math, physics), lessThan(0));
      expect(compareReviewDeckKeys(physics, math), greaterThan(0));
    });

    test('同学科同能力按标签路径比较', () {
      const String mechanics = 'review_deck|physics|A3|物理/力学';
      const String kinematics = 'review_deck|physics|A3|物理/运动学';
      expect(compareReviewDeckKeys(mechanics, kinematics), lessThan(0));
    });

    test('相同键比较为 0', () {
      expect(compareReviewDeckKeys(_sample, _sample), 0);
    });

    test('非法键排在合法键之后', () {
      expect(compareReviewDeckKeys(_junk, _sample), greaterThan(0));
      expect(compareReviewDeckKeys(_sample, _junk), lessThan(0));
    });

    test('两条都非法时按原文比较', () {
      expect(compareReviewDeckKeys('zzz', 'aaa'), greaterThan(0));
      expect(compareReviewDeckKeys('aaa', 'zzz'), lessThan(0));
      expect(compareReviewDeckKeys('aaa', 'aaa'), 0);
    });

    test('sortedReviewDeckKeys 去重并排序', () {
      const String a2 = 'review_deck|physics|A2|物理/力学';
      const String a10 = 'review_deck|physics|A10|物理/力学';
      final List<String> sorted = sortedReviewDeckKeys(<String>[
        a10,
        _junk,
        a2,
        a2,
      ]);
      expect(sorted, <String>[a2, a10, _junk]);
      expect(() => sorted.add('x'), throwsUnsupportedError);
    });

    test('排序结果与输入顺序无关', () {
      const String a2 = 'review_deck|physics|A2|物理/力学';
      const String a10 = 'review_deck|physics|A10|物理/力学';
      expect(
        sortedReviewDeckKeys(<String>[_junk, a10, a2]),
        sortedReviewDeckKeys(<String>[a2, _junk, a10]),
      );
    });
  });

  group('常量与值对象', () {
    test('前缀与分隔符', () {
      expect(kReviewDeckKeyPrefix, 'review_deck');
      expect(kReviewDeckKeySeparator, '|');
      expect(
        '$kReviewDeckKeyPrefix$kReviewDeckKeySeparator'
            'physics$kReviewDeckKeySeparator'
            'A3$kReviewDeckKeySeparator'
            '物理/力学',
        'review_deck|physics|A3|物理/力学',
      );
    });

    test('能力编号表恰好是 A1–A10', () {
      expect(kReviewDeckCapabilityCodes, hasLength(10));
      expect(kReviewDeckCapabilityCodes.first, 'A1');
      expect(kReviewDeckCapabilityCodes.last, 'A10');
      for (final String code in kReviewDeckCapabilityCodes) {
        expect(RegExp(r'^A([1-9]|10)$').hasMatch(code), isTrue, reason: code);
      }
      expect(kReviewDeckCapabilityCodes.toSet(), hasLength(10));
    });

    test('ReviewDeckKey 值语义', () {
      const ReviewDeckKey a = ReviewDeckKey(
        subjectKey: 'physics',
        capabilityCode: 'A3',
        tagPath: '物理/力学',
      );
      const ReviewDeckKey b = ReviewDeckKey(
        subjectKey: 'physics',
        capabilityCode: 'A3',
        tagPath: '物理/力学',
      );
      const ReviewDeckKey c = ReviewDeckKey(
        subjectKey: 'math',
        capabilityCode: 'A3',
        tagPath: '数学/函数',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('physics'));
      expect(a.toString(), contains('A3'));
    });
  });
}
