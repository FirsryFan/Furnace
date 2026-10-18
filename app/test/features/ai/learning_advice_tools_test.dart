/// 学习建议 AI 工具：只读、与页面同源、参数校验与摘要口径。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/learning_advice_tools.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';

void main() {
  late AppDatabase db;
  late GetLearningAdviceTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tool = GetLearningAdviceTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedQuestion(String id) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: '一道题干足够长的题，用来给建议层提供题数。',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
  }

  Future<void> seedChain({
    required String id,
    required String questionId,
    required List<String> actions,
    List<double?> risks = const <double?>[],
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: id,
            questionId: questionId,
            summary: const Value('一条链'),
            stepCount: Value(actions.length),
            createdAt: 1,
          ),
        );
    for (var i = 0; i < actions.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$id-s$i',
              chainId: id,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(actions[i]),
              stuckRisk: Value(i < risks.length ? risks[i] : null),
              createdAt: 1,
            ),
          );
    }
  }

  ToolInvocation call(Map<String, Object?> arguments) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: arguments,
      );

  Map<String, Object?> mapOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> advicesOf(ToolResult result) {
    final plan = (mapOf(result)['plan']! as Map).cast<String, Object?>();
    return (plan['advices']! as List).cast<Map<String, Object?>>();
  }

  test('空库：给 noData 建议并如实说先去解题', () async {
    final result = await tool.run(call(const <String, Object?>{}));

    expect(result.ok, isTrue);
    final report = mapOf(result);
    expect(report['corpus_question_count'], 0);
    final insights = (report['insights']! as Map).cast<String, Object?>();
    expect(insights['chain_count'], 0);
    final advices = advicesOf(result);
    expect(advices, hasLength(1));
    expect(advices.single['kind'], 'noData');
    expect(result.summary, contains('还没有学习数据'));
  });

  test('已知动作 3 步高风险 → 练习建议排第一，摘要给第一条', () async {
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>[
        'first_principles',
        'first_principles',
        'first_principles'
      ],
      risks: <double?>[0.9, 0.8, 0.7],
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final advices = advicesOf(result);
    expect(advices.first['kind'], 'practiceAction');
    expect(advices.first['action_type'], 'first_principles');
    expect(result.summary, contains('下一步建议'));
    final insights =
        (mapOf(result)['insights']! as Map).cast<String, Object?>();
    expect(insights['high_risk_step_count'], 3);
    expect(insights['chain_count'], 1);
  });

  test('2 步高风险不足默认阈值 → 只给继续练（keepGoing）', () async {
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>['first_principles', 'first_principles'],
      risks: <double?>[0.9, 0.8],
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final advices = advicesOf(result);
    expect(
        advices.map((advice) => advice['kind']).toSet(), <String>{'keepGoing'});
  });

  test('阈值可调：high_risk_min_steps=2 时 2 步也够格', () async {
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>['first_principles', 'first_principles'],
      risks: <double?>[0.9, 0.8],
    );

    final result = await tool.run(
      call(const <String, Object?>{'high_risk_min_steps': 2}),
    );

    final advices = advicesOf(result);
    expect(advices.first['kind'], 'practiceAction');
    final thresholds =
        (mapOf(result)['thresholds']! as Map).cast<String, Object?>();
    expect(thresholds['high_risk_min_steps'], 2);
  });

  test('未知动作 → 扩充词表建议（reviewVocabulary）', () async {
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>['made_up_move', 'made_up_move', 'made_up_move'],
      risks: <double?>[0.9, 0.8, 0.7],
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final advices = advicesOf(result);
    expect(advices.first['kind'], 'reviewVocabulary');
    expect((advices.first['detail_zh']! as String), contains('made_up_move'));
  });

  test('题数多于链覆盖 → 补解题链建议如实说还差几道', () async {
    await seedQuestion('q1');
    await seedQuestion('q2');
    await seedQuestion('q3');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>['first_principles'],
      risks: <double?>[0.2],
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final advices = advicesOf(result);
    final collect =
        advices.singleWhere((advice) => advice['kind'] == 'collectChains');
    expect((collect['detail_zh']! as String), contains('还有 2 道题没有解题链'));
  });

  test('词表 overlay 里的自定义动作被认作已知动作并能给练习建议', () async {
    await CapabilityVocabularyStore(SettingsRepository(db)).save(
      CapabilityActionOverlay.fromJson(<String, Object?>{
        'version': 1,
        'customActions': <Object?>[
          <String, Object?>{'key': 'draw_force_diagram', 'labelZh': '画受力图'},
        ],
      }),
    );
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>[
        'draw_force_diagram',
        'draw_force_diagram',
        'draw_force_diagram',
      ],
      risks: <double?>[0.9, 0.8, 0.7],
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final advices = advicesOf(result);
    expect(advices.first['kind'], 'practiceAction');
    expect(advices.first['action_label_zh'], '画受力图');
  });

  test('max_advices 上限钳制与非法参数', () async {
    final clamped =
        await tool.run(call(const <String, Object?>{'max_advices': 99}));
    final thresholds =
        (mapOf(clamped)['thresholds']! as Map).cast<String, Object?>();
    expect(thresholds['max_advices'], 10);

    await expectLater(
      tool.run(call(const <String, Object?>{'max_advices': 0})),
      throwsA(isA<ToolArgError>().having(
        (error) => error.message,
        'message',
        contains('max_advices 必须是正整数'),
      )),
    );
    await expectLater(
      tool.run(call(const <String, Object?>{'high_risk_min_steps': -1})),
      throwsA(isA<ToolArgError>().having(
        (error) => error.message,
        'message',
        contains('high_risk_min_steps 必须是正整数'),
      )),
    );
  });

  test('工具声明：名称稳定、只读、schema 两个参数', () async {
    expect(tool.name, 'get_learning_advice');
    expect(tool.readOnly, isTrue);
    expect(tool.availableOnCurrentPlatform, isTrue);
    final properties =
        (tool.parameters['properties']! as Map).cast<String, Object?>();
    expect(properties.keys,
        containsAll(<String>['max_advices', 'high_risk_min_steps']));
  });

  test('只读：跑完题库与链的行数不变', () async {
    await seedQuestion('q1');
    await seedChain(
      id: 'c1',
      questionId: 'q1',
      actions: <String>['first_principles'],
      risks: <double?>[0.5],
    );
    final beforeQuestions = await db.select(db.questions).get();
    final beforeChains = await db.select(db.reasoningChains).get();
    final beforeSteps = await db.select(db.reasoningSteps).get();

    await tool.run(call(const <String, Object?>{}));

    expect(
        (await db.select(db.questions).get()).length, beforeQuestions.length);
    expect((await db.select(db.reasoningChains).get()).length,
        beforeChains.length);
    expect(
        (await db.select(db.reasoningSteps).get()).length, beforeSteps.length);
  });
}
