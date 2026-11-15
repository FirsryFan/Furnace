/// 内容包导入 CLI 的测试（task-83，2026-11-15）。
///
/// 三件事都在这个文件里：
///
/// 1. **纯 Dart 侧的单元测试**：参数解析、kp-map、包目录发现、只读库画像、
///    备份（`VACUUM INTO` + 完整性 + SHA256）、渲染与退出码；
/// 2. **host 侧的行为测试**（`flutter test` 内存库）：dry-run 真跑回滚、
///    apply 计数、二次 apply 幂等、`--create-kps=false`、`--kp-map`、失败回滚、
///    不覆盖已有题正文；
/// 3. **host 宿主用例** `content import cli host`：被
///    `tool/content_import_cli.dart` 用 env `CONTENT_IMPORT_REQUEST` /
///    `CONTENT_IMPORT_RESULT` 拉起，平时整组 skip，所以常规测试套件不会碰
///    任何真实库。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:furnace/data/content/content_package_reader.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/content/content_package.dart';
import 'package:furnace/domain/services/content/content_package_import_service.dart';
import 'package:furnace/features/questions/application/exam_paper_question_importer.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

import '../../tool/content_import_cli.dart';
import '../../tool/content_import_host.dart';

/// 工作区内容包根（与 `test/experiments/content_package_import_real_content_test.dart`
/// 同一份绝对路径；文件不在本机时真内容包组整组 skip）。
const String _contentStoreRoot =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\content-store';

/// 真实数学整卷（task-88 验收样本）；文件不在本机时整卷 host 组整组 skip。
const String _mathPaperDir =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\exam-papers\2025-math-national1';

bool get _mathPaperPresent =>
    File(p.join(_mathPaperDir, 'paper.json')).existsSync();

final List<String> _realPackageDirs = <String>[
  p.join(_contentStoreRoot, 'physics', 'Q-PH0001'),
  p.join(_contentStoreRoot, 'math', 'Q-MA0001'),
  p.join(_contentStoreRoot, 'chinese', 'Q-CH0001'),
];

bool get _realPackagesPresent =>
    _realPackageDirs.every((dir) => Directory(dir).existsSync());

const String _hostTestName = contentImportHostTestName;

/// host 用例由 CLI 拉起；没被拉起时 skip，常规套件保持全绿。
final String _hostRequestPath =
    Platform.environment['CONTENT_IMPORT_REQUEST'] ?? '';
final String _hostResultPath =
    Platform.environment['CONTENT_IMPORT_RESULT'] ?? '';

