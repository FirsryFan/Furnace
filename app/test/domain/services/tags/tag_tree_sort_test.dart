import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';

DateTime _t(int seconds) => DateTime.utc(2026, 1, 1, 0, 0, seconds);

TagTreeSortEntry _item(
  String id, {
  String? name,
  DateTime? createdAt,
  int objectCount = 0,
}) =>
    TagTreeSortEntry(
      id: id,
      name: name ?? id,
      createdAt: createdAt ?? _t(0),
      objectCount: objectCount,
    );

List<String> _idsOf(Iterable<TagTreeSortEntry> entries) => [
      for (final e in entries) e.id,
    ];

void main() {
  group('TagTreeSortMode：code / labelZh / byCode', () {
    test('三种口径的枚举顺序、code 与中文名', () {
      expect(
        TagTreeSortMode.values.map((m) => m.code).toList(),
        const ['alphabetical', 'object_count', 'created_at'],
      );
      expect(
        TagTreeSortMode.values.map((m) => m.labelZh).toList(),
        const ['字典序', '按内容量', '按添加时间'],
      );
    });

    test('byCode 精确匹配三种 code', () {
      expect(
          TagTreeSortMode.byCode('alphabetical'), TagTreeSortMode.alphabetical);
      expect(TagTreeSortMode.byCode('object_count'),
          TagTreeSortMode.byObjectCount);
      expect(TagTreeSortMode.byCode('created_at'), TagTreeSortMode.byCreatedAt);
    });

    test('byCode 大小写不敏感', () {
      expect(
          TagTreeSortMode.byCode('Alphabetical'), TagTreeSortMode.alphabetical);
      expect(TagTreeSortMode.byCode('OBJECT_COUNT'),
          TagTreeSortMode.byObjectCount);
      expect(TagTreeSortMode.byCode('Created_At'), TagTreeSortMode.byCreatedAt);
    });

    test('byCode 两端空白先 trim', () {
      expect(TagTreeSortMode.byCode('  created_at  '),
          TagTreeSortMode.byCreatedAt);
      expect(TagTreeSortMode.byCode('\talphabetical\n'),
          TagTreeSortMode.alphabetical);
    });

    test('byCode 认不出时返回 null', () {
      expect(TagTreeSortMode.byCode('name'), isNull);
      expect(TagTreeSortMode.byCode('count'), isNull);
      expect(TagTreeSortMode.byCode('objectCount'), isNull);
      expect(TagTreeSortMode.byCode('sorted_by_time'), isNull);
    });

    test('byCode 空串 / 纯空白返回 null', () {
      expect(TagTreeSortMode.byCode(''), isNull);
      expect(TagTreeSortMode.byCode('   '), isNull);
    });

    test('byCode 不认中文名', () {
      for (final mode in TagTreeSortMode.values) {
        expect(TagTreeSortMode.byCode(mode.labelZh), isNull);
      }
    });

    test('tagTreeSortModeNameZh 返回中文名（签名可空）', () {
      final String? label =
          tagTreeSortModeNameZh(TagTreeSortMode.byObjectCount);
      expect(label, '按内容量');
      expect(tagTreeSortModeNameZh(TagTreeSortMode.alphabetical), '字典序');
      expect(tagTreeSortModeNameZh(TagTreeSortMode.byCreatedAt), '按添加时间');
    });
  });

  group('alphabetical：字典序（与 tag_tree_page.dart:56 同口径）', () {
    test('英文名按 compareTo 升序', () {
      final input = [
        _item('banana', name: 'banana'),
        _item('apple', name: 'apple'),
        _item('cherry', name: 'cherry'),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['apple', 'banana', 'cherry']);
    });

    test('中文名按 String.compareTo（UTF-16 代码单元）升序', () {
      final input = [
        _item('wang', name: '王'),
        _item('zhang', name: '张'),
        _item('li', name: '李'),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['zhang', 'li', 'wang']);
    });

    test('大小写与数字按代码单元排（不做大小写折叠）', () {
      final input = [
        _item('n-a', name: 'a'),
        _item('n-B', name: 'B'),
        _item('n-1', name: '1'),
        _item('n-b', name: 'b'),
        _item('n-2', name: '2'),
        _item('n-A', name: 'A'),
        _item('n-10', name: '10'),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const [
        'n-1',
        'n-10',
        'n-2',
        'n-A',
        'n-B',
        'n-a',
        'n-b',
      ]);
    });

    test('同名时 createdAt 升序决胜', () {
      final input = [
        _item('late', name: 'kp', createdAt: _t(2)),
        _item('early', name: 'kp', createdAt: _t(0)),
        _item('middle', name: 'kp', createdAt: _t(1)),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['early', 'middle', 'late']);
    });

    test('同名同创建时间时按 id 升序决胜', () {
      final input = [
        _item('b', name: 'kp', createdAt: _t(1)),
        _item('a', name: 'kp', createdAt: _t(1)),
        _item('c', name: 'kp', createdAt: _t(1)),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['a', 'b', 'c']);
    });

    test('空表返回空列表', () {
      final sorted = sortTagTreeSiblings(
        const <TagTreeSortEntry>[],
        TagTreeSortMode.alphabetical,
      );
      expect(sorted, isEmpty);
    });

    test('单项：顺序不变，但返回新列表', () {
      final only = _item('only', name: 'only');
      final sorted = sortTagTreeSiblings([only], TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['only']);
      expect(identical(sorted, <TagTreeSortEntry>[only]), isFalse);
    });
  });

  group('byObjectCount：内容量降序（负数当 0）', () {
    test('按内容量降序（多者在前）', () {
      final input = [
        _item('one', objectCount: 1),
        _item('three', objectCount: 3),
        _item('two', objectCount: 2),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['three', 'two', 'one']);
    });

    test('内容量相同按 name 升序决胜', () {
      final input = [
        _item('b', name: 'b', objectCount: 5),
        _item('a', name: 'a', objectCount: 5),
        _item('c', name: 'c', objectCount: 5),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['a', 'b', 'c']);
    });

    test('内容量与名称都相同按 id 升序决胜', () {
      final input = [
        _item('z', name: 'kp', objectCount: 5),
        _item('a', name: 'kp', objectCount: 5),
        _item('m', name: 'kp', objectCount: 5),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['a', 'm', 'z']);
    });

    test('负数当 0 参与比较（原始值保留）', () {
      final neg = _item('neg', name: 'b', objectCount: -5);
      final input = [
        neg,
        _item('zero', name: 'a'),
        _item('one', name: 'c', objectCount: 1)
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['one', 'zero', 'neg']);
      expect(neg.objectCount, -5);
      expect(neg.sortableObjectCount, 0);
    });

    test('全部为负数：都按 0 并列，再按 name 升序', () {
      final input = [
        _item('x-c', name: 'c', objectCount: -1),
        _item('x-a', name: 'a', objectCount: -9),
        _item('x-b', name: 'b', objectCount: -3),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['x-a', 'x-b', 'x-c']);
    });

    test('负数与 0 视为并列，按 name 决胜', () {
      final input = [
        _item('minus', name: 'b', objectCount: -7),
        _item('zero', name: 'a'),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byObjectCount);
      expect(_idsOf(sorted), const ['zero', 'minus']);
    });

    test('空表返回空列表', () {
      final sorted = sortTagTreeSiblings(
        const <TagTreeSortEntry>[],
        TagTreeSortMode.byObjectCount,
      );
      expect(sorted, isEmpty);
    });

    test('单项：顺序不变', () {
      final sorted = sortTagTreeSiblings(
        [_item('only', objectCount: -3)],
        TagTreeSortMode.byObjectCount,
      );
      expect(_idsOf(sorted), const ['only']);
    });
  });

  group('byCreatedAt：添加时间升序', () {
    test('按时间升序（先加的在前）', () {
      final input = [
        _item('t2', createdAt: _t(2)),
        _item('t0', createdAt: _t(0)),
        _item('t1', createdAt: _t(1)),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byCreatedAt);
      expect(_idsOf(sorted), const ['t0', 't1', 't2']);
    });

    test('时间相同按 name 升序决胜', () {
      final input = [
        _item('b', name: 'b', createdAt: _t(1)),
        _item('a', name: 'a', createdAt: _t(1)),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byCreatedAt);
      expect(_idsOf(sorted), const ['a', 'b']);
    });

    test('时间与名称都相同按 id 升序决胜', () {
      final input = [
        _item('z', name: 'kp', createdAt: _t(1)),
        _item('a', name: 'kp', createdAt: _t(1)),
      ];
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.byCreatedAt);
      expect(_idsOf(sorted), const ['a', 'z']);
    });

    test('不同时区写法但同一时刻视为并列（按时刻比较）', () {
      final offset = _item(
        'offset',
        name: 'b',
        createdAt: DateTime.parse('2026-01-01T08:00:00+08:00'),
      );
      final utc = _item('utc', name: 'a', createdAt: DateTime.utc(2026, 1, 1));
      final sorted =
          sortTagTreeSiblings([offset, utc], TagTreeSortMode.byCreatedAt);
      expect(_idsOf(sorted), const ['utc', 'offset']);
    });

    test('空表返回空列表', () {
      final sorted = sortTagTreeSiblings(
        const <TagTreeSortEntry>[],
        TagTreeSortMode.byCreatedAt,
      );
      expect(sorted, isEmpty);
    });

    test('单项：顺序不变', () {
      final sorted = sortTagTreeSiblings(
        [_item('only', createdAt: _t(3))],
        TagTreeSortMode.byCreatedAt,
      );
      expect(_idsOf(sorted), const ['only']);
    });
  });

  group('通用保证：入参不变 / 返回新列表 / 全序确定', () {
    final base = <TagTreeSortEntry>[
      _item('tag-b', name: 'beta', createdAt: _t(2), objectCount: 5),
      _item('tag-a', name: 'alpha', createdAt: _t(0), objectCount: 5),
      _item('tag-c', name: 'gamma', createdAt: _t(1)),
      _item('tag-d', name: 'beta', createdAt: _t(1), objectCount: 7),
      _item('tag-e', name: 'Alpha', createdAt: _t(0), objectCount: 7),
    ];

    test('不修改入参、返回新列表', () {
      final input = [
        _item('b', name: 'b'),
        _item('a', name: 'a'),
      ];
      final before = _idsOf(input);
      final sorted = sortTagTreeSiblings(input, TagTreeSortMode.alphabetical);
      expect(_idsOf(input), before);
      expect(identical(input, sorted), isFalse);
      expect(_idsOf(sorted), const ['a', 'b']);
    });

    test('入参是不可修改列表也能排，返回值可继续修改', () {
      final frozen = List<TagTreeSortEntry>.unmodifiable([
        _item('b', name: 'b'),
        _item('a', name: 'a'),
      ]);
      final sorted = sortTagTreeSiblings(frozen, TagTreeSortMode.alphabetical);
      expect(_idsOf(sorted), const ['a', 'b']);
      sorted.add(_item('c', name: 'c'));
      expect(sorted.length, 3);
      expect(frozen.length, 2);
    });

    test('alphabetical：任意输入顺序结果一致', () {
      final expected =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.alphabetical));
      expect(
          _idsOf(sortTagTreeSiblings(
              base.reversed.toList(), TagTreeSortMode.alphabetical)),
          expected);
      expect(
          _idsOf(sortTagTreeSiblings([...base.skip(2), ...base.take(2)],
              TagTreeSortMode.alphabetical)),
          expected);
    });

    test('byObjectCount：任意输入顺序结果一致', () {
      final expected =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.byObjectCount));
      expect(
          _idsOf(sortTagTreeSiblings(
              base.reversed.toList(), TagTreeSortMode.byObjectCount)),
          expected);
      expect(
          _idsOf(sortTagTreeSiblings([...base.skip(2), ...base.take(2)],
              TagTreeSortMode.byObjectCount)),
          expected);
    });

    test('byCreatedAt：任意输入顺序结果一致', () {
      final expected =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.byCreatedAt));
      expect(
          _idsOf(sortTagTreeSiblings(
              base.reversed.toList(), TagTreeSortMode.byCreatedAt)),
          expected);
      expect(
          _idsOf(sortTagTreeSiblings(
              [...base.skip(2), ...base.take(2)], TagTreeSortMode.byCreatedAt)),
          expected);
    });

    test('三种口径对同一组数据给出不同顺序', () {
      final alphabetical =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.alphabetical));
      final byCount =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.byObjectCount));
      final byCreatedAt =
          _idsOf(sortTagTreeSiblings(base, TagTreeSortMode.byCreatedAt));
      expect(alphabetical, const ['tag-e', 'tag-a', 'tag-d', 'tag-b', 'tag-c']);
      expect(byCount, const ['tag-e', 'tag-d', 'tag-a', 'tag-b', 'tag-c']);
      expect(byCreatedAt, const ['tag-e', 'tag-a', 'tag-d', 'tag-c', 'tag-b']);
    });

    test('排序幂等：再排一次顺序不变', () {
      for (final mode in TagTreeSortMode.values) {
        final once = sortTagTreeSiblings(base, mode);
        final twice = sortTagTreeSiblings(once, mode);
        expect(_idsOf(twice), _idsOf(once), reason: mode.code);
      }
    });

    test('空表在三种口径下都是空列表', () {
      for (final mode in TagTreeSortMode.values) {
        expect(sortTagTreeSiblings(const <TagTreeSortEntry>[], mode), isEmpty);
      }
    });

    test('toString 便于调试（含 id / 名称 / 创建时间 / 内容量）', () {
      final e = _item(
        'tag-1',
        name: '函数',
        createdAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
        objectCount: -2,
      );
      final text = e.toString();
      expect(text, contains('tag-1'));
      expect(text, contains('函数'));
      expect(text, contains('2026-02-03 04:05:06.000Z'));
      expect(text, contains('-2'));
    });
  });
}
