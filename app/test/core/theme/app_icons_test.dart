// Tests for the built-in icon catalog behind the semantic icon slots
// (APPEARANCE_DESIGN decision D1).
//
// Three properties matter here and each one has a way to break silently:
//   1. the catalog is **const** - otherwise `--tree-shake-icons` stops working and
//      the whole Material font ships;
//   2. the **outlined and filled** variant of an entry are actually different
//      icons - an accidental copy would render "selected" and "unselected"
//      identically and nobody would notice in a screenshot;
//   3. an unknown name **falls back** instead of throwing - theme files travel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/theme/app_icons.dart';

void main() {
  // Compile-time evidence for property 1: this only compiles because the catalog
  // (and every AppIcon in it) is a compile-time constant. Making the map non-const
  // breaks this test file, which is the point - a runtime lookup would defeat
  // `--tree-shake-icons`.
  const Map<String, AppIcon> catalogIsConst = AppIcons.catalog;

  group('catalog', () {
    test('offers at least 100 icons, each listed exactly once', () {
      expect(catalogIsConst.length, greaterThanOrEqualTo(100));

      final names = AppIcons.names;
      expect(names.length, catalogIsConst.length,
          reason: 'every catalog entry belongs to exactly one category');
      expect(names.toSet().length, names.length,
          reason: 'an icon listed in two categories would appear twice '
              'in the picker');
      expect(names.toSet(), catalogIsConst.keys.toSet(),
          reason: 'the categories must cover the catalog exactly');
    });

    test('every entry really has two different icons', () {
      for (final entry in catalogIsConst.entries) {
        expect(
          entry.value.outlined.codePoint,
          isNot(entry.value.filled.codePoint),
          reason: '${entry.key}: outlined and filled are the same glyph, so the '
              'selected state would be invisible',
        );
        expect(
          entry.value.outlined.fontFamily,
          entry.value.filled.fontFamily,
          reason: entry.key,
        );
        expect(
          entry.value.outlined.fontPackage,
          entry.value.filled.fontPackage,
          reason: entry.key,
        );
        expect(
          entry.value.outlined.matchTextDirection,
          entry.value.filled.matchTextDirection,
          reason: entry.key,
        );
      }
    });

    test('every category has members and is reachable through categoryOf', () {
      expect(AppIcons.categories.keys.toSet(), IconCategory.values.toSet());
      for (final entry in AppIcons.categories.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key.name);
        for (final name in entry.value) {
          expect(AppIcons.categoryOf(name), entry.key);
          expect(AppIcons.isKnown(name), isTrue, reason: name);
        }
      }
      expect(AppIcons.categoryOf('not_a_real_icon'), isNull);
      expect(AppIcons.isKnown('not_a_real_icon'), isFalse);
      expect(AppIcons.isKnown(null), isFalse);
    });
  });

  group('slots', () {
    test('the fixed slot set and its factory icons', () {
      expect(AppIcons.slots, const <String>[
        'tags',
        'thread',
        'time',
        'knowledge',
        'packages',
        'ai',
        'settings',
      ]);
      expect(AppIcons.slotDefaults.keys.toSet(), AppIcons.slots.toSet());
      // The factory defaults are the icons the shell hard-coded before D1, so an
      // untouched theme keeps rendering what the app always rendered.
      expect(AppIcons.slotDefaults, const <String, String>{
        'tags': 'account_tree',
        'thread': 'bolt',
        'time': 'schedule',
        'knowledge': 'psychology',
        'packages': 'library_books',
        'ai': 'smart_toy',
        'settings': 'settings',
      });
      for (final name in AppIcons.slotDefaults.values) {
        expect(AppIcons.isKnown(name), isTrue,
            reason: '$name is the factory icon of a slot, so it must be in the '
                'catalog (the picker has to be able to show it as chosen)');
      }
    });

    test('an unconfigured slot renders its factory icon', () {
      for (final slot in AppIcons.slots) {
        final expected = catalogIsConst[AppIcons.slotDefaults[slot]]!;
        expect(AppIcons.effectiveName(slot, const {}), AppIcons.slotDefaults[slot]);
        expect(AppIcons.iconFor(slot, const {}).outlined, expected.outlined);
        expect(
          AppIcons.iconData(slot, const {}, filled: false),
          expected.outlined,
        );
        expect(AppIcons.iconData(slot, const {}, filled: true), expected.filled);
      }
    });

    test('an unknown name falls back to the slot icon instead of throwing', () {
      const configured = <String, String>{
        'tags': 'definitely_not_an_icon',
        'thread': 'star',
      };
      expect(AppIcons.effectiveName('tags', configured), 'account_tree');
      expect(
        AppIcons.iconData('tags', configured, filled: false),
        Icons.account_tree_outlined,
      );
      expect(
        AppIcons.iconData('tags', configured, filled: true),
        Icons.account_tree,
      );
      // A known name still wins, obviously.
      expect(AppIcons.effectiveName('thread', configured), 'star');
      expect(AppIcons.iconData('thread', configured, filled: true), Icons.star);
    });

    test('every catalog name is usable in every slot', () {
      for (final name in AppIcons.names) {
        for (final slot in AppIcons.slots) {
          expect(
            AppIcons.iconData(slot, <String, String>{slot: name}, filled: false),
            catalogIsConst[name]!.outlined,
            reason: '$name in $slot',
          );
        }
      }
    });

    test('an unknown slot is a programming error, not a silent default', () {
      expect(
        () => AppIcons.effectiveName('nowhere', const {}),
        throwsArgumentError,
      );
    });
  });

  group('search', () {
    test('an empty query returns the whole catalog, in category order', () {
      expect(AppIcons.search(''), AppIcons.names);
      expect(AppIcons.search('   '), AppIcons.names);
    });

    test('filters by substring and ignores case', () {
      expect(AppIcons.search('star'), contains('star'));
      expect(AppIcons.search('STAR'), contains('star'));
      expect(
        AppIcons.search('arrow'),
        isNotEmpty,
        reason: 'the catalog has arrow_* names',
      );
      expect(AppIcons.search('arrow'), everyElement(contains('arrow')));
      expect(AppIcons.search('zzzzzz'), isEmpty);
    });
  });
}
