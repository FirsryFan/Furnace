import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/anki/application/anki_service.dart';
import '../../features/anki/application/anki_stats_service.dart';
import '../../features/packages/application/package_export_service.dart';
import '../../features/packages/application/package_import_service.dart';
import '../../features/tasks/application/task_scheduler_service.dart';
import '../database/app_database_provider.dart';
import 'anki_repository.dart';
import 'diffusion_log_repository.dart';
import 'mind_map_repository.dart';
import 'package_repository.dart';
import 'settings_repository.dart';
import 'tag_repository.dart';
import 'task_repository.dart';
import 'theme_repository.dart';
import 'thread_rank_repository.dart';
import 'thread_state_repository.dart';
import 'time_block_repository.dart';
import 'time_template_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider));
});

/// Appearance themes (spec §4): selection, import and export.
final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  return ThemeRepository(ref.watch(appDatabaseProvider));
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
});

final threadStateRepositoryProvider = Provider<ThreadStateRepository>((ref) {
  return ThreadStateRepository(ref.watch(appDatabaseProvider));
});

/// Public, editable Thread ranking parameters (blueprint P5).
final threadRankRepositoryProvider = Provider<ThreadRankRepository>((ref) {
  return ThreadRankRepository(ref.watch(appDatabaseProvider));
});

/// Daily study ledger for the separate review-insight screen (blueprint 4.4).
final diffusionLogRepositoryProvider =
    Provider<DiffusionLogRepository>((ref) {
  return DiffusionLogRepository(ref.watch(appDatabaseProvider));
});

final ankiRepositoryProvider = Provider<AnkiRepository>((ref) {
  return AnkiRepository(ref.watch(appDatabaseProvider));
});

final ankiServiceProvider = Provider<AnkiService>((ref) {
  return AnkiService(ref.watch(ankiRepositoryProvider));
});

final ankiStatsServiceProvider = Provider<AnkiStatsService>((ref) {
  return AnkiStatsService(ref.watch(ankiRepositoryProvider));
});

final timeBlockRepositoryProvider = Provider<TimeBlockRepository>((ref) {
  return TimeBlockRepository(ref.watch(appDatabaseProvider));
});

/// Weekly/daily schedule templates and Time view preferences (feedback item 3).
final timeTemplateRepositoryProvider = Provider<TimeTemplateRepository>((ref) {
  return TimeTemplateRepository(ref.watch(appDatabaseProvider));
});

final timeViewRepositoryProvider = Provider<TimeViewRepository>((ref) {
  return TimeViewRepository(ref.watch(appDatabaseProvider));
});

final taskSchedulerServiceProvider = Provider<TaskSchedulerService>((ref) {
  return TaskSchedulerService(
    taskRepository: ref.watch(taskRepositoryProvider),
    timeBlockRepository: ref.watch(timeBlockRepositoryProvider),
    tagRepository: ref.watch(tagRepositoryProvider),
  );
});

final mindMapRepositoryProvider = Provider<MindMapRepository>((ref) {
  return MindMapRepository(ref.watch(appDatabaseProvider));
});

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  return PackageRepository(ref.watch(appDatabaseProvider));
});

final packageImportServiceProvider = Provider<PackageImportService>((ref) {
  return PackageImportService(
    packageRepository: ref.watch(packageRepositoryProvider),
    tagRepository: ref.watch(tagRepositoryProvider),
    ankiRepository: ref.watch(ankiRepositoryProvider),
    mindMapRepository: ref.watch(mindMapRepositoryProvider),
  );
});

final packageExportServiceProvider = Provider<PackageExportService>((ref) {
  return PackageExportService(
    tagRepository: ref.watch(tagRepositoryProvider),
    ankiRepository: ref.watch(ankiRepositoryProvider),
    mindMapRepository: ref.watch(mindMapRepositoryProvider),
  );
});
