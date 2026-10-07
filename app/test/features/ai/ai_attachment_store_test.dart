// Images have to survive the thing that actually breaks them: a restart.
//
// The database stores a path and the bytes live on disk, so "it still works
// after reopening the conversation" is a claim about three things lining up -
// the `attachments` row, the file it points at, and the message it belongs to.
// These tests read the conversation back the way the app does on launch, and
// drive one real turn through the loop to check the bytes reach the provider.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/domain/vision_payload.dart';
import 'package:furnace/features/ai/infrastructure/ai_attachment_store.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

import 'image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AiRepository repository;
  late AiAttachmentStore store;
  late Directory supportDir;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    // A real temporary directory: the point of these tests is the filesystem
    // contract, so faking the file layer would test nothing.
    supportDir = Directory.systemTemp.createTempSync('furnace_ai_attach');
    store = AiAttachmentStore(
      repository: repository,
      supportDirectory: () async => supportDir,
    );
  });

  tearDown(() async {
    await db.close();
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  Future<PendingImage> savedImage() async {
    final raw = await paintPng(240, 160);
    final result = await const VisionImageEncoder().encode(raw);
    return store.save(result as VisionImageReady);
  }

  AgentLoop buildLoop(FakeModelAdapter adapter) => AgentLoop(
        adapter: adapter,
        registry: ToolRegistry([]),
        approval: const ApprovalEngine(mode: AiPermissionMode.auto),
        repository: repository,
        db: db,
        attachments: store,
      );

  Future<void> settle(AgentLoop loop, Future<void> Function() action) async {
    final sub = loop.states.listen((_) {});
    await action();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
  }

  group('storage', () {
    test('saving writes a real file under the support directory', () async {
      final pending = await savedImage();

      expect(pending.relPath, startsWith('ai_attachments/'));
      expect(pending.relPath, endsWith('.png'));
      expect(pending.mime, 'image/png');
      expect(pending.width, 240);
      final file = File(pending.absolutePath);
      expect(file.existsSync(), isTrue);
      expect(await store.readBytes(pending.relPath), isNotEmpty);
      // The path stored in the database is relative, so the row keeps working
      // when the app support directory itself moves (Windows app renames).
      expect(pending.relPath.contains(supportDir.path), isFalse);
    });

    test('a missing file reads as null instead of throwing', () async {
      final pending = await savedImage();
      File(pending.absolutePath).deleteSync();
      expect(await store.readBytes(pending.relPath), isNull);
      expect(await store.readBytes('ai_attachments/never-existed.png'), isNull);
    });

    test('removing the conversation removes its files', () async {
      final conversation = await repository.createConversation();
      final message = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: 'x',
      );
      final pending = await savedImage();
      await store.register(message.id, [pending]);

      await store.deleteConversationFiles(conversation.id);

      expect(File(pending.absolutePath).existsSync(), isFalse);
    });
  });

  group('persistence', () {
    test('an attached image is still resolvable after re-reading the chat',
        () async {
      final conversation = await repository.createConversation();
      final pending = await savedImage();
      final message = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '看这张图，帮我做成背诵卡片',
      );
      await store.register(message.id, [pending]);

      // Exactly what a restart does: drop everything in memory, read the
      // conversation back from the database.
      final rows = await repository.listMessages(conversation.id);
      final reread = await repository.listMessageAttachments(rows.single.id);

      expect(reread, hasLength(1));
      expect(reread.single.ownerType, AiRepository.attachmentOwnerType);
      expect(reread.single.ownerId, message.id);
      expect(reread.single.mime, 'image/png');

      final bytes = await store.readBytes(reread.single.relPath);
      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
      // The pixels are on disk, not in a row: the message content is the text
      // the user typed, with no base64 blob anywhere in the database.
      expect(rows.single.content, '看这张图，帮我做成背诵卡片');
    });

    test('the bubble gets absolute paths for every message', () async {
      final conversation = await repository.createConversation();
      final first = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '第一张',
      );
      final second = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '第二张',
      );
      final a = await savedImage();
      final b = await savedImage();
      await store.register(first.id, [a]);
      await store.register(second.id, [b]);

      final grouped = await store.imagesForConversation(conversation.id);

      expect(grouped.keys.toSet(), {first.id, second.id});
      expect(grouped[first.id]!.single.absolutePath, a.absolutePath);
      expect(File(grouped[second.id]!.single.absolutePath).existsSync(), isTrue);
      // Message order is preserved within a message, and a message without
      // images simply is not in the map.
      final third = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '没有图',
      );
      expect(
        (await store.imagesForConversation(conversation.id))
            .containsKey(third.id),
        isFalse,
      );
    });
  });

  group('what the model is sent', () {
    test('the attached image arrives as a data URL part', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('看到了。')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final pending = await savedImage();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '这张图上写的是什么？',
          images: [pending],
        ),
      );

      final sent = adapter.requests.single.messages;
      final user = sent.lastWhere((m) => m.role == 'user');
      final parts = (user.toJson()['content'] as List).cast<Map>();
      expect(parts.first, {'type': 'text', 'text': '这张图上写的是什么？'});
      expect(parts.last['type'], 'image_url');
      final url = (parts.last['image_url'] as Map)['url'] as String;
      expect(url, startsWith('data:image/png;base64,'));
      // The bytes on the wire are the bytes on disk.
      final stored = await store.readBytes(pending.relPath);
      expect(base64Decode(url.split(',').last), equals(stored));
    });

    test('an image with no text is still a complete message', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好的。')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final pending = await savedImage();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '   ',
          images: [pending],
        ),
      );

      final rows = await repository.listMessages(conversation.id);
      final storedUser =
          rows.firstWhere((m) => m.role == AiRepository.roleUser);
      expect(storedUser.content, isNull,
          reason: 'an empty string would become a stray empty text part');
      final user = adapter.requests.single.messages
          .lastWhere((m) => m.role == 'user');
      expect((user.toJson()['content'] as List), hasLength(1));
    });

    test('a later text-only turn still sends a plain string', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.answer('看到了。'),
        FakeModelAdapter.answer('不客气。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final pending = await savedImage();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '这是什么？',
          images: [pending],
        ),
      );
      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '谢谢',
        ),
      );

      final secondRequest = adapter.requests[1].messages;
      // The earlier image is still in the history (a follow-up must be able to
      // refer to it), and the newest user turn is untouched text.
      expect(secondRequest.last.content, '谢谢');
      expect(secondRequest.last.images, isEmpty);
      final withImage = secondRequest.where((m) => m.images.isNotEmpty);
      expect(withImage, hasLength(1));
      expect(withImage.single.content, '这是什么？');
    });

    test('an image whose file disappeared does not break the turn', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好的。')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final pending = await savedImage();
      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '先发一张',
          images: [pending],
        ),
      );
      // The user cleared the app's files, or the OS did.
      File(pending.absolutePath).deleteSync();
      adapter.requests.clear();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '再问一句',
        ),
      );

      expect(loop.state.error, isNull,
          reason: 'a lost picture is a smaller loss than a lost conversation');
      final history = adapter.requests.single.messages;
      expect(history.where((m) => m.images.isNotEmpty), isEmpty);
      // The text of the message that had a picture is still there.
      expect(
        history.any((m) => m.content == '先发一张'),
        isTrue,
      );
    });

    test('the loop refuses images when it has no attachment store', () async {
      // Unreachable in the running app (the provider always supplies one), but
      // silently dropping the user's photo would be the worst possible failure.
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('x')]);
      final loop = AgentLoop(
        adapter: adapter,
        registry: ToolRegistry([]),
        approval: const ApprovalEngine(mode: AiPermissionMode.auto),
        repository: repository,
        db: db,
      );
      final conversation = await repository.createConversation();
      final pending = await savedImage();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '看图',
          images: [pending],
        ),
      );

      expect(loop.state.error, isNotNull);
      expect(adapter.requests, isEmpty);
      expect(await repository.listMessages(conversation.id), isEmpty);
    });
  });
}
