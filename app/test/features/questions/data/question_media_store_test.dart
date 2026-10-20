/// `QuestionMediaStore` 的测试：题目配图要落下的两样东西——磁盘上的文件，和
/// 指向它的 `attachments` 行——必须同生同死，而且不能和别的主人（拍照整理、
/// 别的题）混在一起。
///
/// v24 的验收不是"能选图片了"，而是：题目删了图不会变孤儿、同一道题的图顺序
/// 稳定、文件被人从外面删掉时读回来是 null 而不是抛异常。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory support;
  late QuestionMediaStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    support = Directory.systemTemp.createTempSync('furnace_question_media_');
    store = QuestionMediaStore(
      database: db,
      supportDirectory: () async => support,
    );
  });

  tearDown(() async {
    await db.close();
    if (support.existsSync()) {
      support.deleteSync(recursive: true);
    }
  });

  Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

  /// 某个题目在 `attachments` 里的行数（用来断言行真的删了）。
  Future<int> attachmentCount(String questionId) async {
    final rows = await (db.select(db.attachments)
          ..where((t) => t.ownerId.equals(questionId)))
        .get();
    return rows.length;
  }

  test('save：文件落在 question_images/<题>/<附件>/，attachments 记一行', () async {
    final image = await store.save(
      questionId: 'q-test',
      fileName: 'ch1-page3.png',
      bytes: bytesOf([1, 2, 3, 4]),
    );

    expect(image.relPath, startsWith('${QuestionMediaStore.directoryName}/q-test/'));
    expect(image.relPath, endsWith('ch1-page3.png'));
    expect(image.relPath, contains(image.attachmentId));
    // 入库路径必须是 POSIX 相对路径：Windows 上反斜杠写进数据库，换台机器就读不回来。
    expect(image.relPath.contains('\\'), isFalse);
    expect(image.fileName, 'ch1-page3.png');
    expect(image.extension, 'png');
    expect(image.mime, 'image/png');
    expect(image.sortOrder, 0);

    final file = File(image.absolutePath);
    expect(file.existsSync(), isTrue);
    expect(file.path, startsWith(support.path));
    expect(await file.readAsBytes(), equals([1, 2, 3, 4]));

    final rows = await db.select(db.attachments).get();
    expect(rows, hasLength(1));
    expect(rows.single.ownerType, QuestionMediaStore.ownerType);
    expect(rows.single.ownerId, 'q-test');
    expect(rows.single.relPath, image.relPath);
    expect(rows.single.mime, 'image/png');
    expect(rows.single.sortOrder, 0);
  });

  test('save：sortOrder 缺省接在已有图片后面', () async {
    final first = await store.save(
      questionId: 'q-test',
      fileName: 'a.png',
      bytes: bytesOf([1]),
    );
    final second = await store.save(
      questionId: 'q-test',
      fileName: 'b.png',
      bytes: bytesOf([2]),
    );
    final explicit = await store.save(
      questionId: 'q-test',
      fileName: 'c.png',
      bytes: bytesOf([3]),
      sortOrder: 10,
    );
    final afterExplicit = await store.save(
      questionId: 'q-test',
      fileName: 'd.png',
      bytes: bytesOf([4]),
    );

    expect([first.sortOrder, second.sortOrder], [0, 1]);
    expect(explicit.sortOrder, 10);
    expect(afterExplicit.sortOrder, 11);
  });

  test('list：按 sortOrder 排序，只返回这道题的图', () async {
    await store.save(
      questionId: 'q-b',
      fileName: 'other.png',
      bytes: bytesOf([9]),
    );
    await store.save(
      questionId: 'q-a',
      fileName: 'second.png',
      bytes: bytesOf([2]),
      sortOrder: 5,
    );
    await store.save(
      questionId: 'q-a',
      fileName: 'first.png',
      bytes: bytesOf([1]),
      sortOrder: 1,
    );
    // 别的 owner 写的行：同一个 ownerId 也不该出现在题目配图里。
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-handwriting',
            ownerType: 'handwriting_intake',
            ownerId: 'q-a',
            relPath: 'handwriting_intake/x.png',
            createdAt: 1,
          ),
        );

    final images = await store.list('q-a');
    expect(images.map((image) => image.fileName), ['first.png', 'second.png']);
    expect(images.map((image) => image.sortOrder), [1, 5]);

    final other = await store.list('q-b');
    expect(other.map((image) => image.fileName), ['other.png']);
  });

  test('readBytes：文件还在时读回字节，被删掉后返回 null', () async {
    final image = await store.save(
      questionId: 'q-test',
      fileName: 'a.png',
      bytes: bytesOf([7, 8, 9]),
    );
    expect(await store.readBytes(image.relPath), equals([7, 8, 9]));

    File(image.absolutePath).deleteSync();
    expect(await store.readBytes(image.relPath), isNull);
  });

  test('delete：行和文件一起删，空目录顺手收掉', () async {
    final image = await store.save(
      questionId: 'q-test',
      fileName: 'a.png',
      bytes: bytesOf([1]),
    );
    final file = File(image.absolutePath);
    expect(file.existsSync(), isTrue);

    await store.delete(image);

    expect(file.existsSync(), isFalse);
    expect(await attachmentCount('q-test'), 0);
    // <题>/<附件>/ 两层空目录都应被收掉，只留下 question_images/ 根。
    expect(Directory('${support.path}/${QuestionMediaStore.directoryName}/q-test')
        .existsSync(), isFalse);
  });

  test('deleteForQuestion：只删这道题的图，别的题不动', () async {
    final a1 = await store.save(
      questionId: 'q-a',
      fileName: 'a1.png',
      bytes: bytesOf([1]),
    );
    final a2 = await store.save(
      questionId: 'q-a',
      fileName: 'a2.png',
      bytes: bytesOf([2]),
    );
    final b1 = await store.save(
      questionId: 'q-b',
      fileName: 'b1.png',
      bytes: bytesOf([3]),
    );

    final removed = await store.deleteForQuestion('q-a');

    expect(removed, 2);
    expect(File(a1.absolutePath).existsSync(), isFalse);
    expect(File(a2.absolutePath).existsSync(), isFalse);
    expect(File(b1.absolutePath).existsSync(), isTrue);
    expect(await store.list('q-a'), isEmpty);
    expect(await store.list('q-b'), hasLength(1));
  });

  test('save：同名文件不互相覆盖（按附件 id 分目录）', () async {
    final first = await store.save(
      questionId: 'q-test',
      fileName: 'same.png',
      bytes: bytesOf([1, 1]),
    );
    final second = await store.save(
      questionId: 'q-test',
      fileName: 'same.png',
      bytes: bytesOf([2, 2]),
    );

    expect(first.absolutePath, isNot(second.absolutePath));
    expect(await store.readBytes(first.relPath), equals([1, 1]));
    expect(await store.readBytes(second.relPath), equals([2, 2]));
  });

  test('save：文件名里的目录部分被剥掉，不会跑出题目目录', () async {
    final image = await store.save(
      questionId: 'q-test',
      fileName: '../../evil.png',
      bytes: bytesOf([1]),
    );

    expect(image.fileName, 'evil.png');
    expect(image.relPath, endsWith('/evil.png'));
    expect(image.relPath.contains('..'), isFalse);
    expect(File(image.absolutePath).existsSync(), isTrue);
    // 绝对路径是平台原生分隔符（Windows 上是反斜杠），只断言"确实在本 store 的
    // 目录之下"——拼路径是 `path` 包的事，测试不该在这里重新实现一遍。
    expect(p.isWithin(support.path, image.absolutePath), isTrue);
    expect(
      p.basename(p.dirname(image.absolutePath)),
      image.attachmentId,
      reason: '文件落在 <题>/<附件>/ 两层目录里',
    );
  });

  test('save：认不出的扩展名落 null，显式 mime 优先', () async {
    final unknown = await store.save(
      questionId: 'q-test',
      fileName: 'scan.bin',
      bytes: bytesOf([1]),
    );
    final explicit = await store.save(
      questionId: 'q-test',
      fileName: 'photo.png',
      bytes: bytesOf([1]),
      mime: 'image/webp',
    );

    expect(unknown.mime, isNull);
    expect(explicit.mime, 'image/webp');
  });

  test('save：空题目 id / 空文件名当场报错', () async {
    expect(
      () => store.save(
        questionId: '   ',
        fileName: 'a.png',
        bytes: bytesOf([1]),
      ),
      throwsArgumentError,
    );
    expect(
      () => store.save(
        questionId: 'q-test',
        fileName: '  ',
        bytes: bytesOf([1]),
      ),
      throwsArgumentError,
    );
  });

  group('角色（v27 attachments.role）', () {
    test('effectiveQuestionImageRole：NULL/空串算题干配图，其它原样', () {
      expect(effectiveQuestionImageRole(null), QuestionImageRole.stem);
      expect(effectiveQuestionImageRole(''), QuestionImageRole.stem);
      expect(effectiveQuestionImageRole('   '), QuestionImageRole.stem);
      expect(effectiveQuestionImageRole('stem'), QuestionImageRole.stem);
      expect(effectiveQuestionImageRole('answer'), QuestionImageRole.answer);
      expect(effectiveQuestionImageRole('solution'), QuestionImageRole.solution);
      // 不认识的也原样留着：读侧不假装它是题干图。
      expect(effectiveQuestionImageRole('weird'), 'weird');
    });

    test('save：缺省写 stem，显式 answer 写 answer', () async {
      final stem = await store.save(
        questionId: 'q-role',
        fileName: 'stem.png',
        bytes: bytesOf([1]),
      );
      final answer = await store.save(
        questionId: 'q-role',
        fileName: 'answer.png',
        bytes: bytesOf([2]),
        role: QuestionImageRole.answer,
      );

      expect(stem.role, QuestionImageRole.stem);
      expect(answer.role, QuestionImageRole.answer);

      final rows = await (db.select(db.attachments)
            ..where((t) => t.ownerId.equals('q-role')))
          .get();
      final byName = {for (final row in rows) p.basename(row.relPath): row};
      expect(byName['stem.png']!.role, QuestionImageRole.stem);
      expect(byName['answer.png']!.role, QuestionImageRole.answer);
    });

    test('list：不传 role 返回全部角色', () async {
      await store.save(
        questionId: 'q-role',
        fileName: 'stem.png',
        bytes: bytesOf([1]),
      );
      await store.save(
        questionId: 'q-role',
        fileName: 'answer.png',
        bytes: bytesOf([2]),
        role: QuestionImageRole.answer,
      );

      final all = await store.list('q-role');
      expect(all.map((image) => image.fileName), ['stem.png', 'answer.png']);
      expect(all.map((image) => image.role),
          [QuestionImageRole.stem, QuestionImageRole.answer]);
    });

    test('list：stem 含 NULL 旧行但排掉 answer，answer 只给答案截图', () async {
      // v27 之前写下的行：role 是 NULL。
      await db.into(db.attachments).insert(
            AttachmentsCompanion.insert(
              id: 'att-legacy',
              ownerType: QuestionMediaStore.ownerType,
              ownerId: 'q-role',
              relPath: 'question_images/q-role/att-legacy/legacy.png',
              createdAt: 1,
            ),
          );
      await store.save(
        questionId: 'q-role',
        fileName: 'new-stem.png',
        bytes: bytesOf([1]),
      );
      await store.save(
        questionId: 'q-role',
        fileName: 'answer.png',
        bytes: bytesOf([2]),
        role: QuestionImageRole.answer,
      );

      final stems = await store.list('q-role', role: QuestionImageRole.stem);
      // 排序是 sortOrder 优先：旧行缺省 0，新题干图接在它后面（1）。
      expect(stems.map((image) => image.fileName),
          ['legacy.png', 'new-stem.png']);
      expect(stems.map((image) => image.role),
          [QuestionImageRole.stem, QuestionImageRole.stem],
          reason: 'NULL 旧行读出来折成 stem，但库里仍是 NULL');
      // 写入时按角色分别排号：旧行的 NULL 算 stem，所以新 stem 图接在 1。
      expect(stems.last.sortOrder, 1);

      final answers = await store.list('q-role', role: QuestionImageRole.answer);
      expect(answers.map((image) => image.fileName), ['answer.png']);

      final rawRows = await (db.select(db.attachments)
            ..where((t) => t.id.equals('att-legacy')))
          .getSingle();
      expect(rawRows.role, isNull, reason: '迁移不回填，NULL 是兼容语义');
    });

    test('sortOrder：题干配图与答案截图各自从 0 起排序', () async {
      final stem0 = await store.save(
        questionId: 'q-role',
        fileName: 's0.png',
        bytes: bytesOf([1]),
      );
      final answer0 = await store.save(
        questionId: 'q-role',
        fileName: 'a0.png',
        bytes: bytesOf([2]),
        role: QuestionImageRole.answer,
      );
      final stem1 = await store.save(
        questionId: 'q-role',
        fileName: 's1.png',
        bytes: bytesOf([3]),
      );
      final answer1 = await store.save(
        questionId: 'q-role',
        fileName: 'a1.png',
        bytes: bytesOf([4]),
        role: QuestionImageRole.answer,
      );

      expect([stem0.sortOrder, stem1.sortOrder], [0, 1]);
      expect([answer0.sortOrder, answer1.sortOrder], [0, 1]);
    });

    test('deleteForQuestion：两个角色的图一起删', () async {
      await store.save(
        questionId: 'q-role',
        fileName: 'stem.png',
        bytes: bytesOf([1]),
      );
      final answer = await store.save(
        questionId: 'q-role',
        fileName: 'answer.png',
        bytes: bytesOf([2]),
        role: QuestionImageRole.answer,
      );

      final removed = await store.deleteForQuestion('q-role');

      expect(removed, 2);
      expect(File(answer.absolutePath).existsSync(), isFalse);
      expect(await attachmentCount('q-role'), 0);
    });

    test('save：不认识的角色值原样落库，不静默改写成 stem', () async {
      final odd = await store.save(
        questionId: 'q-role',
        fileName: 'odd.png',
        bytes: bytesOf([1]),
        role: 'scan_extra',
      );
      expect(odd.role, 'scan_extra');
      expect(await store.list('q-role', role: QuestionImageRole.stem), isEmpty);
      final all = await store.list('q-role');
      expect(all.single.role, 'scan_extra');
    });
  });
}
