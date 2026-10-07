import 'dart:io';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../domain/ai_tool.dart';
import '../domain/model_adapter.dart';
import '../tools/cognitive_tools.dart';
import '../tools/knowledge_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/task_tools.dart';
import '../tools/web_tools.dart';

/// The complete, static list of tools the model may use.
///
/// "Static" is the whole point (docs/AI_DESIGN.md §10 C2): there is no plugin
/// registry, no runtime extension point, no dependency-injection container. A
/// tool exists because it is in this list, and adding one is a code change.
/// That is what "no cordis" means in practice.
///
/// Platform gating lives on the tool itself (`availableOnCurrentPlatform`), so
/// a Windows-only capability is simply absent from [forCurrentPlatform] on
/// Android rather than failing at call time.
class ToolRegistry {
  ToolRegistry(this._tools);

  /// The app's single tool list, assembled in one place.
  ///
  /// Registration and construction belong together: a tool that is not in this
  /// list is not reachable by the model at all (it would be dead code), and
  /// keeping the list here - rather than inside a Riverpod callback - is what
  /// lets a test assert membership and schemas without a widget tree.
  factory ToolRegistry.forApp({
    required AppDatabase db,
    required TaskRepository tasks,
    required TimeBlockRepository blocks,
    required AnkiRepository anki,
    required TagRepository tags,
    CognitiveModel model = const MindNetCognitiveModel(),
    DateTime Function()? clock,
  }) {
    return ToolRegistry([
      FetchPageTool(),
      QueryTasksTool(tasks, db),
      ManageTaskTool(tasks, db),
      QueryScheduleTool(blocks),
      ManageTimeBlockTool(blocks, db),
      // 用途 1 (docs/MINDNET_CONTRACT.md §6.3): read-only problem evaluation.
      EvaluateProblemFitTool(
        ankiRepository: anki,
        tagRepository: tags,
        model: model,
        clock: clock,
      ),
      // The write half of the photo flow: an attached page of notes becomes a
      // real knowledge point plus cards (see tools/knowledge_tools.dart).
      CreateKnowledgeCardsTool(anki),
    ]);
  }


  final List<AiTool> _tools;

  /// Every registered tool, including ones this platform cannot offer. Used by
  /// the settings screen to explain what is missing and why.
  List<AiTool> get all => List.unmodifiable(_tools);

  /// The tools this platform may actually offer.
  List<AiTool> get forCurrentPlatform =>
      [for (final tool in _tools) if (tool.availableOnCurrentPlatform) tool];

  /// Tools that are registered but unavailable here.
  List<AiTool> get unavailableHere =>
      [for (final tool in _tools) if (!tool.availableOnCurrentPlatform) tool];

  AiTool? byName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    return null;
  }

  /// The provider-facing declarations. Sent on every turn rather than cached,
  /// because the list depends on the platform and would otherwise be wrong on
  /// whichever platform it was not built for.
  List<ModelToolSpec> get modelSpecs => [
        for (final tool in forCurrentPlatform)
          ModelToolSpec(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
          ),
      ];

  /// True when the current platform can offer nothing at all, which the UI says
  /// out loud instead of showing an AI that cannot act.
  bool get isEmptyHere => forCurrentPlatform.isEmpty;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
