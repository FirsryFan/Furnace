// 学生提问 → 按内容组织回答（P0 B11）的纯 domain 测试。
//
// 这里钉的是行为契约，不是措辞：
// 1) 问题里的字面线索能命中 DAG 节点（怎么判 C / 公式 / 多节点）；
// 2) 没有对应内容时明确说“这题没有直接对应内容”，不编、不串到别的题；
// 3) 错因按字面线索挑选，泛问“易错点”时给本题记录的条目；
// 4) 短追问继承上一轮上文；
// 5) 输出里不出现开发者/证据/信任字段，也不出现节点 id。
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/design_board/domain/design_board.dart';
import 'package:furnace/features/design_board/domain/feedback_answer_composer.dart';

const String _stem = '1. 一同学将铅球水平推出，不计空气阻力和转动的影响，铅球在平抛运动过程中（ ） '
    'A. 机械能一直增加 B. 加速度保持不变 C. 速度大小保持不变 D. 被推出后瞬间动能最大';

List<DagNode> _physicsNodes() => const <DagNode>[
      DagNode(
        id: 'N-01',
        kind: 'condition',
        role: 'read_question',
        label: '审题：一个过程、四条结论、三条前提',
        body: '过程是平抛，前提是平抛 ⇒ 初速度水平、只受重力；“被推出后瞬间”就是 t=0。',
        stepType: 'thinking',
        formulas: <String>['t=0:\\ v_y=0'],
        keyQuantities: <String>['v0：水平初速度（全程不变）'],
        result: '过程=离手到落地；前提=只受重力',
      ),
      DagNode(
        id: 'N-02',
        kind: 'formula_or_model',
        role: 'construct',
        label: '建模：平抛 = 水平匀速 + 竖直自由落体',
        body: '水平方向 vx=v0 全程不变；竖直方向 vy=gt 线性增大；速度大小 '
            'v(t)=√(v0²+g²t²)。',
        stepType: 'derivation',
        formulas: <String>['v_x=v_0', 'v_y=gt', 'v(t)=\\sqrt{v_0^2+g^2t^2}'],
        keyQuantities: <String>['vx=v0：水平分速度（不变）', 'vy=gt：竖直分速度（从 0 增大）'],
        result: 'vx=v0、vy=gt、a=g；速度大小与动能由 v(t) 决定',
      ),
      DagNode(
        id: 'N-03',
        kind: 'check',
        role: 'judge',
        label: '判 B：合力恒为重力 ⇒ a=g 不变（B 成立）',
        body: '只受重力，合力 F=mg 是恒矢量；由牛顿第二定律 a=F/m=g，大小方向都不变。',
        stepType: 'derivation',
        formulas: <String>['\\vec a=\\frac{\\vec F}{m}=\\vec g'],
        keyQuantities: <String>['a=g：恒矢量'],
        result: 'B 真',
      ),
      DagNode(
        id: 'N-04',
        kind: 'check',
        role: 'exclude',
        label: '判 A：只有重力做功 ⇒ 机械能守恒（A 假）',
        body: '只有重力做功，动能确实变大，但重力势能同幅减小，机械能总量守恒。',
        stepType: 'derivation',
        formulas: <String>['\\Delta(E_k+E_p)=0'],
        keyQuantities: <String>['E=Ek+Ep：机械能（守恒）'],
        result: 'A 假：机械能守恒',
      ),
      DagNode(
        id: 'N-05',
        kind: 'computation',
        role: 'compute',
        label: '判 C、D：v(t) 单调增大 ⇒ 推出瞬间最小（C、D 假）',
        body: 'v(t)=√(v0²+g²t²) 随 t 单调增大，所以速度大小从 v0 起单调增大；'
            '动能最小值在 t=0，而不是最大。',
        stepType: 'derivation',
        formulas: <String>['v(t)=\\sqrt{v_0^2+g^2t^2}'],
        keyQuantities: <String>['Ek(0)=½mv0²：过程最小动能'],
        result: 'C 假、D 假',
      ),
      DagNode(
        id: 'N-06',
        kind: 'conclusion',
        role: 'conclude',
        label: '收口：唯一成立项是 B',
        body: '四项判完，只有 B 与平抛模型相容。',
        stepType: 'derivation',
        formulas: <String>[],
        keyQuantities: <String>['唯一真项：B'],
        result: '答案 B',
      ),
    ];

const List<String> _physicsErrorCauses = <String>[
  '混淆“水平分速度不变”与“速度大小不变”，错选 C。；'
      '根因：平抛速度分解只记住“水平匀速”，没有把合速度矢量式写出来。；'
      '补救：写出 v(t)，取 t=0、t=1 s 两点比较合速度大小。',
  '把“动能越来越大”直接当成“机械能一直增加”，错选 A。；'
      '根因：机械能=动能+重力势能，漏掉重力势能项。；'
      '补救：做 1 道“机械能分项填表”任务。',
];

