/// Turning a picked photo into something the model can actually receive.
///
/// A phone photo of a textbook page is 3-12 MB of JPEG, and base64 adds another
/// third on top of that. Providers either reject a body that large or quietly
/// truncate the context, so every attached image goes through here first:
/// decode, downscale so the long side is at most [VisionImageEncoder.longSide],
/// re-encode as PNG, and refuse anything still over
/// [VisionImageEncoder.maxBytes] instead of sending half a page.
///
/// This is the only reason the AI feature touches `dart:ui`. The app has no
/// image package by design - `dart:ui` is already the decoder Flutter ships -
/// and the encode step has to be shared by the picker and the tests, so it
/// lives in one place rather than inside the widget.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'model_adapter.dart';

/// Why an image cannot be attached.
enum ImageFailureCode {
  /// Re-encoded fine, but still larger than the hard cap.
  tooLarge,

  /// `dart:ui` could not decode it: not an image, or a format the engine does
  /// not support.
  unreadable,
}

/// The outcome of encoding one picked image.
sealed class VisionImageResult {
  const VisionImageResult();
}

/// An image ready to send: downscaled, re-encoded, under the cap.
class VisionImageReady extends VisionImageResult {
  const VisionImageReady({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// The encoded PNG. Kept so the copy written to disk is byte-for-byte the
  /// copy that goes to the provider - two encodings of the same photo could
  /// differ, and then "what the user sees" and "what the model saw" would too.
  final Uint8List bytes;

  /// Always PNG; the encoder normalises every input format.
  String get mime => 'image/png';

  final int width;
  final int height;

  /// The `image_url` content part, i.e. what actually enters the request body.
  ChatImagePart toPart() =>
      ChatImagePart(mime: mime, base64: base64Encode(bytes));
}

/// An image that must not be sent, with the reason the user is told.
class VisionImageRejected extends VisionImageResult {
  const VisionImageRejected(this.code);
  final ImageFailureCode code;
}

/// Downscales and re-encodes attached images for the model.
///
/// The limits are constructor parameters rather than hard-coded constants so a
/// test can exercise the cap without manufacturing a 4 MB photo.
class VisionImageEncoder {
  const VisionImageEncoder({
    this.longSide = defaultLongSide,
    this.maxBytes = defaultMaxBytes,
  });

  /// Longest edge of what is sent. Large enough to read a page of notes, small
  /// enough that a page costs a fraction of the context window.
  static const int defaultLongSide = 1280;

  /// Hard cap on the ENCODED image. Over this the image is not sent at all:
  /// sending a truncated page would make the model answer confidently about
  /// content it never saw.
  static const int defaultMaxBytes = 4 * 1024 * 1024;

  final int longSide;
  final int maxBytes;

  /// Decodes, scales and re-encodes [raw] as PNG.
  ///
  /// Never throws: a file the engine cannot read is a user-facing answer
  /// ("this is not an image I can use"), not an exception that loses the turn.
  Future<VisionImageResult> encode(Uint8List raw) async {
    ui.Image? image;
    try {
      // Header-only read to learn which edge is long. Both target dimensions
      // cannot be passed to the codec: that would stretch a non-square photo
      // into a square box.
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final wide = descriptor.width >= descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      final codec = await ui.instantiateImageCodec(
        raw,
        targetWidth: wide ? longSide : null,
        targetHeight: wide ? null : longSide,
        // Without this an image smaller than [longSide] would be scaled UP,
        // which costs tokens and adds no detail.
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      codec.dispose();

      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return const VisionImageRejected(ImageFailureCode.unreadable);
      }
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length > maxBytes) {
        return const VisionImageRejected(ImageFailureCode.tooLarge);
      }
      return VisionImageReady(
        bytes: bytes,
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      // `dart:ui` surfaces an unsupported or corrupt file as an arbitrary
      // exception; every one of them means the same thing to the user.
      return const VisionImageRejected(ImageFailureCode.unreadable);
    } finally {
      image?.dispose();
    }
  }
}
