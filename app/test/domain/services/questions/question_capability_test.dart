import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_capability.dart';

void main() {
  group('QuestionCapability 词表', () {
    test('恰好十个能力，编号按 A1–A10 顺序', () {
      expect(QuestionCapability.values, hasLength(10));
      expect(
        QuestionCapability.values.map((capability) => capability.code).toList(),
        const <String>[
          'A1',
          'A2',
          'A3',
          'A4',
          'A5',
          'A6',
          'A7',
          'A8',
          'A9',
          'A10'
        ],
      );
    });

    test('每项编号唯一，中文名与判定口径非空', () {
      final codes = QuestionCapability.values
          .map((capability) => capability.code)
          .toSet();
      expect(codes, hasLength(10));
      for (final capability in QuestionCapability.values) {
        expect(capability.labelZh.trim(), isNotEmpty);
        expect(capability.definitionZh.trim(), isNotEmpty);
      }
    });

    test('中文名与规格第 5.6 节原文一致', () {
      const expected = <String, String>{
        'A1': '语言解码',
        'A2': '信息定位与提取',
        'A3': '逻辑与论证',
        'A4': '结构化建模',
        'A5': '计算与估算',
        'A6': '图表与图像',
        'A7': '转化与等价',
        'A8': '实验与证据设计',
        'A9': '表达与压缩',
        'A10': '自我监控',
      };
      for (final capability in QuestionCapability.values) {
        expect(capability.labelZh, expected[capability.code]);
      }
    });

    test('一句话判定口径与规格第 5.6 节原文一致', () {
      const expected = <String, String>{
        'A1': '词汇 / 句法 / 术语 / 文本结构',
        'A2': '从材料找证据句 / 图表数据',
        'A3': '因果、充分必要、反例、归谬、削弱加强',
        'A4': '情境→方程 / 图式 / 模型',
        'A5': '运算、量纲、有效数字、近似',
        'A6': '读图、图像→代数、趋势判断',
        'A7': '同义改写、换元、数形结合、选项↔原文',
        'A8': '变量控制、对照、误差、方案评价',
        'A9': '概括、翻译、写作、讲清楚',
        'A10': '检查、时间分配、边界条件',
      };
      for (final capability in QuestionCapability.values) {
        expect(capability.definitionZh, expected[capability.code]);
      }
    });

    test('fromCode 容忍首尾空白与大小写', () {
      expect(QuestionCapability.fromCode('A3'), QuestionCapability.a3);
      expect(QuestionCapability.fromCode('a3'), QuestionCapability.a3);
      expect(QuestionCapability.fromCode(' A3 '), QuestionCapability.a3);
      expect(QuestionCapability.fromCode('a10'), QuestionCapability.a10);
      expect(QuestionCapability.fromCode(' A10 '), QuestionCapability.a10);
    });

    test('fromCode 对未知与空输入返回 null', () {
      expect(QuestionCapability.fromCode(null), isNull);
      expect(QuestionCapability.fromCode(''), isNull);
      expect(QuestionCapability.fromCode('   '), isNull);
      expect(QuestionCapability.fromCode('A'), isNull);
      expect(QuestionCapability.fromCode('A0'), isNull);
      expect(QuestionCapability.fromCode('A11'), isNull);
      expect(QuestionCapability.fromCode('A01'), isNull);
      expect(QuestionCapability.fromCode('B1'), isNull);
    });
  });

  group('capabilityCodesFromJson 归一化', () {
    test('null 返回空列表', () {
      expect(capabilityCodesFromJson(null), isEmpty);
    });

    test('单个字符串视为一个编号', () {
      expect(capabilityCodesFromJson('a3'), const <String>['A3']);
      expect(capabilityCodesFromJson(' A3 '), const <String>['A3']);
    });

    test('非法编号与非字符串元素被丢弃', () {
      expect(
        capabilityCodesFromJson(<Object?>['A3', 'X', '', 'A99', 'A0', 3, null]),
        const <String>['A3'],
      );
      expect(capabilityCodesFromJson('不是能力'), isEmpty);
    });

    test('去重后按 A 序号升序，A10 排在 A2 之后', () {
      expect(
        capabilityCodesFromJson(<Object?>['A10', 'A2', 'a2', ' A1 ', 'A10']),
        const <String>['A1', 'A2', 'A10'],
      );
    });

    test('Set 输入同样按 A 序号排序', () {
      expect(
        capabilityCodesFromJson(<String>{'A2', 'A1'}),
        const <String>['A1', 'A2'],
      );
    });

    test('非列表非字符串的 JSON 形状返回空', () {
      expect(capabilityCodesFromJson(42), isEmpty);
      expect(capabilityCodesFromJson(<String, Object?>{'capability': 'A1'}),
          isEmpty);
      expect(capabilityCodesFromJson(<Object?>[]), isEmpty);
    });

    test('嵌套列表不被展开', () {
      expect(
        capabilityCodesFromJson(<Object?>[
          'A1',
          <String>['A2']
        ]),
        const <String>['A1'],
      );
    });

    test('逗号连接的字符串不做拆分（约定只接受单个编号）', () {
      expect(capabilityCodesFromJson('A1,A3'), isEmpty);
    });

    test('返回列表不可修改', () {
      final codes = capabilityCodesFromJson(<Object?>['A2']);
      expect(
        () => codes.add('A1'),
        throwsUnsupportedError,
      );
    });

    test('输入顺序不影响输出', () {
      final left = capabilityCodesFromJson(<Object?>['A9', 'A3', 'A1']);
      final right = capabilityCodesFromJson(<Object?>['A1', 'A9', 'A3']);
      expect(left, right);
    });
  });

  group('capabilityCodesToJson 写出', () {
    test('写出前同样归一化', () {
      expect(
        capabilityCodesToJson(const <String>['a3', 'A1', 'A3', 'X']),
        const <String>['A1', 'A3'],
      );
    });

    test('空列表写出空不可变列表', () {
      final codes = capabilityCodesToJson(const <String>[]);
      expect(codes, isEmpty);
      expect(() => codes.add('A1'), throwsUnsupportedError);
    });
  });

  group('题型中文标签', () {
    test('五个已知题型 key 有中文名', () {
      expect(kQuestionTypeLabelsZh, hasLength(5));
      expect(questionTypeLabelZh('single_choice'), '单选题');
      expect(questionTypeLabelZh('multi_choice'), '多选题');
      expect(questionTypeLabelZh('fill_blank'), '填空题');
      expect(questionTypeLabelZh('solution'), '解答题');
      expect(questionTypeLabelZh('open'), '开放题');
    });

    test('未知题型 key 原样返回', () {
      expect(questionTypeLabelZh('judge'), 'judge');
      expect(questionTypeLabelZh('essay_question'), 'essay_question');
    });

    test('首尾空白先 trim 再查表', () {
      expect(questionTypeLabelZh(' single_choice '), '单选题');
      expect(questionTypeLabelZh('\topen\n'), '开放题');
    });

    test('空字符串返回空字符串', () {
      expect(questionTypeLabelZh(''), '');
      expect(questionTypeLabelZh('   '), '   ');
    });
  });
}
