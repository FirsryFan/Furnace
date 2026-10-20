/// 题库包（.tqb）的导出/导入服务（应用层）。
///
/// 四件事：
///  - [QuestionPackService.exportBytes]：读题库（可筛选）→ 打 zip → 返回字节（保存交给 UI）；
///  - [QuestionPackService.peek]：只读清单，给导入前的确认框用；
///  - [QuestionPackService.planImport]：导入前预检（解码 + 对账 + 合并计划，不写库）；
///  - [QuestionPackService.importPack]：解码 → 定合并计划 → 逐题入库 → 存配图。
///
/// 导入口径（与 `docs/QUESTION_BANK_DESIGN.md` §20 一致）：**只新增，不覆盖、
/// 不删除**。同题干（stemFingerprint 相同）跳过并计入 skippedCount；题号不保留，
/// 由 `QuestionRepository.ingest` 重新分配——两台机器各导过同一个包时号会撞，
/// 编号方案本身接受这一点（见 DATA_MODEL §13）。标签只挂题库里**已存在**的路径，
/// 缺的写进 warnings。导入前不自动备份：append 模式不会动已有数据。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_info.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/package/question_pack_codec.dart';
import '../../../data/package/question_pack_source.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/package/question_pack_import_preview.dart';
import '../../../domain/services/package/question_pack_manifest.dart';
import '../../../domain/services/package/question_pack_plan.dart';
import '../../../domain/services/package/question_pack_record.dart';
import '../../../domain/services/package/question_pack_selection.dart';
import '../data/question_media_store.dart';
import 'question_media_providers.dart';

/// 一次导出的结果（字节 + 计数 + 导出时没带上的告警）。
class QuestionPackExportResult {
  const QuestionPackExportResult({
    required this.bytes,
    required this.questionCount,
    required this.mediaCount,
    this.warnings = const <String>[],
  });

  /// `.tqb` 文件内容。
  final Uint8List bytes;

  /// 包里的题目数（= 题库全部题目）。
  final int questionCount;

  /// 包里的媒体文件数。
  final int mediaCount;

  /// 配图没导出的原因（扩展名不认识 / 读不到字节），给导出后的 SnackBar 用。
  final List<String> warnings;
}

/// 导入前的包子集：只解清单，不碰题目和媒体。
class QuestionPackPreview {
  const QuestionPackPreview({
    required this.questionCount,
    required this.mediaCount,
    this.appVersion = '',
    this.exportedAt,
  });

  /// 清单里写的题目数。
  final int questionCount;

  /// 清单里写的媒体文件数。
  final int mediaCount;

  /// 导出方 App 版本（旧包可能为空串）。
  final String appVersion;

  /// 导出时间（清单里没有合法时间时为 null）。
  final DateTime? exportedAt;
}

/// 一次导入的结果。
class QuestionPackImportReport {
  const QuestionPackImportReport({
    required this.createdCount,
    required this.skippedCount,
    required this.mediaCount,
    required this.warnings,
    required this.failures,
  });

  /// 新建了几道题。
  final int createdCount;

  /// 因重复跳过了几道题（题库已有 + 包内重复）。
  final int skippedCount;

  /// 落盘了几张配图。
  final int mediaCount;

  /// 不阻断导入的告警（跳过重复、标签缺失、单张配图没存进去）。
  final List<String> warnings;

  /// 单题级失败原因（题干空、入库异常……）；有失败不代表整包失败。
  final List<String> failures;

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasFailures => failures.isNotEmpty;
}

/// 题库包的导出/导入服务。
class QuestionPackService {
  QuestionPackService({
    required AppDatabase database,
    required QuestionRepository questions,
    required QuestionMediaStore mediaStore,
    required TagRepository tags,
  })  : _database = database,
        _questions = questions,
        _mediaStore = mediaStore,
        _tags = tags;

  final AppDatabase _database;
  final QuestionRepository _questions;
  final QuestionMediaStore _mediaStore;
  final TagRepository _tags;

