/// 题库包（.tqb）的导出/导入服务（应用层）。
///
/// 四件事：
///  - [QuestionPackService.exportBytes]：读题库（可筛选）→ 打 zip → 返回字节（保存交给 UI）；
///  - [QuestionPackService.peek]：只读清单，给导入前的确认框用；
///  - [QuestionPackService.planImport]：导入前预检（解码 + 对账 + 合并计划，不写库）；
///  - [QuestionPackService.importPack]：解码 → 定合并计划 → 备份现有题库 →
///    逐题入库 → 存配图。
///
/// 导入口径（与 `docs/QUESTION_BANK_DESIGN.md` §20/§29 一致）：默认**只新增**，
/// 同题干（stemFingerprint 相同）跳过并计入 skippedCount；题号不保留，由
/// `QuestionRepository.ingest` 重新分配。带 `zujuanQuestionId` 且题库里已有同题号
/// 的题会走 update：题干/答案/解析/来源字段按「包里非空才覆盖」打补丁，配图按
/// 包里出现过的角色整体替换，title/serialNo 保留；更新数记进 updatedCount，
/// 不占 skippedCount。标签只挂题库里**已存在**的路径，缺的写进 warnings。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// 导入前自动备份的目录名（在 app documents 目录下）。
const String kQuestionPackBackupFolderName = 'question_pack_backups';

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
    this.updatedCount = 0,
    this.backupPath,
    this.backupError,
  });

  /// 新建了几道题。
  final int createdCount;

  /// 按组卷网题号更新了几道题库里已有的题（同题号再导入升级答案/配图）。
  final int updatedCount;

  /// 因重复跳过了几道题（题库已有 + 包内重复）。
  final int skippedCount;

  /// 落盘了几张配图。
  final int mediaCount;

  /// 不阻断导入的告警（跳过重复、标签缺失、单张配图没存进去）。
  final List<String> warnings;

  /// 单题级失败原因（题干空、入库异常……）；有失败不代表整包失败。
  final List<String> failures;

  /// 导入前自动备份的 `.tqb` 绝对路径；本机原本没有题目时不备份（null）。
  final String? backupPath;

  /// 备份失败的原因（导入照常进行）；备份成功或不需要备份时为 null。
  final String? backupError;

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasFailures => failures.isNotEmpty;

  /// 这次导入前是否留下了备份文件。
  bool get hasBackup => backupPath != null;
}

