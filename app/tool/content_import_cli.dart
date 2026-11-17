/// 内容包 / 整卷 → 真实题库的可回滚导入 CLI（task-83 + task-88，2026-11-15）。
///
/// 文档：工作区 `10-projects/agent-control-plane/CONTENT-IMPORT-CLI-2026-11-15.md`
/// （内容包）与 `EXAM-PAPER-CLI-2026-11-15.md`（整卷；用法、备份、apply 前
/// 检查、风险、真库副本验证的真实输出）。
///
/// 两种输入来源共用同一套安全闸门（备份 / dry-run 临时副本 / apply 前检查 /
/// SHA256 见证 / 幂等 / 退出码）：
///
///  * **内容包**（`--packages`）：`content-store/` 下的 `question.json`，
///    由 `ContentPackageImportService` 导入；
///  * **整卷**（`--papers` / `--exam-paper`）：`exam-papers/` 下的
///    `paper.json`（+ 可选 `manifest.json`），由 `ExamPaperQuestionImporter`
///    导入；图片经 `QuestionMediaStore` 落盘，所以 apply 必须显式给
///    `--media-dir`（dry-run 自动用临时目录，跑完删除）。
///
/// 一次只导一种来源：`--packages` 与 `--papers/--exam-paper` 互斥。
///
/// ## 为什么分成「纯 Dart 入口 + Flutter host」两段
///
/// 写产品库必须走 `AppDatabase`，而
/// `database.dart -> app_storage.dart -> path_provider -> package:flutter ->
/// dart:ui`，纯 Dart VM 没有 `dart:ui`（本仓库 `tool/mindnet_probe.dart` 与
/// `test/tool/mindnet_probe_report_test.dart` 记录过同一次测量）。所以：
///
///  * **本文件（纯 Dart，`dart run tool/content_import_cli.dart`）**：参数解析、
///    SQLite 只读检查、备份（`VACUUM INTO`）、dry-run 临时副本、SHA256 见证、
///    启动 host、渲染报告；
///  * **`tool/content_import_host.dart`（只能编译进 Flutter 运行时）**：打开
///    `AppDatabase`、读内容包、在事务里重放/提交导入、返回计数与报告；
///  * **`test/tool/content_import_cli_test.dart`**：host 用例
///    `content import cli host`，由本文件用 `flutter test --plain-name` 拉起。
///
/// ## 安全边界（任务硬约束，写进代码而不是只写进文档）
///
/// 1. **dry-run 不打开原库**：先复制主文件 + `-wal`/`-shm` 到临时目录，只打开
///    副本；host 在副本上把整个导入跑一遍并**回滚事务**，所以报告里的
///    `counts_after_import` 是「真跑一遍会变成什么」，而 `counts_after` 证明
///    回滚干净。
/// 2. **apply 先备份**：默认用 SQLite 的 `VACUUM INTO` 生成
///    `<db>.<yyyyMMdd-HHmmss>.bak`（`--backup-dir` 可改位置），备份后立刻做
///    `PRAGMA integrity_check` 并记 SHA256；`--no-backup` 只允许用在副本上。
/// 3. **真实库要显式授权**：`--apply` 的路径命中已知真实库时，必须同时给
///    `--allow-real-db`，且不允许 `--no-backup`。
/// 4. **原库 SHA256 前后对比**：dry-run 前后变了就是缺陷（退出码 2）。
/// 5. **apply 拒绝活跃 WAL**：发现非空 `-wal` 说明应用可能正开着库，先让用户
///    退出 Furnace，避免两个写者。
///
/// 退出码：0 成功；1 导入失败（事务已回滚）；2 参数/见证缺陷；3 拒绝或找不到
/// 库/包；4 host 失败；5 有包被 blocked（其他包照常写入）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// 复用 `mindnet_probe.dart` 里已被 NIST 向量钉过的 SHA256 与 Flutter 路径解析：
// 完整性见证不应该有第二份实现。测试也从这里拿同一个实现。
import 'mindnet_probe.dart' show resolveFlutterExecutable, sha256HexOfFile;
export 'mindnet_probe.dart' show sha256Hex, sha256HexOfFile;

/// `AppDatabase.schemaVersion`（`app/lib/data/database/database.dart:234`）。
///
/// 纯 Dart 侧读不到 drift 的常量，所以这里保留一个常量；host 会在报告里返回
/// `db.schemaVersion`，测试断言两者相等，避免悄悄漂移。
const int kFurnaceSchemaVersion = 48;

/// host 用例名（`flutter test --plain-name` 选中它）。
const String contentImportHostTestName = 'content import cli host';

/// host 用例所在文件（相对 app 目录）。
const String contentImportHostFile = 'test/tool/content_import_cli_test.dart';

/// 请求/结果的 schema 版本（本文件与 host 的契约）。
const String contentImportRequestSchema = 'content.import.request/1';
const String contentImportResultSchema = 'content.import.result/1';

/// 已知真实库路径（Windows 数据根，见 `app_storage.dart` 的
/// `windowsDataRootPath = E:\Furnace\data`）与 `%APPDATA%` 下的旧目录。
///
/// 这不是「信任清单」，而是 apply 的**默认拒绝清单**：命中就必须
/// `--allow-real-db`。用户把库搬到别处时这张表不会误伤（只是少了这层保护）。
List<String> knownRealDatabasePaths({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final paths = <String>[r'E:\Furnace\data\furnace.db'];
  final appData = env['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    for (final name in const ['furnace.db', 'threadflow.db', 'knowflow.db']) {
      paths.add(p.join(appData, 'FirsryFan', 'Furnace', name));
      paths.add(p.join(appData, 'com.example', 'knowflow', name));
    }
  }
  return paths;
}

/// `--help` 与参数错误时打印。
const String contentImportUsage = '''
内容包 / 整卷 → Furnace 题库的可回滚导入 CLI（默认 dry-run）。

用法（在 `app/` 目录下）：
  dart run tool/content_import_cli.dart <模式> [选项]

先读库（只读，不打开 drift、不迁移）：
  dart run tool/content_import_cli.dart db --db <path>

先看会导入哪些内容包（只解析，不碰库）：
  dart run tool/content_import_cli.dart packages --packages <dir> [--packages <dir> ...]

先看会导入哪些整卷（只解析，不碰库）：
  dart run tool/content_import_cli.dart papers --papers <dir> [--exam-paper <dir> ...]

dry-run 内容包（默认；复制临时副本、真跑一遍、事务回滚）：
  dart run tool/content_import_cli.dart dry-run --db <path> --packages <dir>

dry-run 整卷（同上；图只落临时目录，跑完删除）：
  dart run tool/content_import_cli.dart dry-run --db <path> --papers <dir>

显式 apply 内容包（默认先备份；真实库还要 --allow-real-db）：
  dart run tool/content_import_cli.dart apply --db <path> --packages <dir> [--backup-dir <dir>]

显式 apply 整卷（默认先备份；图落 --media-dir；真实库还要 --allow-real-db）：
  dart run tool/content_import_cli.dart apply --db <path> --papers <dir> --media-dir <dir> [--backup-dir <dir>]

只做备份：
  dart run tool/content_import_cli.dart backup --db <path> [--backup-dir <dir>]

选项：
  --db <path>            要操作的 SQLite 库（备份/apply/dry-run/db）
  --packages <dir>       内容包根目录；递归找 question.json，可重复
  --package <dir>        同上，单个包目录（可重复）
  --papers <dir>         整卷目录根；递归找 paper.json，可重复
  --exam-paper <dir>     单个整卷目录（含 paper.json），可重复
  --media-dir <dir>      整卷 apply 的图片落盘根（QuestionMediaStore 的 support
                         根）；dry-run 自动用临时目录，不允许显式给
  --dry-run              只演练（默认）；复制副本 + 事务回滚
  --apply                真正写库（事务提交；失败回滚）
  --backup               生成带时间戳备份（apply 默认就有）
  --backup-dir <dir>     备份目录（默认 <db 所在目录>/backups）
  --no-backup            apply 时跳过备份（只允许副本，真实库拒绝）
  --kp-map <json>        内容包：内容节点 id → 已有产品 knowledge_points.id
  --create-kps[=false]   内容包：是否允许新建产品知识点（默认 true）
  --no-create-kps        等价 --create-kps=false
  --cards                内容包：尝试把 DAG/错因生成闪存卡
  --cards-apply          内容包：apply 时真正写卡片模板（默认只给卡计划）
  --allow-real-db        允许对已知真实库 apply（仍需先备份）
  --now <iso8601>        固定导入时钟（测试/复现用）
  --report <path>        把机器可读报告写成 JSON 文件
  --json                 直接打印 JSON 报告
  --keep-temp            保留 dry-run 临时副本（排障用）
  --help                 本帮助

内容包（--packages）与整卷（--papers/--exam-paper）一次只能给一种；
整卷模式不建知识点/标签/卡片，所以 --kp-map/--create-kps/--cards 被拒绝。

退出码：0 成功 · 1 导入失败已回滚 · 2 参数/见证缺陷 · 3 拒绝/找不到
        4 host 失败 · 5 有卷/包 blocked（其余已写入）
''';

