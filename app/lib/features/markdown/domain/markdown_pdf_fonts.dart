/// PDF 导出的中文字体来源：应用内置的一份可再分发中文 TTF。
///
/// `pdf` 包本身不携带中文字形：内置的 Helvetica/Times 只覆盖 WinAnsi，把中文
/// 直接交给它们会得到空白或乱码。所以导出 PDF 的第一步是取一份能嵌入的
/// TrueType 中文字体（pdf 包按用到的字形做子集嵌入，成品通常只有几十 KB）。
///
/// 字体来自**应用资产**而不是系统字体目录，原因：
///
///  * Windows 的 `C:\Windows\Fonts\*.ttf` 不是每台机器都有；Android 的系统
///    中文字体是 `.ttc` 集合，而 `pdf` 3.12 的 `TtfParser` 从文件偏移 4 处直接
///    读 table 目录、没有 TTC 集合头解析，喂 `.ttc` 必然解析失败。
///  * 内置同一份 TTF 让 Windows 与 Android 的 PDF 排版/字形完全一致。
///
/// 资产：`assets/fonts/noto-sans-sc-regular.ttf`（Noto Sans SC Regular，
/// SIL Open Font License 1.1；上游 commit、派生命令与 SHA256 见
/// `assets/fonts/FONT-NOTICE.md`）。字体缺失时抛
/// [MarkdownPdfFontUnavailableException]，绝不生成"没有中文"的 PDF。
library;

import 'package:flutter/services.dart';

/// 一份可嵌入的中文字体。
class MarkdownPdfFontData {
  const MarkdownPdfFontData({required this.bytes, required this.sourcePath});

  final Uint8List bytes;

  /// 字体实际来源（内置资产路径；写进诊断信息，方便判断打包是否完整）。
  final String sourcePath;
}

/// 找不到可嵌入的中文字体。PDF 导出必须把它当作"不可用"报告，而不是生成一份
/// 中文全部缺失的 PDF。
class MarkdownPdfFontUnavailableException implements Exception {
  MarkdownPdfFontUnavailableException(this.attempted);

  /// 尝试过但不可用的来源（含原因）。
  final List<String> attempted;

  @override
  String toString() => '没有找到可嵌入的中文字体（TTF）；尝试过：'
      '${attempted.isEmpty ? '（无候选来源）' : attempted.join('、')}';
}

/// 字体解析接口；测试可替换。
abstract class MarkdownPdfFontResolver {
  Future<MarkdownPdfFontData> resolve();
}

/// 从应用资产加载内置中文字体（Windows / Android 同一份 TTF）。
class BundledMarkdownPdfFontResolver implements MarkdownPdfFontResolver {
  BundledMarkdownPdfFontResolver({
    Future<ByteData> Function(String path)? loadAsset,
  }) : _loadAsset = loadAsset ?? rootBundle.load;

  /// 内置字体（Noto Sans SC Regular，OFL 1.1）。
  static const String fontAssetPath =
      'assets/fonts/noto-sans-sc-regular.ttf';

  /// 随字体一起分发的许可全文（不进 PDF，只作为应用资产打包）。
  static const String licenseAssetPath = 'assets/fonts/OFL.txt';

  /// 字体资产的最小合理体积；小于它的只可能是占位/截断文件，继续喂给 `pdf`
  /// 只会得到难以定位的解析异常，不如在这里就当作"字体不可用"。
  static const int minimumSaneFontBytes = 256 * 1024;

  final Future<ByteData> Function(String path) _loadAsset;

  @override
  Future<MarkdownPdfFontData> resolve() async {
    final attempted = <String>[];
    ByteData? data;
    try {
      data = await _loadAsset(fontAssetPath);
    } on Object catch (error) {
      attempted.add('$fontAssetPath（内置字体资产不可读：$error）');
    }
    if (data == null) {
      throw MarkdownPdfFontUnavailableException(attempted);
    }

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final kind = trueTypeKind(bytes);
    if (kind == TrueTypeKind.collection) {
      attempted.add('$fontAssetPath（TTC 集合，pdf 包不支持）');
      throw MarkdownPdfFontUnavailableException(attempted);
    }
    if (kind != TrueTypeKind.trueType) {
      attempted.add(
        '$fontAssetPath（需要 TrueType outlines 的 TTF，实际文件头 '
        '${_fontHeader(bytes)}）',
      );
      throw MarkdownPdfFontUnavailableException(attempted);
    }
    if (bytes.length < minimumSaneFontBytes) {
      attempted.add(
        '$fontAssetPath（字体只有 ${bytes.length} 字节，疑似被截断）',
      );
      throw MarkdownPdfFontUnavailableException(attempted);
    }
    return MarkdownPdfFontData(bytes: bytes, sourcePath: fontAssetPath);
  }

  static String _fontHeader(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '（空文件）';
    }
    final head = bytes.sublist(0, bytes.length < 4 ? bytes.length : 4);
    final hex = head
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final ascii = String.fromCharCodes(
      head.map((byte) => byte >= 0x20 && byte < 0x7f ? byte : 0x2e),
    );
    return '$hex / $ascii';
  }
}

/// 字体文件头分类。
enum TrueTypeKind {
  /// 单字体 TrueType（0x00010000 / 'true'）。
  trueType,

  /// 单字体 OpenType/CFF（'OTTO'）。
  openType,

  /// TTC 字体集合（'ttcf'）。
  collection,

  /// 无法识别。
  unknown,
}

/// 按文件头判断字体种类。`pdf` 包只支持带 TrueType outlines 的单字体 TTF。
TrueTypeKind trueTypeKind(Uint8List bytes) {
  if (bytes.length < 4) {
    return TrueTypeKind.unknown;
  }
  final tag = String.fromCharCodes(bytes.sublist(0, 4));
  if (tag == 'ttcf') {
    return TrueTypeKind.collection;
  }
  if (tag == 'OTTO') {
    return TrueTypeKind.openType;
  }
  if (tag == 'true' || tag == 'typ1') {
    return TrueTypeKind.trueType;
  }
  final version = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  if (version == 0x00010000) {
    return TrueTypeKind.trueType;
  }
  return TrueTypeKind.unknown;
}
