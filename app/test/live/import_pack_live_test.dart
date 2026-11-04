import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

void main() {
  test('真实导入题库包到 E 盘数据库', () async {
    final pack = File(Platform.environment['PACK_PATH'] ??
        r'E:\Workspaces\Furnace\10-projects\furnace-pipeline\ingest-2026-11-05\Furnace-DSN-math-2026-11-05.tqb');
    expect(await pack.exists(), isTrue);
    final dbFile = File(r'E:\Furnace\data\furnace.db');
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final support = Directory(r'E:\Furnace\data');
    final service = QuestionPackService(
      database: db,
      questions: QuestionRepository(db),
      mediaStore: QuestionMediaStore(
          database: db, supportDirectory: () async => support),
      tags: TagRepository(db),
      documentsDirectory: () async => Directory(r'E:\Furnace\data\documents'),
    );
    final bytes = await pack.readAsBytes();
    final peek = service.peek(bytes);
    final preview = await service.planImport(bytes);
    // ignore: avoid_print
    print('PACK questions=' +
        peek.questionCount.toString() +
        ' media=' +
        peek.mediaCount.toString() +
        ' preview=' +
        preview.summaryZh.join(" | "));
    final report = await service.importPack(bytes);
    await db.close();
    // ignore: avoid_print
    print('IMPORT created=' +
        report.createdCount.toString() +
        ' updated=' +
        report.updatedCount.toString() +
        ' skipped=' +
        report.skippedCount.toString() +
        ' media=' +
        report.mediaCount.toString() +
        ' backup=' +
        (report.backupPath ?? report.backupError ?? ''));
    expect(report.createdCount, greaterThan(0));
  },
      timeout: const Timeout(Duration(minutes: 30)),
      skip: Platform.environment['RUN_PACK_IMPORT'] != '1');
}
