import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/dictionary/oald_entry.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/oald_lookup_tool.dart';

/// The optional live probe for `lookup_oald`: the real OALD site, the real
/// parser, one word with a context.
///
/// **Skipped by default.** Run it only where the machine can actually reach
/// `www.oxfordlearnersdictionaries.com`:
///
///   flutter test test/live/oald_lookup_live_test.dart --dart-define=RUN_LIVE_OALD=1
///
/// On 2026-11-15 this environment was blocked by the site's Cloudflare bot
/// protection (HTTP 403, evidence in `OALD-TOOL-2026-11-15.md`), so the live run
/// was **not** executed here; the fixture tests are the executed evidence. The
/// tool treats a block page as an explicit error and never as a definition,
/// which is what makes leaving this probe opt-in safe.
void main() {
  const liveFlag = String.fromEnvironment('RUN_LIVE_OALD');

  test(
    'lookup_oald reads the real OALD page for observe with a context',
    () async {
      final cacheRoot = await Directory.systemTemp.createTemp('furnace_oald_live_');
      addTearDown(() async {
        if (cacheRoot.existsSync()) {
          await cacheRoot.delete(recursive: true);
        }
      });

      final tool = OaldLookupTool(
        // Write the live cache to a temp directory, never to the real
        // <appSupport> used by the running app.
        supportDirectory: () async => cacheRoot,
      );
      final result = await tool.run(const ToolInvocation(
        toolName: OaldLookupTool.toolName,
        action: OaldLookupTool.toolName,
        arguments: {
          'word': 'observe',
          'context': 'The police observed the crowd closely.',
        },
      ));

      if (!result.ok) {
        fail('live lookup failed (network/anti-bot?): ${result.error}');
      }
      final data = (result.modelResult! as Map).cast<String, Object?>();
      expect(data['source'], contains('Oxford'));
      expect(data['word'], 'observe');
      expect(data['part_of_speech'], isNotNull);
      expect((data['senses']! as List), isNotEmpty);
      expect(data['source_url'], startsWith('https://'));
      expect((data['source_url']! as String), contains(oaldHost));
      expect((data['source_url']! as String), contains('/definition/english/'));
      expect(data['content_rule'], contains('不得改写'));
      // The live page must also be readable by the cache: the record is written
      // for the next lookup.
      final cacheFiles = Directory(
        '${cacheRoot.path}${Platform.pathSeparator}'
        '${OaldLookupTool.cacheDirectoryName}',
      ).listSync();
      expect(cacheFiles.whereType<File>(), isNotEmpty);

      final selection =
          (data['sense_selection']! as Map).cast<String, Object?>();
      expect(selection['context_provided'], isTrue);
      // With a context, the tool either points at a sense or explicitly says the
      // page's wording did not overlap - both are acceptable; silently picking a
      // random sense is not.
      expect(
        selection['matched'] == true || selection['rule'] == 'no_match',
        isTrue,
        reason: 'unexpected sense_selection: $selection',
      );
    },
    skip: liveFlag.isEmpty
        ? 'set --dart-define=RUN_LIVE_OALD=1 to hit the real site'
        : false,
  );
}