/// CLI 模式。
enum ContentImportMode {
  /// 只读检查库（schema/计数/完整性/SHA256/WAL）。
  dbInfo,

  /// 只解析内容包（不碰库）。
  packages,

  /// 只解析整卷（不碰库）。
  papers,

  /// 只备份。
  backupOnly,

  /// 复制副本 + 真实导入 + 事务回滚。
  dryRun,

  /// 真正写库（先备份）。
  apply;

  String get wireValue => switch (this) {
        ContentImportMode.dbInfo => 'db',
        ContentImportMode.packages => 'packages',
        ContentImportMode.papers => 'papers',
        ContentImportMode.backupOnly => 'backup',
        ContentImportMode.dryRun => 'dry_run',
        ContentImportMode.apply => 'apply',
      };

  bool get needsDatabase =>
      this != ContentImportMode.packages && this != ContentImportMode.papers;

  bool get needsPackages =>
      this == ContentImportMode.dryRun || this == ContentImportMode.apply;
}

/// 解析后的命令行。
class ContentImportCliOptions {
  const ContentImportCliOptions({
    required this.mode,
    this.dbPath,
    this.packageRoots = const <String>[],
    this.paperRoots = const <String>[],
    this.mediaDir,
    this.backup = false,
    this.noBackup = false,
    this.backupDir,
    this.kpMapPath,
    this.createKnowledgePoints = true,
    this.cards = false,
    this.cardsApply = false,
    this.allowRealDb = false,
    this.now,
    this.reportPath,
    this.json = false,
    this.keepTemp = false,
    this.help = false,
  });

  final ContentImportMode mode;
  final String? dbPath;
  final List<String> packageRoots;

  /// 整卷目录根（`--papers`/`--exam-paper`）。与 [packageRoots] 互斥。
  final List<String> paperRoots;

  /// 整卷 apply 的图片落盘根（`QuestionMediaStore` 的 support 根）。
  final String? mediaDir;

  /// 是否显式要备份（apply 默认就会备份；这里记录命令行是否给了 `--backup`）。
  final bool backup;

  final bool noBackup;
  final String? backupDir;
  final String? kpMapPath;
  final bool createKnowledgePoints;
  final bool cards;
  final bool cardsApply;
  final bool allowRealDb;
  final DateTime? now;
  final String? reportPath;
  final bool json;
  final bool keepTemp;
  final bool help;

  /// 是否整卷来源（`--papers`/`--exam-paper`）。
  bool get examPaperSource => paperRoots.isNotEmpty;

  /// 解析 `dart run tool/content_import_cli.dart ...` 的参数。
  ///
  /// 参数错误一律 [ArgumentError]（退出码 2）；不在这里读盘。
  static ContentImportCliOptions parse(List<String> args) {
    ContentImportMode? explicitMode;
    String? dbPath;
    final packageRoots = <String>[];
    final paperRoots = <String>[];
    String? mediaDir;
    var backupRequested = false;
    var noBackup = false;
    String? backupDir;
    String? kpMapPath;
    var createKnowledgePoints = true;
    var createKpsFlag = false;
    var cards = false;
    var cardsApply = false;
    var allowRealDb = false;
    DateTime? now;
    String? reportPath;
    var json = false;
    var keepTemp = false;
    var help = false;

    void setMode(ContentImportMode next, String source) {
      if (explicitMode != null && explicitMode != next) {
        throw ArgumentError(
          '模式冲突：$source 与已有模式 ${explicitMode!.wireValue}',
        );
      }
      explicitMode = next;
    }

    String valueAfter(int index, String flag) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw ArgumentError('$flag 需要一个值');
      }
      return args[index + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == 'db') {
        setMode(ContentImportMode.dbInfo, arg);
      } else if (arg == 'packages') {
        setMode(ContentImportMode.packages, arg);
      } else if (arg == 'papers') {
        setMode(ContentImportMode.papers, arg);
      } else if (arg == 'dry-run' || arg == 'dry_run') {
        setMode(ContentImportMode.dryRun, arg);
      } else if (arg == 'apply') {
        setMode(ContentImportMode.apply, arg);
      } else if (arg == 'backup') {
        backupRequested = true;
        setMode(ContentImportMode.backupOnly, arg);
      } else if (arg == '--db') {
        dbPath = valueAfter(i, arg);
        i += 1;
      } else if (arg == '--packages' || arg == '--package') {
        packageRoots.add(valueAfter(i, arg));
        i += 1;
      } else if (arg == '--papers' || arg == '--exam-paper') {
        paperRoots.add(valueAfter(i, arg));
        i += 1;
      } else if (arg == '--media-dir') {
        mediaDir = valueAfter(i, arg);
        i += 1;
      } else if (arg == '--dry-run') {
        setMode(ContentImportMode.dryRun, arg);
      } else if (arg == '--apply') {
        setMode(ContentImportMode.apply, arg);
      } else if (arg == '--backup') {
        backupRequested = true;
      } else if (arg == '--backup-dir') {
        backupDir = valueAfter(i, arg);
        i += 1;
      } else if (arg == '--no-backup') {
        noBackup = true;
      } else if (arg == '--kp-map') {
        kpMapPath = valueAfter(i, arg);
        i += 1;
      } else if (arg.startsWith('--kp-map=')) {
        kpMapPath = arg.substring('--kp-map='.length);
      } else if (arg == '--create-kps') {
        createKnowledgePoints = true;
        createKpsFlag = true;
      } else if (arg.startsWith('--create-kps=')) {
        createKnowledgePoints =
            _parseBool(arg.substring('--create-kps='.length), '--create-kps');
        createKpsFlag = true;
      } else if (arg == '--no-create-kps') {
        createKnowledgePoints = false;
        createKpsFlag = true;
      } else if (arg == '--cards') {
        cards = true;
      } else if (arg == '--cards-apply') {
        cardsApply = true;
      } else if (arg == '--allow-real-db') {
        allowRealDb = true;
      } else if (arg == '--now') {
        final raw = valueAfter(i, arg);
        final parsed = DateTime.tryParse(raw);
        if (parsed == null) {
          throw ArgumentError('--now 需要 ISO-8601 时间，收到 $raw');
        }
        now = parsed;
        i += 1;
      } else if (arg == '--report') {
        reportPath = valueAfter(i, arg);
        i += 1;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--keep-temp') {
        keepTemp = true;
      } else if (arg == '--help' || arg == '-h') {
        help = true;
      } else if (arg.startsWith('-')) {
        throw ArgumentError('未知参数：$arg');
      } else {
        throw ArgumentError('未知子命令：$arg');
      }
    }

    if (help) {
      return const ContentImportCliOptions(
        mode: ContentImportMode.dryRun,
        help: true,
      );
    }

    if (noBackup && backupRequested) {
      throw ArgumentError('--backup 与 --no-backup 不能同时给');
    }
    if (noBackup && explicitMode != ContentImportMode.apply) {
      throw ArgumentError('--no-backup 只对 apply 有意义');
    }
    if (cardsApply && explicitMode != ContentImportMode.apply) {
      throw ArgumentError('--cards-apply 只对 apply 有意义');
    }
    if (backupRequested && explicitMode == ContentImportMode.packages) {
      throw ArgumentError('packages 模式不碰库，--backup 无意义');
    }
    if (backupRequested && explicitMode == ContentImportMode.papers) {
      throw ArgumentError('papers 模式不碰库，--backup 无意义');
    }
    if (packageRoots.isNotEmpty && paperRoots.isNotEmpty) {
      throw ArgumentError(
        '--packages 与 --papers/--exam-paper 不能同时给（一次只导一种来源）',
      );
    }

    final mode = explicitMode ??
        (backupRequested
            ? ContentImportMode.backupOnly
            : ContentImportMode.dryRun);

    // 整卷来源的专属/互斥参数。内容包模式保持原样（不破坏既有用法）。
    final hasPapers = paperRoots.isNotEmpty;
    if (hasPapers) {
      if (mode == ContentImportMode.papers && packageRoots.isNotEmpty) {
        throw ArgumentError('papers 模式只读整卷，--packages 无意义');
      }
      if (createKpsFlag || kpMapPath != null || cards || cardsApply) {
        throw ArgumentError(
          '整卷模式不建知识点/标签/卡片，--kp-map/--create-kps/--cards 被拒绝',
        );
      }
      if (mode == ContentImportMode.apply &&
          (mediaDir == null || mediaDir.trim().isEmpty)) {
        throw ArgumentError(
          '整卷 apply 需要 --media-dir <dir>（图片落盘根，'
          'QuestionMediaStore 的 support 根）；dry-run 会使用临时目录',
        );
      }
      if (mode == ContentImportMode.dryRun && mediaDir != null) {
        throw ArgumentError(
          '整卷 dry-run 不接受 --media-dir：图只落临时副本，跑完自动删除',
        );
      }
    } else if (mediaDir != null) {
      throw ArgumentError('--media-dir 只对整卷（--papers/--exam-paper）有意义');
    }

    if (mode.needsDatabase && (dbPath == null || dbPath.trim().isEmpty)) {
      throw ArgumentError('${mode.wireValue} 需要 --db <path>');
    }
    if (mode == ContentImportMode.papers && paperRoots.isEmpty) {
      throw ArgumentError('papers 需要 --papers <dir> 或 --exam-paper <dir>');
    }
    if (mode == ContentImportMode.packages && packageRoots.isEmpty) {
      throw ArgumentError('packages 需要 --packages <dir>');
    }
    if (mode.needsPackages && packageRoots.isEmpty && paperRoots.isEmpty) {
      throw ArgumentError(
        '${mode.wireValue} 需要 --packages <dir> 或 --papers/--exam-paper <dir>',
      );
    }
    if (kpMapPath != null && (!mode.needsPackages || hasPapers)) {
      throw ArgumentError('--kp-map 只对内容包 dry-run/apply 有意义');
    }
    if (mode == ContentImportMode.dryRun && noBackup) {
      throw ArgumentError('dry-run 不写库，--no-backup 无意义');
    }

    return ContentImportCliOptions(
      mode: mode,
      dbPath: dbPath,
      packageRoots: List<String>.unmodifiable(packageRoots),
      paperRoots: List<String>.unmodifiable(paperRoots),
      mediaDir: mediaDir,
      backup: backupRequested ||
          mode == ContentImportMode.apply, // apply 默认就备份
      noBackup: noBackup,
      backupDir: backupDir,
      kpMapPath: kpMapPath,
      createKnowledgePoints: createKnowledgePoints,
      cards: cards,
      cardsApply: cardsApply,
      allowRealDb: allowRealDb,
      now: now,
      reportPath: reportPath,
      json: json,
      keepTemp: keepTemp,
    );
  }

  /// 实际是否要写备份文件。
  bool get writesBackup =>
      !noBackup &&
      (mode == ContentImportMode.apply || mode == ContentImportMode.backupOnly);
}

