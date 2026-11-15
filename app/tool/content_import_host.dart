/// 内容包 / 整卷导入的 Flutter host（task-83 + task-88，2026-11-15）：真正打开
/// `AppDatabase`，在事务里重放/提交 `ContentPackageImportService` 或
/// `ExamPaperQuestionImporter`。
///
/// 这个文件**只能**在 Flutter 运行时里编译（`database.dart -> app_storage.dart
/// -> path_provider -> package:flutter -> dart:ui`），所以它不自己启动：
///
///  * 命令行入口是 `tool/content_import_cli.dart`（纯 Dart：参数、备份、副本、
///    SHA256 见证、渲染），由它用 `flutter test --plain-name
///    "content import cli host"` 拉起本文件的调用；
///  * host 用例在 `test/tool/content_import_cli_test.dart`，通过环境变量
///    `CONTENT_IMPORT_REQUEST` / `CONTENT_IMPORT_RESULT` 交换 JSON；
///  * 单元测试直接调 [executeContentImport] / [executeExamPaperImport]
///    （内存库），把 dry-run 回滚、apply 幂等、失败回滚钉在测试里。
///
/// 整卷模式（`paper_dirs` 非空）与内容包模式的差别：
///  * 输入是 `paper.json`/`manifest.json`，由 `ExamPaperQuestionImporter` 按题
///    导入，幂等键是 `content_refs.content_id = <paperKey>#Q<n>`；
///  * 图片必须经 `QuestionMediaStore` 落盘，所以请求带 `media_dir`；dry-run 的
///    host 在回滚后**删除本次新写的图片目录**（CLI 还会把整个临时副本删掉），
///    apply 失败也删除本次新写的图片目录，不留孤儿文件；
///  * 统计口径是题/选项/图/引用（`exam_counts_*`），与内容包的 9 张表计数分开。
///
/// 事务语义：
///  * **整批一个外层事务**：任一包/卷抛错 → 外层事务回滚，之前已导入的也一起
///    回滚（服务自己的内层 `db.transaction` 走 drift 的嵌套事务/savepoint）；
///  * **dry-run = 真跑 + 故意抛哨兵回滚**：[executeContentImport] /
///    [executeExamPaperImport] 在事务里把所有输入跑一遍、记下
///    `counts_after_import`，然后抛 [_DryRunRollback] 让 drift 回滚；
///  * **apply 不额外重试**：失败就如实返回 `ok:false` + 错误文本，由 CLI 决定
///    退出码。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'package:furnace/data/content/content_package_reader.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/content/content_package.dart';
import 'package:furnace/domain/services/content/content_package_import_service.dart';
import 'package:furnace/features/questions/application/exam_paper_question_importer.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

import 'content_import_cli.dart'
    show
        contentImportRequestSchema,
        contentImportResultSchema,
        kFurnaceSchemaVersion;

/// 造一个导入服务（测试注入会抛错/换仓储的实现）。
typedef ContentImportServiceFactory = ContentPackageImportService Function(
  AppDatabase db,
);

/// 默认工厂：生产语义，不覆盖仓储。
ContentPackageImportService _defaultServiceFactory(AppDatabase db) =>
    ContentPackageImportService(db);

/// 一次 host 请求的解析结果。
class ContentImportHostConfig {
  const ContentImportHostConfig({
    required this.mode,
    this.packageDirs = const <String>[],
    this.paperDirs = const <String>[],
    this.mediaDir,
    this.dbPath,
    this.kpMap = const <String, String>{},
    this.createKnowledgePoints = true,
    this.cards = false,
    this.cardsApply = false,
    this.now,
  });

  /// `packages` / `papers` / `dry_run` / `apply`。
  final String mode;

  /// 内容包目录（`packages`/`dry_run`/`apply` 的内容包来源）。
  final List<String> packageDirs;

  /// 整卷目录（`papers`/`dry_run`/`apply` 的整卷来源）。
  final List<String> paperDirs;

  /// 整卷图片落盘根（`QuestionMediaStore` 的 support 根）。整卷 dry-run 时是
  /// CLI 临时副本里的子目录；apply 时由用户显式给 `--media-dir`。
  final String? mediaDir;

