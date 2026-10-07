/// Where an attached image lives once the user has picked it.
///
/// Two things have to stay in step: the file on disk and the `attachments` row
/// that points at it. Keeping both behind one class is what makes that possible
/// - the database stores a path relative to the app support directory (so the
/// row survives the directory moving, which it does on Windows when the app is
/// renamed), and this class is the only place that knows how to turn the two
/// into bytes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/ids.dart';
import '../../../data/repositories/ai_repository.dart';
import '../domain/model_adapter.dart';
import '../domain/vision_payload.dart';

/// One image the user attached, already written to disk and waiting for the
/// message id that will own it.
///
/// The database row cannot be written at pick time: its `owner_id` is the
/// message id, and the message does not exist until the user hits send. The
/// file, on the other hand, has to exist before the thumbnail can be shown.
class PendingImage {
  const PendingImage({
    required this.relPath,
    required this.absolutePath,
    required this.mime,
    required this.width,
    required this.height,
  });

  /// Path relative to the app support directory, POSIX-separated so the row
  /// means the same thing on Windows and Android. This is what is persisted.
  final String relPath;

  /// Absolute path, for rendering the thumbnail before the message is sent.
  final String absolutePath;

  final String mime;
  final int width;
  final int height;
}

/// One stored image of a message, with its path already resolved for display.
class AiMessageImage {
  const AiMessageImage({
    required this.messageId,
    required this.relPath,
    required this.absolutePath,
    required this.mime,
  });

  final String messageId;
  final String relPath;
  final String absolutePath;
  final String? mime;
}

/// Owns the `ai_attachments` directory and the rows that point into it.
class AiAttachmentStore {
  AiAttachmentStore({
    required AiRepository repository,
    Future<Directory> Function()? supportDirectory,
  })  : _repository = repository,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final AiRepository _repository;

  /// Injected in tests, which must not touch the real app data directory.
  final Future<Directory> Function() _supportDirectory;

  /// Subdirectory of the app support directory. Images only - the `attachments`
  /// table is shared with other features, so files are kept apart by folder as
  /// well as by `owner_type`.
  static const String directoryName = 'ai_attachments';

  /// Writes an encoded image and returns the record the agent loop persists.
  Future<PendingImage> save(VisionImageReady image) async {
    // The extension is always `.png` because the encoder normalises every input
    // format; keeping the original extension would make the file's name lie
    // about its contents.
    final relPath = '$directoryName/${Ids.next('img')}.png';
    final directory = await _directory();
    final file = File(p.join(directory.path, p.basename(relPath)));
    await file.writeAsBytes(image.bytes, flush: true);
    return PendingImage(
      relPath: relPath,
      absolutePath: file.path,
      mime: image.mime,
      width: image.width,
      height: image.height,
    );
  }

  /// Records [images] as belonging to [messageId].
  Future<void> register(String messageId, Iterable<PendingImage> images) async {
    for (final image in images) {
      await _repository.addAttachment(
        messageId: messageId,
        relPath: image.relPath,
        mime: image.mime,
      );
    }
  }

  /// The bytes stored at [relPath], or null when the file is gone.
  ///
  /// A missing file is not an error here: a conversation must still be readable
  /// after the user clears the app's files, just without the pictures.
  Future<Uint8List?> readBytes(String relPath) async {
    try {
      final file = File(await absolutePath(relPath));
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Absolute path of a stored [relPath].
  Future<String> absolutePath(String relPath) async {
    final root = await _supportDirectory();
    return p.joinAll([root.path, ...relPath.split('/')]);
  }

  /// The `image_url` parts for one message, ready to be handed to the provider.
  ///
  /// A file that can no longer be read is skipped rather than failing the turn:
  /// losing a picture is a smaller loss than losing the conversation.
  Future<List<ChatImagePart>> partsForMessage(String messageId) async {
    final rows = await _repository.listMessageAttachments(messageId);
    final parts = <ChatImagePart>[];
    for (final row in rows) {
      final bytes = await readBytes(row.relPath);
      if (bytes == null) {
        continue;
      }
      parts.add(ChatImagePart(
        mime: row.mime ?? 'image/png',
        base64: base64Encode(bytes),
      ));
    }
    return parts;
  }

  /// Every image of a conversation, grouped by message id.
  Future<Map<String, List<AiMessageImage>>> imagesForConversation(
    String conversationId,
  ) async {
    final rows = await _repository.listConversationAttachments(conversationId);
    final grouped = <String, List<AiMessageImage>>{};
    for (final row in rows) {
      final resolved = AiMessageImage(
        messageId: row.ownerId,
        relPath: row.relPath,
        absolutePath: await absolutePath(row.relPath),
        mime: row.mime,
      );
      grouped.putIfAbsent(row.ownerId, () => []).add(resolved);
    }
    return grouped;
  }

  /// Removes the files of every image attached to a conversation.
  ///
  /// Called *before* the conversation rows are deleted, because the paths are
  /// read from those rows.
  Future<void> deleteConversationFiles(String conversationId) async {
    final rows = await _repository.listConversationAttachments(conversationId);
    await deleteFiles([for (final row in rows) row.relPath]);
  }

  /// Removes the files at [relPaths], best effort.
  ///
  /// Used for images the user staged and then removed before sending: they have
  /// no database row yet, so nothing else would ever clean them up.
  Future<void> deleteFiles(Iterable<String> relPaths) async {
    for (final relPath in relPaths) {
      await _deleteFile(relPath);
    }
  }

  Future<void> _deleteFile(String relPath) async {
    try {
      final file = File(await absolutePath(relPath));
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException {
      // An undeletable file is not worth failing a conversation delete over.
    }
  }

  Future<Directory> _directory() async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}
