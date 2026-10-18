/// 图片**像素尺寸**解析：只读文件头，不解码像素、不依赖任何第三方包。
///
/// 为什么需要它：导出 .docx 时要给每张图一个"打印出来多大"的尺寸（Word 的
/// drawing 只认 EMU，不认"缩放到栏宽"这种相对说法）。尺寸错，图要么撑破版心、
/// 要么被拉成一条。解析失败不猜：返回 `null`，由调用方决定"跳过这张图并报告"，
/// 绝不编一个尺寸糊上去。
///
/// 支持 PNG / JPEG / GIF / BMP / WEBP（HEIC 等只拍不转的格式暂不解析——手机上
/// 常见，但 Dart 没有内置解码，硬编尺寸不如明确报告"这张没嵌进去"）。
library;

import 'dart:typed_data';

/// 图片的像素尺寸（宽 × 高，均为正数）。
class ImageSize {
  const ImageSize(this.width, this.height);

  final int width;
  final int height;

  bool get isValid => width > 0 && height > 0;

  @override
  String toString() => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      other is ImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// 认得的图片容器格式。
enum ImageFormat {
  png('png'),
  jpeg('jpeg'),
  gif('gif'),
  bmp('bmp'),
  webp('webp');

  const ImageFormat(this.extension);

  /// 写进 docx 的扩展名（`image/jpeg` 对应 `jpeg`，不是 `jpg`）。
  final String extension;
}

/// 一次解析结果：格式 + 像素尺寸。
class ImageInfo {
  const ImageInfo(this.format, this.size);

  final ImageFormat format;
  final ImageSize size;
}

/// 只解析文件头。认不出格式或头部不完整 → `null`。
ImageInfo? readImageInfo(Uint8List bytes) {
  final png = _pngInfo(bytes);
  if (png != null) return png;
  final gif = _gifInfo(bytes);
  if (gif != null) return gif;
  final bmp = _bmpInfo(bytes);
  if (bmp != null) return bmp;
  final webp = _webpInfo(bytes);
  if (webp != null) return webp;
  final jpeg = _jpegInfo(bytes);
  if (jpeg != null) return jpeg;
  return null;
}

/// 只要尺寸。
ImageSize? readImageSize(Uint8List bytes) => readImageInfo(bytes)?.size;

/// 扩展名（小写、不带点）对应的格式；不认识返回 `null`。
ImageFormat? imageFormatForExtension(String extension) {
  final ext = extension.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  return switch (ext) {
    'png' => ImageFormat.png,
    'jpg' || 'jpeg' || 'jpe' => ImageFormat.jpeg,
    'gif' => ImageFormat.gif,
    'bmp' || 'dib' => ImageFormat.bmp,
    'webp' => ImageFormat.webp,
    _ => null,
  };
}

ImageInfo? _pngInfo(Uint8List b) {
  // 89 50 4E 47 0D 0A 1A 0A，IHDR 从偏移 8 开始：len(4) + 'IHDR'(4) + w(4) + h(4)
  if (b.length < 24) return null;
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (b[i] != signature[i]) return null;
  }
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
    return null;
  }
  final width = _readUint32Be(b, 16);
  final height = _readUint32Be(b, 20);
  return ImageInfo(ImageFormat.png, ImageSize(width, height));
}

ImageInfo? _gifInfo(Uint8List b) {
  // 'GIF87a' / 'GIF89a'，逻辑屏幕宽高为小端 16 位（偏移 6、8）
  if (b.length < 10) return null;
  if (b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46) return null;
  final width = _readUint16Le(b, 6);
  final height = _readUint16Le(b, 8);
  if (width == 0 || height == 0) return null;
  return ImageInfo(ImageFormat.gif, ImageSize(width, height));
}

