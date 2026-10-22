/// The tag tree page: ordering is no longer `name.compareTo` hard-coded, and
/// the tree must stay usable while the object counts are still loading.
///
/// What is pinned here:
///  * the three ordering modes reorder every level (roots and children);
///  * the object-count badge only exists in "by object count" mode;
///  * the expansion state survives a re-sort and a mode switch;
///  * an empty database and a pending count query both render the page without
///    a spinner or an exception (counts fall back to 0);
///  * the mode choice lives in a provider, i.e. it survives page rebuilds
///    within the session.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// One tags row with an explicit id and creation time.
  ///
  /// The repository stamps `DateTime.now()`, which makes the "by created at"
  /// order impossible to pin down (two rows created in the same millisecond
  /// fall back to the name tie-break), so the fixtures write the rows directly.
  Future<void> seedTag(
    String id,
    String name, {
    String? parentId,
    required int createdAt,
  }) async {
    await db.into(db.tags).insert(TagsCompanion.insert(
          id: id,
          parentId: Value(parentId),
          name: name,
          createdAt: createdAt,
          updatedAt: createdAt,
        ));
  }

  /// Attaches [count] knowledge-point links to [tagId].
  ///
  /// object_tags only has a foreign key on tag_id, not on object_id, so
  /// synthetic ids are enough here: the page only reads the COUNT.
  Future<void> attach(String tagId, int count) async {
    for (var index = 0; index < count; index++) {
      final objectId = 'obj-$tagId-$index';
      await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
            id: objectId,
            tagId: tagId,
            objectType: 'knowledge_point',
            objectId: objectId,
            createdAt: 0,
          ));
    }
  }

  /// Names, creation times and content counts all disagree, so each of the
  /// three modes produces a different order. Two children of `alpha` make the
  /// per-level ordering observable, not just the roots.
  ///
  /// alphabetical : alpha, beta, gamma           | alpha-a, alpha-b
  /// by object    : alpha(2), gamma(1), beta(0)  | alpha-a(1), alpha-b(0)
  /// by created at: gamma, alpha, beta           | alpha-b(4000), alpha-a(5000)
  Future<void> seedFixture() async {
    await seedTag('t-beta', 'beta', createdAt: 3000);
    await seedTag('t-alpha', 'alpha', createdAt: 2000);
    await seedTag('t-gamma', 'gamma', createdAt: 1000);
    await seedTag('t-alpha-b', 'alpha-b', parentId: 't-alpha', createdAt: 4000);
    await seedTag('t-alpha-a', 'alpha-a', parentId: 't-alpha', createdAt: 5000);
    await attach('t-alpha', 2);
    await attach('t-gamma', 1);
    await attach('t-alpha-a', 1);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    fail('the tag tree is still loading after 40 pumps');
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TagTreePage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The names on the visible rows, in render order (the ListView children are
  /// in tree order, so this is exactly what the user sees top to bottom).
  List<String> tileTitles(WidgetTester tester) => <String>[
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data!,
      ];

  Future<void> toggle(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Taps the menu item itself (not its label Text) so the test does not
  /// depend on how deep the popup wraps the label.
  Future<void> selectMode(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
      of: find.text(label),
      matching: find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    ));
    await tester.pumpAndSettle();
  }

  final countBadge = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('tag-object-count-');
  });

  testWidgets('默认字典序：与旧的 name.compareTo 一致，且不显示内容量角标', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(countBadge, findsNothing);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(TagTreePage)))
          .read(tagTreeSortModeProvider)
          .value,
      TagTreeSortMode.alphabetical,
    );
  });

  testWidgets('切到「按内容量」：每层按内容量重排，并出现角标', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');

    await selectMode(tester, '按内容量');

    expect(
        tileTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
    expect(countBadge, findsNWidgets(5));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tag-object-count-t-alpha')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      ProviderScope.containerOf(tester.element(find.byType(TagTreePage)))
          .read(tagTreeSortModeProvider)
          .value,
      TagTreeSortMode.byObjectCount,
    );
  });

  testWidgets('切到「按添加时间」：先加的在前（含子层）', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');

    await selectMode(tester, '按添加时间');

    expect(
        tileTitles(tester), ['gamma', 'alpha', 'alpha-b', 'alpha-a', 'beta']);
    expect(countBadge, findsNothing);
  });

  testWidgets('展开状态跨重排保留：已展开的子层不因换排序而收起', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');
    expect(find.text('alpha-a'), findsOneWidget);

    await selectMode(tester, '按添加时间');
    expect(find.text('alpha-a'), findsOneWidget);
    expect(find.text('alpha-b'), findsOneWidget);

    // Collapsing still works after the re-sort, and the state is per tag id,
    // so switching modes again does not re-open it.
    await toggle(tester, 'alpha');
    await selectMode(tester, '按内容量');
    expect(find.text('alpha-a'), findsNothing);
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);
  });

  testWidgets('从「按内容量」切回字典序：角标消失、顺序复原', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    await selectMode(tester, '按内容量');
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);
    expect(countBadge, findsNWidgets(3));

    await selectMode(tester, '字典序');
    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(countBadge, findsNothing);
  });

  testWidgets('空库：显示空状态而不是加载圈', (tester) async {
    await pumpPage(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.tagsEmpty), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('计数未返回时不阻塞树：按 0 处理，模式仍然生效', (tester) async {
    await seedFixture();
    final pending = Completer<Map<String, int>>();

    await pumpPage(
      tester,
      overrides: <Override>[
        tagObjectCountsProvider.overrideWith((ref) => pending.future),
        tagTreeSortModeProvider.overrideWith(
          () => _FixedTagTreeSortModeController(
            TagTreeSortMode.byObjectCount,
          ),
        ),
      ],
    );

    // The tags are already on screen while the count query is still pending;
    // every count reads 0, so the tie-break falls back to the name.
    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(countBadge, findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tag-object-count-t-alpha')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('排序选择器：三档中文名，当前档打勾，切换立即重排', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.text('字典序'), findsOneWidget);
    expect(find.text('按内容量'), findsOneWidget);
    expect(find.text('按添加时间'), findsOneWidget);
    var items = tester.widgetList<CheckedPopupMenuItem<TagTreeSortMode>>(
      find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    );
    expect(
      items.where((item) => item.checked).map((item) => item.value).toList(),
      [TagTreeSortMode.alphabetical],
    );

    await tester.tap(find.ancestor(
      of: find.text('按内容量'),
      matching: find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    ));
    await tester.pumpAndSettle();
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    items = tester.widgetList<CheckedPopupMenuItem<TagTreeSortMode>>(
      find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    );
    expect(
      items.where((item) => item.checked).map((item) => item.value).toList(),
      [TagTreeSortMode.byObjectCount],
    );
  });

  testWidgets('首次打开不落盘：按字典序，读取偏好本身不写库', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(await db.select(db.localSettings).get(), isEmpty);
  });

  testWidgets('落盘的档位在下次打开时恢复', (tester) async {
    await seedFixture();
    final SettingsRepository repo = SettingsRepository(db);
    await repo.ensureSettings();
    await repo.updateTagTreeSortMode(TagTreeSortMode.byCreatedAt.code);

    await pumpPage(tester);

    expect(tileTitles(tester), ['gamma', 'alpha', 'beta']);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(TagTreePage)))
          .read(tagTreeSortModeProvider)
          .value,
      TagTreeSortMode.byCreatedAt,
    );
  });

  testWidgets('切换档位后写回 local_settings', (tester) async {
    await seedFixture();
    final SettingsRepository repo = SettingsRepository(db);
    await repo.ensureSettings();
    await pumpPage(tester);

    await selectMode(tester, '按内容量');

    // The menu handler writes fire-and-forget; give the write a few turns.
    String? stored;
    for (var attempt = 0; attempt < 50; attempt++) {
      stored = await repo.getTagTreeSortMode();
      if (stored != null) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(stored, 'object_count');
  });

  testWidgets('读偏好失败时回退字典序，页面不报错', (tester) async {
    await seedFixture();
    await pumpPage(
      tester,
      overrides: <Override>[
        tagTreeSortModeProvider.overrideWith(
          _ThrowingReadTagTreeSortModeController.new,
        ),
      ],
    );

    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(find.textContaining('settings unreadable'), findsNothing);
  });

  testWidgets('写偏好失败只记日志：本次会话的切换仍然生效', (tester) async {
    await seedFixture();
    await pumpPage(
      tester,
      overrides: <Override>[
        settingsRepositoryProvider
            .overrideWithValue(_ThrowingWriteSettingsRepository(db)),
      ],
    );

    await selectMode(tester, '按内容量');

    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('多选批量操作', () {
    Future<void> enterSelection(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();
    }

    Finder dialogIcon(IconData icon) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(icon),
        );

    Future<void> selectRow(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    List<String> dialogTileTitles(WidgetTester tester) => <String>[
          for (final tile in tester.widgetList<ListTile>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListTile),
            ),
          ))
            (tile.title! as Text).data!,
        ];

    testWidgets('进入多选出现勾选框与底部操作条；退出后消失、选择清空', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await enterSelection(tester);
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('批量删除'), findsOneWidget);
      expect(find.text('批量移动'), findsOneWidget);
      // 多选时单标签菜单让位给整行勾选。
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('已选 0 项'), findsNothing);

      // 再次进入：上一次的选择没有残留。
      await enterSelection(tester);
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('整行点击勾选/取消勾选，计数跟随，且不展开子层', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.text('alpha-a'), findsNothing);

      await selectRow(tester, 'beta');
      expect(find.text('已选 2 项'), findsOneWidget);
      final checkboxes =
          tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(checkboxes[0].value, isTrue);
      expect(checkboxes[1].value, isTrue);
      expect(checkboxes[2].value, isFalse);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox)).first.value,
        isFalse,
      );
    });

    testWidgets('全选包含全部标签（含未展开的子层），再点取消全选', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);

      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 5 项'), findsOneWidget);
      expect(find.text('清空选择'), findsOneWidget);

      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
    });

    testWidgets('展开箭头在多选中仍可展开子层，且不改变选择', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pumpAndSettle();
      expect(find.text('alpha-a'), findsOneWidget);
      expect(find.text('已选 0 项'), findsOneWidget);

      await selectRow(tester, 'alpha-a');
      expect(find.text('已选 1 项'), findsOneWidget);
    });

    testWidgets('批量删除：确认后连同子树一起删，界面与库都刷新', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);
      await selectRow(tester, 'alpha');
      await selectRow(tester, 'beta');

      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除 2 个标签？'), findsOneWidget);
      expect(find.text('alpha、beta（共 2 个）'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(dialogIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      final rows = await db.select(db.tags).get();
      expect(rows.map((row) => row.id).toList()..sort(), <String>['t-gamma']);
      // alpha 的整棵子树 + beta 的 object_tags 一并删除，只剩 gamma 的 1 条。
      expect(await db.select(db.objectTags).get(), hasLength(1));
      expect(tileTitles(tester), <String>['gamma']);
      expect(find.text('已删除 2 个标签'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('批量删除点取消：一个标签都不删，选择保留', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);
      await selectRow(tester, 'alpha');

      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(await db.select(db.tags).get(), hasLength(5));
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('批量移动：逐个挂到目标父节点下，路径级联更新', (tester) async {
      await seedFixture();
      // seedTag 直接写行、不带 path；给目标父节点补上 path，移动后子层的
      // 级联 path 才有父路径可拼（仓库用 getTagById(parentId).path）。
      await (db.update(db.tags)..where((t) => t.id.equals('t-alpha')))
          .write(const TagsCompanion(path: Value('alpha')));
      await pumpPage(tester);
      await enterSelection(tester);
      await selectRow(tester, 'beta');
      await selectRow(tester, 'gamma');

      await tester.tap(find.text('批量移动'));
      await tester.pumpAndSettle();
      // seedTag 直接写行、不给 path，所以 _labelOf 退回 name。
      expect(dialogTileTitles(tester),
          <String>['顶层', 'alpha', 'alpha-a', 'alpha-b']);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('alpha'),
      ));
      await tester.pumpAndSettle();

      final rows = <String, dynamic>{
        for (final row in await db.select(db.tags).get()) row.id: row,
      };
      expect(rows['t-beta'].parentId, 't-alpha');
      expect(rows['t-gamma'].parentId, 't-alpha');
      expect(rows['t-beta'].path, 'alpha/beta');
      expect(rows['t-gamma'].path, 'alpha/gamma');
      expect(find.text('已移动 2 个标签'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('移动目标列表排除被选标签自身与全部后代', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);
      await selectRow(tester, 'alpha');

      await tester.tap(find.text('批量移动'));
      await tester.pumpAndSettle();

      expect(dialogTileTitles(tester), <String>['顶层', 'beta', 'gamma']);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('alpha'),
        ),
        findsNothing,
      );
    });

    testWidgets('批量删除失败：汇总成功/失败并退出多选，库不受影响', (tester) async {
      await seedFixture();
      await pumpPage(
        tester,
        overrides: <Override>[
          tagRepositoryProvider.overrideWithValue(
            _ThrowingDeleteTagRepository(db),
          ),
        ],
      );
      await enterSelection(tester);
      await selectRow(tester, 'alpha');
      await selectRow(tester, 'beta');

      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.textContaining('成功 0 个、失败 2 个'), findsOneWidget);
      expect(await db.select(db.tags).get(), hasLength(5));
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('批量执行期间禁用入口，落定后恢复', (tester) async {
      await seedFixture();
      final repository = _HangingDeleteTagRepository(db);
      await pumpPage(
        tester,
        overrides: <Override>[
          tagRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await enterSelection(tester);
      await selectRow(tester, 'alpha');

      await tester.tap(find.text('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(dialogIcon(Icons.delete_outline));
      // settle 只等动画；删除仍卡在 gate 上，所以多选条保持锁定。
      await tester.pumpAndSettle();

      expect(find.text('处理中…'), findsOneWidget);
      expect(find.text('已选 1 项'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '批量删除'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '批量移动'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '全选'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.descendant(
              of: find.byType(AppBar),
              matching: find.widgetWithIcon(IconButton, Icons.close),
            ))
            .onPressed,
        isNull,
      );

      repository.release();
      await tester.pumpAndSettle();

      // alpha 连同两个子层一起删：只剩 beta 与 gamma。
      expect(find.text('已删除 1 个标签'), findsOneWidget);
      expect(await db.select(db.tags).get(), hasLength(2));
    });

    testWidgets('普通模式不回归：没有勾选框，单标签菜单照旧', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.text('新建子标签'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });
  });
}

/// Answers with a fixed mode without touching the settings repository.
class _FixedTagTreeSortModeController extends TagTreeSortModeController {
  _FixedTagTreeSortModeController(this.mode);

  final TagTreeSortMode mode;

  @override
  Future<TagTreeSortMode> build() async => mode;
}

/// Simulates an unreadable settings table; the page must fall back to 字典序.
class _ThrowingReadTagTreeSortModeController extends TagTreeSortModeController {
  @override
  Future<TagTreeSortMode> build() async =>
      throw StateError('settings unreadable');
}

/// A settings repository whose writes fail; the session choice must survive.
class _ThrowingWriteSettingsRepository extends SettingsRepository {
  _ThrowingWriteSettingsRepository(super.db);

  @override
  Future<void> updateTagTreeSortMode(String? mode) async {
    throw StateError('disk full');
  }
}

/// A tag repository whose deletion always fails; the batch flow must report the
/// failures instead of tearing the page down.
class _ThrowingDeleteTagRepository extends TagRepository {
  // The super field `_db` is private to tag_repository.dart, so a super
  // parameter cannot be spelled from this library.
  // ignore: use_super_parameters
  _ThrowingDeleteTagRepository(AppDatabase database) : super(database);

  @override
  Future<void> deleteTag(String id) async {
    throw StateError('delete rejected for $id');
  }
}

/// A tag repository whose deletion waits on a gate; the batch flow must lock its
/// entry points until the delete settles.
class _HangingDeleteTagRepository extends TagRepository {
  // See _ThrowingDeleteTagRepository for the super-parameter note.
  // ignore: use_super_parameters
  _HangingDeleteTagRepository(AppDatabase database) : super(database);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> deleteTag(String id) async {
    await _gate.future;
    await super.deleteTag(id);
  }
}
