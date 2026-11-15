/// 「主题设置 → Markdown」：左侧完整 A4 页面预览，右侧个性化设置。
///
/// 交互要点：
///
///  * 左侧默认是**预览模式**，按 A4 比例渲染当前主题下的默认文档；左下角按钮
///    切到**代码模式**，代码可以编辑，但**不会保存**——离开页面再进来仍是默认
///    文档（[defaultMarkdownDocument]），预览也不会被上次的临时代码污染。
///  * 右侧所有设置即时生效并写入全局 Markdown 主题（`markdown/theme.json`），
///    所以 AI 消息、题目、闪存卡、PDF 一起变化；改的是"主题"，不是某一份文档。
///  * 4 套旧 Typora 式主题（纸张/护眼/深色/紧凑）迁移为预置；预设之外还可以
///    逐项自定义（颜色、字体、字号、行距、标题、表格、代码块、分栏、PDF）。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/markdown_providers.dart';
import '../domain/markdown_columns.dart';
import '../domain/markdown_default_document.dart';
import '../domain/markdown_pdf_exporter.dart';
import '../domain/markdown_pdf_fonts.dart';
import '../domain/markdown_render_theme.dart';
import 'markdown_renderer.dart';

/// 设置页里「主题设置 → Markdown」的入口（测试按 key 找）。
const Key settingsMarkdownTileKey = Key('settings-markdown-tile');

/// Markdown 设置页的控件 key。
class MarkdownSettingsKeys {
  const MarkdownSettingsKeys._();

  static const Key previewPane = Key('markdown-settings-preview-pane');
  static const Key previewPaper = Key('markdown-settings-a4-paper');
  static const Key modeToggle = Key('markdown-settings-mode-toggle');
  static const Key codeEditor = Key('markdown-settings-code-editor');
  static const Key resetDocument = Key('markdown-settings-reset-document');
  static const Key resetTheme = Key('markdown-settings-reset-theme');
  static const Key exportPdf = Key('markdown-settings-export-pdf');
  static const Key fontSizeSlider = Key('markdown-settings-font-size');
  static const Key lineHeightSlider = Key('markdown-settings-line-height');
  static const Key paragraphSpacingSlider =
      Key('markdown-settings-paragraph-spacing');
  static const Key headingCenterSwitch = Key('markdown-settings-heading-center');
  static const Key headingRuleSwitch = Key('markdown-settings-heading-rule');
  static const Key tableStripeSwitch = Key('markdown-settings-table-stripe');
  static const Key tableCompactSwitch = Key('markdown-settings-table-compact');
  static const Key codeLineNumbersSwitch =
      Key('markdown-settings-code-line-numbers');
  static const Key columnsSwitch = Key('markdown-settings-columns');
  static const Key pageNumberSwitch = Key('markdown-settings-page-number');
  static const Key pageMarginSlider = Key('markdown-settings-page-margin');
  static const Key pdfHeaderField = Key('markdown-settings-pdf-header');
  static const Key pdfFooterField = Key('markdown-settings-pdf-footer');
  static const Key chineseFontDropdown = Key('markdown-settings-font-cjk');
  static const Key latinFontDropdown = Key('markdown-settings-font-latin');
  static const String presetChipPrefix = 'markdown-settings-preset-';
}

/// 设置页里的「Markdown 排版」入口行。
///
/// 独立组件：设置页/主题设置重构时直接放 `const MarkdownSettingsTile()` 即可，
/// 不需要知道路由细节；也可以自己 `Navigator.push(MarkdownSettingsPage.route())`。
class MarkdownSettingsTile extends StatelessWidget {
  const MarkdownSettingsTile({super.key});

  /// 页面路由（设置页重构后统一接入用）。
  static Route<void> route() => MaterialPageRoute<void>(
        builder: (context) => const MarkdownSettingsPage(),
      );

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: settingsMarkdownTileKey,
      leading: const Icon(Icons.article_outlined),
      title: const Text('Markdown 排版'),
      subtitle: const Text(
        'A4 预览 / 中英文字体 / 标题 / 表格 / 分栏 / 代码块 / PDF',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(route()),
    );
  }
}