  /// 导出（默认整个、可按 [selection] 筛选）题库为 `.tqb` 字节。
  ///
  /// 筛选只影响包内容与清单计数，不改库；未选中的题不会读配图文件。
  Future<QuestionPackExportResult> exportBytes({
    DateTime? now,
    QuestionPackSelection selection = const QuestionPackSelection(),
  }) async {
    final snapshot = await readQuestionPackSource(
      database: _database,
      readMedia: _mediaStore.readBytes,
      selection: selection,
    );
    final manifest = QuestionPackManifest(
      exportedAt: now ?? DateTime.now(),
      appVersion: kAppVersion,
      questionCount: snapshot.questionCount,
      mediaCount: snapshot.mediaCount,
    );
    final bytes = encodeQuestionPackArchive(
      manifest: manifest,
      records: snapshot.records,
      mediaBytes: snapshot.mediaBytes,
    );
    return QuestionPackExportResult(
      bytes: bytes,
      questionCount: snapshot.questionCount,
      mediaCount: snapshot.mediaCount,
      warnings: snapshot.warnings,
    );
  }

  /// 只读清单；坏包抛 [QuestionPackException] / [FormatException]。
  QuestionPackPreview peek(Uint8List bytes) {
    final manifest = readQuestionPackManifest(bytes);
    return QuestionPackPreview(
      questionCount: manifest.questionCount,
      mediaCount: manifest.mediaCount,
      appVersion: manifest.appVersion,
      exportedAt: manifest.exportedAt,
    );
  }

  /// 导入前预检：解码、对账清单、算出合并计划，**不写库、不落图**。
  ///
  /// 坏包抛 [QuestionPackException] / [FormatException]；只读数据库
  /// （题干指纹与标签路径）来判定会新增还是跳过。
  Future<QuestionPackImportPreview> planImport(Uint8List bytes) async {
    final archive = decodeQuestionPackArchive(bytes);
    final tagByPath = await _tagByPath();
    final plan = planQuestionPackImport(
      records: archive.records,
      fingerprintOf: stemFingerprint,
      existingFingerprints: await _existingFingerprints(),
      existingTagPaths: tagByPath.keys.toSet(),
    );
    return buildQuestionPackImportPreview(
      manifest: archive.manifest,
      records: archive.records,
      plan: plan,
    );
  }

  /// 导入一个题库包：只新增，不覆盖、不删除。
  Future<QuestionPackImportReport> importPack(
    Uint8List bytes, {
    DateTime? now,
  }) async {
    final archive = decodeQuestionPackArchive(bytes);
    final tagByPath = await _tagByPath();
    final plan = planQuestionPackImport(
      records: archive.records,
      fingerprintOf: stemFingerprint,
      existingFingerprints: await _existingFingerprints(),
      existingTagPaths: tagByPath.keys.toSet(),
    );

    final warnings = <String>[...plan.warnings];
    final failures = <String>[];
    var created = 0;
    var mediaSaved = 0;
    var skipped = plan.skipCount;

    for (final decision in plan.decisions) {
      if (decision.action != QuestionPackAction.create) continue;
      final record = archive.records[decision.index];
      final humanIndex = decision.index + 1;

      final tagIds = <String>{};
      for (final rawPath in record.tagPaths) {
        final path = rawPath.trim();
        if (path.isEmpty) continue;
        final tag = tagByPath[path];
        if (tag != null) tagIds.add(tag.id);
      }

      try {
        final result = await _questions.ingest(
          _draftOf(record, tagIds: tagIds),
          now: now,
        );
        if (!result.created) {
          skipped++;
          warnings.add('第 $humanIndex 道题在导入时又发现题库里已有同一道题，跳过');
          continue;
        }
        created++;

        for (final media in record.media) {
          final mediaBytes = archive.mediaBytes[media.packPath];
          if (mediaBytes == null) {
            warnings.add(
              '第 $humanIndex 道题的配图 ${media.packPath} 在包里找不到，没有导入',
            );
            continue;
          }
          final fileName = _fileNameForMedia(media);
          try {
            await _mediaStore.save(
              questionId: result.question.id,
              fileName: fileName,
              bytes: mediaBytes,
              mime: media.mime,
              sortOrder: media.sortOrder,
              role: media.role,
              now: now,
            );
            mediaSaved++;
          } on Object catch (error) {
            warnings.add(
              '第 $humanIndex 道题的配图 $fileName 没存进题库目录：$error',
            );
          }
        }
      } on Object catch (error) {
        failures.add('第 $humanIndex 道题没有导入：$error');
      }
    }

    return QuestionPackImportReport(
      createdCount: created,
      skippedCount: skipped,
      mediaCount: mediaSaved,
      warnings: List<String>.unmodifiable(warnings),
      failures: List<String>.unmodifiable(failures),
    );
  }

