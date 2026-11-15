/// Markdown 统一渲染的依赖注入点。
///
///  * [markdownThemeStoreProvider] —— 主题读写（文件 / 测试内存替身）；
///  * [markdownRenderThemeProvider] —— 当前生效的全局 Markdown 主题；
///  * [markdownPdfFontResolverProvider] —— PDF 中文 TTF 来源；
///  * [markdownPdfExporterProvider] —— PDF 生成器（吃上面的字体解析器）。
///
/// 页面只读这些 provider，所以 widget test 可以用内存存储和假字体，不碰真
/// 文件系统、也不加载 10 MB 的内置字体。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/markdown_pdf_exporter.dart';
import '../domain/markdown_pdf_fonts.dart';
import '../domain/markdown_render_theme.dart';
import 'markdown_theme_store.dart';

/// 主题存储（默认落到应用支持目录的 JSON 文件）。
final markdownThemeStoreProvider = Provider<MarkdownThemeStore>(
  (ref) => FileMarkdownThemeStore(),
);

/// 当前生效的 Markdown 主题。
///
/// 构造时先用内置预设（同步可用），随后异步读盘覆盖；用户每次修改都会先更新
/// 内存状态、再延迟 300ms 落盘，避免拖滑块时每个像素写一次文件。
final markdownRenderThemeProvider =
    StateNotifierProvider<MarkdownThemeController, MarkdownRenderTheme>(
  (ref) => MarkdownThemeController(ref.watch(markdownThemeStoreProvider)),
);

/// 全局 Markdown 主题的控制器。
class MarkdownThemeController extends StateNotifier<MarkdownRenderTheme> {
  MarkdownThemeController(this._store) : super(MarkdownRenderTheme.fallback) {
    unawaited(_load());
  }

  final MarkdownThemeStore _store;

  Timer? _saveTimer;

  /// 用户是否改过主题（用于测试/诊断"是否真的写过"）。
  bool get hasPendingSave => _saveTimer?.isActive ?? false;

  Future<void> _load() async {
    final stored = await _store.load();
    if (!mounted || stored == null) {
      return;
    }
    state = stored;
  }

  /// 应用一份完整主题（设置页的每次改动都走这里）。
  void apply(MarkdownRenderTheme theme) {
    state = theme;
    _scheduleSave();
  }

  /// 切到某个内置预设。
  void selectPreset(String id) => apply(MarkdownRenderTheme.byId(id));

  /// 把当前主题恢复成同名预设的默认值（保留 id/名称，丢弃自定义）。
  void resetToPreset() => apply(MarkdownRenderTheme.byId(state.id));

  /// 立即把待写主题落盘（页面 dispose / widget test 用）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _store.save(state);
    } on Object catch (error) {
      debugPrint('[MarkdownTheme] save failed: $error');
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }
}

/// PDF 中文字体解析（默认用打包进资产的 Noto Sans SC TTF）。
final markdownPdfFontResolverProvider = Provider<MarkdownPdfFontResolver>(
  (ref) => BundledMarkdownPdfFontResolver(),
);

/// PDF 生成器。
final markdownPdfExporterProvider = Provider<MarkdownPdfExporter>(
  (ref) => MarkdownPdfExporter(
    fontResolver: ref.watch(markdownPdfFontResolverProvider),
  ),
);
