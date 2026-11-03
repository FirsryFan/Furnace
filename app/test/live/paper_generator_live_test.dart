import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/questions/application/paper_generator_service.dart';

/// 真实网络 + 真实题库的端到端测试：只在 RUN_LIVE_PAPER=1 时跑。
/// 会消耗模型 token，不进入常规测试集。
void main() {
  test('真实 AI 生成 8 题题单（四科 ×2，视觉 + 并发 + SVG 树）', () async {
    final env = Platform.environment;
    final legacy = Platform.environment['APPDATA'];
    if (legacy == null) {
      fail('APPDATA missing');
    }
    final dbPath =
        legacy.replaceAll('\\', '/') + '/FirsryFan/Furnace/furnace.db';
    final source = File(dbPath);
    expect(await source.exists(), isTrue, reason: '真实库不存在');
    final tempRoot =
        Directory('E:/Workspaces/Furnace/00-inbox/live-paper-output');
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
    await tempRoot.create(recursive: true);
    final dbCopy = File(tempRoot.path + '/furnace.db');
    await source.copy(dbCopy.path);

    final db = AppDatabase.forTesting(NativeDatabase(dbCopy));
    final config = await AiRepository(db).getConfig();
    expect(config.isUsable, isTrue, reason: 'AI 未配置');
    final support =
        Directory(legacy.replaceAll('\\', '/') + '/FirsryFan/Furnace');
    final service = PaperGeneratorService(
      db: db,
      config: config,
      supportDirectory: () async => support,
      documentsDirectory: () async => Directory('E:/Furnace/data/documents'),
      questionConcurrency: 3,
    );
    final messages = <String>[];
    final result = await service.generate(
      date: DateTime(2026, 11, 4),
      onProgress: messages.add,
    );
    await db.close();

    final md = File(result.markdownPath);
    expect(await md.exists(), isTrue);
    final text = await md.readAsString();
    expect(text, contains('# 物理'));
    expect(text, contains('# 数学'));
    expect(text, contains('# 语文'));
    expect(text, contains('# 英语'));
    expect(RegExp(r'^## 题', multiLine: true).allMatches(text).length, 8);
    final treeFiles = Directory(result.treeDirectory)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();
    expect(treeFiles, isNotEmpty, reason: '没有生成树图');
    for (final f in treeFiles) {
      final svg = await f.readAsString();
      expect(svg, startsWith('<?xml'));
      expect(svg, contains('<svg'));
    }
    // ignore: avoid_print
    print('LIVE PAPER OK: ' +
        result.markdownPath +
        ' trees=' +
        treeFiles.length.toString() +
        ' progress=' +
        messages.length.toString());
  },
      timeout: const Timeout(Duration(minutes: 20)),
      skip: Platform.environment['RUN_LIVE_PAPER'] != '1');
}