  final String? dbPath;
  final Map<String, String> kpMap;
  final bool createKnowledgePoints;
  final bool cards;
  final bool cardsApply;
  final DateTime? now;

  static ContentImportHostConfig fromJson(Map<String, Object?> json) {
    final schema = '${json['schema'] ?? ''}';
    if (schema != contentImportRequestSchema) {
      throw StateError('未知请求 schema：$schema（期望 $contentImportRequestSchema）');
    }
    final mode = '${json['mode'] ?? ''}';
    if (!const <String>{'packages', 'papers', 'dry_run', 'apply'}
        .contains(mode)) {
      throw StateError('未知 host 模式：$mode');
    }
    final packageDirs = <String>[
      for (final value in (json['package_dirs'] as List? ?? const <Object?>[]))
        if ('$value'.trim().isNotEmpty) '$value'.trim(),
    ];
    final paperDirs = <String>[
      for (final value in (json['paper_dirs'] as List? ?? const <Object?>[]))
        if ('$value'.trim().isNotEmpty) '$value'.trim(),
    ];
    if (packageDirs.isNotEmpty && paperDirs.isNotEmpty) {
      throw StateError('host 请求不能同时给 package_dirs 与 paper_dirs');
    }
    if (mode == 'packages' && packageDirs.isEmpty) {
      throw StateError('host 请求没有 package_dirs');
    }
    if (mode == 'papers' && paperDirs.isEmpty) {
      throw StateError('host 请求没有 paper_dirs');
    }
    if (mode == 'dry_run' || mode == 'apply') {
      if (packageDirs.isEmpty && paperDirs.isEmpty) {
        throw StateError('host 模式 $mode 需要 package_dirs 或 paper_dirs');
      }
    }
    final mediaDir = '${json['media_dir'] ?? ''}'.trim();
    if (paperDirs.isNotEmpty &&
        mode == 'apply' &&
        mediaDir.isEmpty) {
      throw StateError('整卷 apply 需要 media_dir（QuestionMediaStore 根）');
    }
    final dbPath = '${json['db_path'] ?? ''}'.trim();
    if (mode != 'packages' && mode != 'papers' && dbPath.isEmpty) {
      throw StateError('host 模式 $mode 需要 db_path');
    }
    final kpMap = <String, String>{};
    final rawMap = json['kp_map'];
    if (rawMap is Map) {
      for (final entry in rawMap.entries) {
        final key = '${entry.key}'.trim();
        final value = '${entry.value}'.trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          kpMap[key] = value;
        }
      }
    }
    final nowRaw = '${json['now'] ?? ''}'.trim();
    return ContentImportHostConfig(
      mode: mode,
      packageDirs: packageDirs,
      paperDirs: paperDirs,
      mediaDir: mediaDir.isEmpty ? null : mediaDir,
      dbPath: dbPath.isEmpty ? null : dbPath,
      kpMap: kpMap,
      createKnowledgePoints: json['create_knowledge_points'] != false,
      cards: json['cards'] == true,
      cardsApply: json['cards_apply'] == true,
      now: nowRaw.isEmpty ? null : DateTime.parse(nowRaw),
    );
  }
}

