import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/core/theme/theme_profile.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/theme_repository.dart';

/// Appearance themes: seeding, selection, import/export and the promise that a
/// built-in theme can never be destroyed by editing it.
void main() {
  late AppDatabase db;
  late ThemeRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ThemeRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('built-in seeding', () {
    test('both shipped themes exist after the first read', () async {
      final themes = await repo.getAll();
      expect(themes.map((t) => t.id), containsAll(['builtin-dark', 'builtin-light']));
      expect(themes.where((t) => t.isBuiltin == 1), hasLength(2));
    });

    test('seeding is idempotent', () async {
      await repo.getAll();
      await repo.getAll();
      expect(await db.select(db.themes).get(), hasLength(2));
    });

    test('the seeded payload parses back into the shipped profile', () async {
      final row = (await repo.getAll())
          .firstWhere((t) => t.id == 'builtin-dark');
      final data = repo.dataOf(row);
      expect(data.brightness, 'dark');
      expect(data.name, ThemeProfileData.builtinDark.name);
    });
  });

  group('active theme', () {
    test('starts as "follow the system"', () async {
      await repo.ensureBuiltins();
      expect(await repo.active(), isNull);
    });

    test('selection persists and is readable', () async {
      await repo.ensureBuiltins();
      await repo.setActive('builtin-light');
      final active = await repo.active();
      expect(active, isNotNull);
      expect(active!.row.id, 'builtin-light');
      expect(active.data.brightness, 'light');
    });

    test('clearing the selection restores the system default', () async {
      await repo.ensureBuiltins();
      await repo.setActive('builtin-dark');
      await repo.setActive(null);
      expect(await repo.active(), isNull);
    });

    test('an unknown id reads as system default instead of throwing', () async {
      await repo.ensureBuiltins();
      await repo.setActive('does-not-exist');
      expect(await repo.active(), isNull);
    });
  });

  group('save semantics', () {
    test('a new theme is stored as a user theme', () async {
      final saved = await repo.save(
        data: const ThemeProfileData(name: '深潜', primary: '#123456'),
      );
      expect(saved.isBuiltin, 0);
      expect(saved.name, '深潜');
      expect(repo.dataOf(saved).primary, '#123456');
    });

    test('saving with makeActive selects it', () async {
      final saved = await repo.save(
        data: const ThemeProfileData(name: 'A'),
        makeActive: true,
      );
      expect((await repo.active())!.row.id, saved.id);
    });

    test('editing a built-in stores a copy and leaves the default intact',
        () async {
      await repo.ensureBuiltins();
      final original =
          repo.dataOf((await repo.getById('builtin-dark'))!);

      final result = await repo.save(
        id: 'builtin-dark',
        data: original.copyWith(name: '我的深色', primary: '#FF0000'),
      );

      expect(result.id, isNot('builtin-dark'),
          reason: 'a built-in must never be overwritten in place');
      expect(result.isBuiltin, 0);
      expect(result.name, '我的深色');

      // The shipped theme is untouched.
      final shipped = await repo.getById('builtin-dark');
      expect(shipped!.name, ThemeProfileData.builtinDark.name);
      expect(repo.dataOf(shipped).primary,
          ThemeProfileData.builtinDark.primary);
    });

    test('editing a user theme updates it in place', () async {
      // getAll() is what seeds the built-ins, so it is called explicitly to
      // make the expected row count below meaningful.
      await repo.getAll();
      final saved = await repo.save(data: const ThemeProfileData(name: 'A'));
      final updated = await repo.save(
        id: saved.id,
        data: const ThemeProfileData(name: 'B', scale: 1.3),
      );
      expect(updated.id, saved.id);
      expect(updated.name, 'B');
      expect(repo.dataOf(updated).scale, 1.3);
      expect(await db.select(db.themes).get(), hasLength(3),
          reason: 'two built-ins plus the one user theme');
    });
  });

  group('import / export', () {
    test('export then import round-trips the document', () async {
      final source = await repo.save(
        data: const ThemeProfileData(
          name: '可分享',
          brightness: 'light',
          primary: '#010203',
          backgroundOpacity: 0.5,
          scale: 1.25,
          animations: false,
        ),
      );
      final json = repo.exportJson(source);
      expect(ThemeRepository.isValidThemeJson(json), isTrue);

      final other = ThemeRepository(
        AppDatabase.forTesting(NativeDatabase.memory()),
      );
      addTearDown(() async {});
      final imported = await other.importJson(json);
      final data = other.dataOf(imported);
      expect(data.name, '可分享');
      expect(data.brightness, 'light');
      expect(data.primary, '#010203');
      expect(data.backgroundOpacity, 0.5);
      expect(data.scale, 1.25);
      expect(data.animations, isFalse);
      expect(imported.isBuiltin, 0);
    });

    test('a malformed document is rejected before anything is written',
        () async {
      expect(ThemeRepository.isValidThemeJson('{not json'), isFalse);
      expect(ThemeRepository.isValidThemeJson('[]'), isFalse);
      expect(
        () => repo.importJson('{not json'),
        throwsA(isA<FormatException>()),
      );
      // Seeded built-ins only - the failed import added nothing.
      await repo.getAll();
      expect(await db.select(db.themes).get(), hasLength(2));
    });

    test('exportJson can rename on the way out', () async {
      final saved = await repo.save(data: const ThemeProfileData(name: '旧名'));
      final json = repo.exportJson(saved, nameOverride: '新名');
      expect(ThemeProfileData.decode(json).name, '新名');
    });
  });

  group('delete rules', () {
    test('a user theme can be deleted', () async {
      final saved = await repo.save(data: const ThemeProfileData(name: '临时'));
      expect(await repo.delete(saved.id), isTrue);
      expect(await repo.getById(saved.id), isNull);
    });

    test('a built-in cannot be deleted', () async {
      await repo.ensureBuiltins();
      expect(await repo.delete('builtin-dark'), isFalse);
      expect(await repo.getById('builtin-dark'), isNotNull);
    });

    test('deleting the active theme falls back to the system default',
        () async {
      final saved = await repo.save(
        data: const ThemeProfileData(name: '临时'),
        makeActive: true,
      );
      expect((await repo.active())!.row.id, saved.id);
      await repo.delete(saved.id);
      expect(await repo.active(), isNull,
          reason: 'the app must not keep pointing at a deleted theme');
    });
  });

  group('file names', () {
    test('illegal characters are stripped', () {
      expect(
        ThemeRepository.fileNameFor(const ThemeProfileData(name: 'a/b:c*d?')),
        'a_b_c_d_.threadflow-theme.json',
      );
      expect(
        ThemeRepository.fileNameFor(const ThemeProfileData(name: '   ')),
        'theme.threadflow-theme.json',
      );
    });
  });
}
