/// 标签树展开状态的持久化编解码（v48，2026-11-17）。
///
/// 锁的是契约而不是实现：
///  * 没有任何保存值（NULL / 空白 / 坏 JSON / 非数组）→ 空集合 = 默认全折叠；
///  * 存「展开」而不是「折叠」：新标签不在历史集合里，因此默认折叠；
///  * 写侧去重、排序、丢空白，同一集合恒得同一字符串，方便逐字节断言；
///  * 未知 / 多余 id 原样保留（删标签由页面负责清理），读侧不会因为集合里有
///    不存在的 id 而报错。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_tree_expansion.dart';

void main() {
  group('tagTreeExpandedIdsFromStorage', () {
    test('NULL / 空白 / 坏 JSON / 非数组都读作出厂全折叠（空集合）', () {
      for (final raw in <String?>[
        null,
        '',
        '   ',
        'not-json',
        '{}',
        '"t-a"',
        '42',
      ]) {
        expect(tagTreeExpandedIdsFromStorage(raw), isEmpty,
            reason: 'raw = $raw');
      }
    });

    test('字符串数组还原成集合，跳过非字符串与空白项', () {
      expect(
        tagTreeExpandedIdsFromStorage('["t-a"," t-b ","",3,{"id":"t-c"}]'),
        <String>{'t-a', 't-b'},
      );
    });

    test('重复 id 只算一次', () {
      expect(
        tagTreeExpandedIdsFromStorage('["t-a","t-a","t-b"]'),
        <String>{'t-a', 't-b'},
      );
    });

    test('空数组读作"全都收起"而不是"没有保存值"之外的第三种状态', () {
      expect(tagTreeExpandedIdsFromStorage('[]'), isEmpty);
    });
  });

  group('tagTreeExpandedIdsToStorage', () {
    test('排序 + 去重 + 丢空白，保证同一集合序列化结果唯一', () {
      expect(
        tagTreeExpandedIdsToStorage(<String>['t-b', 't-a', ' t-b ', '', '   ']),
        '["t-a","t-b"]',
      );
      expect(tagTreeExpandedIdsToStorage(<String>[]), '[]');
    });

    test('序列化后再解析回原集合（往返稳定）', () {
      final ids = <String>{'t-c', 't-a', 't-b'};
      final encoded = tagTreeExpandedIdsToStorage(ids);
      expect(tagTreeExpandedIdsFromStorage(encoded), ids);
      expect(
          tagTreeExpandedIdsToStorage(
            tagTreeExpandedIdsFromStorage(encoded),
          ),
          encoded);
    });
  });
}
