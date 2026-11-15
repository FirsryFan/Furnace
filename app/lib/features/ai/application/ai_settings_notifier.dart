import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/ai_repository.dart';
import '../domain/model_adapter.dart' show ReasoningEffort;
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
  ///
  /// The v46 model parameters are carried over from the stored configuration
  /// when [config] leaves them null: this screen has no controls for them yet,
  /// so its `AiConfig` is built with NULLs meaning "the screen did not carry
  /// this", not "clear it". Without the carry-over, opening 设置 and pressing
  /// 保存 would silently wipe an effort/temperature chosen directly in the
  /// database - exactly the values the effort-alignment experiment needs.
  Future<void> save(AiConfig config) async {
    final repository = _ref.read(aiRepositoryProvider);
    final language = await repository.currentLanguage();
    final stored = await repository.getConfig();
    await repository.saveConfig(
      AiConfig(
        enabled: config.enabled,
        apiKey: _nullIfBlank(config.apiKey),
        baseUrl: _nullIfBlank(config.baseUrl),
        model: _nullIfBlank(config.model),
        permissionMode: config.permissionMode,
        // Not blank-able: the round budget is a bounded number, and the
        // repository resolves anything out of range into the offered range.
        maxRounds: config.maxRounds,
        // v46: carried over from the stored row when this screen did not carry
        // them (see the doc comment above).
        reasoningEffort: config.reasoningEffort ?? stored.reasoningEffort,
        temperature: config.temperature ?? stored.temperature,
        answerTemperature:
            config.answerTemperature ?? stored.answerTemperature,
        verifierTemperature:
            config.verifierTemperature ?? stored.verifierTemperature,
        maxReasoningTokens:
            config.maxReasoningTokens ?? stored.maxReasoningTokens,
        answerReserveTokens:
            config.answerReserveTokens ?? stored.answerReserveTokens,
        verifierModel: config.verifierModel ?? stored.verifierModel,
        verifierEffort: config.verifierEffort ?? stored.verifierEffort,
      ),
      fallbackLanguage: language ?? 'system',
    );
    _ref.invalidate(aiConfigProvider);
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// 只改聊天回合的思考强度，其余参数原样保留。
  ///
  /// 给对话页提交按钮旁的 effort 选择器用：它和设置页不是同一个入口，但写的是
  /// 同一列（`local_settings.ai_reasoning_effort`，v46 已有，不加 schema）。走
  /// 独立方法而不是 [save] 是因为 [save] 把 `null` 当「这个界面没带这个字段」
  /// 并回填旧值，而这里 `null` 是「用户选了默认（不发送 reasoning_effort）」。
  Future<void> saveReasoningEffort(ReasoningEffort? effort) async {
    final repository = _ref.read(aiRepositoryProvider);
    final stored = await repository.getConfig();
    final language = await repository.currentLanguage();
    await repository.saveConfig(
      stored.withReasoningEffort(effort),
      fallbackLanguage: language ?? 'system',
    );
    _ref.invalidate(aiConfigProvider);
  }
}

final aiSettingsControllerProvider = Provider<AiSettingsController>((ref) {
  return AiSettingsController(ref);
});