bool _parseBool(String raw, String flag) {
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
      return false;
  }
  throw ArgumentError('$flag 只接受 true/false，收到 $raw');
}

// ---------------------------------------------------------------------------
// 内容包目录发现（纯 Dart：只找 question.json，不解析内容）
// ---------------------------------------------------------------------------

/// 从 [roots] 递归找出所有内容包目录（含 `question.json` 的目录）。
///
/// 排序固定（绝对路径字典序），所以报告与「第几条」可复现。
List<String> discoverPackageDirs(List<String> roots) {
  final found = <String>{};
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      throw StateError('内容包目录不存在：$root');
    }
    final direct = File(p.join(directory.absolute.path, 'question.json'));
    if (direct.existsSync()) {
      found.add(p.normalize(directory.absolute.path));
      continue;
    }
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (p.basename(entity.path) != 'question.json') {
        continue;
      }
      found.add(p.normalize(p.dirname(entity.absolute.path)));
    }
  }
  final ordered = found.toList()..sort();
  return ordered;
}

// ---------------------------------------------------------------------------
// 整卷目录发现（纯 Dart：只找 paper.json，不解析内容）
// ---------------------------------------------------------------------------

/// 从 [roots] 递归找出所有整卷目录（含 `paper.json` 的目录）。
///
/// 与 [discoverPackageDirs] 同一口径：根目录本身是卷就只收它；否则递归找
/// `paper.json`，去重后按绝对路径字典序排序（报告可复现）。
///
/// `--exam-paper <dir>` 是「单个卷目录」的入口，但这里不区分来源——如果给错
/// 了一个大目录，`--exam-paper` 也会递归找到多卷；调用方在报告里能看到全部。
List<String> discoverPaperDirs(List<String> roots) {
  final found = <String>{};
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      throw StateError('整卷目录不存在：$root');
    }
    final direct = File(p.join(directory.absolute.path, 'paper.json'));
    if (direct.existsSync()) {
      found.add(p.normalize(directory.absolute.path));
      continue;
    }
    for (final entity in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (p.basename(entity.path) != 'paper.json') {
        continue;
      }
      found.add(p.normalize(p.dirname(entity.absolute.path)));
    }
  }
  final ordered = found.toList()..sort();
  return ordered;
}

// ---------------------------------------------------------------------------
// kp-map（内容节点 id → 已有产品知识点 id）
// ---------------------------------------------------------------------------

/// 读 `--kp-map` JSON：`{"kp-node": "kp-uuid"}` 或 `{"mappings": {...}}`。
Map<String, String> loadKnowledgePointMap(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('kp-map 文件不存在：$path');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw StateError('kp-map 不是合法 JSON：$path（${error.message}）');
  }
  if (decoded is! Map) {
    throw StateError('kp-map 顶层应为 JSON 对象：$path');
  }
  final Object? raw = decoded['mappings'] is Map ? decoded['mappings'] : decoded;
  if (raw is! Map) {
    throw StateError('kp-map 的 mappings 应为 JSON 对象：$path');
  }
  final map = <String, String>{};
  for (final entry in raw.entries) {
    final key = '${entry.key}'.trim();
    final value = '${entry.value}'.trim();
    if (key.isEmpty) {
      continue;
    }
    if (value.isEmpty) {
      continue; // 空值 = 留空由 --create-kps 决定，不当作映射。
    }
    map[key] = value;
  }
  return map;
}

// ---------------------------------------------------------------------------
// 只读库检查（纯 Dart sqlite3，不打开 drift，不触发迁移）
// ---------------------------------------------------------------------------

/// 只读库画像：`db` 模式输出，也是 apply 前的检查。
class ContentImportDatabaseInfo {
  const ContentImportDatabaseInfo({
    required this.path,
    required this.bytes,
    required this.sha256,
    required this.schemaVersion,
    required this.integrity,
    required this.walPresent,
    required this.counts,
  });

  final String path;
  final int bytes;
  final String sha256;
  final int schemaVersion;
  final String integrity;
  final bool walPresent;

  /// 表名 → 行数；表不存在时为 null（老库、迁移前）。
  final Map<String, int?> counts;

  static const List<String> countedTables = <String>[
    'questions',
    'knowledge_points',
    'content_refs',
    'card_templates',
    'tags',
    'object_tags',
    'card_states',
    'review_logs',
    'question_serial_counters',
  ];

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'bytes': bytes,
        'sha256': sha256,
        'schema_version': schemaVersion,
        'app_schema_version': kFurnaceSchemaVersion,
        'integrity_check': integrity,
        'wal_present': walPresent,
        'counts': counts,
      };
}

/// 用 SQLite 只读连接读库画像；**不写、不迁移**。
ContentImportDatabaseInfo readDatabaseInfo(String dbPath) {
  final file = File(dbPath);
  if (!file.existsSync()) {
    throw StateError('数据库不存在：$dbPath');
  }
  if (file.lengthSync() == 0) {
    throw StateError('数据库文件为空：$dbPath');
  }
  final walPresent = _walBytes(dbPath) > 0;
  final Database db;
  try {
    db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  } on SqliteException catch (error) {
    throw StateError(
      '打不开数据库（可能损坏/加密/非 SQLite）：$dbPath\n$error',
    );
  }
  try {
    final version = (db.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    final integrity =
        '${db.select('PRAGMA integrity_check').first.values.first}';
    final counts = <String, int?>{};
    for (final table in ContentImportDatabaseInfo.countedTables) {
      final exists = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object?>[table],
      );
      if (exists.isEmpty) {
        counts[table] = null;
        continue;
      }
      counts[table] =
          (db.select('SELECT COUNT(*) AS c FROM "$table"').first['c'] as int?) ??
              0;
    }
    return ContentImportDatabaseInfo(
      path: file.absolute.path,
      bytes: file.lengthSync(),
      sha256: sha256HexOfFile(file),
      schemaVersion: version,
      integrity: integrity,
      walPresent: walPresent,
      counts: counts,
    );
  } on SqliteException catch (error) {
    throw StateError('数据库读取失败（文件损坏？）：$dbPath\n$error');
  } finally {
    db.dispose();
  }
}

int _walBytes(String dbPath) {
  for (final suffix in const ['-wal', '-shm']) {
    final file = File('$dbPath$suffix');
    if (file.existsSync() && file.lengthSync() > 0) {
      return file.lengthSync();
    }
  }
  return 0;
}

// ---------------------------------------------------------------------------
// 备份（SQLite `VACUUM INTO`；源库只读）
// ---------------------------------------------------------------------------

