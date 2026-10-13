/// Which card type the automatic generation paths should write.
///
/// A **generation-time** preference: it decides what the generators produce for
/// new material, not how an answer is judged later (the practice screen owns its
/// own per-answer judging mode, see `review_page.dart`).
///
/// **It is persisted** in `local_settings.anki_card_type_preference` (v7), and
/// NULL there means "the user never chose", which resolves to
/// [CardTypePreference.mixed] - the fill-blank fallback every generator produced
/// before this preference existed.
///
/// There are two readers and they read the same value through one seam:
/// the Riverpod surfaces below, and `CardTypePreferenceStore` for the AI tool
/// (`CreateKnowledgeCardsTool` is constructed by the tool registry, which has no
/// `Ref`). Every write goes through [CardTypePreferenceController], so the store
/// and the database can never disagree - with one honest exception, a session
/// that never opens a review surface still reads [CardTypePreferenceStore]'s
/// default until the provider first loads. That exception is why the store keeps
/// its own default rather than being a second copy of the database value.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/card_template.dart';
import '../../../domain/entities/knowledge_point.dart';
import '../../../domain/services/cloze/cloze_engine.dart';
import '../../../domain/services/cloze/cloze_generator.dart';

/// What the generators may produce for a knowledge point.
enum CardTypePreference {
  /// Let the generator decide from the material. It resolves to the fill-blank
  /// fallback, i.e. exactly the behaviour before this preference existed: a
  /// knowledge point that has never been authored still gets one blankable card.
  mixed,

  /// A single-choice card. The generator only builds one when the material
  /// itself yields a distractor (a second discoverable blank), because inventing
  /// plausible wrong options would be inventing facts.
  mcq,

  /// A fill-blank card judged by the exact characters typed - the dictation and
  /// spelling practice of user annotation 18.
  fillBlank,

  /// A fill-blank card judged leniently: the user recalls the material and the
  /// comparison forgives whitespace, full/half width, punctuation, case and a
  /// typo. See `ReviewService.lenientMatch`.
  fillBlankLenient,

  /// A prompt with the whole content as the answer, judged by the user (there is
  /// no auto comparison of prose).
  essay;

  /// Whether cards made under this preference are meant to be recalled rather
  /// than dictated. The practice screen reads it for its *initial* judging
  /// strictness: a fill-blank stores only its type (`fill_blank`), so a saved
  /// card cannot say which of the two flavours it was generated under, and this
  /// preference is the only signal available.
  bool get prefersLenientComparison =>
      this == CardTypePreference.fillBlankLenient;

  /// The value stored in `local_settings.anki_card_type_preference`.
  ///
  /// The enum's own `name` happens to be exactly this today, but it is spelled
  /// out so renaming a Dart identifier can never change what an already-written
  /// setting means.
  String get storageValue => switch (this) {
        CardTypePreference.mixed => 'mixed',
        CardTypePreference.mcq => 'mcq',
        CardTypePreference.fillBlank => 'fill_blank',
        CardTypePreference.fillBlankLenient => 'fill_blank_lenient',
        CardTypePreference.essay => 'essay',
      };

  /// Reads a stored value back.
  ///
  /// NULL ("never chosen") and an unknown string (written by a build that knew a
  /// different set) both mean [CardTypePreference.mixed]: the generator then
  /// decides from the material, which is today's behaviour and cannot produce a
  /// card the material does not support.
  static CardTypePreference fromStorage(String? value) {
    for (final preference in CardTypePreference.values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return CardTypePreference.mixed;
  }
}

/// The process-wide value.
///
/// The AI tool (`CreateKnowledgeCardsTool`) is constructed by the tool registry
/// rather than by Riverpod, so the value has to be readable without a `Ref`. The
/// provider below is a reactive façade over this single field instead of a
/// second copy, so the generator and the UI can never disagree about it.
abstract final class CardTypePreferenceStore {
  /// Default [CardTypePreference.mixed] - i.e. the fill-blank fallback stays the
  /// default until the user asks for something else.
  static CardTypePreference current = CardTypePreference.mixed;
}

/// The app's view of [CardTypePreferenceStore].
///
/// The synchronous state comes from the store (so the first frame shows the
/// current session's value and nothing flickers), and the persisted value is
/// loaded once behind it. A choice made while that load is in flight wins: it
/// would be a bug of exactly the kind this change fixes if a user's tap on
/// "选择题" were overwritten a moment later by the value that was in the
/// database before they tapped.
class CardTypePreferenceController extends Notifier<CardTypePreference> {
  /// Bumped by every user choice. The initial load only applies its value while
  /// this is still zero.
  int _userChoices = 0;

  @override
  CardTypePreference build() {
    _loadPersisted();
    return CardTypePreferenceStore.current;
  }

