import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/presentation/drop_intake_filter.dart';
import 'package:path/path.dart' as p;

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// 微信/相机常见的真实签名（只取前 12 字节，够 classify 用）。
final Uint8List pngHead = bytes(
  const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D],
);
final Uint8List jpegHead = bytes(
  const <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1],
);
final Uint8List gifHead = bytes(
  const <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0, 0, 0],
);
final Uint8List webpHead = bytes(
  const <int>[0x52, 0x49, 0x46, 0x46, 0x24, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
);
final Uint8List bmpHead = bytes(
  const <int>[0x42, 0x4D, 0x36, 0, 0, 0, 0, 0, 0, 0, 0, 0],
);
final Uint8List heicHead = bytes(
  const <int>[0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63],
);

DropIntakeCandidate candidate(
  String path, {
  Uint8List? head,
  Object? readError,
  bool isDirectory = false,
}) {
  return DropIntakeCandidate(
    path: path,
    fileName: dropIntakeFileName(path),
    head: head,
    readError: readError,
    isDirectory: isDirectory,
  );
}

void main() {
  group('扩展名识别（第一道保险）', () {
    const expectations = <String, String>{
      'a.png': 'image/png',
      'a.PNG': 'image/png',
      'b.jpg': 'image/jpeg',
      'b.jpeg': 'image/jpeg',
      'b.JPEG': 'image/jpeg',
      'c.gif': 'image/gif',
      'd.webp': 'image/webp',
      'e.heic': 'image/heic',
      'f.bmp': 'image/bmp',
    };
    for (final entry in expectations.entries) {
      test('${entry.key} → ${entry.value}', () {
        expect(dropIntakeMimeForName(entry.key), entry.value);
      });
    }

    test('中文 / 空格文件名照样认扩展名', () {
      expect(dropIntakeMimeForName('微信图片 2026-10-18.png'), 'image/png');
      expect(dropIntakeMimeForName('照片 1.JPG'), 'image/jpeg');
    });

    test('非图片扩展名 / 没有扩展名 → null', () {
      expect(dropIntakeMimeForName('notes.txt'), isNull);
      expect(dropIntakeMimeForName('question.pdf'), isNull);
      expect(dropIntakeMimeForName('no_extension'), isNull);
      expect(dropIntakeMimeForName('archive.zip'), isNull);
    });

    test('文件名从完整路径取（Windows 临时目录风格）', () {
      final path = p.join(
          'C:', 'Users', '微信', 'AppData', 'Local', 'Temp', 'wx_照片 1.png');
      expect(dropIntakeFileName(path), 'wx_照片 1.png');
    });
  });

  group('魔数识别（第二道保险）', () {
    test('PNG', () => expect(dropIntakeSniffMime(pngHead), 'image/png'));
    test('JPEG', () => expect(dropIntakeSniffMime(jpegHead), 'image/jpeg'));
    test('GIF', () => expect(dropIntakeSniffMime(gifHead), 'image/gif'));
    test('WebP', () => expect(dropIntakeSniffMime(webpHead), 'image/webp'));
    test('BMP', () => expect(dropIntakeSniffMime(bmpHead), 'image/bmp'));
    test('HEIC', () => expect(dropIntakeSniffMime(heicHead), 'image/heic'));

    test('字节不够长不会越界', () {
      expect(dropIntakeSniffMime(bytes(const <int>[0x89])), isNull);
      expect(dropIntakeSniffMime(Uint8List(0)), isNull);
      expect(dropIntakeSniffMime(bytes(const <int>[0xFF, 0xD8])), isNull);
    });

    test('不是图片的文件头 → null', () {
      expect(dropIntakeSniffMime(bytes('%PDF-1.7'.codeUnits)), isNull);
      expect(dropIntakeSniffMime(bytes('hello world'.codeUnits)), isNull);
    });
  });

  group('单文件分类', () {
    test('扩展名是图片：直接收，MIME 按扩展名', () {
      final decision = classifyDropIntakeCandidate(candidate('照片 1.png'));
      expect(decision.status, DropIntakeStatus.image);
      expect(decision.mime, 'image/png');
      expect(decision.extension, 'png');
    });

    test('扩展名不认识但魔数是 PNG：靠魔数救回来', () {
      final decision = classifyDropIntakeCandidate(
        candidate('wx_tmp_001', head: pngHead),
      );
      expect(decision.status, DropIntakeStatus.image);
      expect(decision.mime, 'image/png');
    });

    test('扩展名不认识、魔数也不认识：非图片', () {
      final decision = classifyDropIntakeCandidate(
        candidate('readme.txt', head: bytes('hello'.codeUnits)),
      );
      expect(decision.status, DropIntakeStatus.nonImage);
      expect(decision.mime, isNull);
    });

    test('读失败的文件：unreadable，带原因', () {
      final decision = classifyDropIntakeCandidate(
        candidate('missing.png', readError: StateError('permission denied')),
      );
      expect(decision.status, DropIntakeStatus.unreadable);
      expect(decision.errorReason, contains('permission denied'));
    });

    test('空文件：unreadable（就算扩展名是 png）', () {
      final decision = classifyDropIntakeCandidate(
        candidate('empty.png', head: Uint8List(0)),
      );
      expect(decision.status, DropIntakeStatus.unreadable);
      expect(decision.errorReason, 'empty file');
    });

    test('文件夹：directory，不当图片收', () {
      final decision = classifyDropIntakeCandidate(
        candidate('照片目录', isDirectory: true),
      );
      expect(decision.status, DropIntakeStatus.directory);
    });

    test('没有扩展名时 extension 为 null', () {
      final decision = classifyDropIntakeCandidate(candidate('no_extension'));
      expect(decision.extension, isNull);
    });
  });

  group('同批去重与计数聚合', () {
    test('同一个路径只收一次，顺序按拖入顺序', () {
      final plan = planDropIntake(<DropIntakeCandidate>[
        candidate('a.png'),
        candidate('b.jpg'),
        candidate('a.png'),
      ]);
      expect(plan.images.map((d) => d.fileName), <String>['a.png', 'b.jpg']);
      expect(plan.duplicateCount, 1);
      expect(plan.consideredCount, 3);
    });

    test('图片 / 非图片 / 读不出来 / 文件夹分别计数', () {
      final plan = planDropIntake(<DropIntakeCandidate>[
        candidate('a.png'),
        candidate('b.png'),
        candidate('notes.txt'),
        candidate('broken.png', readError: StateError('boom')),
        candidate('照片目录', isDirectory: true),
      ]);
      expect(plan.images.length, 2);
      expect(plan.nonImageCount, 1);
      expect(plan.unreadable.length, 1);
      expect(plan.directoryCount, 1);
      expect(plan.duplicateCount, 0);
      expect(plan.consideredCount, 5);
      expect(plan.firstError, contains('boom'));
    });

    test('没有读失败时 firstError 为 null', () {
      final plan = planDropIntake(<DropIntakeCandidate>[candidate('a.png')]);
      expect(plan.firstError, isNull);
    });

    test('ignorePathCase 把大小写不同的同一路径算重复', () {
      final paths = <String>[p.join('Temp', 'A.PNG'), p.join('temp', 'a.png')];
      final strict = planDropIntake(<DropIntakeCandidate>[
        candidate(paths[0]),
        candidate(paths[1]),
      ]);
      expect(strict.images.length, 2);
      expect(strict.duplicateCount, 0);

      final lenient = planDropIntake(
        <DropIntakeCandidate>[candidate(paths[0]), candidate(paths[1])],
        ignorePathCase: true,
      );
      expect(lenient.images.length, 1);
      expect(lenient.duplicateCount, 1);
    });

    test('空拖拽：什么都不收', () {
      final plan = planDropIntake(const <DropIntakeCandidate>[]);
      expect(plan.consideredCount, 0);
      expect(plan.images, isEmpty);
    });
  });
}
