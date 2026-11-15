import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/presentation/review_card_media.dart';
import 'package:path/path.dart' as p;

/// 2×2 合法 PNG（纯红色）。
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
);

/// 卡面图片字节的读侧：只读本地文件，绝不联网；读不到就当作没有图。
void main() {
  group('图片路径提取', () {
    test('按出现顺序去重，只认 Markdown 图片语法', () {
      expect(
        reviewCardImagePaths('前 ![一](a.png) 中 ![二](b.png) 后 ![一](a.png)。'),
        <String>['a.png', 'b.png'],
      );
      expect(reviewCardImagePaths('没有图片'), isEmpty);
      expect(reviewCardImagePaths('普通链接 [说明](a.png) 不算图片'), isEmpty);
    });

    test('空路径被丢掉', () {
      expect(reviewCardImagePaths('![](   )'), isEmpty);
    });
  });

  group('字节读取', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('furnace-review-media-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    ProviderContainer containerFor(Directory support) {
      final container = ProviderContainer(
        overrides: [
          reviewCardMediaSupportDirectoryProvider
              .overrideWithValue(() async => support),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<Map<String, dynamic>> read(
      ProviderContainer container,
      String text,
    ) async {
      final provider = reviewCardImageBytesProvider(text);
      final sub = container.listen(provider, (_, __) {});
      addTearDown(sub.close);
      final images = await container.read(provider.future);
      return <String, dynamic>{
        for (final entry in images.entries)
          entry.key: entry.value.bytes,
      };
    }

    test('support 目录下的相对路径能读到字节', () async {
      await File(p.join(root.path, 'a.png')).writeAsBytes(tinyPngBytes);
      final images = await read(containerFor(root), '如图 ![示意](a.png) 所示。');
      expect(images.keys, <String>['a.png']);
      expect(images['a.png'], tinyPngBytes);
    });

    test('带 question_images 相对目录的路径按 support 目录解析', () async {
      final nested = Directory(p.join(root.path, 'question_images', 'q-1'));
      await nested.create(recursive: true);
      await File(p.join(nested.path, 'a.png')).writeAsBytes(tinyPngBytes);
      final images = await read(
        containerFor(root),
        '![题干图](question_images/q-1/a.png)',
      );
      expect(images.keys, <String>['question_images/q-1/a.png']);
    });

    test('绝对路径直接读', () async {
      final file = File(p.join(root.path, 'abs.png'));
      await file.writeAsBytes(tinyPngBytes);
      final images = await read(containerFor(root), '![图](${file.path})');
      expect(images.keys, <String>[file.path]);
    });

    test('文件不存在、空文件都降级为空（不抛）', () async {
      await File(p.join(root.path, 'empty.png')).writeAsBytes(<int>[]);
      final images = await read(
        containerFor(root),
        '![不在](missing.png) ![空](empty.png)',
      );
      expect(images, isEmpty);
    });

    test('http(s) 外链不读、不联网，返回空表', () async {
      final container = containerFor(root);
      // 不 override support 也不影响：外链在解析阶段就被拒绝。
      final images = await read(
        container,
        '![网络图](https://example.com/a.png)',
      );
      expect(images, isEmpty);
    });

    test('support 目录解析失败时相对路径降级为空，绝对路径仍然工作', () async {
      final file = File(p.join(root.path, 'abs-ok.png'));
      await file.writeAsBytes(tinyPngBytes);
      final container = ProviderContainer(
        overrides: [
          reviewCardMediaSupportDirectoryProvider.overrideWithValue(
            () async {
              throw const FileSystemException('no support dir');
            },
          ),
        ],
      );
      addTearDown(container.dispose);
      final images = await read(
        container,
        '![相对](a.png) ![绝对](${file.path})',
      );
      expect(images.keys, <String>[file.path]);
    });
  });
}
