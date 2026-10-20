/// 缩略图解码尺寸：把「显示尺寸 + 设备像素比」换算成 Image.memory /
/// Image.file 的 cacheWidth / cacheHeight。
///
/// 为什么需要它：题目配图列表里每个格子只显示 48-96 逻辑像素，但
/// Image.memory(bytes) 默认按原始像素解码——一张 4000x3000 的手机照片
/// 解码后约 48 MB，一屏十几张就是几百 MB，滚动会卡、低端机会被系统杀。
/// 传 cacheWidth/cacheHeight 让 Flutter 在**解码阶段**就缩到显示尺寸
/// （docs/QUESTION_BANK_DESIGN.md §11.2 记的「48x48 是解码整图后缩放」）。
///
/// 这是纯逻辑：不 import Flutter、不读文件、不猜原图尺寸。原图比目标小
/// 时多算出来的 cache 尺寸没有副作用（解码器不会放大），所以这里不做
/// 「先探测原图再决定」——那会把一次同步计算变成一次 IO。
library;

import 'dart:math' as math;

/// 一次缩略图解码的尺寸建议。
///
/// cacheWidth / cacheHeight 是**解码后的像素尺寸**（不是逻辑像素），
/// 直接传给 Image.memory(cacheWidth:, cacheHeight:)。
class ThumbnailDecodeSpec {
  const ThumbnailDecodeSpec({
    required this.cacheWidth,
    required this.cacheHeight,
    required this.devicePixelRatio,
    required this.capped,
  });

  /// 解码宽度（像素）。isEmpty 为 true 时是 0——**不要**把它传给 Image。
  final int cacheWidth;

  /// 解码高度（像素）。isEmpty 为 true 时是 0。
  final int cacheHeight;

  /// 实际参与计算的设备像素比（非法输入已归一成 1.0）。
  final double devicePixelRatio;

  /// 是否被 thumbnailDecodeSpec 的 maxDecodeSide 压过。
  final bool capped;

  /// 输入尺寸非法（宽或高 <= 0）时为 true：调用方应**不传** cache 参数
  /// （Flutter 的 Image 断言 cacheWidth/cacheHeight 必须 > 0）。
  bool get isEmpty => cacheWidth <= 0 || cacheHeight <= 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'cacheWidth': cacheWidth,
        'cacheHeight': cacheHeight,
        'devicePixelRatio': devicePixelRatio,
        'capped': capped,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailDecodeSpec &&
          other.cacheWidth == cacheWidth &&
          other.cacheHeight == cacheHeight &&
          other.devicePixelRatio == devicePixelRatio &&
          other.capped == capped;

  @override
  int get hashCode =>
      Object.hash(cacheWidth, cacheHeight, devicePixelRatio, capped);

  @override
  String toString() => 'ThumbnailDecodeSpec($cacheWidth×$cacheHeight, '
      'dpr=$devicePixelRatio, capped=$capped)';
}

/// 设备像素比的合理上限：有测试/假数据会传 1e300 之类的值，直接乘会把
/// int 撑爆；真实屏幕没有超过 16 的（4K 手机 + 系统缩放也远低于它）。
const double _kMaxDevicePixelRatio = 16.0;

/// 按显示尺寸与设备像素比算缩略图解码尺寸。
///
/// * logicalWidth / logicalHeight 是布局尺寸（逻辑像素），任何一边
///   <= 0 返回 ThumbnailDecodeSpec.isEmpty == true 的空 spec。
/// * devicePixelRatio 非有限、<= 0 时按 1.0；超过 16 按 16（防溢出）。
/// * 先乘像素比再 **向上取整**：宁可多解一行像素，也别让缩略图被拉糊。
/// * maxDecodeSide > 0 时长边压到它（保持宽高比，两边至少 1）；
///   <= 0 表示不设上限。
ThumbnailDecodeSpec thumbnailDecodeSpec({
  required int logicalWidth,
  required int logicalHeight,
  double devicePixelRatio = 1.0,
  int maxDecodeSide = 1024,
}) {
  final dpr = _normalizeDevicePixelRatio(devicePixelRatio);
  if (logicalWidth <= 0 || logicalHeight <= 0) {
    return ThumbnailDecodeSpec(
      cacheWidth: 0,
      cacheHeight: 0,
      devicePixelRatio: dpr,
      capped: false,
    );
  }
  var cacheWidth = (logicalWidth * dpr).ceil();
  var cacheHeight = (logicalHeight * dpr).ceil();
  var capped = false;
  if (maxDecodeSide > 0) {
    final longest = math.max(cacheWidth, cacheHeight);
    if (longest > maxDecodeSide) {
      final scale = maxDecodeSide / longest;
      cacheWidth = math.max(1, (cacheWidth * scale).round());
      cacheHeight = math.max(1, (cacheHeight * scale).round());
      capped = true;
    }
  }
  return ThumbnailDecodeSpec(
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    devicePixelRatio: dpr,
    capped: capped,
  );
}

double _normalizeDevicePixelRatio(double raw) {
  if (!raw.isFinite || raw <= 0) {
    return 1.0;
  }
  return raw > _kMaxDevicePixelRatio ? _kMaxDevicePixelRatio : raw;
}