/// 一份「导入前自动备份」的 `.tqb` 文件。
///
/// 备份由 [QuestionPackService.importPack] 落盘（题库非空时先整份导出到
/// `<documents>/question_pack_backups/`）；设置页只负责列出与删除。
class QuestionPackBackup {
  const QuestionPackBackup({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  /// 备份文件绝对路径；删除时原样传回 [QuestionPackService.deleteBackup]。
  final String path;

  /// 文件名（不含目录），例如 `题库备份-20261023-060810-123.tqb`。
  final String name;

  /// 文件字节数；显示成可读大小是 UI 的事（服务层不猜格式）。
  final int sizeBytes;

  /// 文件最后修改时间（本地时区）；列表按它新→旧排序。
  final DateTime modifiedAt;
}

/// 题库包的导出/导入服务。
class QuestionPackService {
  QuestionPackService({
    required AppDatabase database,
    required QuestionRepository questions,
    required QuestionMediaStore mediaStore,
    required TagRepository tags,
    Future<Directory> Function()? documentsDirectory,
  })  : _database = database,
        _questions = questions,
        _mediaStore = mediaStore,
        _tags = tags,
        _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  final AppDatabase _database;
  final QuestionRepository _questions;
  final QuestionMediaStore _mediaStore;
  final TagRepository _tags;

  /// backups 落到哪个 documents 目录（测试注入临时目录，生产走 path_provider）。
  final Future<Directory> Function() _documentsDirectory;

  /// 导出（默认整个、可按 [selection] 或 [questionIds] 筛选）题库为 `.tqb` 字节。
  ///
  /// 筛选只影响包内容与清单计数，不改库；未选中的题不会读配图文件。
  /// [questionIds] 是题库页多选后「导出选中」传进来的显式集合，空集合=不约束。
  Future<QuestionPackExportResult> exportBytes({
    DateTime? now,
    QuestionPackSelection selection = const QuestionPackSelection(),
    Set<String> questionIds = const <String>{},
  }) async {
    final snapshot = await readQuestionPackSource(
      database: _database,
      readMedia: _mediaStore.readBytes,
      selection: selection,
      questionIds: questionIds,
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
      existingQuestionIdByZujuanQuestionId:
          await _questions.questionIdsByZujuanQuestionId(),
    );
    return buildQuestionPackImportPreview(
      manifest: archive.manifest,
      records: archive.records,
      plan: plan,
    );
  }

  /// 导入一个题库包：只新增，不覆盖、不删除。
  ///
  /// 写库前若本机已有题目，先把现有题库导出成
  /// `<documents>/question_pack_backups/题库备份-<时间戳>.tqb`；备份失败只记
  /// [QuestionPackImportReport.backupError]，不阻断导入。
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
      existingQuestionIdByZujuanQuestionId:
          await _questions.questionIdsByZujuanQuestionId(),
    );

    final backupNow = now ?? DateTime.now();
    String? backupPath;
    String? backupError;
    if (await _questionCount() > 0) {
      final backup = await _backupCurrentBank(now: backupNow);
      backupPath = backup.path;
      backupError = backup.error;
    }

    final warnings = <String>[...plan.warnings];
    final failures = <String>[];
    var created = 0;
    var updated = 0;
    var mediaSaved = 0;
    var skipped = plan.skipCount;

    for (final decision in plan.decisions) {
      final record = archive.records[decision.index];
      final humanIndex = decision.index + 1;

      final tagIds = <String>{};
      for (final rawPath in record.tagPaths) {
        final path = rawPath.trim();
        if (path.isEmpty) continue;
        final tag = tagByPath[path];
        if (tag != null) tagIds.add(tag.id);
      }

      if (decision.action == QuestionPackAction.update) {
        final existingId = decision.existingQuestionId?.trim() ?? '';
        if (existingId.isEmpty) {
          failures.add('第 $humanIndex 道题计划更新，但没带题库里的题目 id，没有更新');
          continue;
        }
        try {
          final changed = await _questions.updateFromPack(
            questionId: existingId,
            stem: record.stem,
            answer: _nullIfBlank(record.answer),
            solution: _nullIfBlank(record.solution),
            subjectKey: _nullIfBlank(record.subjectKey),
            questionType: _nullIfBlank(record.questionType),
            sourceLevel: _nullIfBlank(record.sourceLevel),
            sourceLabel: _nullIfBlank(record.sourceLabel),
            year: record.year,
            region: _nullIfBlank(record.region),
            sourceUrl: _nullIfBlank(record.sourceUrl),
            zujuanQuestionId: _nullIfBlank(record.zujuanQuestionId),
            zujuanBankId: _nullIfBlank(record.zujuanBankId),
            difficulty: record.difficulty,
            difficultySource: _nullIfBlank(record.difficultySource),
            trapNote: _nullIfBlank(record.trapNote),
            origin: _nullIfBlank(record.origin),
            state: _nullIfBlank(record.state),
            options: <QuestionOptionDraft>[
              for (final option in record.options)
                QuestionOptionDraft(
                  label: option.label,
                  content: option.content,
                  isCorrect: option.isCorrect,
                  sortOrder: option.sortOrder,
                ),
            ],
            additionalTagIds: tagIds,
            now: now,
          );
          if (changed == 0) {
            failures.add(
              '第 $humanIndex 道题要更新的原题（$existingId）在题库里找不到了，没有更新',
            );
            continue;
          }
          final roles = <String>{
            for (final media in record.media)
              if (media.role.trim().isNotEmpty) media.role.trim(),
          };
          if (roles.isNotEmpty) {
            await _mediaStore.deleteForQuestion(existingId, roles: roles);
          }
          updated++;
          mediaSaved += await _saveMediaFor(
            record: record,
            questionId: existingId,
            humanIndex: humanIndex,
            mediaBytes: archive.mediaBytes,
            warnings: warnings,
            now: now,
          );
        } on Object catch (error) {
          failures.add('第 $humanIndex 道题没有更新：$error');
        }
        continue;
      }
      if (decision.action != QuestionPackAction.create) continue;

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
        mediaSaved += await _saveMediaFor(
          record: record,
          questionId: result.question.id,
          humanIndex: humanIndex,
          mediaBytes: archive.mediaBytes,
          warnings: warnings,
          now: now,
        );
      } on Object catch (error) {
        failures.add('第 $humanIndex 道题没有导入：$error');
      }
    }

