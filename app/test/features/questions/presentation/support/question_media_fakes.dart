/// 题目配图的测试替身：只读内存里的图，不碰真实磁盘、不读 app support 目录。
///
/// `questionImagesProvider` / `questionImageBytesProvider` 都走
/// `questionMediaStoreProvider`；测试里 override 成这个替身，就能验证「题号 +
/// 缩略图 / 大图」的渲染，而不用装 path_provider 的测试桩。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:furnace/features/questions/data/question_media_store.dart';

/// 2×2 的合法 PNG（纯红色）：足够让 `Image.memory` 真的解码，而不是拿垃圾字节
/// 糊弄（`errorBuilder` 那条通路另有专门用例）。
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
);

/// 只读的 `QuestionMediaStore`：`list` / `readBytes` 返回种子数据，写操作直接报错。
///
/// 页面在三处只读地用到配图（清单缩略图、详情缩略图、大图对话框），所以这个替身
/// **只实现读**；将来界面真的加了「加图/删图」，这里的写方法会立刻炸出来提醒补替身。
class FakeQuestionMediaStore extends QuestionMediaStore {
  FakeQuestionMediaStore({required super.database});

  final Map<String, List<QuestionImage>> _images =
      <String, List<QuestionImage>>{};
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, int> _sequence = <String, int>{};

  /// 给 [questionId] 种一张图，返回写进 store 的 `QuestionImage`。
  QuestionImage seed({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
  }) {
    final images = _images.putIfAbsent(questionId, () => <QuestionImage>[]);
    final index = _sequence.update(
      questionId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final attachmentId = 'att-$questionId-$index';
    final relPath =
        '${QuestionMediaStore.directoryName}/$questionId/$attachmentId/$fileName';
    final image = QuestionImage(
      attachmentId: attachmentId,
      relPath: relPath,
      absolutePath: '/fake/$relPath',
      fileName: fileName,
      sortOrder: images.length,
      mime: mime,
      createdAt: DateTime(2026, 10, 18),
    );
    images.add(image);
    _bytes[relPath] = bytes;
    return image;
  }

  /// 模拟「attachments 行还在，但磁盘上的图丢了」。
  void removeBytes(QuestionImage image) {
    _bytes.remove(image.relPath);
  }

  @override
  Future<List<QuestionImage>> list(String questionId) async =>
      List<QuestionImage>.unmodifiable(
        _images[questionId] ?? const <QuestionImage>[],
      );

  @override
  Future<Uint8List?> readBytes(String relPath) async => _bytes[relPath];

  @override
  Future<QuestionImage> save({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
    int? sortOrder,
    DateTime? now,
  }) =>
      throw UnsupportedError('测试替身是只读的：界面不该在测试里写图');

  @override
  Future<void> delete(QuestionImage image) =>
      throw UnsupportedError('测试替身是只读的：界面不该在测试里删图');

  @override
  Future<int> deleteForQuestion(String questionId) =>
      throw UnsupportedError('测试替身是只读的：界面不该在测试里删图');
}
