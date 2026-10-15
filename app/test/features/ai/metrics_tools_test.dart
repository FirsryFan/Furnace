import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/metrics_tools.dart';

/// `review_metrics` 是"复习效果"的只读工具（Q16 标定协议 v1 的工具面），验收点：
///
///  1. **只读**：不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **诚实**：没有预测样本、样本不足 30 条时，摘要里明说"算不出来/不补算"，
///     而**不是**给一个看起来像结论的偏置；
///  3. 留存率分桶、Brier/ECE、标定偏置都来自同一批复习（`calibration_reader.dart`）；
///  4. 边界：空库、`since_days` 过滤、`limit` 截断、参数非法。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewMetricsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    tool = ReviewMetricsTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Map<String, Object?> payloadOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  Map<String, Object?> calibrationOf(ToolResult result) =>
      payloadOf(result)['calibration']! as Map<String, Object?>;

  /// 一张真的卡（知识点 → 模板 → 卡状态），复习日志要挂在它上面。
  Future<({String stateId, String templateId})> seedCard(
    String title,
  ) async {
    final point = await anki.createKnowledgePoint(title: title, content: '');
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: 'Q',
      answer: 'A',
    );
    final state = await anki.getOrCreateCardState(template.id);
    return (stateId: state.id, templateId: template.id);
  }

  /// 写一条复习：`rating 2` = 记得，`0` = 忘记（`recalledFromReview` 的旧评分口径）。
  Future<void> seedReview({
    required ({String stateId, String templateId}) card,
    required bool recalled,
    required int reviewedAtMs,
    double? predictedR,
  }) async {
    await anki.addReviewLog(
      cardStateId: card.stateId,
      cardTemplateId: card.templateId,
      rating: recalled ? 2 : 0,
      reviewedAt: reviewedAtMs,
      predictedR: predictedR,
    );
  }

  /// 复习日志 + 卡状态的整库指纹：只读工具不该让任何一行变化。
  Future<List<String>> snapshot() async {
    final logs = await db.select(db.reviewLogs).get();
    final states = await db.select(db.cardStates).get();
    return [
      for (final log in logs)
        'l:${log.id}:${log.rating}:${log.predictedR}:${log.reviewedAt}',
      for (final state in states)
        's:${state.id}:${state.repetitions}:${state.dueAt}:${state.updatedAt}',
    ];
  }

  group('read-only by construction', () {
    test('ApprovalEngine never asks per call, in any mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isTrue);
        expect(
          decision.disposition,
          isNot(ToolDisposition.individualApproval),
          reason: 'mode ${mode.name} must not ask one by one for a read',
        );
      }
      expect(tool.readOnly, isTrue);
      expect(tool.riskFor(''), ToolRisk.write); // unused: no actions
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('a call leaves every table untouched', () async {
      final card = await seedCard('光合作用');
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 40; i++) {
        await seedReview(
          card: card,
          recalled: i % 3 != 0,
          reviewedAtMs: base - i * 60000,
          predictedR: 0.7,
        );
      }

      final before = await snapshot();
      final result = await tool.run(invoke({}));

      expect(result.ok, isTrue);
      expect(await snapshot(), before,
          reason: 'the tool must not write: same rows, same values');
    });
  });

  group('没有数字可讲的时候', () {
    test('空库 → ok 但明说没有记录', () async {
      final result = await tool.run(invoke({}));
      final payload = payloadOf(result);

      expect(result.ok, isTrue);
      expect(payload['reviewed'], 0);
      expect(payload['recalled'], 0);
      expect(payload['calibrated_samples'], 0);
      expect(result.summary, contains('还没有记录'));
      expect(result.summary, contains('我不会编一个'));
      expect(calibrationOf(result)['verdict'], 'no_samples');
      expect(calibrationOf(result)['usable'], isFalse);
    });

    test('有复习但没有预测 → 只有留存率，并说明历史不补算', () async {
      final card = await seedCard('细胞呼吸');
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 20; i++) {
        await seedReview(
          card: card,
          recalled: i.isEven,
          reviewedAtMs: base - i * 3600000,
        );
      }

      final result = await tool.run(invoke({}));
      final payload = payloadOf(result);

      expect(result.ok, isTrue);
      expect(payload['reviewed'], 20);
      expect(payload['recalled'], 10);
      expect(payload['calibrated_samples'], 0);
      expect(payload['brier'], isNull);
      expect(calibrationOf(result)['verdict'], 'no_samples');
      expect(result.summary, contains('不补算'));
      expect(result.summary, contains('只有留存率'));
    });

    test('带预测但不足 30 条 → 转达"样本不足"，不给系数', () async {
      final card = await seedCard('光合作用');
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 10; i++) {
        await seedReview(
          card: card,
          recalled: i.isEven,
          reviewedAtMs: base - i * 60000,
          predictedR: 0.6,
        );
      }

      final result = await tool.run(invoke({}));
      final calibration = calibrationOf(result);

      expect(result.ok, isTrue);
      expect(payloadOf(result)['calibrated_samples'], 10);
      expect(calibration['verdict'], 'too_few_samples');
      expect(calibration['usable'], isFalse);
      expect(calibration['fit'], isNull);
      expect(calibration['refusal'] as String, contains('30'));
      expect(result.summary, contains('样本不足'));
    });
  });

  group('有样本时给出的读数', () {
    /// 40 条带预测的复习：预测 0.6 的那半只有 30% 记住、预测 0.8 的那半 55%
    /// —— 实际比预测低，也就是"系统性过度自信"。
    Future<void> seedOverconfident() async {
      final card = await seedCard('动量守恒');
      final base = DateTime.now().millisecondsSinceEpoch;
      var index = 0;
      for (final (predicted, positives) in const [(0.6, 6), (0.8, 11)]) {
        for (var k = 0; k < 20; k++) {
          await seedReview(
            card: card,
            recalled: k < positives,
            reviewedAtMs: base - index * 60000,
            predictedR: predicted,
          );
          index++;
        }
      }
    }

    test('过度自信 → 负偏置、Brier/ECE 与偏置一起给', () async {
      await seedOverconfident();

      final result = await tool.run(invoke({}));
      final payload = payloadOf(result);
      final calibration = calibrationOf(result);
      final fit = calibration['fit']! as Map<String, Object?>;

      expect(result.ok, isTrue);
      expect(payload['reviewed'], 40);
      expect(payload['calibrated_samples'], 40);
      expect(payload['brier'], isNotNull);
      expect(payload['ece'], isNotNull);
      expect(calibration['usable'], isTrue);
      expect(calibration['verdict'], 'ok');
      expect(fit['intercept'] as double, lessThan(0));
      expect(calibration['samples'], 40);
      expect(result.summary, contains('过度自信'));
      expect(result.summary, contains('Brier'));
    });

    test('默认返回留存分桶与校准分箱明细', () async {
      await seedOverconfident();

      final withBuckets = payloadOf(await tool.run(invoke({})));
      expect(withBuckets['buckets'], isA<List<Object?>>());
      expect(withBuckets['bins'], isA<List<Object?>>());

      final without =
          payloadOf(await tool.run(invoke({'include_buckets': false})));
      expect(without.containsKey('buckets'), isFalse);
      expect(without.containsKey('bins'), isFalse);
    });

    test('间隔分桶：同一条卡隔几天再复习会进桶', () async {
      final card = await seedCard('光合作用');
      final base = DateTime.now().millisecondsSinceEpoch;
      const day = 24 * 3600 * 1000;
      // 三次复习：0 天、+1 天、+5 天 → 两条间隔（1 天、4 天）。
      await seedReview(
          card: card, recalled: true, reviewedAtMs: base - 6 * day);
      await seedReview(
          card: card, recalled: false, reviewedAtMs: base - 5 * day);
      await seedReview(card: card, recalled: true, reviewedAtMs: base);

      final payload = payloadOf(await tool.run(invoke({})));
      final buckets = payload['buckets']! as List<Object?>;
      final informative = [
        for (final bucket in buckets)
          if ((bucket! as Map<String, Object?>)['samples'] as int > 0) bucket,
      ];

      expect(payload['reviewed'], 3);
      expect(informative, hasLength(2));
      expect(
        firstBucketOf(informative).keys,
        containsAll(['lo_days', 'hi_days', 'samples', 'retention']),
      );
    });
  });

  group('参数与边界', () {
    test('since_days 只看窗口内的复习', () async {
      final card = await seedCard('光合作用');
      final now = DateTime.now().millisecondsSinceEpoch;
      const day = 24 * 3600 * 1000;
      for (var i = 0; i < 5; i++) {
        await seedReview(
          card: card,
          recalled: true,
          reviewedAtMs: now - i * 60000,
          predictedR: 0.7,
        );
      }
      for (var i = 0; i < 5; i++) {
        await seedReview(
          card: card,
          recalled: false,
          reviewedAtMs: now - (90 + i) * day,
          predictedR: 0.9,
        );
      }

      final recent = payloadOf(await tool.run(invoke({'since_days': 7})));
      final all = payloadOf(await tool.run(invoke({})));

      expect(recent['reviewed'], 5);
      expect(recent['since_days'], 7);
      expect(all['reviewed'], 10);
      expect(all['since_days'], isNull);
    });

    test('limit 截断读取条数', () async {
      final card = await seedCard('光合作用');
      final base = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 10; i++) {
        await seedReview(
          card: card,
          recalled: true,
          reviewedAtMs: base - i * 60000,
        );
      }

      final payload = payloadOf(await tool.run(invoke({'limit': 3})));
      expect(payload['reviewed'], 3);
      expect(payload['limit'], 3);
    });

    test('非法参数 → 失败并说明怎么改', () async {
      final negative = await tool.run(invoke({'since_days': -1}));
      expect(negative.ok, isFalse);
      expect(negative.error, contains('since_days'));

      final zeroBins = await tool.run(invoke({'calibration_bin_count': 0}));
      expect(zeroBins.ok, isFalse);
      expect(zeroBins.error, contains('calibration_bin_count'));

      final manyBins = await tool.run(invoke({
        'calibration_bin_count': ReviewMetricsTool.maxBinCount + 1,
      }));
      expect(manyBins.ok, isFalse);
      expect(manyBins.error, contains('${ReviewMetricsTool.maxBinCount}'));
    });
  });

  group('注册与 schema', () {
    test('在 ToolRegistry.forApp 里可达，且声明是只读的', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      expect(registry.byName('review_metrics'), isA<ReviewMetricsTool>());
      expect(
        registry.forCurrentPlatform.map((t) => t.name),
        contains('review_metrics'),
      );

      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      expect(spec.description, contains('只读'));
      expect(spec.parameters['type'], 'object');
      expect(
        (spec.parameters['properties']! as Map<String, Object?>).keys,
        containsAll([
          'since_days',
          'calibration_bin_count',
          'include_buckets',
          'limit',
        ]),
      );
    });
  });
}

/// 分桶明细里第一条（`RetentionBucket.toJson()` 的键）。
Map<String, Object?> firstBucketOf(List<Object?> buckets) =>
    buckets.first! as Map<String, Object?>;