/// host 入口：读请求 → 解析输入（内容包 / 整卷）→ 打开库 → 执行 → 返回 JSON。
Future<Map<String, Object?>> runContentImportHost(
  Map<String, Object?> request,
) async {
  final config = ContentImportHostConfig.fromJson(request);

  // 整卷来源（task-88）：只解析清单，或加载整卷后在库里导入。
  if (config.mode == 'papers') {
    return _listExamPapers(config.paperDirs);
  }
  if (config.paperDirs.isNotEmpty) {
    return _importExamPapers(config);
  }

  const reader = ContentPackageReader();
  final packageDirs = <String>[];
  final packages = <ContentPackage>[];
  final warningsByDir = <String, List<String>>{};
  final parseErrors = <Map<String, Object?>>[];
  for (final dir in config.packageDirs) {
    try {
      final read = reader.readDirectory(dir);
      packageDirs.add(dir);
      packages.add(read.package);
      warningsByDir[dir] = read.warnings;
    } catch (error) {
      parseErrors.add(<String, Object?>{
        'package_dir': dir,
        'error': '$error',
      });
    }
  }
  if (parseErrors.isNotEmpty) {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': config.mode,
      'error': '内容包解析失败：${parseErrors.length} 个',
      'parse_errors': parseErrors,
    };
  }

  if (config.mode == 'packages') {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': true,
      'mode': 'packages',
      'packages': <Map<String, Object?>>[
        for (var i = 0; i < packages.length; i++)
          _packageListing(
            packages[i],
            packageDirs[i],
            warningsByDir[packageDirs[i]] ?? const <String>[],
          ),
      ],
    };
  }

  final dbPath = config.dbPath!;
  final dbFile = File(dbPath);
  if (!dbFile.existsSync()) {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': config.mode,
      'error': '数据库不存在：$dbPath',
    };
  }
  final db = AppDatabase.forTesting(NativeDatabase(dbFile));
  try {
    final result = await executeContentImport(
      db,
      mode: config.mode,
      packages: packages,
      packageDirs: packageDirs,
      kpMap: config.kpMap,
      createKnowledgePoints: config.createKnowledgePoints,
      cards: config.cards,
      cardsApply: config.cardsApply,
      now: config.now,
    );
    return <String, Object?>{...result, 'db_path': dbFile.absolute.path};
  } finally {
    await db.close();
  }
}

/// 一次整卷导入的图片落盘根（测试可注入失败实现）。
typedef ExamPaperMediaStoreFactory = QuestionMediaStore Function(
  AppDatabase db,
  String mediaRoot,
);

/// 默认图片落盘：`<mediaRoot>/question_images/<questionId>/<attId>/<file>`，
/// 与产品运行时 `AppStorage.supportDirectory` 的目录约定一致。
QuestionMediaStore _defaultExamPaperMediaStore(
  AppDatabase db,
  String mediaRoot,
) =>
    QuestionMediaStore(
      database: db,
      supportDirectory: () async => Directory(mediaRoot),
    );

/// 只解析整卷（`papers` 模式，不打开库）。
Future<Map<String, Object?>> _listExamPapers(List<String> dirs) async {
  final papers = <Map<String, Object?>>[];
  final parseErrors = <Map<String, Object?>>[];
  for (final dir in dirs) {
    try {
      final paper = ExamPaperDocument.loadDirectory(dir);
      papers.add(_paperListing(paper, dir));
    } catch (error) {
      parseErrors.add(<String, Object?>{'paper_dir': dir, 'error': '$error'});
    }
  }
  if (parseErrors.isNotEmpty) {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': 'papers',
      'error': '整卷解析失败：${parseErrors.length} 个',
      'parse_errors': parseErrors,
    };
  }
  return <String, Object?>{
    'schema': contentImportResultSchema,
    'ok': true,
    'mode': 'papers',
    'papers': papers,
  };
}

/// 加载卷目录 → 打开库 → [executeExamPaperImport]。
Future<Map<String, Object?>> _importExamPapers(
  ContentImportHostConfig config,
) async {
  final papers = <ExamPaperDocument>[];
  final paperDirs = <String>[];
  final parseErrors = <Map<String, Object?>>[];
  for (final dir in config.paperDirs) {
    try {
      papers.add(ExamPaperDocument.loadDirectory(dir));
      paperDirs.add(dir);
    } catch (error) {
      parseErrors.add(<String, Object?>{'paper_dir': dir, 'error': '$error'});
    }
  }
  if (parseErrors.isNotEmpty) {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': config.mode,
      'error': '整卷解析失败：${parseErrors.length} 个',
      'parse_errors': parseErrors,
    };
  }
  final dbPath = config.dbPath!;
  final dbFile = File(dbPath);
  if (!dbFile.existsSync()) {
    return <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': config.mode,
      'error': '数据库不存在：$dbPath',
    };
  }
  final db = AppDatabase.forTesting(NativeDatabase(dbFile));
  try {
    final result = await executeExamPaperImport(
      db,
      mode: config.mode,
      papers: papers,
      paperDirs: paperDirs,
      mediaRoot: config.mediaDir,
      now: config.now,
    );
    return <String, Object?>{...result, 'db_path': dbFile.absolute.path};
  } finally {
    await db.close();
  }
}

