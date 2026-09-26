import 'dart:io';

import '../domain/ai_tool.dart';
import '../domain/model_adapter.dart';

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
