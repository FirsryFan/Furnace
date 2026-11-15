/// Markdown 统一渲染测试替身：内存主题存储 + 可控的 PDF 中文字体来源。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:furnace/features/markdown/application/markdown_theme_store.dart';
import 'package:furnace/features/markdown/domain/markdown_pdf_fonts.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';

/// 内存主题存储：记录每次 save()，load() 返回当前值。
final class MemoryMarkdownThemeStore implements MarkdownThemeStore {
  MemoryMarkdownThemeStore([this.theme]);

  MarkdownRenderTheme? theme;

  /// 每次 save 的副本；last 即最后一次写入。
  final List<MarkdownRenderTheme> saves = <MarkdownRenderTheme>[];

  @override
  Future<MarkdownRenderTheme?> load() async => theme;

  @override
  Future<void> save(MarkdownRenderTheme theme) async {
    this.theme = theme;
    saves.add(theme);
  }
}

/// 字体解析替身：[data] 为 null 时抛"缺字体"，用来测降级路径。
final class FakeMarkdownPdfFontResolver implements MarkdownPdfFontResolver {
  FakeMarkdownPdfFontResolver({this.data});

  MarkdownPdfFontData? data;
  int calls = 0;

  @override
  Future<MarkdownPdfFontData> resolve() async {
    calls++;
    final resolved = data;
    if (resolved == null) {
      throw MarkdownPdfFontUnavailableException(<String>[
        '${BundledMarkdownPdfFontResolver.fontAssetPath}'
            '（内置字体资产不可读：测试替身）',
      ]);
    }
    return resolved;
  }
}

/// 打包进应用的字体资产在测试进程工作目录（package root）下的路径。
String get bundledFontAssetFile =>
    BundledMarkdownPdfFontResolver.fontAssetPath;

/// 内置字体资产是否在磁盘上（`flutter test` 的工作目录就是 package root）。
bool hasBundledChineseFont() => File(bundledFontAssetFile).existsSync();

/// 通过应用资产加载内置中文字体（`rootBundle`，与运行时同一条路径）。
Future<MarkdownPdfFontData?> loadBundledChineseFont() async {
  if (!hasBundledChineseFont()) {
    return null;
  }
  return BundledMarkdownPdfFontResolver().resolve();
}

/// 造一份带首 4 字节 TrueType 标记的假数据（只给解析器单测用）。
Uint8List fakeTrueTypeBytes() => Uint8List.fromList(<int>[
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

/// 假资产加载器：记下被请求的路径，返回给定字节（null = 资产不存在）。
Future<ByteData> Function(String path) fakeAssetLoader(
  Uint8List? bytes, {
  List<String>? requests,
}) {
  return (String path) async {
    requests?.add(path);
    if (bytes == null) {
      throw FlutterError('Unable to load asset: "$path"');
    }
    return ByteData.sublistView(bytes);
  };
}
