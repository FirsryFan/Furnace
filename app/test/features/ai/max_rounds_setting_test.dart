import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// The agent loop's tool-call budget as a **setting**: it is stored, it comes
/// back out of the repository, it is pinned to a sane range, and the number the
/// loop actually runs with is the one the user chose.
///
/// The last claim is the one worth being pedantic about. "It is stored" and "it
/// reaches the loop" are different facts: a setting that persists but is never
/// passed to [AgentLoop] looks perfect in a settings test and does nothing.
/// These tests therefore read the value back through the same providers the
/// running app uses, and then let a model that never stops run into the cap.
void main() {
  late AppDatabase db;
  late AiRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// A container wired the way the app is: the database and the network adapter
  /// replaced, everything else (configuration reader included) real.
  Future<ProviderContainer> containerWith(FakeModelAdapter adapter) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        modelAdapterProvider.overrideWithValue(adapter),
      ],
    );
    addTearDown(container.dispose);
    // The configuration is a FutureProvider; the loop reads its value, so it
    // has to have resolved before the loop exists at all.
    await container.read(aiConfigProvider.future);
    return container;
  }

  group('the stored budget', () {
    test('the shipped default is 8, inside the offered range', () async {
      expect(AiConfig.defaultMaxRounds, 8);
      expect(AiConfig.minMaxRounds, 1);
      expect(AiConfig.maxMaxRounds, 20);
      expect(AiConfig.minMaxRounds,
          lessThanOrEqualTo(AiConfig.defaultMaxRounds));
      expect(AiConfig.defaultMaxRounds,
          lessThanOrEqualTo(AiConfig.maxMaxRounds));
    });

    test('a database with no settings row reports the default', () async {
      // The shape of an upgraded pre-AI install: no row at all. It must read as
      // the shipped budget rather than as zero rounds.
      expect((await repository.getConfig()).maxRounds, 8);
    });

    test('a chosen budget round-trips through the repository', () async {
      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test', maxRounds: 15),
        fallbackLanguage: 'zh',
      );

      expect((await repository.getConfig()).maxRounds, 15);
      // Stored, not merely recomputed on read: the column is what a restart,
      // an export or a second read path sees.
      final row = (await db.select(db.localSettings).get()).single;
      expect(row.aiMaxRounds, 15);
    });

    test('saving a budget leaves the rest of the settings row alone', () async {
      // The settings row is shared with language/theme/profile, and this save
      // must not reset them - the same promise the other AI columns make.
      await db.into(db.localSettings).insert(
            LocalSettingsCompanion.insert(
              id: const Value(1),
              language: const Value('en'),
              createdAt: 1,
              updatedAt: 1,
            ),
          );

      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test', maxRounds: 12),
        fallbackLanguage: 'zh',
      );

      final row = (await db.select(db.localSettings).get()).single;
      expect(row.language, 'en');
      expect(row.aiMaxRounds, 12);
    });

    test('a stored value outside the range is clamped, not obeyed', () async {
      // A future build, a hand-edited file or a bad migration can put anything
      // in the column. One message must still not be able to spend an unbounded
      // number of paid calls, and zero rounds would answer nothing at all.
      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test'),
        fallbackLanguage: 'zh',
      );
      Future<void> writeRaw(int? stored) async {
        await (db.update(db.localSettings)..where((t) => t.id.equals(1)))
            .write(LocalSettingsCompanion(aiMaxRounds: Value(stored)));
      }

      await writeRaw(999);
      expect((await repository.getConfig()).maxRounds,
          AiConfig.maxMaxRounds);
      await writeRaw(0);
      expect((await repository.getConfig()).maxRounds, AiConfig.minMaxRounds);
      await writeRaw(-3);
      expect((await repository.getConfig()).maxRounds, AiConfig.minMaxRounds);
      await writeRaw(null);
      expect((await repository.getConfig()).maxRounds,
          AiConfig.defaultMaxRounds,
          reason: 'NULL means "never chosen"');
    });

    test('an out-of-range value cannot be written in the first place', () async {
      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test', maxRounds: 99),
        fallbackLanguage: 'zh',
      );
      final row = (await db.select(db.localSettings).get()).single;
      expect(row.aiMaxRounds, AiConfig.maxMaxRounds,
          reason: 'the save path clamps, so the file never holds a bad budget');
    });
  });

  group('the loop the app builds', () {
    test('gets the configured budget, not the default', () async {
      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test', maxRounds: 3),
        fallbackLanguage: 'zh',
      );
      final container = await containerWith(FakeModelAdapter(const []));
      final conversation = await repository.createConversation();

      final loop = container.read(agentLoopProvider(conversation.id));

      expect(loop, isNotNull, reason: 'a configured key must produce a loop');
      expect(loop!.maxRounds, 3);
      expect(loop.maxRounds, isNot(AiConfig.defaultMaxRounds),
          reason: 'the default must not be what the loop runs with');
    });

    test('stops a model that never stops at the configured budget', () async {
      const budget = 2;
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          // Auto mode, so a read tool runs without an approval: the cap is then
          // the only thing that can stop the loop.
          permissionMode: AiPermissionMode.auto,
          maxRounds: budget,
        ),
        fallbackLanguage: 'zh',
      );
      // Twenty rounds are available to the model; only [budget] may happen.
      final adapter = FakeModelAdapter([
        for (var i = 0; i < 20; i++)
          FakeModelAdapter.callTool(
            'query_tasks',
            {'limit': 1},
            id: 'call_$i',
          ),
      ]);
      final container = await containerWith(adapter);
      final conversation = await repository.createConversation();
      final loop = container.read(agentLoopProvider(conversation.id))!;

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '一直查下去',
      );

      expect(adapter.requests, hasLength(budget),
          reason: 'exactly one model call per allowed round');
      expect(loop.state.rounds, budget);
      expect(loop.state.generating, isFalse);
      // The stop is explained with the number that caused it, rather than being
      // a silent truncation.
      expect(loop.state.error, contains('$budget 轮'));
    });

    test('a one-round budget still answers once instead of refusing', () async {
      // The lower end of the slider is a real setting, not a broken one: the
      // first round runs, and the cap stops it after that.
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          permissionMode: AiPermissionMode.auto,
          maxRounds: AiConfig.minMaxRounds,
        ),
        fallbackLanguage: 'zh',
      );
      final adapter = FakeModelAdapter([
        FakeModelAdapter.answer('只回答一次'),
      ]);
      final container = await containerWith(adapter);
      final conversation = await repository.createConversation();
      final loop = container.read(agentLoopProvider(conversation.id))!;

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '在吗',
      );

      expect(adapter.requests, hasLength(1));
      expect(loop.state.rounds, 1);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.last.content, '只回答一次');
    });
  });
}