  QuestionDraft _draftOf(
    QuestionPackRecord record, {
    required Set<String> tagIds,
  }) {
    final questionType = record.questionType.trim();
    final sourceLevel = record.sourceLevel.trim();
    final origin = record.origin.trim();
    final state = record.state.trim();
    return QuestionDraft(
      stem: record.stem,
      answer: _nullIfBlank(record.answer),
      solution: _nullIfBlank(record.solution),
      subjectKey: record.subjectKey.trim(),
      questionType: questionType.isEmpty ? 'solution' : questionType,
      sourceLevel: sourceLevel.isEmpty ? 'unknown' : sourceLevel,
      sourceLabel: record.sourceLabel.trim(),
      year: record.year,
      region: _nullIfBlank(record.region),
      sourceUrl: _nullIfBlank(record.sourceUrl),
      zujuanQuestionId: _nullIfBlank(record.zujuanQuestionId),
      zujuanBankId: _nullIfBlank(record.zujuanBankId),
      difficulty: record.difficulty,
      difficultySource: _nullIfBlank(record.difficultySource),
      trapNote: _nullIfBlank(record.trapNote),
      origin: origin.isEmpty ? 'manual' : origin,
      state: state.isEmpty ? 'structured' : state,
      options: <QuestionOptionDraft>[
        for (final option in record.options)
          QuestionOptionDraft(
            label: option.label,
            content: option.content,
            isCorrect: option.isCorrect,
            sortOrder: option.sortOrder,
          ),
      ],
      tagIds: tagIds,
    );
  }

  Future<Set<String>> _existingFingerprints() async {
    final query = _database.selectOnly(_database.questions)
      ..addColumns([_database.questions.stemFingerprint]);
    final rows = await query.get();
    final result = <String>{};
    for (final row in rows) {
      final value = row.read(_database.questions.stemFingerprint);
      if (value == null || value.trim().isEmpty) continue;
      result.add(value);
    }
    return result;
  }

  Future<Map<String, Tag>> _tagByPath() async {
    final tags = await _tags.getAllTags();
    final byPath = <String, Tag>{};
    for (final tag in tags) {
      final path = tag.path?.trim() ?? '';
      if (path.isEmpty) continue;
      byPath[path] = tag;
    }
    return byPath;
  }
}

String? _nullIfBlank(String? raw) {
  final trimmed = raw?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// 包内媒体的落盘文件名：优先用包里记的原文件名，没记就用路径最后一段。
String _fileNameForMedia(QuestionPackMedia media) {
  final recorded = media.fileName?.trim() ?? '';
  if (recorded.isNotEmpty) return p.basename(recorded);
  return p.basename(media.packPath);
}

/// 题库包服务（唯一实例，设置页导出/导入共用）。
final Provider<QuestionPackService> questionPackServiceProvider =
    Provider<QuestionPackService>((ref) {
  return QuestionPackService(
    database: ref.watch(appDatabaseProvider),
    questions: ref.watch(questionRepositoryProvider),
    mediaStore: ref.watch(questionMediaStoreProvider),
    tags: ref.watch(tagRepositoryProvider),
  );
});
