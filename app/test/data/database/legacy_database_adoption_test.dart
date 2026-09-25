import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Guards the rename (`knowflow` -> `threadflow` -> `furnace`) against silent
/// data loss.
///
/// `getApplicationSupportDirectory()` is derived from the executable metadata
/// on Windows and the application id on Android, so renaming the app changes
/// the *directory*, not just the file name. A file-name-only fallback would
/// quietly hand the user a brand new empty database - which is exactly what
/// happened on this machine before the fix.
void main() {
  late Directory sandbox;
  late Directory appData;
  late Directory current;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('furnace-legacy-');
    appData = Directory(p.join(sandbox.path, 'Roaming'))..createSync();
    current = Directory(p.join(appData.path, 'FirsryFan', 'Furnace'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// Writes a real SQLite file holding [titles], so the assertions run against
  /// a database rather than an opaque byte blob.
  File seedDatabase(String path, List<String> titles) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(file.path);
    db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT)');
    for (var i = 0; i < titles.length; i++) {
      db.execute("INSERT INTO tasks (id, title) VALUES ('id-$i', '${titles[i]}')");
    }
    db.dispose();
    return file;
  }

  List<String> readTitles(File file) {
    final db = sqlite3.open(file.path);
    final rows = db.select('SELECT title FROM tasks ORDER BY title');
    final titles = rows.map((r) => r['title'] as String).toList();
    db.dispose();
    return titles;
  }

  File resolve() => resolveDatabaseFileForTest(
        current.path,
        File(p.join(current.path, 'furnace.db')),
        applicationDataDir: appData.path,
      );

  group('legacy database adoption', () {
    test('the current database is used as-is', () {
      final target = seedDatabase(p.join(current.path, 'furnace.db'), ['current']);

      final resolved = resolve();

      expect(resolved.path, target.path);
      expect(readTitles(resolved), ['current']);
    });

    test('an older file name in the same directory is used without copying', () {
      final legacy = seedDatabase(
        p.join(current.path, 'knowflow.db'),
        ['legacy-old-name'],
      );

      final resolved = resolve();

      expect(resolved.path, legacy.path);
      // Same directory: no copy is needed, so none is made.
      expect(File(p.join(current.path, 'furnace.db')).existsSync(), isFalse);
    });

    test('a database under the pre-rename directory is copied to the new one',
        () {
      final legacy = seedDatabase(
        p.join(appData.path, 'com.example', 'knowflow', 'threadflow.db'),
        ['legacy-a', 'legacy-b', 'legacy-c'],
      );
      final legacyDigest = legacy.readAsBytesSync();

      final resolved = resolve();

      // The copy becomes the live database...
      expect(resolved.path, p.join(current.path, 'furnace.db'));
      expect(readTitles(resolved), ['legacy-a', 'legacy-b', 'legacy-c']);
      // ...and the original is left byte-for-byte alone.
      expect(legacy.existsSync(), isTrue);
      expect(legacy.readAsBytesSync(), legacyDigest);
    });

    test('an empty leftover directory never hijacks a fresh install', () {
      // Old directory exists but holds no database.
      Directory(p.join(appData.path, 'com.example', 'knowflow'))
          .createSync(recursive: true);

      final resolved = resolve();

      expect(resolved.path, p.join(current.path, 'furnace.db'));
      expect(resolved.existsSync(), isFalse);
    });

    test('an existing database beats a legacy copy elsewhere', () {
      final target = seedDatabase(p.join(current.path, 'furnace.db'), ['current']);
      seedDatabase(
        p.join(appData.path, 'com.example', 'knowflow', 'knowflow.db'),
        ['legacy-should-lose'],
      );

      final resolved = resolve();

      expect(resolved.path, target.path);
      expect(readTitles(resolved), ['current']);
    });

    test('the legacy name wins over an unreadable other candidate', () {
      // `furnace.db` is absent, so the previous name is the honest answer even
      // when a directory candidate also exists.
      final sibling = seedDatabase(
        p.join(current.path, 'threadflow.db'),
        ['legacy-sibling'],
      );
      seedDatabase(
        p.join(appData.path, 'com.example', 'knowflow', 'threadflow.db'),
        ['legacy-other-dir'],
      );

      final resolved = resolve();

      expect(resolved.path, sibling.path);
      expect(readTitles(resolved), ['legacy-sibling']);
    });
  });
}
