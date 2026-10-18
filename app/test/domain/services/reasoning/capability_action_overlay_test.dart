// 能力动作词表 overlay：用户可编辑词表的合并、校验、序列化，以及它接入
// 提示词/解析器的行为。
//
// 三条硬约束各有一组测试守着：默认 overlay 零行为变化；内置 key 优先不被覆盖；
// 坏的持久化数据只能退化、不能崩。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';

/// 构造一条合法的自定义动作；各测试只覆盖自己关心的字段。
CustomCapabilityAction customAction({
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

CapabilityActionCatalog catalogOf(List<CustomCapabilityAction> actions) {
  return CapabilityActionOverlay(customActions: actions).catalog;
}

void main() {
  group('默认构造零行为变化', () {
    test('默认 overlay 的合并词表与内置词表逐项相同（含对象身份）', () {
      final catalog = const CapabilityActionOverlay().catalog;
      expect(catalog.issues, isEmpty);
      expect(catalog.customActions, isEmpty);
      expect(catalog.length, CapabilityAction.catalog.length);
      for (var i = 0; i < CapabilityAction.catalog.length; i++) {
        expect(
          identical(catalog.actions[i], CapabilityAction.catalog[i]),
          isTrue,
          reason: '第 $i 个动作必须是内置对象本身，不能被复制或重排',
        );
      }
      expect(catalog.keys, CapabilityAction.keys);
    });

    test('空 overlay 仍能查内置动作、仍不认识未知 key', () {
      final catalog = CapabilityActionOverlay.empty.catalog;
      expect(catalog.byKey('reduction'),
          same(CapabilityAction.byKey('reduction')));
      expect(catalog.isKnownKey('reduction'), isTrue);
      expect(catalog.isBuiltInKey('reduction'), isTrue);
      expect(catalog.isCustomKey('reduction'), isFalse);
      expect(catalog.isKnownKey('quantum_vibes'), isFalse);
      expect(catalog.isEmpty, isFalse);
      expect(catalog.isNotEmpty, isTrue);
    });

    test('空 overlay 的 JSON 往返仍是空 overlay', () {
      final encoded = jsonEncode(CapabilityActionOverlay.empty.toJson());
      final round = CapabilityActionOverlay.fromJson(jsonDecode(encoded));
      expect(round.customActions, isEmpty);
      expect(round.isEmpty, isTrue);
      expect(round.toJson(), <String, Object?>{
        'version': 1,
        'customActions': <Object?>[],
      });
    });

    test('静态 builtIn 与合并空列表完全一致', () {
      final catalog = CapabilityActionCatalog.builtIn;
      expect(catalog.issues, isEmpty);
      expect(catalog.customActions, isEmpty);
      expect(catalog.keys, CapabilityAction.keys);
      expect(catalog.byKey('first_principles'),
          same(CapabilityAction.byKey('first_principles')));
    });
  });

  group('合并规则', () {
    test('自定义动作追加在内置之后，sortOrder 等于合并后下标', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'force_diagram', labelZh: '画受力图'),
        customAction(
          key: 'unit_check',
          labelZh: '量纲检查',
          subjectHints: const <String>['physics'],
        ),
      ]);
      expect(catalog.issues, isEmpty);
      expect(catalog.length, CapabilityAction.catalog.length + 2);

      final first = catalog.actions[CapabilityAction.catalog.length];
      expect(first.key, 'force_diagram');
      expect(first.sortOrder, CapabilityAction.catalog.length);

      final second = catalog.actions[CapabilityAction.catalog.length + 1];
      expect(second.key, 'unit_check');
      expect(second.sortOrder, CapabilityAction.catalog.length + 1);
      expect(catalog.customActions.map((a) => a.key),
          <String>['force_diagram', 'unit_check']);
    });

    test('transferable 由合法学科提示数量按统一判据推出', () {
      final transferable = catalogOf(<CustomCapabilityAction>[
        customAction(subjectHints: const <String>[
          'physics',
          'math',
          'chemistry',
          'biology',
        ]),
      ]).customActions.single;
      expect(transferable.transferable, isTrue);
      expect(transferable.subjectHints.length,
          CapabilityAction.transferableSubjectThreshold);

      final local = catalogOf(<CustomCapabilityAction>[
        customAction(
          key: 'unit_check',
          subjectHints: const <String>['physics', 'math', 'chemistry'],
        ),
      ]).customActions.single;
      expect(local.transferable, isFalse);
    });

    test('subjectHints 只保留合法学科、去重、保持顺序', () {
      final action = catalogOf(<CustomCapabilityAction>[
        customAction(subjectHints: const <String>[
          'physics',
          'not_a_subject',
          'math',
          'physics',
          '  chemistry  ',
        ]),
      ]).customActions.single;
      expect(action.subjectHints, <String>['physics', 'math', 'chemistry']);
    });

    test('展示字段留空时的兜底可预期', () {
      final action = catalogOf(<CustomCapabilityAction>[
        const CustomCapabilityAction(key: 'unit_check', labelZh: '量纲检查'),
      ]).customActions.single;
      expect(action.labelEn, 'unit_check');
      expect(action.descriptionZh, '量纲检查');
      expect(action.subjectHints, isEmpty);
      expect(action.transferable, isFalse);
    });

    test('byKey / isBuiltInKey / isCustomKey 区分三类动作', () {
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      expect(catalog.isBuiltInKey('reduction'), isTrue);
      expect(catalog.isCustomKey('reduction'), isFalse);
      expect(catalog.isBuiltInKey('force_diagram'), isFalse);
      expect(catalog.isCustomKey('force_diagram'), isTrue);
      expect(catalog.isKnownKey('force_diagram'), isTrue);
      expect(catalog.isKnownKey('quantum_vibes'), isFalse);
      expect(catalog.isCustomKey('quantum_vibes'), isFalse);
      expect(catalog.byKey('  force_diagram  '),
          same(catalog.byKey('force_diagram')));
      expect(catalog.byKey('Force_Diagram'), isNull,
          reason: '大小写不忽略：错大小写就是未知 key');
    });
  });

  group('内置优先（覆盖被拒绝）', () {
    test('与内置 key 冲突时拒绝覆盖，内置条目原样保留', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'reduction', labelZh: '我的化归'),
      ]);
      expect(catalog.customActions, isEmpty);
      expect(catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.keyReserved);
      expect(catalog.issues.single.key, 'reduction');
      expect(catalog.issues.single.message, contains('内置'));
      expect(catalog.byKey('reduction'),
          same(CapabilityAction.byKey('reduction')));
      expect(catalog.byKey('reduction')!.labelZh, isNot('我的化归'));
    });

    test('自定义之间重复 key：先到先得，后一条记 issue', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'unit_check', labelZh: '甲'),
        customAction(key: 'unit_check', labelZh: '乙'),
      ]);
      expect(catalog.customActions.single.labelZh, '甲');
      expect(catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.duplicateKey);
      expect(catalog.issues.single.key, 'unit_check');
      expect(catalog.byKey('unit_check')!.labelZh, '甲');
    });

    test('被拒条目不占位：前一条非法时后一条同 key 合法条目仍生效', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'Bad-Key'),
        customAction(key: 'unit_check', labelZh: '量纲检查'),
      ]);
      expect(catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.keyNotSnakeCase);
      expect(catalog.isCustomKey('unit_check'), isTrue);
    });
  });

  group('key 校验', () {
    test('空 key 被拒', () {
      for (final key in <String>['', '   ']) {
        final catalog =
            catalogOf(<CustomCapabilityAction>[customAction(key: key)]);
        expect(catalog.issues.single.reason,
            CapabilityActionOverlayIssueReason.missingKey,
            reason: '"$key"');
        expect(catalog.customActions, isEmpty);
      }
    });

    test('非小写蛇形 key 被拒', () {
      const badKeys = <String>[
        'Reduction',
        'two__underscores',
        '_leading',
        'trailing_',
        'has space',
        '中文动作',
        '9starts_with_digit',
        'dash-key',
      ];
      for (final key in badKeys) {
        final catalog =
            catalogOf(<CustomCapabilityAction>[customAction(key: key)]);
        expect(catalog.issues.single.reason,
            CapabilityActionOverlayIssueReason.keyNotSnakeCase,
            reason: key);
        expect(catalog.customActions, isEmpty, reason: key);
      }
    });

    test('key 长度上限：48 放行、49 拒绝', () {
      final atLimit =
          List<String>.filled(CapabilityActionOverlay.maxKeyLength, 'a').join();
      final overLimit = '${atLimit}a';
      final accepted =
          catalogOf(<CustomCapabilityAction>[customAction(key: atLimit)]);
      expect(accepted.issues, isEmpty);
      expect(accepted.customActions.single.key, atLimit);

      final rejected =
          catalogOf(<CustomCapabilityAction>[customAction(key: overLimit)]);
      expect(rejected.issues.single.reason,
          CapabilityActionOverlayIssueReason.keyTooLong);
    });

    test('key 首尾空白被 trim 后接受', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: '  unit_check  '),
      ]);
      expect(catalog.issues, isEmpty);
      expect(catalog.customActions.single.key, 'unit_check');
    });

    test('缺中文名被拒', () {
      final catalog = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'unit_check', labelZh: '   '),
      ]);
      expect(catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.missingLabelZh);
      expect(catalog.customActions, isEmpty);
    });

    test('issue 的 JSON / 文案带原因枚举名与可读信息', () {
      final issue = catalogOf(<CustomCapabilityAction>[
        customAction(key: 'reduction'),
      ]).issues.single;
      expect(issue.toJson()['reason'], 'keyReserved');
      expect(issue.toJson()['key'], 'reduction');
      expect(issue.message, isNotEmpty);
      expect(issue.toString(), contains('keyReserved'));
    });
  });

  group('序列化与容错', () {
    test('合法 overlay 往返字段不丢', () {
      final overlay =
          CapabilityActionOverlay(customActions: <CustomCapabilityAction>[
        customAction(subjectHints: const <String>['physics', 'math']),
        customAction(key: 'unit_check', subjectHints: const <String>[]),
      ]);
      final round = CapabilityActionOverlay.fromJson(
          jsonDecode(jsonEncode(overlay.toJson())));
      expect(round.customActions.length, 2);
      final first = round.customActions.first;
      expect(first.key, 'force_diagram');
      expect(first.labelZh, '画受力图');
      expect(first.labelEn, 'Free-body diagram');
      expect(first.descriptionZh, '把研究对象独立出来，按性质逐个画力。');
      expect(first.subjectHints, <String>['physics', 'math']);
      expect(round.catalog.issues, isEmpty);
    });

    test('未知顶层字段与未知条目字段被忽略', () {
      final tolerant = CapabilityActionOverlay.fromJson(<String, Object?>{
        'version': 99,
        'futureFlag': true,
        'customActions': <Object?>[
          <String, Object?>{
            'key': 'unit_check',
            'labelZh': '量纲检查',
            'color': 'red',
          },
        ],
      });
      expect(tolerant.customActions.single.key, 'unit_check');
      expect(tolerant.toJson().containsKey('futureFlag'), isFalse);
      final entry = (tolerant.toJson()['customActions']! as List<Object?>)
          .first! as Map<String, Object?>;
      expect(entry.containsKey('color'), isFalse);
    });

    test('fromJson 吃坏数据不崩、退化为空 overlay', () {
      final garbage = <Object?>[
        null,
        42,
        'nope',
        true,
        <int>[1, 2],
        <String, Object?>{'customActions': 'nope'},
        <String, Object?>{},
      ];
      for (final raw in garbage) {
        late CapabilityActionOverlay overlay;
        expect(() {
          overlay = CapabilityActionOverlay.fromJson(raw);
        }, returnsNormally);
        expect(overlay.customActions, isEmpty);
        expect(overlay.catalog.issues, isEmpty);
      }
    });

    test('接受裸数组形态，条目里的非对象被跳过', () {
      final overlay = CapabilityActionOverlay.fromJson(<Object?>[
        <String, Object?>{'key': 'unit_check', 'labelZh': '量纲检查'},
        42,
        'not an object',
      ]);
      expect(overlay.customActions.single.key, 'unit_check');
      expect(overlay.catalog.customActions.single.labelZh, '量纲检查');
    });

    test('条目字段类型错误退化默认值，合并时按缺失 key 记 issue', () {
      final overlay = CapabilityActionOverlay.fromJson(<String, Object?>{
        'customActions': <Object?>[
          <String, Object?>{
            'key': 42,
            'labelZh': <String>['x'],
          },
        ],
      });
      expect(overlay.customActions.single.key, '');
      expect(overlay.catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.missingKey);
    });

    test('非法条目随序列化保留，不替用户丢数据', () {
      final overlay =
          CapabilityActionOverlay(customActions: <CustomCapabilityAction>[
        customAction(key: 'Bad-Key', labelZh: '坏 key'),
      ]);
      final round = CapabilityActionOverlay.fromJson(
          jsonDecode(jsonEncode(overlay.toJson())));
      expect(round.customActions.single.key, 'Bad-Key');
      expect(round.catalog.issues.single.reason,
          CapabilityActionOverlayIssueReason.keyNotSnakeCase);
    });

    test('CustomCapabilityAction.fromJson 对非对象与坏字段宽容', () {
      final empty = CustomCapabilityAction.fromJson(null);
      expect(empty.key, '');
      expect(empty.labelZh, '');
      expect(empty.subjectHints, isEmpty);

      final parsed = CustomCapabilityAction.fromJson(<String, Object?>{
        'key': '  unit_check ',
        'labelZh': ' 量纲检查 ',
        'subjectHints': <Object?>['physics', 42, 'physics'],
      });
      expect(parsed.key, 'unit_check');
      expect(parsed.labelZh, '量纲检查');
      expect(parsed.subjectHints, <String>['physics']);
    });
  });

  group('parseChain 注入自定义词表', () {
    const customReply = '''
{"summary":"s","steps":[
  {"index":1,"goal":"画受力图","actionType":"force_diagram","stuckRisk":0.3},
  {"index":2,"goal":"化归","actionType":"reduction","stuckRisk":0.2}
]}''';

    test('注入 lookup 后自定义动作算已知，且标 customAction', () {
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      final chain = parseChain(customReply, lookup: catalog.byKey);
      final custom = chain.steps.first;
      expect(custom.actionType, 'force_diagram');
      expect(custom.knownAction, isTrue);
      expect(custom.customAction, isTrue);
      expect(custom.builtInAction, isFalse);
      expect(chain.unknownActionTypes, isEmpty);
      expect(chain.usedActions.map((a) => a.key),
          <String>['force_diagram', 'reduction']);
    });

    test('不注入 lookup 时保留原串并标记未知，步骤不丢', () {
      final chain = parseChain(customReply);
      final custom = chain.steps.first;
      expect(custom.actionType, 'force_diagram');
      expect(custom.knownAction, isFalse);
      expect(custom.action, isNull);
      expect(custom.builtInAction, isFalse);
      expect(custom.customAction, isFalse);
      expect(chain.unknownActionTypes, <String>['force_diagram']);
      expect(chain.steps.length, 2);
    });

    test('注入 lookup 也不认识的 actionType 仍是未知', () {
      const reply = '{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"quantum_vibes","stuckRisk":0.1}]}';
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      final chain = parseChain(reply, lookup: catalog.byKey);
      expect(chain.steps.single.actionType, 'quantum_vibes');
      expect(chain.steps.single.knownAction, isFalse);
      expect(chain.steps.single.customAction, isFalse);
    });

    test('ParsedChain.fromJson 也接受 lookup（入库读回可重新判定）', () {
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      final stored = parseChain(customReply).toJson();
      final reread = ParsedChain.fromJson(stored, lookup: catalog.byKey);
      expect(reread.steps.first.knownAction, isTrue);
      expect(reread.steps.first.customAction, isTrue);
      expect(reread.steps.first.actionType, 'force_diagram',
          reason: '原始字符串永远保留，lookup 只影响 action 映射');
      // knownAction 是解析时按当前词表算出的派生字段：存的时候没有 overlay
      // 所以是 false，读回时注入 overlay 就变成 true。其余字段原样不动。
      Map<String, Object?> firstStoredStep(Map<String, Object?> json) =>
          (json['steps']! as List<Object?>).first! as Map<String, Object?>;
      expect(firstStoredStep(stored)['knownAction'], isFalse);
      expect(firstStoredStep(reread.toJson())['knownAction'], isTrue);
      expect(reread.summary, 's');
      expect(reread.steps.map((s) => s.goal), <String>['画受力图', '化归']);
    });
  });

  group('parseChain 异常指认第几步与哪个字段', () {
    test('actionType 类型错：message 含步号、字段、原始值，rawSnippet 含整步 JSON', () {
      const reply = '{"summary":"s","steps":['
          '{"index":1,"goal":"a","actionType":"reduction"},'
          '{"index":2,"goal":"b","actionType":42}]}';
      try {
        parseChain(reply);
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, contains('第 2 步'));
        expect(error.message, contains('steps[1]'));
        expect(error.message, contains('actionType'));
        expect(error.message, contains('42'));
        expect(error.rawSnippet, isNotNull);
        expect(error.rawSnippet, contains('"actionType":42'));
      }
    });

    test('actionType 为空：message 指认空字符串与步号', () {
      const reply = '{"summary":"s","steps":['
          '{"index":1,"goal":"a","actionType":""}]}';
      try {
        parseChain(reply);
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, contains('第 1 步'));
        expect(error.message, contains('actionType'));
        expect(error.message, contains('空字符串'));
        expect(error.rawSnippet, contains('actionType'));
      }
    });

    test('缺 goal：message 指认步号且不静默跳过该步', () {
      const reply = '{"summary":"s","steps":['
          '{"index":1,"goal":"a","actionType":"reduction"},'
          '{"index":2,"actionType":"extreme_case"}]}';
      try {
        parseChain(reply);
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, contains('第 2 步'));
        expect(error.message, contains('steps[1]'));
        expect(error.message, contains('goal'));
      }
    });

    test('stuckRisk 类型错不再重复拼字段名', () {
      const reply = '{"summary":"s","steps":[{"index":1,"goal":"a",'
          '"actionType":"reduction","stuckRisk":"高"}]}';
      try {
        parseChain(reply);
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, contains('第 1 步'));
        expect(error.message, contains('stuckRisk 必须是数字'));
        expect(error.message, isNot(contains('stuckRisk.stuckRisk')));
      }
    });

    test('steps 里的非对象步骤指认位置与类型', () {
      try {
        parseChain('{"summary":"s","steps":[{"index":1,"goal":"a",'
            '"actionType":"reduction"},42]}');
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, contains('第 2 步'));
        expect(error.message, contains('42'));
      }
    });
  });

  group('提示词注入合并词表', () {
    test('自定义动作渲染进系统提示词，内置动作仍在', () {
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      final messages = solveThenDecompose(
        questionStem: '一个物体静止在斜面上，求斜面对它的支持力。',
        subjectKey: 'physics',
        capabilityCatalog: catalog.actions,
      );
      final system = messages.first.content!;
      expect(system, contains('force_diagram'));
      expect(system, contains('画受力图'));
      expect(system, contains('把研究对象独立出来'));
      expect(system, contains('reduction'));
      expect(messages.first.role, 'system');
    });

    test('默认提示词不包含用户自定义动作', () {
      final messages = solveThenDecompose(
        questionStem: '一个物体静止在斜面上，求斜面对它的支持力。',
        subjectKey: 'physics',
      );
      final system = messages.first.content!;
      expect(system, isNot(contains('force_diagram')));
      expect(system, isNot(contains('画受力图')));
    });

    test('只注入自定义子集时提示词只渲染子集', () {
      final catalog = catalogOf(<CustomCapabilityAction>[customAction()]);
      final messages = solveThenDecompose(
        questionStem: '题干',
        subjectKey: 'physics',
        capabilityCatalog: catalog.customActions,
      );
      final system = messages.first.content!;
      // 输出契约的 JSON 示例固定用 first_principles，所以只能检查词表段落：
      final catalogSection = system.substring(
        system.indexOf('【能力动作词表】'),
        system.indexOf('【输出契约】'),
      );
      expect(catalogSection, contains('force_diagram'));
      expect(catalogSection, isNot(contains('first_principles')));
    });
  });
}
