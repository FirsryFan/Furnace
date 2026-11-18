import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../data/database/database.dart';
import '../../../data/package/tfpkg_service.dart';

/// 7 类统一导出：一个 ZIP，里面按类别放 JSON + manifest。
///
/// 数据来自 `TfpkgService.exportDump`（全部 user tables 的逻辑 dump），
/// 因此不需要新 schema，也不会漏掉未分类表：未映射表进 `other_tables.json`。
///
/// **技能/插件**不在 Furnace 数据库里（属于 DSH profile），这里只能如实写
/// `available: false`，不伪造“已导出”。
class SevenCategoryExport {
  const SevenCategoryExport(this._db);

  final AppDatabase _db;

  static const Map<String, List<String>> categories = {
    'tags': ['tags', 'object_tags'],
    'schedule': [
      'tasks',
      'task_dependencies',
      'time_blocks',
      'task_time_blocks',
      'thread_states',
      'task_templates',
      'completion_logs',
      'review_group_plans',
      'review_logs',
      'exposure_logs',
    ],
    'question_bank': [
      'questions',
      'question_options',
      'question_attempts',
      'question_serial_counters',
      'reasoning_chains',
      'reasoning_steps',
      'content_refs',
      'knowledge_edges',
      'handwriting_intake_runs',
      'handwriting_proposals',
      'material_intake_batches',
      'material_intake_proposals',
      'material_intake_undo_logs',
    ],
    'flashcards': [
      'knowledge_points',
      'card_templates',
      'card_states',
      'review_logs',
      'exposure_logs',
      'cloze_slots',
      'cloze_history',
      'boost_entries',
      'diffusion_logs',
    ],
    'agent_sessions': ['ai_conversations', 'ai_messages', 'ai_actions'],
    'skills_plugins': const <String>[],
    'presets_matrices': [
      'profiles',
      'local_settings',
      'ability_scores',
      'assessment_sessions',
      'assessment_responses',
      'cognitive_priors',
      'cog_assessment_tasks',
      'cog_assessment_sessions',
      'cog_assessment_trials',
      'cog_assessment_metrics',
      'cog_ability_estimates',
      'cog_cognitive_params',
    ],
  };

  Future<Uint8List> buildBytes() async {
    final dump = await TfpkgService(_db).exportDump(excludeSensitive: false);
    final used = <String>{};
    final archive = Archive();
    final manifest = <String, Object?>{};

    void addJson(String name, Object? value) {
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(value));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    for (final entry in categories.entries) {
      final category = entry.key;
      final tables = <String, Object?>{};
      for (final table in entry.value) {
        used.add(table);
        tables[table] = dump.tables[table] == null
            ? const <String, Object?>{'rows': <Object?>[]}
            : {
                'rows': dump.tables[table]!.rows,
              };
      }
      if (category == 'skills_plugins') {
        tables['note'] = const {
          'available': false,
          'reason':
              'Skills/plugins live outside the Furnace database (DSH profile). '
              'They are not silently copied into this bundle.',
        };
      }
      addJson('$category.json', tables);
      manifest[category] = {
        'tables': entry.value,
        'table_count': entry.value.length,
        'available': category != 'skills_plugins',
      };
    }

    final other = <String, Object?>{
      for (final table in dump.tables.keys)
        if (!used.contains(table)) table: {'rows': dump.tables[table]!.rows},
    };
    addJson('other_tables.json', other);
    addJson('manifest.json', {
      'format': 'furnace.export/7',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'categories': manifest,
      'other_tables': other.keys.toList(),
      'skills_plugins_available': false,
    });

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
