/// 用**真实题库**里的思维链生成 DAG 图片样例（2026-11-19）。
///
/// 这不是常规回归用例：它读本机真实 `furnace.db`（复制到临时目录再读，绝不碰
/// 用户库里正在写的文件），把其中每条有步骤的链画成 PNG，写到
/// `docs/dag-samples/generated-<chainId>.png`。真实库不存在时整个用例跳过。
///
/// 用途：证明"详情页显示的那张图"确实能从**真实 AI 解题步骤**生成，而不是只在
/// 测试造的数据上成立；样例图也是给下一版自适应渲染做对照的基准。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/storage/app_storage.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';
import 'package:furnace/features/questions/application/dag_image_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

/// 真实库位置：默认与本机运行中的应用同一处（`AppStorage.windowsDataRootPath`），
/// 也可用环境变量 `FURNACE_REAL_DB` 指到别的数据库（其它机器 / CI）。
final String _realDbPath = Platform.environment['FURNACE_REAL_DB'] ??
    p.join(AppStorage.windowsDataRootPath, 'furnace.db');

final bool _hasRealDb = File(_realDbPath).existsSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '从真实题库的思维链生成 DAG PNG 样例',
    () async {
      final temp = Directory.systemTemp.createTempSync('furnace_real_db_');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });
      // 复制 db + WAL/SHM 再读：真实应用可能正开着这个库。
      final copied = File(p.join(temp.path, 'furnace.db'));
      File(_realDbPath).copySync(copied.path);
      for (final suffix in <String>['-wal', '-shm']) {
        final extra = File('$_realDbPath$suffix');
        if (extra.existsSync()) {
          extra.copySync('${copied.path}$suffix');
        }
      }

      final db = sql.sqlite3.open(copied.path);
      final chains = <({String id, String questionId, String summary})>[];
      final rows = db.select(
        'SELECT c.id AS id, c.question_id AS question_id, c.summary AS summary '
        'FROM reasoning_chains c '
        'WHERE EXISTS (SELECT 1 FROM reasoning_steps s WHERE s.chain_id = c.id) '
        'ORDER BY c.created_at DESC',
      );
      for (final row in rows) {
        chains.add((
          id: row['id'] as String,
          questionId: row['question_id'] as String,
          summary: (row['summary'] as String?) ?? '',
        ));
      }
      expect(chains, isNotEmpty,
          reason: '真实库里没有带步骤的思维链，样例无从生成：$_realDbPath');

      final outputDirectory =
          Directory(p.join(Directory.current.parent.path, 'docs', 'dag-samples'));
      outputDirectory.createSync(recursive: true);
      final renderer = DagImageRenderer();
      final generated = <String>[];

      for (final chain in chains) {
        final stepRows = db.select(
          'SELECT idx, goal, action_type, stuck_risk FROM reasoning_steps '
          'WHERE chain_id = ? ORDER BY idx',
          <Object?>[chain.id],
        );
        final steps = <ParsedStep>[
          for (final row in stepRows)
            ParsedStep(
              index: (row['idx'] as int) + 1,
              goal: (row['goal'] as String?) ?? '',
              actionType: (row['action_type'] as String?) ?? 'unknown',
              action: CapabilityAction.byKey(
                (row['action_type'] as String?) ?? 'unknown',
              ),
              justification: '',
              checkMethod: '',
              stuckRisk: (row['stuck_risk'] as num?)?.toDouble() ??
                  defaultStuckRisk,
              knowledgeHints: const <String>[],
            ),
        ];
        final questionStem = db.select(
          'SELECT stem FROM questions WHERE id = ? LIMIT 1',
          <Object?>[chain.questionId],
        );
        final stem = questionStem.isEmpty
            ? '（题库里已找不到这道题的题干）'
            : (questionStem.first['stem'] as String?) ?? '';

        final result = await renderer.render(
          ParsedChain(summary: chain.summary, steps: steps),
          title: '思维 DAG',
        );
        final file = File(p.join(
          outputDirectory.path,
          'generated-${chain.id}.png',
        ));
        file.writeAsBytesSync(result.bytes);

        // ignore: avoid_print
        print('REAL_DAG_SAMPLE ${file.path}\n'
            '  question=${chain.questionId}\n'
            '  stem=${stem.replaceAll('\n', ' ')}\n'
            '  steps=${steps.length} size=${result.width}x${result.height} '
            'bytes=${result.bytes.length}');

        expect(result.isPng, isTrue);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(20 * 1024),
            reason: '真实步骤画出来的图片不可能只有几 KB');
        generated.add(file.path);
      }

      expect(generated, isNotEmpty);
      db.dispose();

      // ignore: avoid_print
      print('REAL_DAG_SAMPLES_GENERATED=${generated.length}');
    },
    skip: _hasRealDb
        ? false
        : '真实 Furnace 数据库不存在：$_realDbPath（可用 FURNACE_REAL_DB 指定）',
  );
}
