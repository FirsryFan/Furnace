/// 闪存卡卡面图片的字节来源：卡片文本里的 Markdown 图片路径 → 本地磁盘字节。
///
/// 为什么需要这一层：`ReviewQuestionText` 只做渲染、不碰 IO（它的文档是硬口径），
/// 所以「图片路径 → 字节」必须在页面组合层做。这里只读本地文件，**绝不联网**：
///
///  * 认 `![说明](路径)` 里的路径。`http(s)://` / `data:` 一律不读（离线题干不能
///    因为一张图触发网络请求）；读不到、空文件、读失败都当作「这张图不存在」，
///    渲染器保留字面文本，页面不崩。
///  * 绝对路径按原样读；相对路径按 app support 目录解析
///    （题库图片的 `relPath` 就是相对 support 目录的，例如
///    `question_images/<questionId>/<attachmentId>/<文件名>`）。
///
/// 数据来源的事实（2026-11-15 只读查过真实库 `E:\Furnace\data\furnace.db`）：
/// `ReviewItem` 本身没有图片字段；`attachments` 表的 owner 只有 `question` /
/// `ai_message` / `handwriting_intake`，没有挂在知识点或卡模板上的行，所以闪存卡
/// 目前没有「附件字节」可读，只有卡面文本自己带的本地图片路径这条来源。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../data/storage/app_storage.dart';
import 'review_question_text.dart';

/// app support 目录解析器。
///
/// 单独成一个 provider 才能让测试把它指到临时目录，不去碰真实的 app 数据目录
/// （与 `questionMediaSupportDirectoryProvider` 同一个口径）。
final reviewCardMediaSupportDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return AppStorage.supportDirectory;
});

/// 卡面文本里的 Markdown 图片路径（按出现顺序、去重；不含空路径）。
List<String> reviewCardImagePaths(String text) {
  if (!text.contains('![')) {
    return const <String>[];
  }
  final seen = <String>{};
  final paths = <String>[];
  for (final match in _markdownImage.allMatches(text)) {
    final path = match.group(1)!.trim();
    if (path.isEmpty || !seen.add(path)) {
      continue;
    }
    paths.add(path);
  }
  return paths;
}

final RegExp _markdownImage = RegExp(r'!\[[^\]\n]*\]\(([^)\n]+)\)');

/// 卡面文本里能读到的图片字节：`图片路径 → 已读好的图`。
///
/// 没有图片路径时同步返回空表（不读盘、不解析 support 目录），所以普通纯文本卡
/// 不会因为这条管线多付任何 IO。
final reviewCardImageBytesProvider = FutureProvider.autoDispose
    .family<Map<String, ReviewQuestionImage>, String>((ref, text) async {
  final paths = reviewCardImagePaths(text);
  if (paths.isEmpty) {
    return const <String, ReviewQuestionImage>{};
  }
  final support = ref.watch(reviewCardMediaSupportDirectoryProvider);
  Directory? root;
  Future<Directory?> supportOrNull() async {
    if (root != null) {
      return root;
    }
    try {
      root = await support();
      return root;
    } on Object {
      return null;
    }
  }

  final images = <String, ReviewQuestionImage>{};
  for (final raw in paths) {
    final file = await _resolveImageFile(raw, supportOrNull);
    if (file == null) {
      continue;
    }
    try {
      if (!await file.exists() || await file.length() <= 0) {
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        continue;
      }
      images[raw] = ReviewQuestionImage(
        bytes: bytes,
        semanticLabel: p.basename(file.path),
      );
    } on Object {
      // 单张图读失败只丢这一张：同段的文字和其它图照常渲染。
      continue;
    }
  }
  return Map<String, ReviewQuestionImage>.unmodifiable(images);
});

/// 把卡面里的图片路径解析成一个候选文件；不认识的协议返回 null（不联网）。
Future<File?> _resolveImageFile(
  String raw,
  Future<Directory?> Function() supportOrNull,
) async {
  final path = raw.trim();
  if (path.isEmpty) return null;
  final lower = path.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('data:') ||
      lower.startsWith('//')) {
    // 外链与内联数据不是本地图：不联网、不解码。
    return null;
  }
  if (lower.startsWith('file://')) {
    final uri = Uri.tryParse(path);
    if (uri == null || uri.scheme != 'file' || uri.path.isEmpty) {
      return null;
    }
    return File(uri.toFilePath());
  }
  if (p.isAbsolute(path)) {
    return File(path);
  }
  final root = await supportOrNull();
  if (root == null) {
    return null;
  }
  final segments = path.replaceAll('\\', '/').split('/');
  return File(p.joinAll(<String>[root.path, ...segments]));
}
