// Q8: 知识点 id（`kp-…`）与标签 id（`tag-…`）之间的键翻译。
//
// 这个文件钉住的是"翻译本身"的规则，端到端的效果在
// `test/features/cognitive/knowledge_point_key_space_test.dart` 里用真实数据钉。

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/knowledge_point_tag_bridge.dart';

ObjectTagLink _link(String tagId, String objectId, {String? objectType}) =>
    ObjectTagLink(
      tagId: tagId,
      objectType: objectType ?? kKnowledgePointObjectType,
      objectId: objectId,
    );

void main() {
  group('tagIdsByKnowledgePoint', () {
    test('groups tags per knowledge point, sorted and de-duplicated', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-b', 'kp-1'),
        _link('tag-a', 'kp-1'),
        _link('tag-a', 'kp-1'), // duplicate link
        _link('tag-c', 'kp-2'),
        _link('tag-z', 'kp-0'),
      ]);

      expect(map.keys.toList(), ['kp-0', 'kp-1', 'kp-2']);
      expect(map['kp-1'], ['tag-a', 'tag-b']);
      expect(map['kp-2'], ['tag-c']);
    });

    test('ignores objects that are not knowledge points', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-a', 'kp-1'),
        _link('tag-b', 'task-1', objectType: 'task'),
        _link('tag-c', 'card-template-1', objectType: 'card_template'),
      ]);

      expect(map.keys.toList(), ['kp-1']);
      expect(map['kp-1'], ['tag-a']);
    });

    test('blank ids are ignored instead of becoming a key', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('   ', 'kp-1'),
        _link('tag-a', '  '),
        _link('tag-b', 'kp-1'),
      ]);

      expect(map.keys.toList(), ['kp-1']);
      expect(map['kp-1'], ['tag-b']);
    });

    test('the result does not depend on input order', () {
      final forward = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-b', 'kp-1'),
        _link('tag-a', 'kp-2'),
        _link('tag-a', 'kp-1'),
      ]);
      final backward = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-a', 'kp-1'),
        _link('tag-a', 'kp-2'),
        _link('tag-b', 'kp-1'),
      ]);

      expect(forward, backward);
    });

    test('no links at all is an empty map, not an error', () {
      expect(KnowledgePointTagBridge.tagIdsByKnowledgePoint(const []), isEmpty);
    });
  });

  group('tagIdsOf / tagIdsOfAll', () {
    final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
      _link('tag-b', 'kp-1'),
      _link('tag-a', 'kp-1'),
      _link('tag-c', 'kp-2'),
    ]);

    test('an unlinked knowledge point yields an empty list', () {
      expect(KnowledgePointTagBridge.tagIdsOf('kp-9', map), isEmpty);
      expect(KnowledgePointTagBridge.tagIdsOf('  ', map), isEmpty);
    });

    test('one point keeps its sorted tags', () {
      expect(KnowledgePointTagBridge.tagIdsOf('kp-1', map), ['tag-a', 'tag-b']);
    });

    test('a set of points unions and sorts, dropping unknown points', () {
      expect(
        KnowledgePointTagBridge.tagIdsOfAll(['kp-2', 'kp-1', 'kp-9'], map),
        ['tag-a', 'tag-b', 'tag-c'],
      );
      expect(KnowledgePointTagBridge.tagIdsOfAll(const [], map), isEmpty);
    });
  });

  group('expandKeys', () {
    test('every tag of a point carries the point value', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-b', 'kp-1'),
        _link('tag-a', 'kp-1'),
        _link('tag-c', 'kp-2'),
      ]);

      final expanded = KnowledgePointTagBridge.expandKeys<String>(
        byKnowledgePoint: const {'kp-1': 'row-1', 'kp-2': 'row-2'},
        tagIdsByKnowledgePoint: map,
      );

      expect(expanded, {'tag-a': 'row-1', 'tag-b': 'row-1', 'tag-c': 'row-2'});
    });

    test('a tag shared by two points goes to the smaller point id', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-shared', 'kp-2'),
        _link('tag-shared', 'kp-1'),
      ]);

      final expanded = KnowledgePointTagBridge.expandKeys<String>(
        byKnowledgePoint: const {'kp-1': 'row-1', 'kp-2': 'row-2'},
        tagIdsByKnowledgePoint: map,
      );

      expect(expanded, {'tag-shared': 'row-1'});
    });

    test('a point without tags contributes nothing', () {
      final expanded = KnowledgePointTagBridge.expandKeys<String>(
        byKnowledgePoint: const {'kp-1': 'row-1'},
        tagIdsByKnowledgePoint: const {},
      );

      expect(expanded, isEmpty);
    });
  });

  group('verdictsByKnowledgePoint', () {
    test('a verdict on any tag becomes a verdict on the point', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-b', 'kp-1'),
        _link('tag-a', 'kp-1'),
      ]);

      final verdicts = KnowledgePointTagBridge.verdictsByKnowledgePoint(
        byTagId: const {'tag-b': BottleneckType.danger},
        tagIdsByKnowledgePoint: map,
      );

      expect(verdicts, {'kp-1': BottleneckType.danger});
    });

    test('the smallest tag id with a verdict wins, not the smallest tag id', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-a', 'kp-1'),
        _link('tag-b', 'kp-1'),
      ]);

      final verdicts = KnowledgePointTagBridge.verdictsByKnowledgePoint(
        byTagId: const {'tag-b': BottleneckType.weak},
        tagIdsByKnowledgePoint: map,
      );

      expect(verdicts, {'kp-1': BottleneckType.weak});
    });

    test('no verdict on any tag means the point is absent, not healthy', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-a', 'kp-1'),
        _link('tag-b', 'kp-2'),
      ]);

      final verdicts = KnowledgePointTagBridge.verdictsByKnowledgePoint(
        byTagId: const {'tag-a': BottleneckType.empty},
        tagIdsByKnowledgePoint: map,
      );

      expect(verdicts.containsKey('kp-2'), isFalse);
      expect(verdicts, {'kp-1': BottleneckType.empty});
    });

    test('an empty diagnosis yields an empty map', () {
      final map = KnowledgePointTagBridge.tagIdsByKnowledgePoint([
        _link('tag-a', 'kp-1'),
      ]);

      expect(
        KnowledgePointTagBridge.verdictsByKnowledgePoint(
          byTagId: const {},
          tagIdsByKnowledgePoint: map,
        ),
        isEmpty,
      );
    });
  });
}
