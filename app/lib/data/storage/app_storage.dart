/// Where this installation keeps its data on disk.
///
/// Two policies, one entry point:
///
///  * **Windows** relocates the whole app-data tree to a fixed, human-findable
///    root ([windowsDataRootPath], currently `E:\Furnace\data`). The relocation
///    is a *copy*, never a move: the old app-support tree is left untouched, so
///    a full/unplugged/read-only target cannot lose data - a failed migration
///    simply keeps using the old directory.
///  * **Every other platform** (Android included) keeps the `path_provider`
///    directories it always used. Nothing about them changes.
///
/// The one thing that cannot live in the database is the database's own
/// location. That is what [pointerFileName] is for: a one-line text file inside
/// the *legacy* app-support directory - the only location that is derivable
/// without already knowing the answer - holding the root that a migration
/// successfully committed to. The pointer is written only after the whole
/// migration succeeded; with no pointer the next launch re-evaluates the target
/// (and re-runs the migration if the old data is still to be carried over).
///
/// Resolution happens once per process: [supportDirectory] and
/// [documentsDirectory] are the single async entry points, and every caller
/// (database, image stores, skill store, document tools, ...) goes through them
/// so no two features can disagree about where the bytes live.
///
/// [debugConfigureForTesting] / [debugReset] are the seam used by
/// `test/data/storage/app_storage_test.dart`. They are the only way a test can
/// point the resolver at temporary directories - and under `flutter test` no
/// test ever writes to the real [windowsDataRootPath].
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (and, on Windows, one-time migrates) the directories this install
/// keeps its files in.
class AppStorage {
  AppStorage._();

  /// Name of the pointer file, inside the *legacy* app-support directory.
  ///
  /// It holds nothing but the absolute path of the relocated root, one line of
  /// UTF-8 text. It is deliberately not inside the database: a database cannot
  /// record where the database is.
  static const String pointerFileName = 'storage_root.txt';

  /// Fixed data root for Windows, as a constant for now.
  ///
  /// A later settings screen can make this configurable; the pointer file
  /// already decouples the on-disk location from the code, so moving it again
  /// does not need a code migration.
  static const String windowsDataRootPath = r'E:\Furnace\data';

  /// Subdirectory of the relocated root that plays the "documents" role on
  /// Windows (question-pack backups live here, and they follow the data root).
  static const String documentsDirectoryName = 'documents';

  /// Folder holding import backups. Must stay identical to
  /// `kQuestionPackBackupFolderName` in
  /// `features/questions/application/question_pack_service.dart`; it is
  /// duplicated here because `data/` must not import `features/`. The storage
  /// test asserts the two constants are equal.
  static const String questionPackBackupsFolderName = 'question_pack_backups';

  /// Database file names, current first: the app was renamed twice and every
  /// name still counts as "this install already has data".
  static const List<String> databaseFileNames = <String>[
    'furnace.db',
    'threadflow.db',
    'knowflow.db',
  ];

  /// app support directory: the database, media and skill files live here.
  ///
  /// On Windows this is the relocated root once a migration has succeeded (or
  /// the legacy directory when relocation is unavailable or fails); elsewhere
  /// it is exactly `getApplicationSupportDirectory()`.
  static Future<Directory> supportDirectory() {
    final cached = _supportDirectory;
    if (cached != null) {
      return cached;
    }
    final resolution = _resolveSupportDirectory();
    _supportDirectory = resolution;
    // Never cache a failure: a plugin that was not ready on the first call (or
    // a transient I/O error) must not poison the whole session.
    _dropFailedResolution(
      resolution,
      () {
        if (identical(_supportDirectory, resolution)) {
          _supportDirectory = null;
        }
      },
    );
    return resolution;
  }

  /// documents directory: question-pack backups live here and follow the data
  /// root on Windows (`<root>/documents`), otherwise the platform directory.
  static Future<Directory> documentsDirectory() {
    final cached = _documentsDirectory;
    if (cached != null) {
      return cached;
    }
    final resolution = _resolveDocumentsDirectory();
    _documentsDirectory = resolution;
    _dropFailedResolution(
      resolution,
      () {
        if (identical(_documentsDirectory, resolution)) {
          _documentsDirectory = null;
        }
      },
    );
    return resolution;
  }

  // ---------------------------------------------------------------------------
  // Test seam
  // ---------------------------------------------------------------------------

  /// Points the resolver at temporary directories for one test.
  ///
  /// Passing null keeps the production behaviour for that knob. In particular
  /// [isWindows] must be passed explicitly by a test that wants to exercise the
  /// Windows relocation path: the real `E:\Furnace\data` is never written by
  /// the test suite.
  ///
  /// Call [debugReset] in `tearDown` to drop the memoized result.
  @visibleForTesting
  static void debugConfigureForTesting({
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? documentsDirectory,
    bool? isWindows,
    String? relocatedRootPath,
  }) {
    _environment = _StorageEnvironment(
      supportDirectory: supportDirectory,
      documentsDirectory: documentsDirectory,
      isWindows: isWindows,
      relocatedRootPath: relocatedRootPath,
    );
    _supportDirectory = null;
    _documentsDirectory = null;
  }

