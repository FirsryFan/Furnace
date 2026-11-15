/// 标签图的可见性 / 搜索纯逻辑（tag_graph_query.dart）。
///
/// 钉住的口径：
///  * 搜索只做 name / path 的子串匹配（大小写不敏感、trim），不模糊匹配；
///  * 命中后要显示「命中节点 + 祖先路径 + 命中的整棵子树」；
///  * 折叠只藏后代，不藏节点自己；搜索模式忽略折叠；
///  * 顺序永远是树的前序，未知 id 不抛异常。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_graph_query.dart';
import 'package:furnace/domain/services/tags/tag_tree_view.dart';

TagTreeViewTag tag(String id, {String? parentId, String? name}) =>
    TagTreeViewTag(
      id: id,
      parentId: parentId,
      name: name ?? id,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// 树形：
///   other(f)
///   root(a) ├─ alpha(b) ├─ alpha-child(c)
///           │           └─ beta(d)
///           └─ sibling(e)
///
/// 字典序前序：f, a, b, c, d, e
TagTreeView fixture() => buildTagTreeView(
      tags: [
        tag('a', name: 'root'),
        tag('b', parentId: 'a', name: 'alpha'),
        tag('c', parentId: 'b', name: 'alpha-child'),
        tag('d', parentId: 'b', name: 'beta'),
        tag('e', parentId: 'a', name: 'sibling'),
        tag('f', name: 'other'),
      ],
    );

List<String> idsOf(List<TagTreeViewNode> nodes) =>
    [for (final node in nodes) node.tagId];

void main() {
  group('可见节点（折叠）', () {
    test('默认全展开：前序输出全部节点', () {
      final view = fixture();
      expect(idsOf(tagGraphVisibleNodes(view)), ['f', 'a', 'b', 'c', 'd', 'e']);
    });

    test('折叠根：只藏它的后代，根自己还在', () {
      final view = fixture();
      final visible = tagGraphVisibleNodes(view, collapsedIds: {'a'});
      expect(idsOf(visible), ['f', 'a']);
    });

    test('折叠中间层：父还在，兄弟不受影响', () {
      final view = fixture();
      final visible = tagGraphVisibleNodes(view, collapsedIds: {'b'});
      expect(idsOf(visible), ['f', 'a', 'b', 'e']);
    });

    test('折叠集合里的未知 id 被忽略', () {
      final view = fixture();
      final visible = tagGraphVisibleNodes(view, collapsedIds: {'nope'});
      expect(idsOf(visible), ['f', 'a', 'b', 'c', 'd', 'e']);
    });

    test('onlyIds：只保留集合内节点，并忽略折叠', () {
      final view = fixture();
      expect(
        idsOf(tagGraphVisibleNodes(
          view,
          collapsedIds: {'a'},
          onlyIds: {'a', 'c'},
        )),
        ['a', 'c'],
      );
      expect(
        idsOf(tagGraphVisibleNodes(view, onlyIds: {'f'})),
        ['f'],
      );
    });

    test('空树：可见节点为空', () {
      final view = buildTagTreeView(tags: const <TagTreeViewTag>[]);
      expect(tagGraphVisibleNodes(view), isEmpty);
      expect(tagGraphVisibleNodes(view, collapsedIds: {'a'}), isEmpty);
    });
  });

  group('搜索命中', () {
    test('空串 / 纯空白：不搜索，返回空列表', () {
      final view = fixture();
      expect(tagGraphSearchMatchIds(view, ''), isEmpty);
      expect(tagGraphSearchMatchIds(view, '   '), isEmpty);
    });

    test('按 name 匹配，大小写不敏感，前后空白忽略', () {
      final view = fixture();
      expect(tagGraphSearchMatchIds(view, 'BETA'), ['d']);
      expect(tagGraphSearchMatchIds(view, '  beta  '), ['d']);
    });

    test('按祖先拼出的 path 匹配：搜 alpha 会命中整条分支', () {
      final view = fixture();
      // b 的 name 命中；c/d 的 path 含 alpha。
      expect(tagGraphSearchMatchIds(view, 'alpha'), ['b', 'c', 'd']);
    });

    test('命中顺序是前序顺序，不是入参顺序', () {
      final view = fixture();
      // alpha-child 与 sibling 的 name（或 path）含 i；beta / other 不含。
      expect(tagGraphSearchMatchIds(view, 'i'), ['c', 'e']);
    });

    test('没有命中返回空列表', () {
      final view = fixture();
      expect(tagGraphSearchMatchIds(view, 'no-such-tag'), isEmpty);
    });
  });

  group('祖先与搜索闭包', () {
    test('祖先是到根的全部节点，不含自己', () {
      final view = fixture();
      expect(tagGraphAncestorIds(view, ['c']), {'a', 'b'});
      expect(tagGraphAncestorIds(view, ['c', 'd']), {'a', 'b'});
      expect(tagGraphAncestorIds(view, ['a']), isEmpty);
      expect(tagGraphAncestorIds(view, ['nope']), isEmpty);
    });

    test('闭包 = 命中节点 + 祖先 + 命中节点的全部后代', () {
      final view = fixture();
      expect(tagGraphSearchVisibleIds(view, ['c']), {'a', 'b', 'c'});
      expect(tagGraphSearchVisibleIds(view, ['b']), {'a', 'b', 'c', 'd'});
      expect(tagGraphSearchVisibleIds(view, ['a']), {'a', 'b', 'c', 'd', 'e'});
      expect(tagGraphSearchVisibleIds(view, ['f']), {'f'});
    });

    test('多个命中取并集；未知 id 被忽略', () {
      final view = fixture();
      expect(
        tagGraphSearchVisibleIds(view, ['c', 'e', 'nope']),
        {'a', 'b', 'c', 'e'},
      );
    });
  });
}
