import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/media/image_size.dart';

/// 只读文件头解析像素尺寸：认得的格式给对宽高，认不出就如实返回 null。
void main() {
  group('PNG', () {
    test('reads IHDR width/height', () {
      final bytes = pngHeader(width: 640, height: 480);
      final info = readImageInfo(bytes);
      expect(info, isNotNull);
      expect(info!.format, ImageFormat.png);
      expect(info.size, const ImageSize(640, 480));
    });

    test('rejects a wrong signature', () {
      final bytes = pngHeader(width: 10, height: 20)..[0] = 0x00;
      expect(readImageInfo(bytes), isNull);
    });

    test('rejects a non-IHDR first chunk', () {
      final bytes = pngHeader(width: 10, height: 20)..[12] = 0x58; // 'X'HDR
      expect(readImageInfo(bytes), isNull);
    });

    test('rejects a truncated header', () {
      final bytes = pngHeader(width: 10, height: 20).sublist(0, 20);
      expect(readImageInfo(Uint8List.fromList(bytes)), isNull);
    });
  });

  group('GIF', () {
    test('reads little-endian logical screen size', () {
      final info = readImageInfo(gifHeader(width: 320, height: 200));
      expect(info, isNotNull);
      expect(info!.format, ImageFormat.gif);
      expect(info.size, const ImageSize(320, 200));
    });

    test('accepts the older GIF87a signature', () {
      final bytes = gifHeader(width: 8, height: 9);
      bytes[4] = 0x37; // GIF87a
      expect(readImageSize(bytes), const ImageSize(8, 9));
    });

    test('zero width is refused instead of producing an empty picture', () {
      expect(readImageInfo(gifHeader(width: 0, height: 9)), isNull);
    });

    test('a plain text file is not a GIF', () {
      final bytes = Uint8List.fromList(<int>[
        0x47,
        0x49,
        0x46,
        ...List<int>.filled(20, 0),
      ]);
      expect(readImageInfo(bytes), isNull);
    });
  });

  group('BMP', () {
    test('BITMAPINFOHEADER width/height', () {
      final info = readImageInfo(bmpInfoHeader(width: 1024, height: 768));
      expect(info, isNotNull);
      expect(info!.format, ImageFormat.bmp);
      expect(info.size, const ImageSize(1024, 768));
    });

    test('negative height (top-down bitmap) becomes an absolute size', () {
      final info = readImageInfo(bmpInfoHeader(width: 100, height: -60));
      expect(info!.size, const ImageSize(100, 60));
    });

    test('BITMAPCOREHEADER 16-bit fields', () {
      final info = readImageInfo(bmpCoreHeader(width: 64, height: 32));
      expect(info!.size, const ImageSize(64, 32));
    });
  });

  group('WEBP', () {
    test('lossy VP8 frame header', () {
      final info = readImageInfo(webpVp8(width: 512, height: 288));
      expect(info, isNotNull);
      expect(info!.format, ImageFormat.webp);
      expect(info.size, const ImageSize(512, 288));
    });

    test('lossless VP8L packed 14+14 bit size', () {
      final info = readImageInfo(webpVp8l(width: 300, height: 200));
      expect(info!.size, const ImageSize(300, 200));
    });

    test('extended VP8X 24-bit canvas size', () {
      final info = readImageInfo(webpVp8x(width: 1920, height: 1080));
      expect(info!.size, const ImageSize(1920, 1080));
    });

    test('a VP8 frame without the 9D 01 2A start code is refused', () {
      final bytes = webpVp8(width: 512, height: 288)..[23] = 0x00;
      expect(readImageInfo(bytes), isNull);
    });
  });

  group('JPEG', () {
    test('reads SOF0 height/width', () {
      final info = readImageInfo(jpegHeader(width: 800, height: 600));
      expect(info, isNotNull);
      expect(info!.format, ImageFormat.jpeg);
      expect(info.size, const ImageSize(800, 600));
    });

    test('skips APP0 and reads a later progressive SOF2 segment', () {
      final info = readImageInfo(
        jpegHeader(width: 12, height: 34, marker: 0xC2, withAppSegment: true),
      );
      expect(info!.size, const ImageSize(12, 34));
    });

    test('truncated before SOF is refused', () {
      final bytes = jpegHeader(width: 800, height: 600).sublist(0, 8);
      expect(readImageInfo(Uint8List.fromList(bytes)), isNull);
    });
  });

  group('dispatchers', () {
    test('readImageSize returns just the size', () {
      expect(
          readImageSize(pngHeader(width: 3, height: 4)), const ImageSize(3, 4));
    });

    test('garbage bytes are null, never a guessed size', () {
      expect(
          readImageInfo(Uint8List.fromList(List<int>.filled(64, 7))), isNull);
      expect(readImageInfo(Uint8List(0)), isNull);
    });

    test('extension lookup is case-insensitive and dot-tolerant', () {
      expect(imageFormatForExtension('PNG'), ImageFormat.png);
      expect(imageFormatForExtension('.JPEG'), ImageFormat.jpeg);
      expect(imageFormatForExtension('jpg'), ImageFormat.jpeg);
      expect(imageFormatForExtension('jpe'), ImageFormat.jpeg);
      expect(imageFormatForExtension('gif'), ImageFormat.gif);
      expect(imageFormatForExtension('bmp'), ImageFormat.bmp);
      expect(imageFormatForExtension('dib'), ImageFormat.bmp);
      expect(imageFormatForExtension('webp'), ImageFormat.webp);
      expect(imageFormatForExtension(' heic '), isNull);
      expect(imageFormatForExtension(''), isNull);
    });

    test('ImageSize value equality and validity', () {
      expect(const ImageSize(10, 20), const ImageSize(10, 20));
      expect(
          const ImageSize(10, 20).hashCode, const ImageSize(10, 20).hashCode);
      expect(const ImageSize(10, 20).isValid, isTrue);
      expect(const ImageSize(0, 20).isValid, isFalse);
      expect(const ImageSize(10, 20).toString(), '10x20');
    });
  });
}