  /// Restores the production environment and forgets everything resolved so
  /// far.
  @visibleForTesting
  static void debugReset() {
    _environment = const _StorageEnvironment();
    _supportDirectory = null;
    _documentsDirectory = null;
  }

  // ---------------------------------------------------------------------------
  // Path resolution
  // ---------------------------------------------------------------------------

  static Future<Directory>? _supportDirectory;
  static Future<Directory>? _documentsDirectory;
  static _StorageEnvironment _environment = const _StorageEnvironment();

  static Future<Directory> _resolveSupportDirectory() async {
    final environment = _environment;
    final legacy = await _legacySupportDirectory(environment);
    if (!_relocationEnabled(environment)) {
      return legacy;
    }

    final rootPath = await _resolveRelocatedRootPath(legacy);
    if (rootPath == null || _samePath(rootPath, legacy.path)) {
      return legacy;
    }

    final root = Directory(rootPath);
    final migrated = await _migrateOnce(legacy: legacy, root: root);
    if (!migrated) {
      debugPrint(
        '[AppStorage] migration to ${root.path} failed; '
        'keeping the legacy app-support directory ${legacy.path}',
      );
      return legacy;
    }
    return root;
  }

  static Future<Directory> _resolveDocumentsDirectory() async {
    final environment = _environment;
    if (_relocationEnabled(environment)) {
      final support = await supportDirectory();
      final legacy = await _legacySupportDirectory(environment);
      if (!_samePath(support.path, legacy.path)) {
        final documents =
            Directory(p.join(support.path, documentsDirectoryName));
        await documents.create(recursive: true);
        return documents;
      }
    }
    return (environment.documentsDirectory ??
        getApplicationDocumentsDirectory)();
  }

  /// True when this process should use the relocated Windows root.
  ///
  /// An explicitly injected [isWindows] always wins (that is how the storage
  /// test exercises the Windows branch on any host). Under `flutter test` the
  /// relocation is otherwise switched off on purpose: other test files mock
  /// `path_provider` per test case and must keep seeing exactly the directory
  /// they mocked - and no test run may probe or create the real
  /// `E:\Furnace\data`.
  static bool _relocationEnabled(_StorageEnvironment environment) {
    final injected = environment.isWindows;
    if (injected != null) {
      return injected;
    }
    if (_runningUnderFlutterTest) {
      return false;
    }
    return Platform.isWindows;
  }

  static bool get _runningUnderFlutterTest {
    final flag = Platform.environment['FLUTTER_TEST'];
    return flag != null && flag.toLowerCase() == 'true';
  }

  static Future<Directory> _legacySupportDirectory(
    _StorageEnvironment environment,
  ) {
    return (environment.supportDirectory ?? getApplicationSupportDirectory)();
  }

  /// Resolves the Windows data root: a valid pointer file wins, then the
  /// default [windowsDataRootPath] (which the caller can override in tests).
  ///
  /// Returns null when neither is usable, which means "stay on the legacy
  /// directory" for this run.
  static Future<String?> _resolveRelocatedRootPath(Directory legacy) async {
    final pointer = File(p.join(legacy.path, pointerFileName));
    try {
      if (await pointer.exists()) {
        final pointed = (await pointer.readAsString()).trim();
        if (pointed.isNotEmpty) {
          final usable = await _prepareWritableRoot(pointed);
          if (usable != null) {
            return usable;
          }
          debugPrint(
            '[AppStorage] ignoring $pointerFileName: '
            '"$pointed" is not a writable directory',
          );
        }
      }
    } on FileSystemException catch (error) {
      debugPrint('[AppStorage] cannot read $pointerFileName: $error');
    }

    final candidate = _environment.relocatedRootPath ?? windowsDataRootPath;
    final usable = await _prepareWritableRoot(candidate);
    if (usable == null) {
      debugPrint('[AppStorage] windows data root unavailable: $candidate');
    }
    return usable;
  }

