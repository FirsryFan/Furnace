import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/user_persona.dart';
import '../application/user_persona_provider.dart';

/// 编辑「自我描述」的输入框。
const Key userPersonaFieldKey = Key('user-persona-field');

/// 「保存」按钮。
const Key userPersonaSaveKey = Key('user-persona-save');

/// 「清除自我描述」按钮（只有确实存过内容时才出现）。
const Key userPersonaClearKey = Key('user-persona-clear');

/// 清除确认框里的「删除」按钮。
const Key userPersonaClearConfirmKey = Key('user-persona-clear-confirm');

/// 用户自我描述的编辑页（schema v35）。
///
/// 这一页只做三件事：读 `userPersonaProvider` 的归一化文本、把用户的原话写回
/// 数据库、以及一个带确认的清除。长度的上限、空文本的存储口径（NULL 而不是
/// 空串）都交给 `domain/services/cognitive/user_persona.dart`，页面不自己截断、
/// 也不自己归一化——静默改写用户的自述比超长更糟。
///
/// 清除按钮的可见性用本地的 `_hasStored` 而不是每帧从 provider 推：页面在
/// 保存/清除之后自己知道结果，不必等 `watchDatabaseRevision()` 把 provider
/// 重新读一遍（测试里数据库没有装写拦截器时也照样正确）。
class UserPersonaPage extends ConsumerStatefulWidget {
  const UserPersonaPage({super.key});

  @override
  ConsumerState<UserPersonaPage> createState() => _UserPersonaPageState();
}

class _UserPersonaPageState extends ConsumerState<UserPersonaPage> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  /// provider 第一次给出数据时把内容灌进输入框；之后输入框归用户所有，
  /// 保存/清除引起的重读不再回写（否则会盖掉正在编辑的文字）。
  bool _initialized = false;

  /// 数据库里此刻是否有非空 persona（决定「清除」按钮是否出现）。
  bool _hasStored = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.personaTitle)),
      body: ref.watch(userPersonaProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            // 读不到已存内容时不要假装「没写过」：给一个空编辑框会让用户顺手覆盖
            // 掉原来那段文字。这里如实显示错误。
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$error', textAlign: TextAlign.center),
              ),
            ),
            data: (persona) {
              if (!_initialized) {
                _initialized = true;
                _controller.text = persona ?? '';
                _hasStored = userPersonaIsPresent(persona);
              }
              return _buildEditor(context, l10n);
            },
          ),
    );
  }

  Widget _buildEditor(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final tooLong = userPersonaTooLong(_controller.text);
    final counter =
        '${_controller.text.characters.length} / $kUserPersonaMaxChars';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.personaEditorHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            key: userPersonaFieldKey,
            controller: _controller,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.personaEditorPlaceholder,
              counterText: counter,
              errorText:
                  tooLong ? l10n.personaTooLong(kUserPersonaMaxChars) : null,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.personaPrivacyNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton(
                key: userPersonaSaveKey,
                onPressed: (_saving || tooLong) ? null : _save,
                child: Text(l10n.commonSave),
              ),
              if (_hasStored) ...[
                const SizedBox(width: 12),
                TextButton(
                  key: userPersonaClearKey,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _saving ? null : _clear,
                  child: Text(l10n.personaClearAction),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateUserPersona(_controller.text);
      if (!mounted) return;
      setState(() => _hasStored = userPersonaIsPresent(_controller.text));
      messenger.showSnackBar(SnackBar(content: Text(l10n.personaSaveDone)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.personaSaveFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.personaClearConfirmTitle),
        content: Text(l10n.personaClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: userPersonaClearConfirmKey,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).updateUserPersona(null);
      if (!mounted) return;
      _controller.clear();
      setState(() => _hasStored = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.personaClearDone)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.personaSaveFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
