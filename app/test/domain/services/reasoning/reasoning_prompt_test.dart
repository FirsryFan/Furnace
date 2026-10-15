// 「先解题、再拆链」的提示词与解析器测试。
//
// 两侧都测：提示词必须钉住「不许自造题目」和「actionType 取自词表」，解析器必须
// 既能吃下模型爱写的 ```json 包裹，又能在结构真的坏掉时抛出可 catch 的类型化异常。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';

const String _stem = '已知函数 f(x)=x^2-2x+3，求 f(x) 在区间 [0,3] 上的最小值。';

const String _happyJson = '''
{
  "summary": "先配方化成顶点式，再比较顶点与端点",
  "steps": [
    {
      "index": 1,
      "goal": "把 f(x) 配方成 (x-1)^2+2",
      "actionType": "reduction",
      "justification": "配方后单调区间与顶点一目了然，比直接求导更快",
      "checkMethod": "把配方结果展开回原式",
      "stuckRisk": 0.2,
      "knowledgeHints": ["二次函数配方"]
    },
    {
      "index": 2,
      "goal": "比较顶点值与两个端点值",
      "actionType": "extreme_case",
      "justification": "闭区间上的连续函数，最值只可能在端点或顶点取到",
      "checkMethod": "代入 x=0、x=1、x=3 验算",
      "stuckRisk": 0.6,
      "knowledgeHints": ["闭区间最值", "单调性"]
    }
  ]
}
''';

