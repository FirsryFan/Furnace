/// 图片文件名的扩展名 → MIME，以及"这真的是图片吗"的魔数嗅探。
///
/// 两处要用：拍照/选图那条通路（`HandwritingIntakeStore`）和题库配图
/// （`QuestionMediaStore`）；拖拽收题还会用到字节嗅探——从微信聊天记录或浏览器里
/// 拖出来的临时文件，扩展名不可信，但字节头不会撒谎。
///
/// 放一处，免得三份 switch 各认各的：以后加一个 `avif` 只改这里。
library;

import 'dart:typed_data';

/// 认得的图片扩展名（小写，不带点）。
const Set<String> kImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'bmp',
};

/// 从文件名推 MIME。认不出来的扩展名返回 null —— `attachments.mime` 可空，
/// 存 null 比存一个猜的要诚实。
String? imageMimeForName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return null;
  }
  // 扩展名要落在最后一个路径分隔符之后；`a.b/c` 这种没有扩展名。
  final separator = name.lastIndexOf(RegExp(r'[\\/]'));
  if (dot < separator) {
    return null;
  }
  return switch (name.substring(dot + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    _ => null,
  };
}

/// 从字节头认图片：只回答"这是不是一张认得的图"，不做解码。
///
/// 用途是挡住拖错的东西（Word 文档、压缩包、聊天记录里拖出来的 .dat），
/// 所以宁可**只认确凿的魔数**，认不出来就返回 false，绝不猜。
bool looksLikeImageBytes(Uint8List bytes) {
  if (bytes.length < 2) {
    return false;
  }
  // JPEG: FF D8 FF
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return true;
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return true;
  }
  // GIF8
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return true;
  }
  // BMP: 42 4D
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  // WEBP: RIFF....WEBP
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  // HEIC/HEIF: `....ftypheic` / `heix` / `heim` / `heis` / `hevc` / `mif1`
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (const {'heic', 'heix', 'heim', 'heis', 'hevc', 'mif1'}.contains(brand)) {
      return true;
    }
  }
  return false;
}
