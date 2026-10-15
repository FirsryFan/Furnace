import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/diffusion_log_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
import 'package:furnace/features/anki/application/review_service.dart';

/// Card types other than the auto-generated blank reaching the queue.
///
/// The templates the manage page, the package importer and the AI tool write all
/// lived in the database and were never presented, because the queue only knew
/// how to derive blanks from a knowledge point's content. These tests pin the
/// three presentations down: a typed blank, a picked choice, a self-judged
/// essay - plus the hint that rides along with a template.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late ReviewService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    service = ReviewService(
      ankiRepository: anki,
      tagRepository: TagRepository(db),
      taskRepository: TaskRepository(db),
      diffusionLogRepository: DiffusionLogRepository(db),
      random: Random(7),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<KnowledgePoint> makePoint(String title, String content) =>
      anki.createKnowledgePoint(title: title, content: content);

  Future<CardTemplate> makeTemplate(
    KnowledgePoint point, {
    required String type,
    required String question,
    required String answer,
    List<String> options = const [],
    String? hint,
  }) async {
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: type,
      question: question,
      answer: answer,
      options: options,
      hint: hint,
    );
    // The manage page, the importer and the AI tool all make this call; without
    // it the card is invisible to the queue.
    await anki.getOrCreateCardState(template.id);
    return template;
  }

  group('a multiple-choice template is reviewable', () {
    test('the queue item carries the options and the template id', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final template = await makeTemplate(
        point,
        type: 'mcq',
        question: '光合作用的场所是？',
        answer: '叶绿体',
        options: ['线粒体', '叶绿体', '细胞核'],
      );

      final queue = await service.buildQueue();

      expect(queue, hasLength(1));
      final item = queue.single;
      expect(item.kind, ReviewItemKind.mcq);
      expect(item.templateId, template.id);
      expect(item.options, ['线粒体', '叶绿体', '细胞核'],
          reason:
              'options are stored \\u0001-separated and must come out whole');
      expect(item.answer, '叶绿体');
      expect(item.isNew, isTrue);
    });

    test('it is judged by option identity, and the log says mcq', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final template = await makeTemplate(
        point,
        type: 'mcq',
        question: '光合作用的场所是？',
        answer: '叶绿体',
        options: ['线粒体', '叶绿体', '细胞核'],
      );
      final item = (await service.buildQueue()).single;

      expect(
        ReviewService.mcqMatch(
          options: item.options,
          answer: item.answer,
          selected: '叶绿体',
        ),
        isTrue,
      );
      expect(
        ReviewService.mcqMatch(
          options: item.options,
          answer: item.answer,
          selected: '线粒体',
        ),
        isFalse,
      );

      await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
        judgeMode: JudgeMode.auto,
      );

      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.judgeMode, 'auto');
      expect(log.format, 'mcq');
      expect(log.cardTemplateId, template.id,
          reason: 'the log points at the card the user actually answered');
      expect(log.unitKey, 'preset:${template.id}');
    });

    test('a choice card with no options is self-judged, not skipped', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      await makeTemplate(
        point,
        type: 'mcq',
        question: '光合作用的场所是？',
        answer: '叶绿体',
      );

      final item = (await service.buildQueue()).single;

      expect(item.kind, ReviewItemKind.essay,
          reason: 'there is nothing to choose from, so the user judges it');
      expect(item.options, isEmpty);
      expect(item.answer, '叶绿体');
    });
  });

  group('an essay template is reviewable, by the user', () {
    test('it goes through the self-judge path and logs judge_mode self',
        () async {
      final point = await makePoint('光合作用', '光合作用把光能转成化学能。');
      final template = await makeTemplate(
        point,
        type: 'essay',
        question: '光合作用的意义是什么？',
        answer: '把光能转成化学能。',
      );

      final item = (await service.buildQueue()).single;
      expect(item.kind, ReviewItemKind.essay);
      expect(item.templateId, template.id);

      // The engine does not decide prose: the caller passes the user's verdict
      // and says who judged it.
      final outcome = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
        judgeMode: JudgeMode.self,
      );

      expect(outcome.correct, isTrue);
      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.judgeMode, 'self');
      expect(log.format, 'essay');
    });

    test('a content with nothing to blank out is an essay unit too', () async {
      // No card, no marker and no blankable term: the engine has nothing to
      // compare, so the unit is prose the user judges.
      final point = await makePoint('待查概念', '这个概念需要查资料。');
      final item = (await service.buildQueue()).single;
      expect(item.kind, ReviewItemKind.essay);
      expect(item.answer, point.content);
    });
  });

  group('a fill-blank template is reviewable', () {
    test('it is typed, and the log says fill', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      await makeTemplate(
        point,
        type: 'fill_blank',
        question: '光合作用的场所是___',
        answer: '叶绿体',
        hint: '想想叶子的颜色',
      );

      final item = (await service.buildQueue()).single;
      expect(item.kind, ReviewItemKind.fillBlank);
      expect(item.question, contains('______'),
          reason: 'the blank marker is rendered as the full blank for display');
      expect(item.hint, '想想叶子的颜色');

      await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
        judgeMode: JudgeMode.auto,
      );
      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.format, 'fill');
      expect(log.judgeMode, 'auto');
    });
  });

  group('the content-derived blank still works', () {
    test('it is drawn, marked as a cloze unit, and keeps cloze history',
        () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');

      final item = (await service.buildQueue()).single;
      expect(item.kind, ReviewItemKind.fillBlank);
      expect(item.clozeSlotKey, isNotNull);
      expect(item.templateId, isNull);
      expect(item.question, contains('______'));

      await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
      );

      expect(await db.select(db.clozeHistory).get(), hasLength(1),
          reason:
              'the free-blank draw reads this history to pick its next slot');
    });

    test('a template card writes no cloze history', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      await makeTemplate(
        point,
        type: 'mcq',
        question: '光合作用的场所是？',
        answer: '叶绿体',
        options: ['线粒体', '叶绿体'],
      );

      final item = (await service.buildQueue()).single;
      await service.grade(item: item, correct: true, rating: FsrsRating.good);

      expect(await db.select(db.clozeHistory).get(), isEmpty,
          reason: 'a preset card has no slot to remember');
    });
  });

  group('the hint travels with the card, and only the card', () {
    test('a content-derived unit takes the material hint', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final template = await makeTemplate(
        point,
        type: 'essay',
        question: '光合作用在哪里进行？',
        answer: '叶绿体',
        // The card is where the user wrote the hint; a content-derived blank has
        // no template row of its own.
        hint: '先想颜色',
      );

      final first = (await service.buildQueue()).single;
      expect(first.templateId, template.id);
      expect(first.hint, '先想颜色');

      // Once the authored card is scheduled, the free-blank unit for the same
      // material is drawn (spec 1.3.2) and carries the material's hint.
      await service.grade(
        item: first,
        correct: true,
        rating: FsrsRating.good,
      );

      final second = (await service.buildQueue()).single;
      expect(second.templateId, isNull);
      expect(second.hint, '先想颜色');
    });

    test('an empty hint means no hint at all', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      await makeTemplate(
        point,
        type: 'fill_blank',
        question: '光合作用的场所是？',
        answer: '叶绿体',
        hint: '   ',
      );

      final item = (await service.buildQueue()).single;
      expect(item.hint, isNull);
    });
  });
}