void main() {
  // ---------------------------------------------------------------------------
  // 0. host 宿主用例（只有 CLI 拉起时执行）
  // ---------------------------------------------------------------------------

  test(
    _hostTestName,
    () async {
      await runContentImportHostFromFiles(
        requestPath: _hostRequestPath,
        resultPath: _hostResultPath,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: _hostRequestPath.isEmpty || _hostResultPath.isEmpty
        ? '未由 content_import_cli 拉起（缺 CONTENT_IMPORT_REQUEST）'
        : false,
  );

  // ---------------------------------------------------------------------------
  // 1. 参数
  // ---------------------------------------------------------------------------

  group('CLI 参数', () {
    test('默认模式是 dry-run；--db/--packages 必填', () {
      final options = ContentImportCliOptions.parse(<String>[
        '--db',
        r'C:\tmp\furnace.db',
        '--packages',
        r'C:\tmp\content-store',
      ]);
      expect(options.mode, ContentImportMode.dryRun);
      expect(options.dbPath, r'C:\tmp\furnace.db');
      expect(options.packageRoots, <String>[r'C:\tmp\content-store']);
      expect(options.createKnowledgePoints, isTrue);
      expect(options.writesBackup, isFalse);
    });

    test('子命令 apply / backup / packages / db 与 --dry-run 等价形式', () {
      expect(
        ContentImportCliOptions.parse(<String>[
          'apply',
          '--db',
          r'C:\tmp\furnace.db',
          '--packages',
          r'C:\tmp\content-store',
        ]).mode,
        ContentImportMode.apply,
      );
      expect(
        ContentImportCliOptions.parse(<String>['--dry-run', '--db', 'x', '--packages', 'y'])
            .mode,
        ContentImportMode.dryRun,
      );
      final backupOnly = ContentImportCliOptions.parse(<String>['backup', '--db', 'x']);
      expect(backupOnly.mode, ContentImportMode.backupOnly);
      expect(backupOnly.writesBackup, isTrue);
      final packages = ContentImportCliOptions.parse(<String>['packages', '--packages', 'y']);
      expect(packages.mode, ContentImportMode.packages);
    });

    test('--apply 默认就写备份；--no-backup 只允许 apply', () {
      final apply = ContentImportCliOptions.parse(<String>[
        '--apply',
        '--db',
        'x',
        '--packages',
        'y',
      ]);
      expect(apply.backup, isTrue);
      expect(apply.writesBackup, isTrue);
      final noBackup = ContentImportCliOptions.parse(<String>[
        '--apply',
        '--db',
        'x',
        '--packages',
        'y',
        '--no-backup',
      ]);
      expect(noBackup.writesBackup, isFalse);
      expect(
        () => ContentImportCliOptions.parse(<String>['--dry-run', '--db', 'x', '--packages', 'y', '--no-backup']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['--backup', '--no-backup', '--apply', '--db', 'x', '--packages', 'y']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('--create-kps 的三种写法', () {
      const base = <String>['--dry-run', '--db', 'x', '--packages', 'y'];
      expect(
        ContentImportCliOptions.parse(<String>[...base, '--create-kps=false'])
            .createKnowledgePoints,
        isFalse,
      );
      expect(
        ContentImportCliOptions.parse(<String>[...base, '--no-create-kps'])
            .createKnowledgePoints,
        isFalse,
      );
      expect(
        ContentImportCliOptions.parse(<String>[...base, '--create-kps=true'])
            .createKnowledgePoints,
        isTrue,
      );
      expect(
        () => ContentImportCliOptions.parse(<String>[...base, '--create-kps=maybe']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('--cards-apply 只对 apply 有意义；--kp-map 只对 dry-run/apply', () {
      expect(
        () => ContentImportCliOptions.parse(<String>['--dry-run', '--db', 'x', '--packages', 'y', '--cards-apply']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['backup', '--db', 'x', '--kp-map', 'k.json']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('模式冲突 / 未知参数 / 缺值 / 缺必填都报 ArgumentError', () {
      expect(
        () => ContentImportCliOptions.parse(<String>['--dry-run', '--apply', '--db', 'x', '--packages', 'y']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['--nope']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['--db']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['--dry-run', '--packages', 'y']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['--dry-run', '--db', 'x']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('--help 不读盘直接返回帮助', () {
      final options = ContentImportCliOptions.parse(<String>['--help']);
      expect(options.help, isTrue);
      expect(contentImportUsage, contains('--allow-real-db'));
      expect(contentImportUsage, contains('--papers'));
      expect(contentImportUsage, contains('--media-dir'));
    });
  });

  // ---------------------------------------------------------------------------
  // 1b. 整卷参数（task-88）
  // ---------------------------------------------------------------------------

  group('CLI 参数（整卷）', () {
    test('--papers / --exam-paper 解析；默认 dry-run；来源标记', () {
      final options = ContentImportCliOptions.parse(<String>[
        '--db',
        r'C:\tmp\furnace.db',
        '--papers',
        r'C:\tmp\exam-papers',
      ]);
      expect(options.mode, ContentImportMode.dryRun);
      expect(options.paperRoots, <String>[r'C:\tmp\exam-papers']);
      expect(options.packageRoots, isEmpty);
      expect(options.examPaperSource, isTrue);
      expect(options.mediaDir, isNull);
      expect(options.mode.needsDatabase, isTrue);

      final single = ContentImportCliOptions.parse(<String>[
        'apply',
        '--db',
        'x',
        '--exam-paper',
        'p1',
        '--media-dir',
        'm',
      ]);
      expect(single.mode, ContentImportMode.apply);
      expect(single.paperRoots, <String>['p1']);
      expect(single.mediaDir, 'm');
      expect(single.writesBackup, isTrue);
    });

    test('papers 子命令只解析；缺 --papers 报错；不需要 --db', () {
      final options =
          ContentImportCliOptions.parse(<String>['papers', '--papers', 'p']);
      expect(options.mode, ContentImportMode.papers);
      expect(options.mode.needsDatabase, isFalse);
      expect(options.examPaperSource, isTrue);
      expect(
        () => ContentImportCliOptions.parse(<String>['papers']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>['papers', '--db', 'x']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('来源互斥：--packages 与 --papers/--exam-paper 不能同时给', () {
      expect(
        () => ContentImportCliOptions.parse(<String>[
          '--dry-run',
          '--db',
          'x',
          '--packages',
          'a',
          '--papers',
          'b',
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>[
          'apply',
          '--db',
          'x',
          '--package',
          'a',
          '--exam-paper',
          'b',
          '--media-dir',
          'm',
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('整卷 apply 必须 --media-dir；dry-run 拒绝 --media-dir', () {
      expect(
        () => ContentImportCliOptions.parse(<String>[
          'apply',
          '--db',
          'x',
          '--papers',
          'p',
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>[
          'dry-run',
          '--db',
          'x',
          '--papers',
          'p',
          '--media-dir',
          'm',
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContentImportCliOptions.parse(<String>[
          '--dry-run',
          '--db',
          'x',
          '--packages',
          'p',
          '--media-dir',
          'm',
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('整卷模式拒绝内容包专属参数（--kp-map/--no-create-kps/--cards）', () {
      for (final extra in <List<String>>[
        <String>['--kp-map', 'k.json'],
        <String>['--no-create-kps'],
        <String>['--cards'],
      ]) {
        expect(
          () => ContentImportCliOptions.parse(<String>[
            '--dry-run',
            '--db',
            'x',
            '--papers',
            'p',
            ...extra,
          ]),
          throwsA(isA<ArgumentError>()),
          reason: '$extra',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 2. kp-map / 包目录发现
  // ---------------------------------------------------------------------------

  group('kp-map 与包目录发现', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('content_import_kp_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('top-level 映射与 {"mappings": ...} 两种形态都读', () {
      final flat = File(p.join(temp.path, 'flat.json'))
        ..writeAsStringSync(jsonEncode(<String, String>{
          'kp-a': 'kp-1',
          ' kp-b ': ' kp-2 ',
          'kp-empty': '',
        }));
      expect(loadKnowledgePointMap(flat.path), <String, String>{
        'kp-a': 'kp-1',
        'kp-b': 'kp-2',
      });

      final wrapped = File(p.join(temp.path, 'wrapped.json'))
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'mappings': <String, String>{'kp-c': 'kp-3'},
          'note': 'ignored',
        }));
      expect(loadKnowledgePointMap(wrapped.path), <String, String>{'kp-c': 'kp-3'});
    });

    test('坏 JSON / 非对象 / 不存在都抛 StateError', () {
      final bad = File(p.join(temp.path, 'bad.json'))..writeAsStringSync('{');
      expect(() => loadKnowledgePointMap(bad.path), throwsA(isA<StateError>()));
      final list = File(p.join(temp.path, 'list.json'))..writeAsStringSync('[]');
      expect(() => loadKnowledgePointMap(list.path), throwsA(isA<StateError>()));
      expect(
        () => loadKnowledgePointMap(p.join(temp.path, 'missing.json')),
        throwsA(isA<StateError>()),
      );
    });

    test('递归发现 question.json 并按路径排序；根目录本身是包也认', () {
      final root = Directory(p.join(temp.path, 'store'))..createSync();
      for (final name in <String>['physics/Q-PH0001', 'math/Q-MA0001', 'chinese/Q-CH0001']) {
        final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
        File(p.join(dir.path, 'question.json')).writeAsStringSync('{}');
      }
      final found = discoverPackageDirs(<String>[root.path]);
      expect(found, <String>[
        p.normalize(p.join(root.path, 'chinese', 'Q-CH0001')),
        p.normalize(p.join(root.path, 'math', 'Q-MA0001')),
        p.normalize(p.join(root.path, 'physics', 'Q-PH0001')),
      ]);

      final single = Directory(p.join(temp.path, 'single'))..createSync();
      File(p.join(single.path, 'question.json')).writeAsStringSync('{}');
      expect(discoverPackageDirs(<String>[single.path]), <String>[
        p.normalize(single.absolute.path),
      ]);
    });

    test('目录不存在抛 StateError', () {
      expect(
        () => discoverPackageDirs(<String>[p.join(temp.path, 'nope')]),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 2b. 整卷目录发现
  // ---------------------------------------------------------------------------

  group('整卷目录发现', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('exam_paper_discover_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('递归找 paper.json 并按路径排序；根目录本身是卷也认', () {
      final root = Directory(p.join(temp.path, 'papers'))..createSync();
      for (final name in <String>['b/2025-x', 'a/2024-y']) {
        final dir = Directory(p.join(root.path, name))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'paper.json')).writeAsStringSync('{}');
      }
      expect(discoverPaperDirs(<String>[root.path]), <String>[
        p.normalize(p.join(root.path, 'a', '2024-y')),
        p.normalize(p.join(root.path, 'b', '2025-x')),
      ]);

      final single = Directory(p.join(temp.path, 'single'))..createSync();
      File(p.join(single.path, 'paper.json')).writeAsStringSync('{}');
      expect(discoverPaperDirs(<String>[single.path]), <String>[
        p.normalize(single.absolute.path),
      ]);
    });

    test('目录不存在抛 StateError', () {
      expect(
        () => discoverPaperDirs(<String>[p.join(temp.path, 'nope')]),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 3. 只读库画像 / 备份
  // ---------------------------------------------------------------------------

  group('只读库画像与备份', () {
    late Directory temp;
    late String dbPath;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('content_import_db_');
      dbPath = p.join(temp.path, 'furnace.db');
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE questions (id TEXT PRIMARY KEY, answer TEXT)');
      db.execute('CREATE TABLE knowledge_points (id TEXT PRIMARY KEY)');
      db.execute("INSERT INTO questions VALUES ('q-1', 'B')");
      db.execute("INSERT INTO knowledge_points VALUES ('kp-1')");
      db.execute('PRAGMA user_version = 47');
      db.dispose();
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('readDatabaseInfo：只读、计数、完整性、schema', () {
      final shaBefore = sha256HexOfFile(File(dbPath));
      final info = readDatabaseInfo(dbPath);
      expect(info.schemaVersion, 47);
      expect(info.integrity, 'ok');
      expect(info.counts['questions'], 1);
      expect(info.counts['knowledge_points'], 1);
      expect(info.counts['content_refs'], isNull, reason: '表不存在要如实为 null');
      expect(info.walPresent, isFalse);
      // 只读检查不得改动文件。
      expect(sha256HexOfFile(File(dbPath)), shaBefore);
    });

    test('readDatabaseInfo 对不存在的库/空文件抛 StateError', () {
      expect(
        () => readDatabaseInfo(p.join(temp.path, 'missing.db')),
        throwsA(isA<StateError>()),
      );
      final empty = File(p.join(temp.path, 'empty.db'))..writeAsStringSync('');
      expect(() => readDatabaseInfo(empty.path), throwsA(isA<StateError>()));
    });

    test('createDatabaseBackup：VACUUM INTO + 完整性 + 源库 SHA256 不变', () {
      final backup = createDatabaseBackup(
        dbPath: dbPath,
        backupDir: p.join(temp.path, 'backups'),
      );
      expect(File(backup.backupPath).existsSync(), isTrue);
      expect(backup.integrityCheck, 'ok');
      expect(backup.sourceUnchanged, isTrue);
      expect(backup.sha256SourceBefore, backup.sha256SourceAfter);
      expect(backup.sourceSchemaVersion, 47);
      expect(backup.bytes, greaterThan(0));
      // 备份里必须真的有一行，而不是空壳。
      final copy = sqlite3.open(backup.backupPath, mode: OpenMode.readOnly);
      try {
        expect(copy.select('SELECT COUNT(*) AS c FROM questions').first['c'], 1);
      } finally {
        copy.dispose();
      }
      expect(backup.backupPath, endsWith('.bak'));

      // 同一秒内再备份一次：文件名不能撞车（追加 -1）。
      final second = createDatabaseBackup(
        dbPath: dbPath,
        backupDir: p.join(temp.path, 'backups'),
      );
      expect(second.backupPath, isNot(backup.backupPath));
    });

    test('备份不存在的库抛 StateError', () {
      expect(
        () => createDatabaseBackup(dbPath: p.join(temp.path, 'nope.db')),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 4. 渲染与退出码
  // ---------------------------------------------------------------------------

  group('渲染与退出码', () {
    ContentImportCliRun run({
      ContentImportMode mode = ContentImportMode.dryRun,
      int hostExit = 0,
      bool ok = true,
      int blocked = 0,
      bool unchanged = true,
      Map<String, Object?>? resultOverride,
    }) {
      return ContentImportCliRun(
        mode: mode,
        packageDirs: const <String>['p1'],
        host: ContentImportHostResult(
          exitCode: hostExit,
          stdout: '',
          stderr: '',
          requestPath: '',
          resultPath: '',
        ),
        result: resultOverride ??
            <String, Object?>{
              'ok': ok,
              'summary': <String, Object?>{'blocked_packages': blocked},
              'transaction': <String, Object?>{
                'committed': mode == ContentImportMode.apply,
              },
            },
        runAt: DateTime.utc(2026, 11, 15),
        sourcePath: 'db',
        integrity: ContentImportIntegrity(
          path: 'db',
          bytesBefore: 10,
          bytesAfter: unchanged ? 10 : 11,
          sha256Before: 'aa',
          sha256After: unchanged ? 'aa' : 'bb',
          modifiedBefore: DateTime.utc(2026, 11, 15),
          modifiedAfter: unchanged ? DateTime.utc(2026, 11, 15) : DateTime.utc(2026, 11, 16),
        ),
      );
    }

    test('退出码：成功 0 / host 失败 4 / 导入失败 1 / 见证缺陷 2 / blocked 5', () {
      expect(exitCodeFor(run()), 0);
      expect(exitCodeFor(run(hostExit: 2)), 4);
      expect(exitCodeFor(run(ok: false)), 1);
      expect(exitCodeFor(run(unchanged: false)), 2);
      expect(exitCodeFor(run(blocked: 1)), 5);
      // apply 允许库变化。
      expect(exitCodeFor(run(mode: ContentImportMode.apply, unchanged: false)), 0);
    });

    test('人类可读报告包含关键段落；--json 是合法 JSON', () {
      final rendered = renderContentImportRun(run(), json: false);
      expect(rendered, contains('dry-run（副本 + 事务回滚）'));
      expect(rendered, contains('原库未被修改：是'));
      final json = renderContentImportRun(run(), json: true);
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['schema'], 'content.import.cli/1');
      expect(decoded['mode'], 'dry_run');
      expect(decoded['exit_code'], 0);
    });

    test('报告里的未映射知识点/缺失标签/kp-map 模板能渲染（计数与明细是不同字段）', () {
      // 回归：`unmapped_knowledge_points` 是 int 计数，明细在 `_detail`；
      // 早先把它当 List 强转会抛 type cast（真库副本验证时实际踩到过）。
      final rendered = renderContentImportRun(
        run(
          resultOverride: <String, Object?>{
            'ok': true,
            'transaction': <String, Object?>{'committed': false, 'rolled_back': true},
            'counts_before': <String, Object?>{'questions': 653},
            'counts_after_import': <String, Object?>{'questions': 656},
            'counts_after': <String, Object?>{'questions': 653},
            'packages': const <Object?>[],
            'summary': <String, Object?>{
              'blocked_packages': 0,
              'skipped': 3,
              'missing_tags': 1,
              'missing_tag_paths': <String>['文化课/学科/物理'],
              'unmapped_knowledge_points': 1,
              'unmapped_knowledge_points_detail': <Map<String, Object?>>[
                <String, Object?>{
                  'content_node_id': 'kp-x',
                  'label': '测试节点',
                  'reason': 'knowledge_point_unmapped',
                },
              ],
              'kp_map_template': <String, Object?>{'kp-x': ''},
              'would_create': <String, Object?>{
                'questions': 3,
                'knowledge_points': 13,
                'content_refs': 16,
                'cards': 0,
              },
            },
          },
        ),
        json: false,
      );
      expect(rendered, contains('文化课/学科/物理'));
      expect(rendered, contains('kp-x'));
      expect(rendered, contains('kp-map 模板'));
    });
  });

  // ---------------------------------------------------------------------------
  // 5. launcher 编排：dry-run 复制/销毁、apply 默认备份（假 host）
  // ---------------------------------------------------------------------------

  group('launcher 编排（假 host）', () {
    late Directory temp;
    late String dbPath;
    late String packagesRoot;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('content_import_flow_');
      dbPath = p.join(temp.path, 'furnace.db');
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE questions (id TEXT PRIMARY KEY)');
      db.execute('PRAGMA user_version = 47');
      db.dispose();
      packagesRoot = p.join(temp.path, 'packages');
      final packageDir = Directory(p.join(packagesRoot, 'Q-TEST0001'))
        ..createSync(recursive: true);
      File(p.join(packageDir.path, 'question.json')).writeAsStringSync('{}');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    ContentImportHostRunner fakeHost(Map<String, Object?> result) {
      return (request) async {
        final dir = Directory.systemTemp.createTempSync('fake_host_');
        final resultPath = p.join(dir.path, 'content-import-result.json');
        File(resultPath).writeAsStringSync(jsonEncode(result));
        return ContentImportHostResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
          requestPath: '',
          resultPath: resultPath,
        );
      };
    }

    test('dry-run：复制副本、跑完销毁、原库 SHA256 不变', () async {
      final shaBefore = sha256HexOfFile(File(dbPath));
      final options = ContentImportCliOptions.parse(<String>[
        'dry-run',
        '--db',
        dbPath,
        '--packages',
        packagesRoot,
      ]);
      final run = await collectDryRun(
        options,
        host: fakeHost(<String, Object?>{
          'ok': true,
          'mode': 'dry_run',
          'transaction': <String, Object?>{'committed': false, 'rolled_back': true},
          'summary': <String, Object?>{'blocked_packages': 0},
          'packages': const <Object?>[],
        }),
      );
      expect(run.integrity, isNotNull);
      expect(run.integrity!.unchanged, isTrue);
      expect(sha256HexOfFile(File(dbPath)), shaBefore);
      // 临时副本默认已删除。
      expect(run.workCopy, isNotNull);
      expect(Directory(run.workCopy!.directory).existsSync(), isFalse);
      expect(exitCodeFor(run), 0);
    });

    test('apply：默认先备份；--no-backup 时不备份', () async {
      final options = ContentImportCliOptions.parse(<String>[
        'apply',
        '--db',
        dbPath,
        '--packages',
        packagesRoot,
        '--backup-dir',
        p.join(temp.path, 'backups'),
      ]);
      final run = await collectApply(
        options,
        host: fakeHost(<String, Object?>{
          'ok': true,
          'mode': 'apply',
          'transaction': <String, Object?>{'committed': true, 'rolled_back': false},
          'summary': <String, Object?>{'blocked_packages': 0},
          'packages': const <Object?>[],
        }),
      );
      expect(run.backup, isNotNull);
      expect(File(run.backup!.backupPath).existsSync(), isTrue);
      expect(exitCodeFor(run), 0);

      final noBackup = ContentImportCliOptions.parse(<String>[
        'apply',
        '--db',
        dbPath,
        '--packages',
        packagesRoot,
        '--no-backup',
      ]);
      final second = await collectApply(
        noBackup,
        host: fakeHost(<String, Object?>{
          'ok': true,
          'mode': 'apply',
          'summary': <String, Object?>{'blocked_packages': 0},
          'packages': const <Object?>[],
        }),
      );
      expect(second.backup, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 5b. launcher 编排：整卷（假 host）
  // ---------------------------------------------------------------------------

  group('launcher 编排：整卷（假 host）', () {
    late Directory temp;
    late String dbPath;
    late String papersRoot;
    late String mediaDir;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('exam_paper_flow_');
      dbPath = p.join(temp.path, 'furnace.db');
      final db = sqlite3.open(dbPath);
      db.execute('CREATE TABLE questions (id TEXT PRIMARY KEY)');
      db.execute('PRAGMA user_version = 47');
      db.dispose();
      final paperDir =
          Directory(p.join(temp.path, 'papers', '2025-math-national1'))
            ..createSync(recursive: true);
      File(p.join(paperDir.path, 'paper.json')).writeAsStringSync('{}');
      papersRoot = p.join(temp.path, 'papers');
      mediaDir = p.join(temp.path, 'media');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    ContentImportHostRunner capturingHost(
      List<ContentImportHostRequest> captured,
      Map<String, Object?> result,
    ) {
      return (request) async {
        captured.add(request);
        final dir = Directory.systemTemp.createTempSync('fake_exam_host_');
        final resultPath = p.join(dir.path, 'content-import-result.json');
        File(resultPath).writeAsStringSync(jsonEncode(result));
        return ContentImportHostResult(
          exitCode: 0,
          stdout: '',
          stderr: '',
          requestPath: '',
          resultPath: resultPath,
        );
      };
    }

    Map<String, Object?> examResult({String mode = 'dry_run'}) =>
        <String, Object?>{
          'ok': true,
          'mode': mode,
          'transaction': <String, Object?>{
            'committed': mode == 'apply',
            'rolled_back': mode == 'dry_run',
          },
          'summary': <String, Object?>{'blocked_packages': 0},
          'papers': const <Object?>[],
        };

    test('dry-run 整卷：请求带 paper_dirs + 临时 media；原库 SHA256 不变、副本删除',
        () async {
      final captured = <ContentImportHostRequest>[];
      final options = ContentImportCliOptions.parse(<String>[
        'dry-run',
        '--db',
        dbPath,
        '--papers',
        papersRoot,
      ]);
      final shaBefore = sha256HexOfFile(File(dbPath));
      final run = await collectDryRun(
        options,
        host: capturingHost(captured, examResult()),
      );
      expect(captured, hasLength(1));
      expect(captured.single.paperDirs, hasLength(1));
      expect(captured.single.packageDirs, isEmpty);
      expect(captured.single.mediaDir, isNotNull);
      expect(
        p.isWithin(captured.single.scratchDir!, captured.single.mediaDir!),
        isTrue,
        reason: 'dry-run 的图片根必须在临时副本目录里',
      );
      expect(run.examPaperSource, isTrue);
      expect(run.integrity!.unchanged, isTrue);
      expect(sha256HexOfFile(File(dbPath)), shaBefore);
      expect(Directory(run.workCopy!.directory).existsSync(), isFalse);
      expect(exitCodeFor(run), 0);
    });

    test('apply 整卷：默认备份；请求 media_dir 就是 --media-dir', () async {
      final captured = <ContentImportHostRequest>[];
      final options = ContentImportCliOptions.parse(<String>[
        'apply',
        '--db',
        dbPath,
        '--papers',
        papersRoot,
        '--media-dir',
        mediaDir,
      ]);
      final run = await collectApply(
        options,
        host: capturingHost(captured, examResult(mode: 'apply')),
      );
      expect(captured.single.paperDirs, hasLength(1));
      expect(captured.single.packageDirs, isEmpty);
      expect(captured.single.mediaDir, mediaDir);
      expect(run.backup, isNotNull);
      expect(File(run.backup!.backupPath).existsSync(), isTrue);
      expect(exitCodeFor(run), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // 5c. host 行为：真实数学卷（内存库，task-88）
  // ---------------------------------------------------------------------------

  group('host：真实数学卷（内存库）', () {
    late Directory mediaRoot;
    late AppDatabase db;

    setUp(() {
      mediaRoot = Directory.systemTemp.createTempSync('exam_paper_cli_media_');
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      if (mediaRoot.existsSync()) {
        mediaRoot.deleteSync(recursive: true);
      }
    });

    Future<Map<String, Object?>> runExam({
      String mode = 'dry_run',
      String? mediaPath,
      ExamPaperMediaStoreFactory? mediaStoreFactory,
    }) {
      final paper = ExamPaperDocument.loadDirectory(_mathPaperDir);
      return executeExamPaperImport(
        db,
        mode: mode,
        papers: <ExamPaperDocument>[paper],
        paperDirs: const <String>[_mathPaperDir],
        mediaRoot: mediaPath,
        mediaStoreFactory: mediaStoreFactory,
        now: DateTime.utc(2026, 11, 15, 12),
      );
    }

    test('dry-run：19 题/44 选项/14 图/19 引用；回滚后计数归零、图片目录清掉',
        () async {
      final result = await runExam(mediaPath: mediaRoot.path);
      expect(result['ok'], isTrue, reason: '${result['error']}');
      expect(result['dry_run'], isTrue);
      final summary = _asMap(result['summary']);
      expect(summary['papers'], 1);
      expect(summary['questions'], 19);
      expect(summary['created_questions'], 19);
      expect(summary['reused_questions'], 0);
      expect(summary['options'], 44);
      expect(summary['figures'], 14);
      expect(summary['figures_imported'], 14);
      expect(summary['content_refs'], 19);
      expect(summary['blocked_issues'], 0);

      final would = _asMap(summary['would_create']);
      expect(would['questions'], 19);
      expect(would['options'], 44);
      expect(would['figures'], 14);
      expect(would['content_refs'], 19);

      expect(_asMap(result['transaction'])['rolled_back'], isTrue);
      expect(_asMap(result['transaction'])['committed'], isFalse);
      expect(result['dry_run_rollback_verified'], isTrue);
      expect(_asMap(result['exam_counts_after']), _asMap(result['exam_counts_before']));
      expect(_asMap(result['exam_counts_before'])['questions'], 0);
      expect(
        Directory(p.join(mediaRoot.path, QuestionMediaStore.directoryName))
            .existsSync(),
        isFalse,
        reason: 'dry-run 回滚后本次新写的图片目录要删掉',
      );
      expect(result['media_cleanup_removed_dirs'], greaterThan(0),
          reason: '本次写过的题目图片目录（有图的题若干）要被删掉');
    });

    test('apply：19 题/44 选项/14 图/19 引用；二次 apply created=0 不翻倍',
        () async {
      final first =
          await runExam(mode: 'apply', mediaPath: mediaRoot.path);
      expect(first['ok'], isTrue, reason: '${first['error']}');
      expect(_asMap(first['transaction'])['committed'], isTrue);
      final firstSummary = _asMap(first['summary']);
      expect(firstSummary['created_questions'], 19);
      expect(firstSummary['figures_imported'], 14);
      expect(await _examCount(db, 'questions'), 19);
      expect(await _examCount(db, 'question_options'), 44);
      expect(await _examCount(db, 'content_refs'), 19);
      expect(await _examCount(db, 'attachments'), 14);
      expect(await _examCount(db, 'knowledge_points'), 0,
          reason: '整卷不建知识点');
      expect(await _examCount(db, 'tags'), 0);
      expect(await _examCount(db, 'object_tags'), 0);

      final second =
          await runExam(mode: 'apply', mediaPath: mediaRoot.path);
      expect(second['ok'], isTrue, reason: '${second['error']}');
      final secondSummary = _asMap(second['summary']);
      expect(secondSummary['created_questions'], 0);
      expect(secondSummary['reused_questions'], 19);
      expect(secondSummary['figures_imported'], 0);
      expect(secondSummary['options'], 44);
      expect(secondSummary['content_refs'], 19);
      expect(await _examCount(db, 'questions'), 19);
      expect(await _examCount(db, 'question_options'), 44);
      expect(await _examCount(db, 'content_refs'), 19);
      expect(await _examCount(db, 'attachments'), 14);
    });

    test('无 media store：Q6/Q17 blocked，其余 17 题导入，attachments=0',
        () async {
      final result = await runExam(mediaPath: null);
      expect(result['ok'], isTrue, reason: '${result['error']}');
      final summary = _asMap(result['summary']);
      expect(summary['questions'], 17);
      expect(summary['created_questions'], 17);
      expect(summary['blocked_issues'], 2);
      expect(summary['figures_imported'], 0);
      final paper = _asMap((result['papers'] as List).single);
      expect(paper['status'], ExamPaperImportStatus.importedWithSkips.name);
      final blocked = (paper['blocked'] as List).whereType<Map>().toList();
      expect(
        blocked.map((issue) => issue['question_number']).toSet(),
        <int>{6, 17},
      );
      expect(
        blocked.map((issue) => issue['code']).toSet(),
        <String>{ExamPaperBlockReason.figureNotImportable},
      );
      expect(_asMap(result['exam_counts_after'])['questions'], 0,
          reason: 'dry-run 已回滚');
    });

    test('失败回滚：图片落盘抛错 → 整卷回滚、计数归零、新图片目录清掉', () async {
      final result = await runExam(
        mode: 'apply',
        mediaPath: mediaRoot.path,
        mediaStoreFactory: (db, root) => _FailingMediaStore(
          database: db,
          supportDirectory: () async => Directory(root),
        ),
      );
      expect(result['ok'], isFalse);
      expect('${result['error']}', contains('injected media failure'));
      expect(_asMap(result['transaction'])['rolled_back'], isTrue);
      expect(result['rollback_verified'], isTrue);
      expect(await _examCount(db, 'questions'), 0);
      expect(await _examCount(db, 'question_options'), 0);
      expect(await _examCount(db, 'content_refs'), 0);
      expect(await _examCount(db, 'attachments'), 0);
      expect(
        Directory(p.join(mediaRoot.path, QuestionMediaStore.directoryName))
            .existsSync(),
        isFalse,
        reason: '失败回滚后不留孤儿图片目录',
      );
    });
  }, skip: _mathPaperPresent ? false : '真实数学卷不在本机：$_mathPaperDir');

  // ---------------------------------------------------------------------------
  // 6. host 行为（真内容包 + 内存库）
  // ---------------------------------------------------------------------------
  group('host：真内容包导入（内存库）', () {
    late AppDatabase db;
    late List<ContentPackage> packages;

    setUpAll(() {
      const reader = ContentPackageReader();
      packages = <ContentPackage>[
        for (final dir in _realPackageDirs) reader.readDirectory(dir).package,
      ];
    });

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<Map<String, int>> counts() async {
      final result = <String, int>{};
      for (final table in const <String>[
        'questions',
        'knowledge_points',
        'content_refs',
        'card_templates',
        'card_states',
        'review_logs',
      ]) {
        final row = await db
            .customSelect('SELECT COUNT(*) AS c FROM "$table"')
            .getSingle();
        result[table] = row.read<int>('c');
      }
      return result;
    }

    List<Map<String, Object?>> packageResults(Map<String, Object?> result) =>
        <Map<String, Object?>>[
          for (final entry in (result['packages'] as List? ?? const []))
            if (entry is Map) entry.cast<String, Object?>(),
        ];

    test('dry-run：wouldCreate 3 题 / 13 知识点 / 16 引用，事务回滚且库为空', () async {
      final result = await executeContentImport(
        db,
        mode: 'dry_run',
        packages: packages,
        packageDirs: _realPackageDirs,
      );
      expect(result['ok'], isTrue, reason: '${result['error']}');
      expect(result['dry_run'], isTrue);
      expect(result['db_schema_version'], kFurnaceSchemaVersion);
      expect(result['app_schema_version'], kFurnaceSchemaVersion);
      final transaction = _asMap(result['transaction']);
      expect(transaction['committed'], isFalse);
      expect(transaction['rolled_back'], isTrue);
      expect(result['counts_after'], equals(result['counts_before']));

      final summary = _asMap(result['summary']);
      final wouldCreate = _asMap(summary['would_create']);
      expect(wouldCreate['questions'], 3);
      expect(wouldCreate['knowledge_points'], 13);
      expect(wouldCreate['content_refs'], 16);
      expect(summary['blocked_packages'], 0);
      expect(summary['missing_tags'], greaterThanOrEqualTo(13));
      expect(summary['missing_tag_paths'], isNotEmpty);
      expect(summary['missing_tag_paths'], contains('文化课/学科/物理'));

      expect(packageResults(result).map((package) => package['content_id']), <String>[
        'Q-PH0001',
        'Q-MA0001',
        'Q-CH0001',
      ]);
      // 回滚后一行都不留。
      expect(await counts(), <String, int>{
        'questions': 0,
        'knowledge_points': 0,
        'content_refs': 0,
        'card_templates': 0,
        'card_states': 0,
        'review_logs': 0,
      });
    });

    test('apply：3 题 / 13 知识点 / 16 引用；二次 apply 幂等', () async {
      final first = await executeContentImport(
        db,
        mode: 'apply',
        packages: packages,
        packageDirs: _realPackageDirs,
      );
      expect(first['ok'], isTrue, reason: '${first['error']}');
      expect(_asMap(first['transaction'])['committed'], isTrue);
      expect(await counts(), <String, int>{
        'questions': 3,
        'knowledge_points': 13,
        'content_refs': 16,
        'card_templates': 0,
        'card_states': 0,
        'review_logs': 0,
      });
      final firstIds = <String, Object?>{
        for (final package in packageResults(first))
          '${package['content_id']}': package['question_id'],
      };
      expect(firstIds.values.toSet(), hasLength(3));
      final deltaApplied = _asMap(first['counts_delta_applied']);
      expect(deltaApplied['questions'], 3);
      expect(deltaApplied['knowledge_points'], 13);
      expect(deltaApplied['content_refs'], 16);

      final second = await executeContentImport(
        db,
        mode: 'apply',
        packages: packages,
        packageDirs: _realPackageDirs,
      );
      expect(second['ok'], isTrue);
      final secondSummary = _asMap(second['summary']);
      final wouldCreate = _asMap(secondSummary['would_create']);
      expect(wouldCreate['questions'], 0);
      expect(wouldCreate['knowledge_points'], 0);
      expect(wouldCreate['content_refs'], 0);
      expect(wouldCreate['cards'], 0);
      expect(await counts(), <String, int>{
        'questions': 3,
        'knowledge_points': 13,
        'content_refs': 16,
        'card_templates': 0,
        'card_states': 0,
        'review_logs': 0,
      });
      // 同一 content_id 还是同一道产品题。
      expect(
        <String, Object?>{
          for (final package in packageResults(second))
            '${package['content_id']}': package['question_id'],
        },
        firstIds,
      );
    });

    test('apply：DAG 卡 dry-run 6/2；--cards-apply 落 6 模板 + 6 引用，不建 FSRS', () async {
      final physics = packages.first;
      final dry = await executeContentImport(
        db,
        mode: 'dry_run',
        packages: <ContentPackage>[physics],
        cards: true,
      );
      final dryPlan = _asMap(_asMap(packageResults(dry).single)['card_plan']);
      expect(dryPlan['would_create'], 6);
      expect(dryPlan['skipped'], 2);
      expect(_asMap(_asMap(dry['summary'])['would_create'])['cards'], 6);
      expect((await counts())['card_templates'], 0, reason: 'dry-run 不写卡');

      final applied = await executeContentImport(
        db,
        mode: 'apply',
        packages: <ContentPackage>[physics],
        cards: true,
        cardsApply: true,
      );
      expect(applied['ok'], isTrue, reason: '${applied['error']}');
      expect(_asMap(_asMap(applied['summary'])['would_create'])['cards'], 6);
      expect(await counts(), <String, int>{
        'questions': 1,
        'knowledge_points': 4,
        'content_refs': 11,
        'card_templates': 6,
        'card_states': 0,
        'review_logs': 0,
      });

      final again = await executeContentImport(
        db,
        mode: 'apply',
        packages: <ContentPackage>[physics],
        cards: true,
        cardsApply: true,
      );
      expect(_asMap(_asMap(again['summary'])['would_create'])['cards'], 0);
      expect((await counts())['card_templates'], 6);
    });

    test('--create-kps=false：不建知识点，13 个节点进未映射报告与 kp-map 模板', () async {
      final result = await executeContentImport(
        db,
        mode: 'apply',
        packages: packages,
        createKnowledgePoints: false,
      );
      expect(result['ok'], isTrue);
      expect(await counts(), <String, int>{
        'questions': 3,
        'knowledge_points': 0,
        'content_refs': 3,
        'card_templates': 0,
        'card_states': 0,
        'review_logs': 0,
      });
      final summary = _asMap(result['summary']);
      expect(summary['unmapped_knowledge_points'], 13);
      expect(
        (summary['unmapped_knowledge_points_detail'] as List).length,
        13,
      );
      expect((summary['kp_map_template'] as Map).length, 13);
    });

    test('--kp-map：显式映射到已有产品知识点，不新建那一个', () async {
      final anki = AnkiRepository(db);
      final existing = await anki.createKnowledgePoint(
        title: '已有产品知识点',
        content: 'seed',
        source: 'seed',
      );
      final physics = packages.first;
      final nodeId = physics.knowledge.first.nodeId;
      final result = await executeContentImport(
        db,
        mode: 'apply',
        packages: <ContentPackage>[physics],
        kpMap: <String, String>{nodeId: existing.id},
      );
      expect(result['ok'], isTrue, reason: '${result['error']}');
      final points = (packageResults(result).single['knowledge_points'] as List)
          .whereType<Map>()
          .cast<Map<String, Object?>>()
          .toList();
      final mapped = points.singleWhere((point) => point['content_node_id'] == nodeId);
      expect(mapped['mapped'], isTrue);
      expect(mapped['created'], isFalse);
      expect(mapped['product_knowledge_point_id'], existing.id);
      // 1 个已有 + 其余新建。
      expect((await counts())['knowledge_points'], physics.knowledge.length);
    });

    test('失败回滚：第二题 ingest 抛错 → 整批回滚，计数回到导入前', () async {
      final result = await executeContentImport(
        db,
        mode: 'apply',
        packages: packages,
        serviceFactory: (db) => ContentPackageImportService(
          db,
          questions: _FailAfterFirstQuestionRepository(db),
        ),
      );
      expect(result['ok'], isFalse);
      expect('${result['error']}', contains('injected ingest failure'));
      final transaction = _asMap(result['transaction']);
      expect(transaction['committed'], isFalse);
      expect(transaction['rolled_back'], isTrue);
      expect(result['rollback_verified'], isTrue);
      expect(await counts(), <String, int>{
        'questions': 0,
        'knowledge_points': 0,
        'content_refs': 0,
        'card_templates': 0,
        'card_states': 0,
        'review_logs': 0,
      }, reason: '第一包也不能留下（外层事务整体回滚）');
    });

    test('不覆盖已有题正文：答案被改的同一题再 apply → answer 仍是旧值并记跳过', () async {
      final physicsDir = _realPackageDirs.first;
      final first = await executeContentImport(
        db,
        mode: 'apply',
        packages: <ContentPackage>[packages.first],
      );
      expect(first['ok'], isTrue);
      final questionId = packageResults(first).single['question_id'];
      final stored = await (db.select(db.questions)
            ..where((row) => row.id.equals('$questionId')))
          .getSingle();
      expect(stored.answer, 'B');

      final modified = _packageWithFirstAnswer(physicsDir, 'C');
      final second = await executeContentImport(
        db,
        mode: 'apply',
        packages: <ContentPackage>[modified],
      );
      expect(second['ok'], isTrue);
      final package = packageResults(second).single;
      expect(package['question_created'], isFalse);
      expect(package['question_id'], questionId);
      final skippedCodes = <String>[
        for (final skip in (package['skipped'] as List? ?? const []))
          if (skip is Map) '${skip['code']}',
      ];
      expect(skippedCodes, contains('question_body_not_updated'));

      final after = await (db.select(db.questions)
            ..where((row) => row.id.equals('$questionId')))
          .getSingle();
      expect(after.answer, 'B', reason: '产品题只追加，不原地改答案');
      expect((await counts())['questions'], 1);
    });

    test('packages 模式只解析：不打开库，返回三包与字段', () async {
      final result = await runContentImportHost(<String, Object?>{
        'schema': contentImportRequestSchema,
        'mode': 'packages',
        'package_dirs': _realPackageDirs,
      });
      expect(result['ok'], isTrue);
      final listed = <Map<String, Object?>>[
        for (final entry in (result['packages'] as List))
          (entry as Map).cast<String, Object?>(),
      ];
      expect(listed.map((package) => package['content_id']), <String>[
        'Q-PH0001',
        'Q-MA0001',
        'Q-CH0001',
      ]);
      expect(listed.first['knowledge_nodes'], 4);
      expect(listed[1]['knowledge_nodes'], 4);
      expect(listed[2]['knowledge_nodes'], 5);
    });

    test('内容包解析失败：host 返回 ok:false + parse_errors（不打开库）', () async {
      final result = await runContentImportHost(<String, Object?>{
        'schema': contentImportRequestSchema,
        'mode': 'packages',
        'package_dirs': <String>[
          ..._realPackageDirs,
          r'C:\definitely\not\a\package',
        ],
      });
      expect(result['ok'], isFalse);
      expect('${result['error']}', contains('内容包解析失败'));
      expect((result['parse_errors'] as List).length, 1);
    });

    test('纯 Dart 常量与 drift schema 一致', () async {
      expect(db.schemaVersion, kFurnaceSchemaVersion);
      expect(hostSchemaVersion, kFurnaceSchemaVersion);
    });
  }, skip: _realPackagesPresent ? false : '真实内容包不在本机：${_realPackageDirs.join(', ')}');
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

/// 一张表的行数（整卷计数断言用；表不存在时返回 0）。
Future<int> _examCount(AppDatabase db, String table) async {
  try {
    final rows =
        await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').get();
    return rows.first.read<int>('c');
  } on Exception {
    return 0;
  }
}

/// 第 2 张图落盘时抛错：验证整卷事务回滚 + 新图片目录清理。
class _FailingMediaStore extends QuestionMediaStore {
  _FailingMediaStore({
    required super.database,
    super.supportDirectory,
  });

  int _saves = 0;

  @override
  Future<QuestionImage> save({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
    int? sortOrder,
    String role = QuestionImageRole.stem,
    DateTime? now,
  }) {
    _saves += 1;
    if (_saves > 1) {
      throw StateError('injected media failure on save $_saves');
    }
    return super.save(
      questionId: questionId,
      fileName: fileName,
      bytes: bytes,
      mime: mime,
      sortOrder: sortOrder,
      role: role,
      now: now,
    );
  }
}

/// 读一个真实包，把第一段答案改成 [value]；用于「不覆盖已有题正文」用例。
ContentPackage _packageWithFirstAnswer(String packageDir, String value) {
  final questionFile = File(p.join(packageDir, 'question.json'));
  final question = (jsonDecode(questionFile.readAsStringSync()) as Map)
      .cast<String, Object?>();
  final subject = '${question['subject']}';
  final boardFile = File(p.join(packageDir, 'boards', '$subject-board.json'));
  final board = boardFile.existsSync()
      ? (jsonDecode(boardFile.readAsStringSync()) as Map).cast<String, Object?>()
      : null;
  final answer = (question['answer'] as Map).cast<String, Object?>();
  final parts = (answer['parts'] as List)
      .whereType<Map>()
      .map((part) => part.cast<String, Object?>())
      .toList();
  parts.first['value'] = value;
  return ContentPackage.fromJson(question, board: board);
}

/// 第二次 ingest 抛错：用于验证外层事务把第一包一起回滚。
class _FailAfterFirstQuestionRepository extends QuestionRepository {
  _FailAfterFirstQuestionRepository(super.db);

  int _calls = 0;

  @override
  Future<({Question question, bool created})> ingest(
    QuestionDraft draft, {
    DateTime? now,
  }) {
    _calls += 1;
    if (_calls > 1) {
      throw StateError('injected ingest failure on call $_calls');
    }
    return super.ingest(draft, now: now);
  }
}
