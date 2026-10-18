// 能力动作 overlay 编辑层：加 / 改 / 删 / 移动 / 导入的纯逻辑行为，以及
// 「失败不改数据」「坏数据不抛异常」两条硬约束。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay_editor.dart';

/// 构造一条合法的自定义动作；各测试只覆盖自己关心的字段。
CustomCapabilityAction action({
  String key = 'force_diagram',
  String labelZh = '画受力图',
  String labelEn = 'Free-body diagram',
  String descriptionZh = '把研究对象独立出来，按性质逐个画力。',
  List<String> subjectHints = const <String>[
    'physics',
    'math',
    'chemistry',
    'biology',
  ],
}) {
  return CustomCapabilityAction(
    key: key,
    labelZh: labelZh,
    labelEn: labelEn,
    descriptionZh: descriptionZh,
    subjectHints: subjectHints,
  );
}

CapabilityActionOverlay overlayOf(List<CustomCapabilityAction> actions) =>
    CapabilityActionOverlay(customActions: actions);

/// 用编辑层自己堆出 count 条合法自定义动作，顺带验证 add 的 happy path。
CapabilityActionOverlay overlayWithCount(int count) {
  var overlay = const CapabilityActionOverlay();
  for (var index = 0; index < count; index++) {
    final result = CapabilityActionOverlayEditor.add(
      overlay,
      action(key: 'custom_action_$index', labelZh: '动作$index'),
    );
    expect(result.changed, isTrue);
    expect(result.issues, isEmpty);
    overlay = result.overlay;
  }
  return overlay;
}

List<CapabilityActionOverlayIssueReason> reasonsOf(
  List<CapabilityActionOverlayIssue> issues,
) {
  return <CapabilityActionOverlayIssueReason>[
    for (final issue in issues) issue.reason,
  ];
}