/// 一次备份的结果（路径、大小、哈希、完整性）。
class ContentImportBackup {
  const ContentImportBackup({
    required this.sourcePath,
    required this.backupPath,
    required this.bytes,
    required this.sha256SourceBefore,
    required this.sha256SourceAfter,
    required this.sha256Backup,
    required this.integrityCheck,
    required this.sourceSchemaVersion,
    required this.createdAt,
  });

  final String sourcePath;
  final String backupPath;
  final int bytes;
  final String sha256SourceBefore;
  final String sha256SourceAfter;
  final String sha256Backup;
  final String integrityCheck;

  /// 备份里的 `user_version`（备份是**迁移前**的快照）。
  final int sourceSchemaVersion;
  final DateTime createdAt;

  bool get sourceUnchanged => sha256SourceBefore == sha256SourceAfter;

  Map<String, Object?> toJson() => <String, Object?>{
        'source_path': sourcePath,
        'backup_path': backupPath,
        'bytes': bytes,
        'sha256_source_before': sha256SourceBefore,
        'sha256_source_after': sha256SourceAfter,
        'source_unchanged': sourceUnchanged,
        'sha256_backup': sha256Backup,
        'integrity_check': integrityCheck,
        'schema_version': sourceSchemaVersion,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// 生成带时间戳的备份：`<basename>.<yyyyMMdd-HHmmss>.bak`。
///
/// 走 SQLite 自己的 `VACUUM INTO`（源连接只读）：它会产出**一致**的快照，即使
/// 源库有 `-wal`。备份完成后立刻对备份做 `integrity_check`，并再次核对源库
/// SHA256 未变——备份过程本身不允许改源库。
ContentImportBackup createDatabaseBackup({
  required String dbPath,
  String? backupDir,
  DateTime? now,
}) {
  final source = File(dbPath);
  if (!source.existsSync()) {
    throw StateError('数据库不存在：$dbPath');
  }
  if (source.lengthSync() == 0) {
    throw StateError('数据库文件为空：$dbPath');
  }
  final directory =
      Directory(backupDir ?? p.join(p.dirname(source.absolute.path), 'backups'));
  directory.createSync(recursive: true);
  final stamp = _backupTimestamp(now ?? DateTime.now());
  final base = p.basename(source.absolute.path);
  var target = p.join(directory.absolute.path, '$base.$stamp.bak');
  var counter = 1;
  while (File(target).existsSync()) {
    target = p.join(directory.absolute.path, '$base.$stamp-${counter++}.bak');
  }

  final shaBefore = sha256HexOfFile(source);
  late final int schemaVersion;
  final Database src;
  try {
    src = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  } on SqliteException catch (error) {
    throw StateError('打不开数据库，无法备份：$dbPath\n$error');
  }
  try {
    final integrity =
        '${src.select('PRAGMA integrity_check').first.values.first}';
    if (integrity != 'ok') {
      throw StateError('源库 integrity_check 未通过：$integrity');
    }
    schemaVersion =
        (src.select('PRAGMA user_version').first.values.first as int?) ?? 0;
    src.execute('VACUUM INTO ?', <Object?>[target]);
  } on SqliteException catch (error) {
    throw StateError(
      '备份失败（$dbPath -> $target）：$error\n'
      '若 Furnace 正在运行，请先退出应用再备份/apply。',
    );
  } finally {
    src.dispose();
  }

  final backup = File(target);
  if (!backup.existsSync() || backup.lengthSync() == 0) {
    throw StateError('备份未生成：$target');
  }
  final Database check;
  try {
    check = sqlite3.open(target, mode: OpenMode.readOnly);
  } on SqliteException catch (error) {
    throw StateError('备份文件打不开：$target\n$error');
  }
  late final String backupIntegrity;
  try {
    backupIntegrity =
        '${check.select('PRAGMA integrity_check').first.values.first}';
  } finally {
    check.dispose();
  }
  if (backupIntegrity != 'ok') {
    throw StateError('备份 integrity_check 未通过：$backupIntegrity（$target）');
  }
  final shaAfter = sha256HexOfFile(source);
  if (shaAfter != shaBefore) {
    throw StateError('备份期间源库被改动，这是缺陷：$dbPath');
  }
  return ContentImportBackup(
    sourcePath: source.absolute.path,
    backupPath: target,
    bytes: backup.lengthSync(),
    sha256SourceBefore: shaBefore,
    sha256SourceAfter: shaAfter,
    sha256Backup: sha256HexOfFile(backup),
    integrityCheck: backupIntegrity,
    sourceSchemaVersion: schemaVersion,
    createdAt: DateTime.now(),
  );
}

String _backupTimestamp(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${moment.year}${two(moment.month)}${two(moment.day)}'
      '-${two(moment.hour)}${two(moment.minute)}${two(moment.second)}';
}

// ---------------------------------------------------------------------------
// 原库见证
// ---------------------------------------------------------------------------

/// 一段操作前后的文件见证。
class ContentImportIntegrity {
  const ContentImportIntegrity({
    required this.path,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.sha256Before,
    required this.sha256After,
    required this.modifiedBefore,
    required this.modifiedAfter,
  });

  final String path;
  final int bytesBefore;
  final int bytesAfter;
  final String sha256Before;
  final String sha256After;
  final DateTime modifiedBefore;
  final DateTime modifiedAfter;

  bool get unchanged =>
      sha256Before == sha256After &&
      bytesBefore == bytesAfter &&
      modifiedBefore == modifiedAfter;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'bytes_before': bytesBefore,
        'bytes_after': bytesAfter,
        'sha256_before': sha256Before,
        'sha256_after': sha256After,
        'modified_before': modifiedBefore.toIso8601String(),
        'modified_after': modifiedAfter.toIso8601String(),
        'unchanged': unchanged,
      };
}

/// 只读见证：只 stat + hash，不打开。
class _FileWitness {
  const _FileWitness(this.bytes, this.sha256, this.modified);

  final int bytes;
  final String sha256;
  final DateTime modified;
}

_FileWitness _witnessOf(File file) {
  final stat = file.statSync();
  return _FileWitness(stat.size, sha256HexOfFile(file), stat.modified);
}

// ---------------------------------------------------------------------------
// dry-run 临时副本
// ---------------------------------------------------------------------------

/// dry-run 实际导入的临时副本（原库只被复制，不被打开）。
class ContentImportWorkCopy {
  const ContentImportWorkCopy({
    required this.directory,
    required this.path,
    required this.copiedFiles,
  });

  final String directory;
  final String path;
  final List<String> copiedFiles;

  void dispose() {
    final dir = Directory(directory);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'directory': directory,
        'path': path,
        'files': copiedFiles,
      };
}

/// 把库（含 `-wal`/`-shm`）复制到临时目录；返回的副本可以安全打开。
ContentImportWorkCopy createWorkCopy(String dbPath) {
  final source = File(dbPath);
  if (!source.existsSync()) {
    throw StateError('数据库不存在：$dbPath');
  }
  final temp = Directory.systemTemp.createTempSync('furnace_content_import_');
  final target = p.join(temp.absolute.path, p.basename(source.absolute.path));
  final copied = <String>[];
  source.copySync(target);
  copied.add(p.basename(target));
  for (final suffix in const ['-wal', '-shm']) {
    final sidecar = File('$dbPath$suffix');
    if (sidecar.existsSync()) {
      sidecar.copySync('$target$suffix');
      copied.add('${p.basename(target)}$suffix');
    }
  }
  return ContentImportWorkCopy(
    directory: temp.absolute.path,
    path: target,
    copiedFiles: copied,
  );
}

// ---------------------------------------------------------------------------
// host 请求 / 结果
// ---------------------------------------------------------------------------

/// host 要做什么。
class ContentImportHostRequest {
  const ContentImportHostRequest({
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
    this.scratchDir,
  });

  /// `packages` / `papers` / `dry_run` / `apply`。
  final String mode;

  /// 内容包目录（`--packages`）；整卷模式为空。
  final List<String> packageDirs;

  /// 整卷目录（`--papers`/`--exam-paper`）；内容包模式为空。
  final List<String> paperDirs;

  /// 整卷 apply 的图片落盘根；dry-run 时是临时副本里的子目录。
  final String? mediaDir;

  final String? dbPath;
  final Map<String, String> kpMap;
  final bool createKnowledgePoints;
  final bool cards;
  final bool cardsApply;
  final DateTime? now;

  /// 请求/结果 JSON 落盘的目录（调用方保证可写；默认系统临时目录）。
  final String? scratchDir;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': contentImportRequestSchema,
        'mode': mode,
        'package_dirs': packageDirs,
        'paper_dirs': paperDirs,
        if (mediaDir != null) 'media_dir': mediaDir,
        if (dbPath != null) 'db_path': dbPath,
        'kp_map': kpMap,
        'create_knowledge_points': createKnowledgePoints,
        'cards': cards,
        'cards_apply': cardsApply,
        if (now != null) 'now': now!.toUtc().toIso8601String(),
      };
}

/// host 进程结果。
class ContentImportHostResult {
  const ContentImportHostResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.requestPath,
    required this.resultPath,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final String requestPath;
  final String resultPath;

