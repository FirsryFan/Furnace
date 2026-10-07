// What an attached photo actually becomes on the wire.
//
// Two failure modes are being guarded against here, and both are invisible in
// the UI until a real provider is involved:
//
//   * a text-only conversation quietly starting to send multimodal content -
//     the Chat Completion API accepts a plain string everywhere and a part list
//     only for vision models, so the shape must not change for text;
//   * a phone photo arriving at the provider as several megabytes of base64,
//     which is either refused or truncated, and truncation produces an answer
//     that looks confident about a page the model never fully saw.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/vision_payload.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/l10n/app_localizations_en.dart';
import 'package:furnace/l10n/app_localizations_zh.dart';

import 'image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('payload shape', () {
    test('a text-only message keeps the plain string shape', () {
      expect(
        const ChatMessage.user('看这张图').toJson(),
        {'role': 'user', 'content': '看这张图'},
      );
      // The other roles too: nothing about them may grow a part list.
      expect(
        const ChatMessage.system('你是助手').toJson(),
        {'role': 'system', 'content': '你是助手'},
      );
      expect(
        const ChatMessage.assistant(content: '好的').toJson(),
        {'role': 'assistant', 'content': '好的'},
      );
    });

    test('one image becomes a text part followed by a data URL part', () {
      const message = ChatMessage.user(
        '这是什么？',
        images: [ChatImagePart(mime: 'image/png', base64: 'QUJD')],
      );

      final parts = (message.toJson()['content'] as List).cast<Map>();
      expect(parts, hasLength(2));
      expect(parts.first, {'type': 'text', 'text': '这是什么？'});
      expect(parts.last['type'], 'image_url');
      expect(
        (parts.last['image_url'] as Map)['url'],
        'data:image/png;base64,QUJD',
        reason: 'the provider only accepts a data URL here, not a file path',
      );
    });

    test('an image-only message carries the image without an empty text part',
        () {
      const message = ChatMessage.user(
        '',
        images: [ChatImagePart(mime: 'image/png', base64: 'QUJD')],
      );
      final parts = message.toJson()['content'] as List;
      expect(parts, hasLength(1));
      expect((parts.single as Map)['type'], 'image_url');
    });
  });

  group('downscaling', () {
    test('the shipped limits are the ones the feature promises', () {
      expect(VisionImageEncoder.defaultLongSide, 1280);
      expect(VisionImageEncoder.defaultMaxBytes, 4 * 1024 * 1024);
    });

    test('a landscape photo comes out 1280 on the long side, aspect kept',
        () async {
      final raw = await paintPng(2600, 1400);
      final result = await const VisionImageEncoder().encode(raw);

      expect(result, isA<VisionImageReady>());
      final ready = result as VisionImageReady;
      expect(ready.width, 1280);
      expect(ready.height, lessThanOrEqualTo(1280));
      expect(ready.height, closeTo(1280 * 1400 / 2600, 1));
    });

    test('a tall photo is limited on its height instead', () async {
      // The case a naive "always pass targetWidth" implementation gets wrong:
      // the long side is the height here, and it must be the one capped.
      final raw = await paintPng(900, 2400);
      final ready =
          await const VisionImageEncoder().encode(raw) as VisionImageReady;
      expect(ready.height, 1280);
      expect(ready.width, lessThanOrEqualTo(1280));
      expect(ready.width, closeTo(1280 * 900 / 2400, 1));
    });

    test('an image smaller than the limit is not scaled up', () async {
      final raw = await paintPng(320, 200);
      final ready =
          await const VisionImageEncoder().encode(raw) as VisionImageReady;
      expect(ready.width, 320);
      expect(ready.height, 200,
          reason: 'upscaling costs tokens and invents no detail');
    });

    test('the encoded image is a real PNG that can be decoded again',
        () async {
      final raw = await paintPng(400, 300);
      final ready =
          await const VisionImageEncoder().encode(raw) as VisionImageReady;

      expect(ready.mime, 'image/png');
      // Round-trip: the base64 in the part decodes to exactly the stored bytes.
      final decoded = base64Decode(ready.toPart().base64);
      expect(decoded, equals(ready.bytes));
      expect(decoded.sublist(0, 8),
          equals(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          reason: 'a PNG signature: what the provider is told it is must be '
              'what it actually gets');
    });
  });

  group('refusals', () {
    test('an image over the cap is refused with the localized reason',
        () async {
      final raw = await paintPng(200, 200);
      // The cap is injected so the test does not need a 4 MB photo to prove
      // what happens at the limit.
      final result = await const VisionImageEncoder(maxBytes: 64).encode(raw);

      expect(result, isA<VisionImageRejected>());
      expect((result as VisionImageRejected).code, ImageFailureCode.tooLarge);

      // Both locales, because "do not send it" is only useful if the user is
      // told why in a language they read.
      final zh = aiImageFailureText(AppLocalizationsZh(), result.code);
      final en = aiImageFailureText(AppLocalizationsEn(), result.code);
      expect(zh, contains('4 MB'));
      expect(en, contains('4 MB'));
      expect(zh, isNot(equals(en)));
    });

    test('bytes that are not an image are refused, not thrown', () async {
      final result = await const VisionImageEncoder()
          .encode(Uint8List.fromList([1, 2, 3, 4, 5, 6]));

      expect(result, isA<VisionImageRejected>());
      expect(
          (result as VisionImageRejected).code, ImageFailureCode.unreadable);
      expect(
        aiImageFailureText(AppLocalizationsZh(), result.code),
        isNotEmpty,
      );
    });
  });
}
