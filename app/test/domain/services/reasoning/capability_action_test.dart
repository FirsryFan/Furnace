// 能力动作词表的守卫测试。
//
// 这张表会被写进数据库并被统计，所以这里守的不是「代码能跑」，而是
// 「key 不会悄悄变、排序规则不会被手改破坏、未知 key 不会让调用方崩」。

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';

/// 任务里给定的 20 个种子动作。词表可以增删，但删掉任何一个都必须是有意识的
/// 决定（并在 docs/REASONING_LAYER_DESIGN.md 里写一句理由），所以这里钉住集合。
const List<String> _seedKeys = <String>[
  'invariant_recognition',
  'counterexample_construction',
  'extreme_case',
  'reduction',
  'induction',
  'constructive_upper_bound',
  'symmetry',
  'dimensional_check',
  'state_tracking',
  'invariant_decomposition',
  'graph_modeling',
  'amortized_argument',
  'proof_by_contradiction',
  'case_split',
  'monotonicity',
  'conservation_law',
  'information_bound',
  'first_principles',
  'analogy_transfer',
  'sanity_check',
];

final RegExp _snakeCase = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

void main() {
  group('catalog 结构不变量', () {
    test('key 唯一，且非空', () {
      final keys = <String>[];
      for (final action in CapabilityAction.catalog) {
        expect(action.key, isNotEmpty);
        expect(keys.contains(action.key), isFalse,
            reason: 'key 重复：${action.key}');
        keys.add(action.key);
      }
      expect(keys.length, CapabilityAction.catalog.length);
      expect(CapabilityAction.keys, keys);
    });

    test('20 个种子动作一个都没丢', () {
      final present = CapabilityAction.keys.toSet();
      for (final seed in _seedKeys) {
        expect(present.contains(seed), isTrue,
            reason: '种子动作 $seed 不在词表里；若确实要删除，'
                '请在 docs/REASONING_LAYER_DESIGN.md 写明理由');
      }
    });

    test('sortOrder 与下标一致且从 0 连续递增', () {
      for (var i = 0; i < CapabilityAction.catalog.length; i++) {
        expect(CapabilityAction.catalog[i].sortOrder, i,
            reason: '${CapabilityAction.catalog[i].key} 的 sortOrder 与下标不一致');
      }
    });

    test('排序规则：可迁移的在前，组内按 subjectHints 数量降序', () {
      const catalog = CapabilityAction.catalog;
      for (var i = 1; i < catalog.length; i++) {
        final prev = catalog[i - 1];
        final cur = catalog[i];
        if (prev.transferable == cur.transferable) {
          expect(prev.subjectHints.length >= cur.subjectHints.length, isTrue,
              reason: '${prev.key}(${prev.subjectHints.length}) 应排在 '
                  '${cur.key}(${cur.subjectHints.length}) 之前');
        } else {
          expect(prev.transferable, isTrue,
              reason: '可迁移动作必须排在领域特有动作之前，'
                  '但 ${prev.key} 排在 ${cur.key} 之前');
        }
      }
    });

    test('transferable 由 subjectHints 数量推出，不是手写的感觉', () {
      for (final action in CapabilityAction.catalog) {
        expect(
          action.transferable,
          action.subjectHints.length >=
              CapabilityAction.transferableSubjectThreshold,
          reason: '${action.key} 的 transferable 与 subjectHints 数量矛盾',
        );
      }
    });
  });

  group('catalog 字段合法性', () {
    test('key 是 snake_case（稳定标识，永不本地化）', () {
      for (final action in CapabilityAction.catalog) {
        expect(_snakeCase.hasMatch(action.key), isTrue,
            reason: '${action.key} 不是 snake_case');
      }
    });

    test('展示文本非空，且中文名不是英文占位', () {
      for (final action in CapabilityAction.catalog) {
        expect(action.labelZh.trim(), isNotEmpty,
            reason: '${action.key} 缺 labelZh');
        expect(action.labelEn.trim(), isNotEmpty,
            reason: '${action.key} 缺 labelEn');
        expect(action.descriptionZh.trim(), isNotEmpty,
            reason: '${action.key} 缺 descriptionZh');
        expect(RegExp(r'[\u4e00-\u9fa5]').hasMatch(action.labelZh), isTrue,
            reason: '${action.key} 的 labelZh 里没有汉字');
      }
    });

    test('subjectHints 取值合法、非空、无重复', () {
      final allowed = CapabilityAction.subjectKeys.toSet();
      expect(allowed.length, CapabilityAction.subjectKeys.length,
          reason: 'subjectKeys 自身有重复');
      for (final action in CapabilityAction.catalog) {
        expect(action.subjectHints, isNotEmpty,
            reason: '${action.key} 没有给出任何学科提示');
        expect(action.subjectHints.toSet().length, action.subjectHints.length,
            reason: '${action.key} 的 subjectHints 有重复');
        for (final hint in action.subjectHints) {
          expect(allowed.contains(hint), isTrue,
              reason: '${action.key} 里出现了未登记的学科键：$hint');
        }
      }
    });
  });

  group('byKey 查询', () {
    test('已知 key 返回同一条目', () {
      for (final action in CapabilityAction.catalog) {
        final found = CapabilityAction.byKey(action.key);
        expect(found, isNotNull);
        expect(identical(found, action), isTrue);
        expect(found!.labelZh, action.labelZh);
      }
    });

    test('未知 key 返回 null，永不抛异常', () {
      for (final unknown in <String>['', '   ', 'nope', 'quantum_vibes']) {
        expect(CapabilityAction.byKey(unknown), isNull,
            reason: '不认识的 key：$unknown');
        expect(CapabilityAction.isKnownKey(unknown), isFalse);
      }
    });

    test('忽略首尾空白，但不忽略大小写', () {
      expect(CapabilityAction.byKey('  reduction  ')?.key, 'reduction');
      expect(CapabilityAction.byKey('Reduction'), isNull,
          reason: '错大小写应当被当成未知 key，而不是被悄悄归一化');
    });
  });

  group('序列化', () {
    test('toJson 含全部契约字段，json 是它的别名', () {
      final action = CapabilityAction.byKey('invariant_recognition')!;
      final json = action.toJson();
      expect(json['key'], 'invariant_recognition');
      expect(json['labelZh'], action.labelZh);
      expect(json['labelEn'], action.labelEn);
      expect(json['descriptionZh'], action.descriptionZh);
      expect(json['subjectHints'], action.subjectHints);
      expect(json['transferable'], action.transferable);
      expect(json['sortOrder'], action.sortOrder);
      expect(action.json, json);
    });

    test('每一条都能序列化，且 key 在 JSON 里可反查', () {
      for (final action in CapabilityAction.catalog) {
        final vector = action.toJson();
        expect(vector.length, 7);
        expect(CapabilityAction.byKey(vector['key'] as String), isNotNull);
      }
    });
  });
}