  String get tail {
    final text = '$stdout\n$stderr';
    return text.length <= 2000 ? text : text.substring(text.length - 2000);
  }
}

typedef ContentImportHostRunner = Future<ContentImportHostResult> Function(
  ContentImportHostRequest request,
);

/// 用 `flutter test` 拉起 host（`package:flutter` 只在那个运行时里可加载）。
Future<ContentImportHostResult> runFlutterHost(
  ContentImportHostRequest request,
) async {
  final appDirectory = contentImportAppDirectory();
  final scratch = request.scratchDir ??
      Directory.systemTemp
          .createTempSync('furnace_content_import_host_')
          .absolute
          .path;
  final requestPath = p.join(scratch, 'content-import-request.json');
  final resultPath = p.join(scratch, 'content-import-result.json');
  File(requestPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(request.toJson()),
  );
  final flutter = resolveFlutterExecutable();
  final environment = Map<String, String>.from(Platform.environment)
    ..['CONTENT_IMPORT_REQUEST'] = requestPath
    ..['CONTENT_IMPORT_RESULT'] = resultPath;
  try {
    final result = await Process.run(
      flutter,
      <String>[
        'test',
        contentImportHostFile,
        '--plain-name',
        contentImportHostTestName,
      ],
      workingDirectory: appDirectory,
      // Windows 上 `flutter` 是 .bat：必须让 shell 解析。
      runInShell: Platform.isWindows,
      environment: environment,
    );
    return ContentImportHostResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
      requestPath: requestPath,
      resultPath: resultPath,
    );
  } on ProcessException catch (error) {
    return ContentImportHostResult(
      exitCode: -1,
      stdout: '',
      stderr: '无法启动 Flutter host（$flutter）：$error',
      requestPath: requestPath,
      resultPath: resultPath,
    );
  }
}

/// app 目录（含 `pubspec.yaml` 与 `tool/content_import_cli.dart`）。
///
/// 优先从当前目录向上找；`dart run` 要求从 app 目录执行，所以正常路径第一格
/// 就命中。找不到再退回脚本的上级目录。
String contentImportAppDirectory({Directory? from}) {
  var directory = (from ?? Directory.current).absolute.path;
  for (var i = 0; i < 8; i++) {
    final hasPubspec = File(p.join(directory, 'pubspec.yaml')).existsSync();
    final hasTool =
        File(p.join(directory, 'tool', 'content_import_cli.dart')).existsSync();
    if (hasPubspec && hasTool) {
      return directory;
    }
    final parent = p.dirname(directory);
    if (parent == directory) {
      break;
    }
    directory = parent;
  }
  final scriptParent = p.dirname(p.dirname(Platform.script.toFilePath()));
  if (File(p.join(scriptParent, 'pubspec.yaml')).existsSync()) {
    return scriptParent;
  }
  return Directory.current.absolute.path;
}

/// 读 host 写出的结果 JSON；不存在时抛出可读错误。
Map<String, Object?> readHostResult(String resultPath) {
  final file = File(resultPath);
  if (!file.existsSync()) {
    throw StateError('host 没有写结果文件：$resultPath');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw StateError('host 结果不是合法 JSON：$resultPath（${error.message}）');
  }
  if (decoded is! Map) {
    throw StateError('host 结果顶层应为 JSON 对象：$resultPath');
  }
  return decoded.cast<String, Object?>();
}

// ---------------------------------------------------------------------------
// 运行一次 dry-run / apply / packages
// ---------------------------------------------------------------------------

/// 一次 CLI 运行的全部证据。
class ContentImportCliRun {
  const ContentImportCliRun({
    required this.mode,
    required this.packageDirs,
    required this.host,
    required this.result,
    required this.runAt,
    required this.sourcePath,
    this.paperDirs = const <String>[],
    this.mediaDir,
    this.integrity,
    this.backup,
    this.workCopy,
    this.database,
  });

  final ContentImportMode mode;
  final List<String> packageDirs;

  /// 整卷目录；内容包模式为空。
  final List<String> paperDirs;

  /// 整卷 apply 的图片落盘根（dry-run 为临时副本里的子目录）。
  final String? mediaDir;

  final ContentImportHostResult host;
  final Map<String, Object?> result;
  final DateTime runAt;
  final String sourcePath;

  /// 原库见证：dry-run 必须 unchanged；apply 允许（也应该）变化。
  final ContentImportIntegrity? integrity;
  final ContentImportBackup? backup;
  final ContentImportWorkCopy? workCopy;

  /// `db` 模式的只读画像；dry-run/apply 时为 null（host 报告里有迁移后的库）。
  final ContentImportDatabaseInfo? database;

  bool get hostPassed => host.exitCode == 0;
  bool get importOk => result['ok'] == true;

  bool get examPaperSource => paperDirs.isNotEmpty;

  int get blockedPackages {
    final summary = result['summary'];
    if (summary is Map) {
      final value = summary['blocked_packages'];
      if (value is int) {
        return value;
      }
    }
    return 0;
  }

  /// 机器可读报告（`--json` / `--report`）。
  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 'content.import.cli/1',
        'generated_at': runAt.toUtc().toIso8601String(),
        'mode': mode.wireValue,
        'source': integrity?.toJson() ??
            <String, Object?>{'path': sourcePath},
        if (backup != null) 'backup': backup!.toJson(),
        if (workCopy != null) 'work_copy': workCopy!.toJson(),
        if (database != null) 'database': database!.toJson(),
        'package_dirs': packageDirs,
        'paper_dirs': paperDirs,
        if (mediaDir != null) 'media_dir': mediaDir,
        'host': <String, Object?>{
          'exit_code': host.exitCode,
          'test': contentImportHostTestName,
        },
        'result': result,
        'exit_code': exitCodeFor(this),
      };
}

/// 依据运行证据算退出码；纯函数，测试直接钉。
int exitCodeFor(ContentImportCliRun run) {
  if (!run.hostPassed) {
    return 4;
  }
  if (!run.importOk) {
    return 1;
  }
  if (run.mode == ContentImportMode.dryRun &&
      run.integrity != null &&
      !run.integrity!.unchanged) {
    return 2;
  }
  if (run.blockedPackages > 0) {
    return 5;
  }
  return 0;
}

/// `db` 模式 / `backup` 模式的运行。
ContentImportCliRun collectDatabaseCommand(ContentImportCliOptions options) {
  final dbPath = options.dbPath!;
  final info = readDatabaseInfo(dbPath);
  late final ContentImportBackup? backup;
  if (options.writesBackup) {
    backup = createDatabaseBackup(
      dbPath: dbPath,
      backupDir: options.backupDir,
      now: options.now,
    );
  } else {
    backup = null;
  }
  final after = readDatabaseInfo(dbPath);
  return ContentImportCliRun(
    mode: options.mode,
    packageDirs: const <String>[],
    host: const ContentImportHostResult(
      exitCode: 0,
      stdout: '',
      stderr: '',
      requestPath: '',
      resultPath: '',
    ),
    result: const <String, Object?>{'ok': true, 'schema': contentImportResultSchema},
    runAt: DateTime.now().toUtc(),
    sourcePath: info.path,
    integrity: ContentImportIntegrity(
      path: info.path,
      bytesBefore: info.bytes,
      bytesAfter: after.bytes,
      sha256Before: info.sha256,
      sha256After: after.sha256,
      modifiedBefore: File(dbPath).statSync().modified,
      modifiedAfter: File(dbPath).statSync().modified,
    ),
    backup: backup,
    database: info,
  );
}

/// 只解析内容包（不碰库）。
Future<ContentImportCliRun> collectPackages(
  ContentImportCliOptions options, {
  ContentImportHostRunner? host,
}) async {
  final dirs = discoverPackageDirs(options.packageRoots);
  if (dirs.isEmpty) {
    throw StateError('没有找到内容包（question.json）：${options.packageRoots.join(', ')}');
  }
  final scratch = Directory.systemTemp.createTempSync('content_import_packages_');
  final ContentImportHostResult hostResult;
  final Map<String, Object?> result;
  try {
    hostResult = await (host ?? runFlutterHost)(
      ContentImportHostRequest(
        mode: 'packages',
        packageDirs: dirs,
        scratchDir: scratch.absolute.path,
      ),
    );
    if (hostResult.exitCode != 0) {
      throw StateError(
        'Flutter host 失败（exit ${hostResult.exitCode}）。\n${hostResult.tail}',
      );
    }
    result = readHostResult(hostResult.resultPath);
  } finally {
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  }
  return ContentImportCliRun(
    mode: options.mode,
    packageDirs: dirs,
    host: hostResult,
    result: result,
    runAt: DateTime.now().toUtc(),
    sourcePath: '',
  );
}