void main() {
  const composer = FeedbackAnswerComposer();

  group('FeedbackAnswerComposer 命中', () {
    test('命中单节点：为什么 C 不对 → 判 C 的节点 + 选项 C 的错因', () {
      final answer = composer.ask(
        question: '为什么 C 不对？',
        stem: _stem,
        nodes: _physicsNodes(),
        errorCauses: _physicsErrorCauses,
        answer: 'B',
      );

      expect(answer.matched, isTrue);
      expect(answer.steps, isNotEmpty);
      expect(
        answer.steps.any((step) => step.label.contains('判 C')),
        isTrue,
        reason: '应引到判 C 的节点：${answer.steps.map((s) => s.label)}',
      );
      // 选项 C 的题干原文（速度大小保持不变）参与匹配，错因也要挑到。
      expect(answer.mistakes, isNotEmpty);
      expect(answer.mistakes.first.title, contains('速度大小'));
      expect(answer.mistakes.first.rootCause, isNotEmpty);
      expect(answer.mistakes.first.remedy, isNotEmpty);

      final text = answer.toPlainText();
      expect(text, contains('你问的是：“为什么 C 不对？”'));
      expect(text, contains('相关步骤与公式'));
      expect(text, contains('易错点'));
      expect(text, contains('仍不明白可以继续问。'));
    });

    test('公式意图：问表达式 → 引到含 v(t) 的步骤并带公式', () {
      final answer = composer.ask(
        question: '速度大小的表达式是什么？',
        stem: _stem,
        nodes: _physicsNodes(),
      );

      expect(answer.matched, isTrue);
      expect(answer.intent, FeedbackIntent.formula);
      expect(answer.formulas, isNotEmpty);
      expect(
        answer.formulas.join('|'),
        contains('v(t)'),
        reason: '公式题应引到速度表达式：${answer.formulas}',
      );
      final text = answer.toPlainText();
      expect(text, contains('公式：'));
      expect(text, contains('结论：'));
    });

    test('多节点：一个问题引到多个相关步骤，按 DAG 顺序输出', () {
      final nodes = _physicsNodes();
      final answer = composer.ask(
        question: '速度大小和动能为什么变化？',
        stem: _stem,
        nodes: nodes,
      );

      expect(answer.matched, isTrue);
      expect(answer.steps.length, greaterThanOrEqualTo(2));
      final indices = <int>[
        for (final step in answer.steps)
          nodes.indexWhere((node) => node.label == step.label),
      ];
      expect(indices, isNot(contains(-1)));
      expect(
        indices,
        orderedEquals(<int>[...indices]..sort()),
        reason: '相关步骤按 DAG 节点顺序输出，不按分数乱序',
      );
      expect(answer.steps.length, lessThanOrEqualTo(composer.maxSteps));
    });

    test('错因意图：泛问易错点 → 给本题记录的错因（含根因/补救）', () {
      final answer = composer.ask(
        question: '这题有什么易错点？',
        stem: _stem,
        nodes: _physicsNodes(),
        errorCauses: _physicsErrorCauses,
      );

      expect(answer.intent, FeedbackIntent.mistake);
      expect(answer.mistakes, isNotEmpty);
      expect(answer.mistakes.length, lessThanOrEqualTo(composer.maxMistakes));
      expect(
        answer.mistakes.every((mistake) => mistake.rootCause.isNotEmpty),
        isTrue,
      );
      expect(answer.toPlainText(), contains('根因：'));
      expect(answer.toPlainText(), contains('补救：'));
    });

    test('直接问答案：给出本题答案，不编解释之外的步骤', () {
      final answer = composer.ask(
        question: '这题答案是几？',
        stem: _stem,
        nodes: _physicsNodes(),
        answer: 'B',
      );

      expect(answer.matched, isTrue);
      expect(answer.intent, FeedbackIntent.answer);
      expect(answer.conclusion, contains('本题答案：B'));
      expect(answer.toPlainText(), contains('本题答案：B'));
    });

    test('追问继承上文：短追问仍然命中上一轮的相关节点', () {
      final nodes = _physicsNodes();
      final first = composer.ask(
        question: '为什么 C 不对？',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
      );
      final second = composer.ask(
        question: '那为什么？',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
        priorExchanges: <FeedbackExchange>[
          FeedbackExchange(question: '为什么 C 不对？', answer: first),
        ],
      );

      expect(second.matched, isTrue, reason: '短追问应继承上文的字面线索');
      expect(second.contextQuestion, contains('为什么 C 不对'));
      expect(second.contextQuestion, contains('那为什么'));
      expect(
        second.steps.any((step) => step.label.contains('判 C')),
        isTrue,
      );
    });

    test('追问在“易错点”回答之后仍能回到相关节点（继承上一轮回答内容）', () {
      final nodes = _physicsNodes();
      final first = composer.ask(
        question: '这题有什么易错点？',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
      );
      expect(first.matched, isTrue);
      expect(first.steps, isEmpty, reason: '易错点问题本身不需要 DAG 步骤');

      final second = composer.ask(
        question: '那为什么？',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
        priorExchanges: <FeedbackExchange>[
          FeedbackExchange(question: '这题有什么易错点？', answer: first),
        ],
      );

      expect(second.matched, isTrue, reason: '线索应来自上一轮回答的错因正文');
      expect(second.steps, isNotEmpty);
      expect(second.contextQuestion, contains('易错点'));
    });
    test('短但独立的提问不被当成追问（不继承上一题内容）', () {
      final nodes = _physicsNodes();
      final prior = composer.ask(
        question: '为什么 C 不对？',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
      );
      final standalone = composer.ask(
        question: '机械能守恒',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
      );
      final withPrior = composer.ask(
        question: '机械能守恒',
        stem: _stem,
        nodes: nodes,
        errorCauses: _physicsErrorCauses,
        priorExchanges: <FeedbackExchange>[
          FeedbackExchange(question: '为什么 C 不对？', answer: prior),
        ],
      );

      expect(standalone.matched, isTrue);
      expect(
        standalone.steps.any((step) => step.label.contains('判 A')),
        isTrue,
      );
      expect(withPrior.toPlainText(), standalone.toPlainText());
      expect(
        withPrior.steps.any((step) => step.label.contains('判 C')),
        isFalse,
        reason: '独立问题不应继承上一题的“判 C”线索',
      );
    });
  });

  group('FeedbackAnswerComposer 未命中', () {
    test('与本题无关的问题：明确说没有直接对应内容，不编内容', () {
      final answer = composer.ask(
        question: '唐朝诗人为什么这样写？',
        stem: _stem,
        nodes: _physicsNodes(),
        errorCauses: _physicsErrorCauses,
        answer: 'B',
      );

      expect(answer.matched, isFalse);
      expect(answer.steps, isEmpty);
      expect(answer.conclusion, isNull);
      expect(answer.mistakes, isEmpty);
      expect(answer.noMatchMessage, contains('这题没有直接对应内容'));
      final text = answer.toPlainText();
      expect(text, contains('这题没有直接对应内容'));
      expect(text, isNot(contains('机械能')));
      expect(text, isNot(contains('平抛')));
      expect(text, isNot(contains('本题答案')));
    });

    test('简单题没有 DAG 时：不猜、不冒充有解析', () {
      final answer = composer.ask(
        question: '为什么选 B？',
        stem: _stem,
        nodes: const <DagNode>[],
        answer: 'B',
      );

      expect(answer.matched, isFalse);
      expect(answer.steps, isEmpty);
      expect(answer.conclusion, isNull);
      expect(answer.noMatchMessage, contains('这题没有直接对应内容'));
    });

    test('空问题：只提示还没有问题，不假装命中', () {
      final answer = composer.ask(
        question: '   ',
        stem: _stem,
        nodes: _physicsNodes(),
      );

      expect(answer.matched, isFalse);
      expect(answer.restatement, contains('你还没有写下问题'));
      expect(answer.steps, isEmpty);
    });

    test('空题干 + 空节点：不崩、不编', () {
      final answer = composer.ask(
        question: '这题怎么想？',
        stem: '',
        nodes: const <DagNode>[],
      );

      expect(answer.matched, isFalse);
      expect(answer.noMatchMessage, contains('这题没有直接对应内容'));
    });
  });

  group('学生口径边界', () {
    test('不泄露开发者字段：输出里没有 trust/hash/evidence/Source/节点 id', () {
      final nodes = <DagNode>[
        const DagNode(
          id: 'N-DEV-01',
          kind: 'check',
          role: 'judge',
          label: '判 B：加速度不变（B 成立）',
          body: 'trust=B_independently_verified；hash=abc123；evidence 23 条；'
              'Source 为第三方答案 docx；expert_authored，DAG 未独立审核。',
          stepType: 'derivation',
          formulas: <String>['a=g'],
          keyQuantities: <String>['a=g：恒矢量'],
          result: 'B 真',
        ),
      ];
      final answer = composer.ask(
        question: '加速度为什么不变？',
        stem: _stem,
        nodes: nodes,
      );

      expect(answer.matched, isTrue);
      final text = answer.toPlainText();
      for (final token in <String>[
        'trust',
        'hash',
        'abc123',
        'evidence',
        'Source',
        'expert_authored',
        '未独立审核',
        'B_independently_verified',
        'N-DEV-01',
      ]) {
        expect(text, isNot(contains(token)), reason: '输出泄露了 "$token"');
      }
      expect(answer.steps.every((step) => !step.label.contains('N-')), isTrue);
    });

    test('开发者 token 清洗不吞掉正常公式', () {
      final answer = composer.ask(
        question: '速度表达式是什么？',
        stem: _stem,
        nodes: _physicsNodes(),
      );
      expect(
        answer.formulas.join('|'),
        contains('v(t)'),
        reason: '清洗不能把公式洗没：${answer.formulas}',
      );
    });
  });
}
