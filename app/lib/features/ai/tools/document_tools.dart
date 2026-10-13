/// The AI's document output: "把这个整理成一份文档" becomes a file the user keeps.
///
/// The model can already write an answer; what it cannot do is hand the user
/// something that survives the conversation. This tool closes that gap the same
/// way `create_knowledge_cards` closed the photo flow: the model decides the
/// title and the body, the tool writes one file into the app's own documents
/// folder, and the chat shows the path so the user can copy it.
///
/// Three properties are deliberate, and each one is what makes the tool safe to
/// run automatically (docs/AI_DESIGN.md D13b):
///
///  * **the model never names a path.** It supplies a title, not a location. The
///    directory is `<appSupport>/documents` and the file name is derived from
///    the title by [sanitizeDocumentTitle]. A version that accepted a path would
///    be a general file-write primitive wearing a document's name.
///  * **the result is bounded.** The model gets the path, the byte count and a
///    one-line summary - never the body back, which it just wrote and which
///    would cost a second time.
///  * **undo removes exactly what this call created.** Only the relative path of
///    the new file goes into `ai_actions.after_json`, and
///    [deleteCreatedDocuments] looks nowhere but inside the documents folder.
///
/// DOCX/PDF export is **not** here: it needs a second library (python-docx is a
/// separate skill in this project), and a tool that silently produced a
/// `.docx`-named file containing markdown would be worse than no tool at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/ai_tool.dart';

