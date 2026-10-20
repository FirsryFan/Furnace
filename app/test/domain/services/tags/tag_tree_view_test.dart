import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';
import 'package:furnace/domain/services/tags/tag_tree_view.dart';

TagTreeViewTag tag(
  String id, {
  String? parentId,
  String? name,
  String? path,
  DateTime? createdAt,
  String? description,
}) =>
    TagTreeViewTag(
      id: id,
      parentId: parentId,
      name: name ?? id,
      path: path,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      description: description,
    );

List<String> idsOf(List<TagTreeViewNode> nodes) => [
      for (final node in nodes) node.tagId,
    ];

List<String> preorderIds(TagTreeView view) => idsOf(view.preorder);

TagTreeViewNode nodeOf(TagTreeView view, String id) => view.byId[id]!;

List<String> childIdsOf(TagTreeView view, String id) =>
    idsOf(nodeOf(view, id).children);

void main() {
  group('基础装配', () {
    test('空输入：没有根、总数 0、诊断为空', () {
      final view = buildTagTreeView(tags: const <TagTreeViewTag>[]);
      expect(view.isEmpty, isTrue);
      expect(view.roots, isEmpty);
      expect(view.totalCount, 0);
      expect(view.preorder, isEmpty);
      expect(view.orphanIds, isEmpty);
      expect(view.cycleIds, isEmpty);
      expect(view.byId, isEmpty);
    });

    test('单节点：根、深度 0、path 就是自身 name', () {
      final view = buildTagTreeView(tags: [tag('a', name: '文化课')]);
      expect(view.isEmpty, isFalse);
      expect(view.totalCount, 1);
      expect(idsOf(view.roots), ['a']);
      final node = nodeOf(view, 'a');
      expect(node.parentId, isNull);
      expect(node.path, '文化课');
      expect(node.depth, 0);
      expect(node.hasChildren, isFalse);
      expect(node.childCount, 0);
      expect(preorderIds(view), ['a']);
    });

    test('两层：子节点路径用父 name 拼、深度 1', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: '文化课'),
        tag('b', parentId: 'a', name: '语文'),
      ]);
      expect(idsOf(view.roots), ['a']);
      final root = nodeOf(view, 'a');
      expect(root.hasChildren, isTrue);
      expect(root.childCount, 1);
      final child = nodeOf(view, 'b');
      expect(child.path, '文化课/语文');
      expect(child.depth, 1);
      expect(child.parentId, 'a');
      expect(preorderIds(view), ['a', 'b']);
    });

    test('三层：path 逐段拼接、深度递增', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: '文化课'),
        tag('b', parentId: 'a', name: '语文'),
        tag('c', parentId: 'b', name: '作文'),
      ]);
      expect(nodeOf(view, 'c').path, '文化课/语文/作文');
      expect(nodeOf(view, 'c').depth, 2);
      expect(preorderIds(view), ['a', 'b', 'c']);
    });

    test('输入顺序无关：打乱输入装配结果一致', () {
      final forward = buildTagTreeView(tags: [
        tag('a', name: '文化课'),
        tag('b', parentId: 'a', name: '语文'),
        tag('c', parentId: 'a', name: '数学'),
      ]);
      final shuffled = buildTagTreeView(tags: [
        tag('c', parentId: 'a', name: '数学'),
        tag('a', name: '文化课'),
        tag('b', parentId: 'a', name: '语文'),
      ]);
      expect(preorderIds(shuffled), preorderIds(forward));
      expect(idsOf(shuffled.roots), idsOf(forward.roots));
      expect(nodeOf(shuffled, 'c').path, nodeOf(forward, 'c').path);
    });

    test('空白 parentId 当根，不进 orphanIds', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: '   ', name: 'A'),
        tag('b', name: 'B'),
      ]);
      expect(idsOf(view.roots), ['a', 'b']);
      expect(view.orphanIds, isEmpty);
    });

    test('空 id 的输入行被跳过，其子节点成为孤儿根', () {
      final view = buildTagTreeView(tags: [
        tag('', name: '坏行'),
        tag('b', parentId: 'ghost', name: 'B'),
      ]);
      expect(view.totalCount, 1);
      expect(idsOf(view.roots), ['b']);
      expect(view.orphanIds, ['b']);
      expect(view.byId.containsKey(''), isFalse);
    });

    test('同 id 重复时保留第一条', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: '第一条'),
        tag('a', name: '第二条'),
      ]);
      expect(view.totalCount, 1);
      expect(nodeOf(view, 'a').name, '第一条');
    });
  });

  group('三口径排序', () {
    test('alphabetical：同层按 name 升序', () {
      final view = buildTagTreeView(tags: [
        tag('root', name: 'R'),
        tag('c', parentId: 'root', name: 'CCC'),
        tag('a', parentId: 'root', name: 'AAA'),
        tag('b', parentId: 'root', name: 'BBB'),
      ]);
      expect(childIdsOf(view, 'root'), ['a', 'b', 'c']);
    });

    test('alphabetical 全序：同名时按 createdAt 升序决胜', () {
      final view = buildTagTreeView(tags: [
        tag('root', name: 'R'),
        tag('c1',
            parentId: 'root', name: '同名', createdAt: DateTime.utc(2026, 1, 3)),
        tag('c2',
            parentId: 'root', name: '同名', createdAt: DateTime.utc(2026, 1, 1)),
        tag('c3',
            parentId: 'root', name: '同名', createdAt: DateTime.utc(2026, 1, 2)),
      ]);
      expect(childIdsOf(view, 'root'), ['c2', 'c3', 'c1']);
    });

    test('alphabetical：空 name 参与排序，path 为空字符串', () {
      final view = buildTagTreeView(tags: [
        tag('b', name: 'B'),
        tag('empty', name: ''),
      ]);
      expect(idsOf(view.roots), ['empty', 'b']);
      expect(nodeOf(view, 'empty').path, '');
    });

    test('byObjectCount：直接计数降序', () {
      final view = buildTagTreeView(
        tags: [
          tag('root', name: 'R'),
          tag('low', parentId: 'root', name: 'A'),
          tag('high', parentId: 'root', name: 'B'),
          tag('mid', parentId: 'root', name: 'C'),
        ],
        objectCounts: {'low': 1, 'high': 9, 'mid': 5},
        mode: TagTreeSortMode.byObjectCount,
      );
      expect(childIdsOf(view, 'root'), ['high', 'mid', 'low']);
    });

    test('byObjectCount：负数按 0 参与，不因负值沉底', () {
      final view = buildTagTreeView(
        tags: [
          tag('root', name: 'R'),
          tag('neg', parentId: 'root', name: 'alpha'),
          tag('zero', parentId: 'root', name: 'beta'),
          tag('pos', parentId: 'root', name: 'gamma'),
        ],
        objectCounts: {'neg': -5, 'zero': 0, 'pos': 3},
        mode: TagTreeSortMode.byObjectCount,
      );
      expect(childIdsOf(view, 'root'), ['pos', 'neg', 'zero']);
      expect(nodeOf(view, 'neg').objectCount, -5);
    });

    test('byObjectCount：计数并列时按 name 升序决胜', () {
      final view = buildTagTreeView(
        tags: [
          tag('root', name: 'R'),
          tag('b', parentId: 'root', name: 'Beta'),
          tag('a', parentId: 'root', name: 'Alpha'),
        ],
        objectCounts: {'a': 2, 'b': 2},
        mode: TagTreeSortMode.byObjectCount,
      );
      expect(childIdsOf(view, 'root'), ['a', 'b']);
    });

    test('byCreatedAt：创建时间升序，先加的在前', () {
      final view = buildTagTreeView(
        tags: [
          tag('root', name: 'R'),
          tag('late',
              parentId: 'root', name: 'A', createdAt: DateTime.utc(2026, 5, 1)),
          tag('early',
              parentId: 'root', name: 'B', createdAt: DateTime.utc(2026, 1, 1)),
          tag('mid',
              parentId: 'root', name: 'C', createdAt: DateTime.utc(2026, 3, 1)),
        ],
        mode: TagTreeSortMode.byCreatedAt,
      );
      expect(childIdsOf(view, 'root'), ['early', 'mid', 'late']);
    });

    test('byCreatedAt：时间并列时按 name 升序决胜', () {
      final view = buildTagTreeView(
        tags: [
          tag('root', name: 'R'),
          tag('b', parentId: 'root', name: 'Beta'),
          tag('a', parentId: 'root', name: 'Alpha'),
        ],
        mode: TagTreeSortMode.byCreatedAt,
      );
      expect(childIdsOf(view, 'root'), ['a', 'b']);
    });

    test('多个根同样按口径排序', () {
      final view = buildTagTreeView(
        tags: [
          tag('r1', name: 'Beta', createdAt: DateTime.utc(2026, 2, 1)),
          tag('r2', name: 'Alpha', createdAt: DateTime.utc(2026, 1, 1)),
        ],
        mode: TagTreeSortMode.byCreatedAt,
      );
      expect(idsOf(view.roots), ['r2', 'r1']);
    });

    test('countDescendants=true 时按子树累计排序（顺序可与直接计数相反）', () {
      final tags = [
        tag('a', name: 'Alpha'),
        tag('a-child', parentId: 'a', name: 'A'),
        tag('b', name: 'Beta'),
      ];
      final direct = buildTagTreeView(
        tags: tags,
        objectCounts: {'a': 1, 'a-child': 4, 'b': 4},
        mode: TagTreeSortMode.byObjectCount,
      );
      expect(idsOf(direct.roots), ['b', 'a']);

      final subtree = buildTagTreeView(
        tags: tags,
        objectCounts: {'a': 1, 'a-child': 4, 'b': 4},
        mode: TagTreeSortMode.byObjectCount,
        countDescendants: true,
      );
      expect(idsOf(subtree.roots), ['a', 'b']);
    });
  });

  group('孤儿', () {
    test('父不在输入：当根并记入 orphanIds', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'missing', name: 'A'),
      ]);
      expect(idsOf(view.roots), ['a']);
      expect(view.orphanIds, ['a']);
      expect(nodeOf(view, 'a').parentId, isNull);
      expect(nodeOf(view, 'a').depth, 0);
    });

    test('多个孤儿按 id 升序记录', () {
      final view = buildTagTreeView(tags: [
        tag('orphan2', parentId: 'm2', name: 'B'),
        tag('orphan1', parentId: 'm1', name: 'A'),
      ]);
      expect(view.orphanIds, ['orphan1', 'orphan2']);
      expect(idsOf(view.roots), ['orphan1', 'orphan2']);
    });

    test('孤儿保留自己的子树', () {
      final view = buildTagTreeView(tags: [
        tag('orphan', parentId: 'missing', name: 'O'),
        tag('child', parentId: 'orphan', name: 'C'),
        tag('grandchild', parentId: 'child', name: 'G'),
      ]);
      expect(idsOf(view.roots), ['orphan']);
      expect(childIdsOf(view, 'orphan'), ['child']);
      expect(childIdsOf(view, 'child'), ['grandchild']);
      expect(nodeOf(view, 'grandchild').path, 'O/C/G');
      expect(preorderIds(view), ['orphan', 'child', 'grandchild']);
    });

    test('孤儿 path 从自身 name 开始（不拼缺失父）', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'missing', name: '孤儿'),
        tag('b', parentId: 'a', name: '孩子'),
      ]);
      expect(nodeOf(view, 'a').path, '孤儿');
      expect(nodeOf(view, 'b').path, '孤儿/孩子');
    });

    test('正常输入 orphanIds 为空', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
      ]);
      expect(view.orphanIds, isEmpty);
    });
  });

  group('环', () {
    test('自环：最小 id 断父边当根并记 cycleIds', () {
      final view = buildTagTreeView(tags: [
        tag('self', parentId: 'self', name: '自环'),
      ]);
      expect(view.cycleIds, ['self']);
      expect(idsOf(view.roots), ['self']);
      expect(nodeOf(view, 'self').parentId, isNull);
      expect(nodeOf(view, 'self').depth, 0);
    });

    test('双节点环：断最小 id 的父边', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'b', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
      ]);
      expect(view.cycleIds, ['a', 'b']);
      expect(idsOf(view.roots), ['a']);
      expect(childIdsOf(view, 'a'), ['b']);
      expect(nodeOf(view, 'b').depth, 1);
      expect(nodeOf(view, 'b').path, 'A/B');
    });

    test('双节点环：输入顺序不影响断点（最小 id 仍当根）', () {
      final view = buildTagTreeView(tags: [
        tag('b', parentId: 'a', name: 'B'),
        tag('a', parentId: 'b', name: 'A'),
      ]);
      expect(view.cycleIds, ['a', 'b']);
      expect(idsOf(view.roots), ['a']);
      expect(childIdsOf(view, 'a'), ['b']);
    });

    test('长环 a→b→c→a：断 a 的父边后成链', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'c', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
        tag('c', parentId: 'b', name: 'C'),
      ]);
      expect(view.cycleIds, ['a', 'b', 'c']);
      expect(idsOf(view.roots), ['a']);
      expect(preorderIds(view), ['a', 'b', 'c']);
      expect(nodeOf(view, 'c').depth, 2);
      expect(nodeOf(view, 'c').path, 'A/B/C');
    });

    test('环外子树挂到环上节点后正常展开', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'b', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
        tag('d', parentId: 'b', name: 'D'),
      ]);
      expect(idsOf(view.roots), ['a']);
      expect(childIdsOf(view, 'b'), ['d']);
      expect(nodeOf(view, 'd').depth, 2);
      expect(nodeOf(view, 'd').path, 'A/B/D');
    });

    test('两个独立环分别断开，cycleIds 按 id 升序', () {
      final view = buildTagTreeView(tags: [
        tag('y', parentId: 'x', name: 'Y'),
        tag('x', parentId: 'y', name: 'X'),
        tag('b', parentId: 'a', name: 'B'),
        tag('a', parentId: 'b', name: 'A'),
      ]);
      expect(view.cycleIds, ['a', 'b', 'x', 'y']);
      expect(idsOf(view.roots), ['a', 'x']);
      expect(childIdsOf(view, 'a'), ['b']);
      expect(childIdsOf(view, 'x'), ['y']);
    });

    test('断环后 path/depth 用环上最小 id 当根的链', () {
      final view = buildTagTreeView(tags: [
        tag('a', parentId: 'c', name: '一级'),
        tag('b', parentId: 'a', name: '二级'),
        tag('c', parentId: 'b', name: '三级'),
      ]);
      expect(nodeOf(view, 'a').path, '一级');
      expect(nodeOf(view, 'b').path, '一级/二级');
      expect(nodeOf(view, 'c').path, '一级/二级/三级');
      expect(nodeOf(view, 'a').depth, 0);
      expect(nodeOf(view, 'b').depth, 1);
      expect(nodeOf(view, 'c').depth, 2);
    });

    test('countDescendants 沿断环后的树边累加（不重复计断开的边）', () {
      final view = buildTagTreeView(
        tags: [
          tag('a', parentId: 'b', name: 'A'),
          tag('b', parentId: 'a', name: 'B'),
        ],
        objectCounts: {'a': 1, 'b': 2},
        countDescendants: true,
      );
      expect(nodeOf(view, 'a').objectCount, 3);
      expect(nodeOf(view, 'b').objectCount, 2);
    });
  });

  group('countDescendants', () {
    test('默认 false：节点计数就是直接计数', () {
      final view = buildTagTreeView(
        tags: [
          tag('a', name: 'A'),
          tag('b', parentId: 'a', name: 'B'),
        ],
        objectCounts: {'a': 1, 'b': 4},
      );
      expect(nodeOf(view, 'a').objectCount, 1);
      expect(nodeOf(view, 'b').objectCount, 4);
    });

    test('objectCounts 缺失时按 0', () {
      final view = buildTagTreeView(
        tags: [
          tag('a', name: 'A'),
          tag('b', parentId: 'a', name: 'B'),
        ],
        countDescendants: true,
      );
      expect(nodeOf(view, 'a').objectCount, 0);
      expect(nodeOf(view, 'b').objectCount, 0);
    });

    test('true：三层累加 = 自身 + 全部子孙', () {
      final view = buildTagTreeView(
        tags: [
          tag('a', name: 'A'),
          tag('b', parentId: 'a', name: 'B'),
          tag('c', parentId: 'b', name: 'C'),
          tag('d', parentId: 'b', name: 'D'),
        ],
        objectCounts: {'a': 1, 'b': 2, 'c': 3, 'd': 4},
        countDescendants: true,
      );
      expect(nodeOf(view, 'a').objectCount, 10);
      expect(nodeOf(view, 'b').objectCount, 9);
      expect(nodeOf(view, 'c').objectCount, 3);
      expect(nodeOf(view, 'd').objectCount, 4);
    });

    test('true：单节点计数等于直接计数', () {
      final view = buildTagTreeView(
        tags: [tag('a', name: 'A')],
        objectCounts: {'a': 7},
        countDescendants: true,
      );
      expect(nodeOf(view, 'a').objectCount, 7);
    });

    test('负数计数原样累加（不 clamp）', () {
      final view = buildTagTreeView(
        tags: [
          tag('a', name: 'A'),
          tag('b', parentId: 'a', name: 'B'),
        ],
        objectCounts: {'a': -2, 'b': -3},
        countDescendants: true,
      );
      expect(nodeOf(view, 'a').objectCount, -5);
      expect(nodeOf(view, 'b').objectCount, -3);
    });

    test('objectCounts 里未知 id 被忽略', () {
      final view = buildTagTreeView(
        tags: [tag('a', name: 'A')],
        objectCounts: {'ghost': 99, 'a': 2},
        countDescendants: true,
      );
      expect(view.totalCount, 1);
      expect(view.byId.containsKey('ghost'), isFalse);
      expect(nodeOf(view, 'a').objectCount, 2);
    });

    test('true/false 只改计数，不改树结构与顺序', () {
      final tags = [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
        tag('c', parentId: 'a', name: 'C'),
      ];
      final direct = buildTagTreeView(tags: tags, objectCounts: {'b': 5});
      final subtree = buildTagTreeView(
        tags: tags,
        objectCounts: {'b': 5},
        countDescendants: true,
      );
      expect(preorderIds(subtree), preorderIds(direct));
      expect(childIdsOf(subtree, 'a'), childIdsOf(direct, 'a'));
      expect(nodeOf(subtree, 'a').objectCount, 5);
      expect(nodeOf(direct, 'a').objectCount, 0);
    });
  });

  group('不可变与确定性', () {
    test('不修改入参 tags 列表与 objectCounts 映射', () {
      final tags = [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
      ];
      final counts = <String, int>{'a': 1, 'b': 2};
      final tagsCopy = List<TagTreeViewTag>.of(tags);
      final countsCopy = Map<String, int>.of(counts);

      buildTagTreeView(
        tags: tags,
        objectCounts: counts,
        mode: TagTreeSortMode.byObjectCount,
        countDescendants: true,
      );
      buildTagTreeView(tags: tags, objectCounts: counts);

      expect(tags, tagsCopy);
      expect(counts, countsCopy);
    });

    test('返回的列表与映射都不可变', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
      ]);
      expect(() => view.orphanIds.add('x'), throwsUnsupportedError);
      expect(() => view.cycleIds.add('x'), throwsUnsupportedError);
      expect(() => nodeOf(view, 'a').children.clear(), throwsUnsupportedError);
      expect(() => view.byId.clear(), throwsUnsupportedError);
    });

    test('同输入同输出：两次装配结果一致', () {
      final tags = [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
        tag('c', parentId: 'missing', name: 'C'),
      ];
      final first = buildTagTreeView(
        tags: tags,
        objectCounts: {'a': 1},
        mode: TagTreeSortMode.byObjectCount,
        countDescendants: true,
      );
      final second = buildTagTreeView(
        tags: tags,
        objectCounts: {'a': 1},
        mode: TagTreeSortMode.byObjectCount,
        countDescendants: true,
      );
      expect(preorderIds(second), preorderIds(first));
      expect(second.orphanIds, first.orphanIds);
      expect(second.cycleIds, first.cycleIds);
      expect(
        [for (final node in second.preorder) node.path],
        [for (final node in first.preorder) node.path],
      );
    });

    test('byId 与 preorder 一致，父一定排在子之前', () {
      final view = buildTagTreeView(tags: [
        tag('a', name: 'A'),
        tag('b', parentId: 'a', name: 'B'),
        tag('c', parentId: 'b', name: 'C'),
        tag('d', parentId: 'a', name: 'D'),
      ]);
      for (final node in view.preorder) {
        expect(identical(view.byId[node.tagId], node), isTrue);
      }
      final index = <String, int>{
        for (var i = 0; i < view.preorder.length; i++)
          view.preorder[i].tagId: i,
      };
      for (final node in view.preorder) {
        final parentId = node.parentId;
        if (parentId == null) continue;
        expect(index[parentId]! < index[node.tagId]!, isTrue);
      }
    });
  });

  group('排序偏好编解码', () {
    test('toStorage 输出稳定 code', () {
      expect(
        tagTreeSortModeToStorage(TagTreeSortMode.alphabetical),
        'alphabetical',
      );
      expect(
        tagTreeSortModeToStorage(TagTreeSortMode.byObjectCount),
        'object_count',
      );
      expect(
        tagTreeSortModeToStorage(TagTreeSortMode.byCreatedAt),
        'created_at',
      );
    });

    test('三种口径 roundtrip 不变', () {
      for (final mode in TagTreeSortMode.values) {
        expect(
            tagTreeSortModeFromStorage(tagTreeSortModeToStorage(mode)), mode);
      }
    });

    test('null 还原为字典序', () {
      expect(tagTreeSortModeFromStorage(null), TagTreeSortMode.alphabetical);
    });

    test('空串 / 全空白还原为字典序', () {
      expect(tagTreeSortModeFromStorage(''), TagTreeSortMode.alphabetical);
      expect(tagTreeSortModeFromStorage('   '), TagTreeSortMode.alphabetical);
    });

    test('认不出的脏值兜底为字典序', () {
      expect(
          tagTreeSortModeFromStorage('pinyin'), TagTreeSortMode.alphabetical);
      expect(tagTreeSortModeFromStorage('object-count'),
          TagTreeSortMode.alphabetical);
      expect(tagTreeSortModeFromStorage('1'), TagTreeSortMode.alphabetical);
    });

    test('容忍大小写与两端空白', () {
      expect(
        tagTreeSortModeFromStorage(' OBJECT_COUNT '),
        TagTreeSortMode.byObjectCount,
      );
      expect(
        tagTreeSortModeFromStorage('Created_At'),
        TagTreeSortMode.byCreatedAt,
      );
      expect(
        tagTreeSortModeFromStorage('ALPHABETICAL'),
        TagTreeSortMode.alphabetical,
      );
    });
  });
}
