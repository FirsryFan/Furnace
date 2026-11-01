import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/storage/app_storage.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart'
    show kQuestionPackBackupFolderName;
import 'package:path/path.dart' as p;

/// Tests for AppStorage: root resolution, the one-time Windows migration and
/// the pointer file.
///
/// Every path used here lives under Directory.systemTemp; no test reads or
/// writes the real E:\Furnace\data. The Windows branch is exercised by injecting
/// isWindows: true plus a temporary relocated root
/// (AppStorage.debugConfigureForTesting), so nothing depends on the host's
/// drives. The real production defaults are only touched by the one test that
/// mocks the path_provider channel to prove the flutter-test guard keeps the
/// legacy directory.
///
/// What the tests prove: which directory is returned in each situation, what a
/// migration copies, that it never deletes the legacy copy and that a failure
/// rolls the half-done copy back without writing a pointer. They do not boot a
/// real app, so platform-plugin behaviour on a device stays unproven.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory legacySupport;
  late Directory legacyDocuments;
  late Directory candidateRoot;
  late File blockingFile;

  setUp(() {
    AppStorage.debugReset();
    sandbox = Directory.systemTemp.createTempSync('furnace_app_storage_');
    legacySupport = Directory(p.join(sandbox.path, 'legacy-support'))
      ..createSync(recursive: true);
    legacyDocuments = Directory(p.join(sandbox.path, 'legacy-documents'))
      ..createSync(recursive: true);
    candidateRoot = Directory(p.join(sandbox.path, 'relocated-root'));
    // A path that can never become a directory: this is how "the Windows root
    // is unusable" (no E: drive, read-only volume, ...) looks on any host.
    blockingFile = File(p.join(sandbox.path, 'not-a-directory'))
      ..writeAsStringSync('x');
  });

  tearDown(() {
    AppStorage.debugReset();
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  void configureWindows({String? relocatedRootPath}) {
    AppStorage.debugConfigureForTesting(
      supportDirectory: () async => legacySupport,
      documentsDirectory: () async => legacyDocuments,
      isWindows: true,
      relocatedRootPath: relocatedRootPath ?? candidateRoot.path,
    );
  }

  void configureNonWindows() {
    AppStorage.debugConfigureForTesting(
      supportDirectory: () async => legacySupport,
      documentsDirectory: () async => legacyDocuments,
      isWindows: false,
      relocatedRootPath: candidateRoot.path,
    );
  }

  File writeFile(String directory, String relativePath, String contents) {
    final file = File(p.join(directory, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  String readPointer() {
    final pointer =
        File(p.join(legacySupport.path, AppStorage.pointerFileName));
    return pointer.existsSync() ? pointer.readAsStringSync().trim() : '';
  }

  group('platform policy', () {
    test('non-Windows platforms keep both path_provider directories', () async {
      configureNonWindows();

      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, legacySupport.path), isTrue);
      expect(p.equals(documents.path, legacyDocuments.path), isTrue);
      expect(candidateRoot.existsSync(), isFalse,
          reason: 'the Windows root is not even prepared off Windows');
      expect(readPointer(), isEmpty);
    });

    test('the flutter-test guard keeps the real Windows root untouched',
        () async {
      // Check the guard first: if this ever runs without flutter_test, fail
      // before the real E:\Furnace\data could be probed.
      expect(Platform.environment['FLUTTER_TEST'], 'true',
          reason: 'AppStorage skips the Windows relocation under flutter test '
              r'precisely so this test file cannot write E:\Furnace\data');

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return legacySupport.path;
        }
        if (call.method == 'getApplicationDocumentsDirectory') {
          return legacyDocuments.path;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      // No debugConfigureForTesting: this is the production environment, only
      // with the platform channel answered by the mock above.
      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, legacySupport.path), isTrue,
          reason: 'the test run must not relocate to the real E: root');
      expect(p.equals(documents.path, legacyDocuments.path), isTrue);
      expect(candidateRoot.existsSync(), isFalse);
    });
  });

  group('pointer file', () {
    test('a valid pointer wins over the default Windows root', () async {
      final pointerRoot = Directory(p.join(sandbox.path, 'pointer-root'));
      writeFile(
        legacySupport.path,
        AppStorage.pointerFileName,
        pointerRoot.path,
      );
      configureWindows();

      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, pointerRoot.path), isTrue);
      expect(
        p.equals(
          documents.path,
          p.join(pointerRoot.path, AppStorage.documentsDirectoryName),
        ),
        isTrue,
      );
      expect(candidateRoot.existsSync(), isFalse,
          reason:
              'a usable pointer must stop the default root from being used');
    });

    test('an unusable pointer falls back to the default Windows root',
        () async {
      final blocked = p.join(blockingFile.path, 'data');
      writeFile(legacySupport.path, AppStorage.pointerFileName, blocked);
      configureWindows();

      final support = await AppStorage.supportDirectory();

      expect(p.equals(support.path, candidateRoot.path), isTrue);
      expect(readPointer(), blocked,
          reason: 'an ignored pointer is left alone, not rewritten');
    });
  });

  group('relocation', () {
    test('copies the database, media and backups and keeps the legacy copy',
        () async {
      writeFile(legacySupport.path, 'furnace.db', 'legacy-database-bytes');
      writeFile(
        legacySupport.path,
        p.join('question_images', 'stem.png'),
        'png-bytes',
      );
      writeFile(
        legacyDocuments.path,
        p.join(AppStorage.questionPackBackupsFolderName, 'backup-1.tqb'),
        'tqb-bytes',
      );
      configureWindows();

      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, candidateRoot.path), isTrue);
      expect(
        p.equals(
          documents.path,
          p.join(candidateRoot.path, AppStorage.documentsDirectoryName),
        ),
        isTrue,
      );
      expect(
        File(p.join(candidateRoot.path, 'furnace.db')).readAsStringSync(),
        'legacy-database-bytes',
      );
      expect(
        File(p.join(candidateRoot.path, 'question_images', 'stem.png'))
            .readAsStringSync(),
        'png-bytes',
      );
      expect(
        File(p.join(
          candidateRoot.path,
          AppStorage.documentsDirectoryName,
          AppStorage.questionPackBackupsFolderName,
          'backup-1.tqb',
        )).readAsStringSync(),
        'tqb-bytes',
      );
      // Copy, not move: an unplugged target disk must not cost the user data.
      expect(
        File(p.join(legacySupport.path, 'furnace.db')).readAsStringSync(),
        'legacy-database-bytes',
      );
      expect(readPointer(), isNotEmpty);
      expect(p.equals(readPointer(), candidateRoot.path), isTrue);
    });

    test('a target that already holds furnace.db is not migrated over',
        () async {
      writeFile(candidateRoot.path, 'furnace.db', 'target-database-bytes');
      writeFile(candidateRoot.path, 'target-note.txt', 'keep-me');
      writeFile(legacySupport.path, 'furnace.db', 'legacy-database-bytes');
      writeFile(legacySupport.path, 'legacy-note.txt', 'do-not-copy');
      configureWindows();

      final support = await AppStorage.supportDirectory();

      expect(p.equals(support.path, candidateRoot.path), isTrue);
      expect(
        File(p.join(candidateRoot.path, 'furnace.db')).readAsStringSync(),
        'target-database-bytes',
        reason: 'the target database is the newer data and wins',
      );
      expect(
        File(p.join(candidateRoot.path, 'legacy-note.txt')).existsSync(),
        isFalse,
        reason: 'no migration means no copy at all',
      );
      expect(readPointer(), isEmpty,
          reason: 'nothing was migrated, so there is nothing to point at');
    });

    test('a failed migration is rolled back and writes no pointer', () async {
      writeFile(legacySupport.path, 'furnace.db', 'legacy-database-bytes');
      writeFile(
        legacySupport.path,
        p.join('question_images', 'stem.png'),
        'png-bytes',
      );
      writeFile(
        legacyDocuments.path,
        p.join(AppStorage.questionPackBackupsFolderName, 'backup-1.tqb'),
        'tqb-bytes',
      );
      // The target root itself is writable, but its documents slot is a file:
      // the migration fails after it has already copied the database.
      writeFile(
          candidateRoot.path, AppStorage.documentsDirectoryName, 'blocker');
      configureWindows();

      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, legacySupport.path), isTrue,
          reason: 'a failed migration must keep using the legacy directory');
      expect(p.equals(documents.path, legacyDocuments.path), isTrue);
      expect(
          File(p.join(candidateRoot.path, 'furnace.db')).existsSync(), isFalse,
          reason: 'the half-done copy is removed again');
      expect(
        Directory(p.join(candidateRoot.path, 'question_images')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(candidateRoot.path, AppStorage.documentsDirectoryName))
            .readAsStringSync(),
        'blocker',
        reason: 'pre-existing target content is never deleted by a rollback',
      );
      expect(readPointer(), isEmpty,
          reason: 'the pointer is only written after a complete migration');
    });

    test('an unusable Windows root falls back to the app-support directory',
        () async {
      writeFile(legacySupport.path, 'furnace.db', 'legacy-database-bytes');
      configureWindows(relocatedRootPath: p.join(blockingFile.path, 'data'));

      final support = await AppStorage.supportDirectory();
      final documents = await AppStorage.documentsDirectory();

      expect(p.equals(support.path, legacySupport.path), isTrue);
      expect(p.equals(documents.path, legacyDocuments.path), isTrue);
      expect(readPointer(), isEmpty);
    });

    test('a fresh install uses the target root and writes no pointer',
        () async {
      configureWindows();

      final support = await AppStorage.supportDirectory();

      expect(p.equals(support.path, candidateRoot.path), isTrue);
      expect(candidateRoot.existsSync(), isTrue,
          reason: 'the root is created on first use');
      expect(readPointer(), isEmpty,
          reason: 'there was nothing to migrate, so the pointer stays absent');
    });
  });

  group('constants', () {
    test('the duplicated backups folder name matches the service constant', () {
      expect(
        AppStorage.questionPackBackupsFolderName,
        kQuestionPackBackupFolderName,
        reason: 'AppStorage duplicates it only to avoid a data/ -> features/ '
            'import; the two must not drift',
      );
    });
  });
}
