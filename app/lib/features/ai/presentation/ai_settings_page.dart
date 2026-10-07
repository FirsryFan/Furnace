import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../data/repositories/ai_repository.dart';
import '../../../data/skill/skill_store.dart';
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
              const SizedBox(height: 16),
              const SkillsCard(),
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

/// Installed `.fskill` packages: switch them on and off, install more, remove.
///
/// This is the whole skill UI, and it is deliberately explicit about the two
/// things the feature does *not* do yet, because both are the kind of absence a
/// user would otherwise read as a bug:
///
///  * script-backed tools are declared and shown but **cannot be called** - the
///    execution container of docs/SKILL_FORMAT.md §3 does not exist, so the card
///    says so instead of registering a tool that would fail at call time;
///  * a refusal is shown with its own reason (wrong protocol, name, platform,
///    a destructive tool, an oversized archive) rather than as "invalid file",
///    because the reason is the only part the user can act on.
///
/// Public, unlike the other cards on this page, because it reads its own
/// strings from the localisations and is therefore mounted directly by a
/// focused widget test instead of through the whole settings page.
class SkillsCard extends ConsumerStatefulWidget {
  const SkillsCard({super.key});

  @override
  ConsumerState<SkillsCard> createState() => SkillsCardState();
}

class SkillsCardState extends ConsumerState<SkillsCard> {
  /// The last install refusal, kept until the next attempt.
  String? _error;

  /// Name currently being enabled/disabled, so its switch shows progress.
  String? _busy;

  bool _installing = false;

  /// The stored refusal message, for the widget test that checks it is shown.
  String? get errorMessage => _error;

  /// Validates and installs one already-read package.
  ///
  /// Taking bytes rather than a `PlatformFile` is what lets the widget test
  /// drive the real read/validate path: a `PlatformFile` can only be produced
  /// by a platform-channel file dialog.
  Future<({String? installed, String? error})> installBytes(Uint8List bytes) =>
      _installBytes(bytes);

  /// Puts [message] in the error area.
  ///
  /// Exists because the card only reaches that state through a real picked
  /// file; the test needs to assert on how a refusal is rendered.
  void showErrorForTest(String message) {
    setState(() => _error = message);
  }

