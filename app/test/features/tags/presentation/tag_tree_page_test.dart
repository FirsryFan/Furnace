/// The tag graph page: a Thinking-DAG-style node/edge map, not a list.
///
/// What is pinned here:
///  * nodes + parent/child edges are laid out as a graph that fits the viewport
///    width (no horizontal scroll); a deeper tree falls back to pan/zoom;
///  * a node's expand/collapse arrow hides its descendants and their edges;
///  * search auto-expands the matched paths, highlights hits and restores the
///    previous collapse state when cleared;
///  * **tapping a node opens the settings modal** (centered card + modal
///    barrier), never an inline menu; the arrow never opens it;
///  * the modal actions (linked content / add child / rename / move / usage /
///    delete) work, including the new single-tag move;
///  * the three ordering modes, multi-select batch flows and usage badges do
///    not regress.
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
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';
import 'package:furnace/features/tags/presentation/tag_graph_layout.dart';
import 'package:furnace/features/tags/presentation/tag_graph_view.dart';
import 'package:furnace/features/tags/presentation/tag_knowledge_entry_page.dart';
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

  /// A 7-level chain: the graph is wider than a 1000px viewport, so the page
  /// must fall back to pan/zoom instead of a horizontal scrollbar.
  Future<void> seedDeepChain(int levels) async {
    for (var index = 0; index < levels; index++) {
      await seedTag(
        't$index',
        'n$index',
        parentId: index == 0 ? null : 't${index - 1}',
        createdAt: 1000 + index,
      );
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    fail('the tag graph is still loading after 40 pumps');
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
    ThemeData? theme,
    Size size = const Size(1000, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: const TagTreePage(),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TagTreePage)));

  /// The node cards in render order (= preorder: parent before children).
  List<TagGraphNodeCard> cards(WidgetTester tester) =>
      tester.widgetList<TagGraphNodeCard>(find.byType(TagGraphNodeCard))
          .toList();

  /// The visible node names in graph order.
  List<String> nodeTitles(WidgetTester tester) =>
      [for (final card in cards(tester)) card.node.name];

  /// The layout the page actually handed to the canvas.
  TagGraphLayout graphLayout(WidgetTester tester) =>
      tester.widget<TagGraphCanvas>(find.byType(TagGraphCanvas)).layout;

  Finder toggleOf(String tagId) =>
      find.byKey(ValueKey<String>('tag-graph-toggle-$tagId'));

  Finder collapsedChipOf(String tagId) =>
      find.byKey(ValueKey<String>('tag-graph-collapsed-$tagId'));

  Future<void> toggle(WidgetTester tester, String tagId) async {
    await tester.tap(toggleOf(tagId));
    await tester.pumpAndSettle();
  }

  Future<void> tapNode(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Opens the node settings modal and taps one of its rows.
  Future<void> openSettingsAction(
    WidgetTester tester,
    String name,
    Key key,
  ) async {
    await tapNode(tester, name);
    expect(find.byType(TagNodeSettingsDialog), findsOneWidget);
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> enterSearch(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey<String>('tag-graph-search')),
      text,
    );
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

  /// No horizontal scrolling container anywhere on the page.
  final horizontalScrollable = find.byWidgetPredicate(
    (widget) =>
        (widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal) ||
        (widget is ListView && widget.scrollDirection == Axis.horizontal),
  );

  testWidgets('默认字典序：图是节点 + 父子连线，不是列表', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'beta', 'gamma']);
    expect(cards(tester), hasLength(5));
    // 两条连线：alpha→alpha-a、alpha→alpha-b。
    expect(graphLayout(tester).edges, hasLength(2));
    expect(graphLayout(tester).fitsWidth(1000), isTrue);
    expect(find.byType(TagGraphCanvas), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(horizontalScrollable, findsNothing);
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

    await selectMode(tester, '按内容量');

    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
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

    await selectMode(tester, '按添加时间');

    expect(
        nodeTitles(tester), ['gamma', 'alpha', 'alpha-b', 'alpha-a', 'beta']);
    expect(countBadge, findsNothing);
  });

  testWidgets('折叠状态跨重排保留：收起的分支不因换排序而展开', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 't-alpha');
    expect(find.text('alpha-a'), findsNothing);
    expect(collapsedChipOf('t-alpha'), findsOneWidget);

    await selectMode(tester, '按添加时间');
    expect(find.text('alpha-a'), findsNothing);
    expect(nodeTitles(tester), ['gamma', 'alpha', 'beta']);

    // 展开后子层按新排序出现，折叠状态按 tag id 记忆，再换档也不会回去。
    await toggle(tester, 't-alpha');
    expect(find.text('alpha-a'), findsOneWidget);
    await selectMode(tester, '按内容量');
    expect(find.text('alpha-a'), findsOneWidget);
    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
  });

  testWidgets('从「按内容量」切回字典序：角标消失、顺序复原', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    await selectMode(tester, '按内容量');
    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
    expect(countBadge, findsNWidgets(5));

    await selectMode(tester, '字典序');
    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'beta', 'gamma']);
    expect(countBadge, findsNothing);
  });

  testWidgets('空库：显示空状态而不是加载圈', (tester) async {
    await pumpPage(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.tagsEmpty), findsOneWidget);
    expect(find.byType(TagGraphNodeCard), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('计数未返回时不阻塞图：按 0 处理，模式仍然生效', (tester) async {
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
    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'beta', 'gamma']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(countBadge, findsNWidgets(5));
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
    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);

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

    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'beta', 'gamma']);
    expect(await db.select(db.localSettings).get(), isEmpty);
  });

  testWidgets('落盘的档位在下次打开时恢复', (tester) async {
    await seedFixture();
    final SettingsRepository repo = SettingsRepository(db);
    await repo.ensureSettings();
    await repo.updateTagTreeSortMode(TagTreeSortMode.byCreatedAt.code);

    await pumpPage(tester);

    expect(
        nodeTitles(tester), ['gamma', 'alpha', 'alpha-b', 'alpha-a', 'beta']);
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

    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'beta', 'gamma']);
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

    expect(
        nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('标签图布局与折叠', () {
    testWidgets('节点/连线数量与布局一致；典型深度不出现横向滚动', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      final layout = graphLayout(tester);
      expect(layout.nodes, hasLength(5));
      expect(layout.edges, hasLength(2));
      expect(layout.depthCount, 2);
      expect(horizontalScrollable, findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);

      // 根贴左、子层在右，且都在视口内。
      final alpha = layout.byId['t-alpha']!;
      final child = layout.byId['t-alpha-a']!;
      expect(alpha.rect.left, lessThan(child.rect.left));
      expect(layout.size.width, lessThanOrEqualTo(1000));
    });

    testWidgets('折叠有子节点的节点：后代与连线一起消失，再展开复原', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      expect(graphLayout(tester).edges, hasLength(2));

      await toggle(tester, 't-alpha');
      expect(find.text('alpha-a'), findsNothing);
      expect(find.text('alpha-b'), findsNothing);
      expect(nodeTitles(tester), ['alpha', 'beta', 'gamma']);
      expect(graphLayout(tester).edges, isEmpty);
      expect(graphLayout(tester).byId.containsKey('t-alpha-a'), isFalse);
      expect(collapsedChipOf('t-alpha'), findsOneWidget);

      await toggle(tester, 't-alpha');
      expect(find.text('alpha-a'), findsOneWidget);
      expect(graphLayout(tester).edges, hasLength(2));
      expect(collapsedChipOf('t-alpha'), findsNothing);
    });

    testWidgets('叶子节点没有折叠箭头', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      expect(toggleOf('t-beta'), findsNothing);
      expect(toggleOf('t-alpha'), findsOneWidget);
    });

    testWidgets('深树降级为可平移/缩放，仍不出现横向滚动条', (tester) async {
      await seedDeepChain(7);
      await pumpPage(tester);

      expect(cards(tester), hasLength(7));
      expect(graphLayout(tester).edges, hasLength(6));
      expect(graphLayout(tester).fitsWidth(1000), isFalse);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text(l10nOf(tester).tagsGraphPanHint), findsOneWidget);
      expect(horizontalScrollable, findsNothing);
    });

    testWidgets('深色主题下节点照常渲染（颜色取自 colorScheme）', (tester) async {
      await seedFixture();
      await pumpPage(tester, theme: ThemeData.dark(useMaterial3: true));

      expect(cards(tester), hasLength(5));
      expect(find.text('alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('搜索', () {
    testWidgets('搜索自动展开命中路径并高亮命中节点', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await toggle(tester, 't-alpha');
      expect(find.text('alpha-a'), findsNothing);

      await enterSearch(tester, 'alpha-a');

      // alpha 被强制展开（命中路径），未命中的兄弟 alpha-b 不显示。
      // 用节点 key 而不是 find.text：搜索框本身也含 'alpha-a' 文本。
      expect(
        find.byKey(const ValueKey<String>('tag-graph-node-t-alpha-a')),
        findsOneWidget,
      );
      expect(find.text('alpha-b'), findsNothing);
      expect(nodeTitles(tester), ['alpha', 'alpha-a']);
      expect(
        cards(tester)
            .singleWhere((card) => card.node.name == 'alpha-a')
            .matched,
        isTrue,
      );
      expect(
        cards(tester).singleWhere((card) => card.node.name == 'alpha').matched,
        isFalse,
      );

      // 清空搜索：回到搜索前的折叠状态。
      await tester.tap(find.byTooltip(l10nOf(tester).tagsClearSearch));
      await tester.pumpAndSettle();
      expect(find.text('alpha-a'), findsNothing);
      expect(nodeTitles(tester), ['alpha', 'beta', 'gamma']);
    });

    testWidgets('搜分支名：命中整条分支并按命中数显示计数', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await toggle(tester, 't-alpha');

      await enterSearch(tester, 'alpha');

      expect(nodeTitles(tester), ['alpha', 'alpha-a', 'alpha-b']);
      expect(cards(tester).every((card) => card.matched), isTrue);
      expect(find.text('匹配 3 个标签'), findsOneWidget);
    });

    testWidgets('搜索没有命中：显示空态，不画空图', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await enterSearch(tester, 'zzz');

      expect(find.byType(TagGraphNodeCard), findsNothing);
      expect(find.text(l10nOf(tester).tagsSearchEmpty), findsOneWidget);
      expect(find.text(l10nOf(tester).tagsSearchHint), findsOneWidget);
    });

    testWidgets('搜索大小写不敏感（与纯逻辑同口径）', (tester) async {
      await seedTag('t-alpha', 'Alpha', createdAt: 1000);
      await seedTag('t-beta', 'beta', createdAt: 2000);
      await pumpPage(tester);

      await enterSearch(tester, 'aLp');

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('beta'), findsNothing);
    });
  });

  group('节点设置浮窗（单击节点）', () {
    testWidgets('单击节点打开居中浮窗 + modal barrier，包含全部动作', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await tapNode(tester, 'alpha');

      expect(find.byType(TagNodeSettingsDialog), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
      expect(find.text(l10nOf(tester).tagsNodeSettings), findsOneWidget);
      expect(find.text(l10nOf(tester).tagsNodeSettingsHint), findsOneWidget);
      for (final key in <Key>[
        tagNodeSettingsKnowledgeKey,
        tagNodeSettingsAddChildKey,
        tagNodeSettingsRenameKey,
        tagNodeSettingsMoveKey,
        tagNodeSettingsUsageKey,
        tagNodeSettingsDeleteKey,
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }

      await tester.tap(find.descendant(
        of: find.byType(TagNodeSettingsDialog),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(TagNodeSettingsDialog), findsNothing);
    });

    testWidgets('折叠箭头不打开设置浮窗', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await toggle(tester, 't-alpha');

      expect(find.byType(TagNodeSettingsDialog), findsNothing);
      expect(find.text('alpha-a'), findsNothing);
    });

    testWidgets('浮窗里重命名：写库并刷新节点名', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await openSettingsAction(tester, 'alpha', tagNodeSettingsRenameKey);
      expect(find.text(l10nOf(tester).tagsRename), findsOneWidget);
      // 页面顶部还有搜索框，这里只往对话框里的输入框写。
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '文化课',
      );
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.check),
      ));
      await tester.pumpAndSettle();

      final row = await (db.select(db.tags)
            ..where((tag) => tag.id.equals('t-alpha')))
          .getSingle();
      expect(row.name, '文化课');
      expect(find.text('文化课'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('浮窗里移动：新父节点写库、路径级联更新', (tester) async {
      await seedFixture();
      await (db.update(db.tags)..where((tag) => tag.id.equals('t-gamma')))
          .write(const TagsCompanion(path: Value('gamma')));
      await pumpPage(tester);

      await openSettingsAction(tester, 'alpha', tagNodeSettingsMoveKey);
      expect(
          find.text(l10nOf(tester).tagsMoveSingleTitle('alpha')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('gamma'),
      ));
      await tester.pumpAndSettle();

      final row = await (db.select(db.tags)
            ..where((tag) => tag.id.equals('t-alpha')))
          .getSingle();
      expect(row.parentId, 't-gamma');
      expect(row.path, 'gamma/alpha');
      expect(find.text('alpha'), findsOneWidget);
    });

    testWidgets('浮窗里删除：确认后连同子树一起删，界面刷新', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await openSettingsAction(tester, 'alpha', tagNodeSettingsDeleteKey);
      expect(find.text(l10nOf(tester).tagsDeleteTitle('alpha')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.delete_outline),
      ));
      await tester.pumpAndSettle();

      final rows = await db.select(db.tags).get();
      expect(
          rows.map((row) => row.id).toList()..sort(), <String>['t-beta', 't-gamma']);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('alpha-a'), findsNothing);
    });

    testWidgets('浮窗里打开关联内容', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      await openSettingsAction(tester, 'alpha', tagNodeSettingsKnowledgeKey);
      // 打开后页面会异步查询，动画（加载圈）不能 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TagKnowledgeEntryPage), findsOneWidget);
      expect(find.byType(TagNodeSettingsDialog), findsNothing);
    });
  });

  group('标签用途边界（v37）', () {
    Finder badgeOf(String tagId) =>
        find.byKey(ValueKey<String>('tag-usage-badge-$tagId'));

    Finder usageCheckbox(TagUsage usage) =>
        find.byKey(ValueKey<String>('tag-usage-check-${usage.code}'));

    bool usageChecked(WidgetTester tester, TagUsage usage) =>
        tester.widget<CheckboxListTile>(usageCheckbox(usage)).value!;

    /// 节点 → 设置浮窗 → 「用途边界」。
    Future<void> openUsageDialog(WidgetTester tester, String tagName) async {
      await tapNode(tester, tagName);
      await tester.tap(find.byKey(tagNodeSettingsUsageKey));
      await tester.pumpAndSettle();
    }

    Future<void> saveDialog(WidgetTester tester) async {
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, l10nOf(tester).commonSave),
      ));
      await tester.pumpAndSettle();
    }

    /// 保存是异步写库：轮询到目标值，超时就把最后的值交给断言报错。
    Future<String?> waitUsageCodes(
      WidgetTester tester,
      String tagId, {
      required String? expected,
    }) async {
      String? codes;
      for (var attempt = 0; attempt < 60; attempt++) {
        final row = await (db.select(db.tags)..where((t) => t.id.equals(tagId)))
            .getSingle();
        codes = row.usageCodes;
        if (codes == expected) {
          return codes;
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      return codes;
    }

    Future<void> waitForBadge(
      WidgetTester tester,
      Finder badge, {
      required bool exists,
    }) async {
      for (var attempt = 0; attempt < 60; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (badge.evaluate().isNotEmpty == exists) {
          return;
        }
      }
    }

    testWidgets('已声明用途的节点有徽标，未声明的没有（继承来的不算）', (tester) async {
      await seedFixture();
      await TagRepository(db).updateTagUsageCodes('t-alpha', {TagUsage.time});
      await pumpPage(tester);

      expect(badgeOf('t-alpha'), findsOneWidget);
      expect(badgeOf('t-beta'), findsNothing);
      expect(badgeOf('t-gamma'), findsNothing);
      expect(
        tester.widget<Tooltip>(badgeOf('t-alpha')).message,
        '纳入时间表',
      );
    });

    testWidgets('浮窗勾选用途保存：写库为 time，徽标立刻出现', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await openUsageDialog(tester, 'alpha');
      expect(find.text(l10n.tagUsageDialogTitle), findsOneWidget);
      expect(find.text(l10n.tagUsageInheritHint), findsOneWidget);
      for (final usage in TagUsage.values) {
        expect(usageChecked(tester, usage), isFalse);
      }

      await tester.tap(usageCheckbox(TagUsage.time));
      await tester.pumpAndSettle();
      expect(usageChecked(tester, TagUsage.time), isTrue);

      await saveDialog(tester);
      expect(await waitUsageCodes(tester, 't-alpha', expected: 'time'), 'time');
      await waitForBadge(tester, badgeOf('t-alpha'), exists: true);
      expect(badgeOf('t-alpha'), findsOneWidget);
    });

    testWidgets('已有声明打开即勾选；全部取消 → 库写回 NULL，徽标消失', (tester) async {
      await seedFixture();
      await TagRepository(db).updateTagUsageCodes(
        't-alpha',
        {TagUsage.time, TagUsage.question},
      );
      await pumpPage(tester);
      expect(badgeOf('t-alpha'), findsOneWidget);

      await openUsageDialog(tester, 'alpha');
      expect(usageChecked(tester, TagUsage.time), isTrue);
      expect(usageChecked(tester, TagUsage.question), isTrue);
      expect(usageChecked(tester, TagUsage.knowledge), isFalse);

      await tester.tap(usageCheckbox(TagUsage.time));
      await tester.tap(usageCheckbox(TagUsage.question));
      await tester.pumpAndSettle();
      expect(usageChecked(tester, TagUsage.time), isFalse);
      expect(usageChecked(tester, TagUsage.question), isFalse);

      await saveDialog(tester);
      expect(await waitUsageCodes(tester, 't-alpha', expected: null), isNull);
      await waitForBadge(tester, badgeOf('t-alpha'), exists: false);
      expect(badgeOf('t-alpha'), findsNothing);
    });

    testWidgets('父标签声明用途、子标签没有：子节点无徽标，子对话框初值全不勾', (tester) async {
      await seedTag('t-parent', '父标签', createdAt: 1000);
      await seedTag('t-child', '子标签', parentId: 't-parent', createdAt: 2000);
      await TagRepository(db).updateTagUsageCodes('t-parent', {TagUsage.time});
      await pumpPage(tester);

      expect(badgeOf('t-parent'), findsOneWidget);

      // 默认全展开，子标签本来就在图上。
      expect(find.text('子标签'), findsOneWidget);
      expect(badgeOf('t-child'), findsNothing);

      await openUsageDialog(tester, '子标签');
      for (final usage in TagUsage.values) {
        expect(
          usageChecked(tester, usage),
          isFalse,
          reason: '初值是本级声明，不能把继承来的勾上',
        );
      }
    });
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
      expect(find.byType(Checkbox), findsNWidgets(5));
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('批量删除'), findsOneWidget);
      expect(find.text('批量移动'), findsOneWidget);
      // 新版没有行内菜单：节点动作都在设置浮窗里。
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('已选 0 项'), findsNothing);
      expect(find.byType(TagNodeSettingsDialog), findsNothing);

      // 再次进入：上一次的选择没有残留。
      await enterSelection(tester);
      expect(find.text('已选 0 项'), findsOneWidget);
    });

    testWidgets('整行点击勾选/取消勾选，计数跟随；点击不展开/折叠', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);
      // 默认展开，点节点只勾选，不改变折叠状态。
      expect(find.text('alpha-a'), findsOneWidget);

      await selectRow(tester, 'beta');
      expect(find.text('已选 2 项'), findsOneWidget);
      final checkboxes =
          tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(checkboxes[0].value, isTrue);
      expect(checkboxes[1].value, isFalse);
      expect(checkboxes[2].value, isFalse);
      expect(checkboxes[3].value, isTrue);
      expect(checkboxes[4].value, isFalse);

      await selectRow(tester, 'alpha');
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox)).first.value,
        isFalse,
      );
    });

    testWidgets('全选包含折叠起来的子层，再点取消全选', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);
      await toggle(tester, 't-alpha');
      expect(find.text('alpha-a'), findsNothing);

      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 5 项'), findsOneWidget);
      expect(find.text('清空选择'), findsOneWidget);

      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
    });

    testWidgets('展开箭头在多选中仍可展开分支，且不改变选择', (tester) async {
      await seedFixture();
      await pumpPage(tester);
      await enterSelection(tester);

      await toggle(tester, 't-alpha');
      expect(find.text('alpha-a'), findsNothing);
      await toggle(tester, 't-alpha');
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
      expect(nodeTitles(tester), <String>['gamma']);
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
      expect(find.byType(Checkbox), findsNWidgets(5));
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

    testWidgets('普通模式不回归：没有勾选框，点击节点打开设置浮窗', (tester) async {
      await seedFixture();
      await pumpPage(tester);

      expect(find.byType(Checkbox), findsNothing);
      await tapNode(tester, 'alpha');
      expect(find.byType(TagNodeSettingsDialog), findsOneWidget);
      expect(find.text('新建子标签'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('移动'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('关联内容'), findsOneWidget);
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