/// 整卷清单的一行（`papers` 模式；不打开库）。
Map<String, Object?> _paperListing(ExamPaperDocument paper, String dir) =>
    <String, Object?>{
      'paper_dir': dir,
      'paper_key': paper.paperKey,
      'title': paper.title,
      'subject': paper.subjectKey,
      'year': paper.year,
      'region': paper.region,
      'source_level': paper.sourceLevel,
      'source_level_basis': paper.sourceLevelBasis,
      'question_count': paper.questions.length,
      'option_count': paper.questions
          .fold<int>(0, (sum, question) => sum + question.options.length),
      'stem_figure_count': paper.questions
          .fold<int>(0, (sum, question) => sum + question.stemFigures.length),
      'answer_figure_count': paper.questions
          .fold<int>(0, (sum, question) => sum + question.answerFigures.length),
      'score_total_stated': paper.scoreTotalStated,
      'has_ai_labels': paper.anyAiLabels,
      'has_knowledge_points': paper.anyKnowledgePoints,
    };

/// 整卷一次导入的完整执行（测试直接调用它注入内存库/失败 media store）。
///
/// 与 [executeContentImport] 同一套事务语义：整批一个外层事务，dry-run 跑完
/// 抛哨兵回滚；apply 失败整批回滚。整卷特有的两点：
///  * [mediaRoot] 为 null 时不构造 [QuestionMediaStore]：题干图题会被
///    `ExamPaperQuestionImporter` 拦截（`figure_not_importable_no_media_store`），
///    其余题照常导入 —— 这是「没配图库就别裸挂图」的兜底；
///  * dry-run / 失败时，删除本次在 [mediaRoot] 下新写的 `question_images/<qid>`
///    目录（数据库行已回滚，不能留孤儿文件；CLI 的 dry-run 还会删整个临时副本）。
Future<Map<String, Object?>> executeExamPaperImport(
  AppDatabase db, {
  required String mode,
  required List<ExamPaperDocument> papers,
  List<String>? paperDirs,
  String? mediaRoot,
  DateTime? now,
  ExamPaperMediaStoreFactory? mediaStoreFactory,
}) async {
  if (mode != 'dry_run' && mode != 'apply') {
    throw StateError('executeExamPaperImport 只接受 dry_run/apply，收到 $mode');
  }
  final dryRun = mode == 'dry_run';
  final before = await _readExamCounts(db);
  final mediaBefore = _mediaQuestionDirs(mediaRoot);
  final QuestionMediaStore? mediaStore = mediaRoot == null
      ? null
      : (mediaStoreFactory ?? _defaultExamPaperMediaStore)(db, mediaRoot);
  final importer = ExamPaperQuestionImporter(
    db,
    mediaStore: mediaStore,
    now: now,
  );

  final results = <ExamPaperImportResult>[];
  Map<String, int>? countsAfterImport;
  Object? failure;
  StackTrace? failureStack;
  var committed = false;
  var rolledBack = false;
  final startedAt = DateTime.now();

  try {
    await db.transaction(() async {
      for (final paper in papers) {
        results.add(await importer.importPaper(paper));
      }
      countsAfterImport = await _readExamCounts(db);
      if (dryRun) {
        // 让 drift 回滚整个外层事务：dry-run 不允许留下任何一行。
        throw const _DryRunRollback();
      }
    });
    committed = !dryRun;
  } on _DryRunRollback {
    rolledBack = true;
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
    rolledBack = true;
  }

  final after = await _readExamCounts(db);
  var removedMediaDirs = 0;
  if (dryRun || failure != null) {
    removedMediaDirs = _cleanupNewMediaDirs(mediaRoot, mediaBefore);
  }
  final rollbackVerified = failure != null && _sameCounts(before, after);
  final uninstalled = failure != null;
  final wouldBeCounts = countsAfterImport;
  final aggregate = _aggregateExamResults(results);
  final blockedPapers = results
      .where((result) => result.status == ExamPaperImportStatus.blocked)
      .length;
  return <String, Object?>{
    'schema': contentImportResultSchema,
    'ok': !uninstalled,
    'mode': mode,
    'dry_run': dryRun,
    'app_schema_version': db.schemaVersion,
    'db_schema_version': await _userVersion(db),
    'transaction': <String, Object?>{
      'committed': committed,
      'rolled_back': rolledBack,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': DateTime.now().toUtc().toIso8601String(),
    },
    'exam_counts_before': before,
    'exam_counts_after_import': wouldBeCounts,
    'exam_counts_after': after,
    'counts_delta_would_be':
        wouldBeCounts == null ? null : _delta(before, wouldBeCounts),
    'counts_delta_applied': _delta(before, after),
    'rollback_verified': rollbackVerified,
    'dry_run_rollback_verified': dryRun ? _sameCounts(before, after) : null,
    'media_root': mediaRoot,
    'media_cleanup_removed_dirs': removedMediaDirs,
    'error': failure == null ? null : _describeError(failure),
    if (failure != null) 'error_type': '${failure.runtimeType}',
    if (failureStack != null) 'error_trace_hint': _firstStackFrame(failureStack),
    'papers': <Map<String, Object?>>[
      for (var i = 0; i < results.length; i++)
        <String, Object?>{
          ...results[i].toJson(),
          'paper_dir':
              i < (paperDirs?.length ?? 0) ? paperDirs![i] : '',
        },
    ],
    'summary': <String, Object?>{
      'papers': results.length,
      'blocked_packages': blockedPapers,
      ...aggregate,
    },
  };
}