  Future<void> _install() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _installing = true;
      _error = null;
    });

    // file_picker 12: `pickFiles` is static, returns the files directly, and
    // the bytes come from an async `readAsBytes()` (see packages_page.dart).
    //
    // `.fskill` is filtered on the desktop and NOT on Android on purpose: the
    // Android picker goes through the system document UI, which filters by MIME
    // type, and an unknown extension has no MIME type - filtering by one there
    // makes the user's own `.fskill` files unselectable. The package is
    // validated immediately after picking anyway, so the filter is a
    // convenience, not a gate.
    final picked = await FilePicker.pickFiles(
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const ['fskill'],
    );
    if (!mounted) {
      return;
    }
    if (picked.isEmpty) {
      // A cancelled dialog is not an outcome, so it leaves no note behind.
      setState(() => _installing = false);
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await picked.first.readAsBytes();
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = '${l10n.skillsInstallFailed}：$e';
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final outcome = await _installBytes(bytes);
    if (!mounted) {
      return;
    }
    setState(() {
      _installing = false;
      _error = outcome.error;
    });
    if (outcome.installed != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.skillsTitle}: ${outcome.installed}')),
      );
    }
  }

  /// Validates and installs [bytes].
  ///
  /// Returns the refusal message instead of throwing, and does not touch the
  /// widget state, so the caller is the only place that needs a `mounted` check.
  Future<({String? installed, String? error})> _installBytes(
    Uint8List bytes,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref.read(skillStoreProvider).install(bytes);
      final failure = result.failure;
      if (failure != null) {
        // The reason is the actionable part, so it is shown verbatim rather
        // than replaced with "invalid package".
        return (installed: null, error: failure.message);
      }
      ref.invalidate(installedSkillsProvider);
      // `skill` is non-null whenever `failure` is null, which the store
      // guarantees by construction (it returns one or the other).
      return (installed: result.skill!.name, error: null);
    } catch (e) {
      // A disk error, not a package error: still reported, never swallowed.
      return (installed: null, error: '${l10n.skillsInstallFailed}：$e');
    }
  }

  Future<void> _setEnabled(InstalledSkill skill, bool value) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = skill.name;
      _error = null;
    });
    final ok = await ref.read(skillStoreProvider).setEnabled(skill.name, value);
    if (!mounted) {
      return;
    }
    setState(() => _busy = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.skillsToggleFailed}：${skill.name}')),
      );
      return;
    }
    ref.invalidate(installedSkillsProvider);
  }

  Future<void> _remove(InstalledSkill skill) async {
    final l10n = AppLocalizations.of(context);
    // Confirmed first, and the dialog names the skill: this is the only action
    // in the feature that destroys something the app cannot restore.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.skillsRemoveConfirmTitle),
        content: Text(l10n.skillsRemoveConfirm(skill.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.skillsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.skillsRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final ok = await ref.read(skillStoreProvider).remove(skill.name);
    if (!mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.skillsRemoveFailed}：${skill.name}')),
      );
    }
    ref.invalidate(installedSkillsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final installed = ref.watch(installedSkillsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.skillsTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              l10n.skillsIntro,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    _installing ? l10n.skillsInstalling : l10n.skillsInstall,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _SkillsMessage(
                icon: Icons.error_outline,
                color: scheme.error,
                text: _error!,
              ),
            ],
            const Divider(height: 20),
            installed.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => _SkillsMessage(
                icon: Icons.warning_amber_outlined,
                color: scheme.error,
                text: '$e',
              ),
              data: (skills) {
                if (skills.isEmpty) {
                  return Text(
                    l10n.skillsEmpty,
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final skill in skills)
                      _SkillTile(
                        skill: skill,
                        busy: _busy == skill.name,
                        onChanged: (value) => _setEnabled(skill, value),
                        onRemove: () => _remove(skill),
                      ),
                    const SizedBox(height: 6),
                    _SkillsMessage(
                      icon: Icons.info_outline,
                      color: scheme.outline,
                      text: l10n.skillsContainerNote,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One installed skill: what it is, what it declares, and the two controls.
class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.busy,
    required this.onChanged,
    required this.onRemove,
  });

  final InstalledSkill skill;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final manifest = skill.manifest;
    final toolNames = [for (final tool in skill.tools) tool.name];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manifest.version.isEmpty
                          ? skill.name
                          : '${skill.name}  ·  v${manifest.version}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (manifest.description.isNotEmpty)
                      Text(
                        manifest.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: skill.enabled,
                  onChanged: onChanged,
                ),
            ],
          ),
          _SkillField(
            label: l10n.skillsPlatforms,
            value: manifest.platforms.map((p) => p.id).join(', '),
          ),
          _SkillField(
            label: l10n.skillsNetwork,
            value: manifest.networkAllow.isEmpty
                ? l10n.skillsNetworkNone
                : manifest.networkAllow.join(', '),
          ),
          _SkillField(
            label: l10n.skillsPermissions,
            value: manifest.permissions.isEmpty
                ? l10n.skillsPermissionsNone
                : manifest.permissions.join(', '),
          ),
          _SkillField(
            label: l10n.skillsTools,
            value: toolNames.isEmpty
                ? l10n.skillsToolsNone
                : '${toolNames.length} · ${toolNames.join(', ')}',
          ),
          _SkillField(
            label: l10n.skillsPath,
            value: skill.directory,
            monospace: true,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
              label: Text(
                l10n.skillsRemove,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }
}

/// One `label: value` line of a skill's declared facts.
class _SkillField extends StatelessWidget {
  const _SkillField({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label：$value',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.outline,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }
}

/// A one-line note with an icon, used for mistakes and for what is missing.
class _SkillsMessage extends StatelessWidget {
  const _SkillsMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}
