import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';

/// Covers `AnkiRepository.updateModelState` only - the narrow write seam of
/// decision D2 (the cognitive model owns `encoding_strength` / `savings`, FSRS
/// keeps `stability` / `difficulty` / `dueAt`).
///
/// The point of these tests is that "it only writes two columns" is **measured**
/// rather than asserted in a comment: every other column is compared field by
/// field against a row seeded at a distinctive value, and `updatedAt` is
/// included in that comparison on purpose (a convenience `updatedAt` bump would
/// put a second writer on a column this method does not own).
void main() {
  late AppDatabase db;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<CardState> readRow() {
    final query = db.select(db.cardStates)..where((t) => t.id.equals('cs-1'));
    return query.getSingle();
  }

  Future<CardState> seedRow() async {
    final kp = await anki.createKnowledgePoint(
      title: '动量守恒',
      content: '系统不受外力时总动量不变。',
    );
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs-1',
            knowledgePointId: Value(kp.id),
            unitKey: const Value('cloze:slot-1'),
            state: const Value('review'),
            dueAt: const Value(1700000000000),
            intervalDays: const Value(12.5),
            ease: const Value(2.9),
            repetitions: const Value(3),
            lapses: const Value(1),
            forced: const Value(1),
            forcedStreak: const Value(2),
            lastReviewedAt: const Value(1699000000000),
            stability: const Value(41.25),
            difficulty: const Value(5.5),
            encodingStrength: const Value(0.6),
            savings: const Value(0.7),
            createdAt: 1111,
            updatedAt: 2222,
          ),
        );
    return readRow();
  }

  /// Every column except the two the model owns, compared one by one.
  void expectEverythingElseUnchanged(CardState before, CardState after) {
    expect(after.id, before.id);
    expect(after.cardTemplateId, before.cardTemplateId);
    expect(after.knowledgePointId, before.knowledgePointId);
    expect(after.unitKey, before.unitKey);
    expect(after.state, before.state);
    expect(after.dueAt, before.dueAt);
    expect(after.intervalDays, before.intervalDays);
    expect(after.ease, before.ease);
    expect(after.repetitions, before.repetitions);
    expect(after.lapses, before.lapses);
    expect(after.forced, before.forced);
    expect(after.forcedStreak, before.forcedStreak);
    expect(after.lastReviewedAt, before.lastReviewedAt);
    expect(after.stability, before.stability);
    expect(after.difficulty, before.difficulty);
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt, before.updatedAt);
  }

  group('updateModelState (D2 narrow write)', () {
    test('writes only encoding_strength and savings, every other column equal',
        () async {
      final before = await seedRow();
      expect(before.encodingStrength, 0.6);
      expect(before.savings, 0.7);

      await anki.updateModelState('cs-1', encodingStrength: 0.42, savings: 0.81);

      final after = await readRow();
      expectEverythingElseUnchanged(before, after);
      expect(after.encodingStrength, 0.42);
      expect(after.savings, 0.81);
    });

    test('leaves the FSRS columns and the timestamp exactly as they were',
        () async {
      final before = await seedRow();

      await anki.updateModelState('cs-1', encodingStrength: 0.33, savings: 0.9);

      final after = await readRow();
      // Spelled out separately from the sweep above: these are the columns a
      // "convenient" companion would have overwritten.
      expect(after.stability, 41.25);
      expect(after.difficulty, 5.5);
      expect(after.dueAt, 1700000000000);
      expect(after.intervalDays, 12.5);
      expect(after.lastReviewedAt, 1699000000000);
      expect(after.updatedAt, 2222);
      expect(after.updatedAt, before.updatedAt);
    });

    test('a null argument leaves its column alone (one column at a time)',
        () async {
      final before = await seedRow();

      await anki.updateModelState('cs-1', savings: 0.95);
      var after = await readRow();
      expect(after.savings, 0.95);
      expect(after.encodingStrength, before.encodingStrength);
      expectEverythingElseUnchanged(before, after);

      await anki.updateModelState('cs-1', encodingStrength: 0.2);
      after = await readRow();
      expect(after.encodingStrength, 0.2);
      expect(after.savings, 0.95);
      expectEverythingElseUnchanged(before, after);
    });

    test('both arguments null is a no-op, and cannot clear a column', () async {
      final before = await seedRow();

      await anki.updateModelState('cs-1');

      final after = await readRow();
      expectEverythingElseUnchanged(before, after);
      expect(after.encodingStrength, 0.6);
      expect(after.savings, 0.7);
      // Deliberate limitation, stated here so nobody later reads "null means
      // clear" into the signature: model state is written forward only.
      expect(after.encodingStrength, isA<double>());
      expect(after.savings, isA<double>());
    });
  });
}