/// 主题设置里的 Markdown 页面。
class MarkdownSettingsPage extends ConsumerStatefulWidget {
  const MarkdownSettingsPage({super.key});

  @override
  ConsumerState<MarkdownSettingsPage> createState() =>
      _MarkdownSettingsPageState();
}

class _MarkdownSettingsPageState extends ConsumerState<MarkdownSettingsPage> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _header = TextEditingController();
  final TextEditingController _footer = TextEditingController();

  /// 在 initState 里拿到 controller：dispose 时不能再 `ref.read`（widget 已
  /// 被标记 disposed），但 controller 本身还可以 flush 最后一笔主题修改。
  late final MarkdownThemeController _themeController;

  MarkdownRenderTheme _theme = MarkdownRenderTheme.fallback;
  String _source = defaultMarkdownDocument;
  bool _codeMode = false;
  bool _pdfBusy = false;

  /// A4 预览页面尺寸（96dpi 逻辑像素）。PDF 同尺寸 ×0.75 即 A4 点。
  static const double _a4Width = 794;
  static const double _a4Height = 1123;

  @override
  void initState() {
    super.initState();
    _themeController = ref.read(markdownRenderThemeProvider.notifier);
    _theme = ref.read(markdownRenderThemeProvider);
    _code.text = _source;
    _header.text = _theme.pdfHeader;
    _footer.text = _theme.pdfFooter;
  }

  @override
  void dispose() {
    // 只保存主题；文档（代码模式里编辑的内容）不落盘。
    unawaited(_themeController.flush());
    _code.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _applyTheme(MarkdownRenderTheme next) {
    setState(() => _theme = next);
    _themeController.apply(next);
  }

  void _selectPreset(MarkdownRenderTheme preset) {
    _header.text = preset.pdfHeader;
    _footer.text = preset.pdfFooter;
    _applyTheme(preset);
  }

  void _toggleMode() {
    setState(() {
      if (_codeMode) {
        // 代码 → 预览：把临时编辑的内容拿去渲染，但不保存。
        _source = _code.text;
      } else {
        // 预览 → 代码：从当前预览内容开始编辑。
        _code.text = _source;
      }
      _codeMode = !_codeMode;
    });
  }

  void _resetDocument() {
    setState(() {
      _source = defaultMarkdownDocument;
      _code.text = _source;
    });
  }

  void _resetTheme() {
    final preset = MarkdownRenderTheme.byId(_theme.id);
    _header.text = preset.pdfHeader;
    _footer.text = preset.pdfFooter;
    _applyTheme(preset);
  }

  Future<void> _exportPdf() async {
    if (_pdfBusy) {
      return;
    }
    setState(() => _pdfBusy = true);
    try {
      final exporter = ref.read(markdownPdfExporterProvider);
      final bytes = await exporter.build(
        markdown: _codeMode ? _code.text : _source,
        theme: _theme,
      );
      final target = await FilePicker.saveFile(
        dialogTitle: '导出 PDF',
        fileName: 'markdown.pdf',
        bytes: bytes,
        type: FileType.any,
      );
      if (target != null && mounted) {
        _showMessage(
          'PDF 已导出（${(bytes.length / 1024).toStringAsFixed(1)} KB）',
        );
      }
    } on MarkdownPdfFontUnavailableException catch (error) {
      _showMessage('PDF 导出不可用：内置中文字体缺失（$error）');
    } on MarkdownPdfExportException catch (error) {
      _showMessage(error.message);
    } on Object catch (error) {
      _showMessage('导出 PDF 失败：$error');
    } finally {
      if (mounted) {
        setState(() => _pdfBusy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Markdown 排版'),
        actions: <Widget>[
          IconButton(
            key: MarkdownSettingsKeys.resetDocument,
            tooltip: '重置默认文档',
            onPressed: _resetDocument,
            icon: const Icon(Icons.restore_page_outlined),
          ),
          IconButton(
            key: MarkdownSettingsKeys.resetTheme,
            tooltip: '恢复该预设默认值',
            onPressed: _resetTheme,
            icon: const Icon(Icons.settings_backup_restore),
          ),
          IconButton(
            key: MarkdownSettingsKeys.exportPdf,
            tooltip: '导出 PDF',
            onPressed: _pdfBusy ? null : _exportPdf,
            icon: _pdfBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final preview = _previewPane(appTheme);
          final settings = _settingsPanel(appTheme);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 6, child: preview),
                const VerticalDivider(width: 1),
                Expanded(flex: 5, child: settings),
              ],
            );
          }
          return ListView(
            children: <Widget>[
              SizedBox(height: 480, child: preview),
              const Divider(height: 1),
              SizedBox(height: 560, child: settings),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 左：A4 预览 / 代码模式 + 左下角切换
  // -------------------------------------------------------------------------

  Widget _previewPane(ThemeData appTheme) {
    return Container(
      key: MarkdownSettingsKeys.previewPane,
      color: appTheme.colorScheme.surfaceContainerHighest,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 56),
              child: _codeMode ? _codeEditor(appTheme) : _a4Paper(appTheme),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: FilledButton.tonalIcon(
              key: MarkdownSettingsKeys.modeToggle,
              onPressed: _toggleMode,
              icon: Icon(_codeMode ? Icons.visibility : Icons.code),
              label: Text(_codeMode ? '预览' : '代码'),
            ),
          ),
          Positioned(
            right: 16,
            top: 8,
            child: Text(
              _codeMode ? '代码模式 · 不保存' : 'A4 预览',
              style: appTheme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _a4Paper(ThemeData appTheme) {
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          key: MarkdownSettingsKeys.previewPaper,
          width: _a4Width,
          height: _a4Height,
          decoration: BoxDecoration(
            color: _theme.background,
            boxShadow: _theme.paperShadow
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          padding: EdgeInsets.all(_theme.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_theme.pdfHeader.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _theme.pdfHeader,
                    style: TextStyle(
                      color: _theme.mutedForeground,
                      fontSize: _theme.fontSize * 0.7,
                    ),
                  ),
                ),
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    child: _paperBody(),
                  ),
                ),
              ),
              if (_theme.pdfFooter.trim().isNotEmpty ||
                  _theme.showPageNumber)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _theme.pdfFooter,
                          style: TextStyle(
                            color: _theme.mutedForeground,
                            fontSize: _theme.fontSize * 0.7,
                          ),
                        ),
                      ),
                      if (_theme.showPageNumber)
                        Text(
                          '第 1 页',
                          style: TextStyle(
                            color: _theme.mutedForeground,
                            fontSize: _theme.fontSize * 0.7,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paperBody() {
    if (!_theme.columnsEnabled) {
      return MarkdownRenderer(
        markdown: _source,
        theme: _theme,
        mode: MarkdownRenderMode.document,
      );
    }
    final chunks = splitMarkdownIntoColumns(_source, _theme.columnCount);
    final children = <Widget>[];
    for (var index = 0; index < chunks.length; index++) {
      if (index > 0) {
        children.add(SizedBox(width: _theme.columnGap / 2));
        if (_theme.columnRule) {
          children.add(Container(width: 1, color: _theme.ruleColor));
        }
        children.add(SizedBox(width: _theme.columnGap / 2));
      }
      children.add(
        Expanded(
          child: MarkdownRenderer(
            markdown: chunks[index],
            theme: _theme,
            mode: MarkdownRenderMode.document,
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _codeEditor(ThemeData appTheme) {
    final mono = TextStyle(
      fontSize: _theme.fontSize,
      height: 1.6,
      fontFamily: 'monospace',
      fontFamilyFallback: MarkdownRenderTheme.monoFontFallback,
      color: appTheme.colorScheme.onSurface,
    );
    return Container(
      color: appTheme.colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: TextField(
        key: MarkdownSettingsKeys.codeEditor,
        controller: _code,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: mono,
        cursorColor: appTheme.colorScheme.primary,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: '在这里编辑 Markdown（改动不会保存）…',
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 右：丰富设置面板
  // -------------------------------------------------------------------------

  Widget _settingsPanel(ThemeData appTheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: <Widget>[
        _presetCard(appTheme),
        _fontCard(appTheme),
        _headingCard(appTheme),
        _tableCard(appTheme),
        _codeCard(appTheme),
        _columnsCard(appTheme),
        _colorCard(appTheme),
        _pdfCard(appTheme),
      ],
    );
  }

  Widget _card(ThemeData appTheme, IconData icon, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: appTheme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: appTheme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _presetCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.palette_outlined,
      '预设',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final preset in MarkdownRenderTheme.all)
            ChoiceChip(
              key: Key('${MarkdownSettingsKeys.presetChipPrefix}${preset.id}'),
              label: Text(preset.name),
              selected: _theme.id == preset.id,
              onSelected: (_) => _selectPreset(preset),
            ),
        ],
      ),
    );
  }

  Widget _fontCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.text_fields,
      '字体与间距',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _fontDropdown(
            appTheme,
            key: MarkdownSettingsKeys.chineseFontDropdown,
            label: '中文字体',
            options: MarkdownRenderTheme.cjkFontOptions,
            value: _theme.cjkFontFamily,
            onChanged: (value) => _applyTheme(
              value == null
                  ? _theme.copyWith(clearCjkFontFamily: true)
                  : _theme.copyWith(cjkFontFamily: value),
            ),
          ),
          const SizedBox(height: 8),
          _fontDropdown(
            appTheme,
            key: MarkdownSettingsKeys.latinFontDropdown,
            label: '英文字体',
            options: MarkdownRenderTheme.latinFontOptions,
            value: _theme.latinFontFamily,
            onChanged: (value) => _applyTheme(
              value == null
                  ? _theme.copyWith(clearLatinFontFamily: true)
                  : _theme.copyWith(latinFontFamily: value),
            ),
          ),
          const SizedBox(height: 8),
          _fontDropdown(
            appTheme,
            label: '代码字体',
            options: MarkdownRenderTheme.monoFontOptions,
            value: _theme.monoFontFamily,
            onChanged: (value) => _applyTheme(
              value == null
                  ? _theme.copyWith(clearMonoFontFamily: true)
                  : _theme.copyWith(monoFontFamily: value),
            ),
          ),
          _slider(
            key: MarkdownSettingsKeys.fontSizeSlider,
            label: '字号',
            value: _theme.fontSize,
            min: MarkdownRenderLimits.minFontSize,
            max: MarkdownRenderLimits.maxFontSize,
            divisions: ((MarkdownRenderLimits.maxFontSize -
                        MarkdownRenderLimits.minFontSize) /
                    MarkdownRenderLimits.fontSizeStep)
                .round(),
            valueText: _theme.fontSize.toStringAsFixed(0),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                fontSize: MarkdownRenderLimits.clampFontSize(value),
              ),
            ),
          ),
          _slider(
            key: MarkdownSettingsKeys.lineHeightSlider,
            label: '行距',
            value: _theme.lineHeight,
            min: MarkdownRenderLimits.minLineHeight,
            max: MarkdownRenderLimits.maxLineHeight,
            divisions: ((MarkdownRenderLimits.maxLineHeight -
                        MarkdownRenderLimits.minLineHeight) /
                    MarkdownRenderLimits.lineHeightStep)
                .round(),
            valueText: _theme.lineHeight.toStringAsFixed(1),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                lineHeight: MarkdownRenderLimits.clampLineHeight(value),
              ),
            ),
          ),
          _slider(
            key: MarkdownSettingsKeys.paragraphSpacingSlider,
            label: '段距',
            value: _theme.paragraphSpacing,
            min: MarkdownRenderLimits.minParagraphSpacing,
            max: MarkdownRenderLimits.maxParagraphSpacing,
            divisions: ((MarkdownRenderLimits.maxParagraphSpacing -
                        MarkdownRenderLimits.minParagraphSpacing) /
                    MarkdownRenderLimits.paragraphSpacingStep)
                .round(),
            valueText: _theme.paragraphSpacing.toStringAsFixed(2),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                paragraphSpacing:
                    MarkdownRenderLimits.clampParagraphSpacing(value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontDropdown(
    ThemeData appTheme, {
    Key? key,
    required String label,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final effective = value ?? options.first;
    final items = <String>[
      ...options,
      if (!options.contains(effective)) effective,
    ];
    return Row(
      children: <Widget>[
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: DropdownButton<String>(
            key: key,
            isExpanded: true,
            value: effective,
            items: <DropdownMenuItem<String>>[
              for (final option in items)
                DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
            ],
            onChanged: (selected) => onChanged(
              selected == null || selected == options.first ? null : selected,
            ),
          ),
        ),
      ],
    );
  }

  Widget _headingCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.title,
      '标题',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            key: MarkdownSettingsKeys.headingCenterSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.headingAlignment == MarkdownHeadingAlignment.center,
            title: const Text('标题居中'),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                headingAlignment: value
                    ? MarkdownHeadingAlignment.center
                    : MarkdownHeadingAlignment.start,
              ),
            ),
          ),
          SwitchListTile(
            key: MarkdownSettingsKeys.headingRuleSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.headingRule,
            title: const Text('一级标题分隔线'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(headingRule: value)),
          ),
          _slider(
            label: '标题字重',
            value: _theme.headingWeight.toDouble(),
            min: MarkdownRenderLimits.minHeadingWeight.toDouble(),
            max: MarkdownRenderLimits.maxHeadingWeight.toDouble(),
            divisions: ((MarkdownRenderLimits.maxHeadingWeight -
                        MarkdownRenderLimits.minHeadingWeight) /
                    MarkdownRenderLimits.headingWeightStep)
                .round(),
            valueText: '${_theme.headingWeight}',
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                headingWeight: MarkdownRenderLimits.clampHeadingWeight(
                  value.round(),
                ),
              ),
            ),
          ),
          _slider(
            label: '标题缩放',
            value: _theme.headingScale,
            min: MarkdownRenderLimits.minHeadingScale,
            max: MarkdownRenderLimits.maxHeadingScale,
            divisions: ((MarkdownRenderLimits.maxHeadingScale -
                        MarkdownRenderLimits.minHeadingScale) /
                    MarkdownRenderLimits.headingScaleStep)
                .round(),
            valueText: '${(_theme.headingScale * 100).round()}%',
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                headingScale: MarkdownRenderLimits.clampHeadingScale(value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.table_chart_outlined,
      '表格',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _theme.tableBorderVisible,
            title: const Text('显示边框'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(tableBorderVisible: value)),
          ),
          _slider(
            label: '边框宽度',
            value: _theme.tableBorderWidth,
            min: MarkdownRenderLimits.minTableBorderWidth,
            max: MarkdownRenderLimits.maxTableBorderWidth,
            divisions: ((MarkdownRenderLimits.maxTableBorderWidth -
                        MarkdownRenderLimits.minTableBorderWidth) /
                    MarkdownRenderLimits.tableBorderWidthStep)
                .round(),
            valueText: _theme.tableBorderWidth.toStringAsFixed(1),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                tableBorderWidth:
                    MarkdownRenderLimits.clampTableBorderWidth(value),
              ),
            ),
          ),
          SwitchListTile(
            key: MarkdownSettingsKeys.tableStripeSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.tableStriped,
            title: const Text('斑马纹'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(tableStriped: value)),
          ),
          SwitchListTile(
            key: MarkdownSettingsKeys.tableCompactSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.tableCompact,
            title: const Text('紧凑单元格'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(tableCompact: value)),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.code,
      '代码块',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            key: MarkdownSettingsKeys.codeLineNumbersSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.codeShowLineNumbers,
            title: const Text('显示行号'),
            subtitle: const Text('打开行号时代码块用等宽纯文本渲染'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(codeShowLineNumbers: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _theme.showCodeCopyButton,
            title: const Text('界面里显示复制按钮'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(showCodeCopyButton: value)),
          ),
          _slider(
            label: '代码字号',
            value: _theme.codeFontScale,
            min: MarkdownRenderLimits.minCodeFontScale,
            max: MarkdownRenderLimits.maxCodeFontScale,
            divisions: ((MarkdownRenderLimits.maxCodeFontScale -
                        MarkdownRenderLimits.minCodeFontScale) /
                    MarkdownRenderLimits.codeFontScaleStep)
                .round(),
            valueText: '${(_theme.codeFontScale * 100).round()}%',
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                codeFontScale:
                    MarkdownRenderLimits.clampCodeFontScale(value),
              ),
            ),
          ),
          _slider(
            label: '圆角',
            value: _theme.codeRadius,
            min: MarkdownRenderLimits.minCodeRadius,
            max: MarkdownRenderLimits.maxCodeRadius,
            divisions: ((MarkdownRenderLimits.maxCodeRadius -
                        MarkdownRenderLimits.minCodeRadius) /
                    MarkdownRenderLimits.codeRadiusStep)
                .round(),
            valueText: _theme.codeRadius.toStringAsFixed(0),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                codeRadius: MarkdownRenderLimits.clampCodeRadius(value),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _columnsCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.view_column_outlined,
      '左右分栏',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            key: MarkdownSettingsKeys.columnsSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.columnsEnabled,
            title: const Text('分栏预览'),
            subtitle: const Text('按顶层块均衡分栏；PDF 暂不支持分栏'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(columnsEnabled: value)),
          ),
          _slider(
            label: '栏间距',
            value: _theme.columnGap,
            min: MarkdownRenderLimits.minColumnGap,
            max: MarkdownRenderLimits.maxColumnGap,
            divisions: ((MarkdownRenderLimits.maxColumnGap -
                        MarkdownRenderLimits.minColumnGap) /
                    MarkdownRenderLimits.columnGapStep)
                .round(),
            valueText: _theme.columnGap.toStringAsFixed(0),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                columnGap: MarkdownRenderLimits.clampColumnGap(value),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _theme.columnRule,
            title: const Text('分栏竖线'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(columnRule: value)),
          ),
        ],
      ),
    );
  }

  Widget _colorCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.color_lens_outlined,
      '颜色',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _colorRow('纸张背景', _theme.background,
              (color) => _applyTheme(_theme.copyWith(background: color))),
          _colorRow('正文', _theme.foreground,
              (color) => _applyTheme(_theme.copyWith(foreground: color))),
          _colorRow('标题', _theme.headingColor,
              (color) => _applyTheme(_theme.copyWith(headingColor: color))),
          _colorRow('链接', _theme.linkColor,
              (color) => _applyTheme(_theme.copyWith(linkColor: color))),
          _colorRow('代码背景', _theme.codeBackground,
              (color) => _applyTheme(_theme.copyWith(codeBackground: color))),
          _colorRow('表头背景', _theme.tableHeaderBackground,
              (color) =>
                  _applyTheme(_theme.copyWith(tableHeaderBackground: color))),
          _colorRow('表格边框', _theme.tableBorder,
              (color) => _applyTheme(_theme.copyWith(tableBorder: color))),
          _colorRow('斑马纹', _theme.tableRowStripe,
              (color) => _applyTheme(_theme.copyWith(tableRowStripe: color))),
          _colorRow('引用背景', _theme.quoteBackground,
              (color) => _applyTheme(_theme.copyWith(quoteBackground: color))),
          _colorRow('引用竖条', _theme.quoteBar,
              (color) => _applyTheme(_theme.copyWith(quoteBar: color))),
        ],
      ),
    );
  }

  Widget _colorRow(String label, Color current, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: current,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final picked = await _pickColor(context, current);
              if (picked != null) {
                onPick(picked);
              }
            },
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }

  Future<Color?> _pickColor(BuildContext context, Color current) {
    const palette = <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFF4ECD8),
      Color(0xFFFBFBFB),
      Color(0xFF1E1F22),
      Color(0xFF101418),
      Color(0xFF1F2328),
      Color(0xFF3B3127),
      Color(0xFF57606A),
      Color(0xFFA9AEB6),
      Color(0xFFD0D7DE),
      Color(0xFF0969DA),
      Color(0xFF0B6BCB),
      Color(0xFF6CB6FF),
      Color(0xFF2F6F4F),
      Color(0xFF8A5A2B),
      Color(0xFFD32F2F),
    ];
    var selected = current;
    final hex = TextEditingController(text: _hexOf(current));
    return showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('选择颜色'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final color in palette)
                      InkWell(
                        onTap: () => setDialogState(() {
                          selected = color;
                          hex.text = _hexOf(color);
                        }),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected.toARGB32() == color.toARGB32()
                                  ? Theme.of(dialogContext).colorScheme.primary
                                  : Theme.of(dialogContext).dividerColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hex,
                  decoration: const InputDecoration(
                    labelText: '十六进制（#RRGGBB）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[#0-9a-fA-F]'),
                    ),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: (value) {
                    final parsed = _parseHex(value);
                    if (parsed != null) {
                      setDialogState(() => selected = parsed);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfCard(ThemeData appTheme) {
    return _card(
      appTheme,
      Icons.picture_as_pdf_outlined,
      'PDF 页面',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _slider(
            key: MarkdownSettingsKeys.pageMarginSlider,
            label: '页边距',
            value: _theme.pageMargin,
            min: MarkdownRenderLimits.minPageMargin,
            max: MarkdownRenderLimits.maxPageMargin,
            divisions: ((MarkdownRenderLimits.maxPageMargin -
                        MarkdownRenderLimits.minPageMargin) /
                    MarkdownRenderLimits.pageMarginStep)
                .round(),
            valueText: _theme.pageMargin.toStringAsFixed(0),
            onChanged: (value) => _applyTheme(
              _theme.copyWith(
                pageMargin: MarkdownRenderLimits.clampPageMargin(value),
              ),
            ),
          ),
          TextField(
            key: MarkdownSettingsKeys.pdfHeaderField,
            controller: _header,
            decoration: const InputDecoration(
              labelText: '页眉',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(pdfHeader: value)),
          ),
          const SizedBox(height: 8),
          TextField(
            key: MarkdownSettingsKeys.pdfFooterField,
            controller: _footer,
            decoration: const InputDecoration(
              labelText: '页脚',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(pdfFooter: value)),
          ),
          SwitchListTile(
            key: MarkdownSettingsKeys.pageNumberSwitch,
            contentPadding: EdgeInsets.zero,
            value: _theme.showPageNumber,
            title: const Text('显示页码'),
            onChanged: (value) =>
                _applyTheme(_theme.copyWith(showPageNumber: value)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _pdfBusy ? null : _exportPdf,
              icon: const Icon(Icons.download_outlined),
              label: const Text('导出 PDF'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    Key? key,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            key: key,
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(valueText, textAlign: TextAlign.end),
        ),
      ],
    );
  }

  static String _hexOf(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  static Color? _parseHex(String value) {
    var text = value.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    }
    if (text.length == 6) {
      text = 'FF$text';
    }
    if (text.length != 8) {
      return null;
    }
    final parsed = int.tryParse(text, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
