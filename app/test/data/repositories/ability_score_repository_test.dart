import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ability_score_repository.dart';
import 'package:furnace/domain/services/cognitive/ability_assessment.dart';

/// 能力测评分数的存储（schema v38，轮次一百七十七）。要锁的口径：
///
///  - 只追加：同一项能力多行，historyFor 新→旧、latestByAbility 取最新；
///  - score 写库前 clamp 到 0–100（绕过域层也不让越界值进库）；
///  - metrics 空表落 NULL、读回空表；指标里的 list 值原样往返；
///  - 未知 ability_key 的行不进 latestByAbility（不让旧数据打挂画像页）；
///  - historyFor 的 limit<=0 直接空表、countFor/countAll/deleteAll 的口径。
void main() {
  late AppDatabase db;
  late AbilityScoreRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AbilityScoreRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  DateTime at(int millis) => DateTime.fromMillisecondsSinceEpoch(millis);

  test('record 返回 ab 前缀的 id，空表时读侧都是空', () async {
    expect(await repository.historyFor(AbilityKey.reactionSpeed), isEmpty);
    expect(await repository.latestByAbility(), isEmpty);
    expect(await repository.countFor(AbilityKey.reactionSpeed), 0);
    expect(await repository.countAll(), 0);

    final id = await repository.record(
      key: AbilityKey.reactionSpeed,
      score: 70,
      now: at(1700000000000),
    );
    expect(id, startsWith('ab'));
  });

  test('historyFor 新→旧，同一毫秒按 id 降序（后写的在前）', () async {
    await repository.record(
      key: AbilityKey.reactionSpeed,
      score: 40,
      now: at(1700000000000),
    );
    await repository.record(
      key: AbilityKey.reactionSpeed,
      score: 90,
      now: at(1700000900000),
    );
    await repository.record(
      key: AbilityKey.workingMemory,
      score: 10,
      now: at(1700000500000),
    );

    final history = await repository.historyFor(AbilityKey.reactionSpeed);
    expect(history.map((entry) => entry.score), [90, 40]);
    expect(
        history.every((entry) => entry.key == AbilityKey.reactionSpeed), isTrue,
        reason: '别的能力的行不会混进来');
    expect(await repository.historyFor(AbilityKey.reactionSpeed, limit: 0),
        isEmpty);
    expect(await repository.historyFor(AbilityKey.reactionSpeed, limit: -1),
        isEmpty);
    expect(
      (await repository.historyFor(AbilityKey.reactionSpeed, limit: 1)),
      hasLength(1),
    );
  });

  test('score 写库前 clamp 到 0–100', () async {
    // 显式递增 captured_at：id 是 uuid v4（不是单调递增），同一毫秒写多行时
    // historyFor 的「captured_at DESC, id DESC」次序不稳定 —— 别让测试依赖它。
    await repository.record(
      key: AbilityKey.attentionStability,
      score: 150,
      now: at(1700000000000),
    );
    await repository.record(
      key: AbilityKey.attentionStability,
      score: -5,
      now: at(1700000001000),
    );
    await repository.record(
      key: AbilityKey.attentionStability,
      score: 0,
      now: at(1700000002000),
    );
    await repository.record(
      key: AbilityKey.attentionStability,
      score: 100,
      now: at(1700000003000),
    );

    final history = await repository.historyFor(AbilityKey.attentionStability);
    expect(history.map((entry) => entry.score), [100, 0, 0, 100]);
  });

  test('metrics 往返：空表落 NULL、指标里的 list/int 原样读回', () async {
    await repository.record(
      key: AbilityKey.reactionSpeed,
      score: 80,
      metrics: const <String, Object?>{
        'samples_ms': <int>[250, 300, 275],
        'median_ms': 275,
        'note': 'ok',
      },
    );
    await repository.record(key: AbilityKey.workingMemory, score: 60);

    final latest = await repository.latestByAbility();
    expect(latest[AbilityKey.reactionSpeed]!.metrics['samples_ms'],
        <int>[250, 300, 275]);
    expect(latest[AbilityKey.reactionSpeed]!.metrics['median_ms'], 275);
    expect(latest[AbilityKey.reactionSpeed]!.metrics['note'], 'ok');
    expect(latest[AbilityKey.workingMemory]!.metrics, isEmpty,
        reason: '没给 metrics 就写 NULL、读回空表');
  });

  test('未知 ability_key 的行被 latestByAbility 跳过，但 countAll 仍数它', () async {
    await repository.record(key: AbilityKey.reactionSpeed, score: 70);
    // 手工写一行未来版本/改库留下的 code：画像页不该因为它整页报错。
    await db.into(db.abilityScores).insert(
          AbilityScoresCompanion.insert(
            id: 'legacy-1',
            abilityKey: 'mystery_ability',
            score: 42,
            metricsJson: const Value<String?>('{"x":1}'),
            capturedAt: 1700000000000,
          ),
        );

    final latest = await repository.latestByAbility();
    expect(latest.keys, [AbilityKey.reactionSpeed]);
    expect(await repository.countAll(), 2);
  });

  test('countFor 只数这一项能力；deleteAll 清空全部', () async {
    await repository.record(key: AbilityKey.reactionSpeed, score: 70);
    await repository.record(key: AbilityKey.reactionSpeed, score: 80);
    await repository.record(key: AbilityKey.patternRecognition, score: 55);

    expect(await repository.countFor(AbilityKey.reactionSpeed), 2);
    expect(await repository.countFor(AbilityKey.patternRecognition), 1);
    expect(await repository.countFor(AbilityKey.attentionStability), 0);
    expect(await repository.countAll(), 3);

    expect(await repository.deleteAll(), 3);
    expect(await repository.countAll(), 0);
    expect(await repository.latestByAbility(), isEmpty);
  });
}