void main() {
  group('solveThenDecompose 提示词', () {
    final messages = solveThenDecompose(
      questionStem: _stem,
      options: const <String>['1', '2', '3', '4'],
      subjectKey: 'math',
    );

    test('产出 system + user 两条消息', () {
      expect(messages.length, 2);
      expect(messages[0].role, 'system');
      expect(messages[1].role, 'user');
      expect(messages[0].images, isEmpty);
      expect(messages[1].images, isEmpty);
    });

    test('user 消息原样带上题干与选项', () {
      final user = messages[1].content!;
      expect(user, contains(_stem));
      expect(user, contains('A. 1'));
      expect(user, contains('B. 2'));
      expect(user, contains('C. 3'));
      expect(user, contains('D. 4'));
    });

    test('选项自带标号时不重复加标号', () {
      final withLabels = solveThenDecompose(
        questionStem: _stem,
        options: const <String>['A. 甲', 'B、乙'],
        subjectKey: 'math',
      );
      final user = withLabels[1].content!;
      expect(user, contains('A. 甲'));
      expect(user, contains('B、乙'));
      expect(user.contains('A. A. 甲'), isFalse);
    });

    test('无选项（非选择题）时不出现选项段', () {
      final noOptions = solveThenDecompose(
        questionStem: _stem,
        subjectKey: 'math',
      );
      expect(noOptions[1].content, isNot(contains('【选项】')));
      expect(noOptions[1].content, contains('【题目】'));
    });

    test('system 消息列出词表里全部 key', () {
      final system = messages[0].content!;
      for (final action in CapabilityAction.catalog) {
        expect(system, contains(action.key),
            reason: '提示词没列出 ${action.key}，模型就没法选它');
      }
      expect(system, contains(CapabilityAction.catalog.first.labelZh));
    });

    test('system 消息逐字禁止自造题目 / 改变题意', () {
      final system = messages[0].content!;
      expect(system, contains('禁止自造题目'));
      expect(system, contains('不得改编、替换、补充、删减或另出任何新题'));
      expect(system, contains('只解用户给出的这一道题'));
      expect(system, contains('不得改变题意'));
      expect(system, contains('题干里的条件、数值、问法一律照原样理解'));
    });

    test('system 消息要求严格 JSON 且 actionType 只能取词表 key', () {
      final system = messages[0].content!;
      expect(system, contains(chainJsonContract));
      expect(system, contains('steps[].actionType 只能取下面这些 key，不得新造'));
      expect(system, contains('区分大小写与下划线'));
    });

    test('system 消息带上科目键与中文名', () {
      expect(messages[0].content, contains('math（数学）'));
      final informatics = solveThenDecompose(
        questionStem: _stem,
        subjectKey: 'informatics',
      );
      expect(informatics[0].content, contains('informatics（信息学竞赛）'));
    });

    test('未知科目键原样透传，不抛异常', () {
      final weird = solveThenDecompose(
        questionStem: _stem,
        subjectKey: 'astrology',
      );
      expect(weird[0].content, contains('astrology（astrology）'));
    });

    test('传入词表子集时只列出子集', () {
      final subset = <CapabilityAction>[
        CapabilityAction.byKey('reduction')!,
        CapabilityAction.byKey('symmetry')!,
      ];
      final scoped = solveThenDecompose(
        questionStem: _stem,
        subjectKey: 'math',
        capabilityCatalog: subset,
      );
      final system = scoped[0].content!;
      expect(system, contains('reduction'));
      expect(system, contains('symmetry'));
      expect(system, isNot(contains('amortized_argument')));
    });

    test('空词表给出兜底说明而不是崩溃', () {
      final empty = solveThenDecompose(
        questionStem: _stem,
        subjectKey: 'math',
        capabilityCatalog: const <CapabilityAction>[],
      );
      expect(empty[0].content, contains('词表为空'));
      expect(empty.length, 2);
    });
  });

  group('parseChain 正常路径', () {
    test('happy path：字段逐个对上', () {
      final chain = parseChain(_happyJson);
      expect(chain.summary, '先配方化成顶点式，再比较顶点与端点');
      expect(chain.steps.length, 2);

      final first = chain.steps[0];
      expect(first.index, 1);
      expect(first.goal, '把 f(x) 配方成 (x-1)^2+2');
      expect(first.actionType, 'reduction');
      expect(first.knownAction, isTrue);
      expect(first.action?.key, 'reduction');
      expect(first.action?.labelZh, '化归');
      expect(first.justification, contains('配方'));
      expect(first.checkMethod, '把配方结果展开回原式');
      expect(first.stuckRisk, 0.2);
      expect(first.knowledgeHints, <String>['二次函数配方']);

      expect(chain.steps[1].actionType, 'extreme_case');
      expect(chain.steps[1].stuckRisk, 0.6);
      expect(chain.usedActions.map((a) => a.key),
          <String>['reduction', 'extreme_case']);
      expect(chain.unknownActionTypes, isEmpty);
    });

    test('容忍 ```json 代码块与前后散文', () {
      const reply = '好的，我先解题。\n```json\n$_happyJson\n```\n以上是我的思路。';
      final chain = parseChain(reply);
      expect(chain.steps.length, 2);
      expect(chain.steps[0].actionType, 'reduction');
    });

    test('容忍无语言标注的代码块与纯前后散文', () {
      expect(parseChain('```\n$_happyJson\n```').steps, hasLength(2));
      expect(parseChain('思路如下：$_happyJson 完毕。').steps, hasLength(2));
    });

    test('summary 缺失时留空字符串（不因概括缺失而失败）', () {
      final chain = parseChain(
        '{"steps":[{"index":1,"goal":"配方法","actionType":"reduction",'
        '"stuckRisk":0.1}]}',
      );
      expect(chain.summary, '');
      expect(chain.steps.single.justification, '');
      expect(chain.steps.single.checkMethod, '');
      expect(chain.steps.single.knowledgeHints, isEmpty);
    });

    test('stuckRisk 缺失时取中性默认值 0.5', () {
      final chain = parseChain(
        '{"summary":"s","steps":[{"index":1,"goal":"g","actionType":"reduction"}]}',
      );
      expect(chain.steps.single.stuckRisk, defaultStuckRisk);
      expect(defaultStuckRisk, 0.5);
    });

    test('steps[] 里的 index 接受整数值的 double', () {
      final chain = parseChain(
        '{"summary":"s","steps":[{"index":1.0,"goal":"g","actionType":"symmetry",'
        '"stuckRisk":0}]}',
      );
      expect(chain.steps.single.index, 1);
    });

    test('toJson 能原样带走结果，可直接交给存储层', () {
      final json = parseChain(_happyJson).toJson();
      final encoded = jsonEncode(json);
      final round = ParsedChain.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(round.steps.length, 2);
      expect(round.steps[0].actionType, 'reduction');
      expect(round.steps[0].knownAction, isTrue);
      expect(round.steps[1].stuckRisk, 0.6);
      expect(round.summary, parseChain(_happyJson).summary);
    });
  });

  group('parseChain 未知动作类型', () {
    test('未知 actionType 保留原字符串并标记 knownAction=false', () {
      const reply = '''
{"summary":"s","steps":[
  {"index":1,"goal":"用某种没人建模过的方法","actionType":"quantum_vibes",
   "justification":"直觉","checkMethod":"","stuckRisk":0.4,
   "knowledgeHints":[]}
]}''';
      final chain = parseChain(reply);
      final step = chain.steps.single;
      expect(step.actionType, 'quantum_vibes');
      expect(step.knownAction, isFalse);
      expect(step.action, isNull);
      expect(chain.unknownActionTypes, <String>['quantum_vibes']);
      expect(step.toJson()['knownAction'], false);
      expect(step.toJson()['actionType'], 'quantum_vibes');
    });

    test('已知与未知混排时两边都不丢', () {
      const reply = '''
{"summary":"s","steps":[
  {"index":1,"goal":"a","actionType":"reduction","stuckRisk":0.1},
  {"index":2,"goal":"b","actionType":"quantum_vibes","stuckRisk":0.2},
  {"index":3,"goal":"c","actionType":"reduction","stuckRisk":0.3}
]}''';
      final chain = parseChain(reply);
      expect(chain.steps.map((s) => s.knownAction), <bool>[true, false, true]);
      expect(chain.usedActions.map((a) => a.key), <String>['reduction']);
      expect(chain.unknownActionTypes, <String>['quantum_vibes']);
    });
  });

  group('parseChain 结构错误一律抛 ReasoningParseException', () {
    void expectThrows(String reply, {String? reason}) {
      expect(
        () => parseChain(reply),
        throwsA(isA<ReasoningParseException>()),
        reason: reason,
      );
    }

    test('空回复', () {
      expectThrows('');
      expectThrows('   \n\t ');
    });

    test('非 JSON 的散文', () {
      expectThrows('对不起，这道题我无法作答。');
      expectThrows('```json\n不好意思，我做不到\n```');
    });

    test('JSON 语法错误', () {
      expectThrows('{"summary":"s","steps":[}');
    });

    test('顶层不是对象', () {
      expectThrows('[1,2,3]');
      expectThrows('"just a string"');
    });

    test('steps 缺失 / 类型错 / 为空', () {
      expectThrows('{"summary":"s"}');
      expectThrows('{"summary":"s","steps":{}}');
      expectThrows('{"summary":"s","steps":[]}');
    });

    test('summary 类型错', () {
      expectThrows('{"summary":42,"steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction"}]}');
    });

    test('单个步骤不是对象', () {
      expectThrows('{"summary":"s","steps":[42]}');
    });

    test('一个坏步骤就整条失败：缺 goal', () {
      const reply = '''
{"summary":"s","steps":[
  {"index":1,"goal":"配方法","actionType":"reduction","stuckRisk":0.2},
  {"index":2,"actionType":"extreme_case","stuckRisk":0.3}
]}''';
      expectThrows(reply, reason: '缺 goal 的步骤必须被发现，而不是静默跳过');
    });

    test('一个坏步骤就整条失败：actionType 缺失或为空', () {
      expectThrows(
          '{"summary":"s","steps":[{"index":1,"goal":"g","actionType":""}]}');
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g"}]}');
    });

    test('index 不是整数', () {
      expectThrows('{"summary":"s","steps":[{"index":"一","goal":"g",'
          '"actionType":"reduction"}]}');
      expectThrows('{"summary":"s","steps":[{"goal":"g",'
          '"actionType":"reduction"}]}');
    });

    test('stuckRisk 越界或类型错', () {
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction","stuckRisk":1.5}]}');
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction","stuckRisk":-0.1}]}');
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction","stuckRisk":"高"}]}');
    });

    test('knowledgeHints 类型错', () {
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction","knowledgeHints":"配方"}]}');
      expectThrows('{"summary":"s","steps":[{"index":1,"goal":"g",'
          '"actionType":"reduction","knowledgeHints":[1,2]}]}');
    });

    test('异常携带可读信息与原文片段', () {
      try {
        parseChain('这不是 JSON');
        fail('应当抛出 ReasoningParseException');
      } on ReasoningParseException catch (error) {
        expect(error.message, isNotEmpty);
        expect(error.rawSnippet, isNotNull);
        expect(error.toString(), contains('ReasoningParseException'));
      }
    });
  });
}