/// Writes one markdown or plain-text document into the app's documents folder.
class CreateDocumentTool extends AiTool {
  CreateDocumentTool({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  /// Injected in tests, which must not touch the real app data directory. The
  /// same seam `AiAttachmentStore` and `SkillStore` use.
  final Future<Directory> Function() _supportDirectory;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'create_document';

  /// Subdirectory of the app support directory. Kept next to (not inside)
  /// `ai_attachments`, because these files are the *user's* output and deleting
  /// a conversation must not take them with it.
  static const String directoryName = 'documents';

  /// The only extensions this tool produces. Anything else is refused rather
  /// than guessed: `.docx`/`.pdf` cannot be written here, and a markdown body
  /// under one of those names would be a file that lies about itself.
  static const Set<String> formats = {'md', 'txt'};
  static const String defaultFormat = 'md';

  /// 512 KiB of UTF-8 text.
  ///
  /// Why a cap at all: the write, the ledger row and the tool result all happen
  /// inside one model turn, and a runaway loop must not be able to fill the
  /// disk one call at a time. Why 512 KiB: a document the user is meant to read
  /// is far below it (that is roughly a 250k-character Chinese document), while
  /// anything above it is a data dump, which belongs in neither a chat reply nor
  /// a hand-kept note.
  static const int maxContentBytes = 512 * 1024;

  /// Longest base name (title part) of the produced file.
  ///
  /// A title is truncated rather than refused, because losing the tail of a long
  /// title is a cosmetic loss while refusing the whole write loses the document.
  /// 80 leaves room for a `-999` collision suffix and the extension inside the
  /// 255-character limit a single Windows path component has.
  static const int maxBaseNameChars = 80;

  /// How many `-2`, `-3`, … attempts a collision gets before the call fails.
  static const int maxCollisionAttempts = 999;

  /// Names that mean a device, not a file, on Windows - whatever the extension
  /// is (`CON.md` is still the console). Appending `_` keeps the name readable
  /// instead of refusing the document, which the user cannot fix from the chat.
  static const Set<String> reservedNames = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', //
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9', //
  };

  @override
  String get name => toolName;

  @override
  String get description =>
      '把一段内容写成一份真正的文档文件（Markdown 或纯文本），保存在应用的文档目录里，'
      '并把完整路径返回给你。'
      '**用户要求"生成文档 / 写一份材料 / 导出成文件 / 整理成一份笔记 / 存下来"时用这个工具**：'
      '你自己组织好正文（标题、分节、列表都用 Markdown 写），一次调用只写一份文档。'
      'content 必须是完整的正文（Markdown 文本），不要写"见上文"；'
      'title 会变成文件名（会自动清理非法字符，重名时自动加 -2、-3）。'
      '正文上限 ${maxContentBytes ~/ 1024} KB，超长会被拒绝，请拆成多份文档。'
      'format 可选：$defaultFormat（Markdown，默认）/ txt。'
      '**本工具只能生成 .md/.txt，不生成 DOCX/PDF**，用户要那些格式时如实说明。'
      '写完以后把返回的 path 原样告诉用户；'
      '**不要声称已经"发送""上传""分享"或"发出"了任何东西**——文件只是写在这台设备的文档目录里。'
      '写错了可以让用户在这条对话里一键撤销（撤销会删掉这次生成的文件）。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': '文档标题（必填）：一句话说清这份文档是什么，会用作文件名',
          },
          'content': {
            'type': 'string',
            'description': '文档正文（必填）：完整的 Markdown 文本，就是用户以后打开文件看到的内容',
          },
          'format': {
            'type': 'string',
            'enum': formats.toList(),
            'description': '输出格式：$defaultFormat（Markdown，默认）/ txt（纯文本）',
          },
          'note': {
            'type': 'string',
            'description': '可选备注：一句话说明这份文档给谁、干什么用，会跟着结果显示在对话里',
          },
        },
        'required': <String>['title', 'content'],
      };

  /// A single-purpose tool: no `action` argument, so the risk is the tool's own.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// Writing one new file is undone by deleting that file, so the before-state
  /// ("the file did not exist") is exactly what the undo needs.
  @override
  bool reversibleFor(String action) => true;

  /// `dart:io` writing into the app support directory works on every platform
  /// this app ships for. It is not a script-backed skill, so the Windows-only
  /// rule of AI_DESIGN D10 does not apply.
  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final title = args.requireString('title');
      // The body is read raw instead of through `optString`, which trims:
      // the file has to contain exactly what the model wrote, and a trailing
      // newline is part of that. Only emptiness is judged on the trimmed text.
      final content = invocation.arguments['content']?.toString() ?? '';
      if (content.trim().isEmpty) {
        return const ToolResult.failure(
          '`content` 为空：这是一份要写进文件的文档正文，空文档不会生成。'
          '请把正文写进 content（Markdown 文本），或者不要调用这个工具。',
        );
      }
      final bytes = utf8.encode(content);
      if (bytes.length > maxContentBytes) {
        return ToolResult.failure(
          '文档正文过大：${bytes.length} 字节，超过上限 $maxContentBytes 字节'
          '（${maxContentBytes ~/ 1024} KB）。请拆成多份文档分别生成。',
        );
      }
      final format = (args.optString('format') ?? defaultFormat).toLowerCase();
      if (!formats.contains(format)) {
        return ToolResult.failure(
          '不支持的 format: $format（只支持 ${formats.join(' / ')}；'
          '本工具不生成 DOCX / PDF，需要那些格式请如实告诉用户当前做不到）',
        );
      }
      final base = sanitizeDocumentTitle(title);
      if (base.isEmpty) {
        return ToolResult.failure(
          '标题「$title」里没有可以用作文件名的字符，无法生成文件：请用正常的文字作为标题。',
        );
      }

      final directory = await documentsDirectory();
      final file = await _claim(directory, base, format);
      try {
        await file.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // A half-written document is worse than none: remove the file claimed
        // for this call, so a failed write leaves nothing behind for the next
        // call (or the user) to mistake for a document.
        try {
          await file.delete();
        } on FileSystemException {
          // Best effort: the original failure is what the caller reports.
        }
        rethrow;
      }

      final note = args.optString('note');
      return ToolResult(
        ok: true,
        // The path is in the summary on purpose: the chat card is the only
        // place the user sees it, and copying it is the one thing they may want
        // to do next. (No file-opening dependency exists here, by design.)
        summary: '已生成文档「$title」${note == null ? '' : '（$note）'}'
            '→ ${file.path}（${bytes.length} 字节）',
        modelResult: {
          'path': file.path,
          'file_name': p.basename(file.path),
          'bytes': bytes.length,
          'format': format,
          if (note != null) 'note': note,
        },
        // The relative path is the whole snapshot: undo only ever needs to know
        // *which* file this call created. Relative (POSIX-separated), like
        // `ai_attachments` rows, so the ledger survives the support directory
        // moving - which it does on Windows when the app is renamed.
        afterJson: jsonEncode({
          'version': 1,
          'rel_paths': ['$directoryName/${p.basename(file.path)}'],
        }),
      );
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes a result it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  /// The folder documents are written into, created on first use.
  Future<Directory> documentsDirectory() async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Creates `<base>.<ext>`, or `<base>-2.<ext>` / `<base>-3.<ext>` … when that
  /// name is taken.
  ///
  /// A numeric suffix rather than an overwrite, because a document the model
  /// writes today must not be able to destroy the document it wrote yesterday
  /// under the same title. `exclusive: true` is what makes that a property and
  /// not a hope: the file is created with CREATE_NEW semantics, so a name that
  /// appeared between two checks still cannot be clobbered.
  Future<File> _claim(Directory directory, String base, String extension) async {
    for (var attempt = 1; attempt <= maxCollisionAttempts; attempt++) {
      final name =
          attempt == 1 ? '$base.$extension' : '$base-$attempt.$extension';
      final candidate = File(p.join(directory.path, name));
      try {
        await candidate.create(exclusive: true);
        return candidate;
      } on FileSystemException {
        if (!candidate.existsSync()) {
          // Not a collision - the directory is gone or not writable. Retrying
          // 998 more names would only hide the real error.
          rethrow;
        }
      }
    }
    throw FileSystemException(
      '同名文档过多（已有 $maxCollisionAttempts 份），请换个标题',
      directory.path,
    );
  }
}

