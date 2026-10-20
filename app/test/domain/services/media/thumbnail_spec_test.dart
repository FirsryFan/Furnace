import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/media/thumbnail_spec.dart';

void main() {
  group('thumbnailDecodeSpec 常规换算', () {
    test('正方形 96 逻辑像素、dpr 1 → 96x96', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 96, logicalHeight: 96);
      expect(spec.cacheWidth, 96);
      expect(spec.cacheHeight, 96);
      expect(spec.devicePixelRatio, 1.0);
      expect(spec.capped, isFalse);
      expect(spec.isEmpty, isFalse);
    });

    test('dpr 2 → 192x192', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 96, logicalHeight: 96, devicePixelRatio: 2);
      expect(spec.cacheWidth, 192);
      expect(spec.cacheHeight, 192);
      expect(spec.devicePixelRatio, 2.0);
    });

    test('dpr 1.5 的整数结果', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 100, logicalHeight: 64, devicePixelRatio: 1.5);
      expect(spec.cacheWidth, 150);
      expect(spec.cacheHeight, 96);
    });

    test('小数结果向上取整（101 * 1.2 = 121.2 → 122）', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 101, logicalHeight: 20, devicePixelRatio: 1.2);
      expect(spec.cacheWidth, 122);
      expect(spec.cacheHeight, 24);
    });

    test('宽图保持宽高比', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 320, logicalHeight: 80);
      expect(spec.cacheWidth, 320);
      expect(spec.cacheHeight, 80);
      expect(spec.capped, isFalse);
    });

    test('竖图保持宽高比', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 48, logicalHeight: 240);
      expect(spec.cacheWidth, 48);
      expect(spec.cacheHeight, 240);
    });

    test('极小的显示尺寸也至少 1 像素', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 1, logicalHeight: 1);
      expect(spec.cacheWidth, 1);
      expect(spec.cacheHeight, 1);
      expect(spec.isEmpty, isFalse);
    });
  });

  group('maxDecodeSide 上限', () {
    test('长边超过上限时压缩并标记 capped', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 2000, logicalHeight: 1000, maxDecodeSide: 1024);
      expect(spec.cacheWidth, 1024);
      expect(spec.cacheHeight, 512);
      expect(spec.capped, isTrue);
    });

    test('竖图长边是高度', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 1000, logicalHeight: 2000, maxDecodeSide: 1024);
      expect(spec.cacheWidth, 512);
      expect(spec.cacheHeight, 1024);
      expect(spec.capped, isTrue);
    });

    test('压到上限后宽高比误差 <= 1 像素（3:2）', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 3000, logicalHeight: 2000, maxDecodeSide: 1024);
      expect(spec.cacheWidth, 1024);
      expect(spec.cacheHeight, 683);
      final ratio = spec.cacheWidth / spec.cacheHeight;
      expect(ratio, closeTo(1.5, 1.5 / 683));
    });

    test('不超过上限时不标记 capped', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 500, logicalHeight: 400, maxDecodeSide: 1024);
      expect(spec.cacheWidth, 500);
      expect(spec.cacheHeight, 400);
      expect(spec.capped, isFalse);
    });

    test('正好等于上限不算 capped', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 1024, logicalHeight: 512, maxDecodeSide: 1024);
      expect(spec.capped, isFalse);
      expect(spec.cacheWidth, 1024);
    });

    test('maxDecodeSide = 0 表示不设上限', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 5000, logicalHeight: 2500, maxDecodeSide: 0);
      expect(spec.cacheWidth, 5000);
      expect(spec.cacheHeight, 2500);
      expect(spec.capped, isFalse);
    });

    test('maxDecodeSide 负数也表示不设上限', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 4000, logicalHeight: 3000, maxDecodeSide: -1);
      expect(spec.cacheWidth, 4000);
      expect(spec.cacheHeight, 3000);
      expect(spec.capped, isFalse);
    });

    test('压缩后两边都不会是 0', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 100000, logicalHeight: 2, maxDecodeSide: 1024);
      expect(spec.cacheWidth, 1024);
      expect(spec.cacheHeight, 1);
      expect(spec.cacheWidth, greaterThan(0));
      expect(spec.cacheHeight, greaterThan(0));
    });
  });

  group('非法输入', () {
    test('宽 0 → 空 spec（不传 cache）', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 0, logicalHeight: 96);
      expect(spec.isEmpty, isTrue);
      expect(spec.cacheWidth, 0);
      expect(spec.cacheHeight, 0);
    });

    test('高负数 → 空 spec', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 96, logicalHeight: -8);
      expect(spec.isEmpty, isTrue);
    });

    test('两边都非法 → 空 spec', () {
      final spec = thumbnailDecodeSpec(logicalWidth: 0, logicalHeight: 0);
      expect(spec.isEmpty, isTrue);
    });

    test('dpr 0 → 按 1.0', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 10, logicalHeight: 10, devicePixelRatio: 0);
      expect(spec.devicePixelRatio, 1.0);
      expect(spec.cacheWidth, 10);
    });

    test('dpr 负数 → 按 1.0', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 10, logicalHeight: 10, devicePixelRatio: -2);
      expect(spec.devicePixelRatio, 1.0);
    });

    test('dpr NaN / Infinity → 按 1.0', () {
      final bads = <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      for (final bad in bads) {
        final spec = thumbnailDecodeSpec(
            logicalWidth: 10, logicalHeight: 10, devicePixelRatio: bad);
        expect(spec.devicePixelRatio, 1.0, reason: bad.toString());
        expect(spec.cacheWidth, 10);
      }
    });

    test('dpr 1e300 被钳到 16（防 int 溢出）', () {
      final spec = thumbnailDecodeSpec(
          logicalWidth: 10, logicalHeight: 10, devicePixelRatio: 1e300);
      expect(spec.devicePixelRatio, 16.0);
      expect(spec.cacheWidth, 160);
    });
  });

  group('值语义', () {
    test('同输入同输出（确定性）', () {
      final a = thumbnailDecodeSpec(
          logicalWidth: 123, logicalHeight: 456, devicePixelRatio: 2.75);
      final b = thumbnailDecodeSpec(
          logicalWidth: 123, logicalHeight: 456, devicePixelRatio: 2.75);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toJson(), b.toJson());
    });

    test('不同尺寸不等', () {
      expect(
        thumbnailDecodeSpec(logicalWidth: 10, logicalHeight: 10),
        isNot(thumbnailDecodeSpec(logicalWidth: 10, logicalHeight: 11)),
      );
    });

    test('capped 不同则不等', () {
      final capped = thumbnailDecodeSpec(
          logicalWidth: 2000, logicalHeight: 1000, maxDecodeSide: 1024);
      final exact = thumbnailDecodeSpec(
          logicalWidth: 1024, logicalHeight: 512, maxDecodeSide: 1024);
      expect(capped, isNot(exact));
    });

    test('toJson 键名稳定', () {
      final json =
          thumbnailDecodeSpec(logicalWidth: 96, logicalHeight: 64).toJson();
      expect(json.keys.toList(), <String>[
        'cacheWidth',
        'cacheHeight',
        'devicePixelRatio',
        'capped',
      ]);
      expect(json['cacheWidth'], 96);
      expect(json['capped'], isFalse);
    });

    test('toString 可读', () {
      expect(
        thumbnailDecodeSpec(logicalWidth: 96, logicalHeight: 96).toString(),
        'ThumbnailDecodeSpec(96×96, dpr=1.0, capped=false)',
      );
    });
  });
}
