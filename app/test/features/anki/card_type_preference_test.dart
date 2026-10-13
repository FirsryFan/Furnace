import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/entities/card_template.dart' as domain;
import 'package:furnace/domain/entities/knowledge_point.dart' as domain;
import 'package:furnace/domain/services/cloze/cloze_generator.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/anki/application/card_type_preference.dart';
import 'package:furnace/features/ai/tools/knowledge_tools.dart';

/// Which card type the generators write.
///
/// The preference is generation-time and in memory only (the settings schema is
/// owned elsewhere), so what is asserted here is that it *reaches* both
/// generation paths - the AI tool's fallback and the policy the manage page
/// calls - and that the default still behaves exactly as before.
void main() {
  setUp(() {
    CardTypePreferenceStore.current = CardTypePreference.mixed;
  });

  tearDown(() {
    CardTypePreferenceStore.current = CardTypePreference.mixed;
  });

  domain.KnowledgePoint material(String title, String content) =>
      domain.KnowledgePoint(id: 'unsaved', title: title, content: content);

  group('the policy turns a preference into a card', () {
    test('mixed keeps the fill-blank fallback, exactly as before', () {
      final card = CardGenerationPolicy.generate(
        material('光合作用场所', '光合作用的主要场所是叶绿体。'),
        CardTypePreference.mixed,
      );

      expect(card, isNotNull);
      expect(card!.type, domain.CardTemplateType.fillBlank);
      expect(card.question, contains(ClozeGenerator.blankMarker));
      expect(card.answer, '叶绿体');
    });

    test('fill-blank and its lenient flavour write the same card', () {
      final strict = CardGenerationPolicy.generate(
        material('光合作用场所', '光合作用的主要场所是叶绿体。'),
        CardTypePreference.fillBlank,
      );
      final lenient = CardGenerationPolicy.generate(
        material('光合作用场所', '光合作用的主要场所是叶绿体。'),
        CardTypePreference.fillBlankLenient,
      );

      expect(strict!.type, domain.CardTemplateType.fillBlank);
      expect(lenient!.type, domain.CardTemplateType.fillBlank,
          reason: 'the lenient flavour is a judging mode, not a stored type');
      expect(
        CardTypePreference.fillBlankLenient.prefersLenientComparison,
        isTrue,
      );
      expect(CardTypePreference.fillBlank.prefersLenientComparison, isFalse);
      expect(CardTypePreference.mixed.prefersLenientComparison, isFalse);
    });

    test('essay asks the material and answers with it', () {
      final card = CardGenerationPolicy.generate(
        material('光合作用场所', '光合作用的主要场所是叶绿体。'),
        CardTypePreference.essay,
      );

      expect(card!.type, domain.CardTemplateType.essay);
      expect(card.answer, '光合作用的主要场所是叶绿体。');
      expect(card.question, '光合作用场所');
    });

    test('mcq takes its distractors from the material itself', () {
      final card = CardGenerationPolicy.generate(
        material('光合作用场所', '光合作用的主要场所是叶绿体，主要产物是葡萄糖。'),
        CardTypePreference.mcq,
      );

      expect(card, isNotNull);
      expect(card!.type, domain.CardTemplateType.mcq);
      expect(card.answer, '叶绿体');
      expect(card.options, ['叶绿体', '葡萄糖'],
          reason: 'the wrong option is another fact of the same material, and '
              'the correct one is not always first');
      expect(card.options, contains(card.answer));
    });

    test('mcq refuses rather than inventing a wrong option', () {
      expect(
        CardGenerationPolicy.generate(
          material('细胞结构', '细胞是生命活动的基本单位。'),
          CardTypePreference.mcq,
        ),
        isNull,
        reason: 'one blankable fact means there is no honest distractor',
      );
    });

    test('an unblankable content yields nothing', () {
      expect(
        CardGenerationPolicy.generate(
          material('待查概念', '这个概念需要查资料。'),
          CardTypePreference.fillBlank,
        ),
        isNull,
      );
      expect(
        CardGenerationPolicy.generate(
          material('待查概念', '这个概念需要查资料。'),
          CardTypePreference.mixed,
        ),
        isNull,
      );
      expect(
        CardGenerationPolicy.generate(
          material('空', '   '),
          CardTypePreference.essay,
        ),
        isNull,
      );
    });

    test('the stored type is the database value, not the enum name', () {
      expect(
        domain.CardTemplateType.fillBlank.storageType,
        'fill_blank',
        reason: 'the enum name is fillBlank, which the database never stores',
      );
      expect(domain.CardTemplateType.mcq.storageType, 'mcq');
      expect(domain.CardTemplateType.essay.storageType, 'essay');
    });
  });

  group('the AI tool generates the preferred type', () {
    late AppDatabase db;
    late AnkiRepository anki;
    late CreateKnowledgeCardsTool tool;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      anki = AnkiRepository(db);
      tool = CreateKnowledgeCardsTool(anki);
    });

    tearDown(() async {
      await db.close();
    });

    ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
          toolName: CreateKnowledgeCardsTool.toolName,
          action: CreateKnowledgeCardsTool.toolName,
          arguments: args,
        );

    Future<List<CardTemplate>> storedTemplates() async {
      final points = await anki.getKnowledgePoints();
      return anki.getTemplatesForKnowledgePoint(points.single.id);
    }

    test('with the default preference it is still the fill-blank fallback',
        () async {
      final result = await tool.run(invoke({
        'title': '细胞',
        'content': '细胞是生命活动的基本单位。',
      }));

      expect(result.ok, isTrue);
      expect((await storedTemplates()).single.type, 'fill_blank');
    });

    test('essay preference writes an essay card', () async {
      CardTypePreferenceStore.current = CardTypePreference.essay;

      final result = await tool.run(invoke({
        'title': '细胞',
        'content': '细胞是生命活动的基本单位。',
      }));

      expect(result.ok, isTrue);
      final template = (await storedTemplates()).single;
      expect(template.type, 'essay');
      expect(template.answer, contains('生命活动的基本单位'));
      expect(template.clozeTemplate, isNull);
    });

    test('mcq preference writes a choice card with its options', () async {
      CardTypePreferenceStore.current = CardTypePreference.mcq;

      final result = await tool.run(invoke({
        'title': '光合作用场所',
        'content': '光合作用的主要场所是叶绿体，主要产物是葡萄糖。',
      }));

      expect(result.ok, isTrue);
      final template = (await storedTemplates()).single;
      expect(template.type, 'mcq');
      expect(template.options, '叶绿体\u0001葡萄糖',
          reason: 'the review queue reads exactly this encoding');
    });

    test('an mcq the material cannot support is refused, not downgraded',
        () async {
      CardTypePreferenceStore.current = CardTypePreference.mcq;

      final result = await tool.run(invoke({
        'title': '细胞结构',
        'content': '细胞是生命活动的基本单位。',
      }));

      expect(result.ok, isFalse);
      expect(result.error, contains('options'));
      expect(await anki.getKnowledgePoints(), isEmpty,
          reason: 'a refusal before the write leaves nothing behind');
    });

    test('a choice card the model supplies carries its options', () async {
      final result = await tool.run(invoke({
        'title': '光合作用场所',
        'content': '光合作用的主要场所是叶绿体。',
        'cards': [
          {
            'question': '光合作用的场所是？',
            'answer': '叶绿体',
            'type': 'mcq',
            'options': ['线粒体', '叶绿体'],
            'hint': '想想叶子的颜色',
          },
        ],
      }));

      expect(result.ok, isTrue);
      final template = (await storedTemplates()).single;
      expect(template.type, 'mcq');
      expect(template.options, '线粒体\u0001叶绿体');
      expect(template.hint, '想想叶子的颜色');
    });

    test('a choice card without options is refused', () async {
      final result = await tool.run(invoke({
        'title': 'T',
        'content': 'C',
        'cards': [
          {'question': 'q', 'answer': 'a', 'type': 'mcq'},
        ],
      }));

      expect(result.ok, isFalse);
      expect(result.error, contains('options'));
      expect(await anki.getKnowledgePoints(), isEmpty);
    });
  });
}