/// 整卷统计汇总（题/选项/图/引用 + 跳过/拦截）。
Map<String, Object?> _aggregateExamResults(
  List<ExamPaperImportResult> results,
) {
  var questions = 0;
  var created = 0;
  var reused = 0;
  var options = 0;
  var optionsCreated = 0;
  var figures = 0;
  var figuresImported = 0;
  var refs = 0;
  var skipped = 0;
  var blockedIssues = 0;
  for (final result in results) {
    questions += result.questionCount;
    created += result.createdCount;
    reused += result.reusedCount;
    options += result.optionCount;
    figures += result.figureCount;
    figuresImported += result.figuresImported;
    refs += result.contentRefCount;
    skipped += result.skippedCount;
    blockedIssues += result.blockedCount;
    for (final question in result.questions) {
      if (question.created) {
        optionsCreated += question.optionCount;
      }
    }
  }
  return <String, Object?>{
    'questions': questions,
    'created_questions': created,
    'reused_questions': reused,
    'options': options,
    'figures': figures,
    'figures_imported': figuresImported,
    'content_refs': refs,
    'skipped': skipped,
    'blocked_issues': blockedIssues,
    'would_create': <String, Object?>{
      'questions': created,
      'options': optionsCreated,
      'figures': figuresImported,
      'content_refs': created,
    },
  };
}

/// `mediaRoot/question_images/` 下已有的题目目录（rollback 清理用）。
Set<String> _mediaQuestionDirs(String? mediaRoot) {
  if (mediaRoot == null) {
    return const <String>{};
  }
  final root = Directory(p.join(mediaRoot, QuestionMediaStore.directoryName));
  if (!root.existsSync()) {
    return const <String>{};
  }
  return <String>{
    for (final entity in root.listSync())
      if (entity is Directory) entity.path,
  };
}

/// 删除本次新写的 `question_images/<qid>` 目录；返回删了几个。
///
/// 只删「导入前不存在」的目录，绝不清理用户既有配图。目录空后再收掉
/// `question_images` 根（仅当本次刚创建时它才会是空的）。
int _cleanupNewMediaDirs(String? mediaRoot, Set<String> before) {
  if (mediaRoot == null) {
    return 0;
  }
  final root = Directory(p.join(mediaRoot, QuestionMediaStore.directoryName));
  if (!root.existsSync()) {
    return 0;
  }
  var removed = 0;
  for (final entity in root.listSync()) {
    if (entity is! Directory || before.contains(entity.path)) {
      continue;
    }
    try {
      entity.deleteSync(recursive: true);
      removed += 1;
    } on FileSystemException {
      // 清理失败不掩盖导入失败的原始错误。
    }
  }
  if (removed > 0 && root.existsSync() && root.listSync().isEmpty) {
    try {
      root.deleteSync();
    } on FileSystemException {
      // 同上。
    }
  }
  return removed;
}

