import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/presentation/drop_intake_reader.dart';
import 'package:path/path.dart' as p;

/// 真实临时文件（不是 memory 文件系统）：验证「中文 + 空格 + 临时目录路径」这条
/// 微信聊天记录最常走的路真的能读出来。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('furnace_drop_reader_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  File writeFile(String name, List<int> content) {
    final file = File(p.join(root.path, name));
    file.createSync(recursive: true);
    file.writeAsBytesSync(content, flush: true);
    return file;
  }

  const List<int> pngSignature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
    0,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  test('中文 / 空格文件名：分类成图片并读回完整字节', () async {
    final file = writeFile('微信图片 2026-10-18.png', const <int>[1, 2, 3, 4]);
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(file.path),
    ]);

    expect(batch.plan.images.single.fileName, '微信图片 2026-10-18.png');
    expect(batch.plan.images.single.mime, 'image/png');
    expect(batch.bytes[file.path], Uint8List.fromList(const <int>[1, 2, 3, 4]));
  });

  test('没有扩展名的临时文件：靠文件头魔数救回来', () async {
    final file = writeFile('wx_tmp_9f3c', pngSignature);
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(file.path),
    ]);

    expect(batch.plan.images.single.mime, 'image/png');
    expect(batch.bytes.containsKey(file.path), isTrue);
  });

  test('非图片文件只计数跳过，不影响同批图片', () async {
    final image = writeFile('照片 1.jpg', const <int>[0xFF, 0xD8, 0xFF, 0, 0]);
    final note = writeFile('notes.txt', 'hello'.codeUnits);
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(image.path),
      DropItemFile(note.path),
    ]);

    expect(batch.plan.images.single.fileName, '照片 1.jpg');
    expect(batch.plan.nonImageCount, 1);
    expect(batch.plan.consideredCount, 2);
  });

  test('文件夹（DropItemFile 包着目录）算 directory，不当文件读', () async {
    final folder = Directory(p.join(root.path, '照片目录'))..createSync();
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(folder.path),
    ]);

    expect(batch.plan.directoryCount, 1);
    expect(batch.plan.images, isEmpty);
    expect(batch.plan.unreadable, isEmpty);
  });

  test('DropItemDirectory 也直接算 directory', () async {
    final folder = Directory(p.join(root.path, '拖进来的文件夹'))..createSync();
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemDirectory(folder.path, const <DropItem>[]),
    ]);

    expect(batch.plan.directoryCount, 1);
  });

  test('不存在的路径：unreadable，留下原因', () async {
    final missing = p.join(root.path, '不存在 的照片.png');
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(missing),
    ]);

    expect(batch.plan.unreadable.single.fileName, '不存在 的照片.png');
    expect(batch.plan.firstError, isNotEmpty);
  });

  test('同批重复路径只收一次', () async {
    final file = writeFile('重复.png', const <int>[1]);
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(file.path),
      DropItemFile(file.path),
    ]);

    expect(batch.plan.images.length, 1);
    expect(batch.plan.duplicateCount, 1);
  });

  test('两张图片按拖入顺序排计划', () async {
    final first = writeFile('第一张.png', const <int>[1]);
    final second = writeFile('第二张.png', const <int>[2]);
    final batch = await const DropIntakeReader().examine(<DropItem>[
      DropItemFile(first.path),
      DropItemFile(second.path),
    ]);

    expect(
      batch.plan.images.map((decision) => decision.fileName),
      <String>['第一张.png', '第二张.png'],
    );
  });

  group('DropIntakePlatformFile 适配器', () {
    test('name / path / bytes / 长度 / 流都按传入值', () async {
      final payload = Uint8List.fromList(const <int>[9, 8, 7]);
      final adapter = DropIntakePlatformFile(
        name: '微信 照片.png',
        path: p.join(root.path, '微信 照片.png'),
        bytes: payload,
      );

      expect(adapter.name, '微信 照片.png');
      expect(adapter.path, p.join(root.path, '微信 照片.png'));
      expect(adapter.uri, Uri.file(adapter.path));
      expect(adapter.lengthSync(), 3);
      expect(await adapter.length(), 3);
      expect(await adapter.readAsBytes(), payload);
      expect(await adapter.readAsByteStream().single, payload);
    });

    test('xFile 明确不支持（store.save 不走它）', () {
      final adapter = DropIntakePlatformFile(
        name: 'a.png',
        path: 'a.png',
        bytes: Uint8List(0),
      );
      expect(() => adapter.xFile, throwsUnsupportedError);
    });
  });
}
