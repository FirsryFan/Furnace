import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';

/// "Delete" has to mean deleted.
///
/// The bug this file pins down: card states come in two shapes - template-backed
/// and presentation-unit (`cloze:…` / `essay:…`, no template) - and the cascade
/// only walked the templates, so unit states survived their flashcard. The
/// cognitive-model page kept listing them as nameless cards, which is how it was
/// noticed.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> count(String table) async {
    final row = await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle();
    return row.read<int>('n');
  }

  /// A flashcard with both state shapes, a cloze slot and history, a boost and a
  /// tag link: one row in every table that points at a flashcard.
  Future<KnowledgePoint> seedFullFlashcard() async {
    final point = await anki.createKnowledgePoint(
      title: '光合作用',
      content: '主要场所是叶绿体。',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'essay',
      question: '场所？',
      answer: '叶绿体',
    );
    final templateState = await anki.getOrCreateCardState(template.id);
    await anki.addReviewLog(
      cardStateId: templateState.id,
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final unitState = await anki.getOrCreateUnitCardState(point.id, 'essay:${point.id}');
    await anki.addReviewLog(
      cardStateId: unitState.id,
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await anki.upsertBoost(knowledgePointId: point.id, factor: 1.2);
    final tag = await tags.createTag(name: '生物');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    return point;
  }

  group('deleting a flashcard', () {
    test('removes both state shapes and everything pointing at it', () async {
      final point = await seedFullFlashcard();
      expect(await count('card_states'), 2);

      await anki.deleteKnowledgePoint(point.id);

      expect(await anki.getKnowledgePointById(point.id), isNull);
      expect(await count('card_templates'), 0);
      expect(
        await count('card_states'),
        0,
        reason: 'the presentation-unit state has no template to be found through',
      );
      expect(await count('review_logs'), 0);
      expect(await count('boost_entries'), 0);
      expect(
        await count('object_tags'),
        0,
        reason: 'the tag link pointed at the deleted flashcard',
      );
      expect(await count('cloze_slots'), 0);
      expect(await count('cloze_history'), 0);
      expect(await anki.countOrphanCardStates(), 0);
    });

    test('deleting one card leaves the flashcard and its other state', () async {
      final point = await seedFullFlashcard();
      final template = (await anki.getTemplatesForKnowledgePoint(point.id)).single;

      await anki.deleteTemplate(template.id);

      expect(await anki.getKnowledgePointById(point.id), isNotNull);
      expect(await count('card_templates'), 0);
      expect(
        await count('card_states'),
        1,
        reason: 'the presentation-unit state belongs to the flashcard, not the card',
      );
      expect(await anki.countOrphanCardStates(), 0);
    });
  });

  group('repairing databases written by the older cascade', () {
    test('counts and purges debris, and leaves live rows alone', () async {
      // One live flashcard whose template state has no knowledge_point_id - the
      // shape `getOrCreateCardState` still produces - plus one orphan state that
      // names a flashcard which is already gone.
      final live = await anki.createKnowledgePoint(title: '活着', content: '内容');
      final template = await anki.createTemplate(
        knowledgePointId: live.id,
        type: 'essay',
        question: '题',
        answer: '答',
      );
      final liveState = await anki.getOrCreateCardState(template.id);
      final orphanState = await anki.getOrCreateUnitCardState(
        'flashcard-that-is-gone',
        'essay:flashcard-that-is-gone',
      );
      await anki.addReviewLog(
        cardStateId: orphanState.id,
        cardTemplateId: template.id,
        rating: 3,
        reviewedAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(await anki.countOrphanCardStates(), 1);

      final removed = await anki.purgeOrphanKnowledgeRows();

      expect(removed, 1);
      expect(await anki.countOrphanCardStates(), 0);
      expect(
        (await db.select(db.cardStates).get()).map((state) => state.id),
        [liveState.id],
        reason: 'a state whose template still exists is not debris',
      );
    });
  });

  group('the readings page', () {
    Future<ProviderContainer> container() async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('shows a template state through its template name, not a blank', () async {
      final point = await anki.createKnowledgePoint(title: '光合作用', content: '内容');
      final template = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '题',
        answer: '答',
      );
      await anki.getOrCreateCardState(template.id);

      final inputs = await (await container())
          .read(cognitiveObservationInputsProvider.future);

      expect(inputs.units, hasLength(1));
      expect(
        inputs.units.single.knowledgePointTitle,
        '光合作用',
        reason: 'the state has no knowledge_point_id; the template supplies it',
      );
    });

    test('does not list debris as cards, and reports it instead', () async {
      await anki.getOrCreateUnitCardState(
        'flashcard-that-is-gone',
        'essay:flashcard-that-is-gone',
      );

      final provider = await container();
      final inputs = await provider.read(cognitiveObservationInputsProvider.future);

      expect(inputs.units, isEmpty);
      expect(await provider.read(orphanCardStateCountProvider.future), 1);
    });
  });
}