/// 一次内容包导入的完整执行（测试直接调用它注入内存库/失败仓储）。
///
/// 传入的 [packages] 与 [packageDirs] 一一对应（测试只关心包时可以省掉目录，
/// 报告里的 `package_dir` 就是空串）。
Future<Map<String, Object?>> executeContentImport(
  AppDatabase db, {
  required String mode,
  required List<ContentPackage> packages,
  List<String>? packageDirs,
  Map<String, String> kpMap = const <String, String>{},
  bool createKnowledgePoints = true,
  bool cards = false,
  bool cardsApply = false,
  DateTime? now,
  ContentImportServiceFactory? serviceFactory,
}) async {
  if (mode != 'dry_run' && mode != 'apply') {
    throw StateError('executeContentImport 只接受 dry_run/apply，收到 $mode');
  }
  final dryRun = mode == 'dry_run';
  final service = (serviceFactory ?? _defaultServiceFactory)(db);
  final options = ContentPackageImportOptions(
    createKnowledgePoints: createKnowledgePoints,
    knowledgePointIdByNodeId: kpMap,
    generateCards: cards,
    // dry-run 永远只给卡计划；apply 是否落模板由 cards_apply 决定。
    cardsDryRun: dryRun || !cardsApply,
    now: now,
  );

  final countsBefore = await _readCounts(db);
  final results = <ContentPackageImportResult>[];
  Map<String, int>? countsAfterImport;
  Object? failure;
  StackTrace? failureStack;
  var committed = false;
  var rolledBack = false;
  final startedAt = DateTime.now();

  try {
    await db.transaction(() async {
      for (final package in packages) {
        results.add(await service.importPackage(package, options: options));
      }
      countsAfterImport = await _readCounts(db);
      if (dryRun) {
        // 让 drift 回滚整个外层事务：dry-run 不允许留下任何一行。
        throw const _DryRunRollback();
      }
    });
    committed = !dryRun;
  } on _DryRunRollback {
    rolledBack = true;
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
    rolledBack = true;
  }

  final countsAfter = await _readCounts(db);
  final rollbackVerified =
      failure != null && _sameCounts(countsBefore, countsAfter);
  final uninstalled = failure != null;
  // 闭包里赋值的局部变量不会被提升，先落一个非空副本再算 delta。
  final wouldBeCounts = countsAfterImport;
  final summary = _summarise(
    packages: packages,
    results: results,
    dryRun: dryRun,
    countsBefore: countsBefore,
    countsAfterImport: wouldBeCounts,
  );
  return <String, Object?>{
    'schema': contentImportResultSchema,
    'ok': !uninstalled,
    'mode': mode,
    'dry_run': dryRun,
    'app_schema_version': db.schemaVersion,
    'db_schema_version': await _userVersion(db),
    'transaction': <String, Object?>{
      'committed': committed,
      'rolled_back': rolledBack,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': DateTime.now().toUtc().toIso8601String(),
    },
    'counts_before': countsBefore,
    'counts_after_import': wouldBeCounts,
    'counts_after': countsAfter,
    'counts_delta_would_be':
        wouldBeCounts == null ? null : _delta(countsBefore, wouldBeCounts),
    'counts_delta_applied': _delta(countsBefore, countsAfter),
    'rollback_verified': rollbackVerified,
    'error': failure == null ? null : _describeError(failure),
    if (failure != null) 'error_type': '${failure.runtimeType}',
    if (failureStack != null) 'error_trace_hint': _firstStackFrame(failureStack),
    'packages': <Map<String, Object?>>[
      for (var i = 0; i < results.length; i++)
        _packageResult(
          results[i],
          i < (packageDirs?.length ?? 0) ? packageDirs![i] : '',
        ),
    ],
    'summary': summary,
  };
}

// ---------------------------------------------------------------------------
// 计数
// ---------------------------------------------------------------------------