    return QuestionPackImportReport(
      createdCount: created,
      updatedCount: updated,
      skippedCount: skipped,
      mediaCount: mediaSaved,
      warnings: List<String>.unmodifiable(warnings),
      failures: List<String>.unmodifiable(failures),
      backupPath: backupPath,
      backupError: backupError,
    );
  }

  /// 列出 `<documents>/question_pack_backups/` 里的 `.tqb` 备份，按修改时间新→旧。
  ///
  /// 目录还不存在（从没导入过）返回空表；单个文件读不到 stat 就跳过——列表只是
  /// 给人看的，不该因为一个坏文件整页失败。同一毫秒的备份按文件名升序兜底，
  /// 保证列表顺序确定。
  Future<List<QuestionPackBackup>> listBackups() async {
    final documents = await _documentsDirectory();
    final directory = Directory(
      p.join(documents.path, kQuestionPackBackupFolderName),
    );
    if (!await directory.exists()) {
      return const <QuestionPackBackup>[];
    }
    final backups = <QuestionPackBackup>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.tqb') continue;
      try {
        final stat = await entity.stat();
        backups.add(
          QuestionPackBackup(
            path: entity.path,
            name: p.basename(entity.path),
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } on FileSystemException catch (error) {
        debugPrint('question pack backup stat failed: $error');
      }
    }
    backups.sort((a, b) {
      final byModified = b.modifiedAt.compareTo(a.modifiedAt);
      return byModified != 0 ? byModified : a.name.compareTo(b.name);
    });
    return List<QuestionPackBackup>.unmodifiable(backups);
  }

  /// 删除一份导入前备份；只允许删备份目录里的 `.tqb`。
  ///
  /// 路径先规范化（`normalize` + `absolute`）再校验父目录，防止把库文件或其他
  /// 路径传进来误删；备份目录外的一律抛 [ArgumentError]。文件已经不在了视为删除
  /// 成功——并发下第二个删除动作不该让界面报错。目录外的「不存在路径」同样抛错，
  /// 免得拿任意路径当探针。
  Future<void> deleteBackup(String path) async {
    final documents = await _documentsDirectory();
    final directory = Directory(
      p.join(documents.path, kQuestionPackBackupFolderName),
    );
    final backupDirectory = p.normalize(directory.absolute.path);
    final target = p.normalize(File(path).absolute.path);
    if (p.extension(target).toLowerCase() != '.tqb' ||
        p.dirname(target) != backupDirectory) {
      throw ArgumentError.value(
        path,
        'path',
        '只能删除导入前备份目录里的 .tqb',
      );
    }
    final file = File(target);
    if (!await file.exists()) {
      return;
    }
    await file.delete();
  }

  /// 本机题库现有题目数（一次 COUNT；备份只在这个数 > 0 时做）。
  Future<int> _questionCount() async {
    final count = _database.questions.id.count();
    final row = await (_database.selectOnly(_database.questions)
          ..addColumns([count]))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// 把现有题库导出到 `<documents>/question_pack_backups/`，返回路径或失败原因。
  ///
  /// 备份失败不阻断导入：调用方只把 error 记进 report，导入照常继续。
  Future<({String? path, String? error})> _backupCurrentBank({
    required DateTime now,
  }) async {
    try {
      final result = await exportBytes(now: now);
      final documents = await _documentsDirectory();
      final directory = Directory(
        p.join(documents.path, kQuestionPackBackupFolderName),
      );
      await directory.create(recursive: true);
      final file = await _writeBackupFile(directory, result.bytes, now);
      return (path: file.path, error: null);
    } on Object catch (error) {
      debugPrint('question pack backup failed: $error');
      return (path: null, error: '$error');
    }
  }

  /// 写备份文件；同一毫秒内连续导入时用 `-2`、`-3` 后缀避免覆盖。
  Future<File> _writeBackupFile(
    Directory directory,
    Uint8List bytes,
    DateTime now,
  ) async {
    final base = _backupFileBaseName(now);
    for (var suffix = 1;; suffix++) {
      final name = suffix == 1 ? '$base.tqb' : '$base-$suffix.tqb';
      final file = File(p.join(directory.path, name));
      if (await file.exists()) continue;
      await file.writeAsBytes(bytes, flush: true);
      return file;
    }
  }

  /// 把一道题在包里的配图逐张落到题库目录，返回成功张数（失败只记 warning）。
  Future<int> _saveMediaFor({
    required QuestionPackRecord record,
    required String questionId,
    required int humanIndex,
    required Map<String, Uint8List> mediaBytes,
    required List<String> warnings,
    DateTime? now,
  }) async {
    var saved = 0;
    for (final media in record.media) {
      final bytes = mediaBytes[media.packPath];
      if (bytes == null) {
        warnings.add(
          '第 $humanIndex 道题的配图 ${media.packPath} 在包里找不到，没有导入',
        );
        continue;
      }
      final fileName = _fileNameForMedia(media);
      try {
        await _mediaStore.save(
          questionId: questionId,
          fileName: fileName,
          bytes: bytes,
          mime: media.mime,
          sortOrder: media.sortOrder,
          role: media.role,
          now: now,
        );
        saved++;
      } on Object catch (error) {
        warnings.add(
          '第 $humanIndex 道题的配图 $fileName 没存进题库目录：$error',
        );
      }
    }
    return saved;
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

/// 备份文件名（不含扩展名）：`题库备份-yyyyMMdd-HHmmss-SSS`（含毫秒，避免同秒冲突）。
String _backupFileBaseName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}${two(now.month)}${two(now.day)}';
  final time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final millis = now.millisecond.toString().padLeft(3, '0');
  return '题库备份-$date-$time-$millis';
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