  Future<void> _loadPersisted() async {
    final choicesAtStart = _userChoices;
    final stored =
        await ref.read(reviewPlanRepositoryProvider).getCardTypePreference();
    if (_userChoices != choicesAtStart) {
      return;
    }
    if (stored == CardTypePreferenceStore.current) {
      return;
    }
    CardTypePreferenceStore.current = stored;
    // `state` is set after the await, so the guard above is what keeps the read
    // from racing the user; nothing else here can mutate the store.
    state = stored;
  }

  /// Records the user's choice and persists it.
  Future<void> select(CardTypePreference preference) async {
    _userChoices++;
    CardTypePreferenceStore.current = preference;
    state = preference;
    await ref
        .read(reviewPlanRepositoryProvider)
        .setCardTypePreference(preference);
  }
}

final cardTypePreferenceProvider =
    NotifierProvider<CardTypePreferenceController, CardTypePreference>(
  CardTypePreferenceController.new,
);

/// The `card_templates.type` value of a domain card type.
///
/// The database stores the snake_case names the manage page's picker, the
/// package importer and the AI tool all agree on (`fill_blank` / `mcq` /
/// `essay`); the enum's own `name` is `fillBlank`, which is not that value.
extension CardTemplateTypeStorage on CardTemplateType {
  String get storageType => switch (this) {
        CardTemplateType.fillBlank => 'fill_blank',
        CardTemplateType.mcq => 'mcq',
        CardTemplateType.essay => 'essay',
      };
}

/// Turns a preference into the template the automatic generation paths write.
///
/// The generators themselves (`ClozeGenerator`) only know how to find a blank;
/// choosing *what kind of card* to build from it is a product decision and lives
/// here, so the AI tool, the manage page's auto-blank button and any future
/// generator cannot drift apart.
abstract final class CardGenerationPolicy {
  /// The card to write for [point], or null when the preference cannot be
  /// honoured from this material.
  ///
  /// Returning null is deliberate rather than falling back silently: a caller
  /// that asked for a choice card and got a fill-blank would report a success
  /// the user did not ask for.
  static CardTemplate? generate(
    KnowledgePoint point,
    CardTypePreference preference,
  ) {
    if (preference == CardTypePreference.essay) {
      return _essay(point);
    }
    // mixed, fillBlank and fillBlankLenient all produce the blank the
    // heuristics can find; only the judging strictness differs downstream.
    final blank = ClozeGenerator.generateFillBlank(point);
    if (blank == null) {
      return null;
    }
    return preference == CardTypePreference.mcq ? _mcq(point) : blank;
  }

  /// The whole content as the answer: what the content-derived essay fallback in
  /// the review engine presents when nothing can be blanked.
  static CardTemplate? _essay(KnowledgePoint point) {
    final content = point.content.trim();
    if (content.isEmpty) {
      return null;
    }
    return CardTemplate(
      id: 'auto-${point.id}-essay',
      knowledgePointId: point.id,
      type: CardTemplateType.essay,
      question: point.title.trim().isEmpty ? content : point.title.trim(),
      answer: content,
    );
  }

  /// A single-choice card built from the material's *own* other blanks.
  ///
  /// The question is one of the blanks [ClozeEngine] finds, and the distractors
  /// are its siblings: the wrong options are real alternatives from the text
  /// rather than invented ones. When the text supports only one blank there is
  /// no honest distractor and this returns null.
  ///
  /// The blanked term is never the material's own title or tag - "what is this
  /// paragraph about" is not what a review card should ask.
  static CardTemplate? _mcq(KnowledgePoint point) {
    final seeds = [point.title, ...point.tags];
    final candidates = ClozeEngine.discoverCandidates(
      point.content,
      seedKeywords: seeds,
    );
    final topicWords = {
      for (final seed in seeds)
        if (seed.trim().isNotEmpty) seed.trim(),
    };
    final answerable = [
      for (final candidate in candidates)
        if (!topicWords.contains(candidate.answerIn(point.content).trim()))
          candidate,
    ];
    if (answerable.isEmpty) {
      return null;
    }
    final target = answerable.first;
    final answer = target.answerIn(point.content).trim();
    if (answer.isEmpty) {
      return null;
    }
    final distractors = <String>{};
    for (final candidate in candidates) {
      final other = candidate.answerIn(point.content).trim();
      if (other.isNotEmpty && other != answer) {
        distractors.add(other);
      }
    }
    if (distractors.isEmpty) {
      return null;
    }
    // Alphabetical placement rather than "correct answer first": the answer must
    // not always sit in the same slot, and the order has to stay reproducible so
    // the same material always yields the same card.
    final options = <String>{
      answer,
      ...(distractors.toList()..sort()).take(3),
    }.toList()
      ..sort();
    return CardTemplate(
      id: 'auto-${point.id}-mcq',
      knowledgePointId: point.id,
      type: CardTemplateType.mcq,
      // The blank is cut at the candidate's own span, the same way the cloze
      // renderer cuts it, so the question and the blank cannot disagree.
      question: '${point.content.substring(0, target.start)}'
          '${ClozeGenerator.blankMarker}'
          '${point.content.substring(target.start + target.length)}',
      answer: answer,
      options: options,
    );
  }
}
