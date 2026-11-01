import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';

/// Platform capability gating ("平台隔离从口头变成代码"):
///
///  * a tool declares its platforms on itself (`supportedPlatforms`), defaulting
///    to both shipped targets;
///  * the registry applies that declaration uniformly and keeps the legacy
///    `availableOnCurrentPlatform` bit for the running process;
///  * the applied result is exportable as stable, l10n-free data.
void main() {
  group('AiToolPlatform declaration', () {
    test('ids are stable machine values and round-trip', () {
      expect(AiToolPlatform.android.id, 'android');
      expect(AiToolPlatform.windows.id, 'windows');
      expect(AiToolPlatform.fromId('android'), AiToolPlatform.android);
      expect(AiToolPlatform.fromId('windows'), AiToolPlatform.windows);
      expect(AiToolPlatform.fromId('linux'), isNull);
      expect(
          AiToolPlatform.all, {AiToolPlatform.android, AiToolPlatform.windows});
    });

    test('a tool that declares nothing is offered on both shipped platforms',
        () {
      final tool = _FakeTool('both');
      expect(tool.supportedPlatforms, AiToolPlatform.all);

      final registry = ToolRegistry([tool]);
      expect(registry.forPlatform(AiToolPlatform.android), [tool]);
      expect(registry.forPlatform(AiToolPlatform.windows), [tool]);
      expect(registry.forCurrentPlatform, [tool]);
      expect(registry.unavailableHere, isEmpty);
    });
  });

  group('registry filtering', () {
    test('a Windows-only tool is offered on Windows and absent on Android', () {
      final both = _FakeTool('both');
      final windowsOnly = _FakeTool(
        'windows_only',
        platforms: {AiToolPlatform.windows},
      );
      final registry = ToolRegistry([both, windowsOnly]);

      expect(
        registry.forPlatform(AiToolPlatform.windows),
        [both, windowsOnly],
      );
      expect(registry.forPlatform(AiToolPlatform.android), [both]);
    });

    test('forCurrentPlatform mirrors the running platform', () {
      final both = _FakeTool('both');
      final androidOnly = _FakeTool(
        'android_only',
        platforms: {AiToolPlatform.android},
      );
      final registry = ToolRegistry([both, androidOnly]);

      // An Android-only tool is absent on every desktop host and offered on
      // Android; [both] is the only eligible tool either way.
      expect(registry.forCurrentPlatform, [both]);
      expect(registry.unavailableHere, [androidOnly]);
    });

    test(
        'the legacy availability bit still hides a tool on the running platform',
        () {
      final legacyOff = _FakeTool('legacy_off', legacyAvailable: false);
      final registry = ToolRegistry([legacyOff]);

      expect(registry.forCurrentPlatform, isEmpty);
      expect(registry.unavailableHere, [legacyOff]);
    });

    test('the legacy bit is not applied to other platforms', () {
      // Documented compatibility semantics: that getter has always meant "this
      // process", so it cannot answer for another platform.
      final legacyOff = _FakeTool('legacy_off', legacyAvailable: false);
      final registry = ToolRegistry([legacyOff]);

      for (final platform in AiToolPlatform.values) {
        if (platform == ToolRegistry.currentPlatform) {
          continue;
        }
        expect(registry.forPlatform(platform), [legacyOff]);
      }
    });
  });

  group('capability description export', () {
    test('exports stable ids, registration order and the restriction flag', () {
      final both = _FakeTool('both');
      final windowsOnly = _FakeTool(
        'windows_only',
        platforms: {AiToolPlatform.windows},
      );
      final registry = ToolRegistry([both, windowsOnly]);

      expect(registry.describePlatformCapabilities(), [
        {
          'tool': 'both',
          'supported_platforms': ['android', 'windows'],
          'restricted_by_platform': false,
          'offered_here': true,
        },
        {
          'tool': 'windows_only',
          'supported_platforms': ['windows'],
          'restricted_by_platform': true,
          'offered_here': !Platform.isAndroid,
        },
      ]);
    });
  });

  group('real app registry (behaviour unchanged)', () {
    late AppDatabase db;
    late ToolRegistry registry;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('all 29 built-in tools are offered on both shipped platforms', () {
      expect(registry.all, hasLength(29));
      expect(registry.forPlatform(AiToolPlatform.android), hasLength(29));
      expect(registry.forPlatform(AiToolPlatform.windows), hasLength(29));
      expect(registry.forCurrentPlatform, hasLength(29));
      expect(registry.unavailableHere, isEmpty);
    });

    test('the exported matrix covers every tool with the same declaration', () {
      final manifest = registry.describePlatformCapabilities();
      expect(manifest, hasLength(registry.all.length));
      for (final entry in manifest) {
        expect(entry['supported_platforms'], ['android', 'windows']);
        expect(entry['restricted_by_platform'], isFalse);
        expect(entry['offered_here'], isTrue);
      }
      // The provider-facing declarations stay exactly the filtered list, so
      // gating and model specs cannot drift apart.
      expect(
        registry.modelSpecs.map((spec) => spec.name),
        registry.forCurrentPlatform.map((tool) => tool.name),
      );
    });
  });
}

/// Minimal tool that exists only to exercise the platform declaration.
class _FakeTool extends AiTool {
  _FakeTool(
    this._name, {
    Set<AiToolPlatform>? platforms,
    this.legacyAvailable = true,
  }) : _supportedPlatforms = platforms ?? AiToolPlatform.all.toSet();

  final String _name;
  final Set<AiToolPlatform> _supportedPlatforms;
  final bool legacyAvailable;

  @override
  String get name => _name;

  @override
  String get description => 'fake tool used by platform capability tests';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  Set<AiToolPlatform> get supportedPlatforms => _supportedPlatforms;

  @override
  bool get availableOnCurrentPlatform => legacyAvailable;

  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async =>
      const ToolResult(ok: true, summary: 'ok');
}