void main() {
  group('add', () {
    test('合法条目：归整后追加，词表立即可用', () {
      final result = CapabilityActionOverlayEditor.add(
        const CapabilityActionOverlay(),
        action(
          key: '  force_diagram  ',
          labelZh: ' 画受力图 ',
          labelEn: ' Free-body diagram ',
          subjectHints: const <String>[
            'physics',
            'unknown',
            'physics',
            'math',
          ],
        ),
      );
      expect(result.changed, isTrue);
      expect(result.issues, isEmpty);
      expect(result.hasIssues, isFalse);
      expect(result.overlay.length, 1);
      final added = result.overlay.customActions.single;
      expect(added.key, 'force_diagram');
      expect(added.labelZh, '画受力图');
      expect(added.labelEn, 'Free-body diagram');
      expect(added.subjectHints, <String>['physics', 'math']);
      final catalog = result.overlay.catalog;
      expect(catalog.issues, isEmpty);
      expect(catalog.isKnownKey('force_diagram'), isTrue);
      expect(catalog.isCustomKey('force_diagram'), isTrue);
      expect(catalog.isBuiltInKey('force_diagram'), isFalse);
      expect(catalog.customActions.single.labelZh, '画受力图');
    });

    test('与已有自定义 key 重复：拒绝且不改数据', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.add(
        base,
        action(labelZh: '新名字'),
      );
      expect(result.changed, isFalse);
      expect(result.issues.length, 1);
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.duplicateKey,
      ]);
      expect(identical(result.overlay, base), isTrue);
      expect(result.overlay.length, 1);
      expect(result.overlay.customActions.single.labelZh, '画受力图');
    });

    test('内置 key 保留：不能追加覆盖', () {
      const base = CapabilityActionOverlay();
      final result = CapabilityActionOverlayEditor.add(
        base,
        action(key: 'first_principles', labelZh: '第一性原理'),
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.keyReserved,
      ]);
      expect(result.changed, isFalse);
      expect(identical(result.overlay, base), isTrue);
    });

    test('非法 key：每种原因各返回对应枚举，数据不变', () {
      const base = CapabilityActionOverlay();
      final tooLong = List<String>.filled(
        CapabilityActionOverlay.maxKeyLength + 1,
        'a',
      ).join();
      final cases = <String, CapabilityActionOverlayIssueReason>{
        '': CapabilityActionOverlayIssueReason.missingKey,
        '   ': CapabilityActionOverlayIssueReason.missingKey,
        tooLong: CapabilityActionOverlayIssueReason.keyTooLong,
        'Force Diagram': CapabilityActionOverlayIssueReason.keyNotSnakeCase,
        'force-diagram': CapabilityActionOverlayIssueReason.keyNotSnakeCase,
        '1force': CapabilityActionOverlayIssueReason.keyNotSnakeCase,
        'force_': CapabilityActionOverlayIssueReason.keyNotSnakeCase,
      };
      for (final entry in cases.entries) {
        final result = CapabilityActionOverlayEditor.add(
          base,
          action(key: entry.key),
        );
        expect(
          reasonsOf(result.issues),
          <CapabilityActionOverlayIssueReason>[entry.value],
          reason: 'key=${entry.key}',
        );
        expect(result.changed, isFalse, reason: 'key=${entry.key}');
        expect(
          identical(result.overlay, base),
          isTrue,
          reason: 'key=${entry.key}',
        );
      }
    });

    test('缺中文名：missingLabelZh', () {
      const base = CapabilityActionOverlay();
      final result = CapabilityActionOverlayEditor.add(
        base,
        action(labelZh: '   '),
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.missingLabelZh,
      ]);
      expect(identical(result.overlay, base), isTrue);
    });

    test('达到上限后拒绝追加新条目', () {
      final base = overlayWithCount(
        CapabilityActionOverlayEditor.maxCustomActions,
      );
      expect(base.length, CapabilityActionOverlayEditor.maxCustomActions);
      final result = CapabilityActionOverlayEditor.add(
        base,
        action(key: 'one_more', labelZh: '再来一条'),
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.customActionLimitExceeded,
      ]);
      expect(result.changed, isFalse);
      expect(identical(result.overlay, base), isTrue);
    });
  });

  group('update', () {
    test('只改中文名：其它字段与顺序不变', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
      ]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        labelZh: ' 画受力图（进阶） ',
      );
      expect(result.changed, isTrue);
      expect(result.issues, isEmpty);
      expect(result.overlay.customActions[0].labelZh, '画受力图（进阶）');
      expect(result.overlay.customActions[0].labelEn, 'Free-body diagram');
      expect(result.overlay.customActions[0].subjectHints, <String>[
        'physics',
        'math',
        'chemistry',
        'biology',
      ]);
      expect(result.overlay.customActions[1].labelZh, '配平');
      expect(identical(result.overlay, base), isFalse);
    });

    test('清空 labelEn / descriptionZh / subjectHints：合并词表用兜底值', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        labelEn: '',
        descriptionZh: '',
        subjectHints: const <String>[],
      );
      expect(result.changed, isTrue);
      final catalog = result.overlay.catalog;
      expect(catalog.issues, isEmpty);
      final merged = catalog.byKey('force_diagram');
      expect(merged, isNotNull);
      expect(merged?.labelEn, 'force_diagram');
      expect(merged?.descriptionZh, '画受力图');
      expect(merged?.subjectHints, isEmpty);
      expect(merged?.transferable, isFalse);
    });

    test('subjectHints 归整：非法学科丢弃、去重保序', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        subjectHints: const <String>['math', 'unknown', 'physics', 'math'],
      );
      expect(result.overlay.customActions.single.subjectHints, <String>[
        'math',
        'physics',
      ]);
      expect(result.overlay.catalog.issues, isEmpty);
    });

    test('传入与原值相同的内容：changed=false 且返回同一对象', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        labelZh: '画受力图',
        labelEn: 'Free-body diagram',
      );
      expect(result.changed, isFalse);
      expect(result.issues, isEmpty);
      expect(identical(result.overlay, base), isTrue);
    });

    test('key 不存在：keyNotFound 且不改数据', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'not_there',
        labelZh: '新名字',
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.keyNotFound,
      ]);
      expect(result.changed, isFalse);
      expect(identical(result.overlay, base), isTrue);
    });

    test('更新后中文名为空：missingLabelZh，原数据不变', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        labelZh: '   ',
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.missingLabelZh,
      ]);
      expect(identical(result.overlay, base), isTrue);
      expect(base.customActions.single.labelZh, '画受力图');
    });

    test('更新不能改 key：key 保持原值', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.update(
        base,
        key: 'force_diagram',
        labelZh: '新名字',
      );
      expect(result.overlay.customActions.single.key, 'force_diagram');
    });
  });

  group('remove', () {
    test('删除中间条目：其余条目保持原顺序', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
        action(key: 'draw_circuit', labelZh: '画电路'),
      ]);
      final result = CapabilityActionOverlayEditor.remove(
        base,
        'balance_equation',
      );
      expect(result.changed, isTrue);
      expect(result.issues, isEmpty);
      expect(result.overlay.length, 2);
      expect(
        result.overlay.customActions.map((item) => item.key).toList(),
        <String>['force_diagram', 'draw_circuit'],
      );
    });

    test('key 不存在：keyNotFound 且不改数据', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.remove(base, 'not_there');
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.keyNotFound,
      ]);
      expect(identical(result.overlay, base), isTrue);
    });

    test('重复 key 的历史数据：删除所有同 key 条目', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
        action(labelZh: '重复受力图'),
      ]);
      final result =
          CapabilityActionOverlayEditor.remove(base, 'force_diagram');
      expect(result.changed, isTrue);
      expect(result.overlay.length, 1);
      expect(result.overlay.customActions.single.key, 'balance_equation');
    });

    test('删空后回到默认 overlay：词表等于内置词表', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result =
          CapabilityActionOverlayEditor.remove(base, 'force_diagram');
      expect(result.overlay.isEmpty, isTrue);
      expect(result.overlay.catalog.isKnownKey('force_diagram'), isFalse);
      expect(
        result.overlay.catalog.isKnownKey('first_principles'),
        isTrue,
      );
    });

    test('空 key：keyNotFound，不会误删空 key 条目', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.remove(base, '   ');
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.keyNotFound,
      ]);
      expect(identical(result.overlay, base), isTrue);
    });
  });

  group('reorder', () {
    test('把最后一条移到最前：顺序按新的下标生效', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
        action(key: 'draw_circuit', labelZh: '画电路'),
      ]);
      final result = CapabilityActionOverlayEditor.reorder(
        base,
        key: 'draw_circuit',
        newIndex: 0,
      );
      expect(result.changed, isTrue);
      expect(
        result.overlay.customActions.map((item) => item.key).toList(),
        <String>['draw_circuit', 'force_diagram', 'balance_equation'],
      );
      expect(
        result.overlay.catalog.customActions.map((item) => item.key).toList(),
        <String>['draw_circuit', 'force_diagram', 'balance_equation'],
      );
    });

    test('把第一条移到最后', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
        action(key: 'draw_circuit', labelZh: '画电路'),
      ]);
      final result = CapabilityActionOverlayEditor.reorder(
        base,
        key: 'force_diagram',
        newIndex: 2,
      );
      expect(
        result.overlay.customActions.map((item) => item.key).toList(),
        <String>['balance_equation', 'draw_circuit', 'force_diagram'],
      );
    });

    test('移到原位：changed=false 且返回同一对象', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
      ]);
      final result = CapabilityActionOverlayEditor.reorder(
        base,
        key: 'force_diagram',
        newIndex: 0,
      );
      expect(result.changed, isFalse);
      expect(result.issues, isEmpty);
      expect(identical(result.overlay, base), isTrue);
    });

    test('下标越界：indexOutOfRange 且不改数据', () {
      final base = overlayOf(<CustomCapabilityAction>[
        action(),
        action(key: 'balance_equation', labelZh: '配平'),
      ]);
      for (final newIndex in <int>[-1, 2]) {
        final result = CapabilityActionOverlayEditor.reorder(
          base,
          key: 'force_diagram',
          newIndex: newIndex,
        );
        expect(
          reasonsOf(result.issues),
          <CapabilityActionOverlayIssueReason>[
            CapabilityActionOverlayIssueReason.indexOutOfRange,
          ],
          reason: 'newIndex=$newIndex',
        );
        expect(identical(result.overlay, base), isTrue);
      }
    });

    test('key 不存在：keyNotFound', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.reorder(
        base,
        key: 'not_there',
        newIndex: 0,
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.keyNotFound,
      ]);
    });
  });

  group('mergeImport', () {
    test('接受 toJson 产物：按顺序追加，冲突键跳过', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final source = overlayOf(<CustomCapabilityAction>[
        action(labelZh: '重复的受力图'),
        action(key: 'balance_equation', labelZh: '配平'),
      ]).toJson();
      final result = CapabilityActionOverlayEditor.mergeImport(base, source);
      expect(result.changed, isTrue);
      expect(result.overlay.length, 2);
      expect(result.overlay.customActions[0].labelZh, '画受力图');
      expect(result.overlay.customActions[1].key, 'balance_equation');
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.duplicateKey,
      ]);
      expect(result.overlay.catalog.issues, isEmpty);
    });

    test('接受裸条目数组', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.mergeImport(
        base,
        <Object?>[action(key: 'balance_equation', labelZh: '配平').toJson()],
      );
      expect(result.changed, isTrue);
      expect(result.overlay.length, 2);
      expect(result.issues, isEmpty);
    });

    test('顶层形状不认识：importNotRecognized 且不改数据', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final sources = <Object?>[
        null,
        'text',
        42,
        <String, Object?>{},
        <String, Object?>{'customActions': 'nope'},
      ];
      for (final source in sources) {
        final result = CapabilityActionOverlayEditor.mergeImport(base, source);
        expect(
          reasonsOf(result.issues),
          <CapabilityActionOverlayIssueReason>[
            CapabilityActionOverlayIssueReason.importNotRecognized,
          ],
          reason: 'source=$source',
        );
        expect(result.changed, isFalse);
        expect(
          identical(result.overlay, base),
          isTrue,
          reason: 'source=$source',
        );
      }
    });

    test('逐条非法：非对象 / 非法 key / 内置 key / 缺中文名各记原因', () {
      const base = CapabilityActionOverlay();
      final result = CapabilityActionOverlayEditor.mergeImport(base, <Object?>[
        'not-a-map',
        <String, Object?>{'key': 'Bad Key', 'labelZh': 'x'},
        <String, Object?>{'key': 'first_principles', 'labelZh': 'x'},
        <String, Object?>{'key': 'no_label'},
        <String, Object?>{'key': 'good_one', 'labelZh': '好的'},
      ]);
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.missingKey,
        CapabilityActionOverlayIssueReason.keyNotSnakeCase,
        CapabilityActionOverlayIssueReason.keyReserved,
        CapabilityActionOverlayIssueReason.missingLabelZh,
      ]);
      expect(result.changed, isTrue);
      expect(result.overlay.length, 1);
      expect(result.overlay.customActions.single.key, 'good_one');
    });

    test('导入条目会归整：去空白、subjectHints 只留合法学科', () {
      const base = CapabilityActionOverlay();
      final result = CapabilityActionOverlayEditor.mergeImport(base, <Object?>[
        <String, Object?>{
          'key': '  balance_equation  ',
          'labelZh': ' 配平 ',
          'subjectHints': <String>['chemistry', 'bogus', 'chemistry'],
        },
      ]);
      final imported = result.overlay.customActions.single;
      expect(imported.key, 'balance_equation');
      expect(imported.labelZh, '配平');
      expect(imported.subjectHints, <String>['chemistry']);
    });

    test('达到上限：合法条目记 customActionLimitExceeded', () {
      final base = overlayWithCount(
        CapabilityActionOverlayEditor.maxCustomActions,
      );
      final result = CapabilityActionOverlayEditor.mergeImport(
        base,
        <Object?>[action(key: 'extra_one', labelZh: '一').toJson()],
      );
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.customActionLimitExceeded,
      ]);
      expect(result.changed, isFalse);
      expect(identical(result.overlay, base), isTrue);
    });

    test('空数组导入：无变化、无问题、返回同一对象', () {
      final base = overlayOf(<CustomCapabilityAction>[action()]);
      final result = CapabilityActionOverlayEditor.mergeImport(
        base,
        const <Object?>[],
      );
      expect(result.changed, isFalse);
      expect(result.issues, isEmpty);
      expect(identical(result.overlay, base), isTrue);
    });

    test('本次导入内重复 key：先到先得', () {
      const base = CapabilityActionOverlay();
      final result = CapabilityActionOverlayEditor.mergeImport(base, <Object?>[
        <String, Object?>{'key': 'balance_equation', 'labelZh': '配平一'},
        <String, Object?>{'key': 'balance_equation', 'labelZh': '配平二'},
      ]);
      expect(result.changed, isTrue);
      expect(result.overlay.length, 1);
      expect(result.overlay.customActions.single.labelZh, '配平一');
      expect(reasonsOf(result.issues), <CapabilityActionOverlayIssueReason>[
        CapabilityActionOverlayIssueReason.duplicateKey,
      ]);
    });
  });

  group('序列化与公开 helper', () {
    test('编辑结果经 toJson/fromJson 往返后继续可编辑', () {
      var overlay = const CapabilityActionOverlay();
      overlay = CapabilityActionOverlayEditor.add(overlay, action()).overlay;
      overlay = CapabilityActionOverlayEditor.add(
        overlay,
        action(key: 'balance_equation', labelZh: '配平'),
      ).overlay;
      final decoded = jsonDecode(jsonEncode(overlay.toJson()));
      final restored = CapabilityActionOverlay.fromJson(decoded);
      expect(restored.length, 2);
      expect(
        restored.customActions.map((item) => item.key).toList(),
        <String>['force_diagram', 'balance_equation'],
      );
      final update = CapabilityActionOverlayEditor.update(
        restored,
        key: 'balance_equation',
        labelZh: '配平（进阶）',
      );
      expect(update.changed, isTrue);
      expect(update.overlay.customActions[1].labelZh, '配平（进阶）');
    });

    test('validateCustomCapabilityAction：合法返回 null，非法返回原因', () {
      expect(validateCustomCapabilityAction(action()), isNull);
      final issue = validateCustomCapabilityAction(action(key: 'Bad Key'));
      expect(issue, isNotNull);
      expect(
        issue?.reason,
        CapabilityActionOverlayIssueReason.keyNotSnakeCase,
      );
    });

    test('normalizeCustomCapabilityAction：只归整、不校验', () {
      final normalized = normalizeCustomCapabilityAction(
        action(
          key: ' Force ',
          labelZh: ' 画 ',
          subjectHints: const <String>['math', 'bogus', 'math'],
        ),
      );
      expect(normalized.key, 'Force');
      expect(normalized.labelZh, '画');
      expect(normalized.subjectHints, <String>['math']);
    });
  });
}