/// 只解析整卷（不碰库）：读每个卷目录的 `paper.json`/`manifest.json`，返回
/// 卷级字段与题/选项/图计数；不做导入、不打开库。
Future<ContentImportCliRun> collectPapers(
  ContentImportCliOptions options, {
  ContentImportHostRunner? host,
}) async {
  final paperDirs = discoverPaperDirs(options.paperRoots);
  if (paperDirs.isEmpty) {
    throw StateError(
      '没有找到整卷（paper.json）：${options.paperRoots.join(', ')}',
    );
  }
  final scratch = Directory.systemTemp.createTempSync('content_import_papers_');
  final ContentImportHostResult hostResult;
  final Map<String, Object?> result;
  try {
    hostResult = await (host ?? runFlutterHost)(
      ContentImportHostRequest(
        mode: 'papers',
        paperDirs: paperDirs,
        scratchDir: scratch.absolute.path,
      ),
    );
    if (hostResult.exitCode != 0) {
      throw StateError(
        'Flutter host 失败（exit ${hostResult.exitCode}）。\n${hostResult.tail}',
      );
    }
    result = readHostResult(hostResult.resultPath);
  } finally {
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  }
  return ContentImportCliRun(
    mode: options.mode,
    packageDirs: const <String>[],
    paperDirs: paperDirs,
    host: hostResult,
    result: result,
    runAt: DateTime.now().toUtc(),
    sourcePath: '',
  );
}

/// dry-run：复制 → host 在副本上真跑 + 回滚 → 见证原库未变 → 删除副本。
Future<ContentImportCliRun> collectDryRun(
  ContentImportCliOptions options, {
  ContentImportHostRunner? host,
}) async {
  final dbPath = options.dbPath!;
  final source = File(dbPath);
  if (!source.existsSync()) {
    throw StateError('数据库不存在：$dbPath');
  }
  final dirs = options.paperRoots.isEmpty
      ? discoverPackageDirs(options.packageRoots)
      : const <String>[];
  final paperDirs = options.paperRoots.isEmpty
      ? const <String>[]
      : discoverPaperDirs(options.paperRoots);
  if (dirs.isEmpty && paperDirs.isEmpty) {
    throw StateError(
      '没有找到内容包（question.json）或整卷（paper.json）：'
      '${options.packageRoots.join(', ')} ${options.paperRoots.join(', ')}',
    );
  }
  final kpMap = options.kpMapPath == null
      ? const <String, String>{}
      : loadKnowledgePointMap(options.kpMapPath!);

  final before = _witnessOf(source);
  final work = createWorkCopy(dbPath);
  // 整卷 dry-run 的图片只落临时副本里：work 删除即图片消失，真实目录不受影响。
  final mediaRoot =
      paperDirs.isEmpty ? null : p.join(work.directory, 'exam_paper_media');
  var disposed = false;
  try {
    final hostResult = await (host ?? runFlutterHost)(
      ContentImportHostRequest(
        mode: 'dry_run',
        dbPath: work.path,
        packageDirs: dirs,
        paperDirs: paperDirs,
        mediaDir: mediaRoot,
        kpMap: kpMap,
        createKnowledgePoints: options.createKnowledgePoints,
        cards: options.cards,
        cardsApply: false,
        now: options.now,
        scratchDir: work.directory,
      ),
    );
    if (hostResult.exitCode != 0) {
      throw StateError(
        'Flutter host 失败（exit ${hostResult.exitCode}）。\n${hostResult.tail}',
      );
    }
    final result = readHostResult(hostResult.resultPath);
    final after = _witnessOf(source);
    final run = ContentImportCliRun(
      mode: options.mode,
      packageDirs: dirs,
      paperDirs: paperDirs,
      mediaDir: mediaRoot,
      host: hostResult,
      result: result,
      runAt: DateTime.now().toUtc(),
      sourcePath: source.absolute.path,
      integrity: ContentImportIntegrity(
        path: source.absolute.path,
        bytesBefore: before.bytes,
        bytesAfter: after.bytes,
        sha256Before: before.sha256,
        sha256After: after.sha256,
        modifiedBefore: before.modified,
        modifiedAfter: after.modified,
      ),
      workCopy: work,
    );
    if (!options.keepTemp) {
      work.dispose();
      disposed = true;
    }
    return run;
  } finally {
    if (!disposed && !options.keepTemp) {
      work.dispose();
    }
  }
}

/// apply：检查 → 备份 → host 写库 → 见证。
Future<ContentImportCliRun> collectApply(
  ContentImportCliOptions options, {
  ContentImportHostRunner? host,
}) async {
  final dbPath = options.dbPath!;
  final source = File(dbPath);
  if (!source.existsSync()) {
    throw StateError('数据库不存在：$dbPath');
  }
  if (_isKnownRealDatabase(dbPath)) {
    if (!options.allowRealDb) {
      throw StateError(
        '拒绝对真实库 apply：$dbPath\n'
        '这是用户的真实数据。先 dry-run；确实要写时显式加 --allow-real-db，'
        '并确认会先生成带时间戳备份。',
      );
    }
    if (options.noBackup) {
      throw StateError('真实库 apply 必须备份，--no-backup 被拒绝');
    }
  }
  // 应用可能正开着库：非空 -wal 时拒绝，避免两个写者。
  if (_walBytes(dbPath) > 0) {
    throw StateError(
      '发现非空 -wal（应用可能正在使用该库）：$dbPath\n'
      '请先退出 Furnace，再备份/apply。',
    );
  }
  final info = readDatabaseInfo(dbPath);
  if (info.integrity != 'ok') {
    throw StateError('源库 integrity_check 未通过（${info.integrity}），拒绝 apply');
  }
  if (info.schemaVersion > kFurnaceSchemaVersion) {
    throw StateError(
      '库 schema v${info.schemaVersion} 比当前应用 v$kFurnaceSchemaVersion 新，'
      '拒绝 apply（会丢数据）。先用新版 Furnace 打开。',
    );
  }

  final dirs = options.paperRoots.isEmpty
      ? discoverPackageDirs(options.packageRoots)
      : const <String>[];
  final paperDirs = options.paperRoots.isEmpty
      ? const <String>[]
      : discoverPaperDirs(options.paperRoots);
  if (dirs.isEmpty && paperDirs.isEmpty) {
    throw StateError(
      '没有找到内容包（question.json）或整卷（paper.json）：'
      '${options.packageRoots.join(', ')} ${options.paperRoots.join(', ')}',
    );
  }
  final kpMap = options.kpMapPath == null
      ? const <String, String>{}
      : loadKnowledgePointMap(options.kpMapPath!);

  final before = _witnessOf(source);
  ContentImportBackup? backup;
  if (options.writesBackup) {
    backup = createDatabaseBackup(
      dbPath: dbPath,
      backupDir: options.backupDir,
      now: options.now,
    );
  }
  final hostScratch = Directory.systemTemp.createTempSync('content_import_apply_');
  final ContentImportHostResult hostResult;
  final Map<String, Object?> result;
  try {
    hostResult = await (host ?? runFlutterHost)(
      ContentImportHostRequest(
        mode: 'apply',
        dbPath: source.absolute.path,
        packageDirs: dirs,
        paperDirs: paperDirs,
        mediaDir: options.mediaDir,
        kpMap: kpMap,
        createKnowledgePoints: options.createKnowledgePoints,
        cards: options.cards,
        cardsApply: options.cardsApply,
        now: options.now,
        scratchDir: hostScratch.absolute.path,
      ),
    );
    if (hostResult.exitCode != 0) {
      throw StateError(
        'Flutter host 失败（exit ${hostResult.exitCode}）。\n${hostResult.tail}',
      );
    }
    result = readHostResult(hostResult.resultPath);
  } finally {
    if (hostScratch.existsSync()) {
      hostScratch.deleteSync(recursive: true);
    }
  }
  final after = _witnessOf(source);
  return ContentImportCliRun(
    mode: options.mode,
    packageDirs: dirs,
    paperDirs: paperDirs,
    mediaDir: options.mediaDir,
    host: hostResult,
    result: result,
    runAt: DateTime.now().toUtc(),
    sourcePath: source.absolute.path,
    integrity: ContentImportIntegrity(
      path: source.absolute.path,
      bytesBefore: before.bytes,
      bytesAfter: after.bytes,
      sha256Before: before.sha256,
      sha256After: after.sha256,
      modifiedBefore: before.modified,
      modifiedAfter: after.modified,
    ),
    backup: backup,
  );
}

