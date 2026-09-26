import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/ai_repository.dart';
import '../application/ai_providers.dart';

/// Writes the AI configuration.
///
/// Separate from [aiConfigProvider] (which reads) so a save has one obvious
/// place to happen, and the read providers are simply invalidated - the same
/// shape the appearance settings use.
class AiSettingsController {
  AiSettingsController(this._ref);

  final Ref _ref;

  /// Persists [config]. Blank key / URL / model become NULL so that "unset"
  /// stays distinguishable from "set to empty", and the defaults apply.
  ///
  /// Only the AI columns are written: the settings row is shared with language,
  /// theme and profile, and saving an API key must not reset those.
  Future<void> save(AiConfig config) async {
    final repository = _ref.read(aiRepositoryProvider);
    final language = await repository.currentLanguage();
    await repository.saveConfig(
      AiConfig(
        enabled: config.enabled,
        apiKey: _nullIfBlank(config.apiKey),
        baseUrl: _nullIfBlank(config.baseUrl),
        model: _nullIfBlank(config.model),
        permissionMode: config.permissionMode,
      ),
      fallbackLanguage: language ?? 'system',
    );
    _ref.invalidate(aiConfigProvider);
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

final aiSettingsControllerProvider = Provider<AiSettingsController>((ref) {
  return AiSettingsController(ref);
});