  /// Makes sure [rawPath] is an absolute, writable directory and returns its
  /// normalized path; null when it is not.
  ///
  /// The write probe (a tiny file created and deleted) is what makes "the E:
  /// drive exists" honest: a missing drive, a read-only volume and a
  /// permissions failure all look the same, and all of them must fall back.
  static Future<String?> _prepareWritableRoot(String rawPath) async {
    if (!p.isAbsolute(rawPath)) {
      return null;
    }
    final directory = Directory(p.normalize(rawPath));
    final probe = File(p.join(directory.path, '.storage_write_probe_$pid'));
    try {
      await directory.create(recursive: true);
      await probe.writeAsString('furnace', flush: true);
      return directory.path;
    } on FileSystemException catch (error) {
      debugPrint('[AppStorage] cannot use ${directory.path}: $error');
      return null;
    } finally {
      try {
        if (await probe.exists()) {
          await probe.delete();
        }
      } on FileSystemException {
        // A leftover probe file is harmless.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // One-time migration
  // ---------------------------------------------------------------------------

  /// Copies the legacy layout into [root] the first time it is needed.
  ///
  /// Runs only when [root] is a different directory, the legacy directory
  /// actually holds a database ([databaseFileNames]) and [root] does not hold
  /// `furnace.db` yet - so an interrupted migration or a fresh root never
  /// overwrites data that is already there.
  ///
  /// Returns true when [root] is safe to use (migrated now, already migrated,
  /// or nothing to migrate) and false when the copy failed; on failure every
  /// entity this attempt created is removed again and the caller falls back to
  /// [legacy]. Nothing is ever deleted from [legacy]: copy, do not move.
  static Future<bool> _migrateOnce({
    required Directory legacy,
    required Directory root,
  }) async {
    final currentDatabase = File(p.join(root.path, 'furnace.db'));
    if (await currentDatabase.exists()) {
      return true;
    }
    final legacyDatabase = _firstDatabaseFile(legacy);
    if (legacyDatabase == null) {
      return true;
    }

    final created = <String>[];
    final pointer = File(p.join(legacy.path, pointerFileName));
    final pointerExistedBefore = await pointer.exists();
    try {
      await for (final entity in legacy.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name == pointerFileName) {
          continue;
        }
        created.addAll(await _copyTree(entity, p.join(root.path, name)));
      }

      final legacyDocuments = await (_environment.documentsDirectory ??
          getApplicationDocumentsDirectory)();
      final legacyBackups = Directory(
        p.join(legacyDocuments.path, questionPackBackupsFolderName),
      );
      if (await legacyBackups.exists()) {
        final documents = Directory(p.join(root.path, documentsDirectoryName));
        if (!await documents.exists()) {
          await documents.create(recursive: true);
          created.add(documents.path);
        }
        created.addAll(await _copyTree(
          legacyBackups,
          p.join(documents.path, questionPackBackupsFolderName),
        ));
      }

      await pointer.writeAsString('${root.path}\n', flush: true);
      debugPrint(
        '[AppStorage] copied ${legacy.path} to ${root.path}; '
        'the legacy copy is kept and $pointerFileName records the new root',
      );
      return true;
    } catch (error, stack) {
      debugPrint('[AppStorage] migration failed: $error\n$stack');
      await _rollback(created);
      if (!pointerExistedBefore) {
        try {
          if (await pointer.exists()) {
            await pointer.delete();
          }
        } on FileSystemException {
          // Nothing else to do: the pointer is re-derived on the next launch.
        }
      }
      return false;
    }
  }

  /// Copies one filesystem entity (recursively for directories) to
  /// [destinationPath] without overwriting anything that is already there.
  ///
  /// Returns the absolute paths it created, outermost first, so a failed
  /// migration can delete exactly its own half-finished work and nothing that
  /// predated the attempt.
  static Future<List<String>> _copyTree(
    FileSystemEntity source,
    String destinationPath,
  ) async {
    final created = <String>[];
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      final sourceDirectory =
          source is Directory ? source : Directory(source.path);
      final destination = Directory(destinationPath);
      if (!await destination.exists()) {
        await destination.create(recursive: true);
        created.add(destination.path);
      }
      await for (final child in sourceDirectory.list(followLinks: false)) {
        created.addAll(await _copyTree(
          child,
          p.join(destination.path, p.basename(child.path)),
        ));
      }
    } else if (type == FileSystemEntityType.file) {
      final destination = File(destinationPath);
      if (!await destination.exists()) {
        await destination.parent.create(recursive: true);
        await File(source.path).copy(destination.path);
        created.add(destination.path);
      }
    } else {
      debugPrint(
        '[AppStorage] skipping ${source.path} ($type) during migration',
      );
    }
    return created;
  }

  /// Deletes everything a failed migration created, deepest entry first.
  static Future<void> _rollback(List<String> created) async {
    for (final path in created.reversed) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(path).delete();
        }
      } on FileSystemException catch (error) {
        debugPrint('[AppStorage] rollback left $path behind: $error');
      }
    }
  }

  static File? _firstDatabaseFile(Directory directory) {
    for (final name in databaseFileNames) {
      final file = File(p.join(directory.path, name));
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  static bool _samePath(String a, String b) =>
      p.equals(p.normalize(p.absolute(a)), p.normalize(p.absolute(b)));

  static void _dropFailedResolution(
    Future<Directory> resolution,
    void Function() clear,
  ) {
    resolution.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        clear();
      },
    );
  }
}

/// Everything [AppStorage] asks the outside world; null fields mean "the
/// production answer".
class _StorageEnvironment {
  const _StorageEnvironment({
    this.supportDirectory,
    this.documentsDirectory,
    this.isWindows,
    this.relocatedRootPath,
  });

  final Future<Directory> Function()? supportDirectory;
  final Future<Directory> Function()? documentsDirectory;

  /// Null means `Platform.isWindows` (with the test-run guard in [AppStorage]).
  final bool? isWindows;

  /// Null means [AppStorage.windowsDataRootPath].
  final String? relocatedRootPath;
}