bool _isKnownRealDatabase(String dbPath) {
  final normalized = p.normalize(p.absolute(dbPath)).toLowerCase();
  for (final known in knownRealDatabasePaths()) {
    if (p.normalize(p.absolute(known)).toLowerCase() == normalized) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// 渲染
// ---------------------------------------------------------------------------

/// 人类可读报告（默认）或 JSON（`--json` / `--report`）。
String renderContentImportRun(ContentImportCliRun run, {required bool json}) {
  if (json) {
    return const JsonEncoder.withIndent('  ').convert(run.toJson());
  }
  final buffer = StringBuffer();
  final title = switch (run.mode) {
    ContentImportMode.dbInfo => '库检查（只读）',
    ContentImportMode.packages => '内容包清单（只解析）',
    ContentImportMode.papers => '整卷清单（只解析）',
    ContentImportMode.backupOnly => '备份',
    ContentImportMode.dryRun => run.examPaperSource
        ? '整卷 dry-run（副本 + 事务回滚）'
        : 'dry-run（副本 + 事务回滚）',
    ContentImportMode.apply =>
      run.examPaperSource ? '整卷 apply（事务提交）' : 'apply（事务提交）',
  };
  buffer.writeln('内容导入 CLI · $title');
  if (run.mediaDir != null) {
    buffer.writeln('图片根：${run.mediaDir}');
  }
  if (run.integrity != null) {
    buffer.writeln('库：${run.integrity!.path}');
    final integrity = run.integrity!;
    buffer.writeln(
      'SHA256 前：${integrity.sha256Before}',
    );
    buffer.writeln(
      'SHA256 后：${integrity.sha256After}',
    );
    if (run.mode == ContentImportMode.dryRun) {
      buffer.writeln(
        '原库未被修改：${integrity.unchanged ? '是' : '否 —— 立即停止并排查'}',
      );
    } else if (run.mode == ContentImportMode.apply) {
      buffer.writeln('库已变化：${integrity.unchanged ? '否' : '是'}');
    }
    buffer.writeln(
      '文件：${integrity.bytesBefore} → ${integrity.bytesAfter} 字节',
    );
  } else if (run.sourcePath.isNotEmpty) {
    buffer.writeln('库：${run.sourcePath}');
  }
  if (run.backup != null) {
    final backup = run.backup!;
    buffer.writeln(
      '备份：${backup.backupPath}（${backup.bytes} 字节，'
      'integrity=${backup.integrityCheck}，schema=v${backup.sourceSchemaVersion}）',
    );
    buffer.writeln('备份 SHA256：${backup.sha256Backup}');
  }
  if (run.workCopy != null) {
    buffer.writeln(
      'dry-run 副本：${run.workCopy!.path}'
      '（${run.workCopy!.copiedFiles.join(', ')}）',
    );
  }
  if (run.database != null) {
    final info = run.database!;
    final status = info.schemaVersion == kFurnaceSchemaVersion
        ? '当前应用 schema'
        : '打开时会迁移到 v$kFurnaceSchemaVersion（先备份）';
    buffer.writeln(
      'schema：user_version=${info.schemaVersion}（$status）',
    );
    buffer.writeln(
      'integrity_check：${info.integrity}'
      '${info.walPresent ? ' · 有活跃 -wal（应用可能正开着库）' : ''}',
    );
    buffer.writeln('计数：');
    for (final entry in info.counts.entries) {
      buffer.writeln(
        '  ${entry.key.padRight(26)} ${entry.value ?? '（表不存在）'}',
      );
    }
    buffer.writeln('SHA256：${info.sha256}');
  }
  if (run.mode != ContentImportMode.dbInfo &&
      run.mode != ContentImportMode.backupOnly) {
    if (run.examPaperSource || run.mode == ContentImportMode.papers) {
      renderExamPaperBody(buffer, run);
    } else {
      renderImportBody(buffer, run);
    }
  }
  return buffer.toString();
}

/// 整卷模式的报告正文（题/选项/图/引用统计 + 逐卷明细 + 跳过/拦截）。
void renderExamPaperBody(StringBuffer buffer, ContentImportCliRun run) {
  final result = run.result;
  final summary =
      (result['summary'] as Map?)?.cast<String, Object?>() ?? const {};
  final papers = ((result['papers'] as List?) ?? const [])
      .whereType<Map>()
      .map((map) => map.cast<String, Object?>())
      .toList();
  final transaction =
      (result['transaction'] as Map?)?.cast<String, Object?>() ?? const {};

  buffer.writeln(
    'host：flutter test 「$contentImportHostTestName」'
    'exit=${run.host.exitCode}',
  );
  if (run.mode != ContentImportMode.papers) {
    buffer.writeln(
      '事务：${transaction['committed'] == true ? '已提交' : '未提交'}'
      ' · ${transaction['rolled_back'] == true ? '已回滚' : '未回滚'}',
    );
  }
  if (result['ok'] != true) {
    buffer.writeln('导入失败：${result['error'] ?? '未知错误'}');
    if (result['rollback_verified'] == true) {
      buffer.writeln('回滚校验：计数回到导入前');
    }
    return;
  }

  if (run.mode == ContentImportMode.papers) {
    buffer.writeln('整卷 ${papers.length} 个：');
    for (final paper in papers) {
      buffer.writeln(
        '  ${paper['paper_key']} · ${paper['title']}',
      );
      buffer.writeln(
        '    学科 ${paper['subject']} · 年份 ${paper['year']} · 地区 '
        '${paper['region']} · 来源 ${paper['source_level']}'
        '（${paper['source_level_basis']}）',
      );
      buffer.writeln(
        '    题 ${paper['question_count']} · 选项 ${paper['option_count']}'
        ' · 题干图 ${paper['stem_figure_count']}'
        ' · 解析图 ${paper['answer_figure_count']}'
        ' · 卷面总分 ${paper['score_total_stated'] ?? '未写'}',
      );
    }
    return;
  }

  final countsBefore = (result['exam_counts_before'] as Map?)
          ?.cast<String, Object?>() ??
      const {};
  final countsWouldBe = (result['exam_counts_after_import'] as Map?)
          ?.cast<String, Object?>() ??
      const {};
  final countsAfter = (result['exam_counts_after'] as Map?)
          ?.cast<String, Object?>() ??
      const {};
  final wouldCreate =
      (summary['would_create'] as Map?)?.cast<String, Object?>() ?? const {};

  buffer.writeln('整卷 ${papers.length} 个：');
  for (final paper in papers) {
    final status = '${paper['status'] ?? '?'}';
    final blocked = (paper['blocked'] as List?) ?? const [];
    final skipped = (paper['skipped'] as List?) ?? const [];
    if (status == 'blocked') {
      buffer.writeln(
        '  ✗ ${paper['paper_key']} · blocked（${blocked.length} 项）',
      );
    } else {
      buffer.writeln(
        '  ✓ ${paper['paper_key']} · $status'
        ' · 新建 ${paper['created']} / 复用 ${paper['reused']}'
        ' · 题 ${paper['question_count']}'
        ' · 选项 ${paper['option_count']}'
        ' · 图 ${paper['figures_imported']} / ${paper['figure_count']}'
        ' · 引用 ${paper['content_ref_count']}',
      );
    }
    buffer.writeln(
      '    分值合计（引用摘要）${paper['score_sum_from_questions']}'
      ' / 卷面 ${paper['score_total_stated'] ?? '未写'}'
      ' · 跳过 ${skipped.length} 项 · 拦截 ${blocked.length} 项',
    );
  }
  buffer.writeln(
    '计数：before → 导入后 → 实际 after'
    '${run.mode == ContentImportMode.dryRun ? '（dry-run 已回滚，最后一段应等于第一段）' : ''}',
  );
  final keys = <String>{
    ...countsBefore.keys,
    ...countsWouldBe.keys,
    ...countsAfter.keys,
  };
  for (final key in keys) {
    buffer.writeln(
      '  ${key.padRight(24)}'
      '${countsBefore[key] ?? '-'} → ${countsWouldBe[key] ?? '-'} → '
      '${countsAfter[key] ?? '-'}',
    );
  }
  buffer.writeln(
    'wouldCreate：题 ${wouldCreate['questions'] ?? 0}'
    ' / 选项 ${wouldCreate['options'] ?? 0}'
    ' / 图 ${wouldCreate['figures'] ?? 0}'
    ' / 引用 ${wouldCreate['content_refs'] ?? 0}',
  );
  buffer.writeln(
    '合计：新建 ${summary['created_questions'] ?? 0} / 复用 '
    '${summary['reused_questions'] ?? 0}'
    ' · 题 ${summary['questions'] ?? 0}'
    ' · 选项 ${summary['options'] ?? 0}'
    ' · 图 ${summary['figures_imported'] ?? 0} / ${summary['figures'] ?? 0}'
    ' · 引用 ${summary['content_refs'] ?? 0}',
  );
  buffer.writeln(
    '跳过 ${summary['skipped'] ?? 0} 项'
    ' · 拦截 ${summary['blocked_issues'] ?? 0} 项'
    ' · blocked 卷 ${summary['blocked_packages'] ?? 0} 个',
  );
  if (run.mediaDir != null) {
    buffer.writeln('图片落盘（QuestionMediaStore）：${run.mediaDir}');
  }
  final backup = run.backup;
  if (backup != null) {
    buffer.writeln(
      '备份可用：${backup.sourceUnchanged ? '源库备份前后未变' : '源库备份前后变了（缺陷）'}',
    );
  }
}

void renderImportBody(StringBuffer buffer, ContentImportCliRun run) {
  final result = run.result;
  final summary =
      (result['summary'] as Map?)?.cast<String, Object?>() ?? const {};
  final countsBefore =
      (result['counts_before'] as Map?)?.cast<String, Object?>() ?? const {};
  final countsWouldBe = (result['counts_after_import'] as Map?)
          ?.cast<String, Object?>() ??
      const {};
  final countsAfter =
      (result['counts_after'] as Map?)?.cast<String, Object?>() ?? const {};
  final transaction =
      (result['transaction'] as Map?)?.cast<String, Object?>() ?? const {};
  final packages = ((result['packages'] as List?) ?? const [])
      .whereType<Map>()
      .map((map) => map.cast<String, Object?>())
      .toList();

  buffer.writeln(
    'host：flutter test 「$contentImportHostTestName」'
    'exit=${run.host.exitCode}',
  );
  buffer.writeln(
    '事务：${transaction['committed'] == true ? '已提交' : '未提交'}'
    ' · ${transaction['rolled_back'] == true ? '已回滚' : '未回滚'}',
  );
  if (result['ok'] != true) {
    buffer.writeln('导入失败：${result['error'] ?? '未知错误'}');
    if (result['rollback_verified'] == true) {
      buffer.writeln('回滚校验：计数回到导入前');
    }
    return;
  }
  if (run.mode == ContentImportMode.packages) {
    buffer.writeln('包 ${packages.length} 个：');
    for (final package in packages) {
      final warnings = (package['warnings'] as List?) ?? const [];
      buffer.writeln(
        '  ${package['content_id']} · ${package['subject']}/'
        '${package['question_type']} · 知识节点 ${package['knowledge_nodes']}'
        ' · DAG ${package['dag_nodes']} · 错因 ${package['error_causes']}',
      );
      if (package['title'] != null && '${package['title']}'.isNotEmpty) {
        buffer.writeln('    题名：${package['title']}');
      }
      for (final warning in warnings) {
        buffer.writeln('    警告：$warning');
      }
    }
    return;
  }

  buffer.writeln('包 ${packages.length} 个：');
  for (final package in packages) {
    buffer.writeln(renderPackageLine(package));
  }
  buffer.writeln(
    '计数：before → 导入后 → 实际 after'
    '${run.mode == ContentImportMode.dryRun ? '（dry-run 已回滚，最后一段应等于第一段）' : ''}',
  );
  final keys = <String>{
    ...countsBefore.keys,
    ...countsWouldBe.keys,
    ...countsAfter.keys,
  };
  for (final key in keys) {
    buffer.writeln(
      '  ${key.padRight(24)}'
      '${countsBefore[key] ?? '-'} → ${countsWouldBe[key] ?? '-'} → '
      '${countsAfter[key] ?? '-'}',
    );
  }
  final wouldCreate =
      (summary['would_create'] as Map?)?.cast<String, Object?>() ?? const {};
  buffer.writeln(
    'wouldCreate：题 ${wouldCreate['questions'] ?? 0}'
    ' / 知识点 ${wouldCreate['knowledge_points'] ?? 0}'
    ' / 引用 ${wouldCreate['content_refs'] ?? 0}'
    ' / 卡 ${wouldCreate['cards'] ?? 0}',
  );
  buffer.writeln(
    '跳过：${summary['skipped'] ?? 0} 条'
    ' · 缺失标签 ${summary['missing_tags'] ?? 0} 条'
    ' · 未映射知识点 ${summary['unmapped_knowledge_points'] ?? 0} 条'
    ' · blocked 包 ${summary['blocked_packages'] ?? 0} 个',
  );
  final missingTags = (summary['missing_tag_paths'] as List?) ?? const [];
  if (missingTags.isNotEmpty) {
    buffer.writeln('缺失标签（库里没有这条 path，未自动创建）：');
    for (final path in missingTags) {
      buffer.writeln('  - $path');
    }
  }
  // `unmapped_knowledge_points` 是计数；明细在 `_detail`（host 契约）。
  final unmapped =
      (summary['unmapped_knowledge_points_detail'] as List?) ?? const [];
  if (unmapped.isNotEmpty) {
    buffer.writeln('未映射/无法建的产品知识点（--kp-map 可人工指定）：');
    for (final item in unmapped.whereType<Map>()) {
      buffer.writeln(
        '  - ${item['content_node_id']}（${item['label'] ?? ''}）'
        '${item['reason'] == null ? '' : ' · ${item['reason']}'}',
      );
    }
  }
  final kpTemplate =
      (summary['kp_map_template'] as Map?)?.cast<String, Object?>() ?? const {};
  if (kpTemplate.isNotEmpty) {
    buffer.writeln('kp-map 模板（内容节点 id → 产品知识点 id，补空值后 --kp-map）：');
    buffer.writeln(const JsonEncoder.withIndent('  ').convert(kpTemplate));
  }
  final backup = run.backup;
  if (backup != null) {
    buffer.writeln(
      '备份可用：${backup.sourceUnchanged ? '源库备份前后未变' : '源库备份前后变了（缺陷）'}',
    );
  }
}

/// 一个包的摘要行。
String renderPackageLine(Map<String, Object?> package) {
  final contentId = '${package['content_id'] ?? '?'}';
  final status = '${package['status'] ?? '?'}';
  if (status == 'blocked') {
    final blocked = (package['blocked'] as List?) ?? const [];
    return '  ✗ $contentId · blocked：${blocked.join('；')}';
  }
  final created = package['question_created'] == true ? '新题' : '已存在';
  final points =
      (package['knowledge_points'] as List?)?.whereType<Map>() ?? const [];
  final createdPoints = points.where((point) => point['created'] == true).length;
  final mappedPoints = points.where((point) => point['mapped'] == true).length;
  final skipped = (package['skipped'] as List?)?.whereType<Map>() ?? const [];
  final tags = (package['tags'] as List?)?.whereType<Map>() ?? const [];
  final missingTags = tags.where((tag) => tag['missing'] == true).length;
  final cardPlan = (package['card_plan'] as Map?)?.cast<String, Object?>();
  final cardText = cardPlan == null
      ? '未启用'
      : 'wouldCreate ${cardPlan['would_create']} / created ${cardPlan['created']}'
          ' / skipped ${cardPlan['skipped']} / blocked ${cardPlan['blocked']}';
  final skipCodes = <String, int>{};
  for (final skip in skipped) {
    final code = '${skip['code']}';
    skipCodes[code] = (skipCodes[code] ?? 0) + 1;
  }
  final buffer = StringBuffer()
    ..writeln('  ✓ $contentId · $status · $created'
        ' · 题号 ${package['serial_no'] ?? '-'}'
        ' · 版本 ${package['content_version'] ?? '-'}'
        ' · 引用 ${package['content_ref_count'] ?? 0}')
    ..writeln('    知识点：新建 $createdPoints / 显式映射 $mappedPoints'
        ' / 共 ${points.length}')
    ..writeln('    标签：命中 ${tags.length - missingTags} / 缺失 $missingTags'
        ' · 卡片：$cardText');
  if (skipCodes.isNotEmpty) {
    buffer.writeln(
      '    跳过原因：${skipCodes.entries.map((entry) => '${entry.key}×${entry.value}').join('、')}',
    );
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final ContentImportCliOptions options;
  try {
    options = ContentImportCliOptions.parse(args);
  } on ArgumentError catch (error) {
    stderr.writeln('$error\n');
    stderr.writeln(contentImportUsage);
    exitCode = 2;
    return;
  }
  if (options.help) {
    stdout.writeln(contentImportUsage);
    return;
  }

  try {
    final run = switch (options.mode) {
      ContentImportMode.dbInfo => collectDatabaseCommand(options),
      ContentImportMode.backupOnly => collectDatabaseCommand(options),
      ContentImportMode.packages => await collectPackages(options),
      ContentImportMode.papers => await collectPapers(options),
      ContentImportMode.dryRun => await collectDryRun(options),
      ContentImportMode.apply => await collectApply(options),
    };
    final rendered = renderContentImportRun(run, json: options.json);
    if (options.json) {
      stdout.writeln(rendered);
    } else {
      stdout.write(rendered);
    }
    if (options.reportPath != null) {
      final report = File(options.reportPath!);
      report.parent.createSync(recursive: true);
      report.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(run.toJson()),
      );
    }
    exitCode = exitCodeFor(run);
    if (run.mode == ContentImportMode.dryRun &&
        run.integrity != null &&
        !run.integrity!.unchanged) {
      stderr.writeln('原库被改动，这是缺陷：${run.integrity!.path}');
    }
    if (run.mode == ContentImportMode.apply && !run.importOk) {
      final message = run.result['error'];
      stderr.writeln('导入失败并回滚：$message');
    }
  } on StateError catch (error) {
    stderr.writeln('$error');
    exitCode = 3;
  }
}