ImageInfo? _bmpInfo(Uint8List b) {
  // 'BM'，DIB 头大小在偏移 14：12 = BITMAPCOREHEADER，≥40 = BITMAPINFOHEADER
  if (b.length < 26) return null;
  if (b[0] != 0x42 || b[1] != 0x4D) return null;
  final dibSize = _readUint32Le(b, 14);
  if (dibSize == 12) {
    final width = _readUint16Le(b, 18);
    final height = _readUint16Le(b, 20);
    if (width == 0 || height == 0) return null;
    return ImageInfo(ImageFormat.bmp, ImageSize(width, height));
  }
  if (dibSize < 40 || b.length < 26) return null;
  final width = _readInt32Le(b, 18);
  final height = _readInt32Le(b, 22);
  // 高度为负表示倒序位图，尺寸取绝对值
  final w = width.abs();
  final h = height.abs();
  if (w == 0 || h == 0) return null;
  return ImageInfo(ImageFormat.bmp, ImageSize(w, h));
}

ImageInfo? _webpInfo(Uint8List b) {
  // 'RIFF' + size(4) + 'WEBP'，再按块类型分：
  //   VP8  → 有损，起始码 9D 01 2A 后接宽高
  //   VP8L → 无损，0x2F 后 4 字节打包 14+14 位宽高
  //   VP8X → 扩展，24 位宽高
  if (b.length < 30) return null;
  if (b[0] != 0x52 || b[1] != 0x49 || b[2] != 0x46 || b[3] != 0x46) return null;
  if (b[8] != 0x57 || b[9] != 0x45 || b[10] != 0x42 || b[11] != 0x50) {
    return null;
  }
  final chunk = String.fromCharCodes(b.sublist(12, 16));
  switch (chunk) {
    case 'VP8 ':
      // 帧头从偏移 20 起：3 字节帧标记 + 3 字节起始码 9D 01 2A
      if (b.length < 30) return null;
      if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
      final width = _readUint16Le(b, 26) & 0x3FFF;
      final height = _readUint16Le(b, 28) & 0x3FFF;
      if (width == 0 || height == 0) return null;
      return ImageInfo(ImageFormat.webp, ImageSize(width, height));
    case 'VP8L':
      if (b.length < 25 || b[20] != 0x2F) return null;
      final packed = _readUint32Le(b, 21);
      final width = (packed & 0x3FFF) + 1;
      final height = ((packed >> 14) & 0x3FFF) + 1;
      return ImageInfo(ImageFormat.webp, ImageSize(width, height));
    case 'VP8X':
      // 偏移 24 起：24 位（宽-1）小端 + 24 位（高-1）小端
      if (b.length < 30) return null;
      final width = _readUint24Le(b, 24) + 1;
      final height = _readUint24Le(b, 27) + 1;
      return ImageInfo(ImageFormat.webp, ImageSize(width, height));
  }
  return null;
}

ImageInfo? _jpegInfo(Uint8List b) {
  // FF D8 开头，扫描到 SOF 标记（C0-C3/C5-C7/C9-CB/CD-CF）读段内宽高。
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var pos = 2;
  while (pos + 3 < b.length) {
    if (b[pos] != 0xFF) {
      pos++;
      continue;
    }
    final marker = b[pos + 1];
    // 独立的 FF 填充字节
    if (marker == 0xFF) {
      pos++;
      continue;
    }
    // 无长度的标记：TEM(RSTn) 与 SOI/EOI
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      pos += 2;
      continue;
    }
    if (pos + 4 > b.length) return null;
    final length = (b[pos + 2] << 8) | b[pos + 3];
    if (length < 2) return null;
    final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof) {
      if (pos + 9 > b.length) return null;
      final height = (b[pos + 5] << 8) | b[pos + 6];
      final width = (b[pos + 7] << 8) | b[pos + 8];
      if (width == 0 || height == 0) return null;
      return ImageInfo(ImageFormat.jpeg, ImageSize(width, height));
    }
    pos += 2 + length;
  }
  return null;
}

int _readUint16Le(Uint8List b, int offset) => b[offset] | (b[offset + 1] << 8);

int _readUint24Le(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16);

int _readUint32Le(Uint8List b, int offset) =>
    b[offset] |
    (b[offset + 1] << 8) |
    (b[offset + 2] << 16) |
    (b[offset + 3] << 24);

int _readInt32Le(Uint8List b, int offset) {
  final value = _readUint32Le(b, offset);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}

int _readUint32Be(Uint8List b, int offset) =>
    (b[offset] << 24) |
    (b[offset + 1] << 16) |
    (b[offset + 2] << 8) |
    b[offset + 3];