/// The characters Windows refuses in a file name, plus the ones that are merely
/// confusing everywhere else. Path separators are in here, which is what keeps
/// a title from ever naming a location instead of a file.
const String _forbiddenInFileName = '<>:"/\\|?*';

/// The base name (no extension) derived from a model-supplied title.
///
/// The rules, and why each one exists:
///
///  1. path separators and Windows' reserved punctuation become `_`, so `a/b`
///     stays one file inside the documents folder instead of becoming a
///     directory, and `a:b` does not fail to open;
///  2. every `..` collapses to `_`, so `../../evil` is a plain name and no
///     parent-directory reference can survive the sanitising;
///  3. control characters (including newlines) become `_`;
///  4. leading and trailing dots and spaces are dropped - Windows refuses a name
///     that ends in `.` or a space, and a leading dot would hide the file;
///  5. the length is capped at [CreateDocumentTool.maxBaseNameChars] (counted in
///     code points, so a cut cannot split an emoji in half);
///  6. a reserved DOS device name (`CON`, `NUL`, `COM1`…) gets `_` appended.
///
/// The result can be empty (`"..."`, `"///"`), which the caller refuses: quietly
/// inventing a name would hide from the user that their title was unusable.
String sanitizeDocumentTitle(String title) {
  final buffer = StringBuffer();
  for (final rune in title.runes) {
    final char = String.fromCharCode(rune);
    if (rune < 0x20 || rune == 0x7f || _forbiddenInFileName.contains(char)) {
      buffer.write('_');
    } else {
      buffer.write(char);
    }
  }

  var name = buffer.toString();
  while (name.contains('..')) {
    name = name.replaceAll('..', '_');
  }
  name = _trimEdges(name);
  if (name.runes.length > CreateDocumentTool.maxBaseNameChars) {
    name = String.fromCharCodes(
      name.runes.take(CreateDocumentTool.maxBaseNameChars),
    );
    // Truncation can expose a trailing dot or space that was inside the name
    // before, and Windows refuses those just the same.
    name = _trimEdges(name);
  }

  // The check is on the part before the first dot because Windows resolves
  // `CON.md` to the console device as well.
  final stem = name.split('.').first.toUpperCase();
  if (CreateDocumentTool.reservedNames.contains(stem)) {
    name = '${name}_';
  }
  return name;
}

/// Drops leading/trailing dots and whitespace, which Windows and "hidden file"
/// conventions both dislike.
String _trimEdges(String name) =>
    name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');

/// Deletes exactly the files one `create_document` call wrote.
///
/// Top-level and `dart:io`-only, like `deleteCreatedKnowledgeCards`: the agent
/// loop's undo path holds the ledger snapshot rather than the tool, and an undo
/// that cannot reach the file it created would leave the user with a document
/// they asked to be rid of.
///
/// The snapshot holds relative paths, so this resolves the support directory the
/// same way the tool did. Only [p.basename] of each entry is used, which is the
/// second lock on the same door: even a hand-edited snapshot cannot name a file
/// outside `<appSupport>/documents`.
///
/// Returns false when the snapshot has no path list - i.e. there is nothing this
/// function can be trusted to delete. A listed file that is already gone is not
/// a failure: the desired end state ("this document does not exist") holds.
Future<bool> deleteCreatedDocuments(
  Map<String, Object?> snapshot, {
  Future<Directory> Function()? supportDirectory,
}) async {
  final raw = snapshot['rel_paths'];
  if (raw is! List || raw.isEmpty) {
    return false;
  }
  final root = await (supportDirectory ?? getApplicationSupportDirectory)();
  final directory = Directory(p.join(root.path, CreateDocumentTool.directoryName));
  for (final entry in raw) {
    if (entry is! String || entry.isEmpty) {
      continue;
    }
    final file = File(p.join(directory.path, p.basename(entry)));
    if (!file.existsSync()) {
      continue;
    }
    try {
      await file.delete();
    } on FileSystemException {
      // One undeletable file (open in another program, say) must not stop the
      // rest of the undo; the user can delete the leftover by hand.
    }
  }
  return true;
}
