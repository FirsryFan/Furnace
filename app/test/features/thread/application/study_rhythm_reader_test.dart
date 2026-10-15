import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/cognitive/study_rhythm.dart';
import 'package:furnace/features/thread/application/study_rhythm_reader.dart';

/// Q25：`study_rhythm_reader` 是"日志 → 上屏读数"之间唯一的一跳。
///
/// 它要如实回答三件事：开关关掉时**不查库也不给数**、没有坐段时给 `null`
/// （由 UI 说"还没有足够的学习记录"，而不是编一个可用性）、有坐段时用
/// `StudyRhythm` 那套未标定阈值给出读数。复习日志与曝光日志都是"学习动作"。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late SettingsRepository settings;
  late StudyRhythmReader reader;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    settings = SettingsRepository(db);
    reader = StudyRhythmReader(db, settings);
  });

  tearDown(() async {
    await db.close();
  });

  /// 写一条真实的复习日志（走生产写入路径，不手搓 SQL）。
  ///
  /// 单元卡的 `card_template_id` 本来就是 NULL（v2 路径按 `unit_key` 定位，
  /// 见 `review_service.dart` 的注释），而 `review_logs.card_template_id` 有
  /// 外键，所以这里显式建一个模板再写日志。
  Future<void> logReview(DateTime when) async {
    final point = await anki.createKnowledgePoint(
      title: '光合作用',
      content: '场所是叶绿体',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );
    final state = await anki.getOrCreateCardState(template.id);
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt: when.millisecondsSinceEpoch,
    );
  }

  test('开关从没选过（NULL）⇒ 默认显示，且有坐段时给出读数', () async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));

    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isTrue);
    expect(snapshot.hasReading, isTrue);
    expect(snapshot.actionCount, 1);
    final reading = snapshot.reading!;
    expect(reading.advice, StudyAdvice.hard);
    expect(reading.minutesOnRounded, inInclusiveRange(5, 7));
    // 6 分钟时 vig = exp(-6/20) = 0.7408，四舍五入 74%（数学本身在
    // study_rhythm_test.dart 里钉死；这里只要求"默认显示时确实给出了数"）。
    expect(reading.vigilancePercent, inInclusiveRange(73, 75));
  });

  test('曝光日志也算学习动作：只"读过没测"也能凑出坐段', () async {
    await settings.ensureSettings();
    final point =
        await anki.createKnowledgePoint(title: '动量守恒', content: '合外力为零');
    final state = await anki.getOrCreateUnitCardState(point.id, 'unit-1');
    await anki.addExposureLog(
      cardStateId: state.id,
      exposedAt: DateTime.now()
          .subtract(const Duration(minutes: 4))
          .millisecondsSinceEpoch,
    );

    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isTrue);
    expect(snapshot.actionCount, 1);
    expect(snapshot.reading, isNotNull);
  });

  test('最后一条动作已过去超过 15 分钟 ⇒ 没有读数（不编一个可用性）', () async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 40)));

    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isTrue);
    expect(snapshot.actionCount, 1);
    expect(snapshot.reading, isNull);
  });

  test('一条日志都没有 ⇒ 没有读数，但仍然是"开着"', () async {
    await settings.ensureSettings();

    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isTrue);
    expect(snapshot.actionCount, 0);
    expect(snapshot.reading, isNull);
  });

  test('用户关掉 ⇒ 直接返回 hidden（不查日志、不给数）', () async {
    await settings.ensureSettings();
    await settings.updateRhythmHintsEnabled(false);
    // 库里有足够的日志能凑出读数——关掉之后这些一律不算数。
    await logReview(DateTime.now().subtract(const Duration(minutes: 3)));
    await logReview(DateTime.now().subtract(const Duration(minutes: 2)));

    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isFalse);
    expect(snapshot.hasReading, isFalse);
    expect(snapshot.actionCount, 0);
  });

  test('重新打开 ⇒ 读数回来了（开关只是显示开关，不删数据）', () async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 3)));
    await settings.updateRhythmHintsEnabled(false);
    expect((await reader.read(now: DateTime.now())).hasReading, isFalse);

    await settings.updateRhythmHintsEnabled(true);
    final snapshot = await reader.read(now: DateTime.now());

    expect(snapshot.enabled, isTrue);
    expect(snapshot.hasReading, isTrue);
  });
}
