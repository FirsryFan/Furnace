import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../data/repositories/ai_repository.dart';
import '../application/ai_providers.dart';
import '../application/ai_settings_notifier.dart';
import '../domain/tool_registry.dart';

/// AI configuration: key, endpoint, model, permission mode.
///
/// Reached from Settings. The screen doubles as the explanation of what turning
/// AI on actually changes - the app is offline by default, and adding a network
/// permission is a real change to that, so it is stated here rather than buried.
class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _key = TextEditingController();
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  bool _enabled = false;
  AiPermissionMode _mode = AiPermissionMode.plan;
  bool _loaded = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _key.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  void _loadOnce(AiConfig config) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _enabled = config.enabled;
    _mode = config.permissionMode;
    _key.text = config.apiKey ?? '';
    _baseUrl.text = config.baseUrl ?? '';
    _model.text = config.model ?? '';
  }

  Future<void> _save(AppLocalizations l10n) async {
    final hasKey = _key.text.trim().isNotEmpty;
    // Enabling without a key would produce an AI surface that fails on the
    // first message, so the toggle simply cannot be satisfied without one.
    if (_enabled && !hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsAiKeyRequired)),
      );
      return;
    }
    await ref.read(aiSettingsControllerProvider).save(AiConfig(
          enabled: _enabled && hasKey,
          apiKey: _key.text,
          baseUrl: _baseUrl.text,
          model: _model.text,
          permissionMode: _mode,
        ));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsAiSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final configAsync = ref.watch(aiConfigProvider);
    final registry = ref.watch(toolRegistryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAiSection)),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (config) {
          _loadOnce(config);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: Text(l10n.settingsAiEnabled),
                subtitle: Text(l10n.aiNotConfiguredHint),
              ),
              const Divider(),
              TextField(
                controller: _key,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: l10n.settingsAiApiKey,
                  helperText: l10n.settingsAiApiKeyHint,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                decoration: InputDecoration(
                  labelText: l10n.settingsAiBaseUrl,
                  hintText: AiConfig.defaultBaseUrl,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: l10n.settingsAiModel,
                  hintText: AiConfig.defaultModel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.settingsAiPermissionMode,
                  style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<AiPermissionMode>(
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v ?? _mode),
                child: Column(
                  children: [
                    RadioListTile<AiPermissionMode>(
                      value: AiPermissionMode.plan,
                      title: Text(l10n.settingsAiPermissionPlan),
                    ),
                    RadioListTile<AiPermissionMode>(
                      value: AiPermissionMode.auto,
                      title: Text(l10n.settingsAiPermissionAuto),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text(
                  l10n.settingsAiPermissionHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _save(l10n),
                child: Text(l10n.settingsAiSave),
              ),
              const SizedBox(height: 24),
              _ToolsCard(registry: registry, l10n: l10n),
            ],
          );
        },
      ),
    );
  }
}

/// What the AI can actually do here, and what this platform cannot offer.
///
/// Listing the tools is deliberate: "the AI can change your data" is abstract,
/// while the concrete list is checkable. The platform note is the honest half -
/// Android has no Node runtime or desktop browser, so script-based abilities are
/// absent there rather than silently failing.
class _ToolsCard extends StatelessWidget {
  const _ToolsCard({required this.registry, required this.l10n});

  final ToolRegistry registry;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('可用工具（${registry.forCurrentPlatform.length}）',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final tool in registry.forCurrentPlatform)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.build_outlined, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${tool.name}  ·  ${tool.description.split('。').first}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (registry.unavailableHere.isNotEmpty) ...[
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l10n.settingsAiPlatformNote}'
                      '（本机不可用：${registry.unavailableHere.map((t) => t.name).join('、')}）',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
