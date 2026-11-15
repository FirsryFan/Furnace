/// Markdown 主题的落盘实现：应用支持目录下的 `markdown/theme.json`。
///
/// 为什么用文件而不是数据库：
///
///  * 任务约束不新增 DB schema；主题只是一份 UI 偏好，换文件不影响数据迁移；
///  * 主题是整份 JSON 覆盖写，失败模式简单（文件不存在/损坏 → 用内置预设），
///    不会阻塞任何页面；
///  * 测试可以换成内存实现，widget test 不需要真的写盘。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../data/storage/app_storage.dart';
import '../domain/markdown_render_theme.dart';

/// 主题读写接口。
abstract class MarkdownThemeStore {
  Future<MarkdownRenderTheme?> load();

  Future<void> save(MarkdownRenderTheme theme);
}

/// 文件实现：`<support>/markdown/theme.json`。
class FileMarkdownThemeStore implements MarkdownThemeStore {
  FileMarkdownThemeStore({
    Future<Directory> Function()? supportDirectory,
    this.folderName = 'markdown',
    this.fileName = 'theme.json',
  }) : _supportDirectory = supportDirectory ?? AppStorage.supportDirectory;

  final Future<Directory> Function() _supportDirectory;
  final String folderName;
  final String fileName;

  Future<File> _file() async {
    final support = await _supportDirectory();
    final folder = Directory(p.join(support.path, folderName));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File(p.join(folder.path, fileName));
  }

  @override
  Future<MarkdownRenderTheme?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return MarkdownRenderTheme.fromJson(decoded);
    } on FormatException catch (error) {
      debugPrint('[MarkdownTheme] unreadable: $error');
      return null;
    } on FileSystemException catch (error) {
      debugPrint('[MarkdownTheme] read failed: $error');
      return null;
    } on Object catch (error) {
      // 测试环境没有 path_provider 插件时也走这里：当作没有主题文件。
      debugPrint('[MarkdownTheme] unavailable: $error');
      return null;
    }
  }

  @override
  Future<void> save(MarkdownRenderTheme theme) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(theme.toJson()),
      flush: true,
    );
  }
}
