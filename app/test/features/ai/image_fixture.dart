/// Synthetic images for the vision tests.
///
/// The input is painted in-process with `dart:ui` rather than checked in as a
/// binary fixture: a repo that carries a 3 MB photo to test a size cap ages
/// badly, and a generated image can be made exactly as large as the case needs.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// Paints a [width] x [height] PNG, returning its bytes.
///
/// The pattern matters: a flat colour compresses to almost nothing, so a
/// downscale test would not be measuring real encoded size.
Future<Uint8List> paintPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  final paint = ui.Paint()..color = const ui.Color(0xFF336699);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  paint.color = const ui.Color(0xFFFFCC00);
  for (var i = 0; i < 120; i++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(
        (i * 37 % width).toDouble(),
        (i * 53 % height).toDouble(),
        width / 12,
        height / 12,
      ),
      paint,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  if (data == null) {
    throw StateError('could not encode the painted test image');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
