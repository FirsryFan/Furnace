import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/entities/knowledge_point.dart' as domain;
import '../../../domain/services/cloze/cloze_generator.dart';
import '../application/anki_stats_service.dart';

final ankiKnowledgePointsProvider = FutureProvider<List<KnowledgePoint>>((ref) {
  return ref.watch(ankiRepositoryProvider).getKnowledgePoints();
});

final ankiStatsProvider = FutureProvider<AnkiStats>((ref) {
  return ref.watch(ankiStatsServiceProvider).load();
});

/// Anki management: create knowledge points and card templates.
class AnkiManagePage extends ConsumerWidget {
  const AnkiManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kpsAsync = ref.watch(ankiKnowledgePointsProvider);
    final statsAsync = ref.watch(ankiStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ankiManage),
        actions: [
          IconButton(
            tooltip: l10n.ankiNewKnowledgePoint,
            icon: const Icon(Icons.add),
            onPressed: () => _createKnowledgePoint(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: statsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => Text('$error'),
              data: (stats) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatItem(
                            label: l10n.ankiStats,
                            value: '${stats.knowledgePointCount} KP',
                          ),
                          _StatItem(
                            label: l10n.ankiNewTemplate,
                            value: '${stats.templateCount}',
                          ),
                          _StatItem(
                            label: l10n.ankiNoDueCards,
                            value: '${stats.dueCardCount}',
                          ),
                          _StatItem(
                            label: l10n.ankiReviews7d,
                            value: '${stats.reviewCount7d}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 72,
                        child: _ReviewBarChart(counts: stats.reviewCounts7d),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: kpsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (kps) {
                if (kps.isEmpty) {
                  return Center(
                    child: FilledButton.icon(
                      onPressed: () => _createKnowledgePoint(context, ref),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.ankiNewKnowledgePoint),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: kps.length,
                  itemBuilder: (context, index) {
                    final kp = kps[index];
                    return ListTile(
                      title: Text(kp.title),
                      subtitle: Text(kp.content),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.ankiAutoBlank,
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: () => _autoBlank(context, ref, kp),
                          ),
                          IconButton(
                            tooltip: l10n.commonEdit,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editKnowledgePoint(context, ref, kp),
                          ),
                          IconButton(
                            tooltip: l10n.ankiNewTemplate,
                            icon: const Icon(Icons.add_card),
                            onPressed: () => _createTemplate(context, ref, kp),
                          ),
                          IconButton(
                            tooltip: l10n.commonDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteKnowledgePoint(context, ref, kp),
                          ),
                        ],
                      ),
                      onTap: () => _showTemplates(context, ref, kp),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createKnowledgePoint(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final sourceController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ankiNewKnowledgePoint),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.commonTitle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.commonContent),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sourceController,
              decoration: InputDecoration(labelText: l10n.ankiSource),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }
    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      return;
    }
    await ref.read(ankiRepositoryProvider).createKnowledgePoint(
          title: title,
          content: content,
          source: sourceController.text.trim(),
        );
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
  }

  Future<void> _autoBlank(
    BuildContext context,
    WidgetRef ref,
    KnowledgePoint kp,
  ) async {
    final l10n = AppLocalizations.of(context);
    final domainKp = domain.KnowledgePoint(
      id: kp.id,
      title: kp.title,
      content: kp.content,
      source: kp.source,
    );
    final template = ClozeGenerator.generateFillBlank(domainKp);
    if (template == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.ankiAutoBlank}: null')),
        );
      }
      return;
    }
    final created = await ref.read(ankiRepositoryProvider).createTemplate(
          knowledgePointId: kp.id,
          type: 'fill_blank',
          question: template.question,
          answer: template.answer,
          clozeTemplate: template.clozeTemplate,
        );
    await ref.read(ankiRepositoryProvider).getOrCreateCardState(created.id);
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
  }

  Future<void> _editKnowledgePoint(
    BuildContext context,
    WidgetRef ref,
    KnowledgePoint kp,
  ) async {
    final l10n = AppLocalizations.of(context);
    final titleController = TextEditingController(text: kp.title);
    final contentController = TextEditingController(text: kp.content);
    final sourceController = TextEditingController(text: kp.source ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.commonEdit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.commonTitle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.commonContent),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sourceController,
              decoration: InputDecoration(labelText: l10n.ankiSource),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }
    await ref.read(ankiRepositoryProvider).updateKnowledgePoint(
          kp.id,
          title: titleController.text.trim(),
          content: contentController.text.trim(),
          source: sourceController.text.trim(),
        );
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
  }

  Future<void> _deleteKnowledgePoint(
    BuildContext context,
    WidgetRef ref,
    KnowledgePoint kp,
  ) async {
    await ref.read(ankiRepositoryProvider).deleteKnowledgePoint(kp.id);
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
  }

  Future<void> _createTemplate(
    BuildContext context,
    WidgetRef ref,
    KnowledgePoint kp,
  ) async {
    final l10n = AppLocalizations.of(context);
    final questionController = TextEditingController();
    final answerController = TextEditingController();
    final optionsController = TextEditingController();
    var type = 'fill_blank';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.ankiNewTemplate),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: InputDecoration(labelText: l10n.ankiType),
                  items: [
                    DropdownMenuItem(
                      value: 'fill_blank',
                      child: Text(l10n.ankiTypeFillBlank),
                    ),
                    DropdownMenuItem(
                      value: 'mcq',
                      child: Text(l10n.ankiTypeMcq),
                    ),
                    DropdownMenuItem(
                      value: 'essay',
                      child: Text(l10n.ankiTypeEssay),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: questionController,
                  decoration: InputDecoration(labelText: l10n.ankiQuestion),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answerController,
                  decoration: InputDecoration(labelText: l10n.ankiAnswer),
                ),
                if (type == 'mcq') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: optionsController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.ankiOptions,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }
    final question = questionController.text.trim();
    final answer = answerController.text.trim();
    if (question.isEmpty || answer.isEmpty) {
      return;
    }
    final options = optionsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final template = await ref.read(ankiRepositoryProvider).createTemplate(
          knowledgePointId: kp.id,
          type: type,
          question: question,
          answer: answer,
          options: options,
        );
    await ref.read(ankiRepositoryProvider).getOrCreateCardState(template.id);
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
  }

  Future<CardTemplate?> _editTemplate(
    BuildContext context,
    WidgetRef ref,
    CardTemplate template,
  ) async {
    final l10n = AppLocalizations.of(context);
    final questionController = TextEditingController(text: template.question);
    final answerController = TextEditingController(text: template.answer);
    final optionsController = TextEditingController(
      text: template.options == null
          ? ''
          : template.options!.split('\u0001').join('\n'),
    );
    var type = template.type;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.commonEdit),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: InputDecoration(labelText: l10n.ankiType),
                  items: [
                    DropdownMenuItem(
                      value: 'fill_blank',
                      child: Text(l10n.ankiTypeFillBlank),
                    ),
                    DropdownMenuItem(
                      value: 'mcq',
                      child: Text(l10n.ankiTypeMcq),
                    ),
                    DropdownMenuItem(
                      value: 'essay',
                      child: Text(l10n.ankiTypeEssay),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: questionController,
                  decoration: InputDecoration(labelText: l10n.ankiQuestion),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answerController,
                  decoration: InputDecoration(labelText: l10n.ankiAnswer),
                ),
                if (type == 'mcq') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: optionsController,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.ankiOptions),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return null;
    }
    final options = optionsController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await ref.read(ankiRepositoryProvider).updateTemplate(
          template.id,
          type: type,
          question: questionController.text.trim(),
          answer: answerController.text.trim(),
          options: options,
        );
    ref.invalidate(ankiKnowledgePointsProvider);
    ref.invalidate(ankiStatsProvider);
    return await ref.read(ankiRepositoryProvider).getCardTemplateById(template.id);
  }

  Future<void> _showTemplates(
    BuildContext context,
    WidgetRef ref,
    KnowledgePoint kp,
  ) async {
    final l10n = AppLocalizations.of(context);
    var templates = await ref
        .read(ankiRepositoryProvider)
        .getTemplatesForKnowledgePoint(kp.id);
    var kpTags = await ref
        .read(tagRepositoryProvider)
        .tagsForObject(objectType: 'knowledge_point', objectId: kp.id);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(kp.title),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.tagsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.commonAdd,
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final allTags = await ref
                            .read(tagRepositoryProvider)
                            .getAllTags();
                        final existingIds =
                            kpTags.map((t) => t.id).toSet();
                        final candidates = allTags
                            .where((t) => !existingIds.contains(t.id))
                            .toList();
                        if (candidates.isEmpty) {
                          return;
                        }
                        final selected = await showDialog<Tag>(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: Text(l10n.tagsTitle),
                            children: [
                              for (final tag in candidates)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(ctx, tag),
                                  child: Text(tag.name),
                                ),
                            ],
                          ),
                        );
                        if (selected != null) {
                          await ref
                              .read(tagRepositoryProvider)
                              .addTagToObject(
                                tagId: selected.id,
                                objectType: 'knowledge_point',
                                objectId: kp.id,
                              );
                          setState(() {
                            kpTags = [...kpTags, selected];
                          });
                        }
                      },
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tag in kpTags)
                      Chip(
                        label: Text(tag.name),
                        onDeleted: () async {
                          await ref
                              .read(tagRepositoryProvider)
                              .removeTagFromObject(
                                tagId: tag.id,
                                objectType: 'knowledge_point',
                                objectId: kp.id,
                              );
                          setState(() {
                            kpTags = [
                              for (final t in kpTags)
                                if (t.id != tag.id) t,
                            ];
                          });
                        },
                      ),
                  ],
                ),
                const Divider(),
                for (final template in templates)
                  ListTile(
                    title: Text(template.question),
                    subtitle: Text(template.answer),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.commonEdit,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final updated = await _editTemplate(
                              context,
                              ref,
                              template,
                            );
                            if (updated != null) {
                              setState(() {
                                templates = [
                                  for (final t in templates)
                                    if (t.id == template.id) updated else t,
                                ];
                              });
                            }
                          },
                        ),
                        IconButton(
                          tooltip: l10n.commonDelete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(ankiRepositoryProvider)
                                .deleteTemplate(template.id);
                            setState(() {
                              templates = [
                                for (final t in templates)
                                  if (t.id != template.id) t,
                              ];
                            });
                            ref.invalidate(ankiKnowledgePointsProvider);
                            ref.invalidate(ankiStatsProvider);
                          },
                        ),
                      ],
                    ),
                  ),
                if (templates.isEmpty)
                  ListTile(title: Text(l10n.ankiNoDueCards)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.commonClose),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ReviewBarChart extends StatelessWidget {
  const _ReviewBarChart({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold(0, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final count in counts)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                height: maxCount == 0 ? 4 : (count / maxCount) * 60 + 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
