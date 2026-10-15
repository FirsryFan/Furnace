/// `HandwritingIntakeStore` 的测试：拍照/选图那条通路要落下的两样东西——磁盘上的
/// 文件，和指向它的 `attachments` 行——必须同生同死。
///
/// 这一页的验收（`docs/QUESTION_BANK_DESIGN.md` §7 步骤 1）不是"按钮点了有反应"，
/// 而是：原图复制进 app support 下的 `handwriting_intake/`、`owner_type` 认得出来、
/// 清单里能读回字节、以及删掉时文件不会变成孤儿。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/data/handwriting_intake_store.dart';

import '../support/picked_file_fakes.dart';

void main() {
  late AppDatabase db;
  late Directory support;
  late HandwritingIntakeStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    support = Directory.systemTemp.createTempSync('furnace_hw_intake_');
    store = HandwritingIntakeStore(
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

  /// 最近一次造出来的"用户选中的文件"。磁盘上真有一个文件（用来断言复制不是
  /// 移动），但交给 store 的是内存字节的 `PlatformFile`。
  File? lastSource;

  /// 一张"用户选中的原图"，放在另一个临时目录里（和 app support 目录分开，才能
  /// 断言是复制不是移动）。
  Future<FakePickedFile> sourceFile(String name, List<int> bytes) async {
    final directory = Directory.systemTemp.createTempSync('furnace_hw_src_');
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    lastSource = file;
    return FakePickedFile(name, file.readAsBytesSync());
  }

  Future<List<PendingHandwritingImage>> pendingRows() => store.pending();

  test('save：复制进 handwriting_intake/，原图留着，attachments 记一行', () async {
    final source = await sourceFile('notes.png', <int>[1, 2, 3, 4]);

    final image = await store.save(source);

    // 相对路径入库，绝对路径只活在内存里。
    expect(image.relPath, startsWith('${HandwritingIntakeStore.directoryName}/'));
    expect(image.relPath, endsWith('notes.png'));
    // 显示名就是原文件名，不带内部 id 前缀（用户起的名字才认得出来）。
    expect(image.fileName, 'notes.png');
    expect(image.extension, 'png');
    expect(image.mime, 'image/png');

    final copy = File(image.absolutePath);
    expect(copy.existsSync(), isTrue);
    expect(copy.path, startsWith(support.path));
    expect(await copy.readAsBytes(), equals(<int>[1, 2, 3, 4]));

    // 复制，不是移动：原图还在原地。
    expect(lastSource, isNotNull);
    expect(lastSource!.existsSync(), isTrue);
    expect(lastSource!.path, isNot(startsWith(support.path)));

    final rows = await db.select(db.attachments).get();
    expect(rows, hasLength(1));
    expect(rows.single.ownerType, HandwritingIntakeStore.ownerType);
    expect(rows.single.relPath, image.relPath);
    expect(rows.single.mime, 'image/png');
  });

  test('pending：新收的在前，只剩自己的 owner_type，绝对路径能读回字节', () async {
    // 别人的附件（别的功能写进同一张表的行）不能混进这一页的清单。
    await db.into(db.attachments).insert(AttachmentsCompanion.insert(
          id: 'att-other',
          ownerType: 'ai_chat',
          ownerId: 'msg-1',
          relPath: 'ai_chat/other.png',
          createdAt: 0,
        ));

    await store.save(await sourceFile('a.png', <int>[7]));
    // createdAt 是毫秒，隔开一点才能断言"新收的在前"而不是撞上同一毫秒。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.save(await sourceFile('b.png', <int>[9, 9]));

    final images = await pendingRows();
    expect(images, hasLength(2));
    expect(images.first.fileName, 'b.png');
    expect(images.last.fileName, 'a.png');
    expect(images.first.createdAt, isNotNull);

    expect(await store.readBytes(images.first.relPath), equals(<int>[9, 9]));
    expect(await store.readBytes(images.last.relPath), equals(<int>[7]));
    // 绝对路径指到 support 目录里的真实文件。
    expect(File(images.first.absolutePath).existsSync(), isTrue);
  });

  test('readBytes：文件被外面删了就返回 null，行还留着', () async {
    final image = await store.save(await sourceFile('gone.png', <int>[1]));
    File(image.absolutePath).deleteSync();

    expect(await store.readBytes(image.relPath), isNull);
    // 少一张图不该让整个待整理清单消失。
    expect(await pendingRows(), hasLength(1));
  });

  test('delete：行和文件一起消失，空目录也收掉', () async {
    final image = await store.save(await sourceFile('del.png', <int>[1]));
    final copy = File(image.absolutePath);
    final parent = copy.parent;

    await store.delete(image);

    expect(copy.existsSync(), isFalse);
    expect(parent.existsSync(), isFalse);
    expect(await pendingRows(), isEmpty);
    expect(await db.select(db.attachments).get(), isEmpty);
  });

  test('mime：按扩展名认，认不出来就是 null', () async {
    expect((await store.save(await sourceFile('p.JPG', <int>[1]))).mime,
        'image/jpeg');
    expect((await store.save(await sourceFile('p.heic', <int>[1]))).mime,
        'image/heic');
    expect((await store.save(await sourceFile('p.xyz', <int>[1]))).mime, isNull);
    expect((await store.save(await sourceFile('noext', <int>[1]))).mime, isNull);
  });

  test('save：同名文件各有各的目录，不会互相覆盖', () async {
    final first = await store.save(await sourceFile('same.png', <int>[1, 1]));
    final second = await store.save(await sourceFile('same.png', <int>[2, 2]));

    expect(first.relPath, isNot(second.relPath));
    expect(await store.readBytes(first.relPath), equals(<int>[1, 1]));
    expect(await store.readBytes(second.relPath), equals(<int>[2, 2]));
  });

  test('Uint8List 尺寸不变：原图字节原样复制，不做重编码', () async {
    // 手写照片走的是 OCR，压缩会毁掉笔迹；这条测试盯着"复制"这个承诺。
    final bytes = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));
    final image = await store.save(await sourceFile('big.png', bytes));

    expect(await store.readBytes(image.relPath), equals(bytes));
  });
}
