import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../features/ai/application/ai_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_generator_service.dart';

/// 「AI 生成题单」：从题库选 6 题（每科 2 题），把题干图+答案图交给内置
/// 多模态模型，逐题生成题单内容；应用负责树图渲染与 Markdown 合并。
///
/// 这是给「明天早上要一份题单」这种场景的固定流程，不是开放式对话：
/// 用户不需要自己挑题、自己贴图、自己排版。
class PaperGeneratorPage extends ConsumerStatefulWidget {
  const PaperGeneratorPage({super.key});

  @override
  ConsumerState<PaperGeneratorPage> createState() => _PaperGeneratorPageState();
}

class _PaperGeneratorPageState extends ConsumerState<PaperGeneratorPage> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _running = false;
  String _status = '';
  String? _resultPath;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final config = await ref.read(aiConfigProvider.future);
    if (!config.isUsable) {
      setState(() => _error = l10n.paperGenNeedKey);
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _resultPath = null;
      _status = l10n.paperGenSelecting;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final service = PaperGeneratorService(db: db, config: config);
      final result = await service.generate(
        date: _date,
        onProgress: (message) {
          if (mounted) {
            setState(() => _status = message);
          }
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _resultPath = result.markdownPath;
        _status = l10n.paperGenDone;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateText = _date.year.toString().padLeft(4, '0') +
        '-' +
        _date.month.toString().padLeft(2, '0') +
        '-' +
        _date.day.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: Text(l10n.paperGenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(l10n.paperGenDate),
              subtitle: Text(dateText),
              trailing: TextButton(
                onPressed: _running ? null : _pickDate,
                child: Text(l10n.paperGenChangeDate),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.paperGenIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_running ? l10n.paperGenRunning : l10n.paperGenStart),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodySmall),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_resultPath != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.paperGenDone, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(_resultPath!,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(l10n.paperGenOpenHint,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
