// The AI's document output: "把这个整理成一份文档" must become a file the user
// can keep, and must never become a way to write anywhere on the disk.
//
// This file covers the tool and its undo helper, which are pure `dart:io`
// (no database, so it runs even while the data layer is being changed). The
// registry entry and the agent-loop undo switch are in
// `document_tools_loop_test.dart`.
//
// The claims worth testing are the ones that decide whether the user ends up
// with a usable file and nothing broken:
//
//   * the bytes on disk are exactly the model's content, and the reported size
//     is that file's size;
//   * a hostile title is sanitised into a name inside the documents folder
//     (`../../evil`, `a/b`, `CON`, a 200-character title), never refused and
//     never allowed to escape;
//   * a collision adds a numeric suffix instead of overwriting yesterday's
//     document;
//   * empty content, oversized content, an unsupported format and an unusable
//     title are refused with distinct, readable messages and no file at all;
//   * undo deletes exactly the created file and leaves the rest of the folder
//     alone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/document_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory supportDir;
  late Directory documentsDir;
  late CreateDocumentTool tool;

  setUp(() {
    // A real temp directory, not a fake file system: the thing under test *is*
    // the interaction with the disk (name collisions, exclusive creation).
    supportDir = Directory.systemTemp.createTempSync('furnace_documents_');
    documentsDir =
        Directory(p.join(supportDir.path, CreateDocumentTool.directoryName));
    tool = CreateDocumentTool(supportDirectory: () async => supportDir);
  });

  tearDown(() {
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: CreateDocumentTool.toolName,
        action: CreateDocumentTool.toolName,
        arguments: args,
      );

  List<File> filesIn(Directory dir) =>
      dir.existsSync() ? dir.listSync().whereType<File>().toList() : const [];

  String pathOf(ToolResult result) =>
      (result.modelResult! as Map)['path'] as String;

  int bytesOf(ToolResult result) =>
      (result.modelResult! as Map)['bytes'] as int;

  group('writing a document', () {
    test('the file holds exactly the given content and the size is reported',
        () async {
      const content = '# 光合作用\n\n光反应在类囊体薄膜上进行。\n';
      final result = await tool.run(invoke({
        'title': '光合作用的光反应',
        'content': content,
        'note': '课上整理',
      }));

      expect(result.ok, isTrue);
      final file = File(pathOf(result));
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), content,
          reason: 'the body is written raw: no trim, no reflow');
      expect(p.basename(file.path), '光合作用的光反应.md');
      expect(p.dirname(file.path), documentsDir.path);
      expect(bytesOf(result), utf8.encode(content).length);
      expect((result.modelResult! as Map)['format'],
          CreateDocumentTool.defaultFormat);

      // The user copies the path out of the chat card, so it has to be there.
      expect(result.summary, contains(file.path));
      expect(result.summary, contains('${utf8.encode(content).length} 字节'));
      expect(result.summary, contains('课上整理'));
      // ... and the model must not be handed the document back.
      expect(result.modelResult.toString(), isNot(contains('类囊体薄膜')));
      expect(result.isUndoable, isTrue);
      expect(result.afterJson, isNotNull);
    });

    test('format=txt changes the extension and nothing else', () async {
      final result = await tool.run(invoke({
        'title': '纯文本',
        'content': '正文',
        'format': 'txt',
      }));

      expect(result.ok, isTrue);
      expect(p.basename(pathOf(result)), '纯文本.txt');
      expect(await File(pathOf(result)).readAsString(), '正文');
    });

    test('a trailing newline survives, because it is part of the content',
        () async {
      final result = await tool.run(invoke({
        'title': '换行',
        'content': 'a\n\n',
      }));

      expect(await File(pathOf(result)).readAsString(), 'a\n\n');
      expect(bytesOf(result), 3);
    });

    test('a format in the wrong case is still accepted', () async {
      // The model writes 'MD' as easily as 'md'; the extension is what matters.
      final result = await tool.run(invoke({
        'title': '大写格式',
        'content': 'x',
        'format': 'MD',
      }));

      expect(result.ok, isTrue);
      expect(p.basename(pathOf(result)), '大写格式.md');
    });
  });

  group('hostile titles', () {
    test('path separators and parent references stay inside the folder',
        () async {
      const titles = [
        '../../evil',
        'a/b',
        r'..\..\evil',
        'a:b|c?d*e',
        'with   内部空格',
      ];

      for (final title in titles) {
        final result = await tool.run(invoke({'title': title, 'content': 'x'}));
        expect(result.ok, isTrue,
            reason: '«$title» should be sanitised, not refused');

        final file = File(pathOf(result));
        expect(p.dirname(file.path), documentsDir.path,
            reason: '«$title» must not name a location');
        final name = p.basename(file.path);
        expect(name, isNot(contains('/')));
        expect(name, isNot(contains(r'\')));
        expect(name, isNot(contains('..')));
        expect(p.basenameWithoutExtension(name), isNotEmpty);
      }

      expect(filesIn(documentsDir), hasLength(titles.length));
      expect(filesIn(supportDir), isEmpty,
          reason: 'nothing may be written next to the documents folder');
    });

    test('a Windows device name gets a suffix instead of being unusable',
        () async {
      final result = await tool.run(invoke({'title': 'CON', 'content': 'x'}));

      expect(result.ok, isTrue);
      final name = p.basename(pathOf(result));
      expect(p.basenameWithoutExtension(name).toUpperCase(), isNot('CON'));
      expect(name, 'CON_.md');
    });

    test('an over-long title is truncated, not refused', () async {
      final result = await tool.run(invoke({
        'title': List.filled(200, '长').join(),
        'content': 'x',
      }));

      expect(result.ok, isTrue);
      final base = p.basenameWithoutExtension(p.basename(pathOf(result)));
      expect(base.runes.length, CreateDocumentTool.maxBaseNameChars);
    });

    test('truncation cannot split a surrogate pair', () async {
      // 80 emoji is exactly the cap in code points; a cut made in UTF-16 code
      // units would leave half a surrogate behind, which the file system
      // refuses and which would corrupt the name.
      final result = await tool.run(invoke({
        'title': List.filled(200, '🙂').join(),
        'content': 'x',
      }));

      expect(result.ok, isTrue);
      final name = p.basename(pathOf(result));
      expect(p.basenameWithoutExtension(name), List.filled(80, '🙂').join());
    });

    test('a title that sanitises to nothing is refused with a reason',
        () async {
      final result = await tool.run(invoke({'title': '.', 'content': 'x'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('文件名'));
      expect(filesIn(documentsDir), isEmpty);
    });
  });

  group('collisions', () {
    test('a second document gets its own file and leaves the first intact',
        () async {
      final first = await tool.run(invoke({'title': '同名', 'content': '第一版'}));
      final second = await tool.run(invoke({'title': '同名', 'content': '第二版'}));

      expect(second.ok, isTrue);
      expect(pathOf(second), isNot(pathOf(first)));
      expect(p.basename(pathOf(second)), '同名-2.md');
      expect(await File(pathOf(first)).readAsString(), '第一版',
          reason: 'the earlier document must never be silently overwritten');
      expect(await File(pathOf(second)).readAsString(), '第二版');
      expect(filesIn(documentsDir), hasLength(2));

      final third =
          await tool.run(invoke({'title': '同名', 'content': '第三版'}));
      expect(p.basename(pathOf(third)), '同名-3.md');
      expect(filesIn(documentsDir), hasLength(3));
    });
  });

  group('refusals', () {
    test('empty content is refused, and differently from an oversized one',
        () async {
      final empty = await tool.run(invoke({'title': '空', 'content': ''}));
      final blank =
          await tool.run(invoke({'title': '空', 'content': '  \n\t '}));
      final missing = await tool.run(invoke({'title': '空'}));
      final oversized = await tool.run(invoke({
        'title': '太大',
        'content': 'x' * (CreateDocumentTool.maxContentBytes + 1),
      }));

      expect(empty.ok, isFalse);
      expect(empty.error, contains('为空'));
      expect(blank.ok, isFalse);
      expect(blank.error, contains('为空'));
      expect(missing.ok, isFalse);
      expect(missing.error, contains('为空'));

      expect(oversized.ok, isFalse);
      expect(oversized.error, contains('过大'));
      expect(oversized.error, contains('${CreateDocumentTool.maxContentBytes}'),
          reason: 'the model must be told the actual limit it broke');
      expect(oversized.error, isNot(empty.error),
          reason: '"too long" and "too short" are different fixes');
      expect(filesIn(documentsDir), isEmpty);
    });

    test('content of exactly the cap is accepted', () async {
      final result = await tool.run(invoke({
        'title': '刚好到上限',
        'content': 'x' * CreateDocumentTool.maxContentBytes,
      }));

      expect(result.ok, isTrue);
      expect(bytesOf(result), CreateDocumentTool.maxContentBytes);
    });

    test('an unsupported format is refused and names what is allowed',
        () async {
      for (final format in ['pdf', 'docx', 'rtf', 'mdx']) {
        final result = await tool.run(
          invoke({'title': '格式', 'content': 'x', 'format': format}),
        );
        expect(result.ok, isFalse, reason: '«$format» is not supported');
        expect(result.error, contains('md'));
        expect(result.error, contains('txt'));
      }
      expect(filesIn(documentsDir), isEmpty);
    });

    test('a missing title is a readable failure that writes nothing', () async {
      final result = await tool.run(invoke({'content': 'x'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('title'));
      expect(filesIn(documentsDir), isEmpty);
    });
  });

  group('undo of the files this call created', () {
    test('it deletes the created file and leaves its neighbour alone',
        () async {
      final result = await tool.run(invoke({'title': '要撤销', 'content': '内容'}));
      final created = File(pathOf(result));
      documentsDir.createSync(recursive: true);
      final neighbour = File(p.join(documentsDir.path, '别动我.md'))
        ..writeAsStringSync('用户自己的文件');

      final snapshot =
          (jsonDecode(result.afterJson!) as Map).cast<String, Object?>();
      final undone = await deleteCreatedDocuments(
        snapshot,
        supportDirectory: () async => supportDir,
      );

      expect(undone, isTrue);
      expect(created.existsSync(), isFalse);
      expect(await neighbour.readAsString(), '用户自己的文件');
      expect(filesIn(documentsDir), hasLength(1));
    });

    test('a shapeless snapshot is refused rather than guessed at', () async {
      Future<bool> undo(Map<String, Object?> snapshot) =>
          deleteCreatedDocuments(
            snapshot,
            supportDirectory: () async => supportDir,
          );

      expect(await undo(const {}), isFalse);
      expect(await undo(const {'rel_paths': <String>[]}), isFalse);
      expect(await undo(const {'rel_paths': 'documents/x.md'}), isFalse);
      expect(await undo(const {'version': 1}), isFalse);
    });

    test('a snapshot cannot name a file outside the documents folder',
        () async {
      // The snapshot is written by the tool, but an undo that trusted it
      // blindly would be one hand-edited ledger row away from deleting
      // arbitrary files, so only the base name of each entry is used.
      final outside = File(p.join(supportDir.path, 'outside.md'))
        ..writeAsStringSync('keep me');
      documentsDir.createSync(recursive: true);
      final inside = File(p.join(documentsDir.path, 'outside.md'))
        ..writeAsStringSync('created by the tool');

      final undone = await deleteCreatedDocuments(
        const {
          'version': 1,
          'rel_paths': ['../outside.md'],
        },
        supportDirectory: () async => supportDir,
      );

      expect(undone, isTrue);
      expect(inside.existsSync(), isFalse);
      expect(await outside.readAsString(), 'keep me');
    });

    test('a file that is already gone is not a failure', () async {
      // The user may have deleted the document by hand; "this document does not
      // exist" is the state undo was asked for, so it is not an error.
      final result = await tool.run(invoke({'title': '已经删了', 'content': 'x'}));
      await File(pathOf(result)).delete();

      final undone = await deleteCreatedDocuments(
        (jsonDecode(result.afterJson!) as Map).cast<String, Object?>(),
        supportDirectory: () async => supportDir,
      );

      expect(undone, isTrue);
    });
  });
}