const List<String> _countedTables = <String>[
  'questions',
  'knowledge_points',
  'content_refs',
  'card_templates',
  'object_tags',
  'tags',
  'card_states',
  'review_logs',
  'question_serial_counters',
];

Future<Map<String, int>> _readCounts(AppDatabase db) async {
  final counts = <String, int>{};
  for (final table in _countedTables) {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM "$table"')
        .getSingle();
    counts[table] = row.read<int>('c');
  }
  return counts;
}

/// 整卷导入关心的四张表：题 / 选项 / 引用 / 配图。
const List<String> _examCountedTables = <String>[
  'questions',
  'question_options',
  'content_refs',
  'attachments',
];

Future<Map<String, int>> _readExamCounts(AppDatabase db) async {
  final counts = <String, int>{};
  for (final table in _examCountedTables) {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM "$table"')
        .getSingle();
    counts[table] = row.read<int>('c');
  }
  return counts;
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Map<String, int> _delta(Map<String, int> before, Map<String, int> after) {
  final keys = <String>{...before.keys, ...after.keys};
  return <String, int>{
    for (final key in keys) key: (after[key] ?? 0) - (before[key] ?? 0),
  };
}

bool _sameCounts(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// 报告
// ---------------------------------------------------------------------------

Map<String, Object?> _packageListing(
  ContentPackage package,
  String dir,
  List<String> warnings,
) =>
    <String, Object?>{
      'package_dir': dir,
      'content_id': package.contentId,
      'subject': package.subject,
      'question_type': package.questionType,
      'title': package.title,
      'version': package.version,
      'content_hash': package.contentHash,
      'knowledge_nodes': package.knowledge.length,
      'knowledge_node_ids': <String>[
        for (final node in package.knowledge) node.nodeId,
      ],
      'dag_nodes': package.dagNodes.length,
      'error_causes': package.errorCauses.length,
      'warnings': warnings,
    };

Map<String, Object?> _packageResult(
  ContentPackageImportResult result,
  String dir,
) {
  final createdPoints =
      result.knowledgePoints.where((point) => point.created).length;
  final mappedPoints =
      result.knowledgePoints.where((point) => point.mapped).length;
  return <String, Object?>{
    ...result.toJson(),
    'package_dir': dir,
    'knowledge_created': createdPoints,
    'knowledge_mapped': mappedPoints,
    'missing_tag_count': result.missingTags.length,
    'skipped_count': result.skipped.length,
    'blocked_count': result.blocked.length,
  };
}

/// 汇总：wouldCreate / skipped / 缺标签 / 缺 KP / blocked / kp-map 模板。
Map<String, Object?> _summarise({
  required List<ContentPackage> packages,
  required List<ContentPackageImportResult> results,
  required bool dryRun,
  required Map<String, int> countsBefore,
  required Map<String, int>? countsAfterImport,
}) {
  final questions = results.where((result) => result.questionCreated).length;
  var knowledgePoints = 0;
  var cardsCreated = 0;
  var cardsWouldCreate = 0;
  var skipped = 0;
  var missingTags = 0;
  final missingTagPaths = <String>{};
  var blockedPackages = 0;
  final skippedCodes = <String, int>{};
  final unmapped = <Map<String, Object?>>[];
  final mappedNodes = <String>{};

  for (final result in results) {
    knowledgePoints += result.knowledgePoints.where((p) => p.created).length;
    for (final point in result.knowledgePoints) {
      mappedNodes.add('${result.contentId}\u0000${point.contentNodeId}');
    }
    skipped += result.skipped.length;
    missingTags += result.missingTags.length;
    for (final tag in result.missingTags) {
      missingTagPaths.add(tag.requested);
    }
    for (final skip in result.skipped) {
      skippedCodes[skip.code] = (skippedCodes[skip.code] ?? 0) + 1;
    }
    if (result.blocked.isNotEmpty) {
      blockedPackages += 1;
    }
    final plan = result.cardPlan;
    if (plan != null) {
      cardsCreated += plan.created;
      cardsWouldCreate += plan.wouldCreate;
    }
    for (final skip in result.skipped) {
      if (!const <String>{
        ContentPackageSkipReason.knowledgePointUnmapped,
        ContentPackageSkipReason.knowledgeLabelMissing,
        ContentPackageSkipReason.unknownMappedKnowledgePoint,
      }.contains(skip.code)) {
        continue;
      }
      if (unmapped.any((item) =>
          item['content_node_id'] == skip.detail &&
          item['reason'] == skip.code)) {
        continue;
      }
      unmapped.add(<String, Object?>{
        'content_node_id': skip.detail,
        'label': _labelOfNode(packages, skip.detail),
        'reason': skip.code,
      });
    }
  }

  final kpTemplate = <String, Object?>{};
  for (final package in packages) {
    for (final node in package.knowledge) {
      final id = node.nodeId.trim();
      if (id.isEmpty) {
        continue;
      }
      if (mappedNodes.contains('${package.contentId}\u0000$id')) {
        continue;
      }
      kpTemplate[id] = '';
    }
  }

  final beforeRefs = countsBefore['content_refs'] ?? 0;
  final afterRefs =
      countsAfterImport == null ? beforeRefs : countsAfterImport['content_refs'] ?? 0;
  return <String, Object?>{
    'packages': results.length,
    'blocked_packages': blockedPackages,
    'would_create': <String, Object?>{
      'questions': questions,
      'knowledge_points': knowledgePoints,
      'content_refs': afterRefs - beforeRefs,
      'cards': dryRun ? cardsWouldCreate : cardsCreated,
      'cards_created': cardsCreated,
      'cards_would_create': cardsWouldCreate,
    },
    'existing_questions': results.length - questions,
    'skipped': skipped,
    'skipped_by_code': skippedCodes,
    'missing_tags': missingTags,
    'missing_tag_paths': missingTagPaths.toList()..sort(),
    'unmapped_knowledge_points': unmapped.length,
    'unmapped_knowledge_points_detail': unmapped,
    'kp_map_template': kpTemplate,
    'source_analysis_visible': <String, Object?>{
      for (final result in results)
        result.contentId: result.skipped.any(
          (skip) => skip.code == ContentPackageSkipReason.solutionSuppressed,
        )
            ? false
            : null,
    },
  };
}

String _labelOfNode(List<ContentPackage> packages, String nodeId) {
  for (final package in packages) {
    for (final node in package.knowledge) {
      if (node.nodeId.trim() == nodeId) {
        return node.label;
      }
    }
  }
  return '';
}

String _describeError(Object error) {
  final text = '$error';
  return text.length <= 4000 ? text : text.substring(0, 4000);
}

String _firstStackFrame(StackTrace stack) {
  final lines = '$stack'.split('\n');
  return lines.isEmpty ? '' : lines.first.trim();
}

/// dry-run 用的回滚哨兵（不是错误：只用来触发 drift 回滚）。
class _DryRunRollback implements Exception {
  const _DryRunRollback();
}

// ---------------------------------------------------------------------------
// 宿主用例之外的便捷：把 request/result 文件对读一遍（host 用例用）
// ---------------------------------------------------------------------------

/// 读 `CONTENT_IMPORT_REQUEST` 指向的 JSON，执行，写
/// `CONTENT_IMPORT_RESULT`，并返回结果（host 用例与手工复现共用）。
Future<Map<String, Object?>> runContentImportHostFromFiles({
  required String requestPath,
  required String resultPath,
}) async {
  final decoded = jsonDecode(File(requestPath).readAsStringSync());
  if (decoded is! Map) {
    throw StateError('请求文件顶层应为 JSON 对象：$requestPath');
  }
  final request = decoded.cast<String, Object?>();
  Map<String, Object?> result;
  try {
    result = await runContentImportHost(request);
  } catch (error, stack) {
    result = <String, Object?>{
      'schema': contentImportResultSchema,
      'ok': false,
      'mode': '${request['mode']}',
      'error': _describeError(error),
      'error_type': '${error.runtimeType}',
      'error_trace_hint': _firstStackFrame(stack),
    };
  }
  final file = File(resultPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  return result;
}

/// 让 `kFurnaceSchemaVersion`（纯 Dart 常量）与 drift 的
/// `AppDatabase.schemaVersion` 对得上；host 测试断言这个关系。
int get hostSchemaVersion => kFurnaceSchemaVersion;