// ---------------------------------------------------------------------------
// 文件头构造：只造到"解析器会读到"的最小长度，不追求成为合法图片。
// ---------------------------------------------------------------------------

Uint8List pngHeader({required int width, required int height}) {
  final bytes = Uint8List(24);
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  bytes.setRange(0, signature.length, signature);
  // 偏移 8..11 = 块长度（13），12..15 = 'IHDR'，16..23 = 宽高（大端）。
  bytes[8] = 0x00;
  bytes[9] = 0x00;
  bytes[10] = 0x00;
  bytes[11] = 0x0D;
  bytes[12] = 0x49; // I
  bytes[13] = 0x48; // H
  bytes[14] = 0x44; // D
  bytes[15] = 0x52; // R
  writeUint32Be(bytes, 16, width);
  writeUint32Be(bytes, 20, height);
  return bytes;
}

Uint8List gifHeader({required int width, required int height}) {
  final bytes = Uint8List(13);
  bytes.setRange(0, 6, 'GIF89a'.codeUnits);
  writeUint16Le(bytes, 6, width);
  writeUint16Le(bytes, 8, height);
  return bytes;
}

Uint8List bmpInfoHeader({required int width, required int height}) {
  final bytes = Uint8List(30);
  bytes[0] = 0x42; // B
  bytes[1] = 0x4D; // M
  writeUint32Le(bytes, 14, 40); // BITMAPINFOHEADER
  writeInt32Le(bytes, 18, width);
  writeInt32Le(bytes, 22, height);
  return bytes;
}

Uint8List bmpCoreHeader({required int width, required int height}) {
  final bytes = Uint8List(26);
  bytes[0] = 0x42;
  bytes[1] = 0x4D;
  writeUint32Le(bytes, 14, 12); // BITMAPCOREHEADER
  writeUint16Le(bytes, 18, width);
  writeUint16Le(bytes, 20, height);
  return bytes;
}

Uint8List webpVp8({required int width, required int height}) {
  final bytes = Uint8List(30);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WEBP'.codeUnits);
  bytes.setRange(12, 16, 'VP8 '.codeUnits);
  bytes[23] = 0x9D;
  bytes[24] = 0x01;
  bytes[25] = 0x2A;
  writeUint16Le(bytes, 26, width & 0x3FFF);
  writeUint16Le(bytes, 28, height & 0x3FFF);
  return bytes;
}

Uint8List webpVp8l({required int width, required int height}) {
  final bytes = Uint8List(30);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WEBP'.codeUnits);
  bytes.setRange(12, 16, 'VP8L'.codeUnits);
  bytes[20] = 0x2F;
  final packed = (width - 1) | ((height - 1) << 14);
  writeUint32Le(bytes, 21, packed);
  return bytes;
}

Uint8List webpVp8x({required int width, required int height}) {
  final bytes = Uint8List(30);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WEBP'.codeUnits);
  bytes.setRange(12, 16, 'VP8X'.codeUnits);
  writeUint24Le(bytes, 24, width - 1);
  writeUint24Le(bytes, 27, height - 1);
  return bytes;
}

/// JPEG 以 SOI 开头；中间可选一个 APP0 段；SOF 段头 2 字节长度，
/// 段内布局：精度(1) 高(2) 宽(2) 分量数(1)…
Uint8List jpegHeader({
  required int width,
  required int height,
  int marker = 0xC0,
  bool withAppSegment = false,
}) {
  final bytes = <int>[0xFF, 0xD8];
  if (withAppSegment) {
    const appPayload = <int>[
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
    ];
    bytes.addAll(<int>[0xFF, 0xE0, 0x00, appPayload.length + 2]);
    bytes.addAll(appPayload);
  }
  bytes.addAll(<int>[
    0xFF,
    marker,
    0x00,
    0x11, // 段长 17
    0x08, // 精度
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    0x03,
    0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
  ]);
  bytes.addAll(<int>[0xFF, 0xD9]);
  return Uint8List.fromList(bytes);
}

void writeUint16Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
}

void writeUint24Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
}

void writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

void writeInt32Le(Uint8List bytes, int offset, int value) =>
    writeUint32Le(bytes, offset, value & 0xFFFFFFFF);

void writeUint32Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xFF;
  bytes[offset + 1] = (value >> 16) & 0xFF;
  bytes[offset + 2] = (value >> 8) & 0xFF;
  bytes[offset + 3] = value & 0xFF;
}
