import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/questions/application/question_reasoning_service.dart';

/// 管道 Q4 的验收点（`docs/REASONING_LAYER_DESIGN.md` §4）：
///
///  * 成功：模型回复 → 解析 → 落库，题干**原样**进提示词，选项按顺序带上；
///  * 失败四态（离线 / 模型报错 / 回复不合契约 / 题目不存在）一律返回结果对象，
///    不抛异常，并且尽量留下原文供排查。
void main() {
  /// 一份合规的模型回复。
  const goodReply = '''
{"summary":"先配方，再用二次函数求最值",
 "steps":[
   {"index":1,"goal":"配方成顶点式","actionType":"first_principles",
    "justification":"恒等变形，值域不变","checkMethod":"回代验证","stuckRisk":0.3,
    "knowledgeHints":["二次函数最值"]},
   {"index":2,"goal":"端点与顶点比较","actionType":"sanity_check",
    "justification":"闭区间最值要比较端点","checkMethod":"","stuckRisk":0.7,
    "knowledgeHints":[]}
 ]}
''';

  late AppDatabase db;
  late QuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  QuestionReasoningService serviceWith(ModelAdapter? adapter) =>
      QuestionReasoningService(repository: repo, adapter: adapter);

  Future<String> seedQuestion() async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '求 f(x)=x²-2x+3 在 [0,3] 上的最小值。',
        subjectKey: 'math',
        options: [
          QuestionOptionDraft(label: 'A', content: '2', isCorrect: true),
          QuestionOptionDraft(label: 'B', content: '3', isCorrect: false),
        ],
      ),
    );
    return ingested.question.id;
  }

  test('成功：解析成链并落库，题目状态变成 processed', () async {
    final id = await seedQuestion();
    final result = await serviceWith(FakeModelAdapter([
      FakeModelAdapter.answer(goodReply),
    ])).solveAndDecompose(id, modelId: 'test-model');

    expect(result.ok, isTrue);
    expect(result.savedSteps, 2);
    expect(result.chainId, isNotNull);
    expect(result.persisted, isTrue);

    final chains = await repo.chainsOf(id);
    expect(chains, hasLength(1));
    expect(chains.single.model, 'test-model');
    expect(chains.single.summary, '先配方，再用二次函数求最值');

    final steps = await repo.stepsOf(result.chainId!);
    expect(steps.map((s) => s.idx).toList(), [0, 1]);
    expect(steps.first.actionType, 'first_principles');
    expect(steps.first.goal, '配方成顶点式');
    expect(steps.first.stuckRisk, closeTo(0.3, 1e-9));
    expect(steps.last.actionType, 'sanity_check');

    expect((await repo.byId(id))!.state, 'processed');
  });

  test('save:false 时只解析不落库', () async {
    final id = await seedQuestion();
    final result = await serviceWith(FakeModelAdapter([
      FakeModelAdapter.answer(goodReply),
    ])).solveAndDecompose(id, save: false);

    expect(result.ok, isTrue);
    expect(result.chain, isNotNull);
    expect(result.chainId, isNull);
    expect(await repo.chainsOf(id), isEmpty);
    expect((await repo.byId(id))!.state, isNot('processed'));
  });

  test('没有适配器（离线）→ 失败结果，不抛异常', () async {
    final id = await seedQuestion();
    final result = await serviceWith(null).solveAndDecompose(id);

    expect(result.ok, isFalse);
    expect(result.failureReason, contains('没有可用的模型适配器'));
    expect(await repo.chainsOf(id), isEmpty);
  });

  test('模型报错 → 失败结果里带上已收到的原文片段', () async {
    final id = await seedQuestion();
    final result = await serviceWith(FakeModelAdapter([
      [
        const ModelTextDelta('{"summary":"先配方"'),
        const ModelFailure('HTTP 500', statusCode: 500),
      ],
    ])).solveAndDecompose(id);

    expect(result.ok, isFalse);
    expect(result.failureReason, contains('模型调用失败：HTTP 500'));
    expect(result.rawReply, contains('先配方'));
    expect(await repo.chainsOf(id), isEmpty);
  });

  test('回复不符合契约 → 解析失败但保留原文', () async {
    final id = await seedQuestion();
    final result = await serviceWith(FakeModelAdapter([
      FakeModelAdapter.answer('这道题我不会'),
    ])).solveAndDecompose(id);

    expect(result.ok, isFalse);
    expect(result.failureReason, contains('不符合契约'));
    expect(result.rawReply, '这道题我不会');
    expect(await repo.chainsOf(id), isEmpty);
  });

  test('题目不存在 → notFound', () async {
    final result = await serviceWith(FakeModelAdapter([
      FakeModelAdapter.answer(goodReply),
    ])).solveAndDecompose('q_missing');

    expect(result.ok, isFalse);
    expect(result.questionId, 'q_missing');
    expect(result.failureReason, contains('题目不存在'));
  });

  test('题干原样进提示词，选项按顺序带上，工具表为空', () async {
    final id = await seedQuestion();
    final adapter = FakeModelAdapter([FakeModelAdapter.answer(goodReply)]);
    await serviceWith(adapter).solveAndDecompose(id);

    final request = adapter.requests.single;
    expect(request.tools, isEmpty);
    expect(request.messages, hasLength(2));
    expect(request.messages.first.role, 'system');

    final user = request.messages.last;
    expect(user.role, 'user');
    expect(user.content, contains('求 f(x)=x²-2x+3 在 [0,3] 上的最小值。'));
    expect(user.content, contains('A. 2'));
    expect(user.content, contains('B. 3'));
  });
}
