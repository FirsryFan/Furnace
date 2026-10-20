/// 题目配图的测试替身：内存里的图，不碰真实磁盘、不读 app support 目录。
///
/// `questionImagesProvider` / `questionAnswerImagesProvider` /
/// `questionImageBytesProvider` 都走 `questionMediaStoreProvider`；测试里 override
/// 成这个替身，就能验证「题号 + 缩略图 / 大图 / 加图 / 删图」的渲染，而不用装
/// path_provider 的测试桩。
///
/// 角色（stem / answer）与真 store 同语义：`list` 不带 role 返回全部，带上则只返回
/// 该角色；旧行没有 role 时按 stem 读（[effectiveQuestionImageRole]）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:furnace/features/questions/data/question_media_store.dart';

/// 2×2 的合法 PNG（纯红色）：足够让 `Image.memory` 真的解码，而不是拿垃圾字节
/// 糊弄（`errorBuilder` 那条通路另有专门用例）。
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
);

/// 内存版 `QuestionMediaStore`：读按角色过滤，写只改内存、不落盘。
///
/// 页面在多处用到配图（清单缩略图、详情缩略图、大图对话框、加图/删图），所以这个
/// 替身同时实现读与写；`save` 不传 role 时与真 store 一样默认写 stem。
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
    String role = QuestionImageRole.stem,
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
      role: role,
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
  Future<List<QuestionImage>> list(String questionId, {String? role}) async {
    final images = _images[questionId] ?? const <QuestionImage>[];
    if (role == null) {
      return List<QuestionImage>.unmodifiable(images);
    }
    final wanted = effectiveQuestionImageRole(role);
    return List<QuestionImage>.unmodifiable(
      images.where(
        (image) => effectiveQuestionImageRole(image.role) == wanted,
      ),
    );
  }

  @override
  Future<Uint8List?> readBytes(String relPath) async => _bytes[relPath];

  /// 写操作也只改内存：详情页的「加图/删图」用得到，但不碰真实磁盘。
  @override
  Future<QuestionImage> save({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
    int? sortOrder,
    String role = QuestionImageRole.stem,
    DateTime? now,
  }) async =>
      seed(
        questionId: questionId,
        fileName: fileName,
        bytes: bytes,
        mime: mime,
        role: role,
      );

  @override
  Future<void> delete(QuestionImage image) async {
    for (final images in _images.values) {
      images.removeWhere((item) => item.attachmentId == image.attachmentId);
    }
    _bytes.remove(image.relPath);
  }

  @override
  Future<int> deleteForQuestion(String questionId) async {
    final images = _images[questionId];
    if (images == null || images.isEmpty) {
      return 0;
    }
    final removed = images.length;
    for (final image in images) {
      _bytes.remove(image.relPath);
    }
    images.clear();
    return removed;
  }
}
