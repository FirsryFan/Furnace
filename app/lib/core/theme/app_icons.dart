// The built-in icon catalog behind the semantic icon slots (APPEARANCE_DESIGN
// decision D1).
//
// Three things this file is deliberately *not*:
//
//   * **a runtime icon lookup.** Every entry is a `const` pair of `IconData`
//     constants, so Flutter's `--tree-shake-icons` keeps working. Building them
//     from a code point (`IconData(0xe5c4)`) or from a string would defeat it and
//     ship the whole font.
//   * **"every Material icon".** The catalog is a curated set of names grouped by
//     category, which is what keeps the picker usable instead of a haystack (the
//     design doc budgets 100-200 entries).
//   * **a second source of truth for labels.** A slot says *where* an icon is
//     used; the words still come from the l10n layer.
//
// The theme document stores only the **base name** (`"tags": "star"`), never a
// code point, so a theme file stays readable and survives Flutter upgrades.
// A name the catalog does not know falls back to that slot's factory icon
// instead of throwing: a theme file may carry names from somewhere else.
//
// The catalog was derived from the SDK's own `Icons` class: every name here has
// both `Icons.<name>` and `Icons.<name>_outlined`, and the two differ (pinned by
// `test/core/theme/app_icons_test.dart`).
library;

import 'package:flutter/material.dart';

/// The picker's grouping: "what kind of thing is this", not "where does it go" -
/// a slot already says where it goes, and a category may be added without
/// touching any slot.
enum IconCategory {
  common,
  navigation,
  time,
  knowledge,
  objects,
  media,
  people,
  ai,
  ui,
}

/// One catalog entry: the same Material icon in its outlined and filled form.
@immutable
class AppIcon {
  const AppIcon({required this.outlined, required this.filled});

  /// The unselected state (navigation rail/bar, list rows, picker grid).
  final IconData outlined;

  /// The selected / emphasised state.
  final IconData filled;
}

/// The catalog plus the rules that turn a theme's `icons` map into an [IconData].
abstract final class AppIcons {
  /// The configurable slots. **Fixed on purpose** (design doc D1): the icon
  /// setting names *semantic places*, not individual widgets, so the set is
  /// small and stable.
  static const List<String> slots = <String>[
    'tags',
    'thread',
    'time',
    'knowledge',
    'packages',
    'ai',
    'settings',
  ];

  /// The factory icon of each slot: exactly the icons the shell hard-coded
  /// before D1, so an untouched theme renders what the app always rendered.
  static const Map<String, String> slotDefaults = <String, String>{
    'tags': 'account_tree',
    'thread': 'bolt',
    'time': 'schedule',
    'knowledge': 'psychology',
    'packages': 'library_books',
    'ai': 'smart_toy',
    'settings': 'settings',
  };

  /// The catalog by category. The declaration order is the picker's display
  /// order, and [names] follows it, so the grid is deterministic.
  static const Map<IconCategory, List<String>> categories =
      <IconCategory, List<String>>{
    IconCategory.common: <String>['star', 'favorite', 'home', 'search', 'bookmark', 'check_circle', 'done', 'add', 'edit', 'delete', 'visibility', 'lock', 'key', 'flag', 'label', 'push_pin', 'thumb_up', 'celebration', 'workspace_premium', 'savings', 'bolt'],
    IconCategory.navigation: <String>['menu', 'arrow_back', 'arrow_forward', 'arrow_upward', 'arrow_downward', 'chevron_left', 'chevron_right', 'expand_more', 'expand_less', 'more_horiz', 'more_vert', 'close', 'refresh', 'open_in_new', 'swap_horiz', 'double_arrow', 'unfold_more', 'login', 'logout'],
    IconCategory.time: <String>['schedule', 'calendar_today', 'alarm', 'timer', 'hourglass_empty', 'event', 'event_note', 'update', 'watch_later', 'history', 'today', 'date_range', 'timelapse', 'pending', 'alarm_on', 'event_available'],
    IconCategory.knowledge: <String>['account_tree', 'psychology', 'school', 'menu_book', 'lightbulb', 'science', 'history_edu', 'auto_stories', 'rule', 'functions', 'calculate', 'translate', 'spellcheck', 'library_add', 'emoji_objects', 'insights', 'schema', 'polyline'],
    IconCategory.objects: <String>['folder', 'description', 'library_books', 'inventory_2', 'archive', 'book', 'article', 'note', 'sticky_note_2', 'attachment', 'link', 'folder_open', 'receipt_long', 'category', 'layers', 'workspaces', 'snippet_folder', 'topic'],
    IconCategory.media: <String>['play_arrow', 'pause', 'stop', 'image', 'videocam', 'mic', 'volume_up', 'headset', 'photo_camera', 'music_note', 'movie', 'slideshow', 'graphic_eq', 'album', 'camera_alt', 'screenshot', 'podcasts', 'radio'],
    IconCategory.people: <String>['person', 'group', 'face', 'badge', 'diversity_3', 'support_agent', 'manage_accounts', 'supervisor_account', 'assignment_ind', 'contact_page', 'fingerprint', 'accessibility_new', 'self_improvement', 'record_voice_over'],
    IconCategory.ai: <String>['smart_toy', 'auto_awesome', 'memory', 'hub', 'model_training', 'rocket_launch', 'tips_and_updates', 'online_prediction', 'blur_on', 'psychology_alt', 'assistant'],
    IconCategory.ui: <String>['tune', 'palette', 'dashboard', 'grid_view', 'view_list', 'filter_list', 'view_module', 'widgets', 'apps', 'format_size', 'text_fields', 'color_lens', 'gradient', 'animation', 'dark_mode', 'light_mode', 'straighten', 'aspect_ratio', 'settings'],
  };

  /// Base name -> the outlined/filled pair. Keyed by the name a theme stores.
  static const Map<String, AppIcon> catalog = <String, AppIcon>{
  'star': AppIcon(outlined: Icons.star_outlined, filled: Icons.star),
  'favorite': AppIcon(outlined: Icons.favorite_outlined, filled: Icons.favorite),
  'home': AppIcon(outlined: Icons.home_outlined, filled: Icons.home),
  'search': AppIcon(outlined: Icons.search_outlined, filled: Icons.search),
  'bookmark': AppIcon(outlined: Icons.bookmark_outlined, filled: Icons.bookmark),
  'check_circle': AppIcon(outlined: Icons.check_circle_outlined, filled: Icons.check_circle),
  'done': AppIcon(outlined: Icons.done_outlined, filled: Icons.done),
  'add': AppIcon(outlined: Icons.add_outlined, filled: Icons.add),
  'edit': AppIcon(outlined: Icons.edit_outlined, filled: Icons.edit),
  'delete': AppIcon(outlined: Icons.delete_outlined, filled: Icons.delete),
  'visibility': AppIcon(outlined: Icons.visibility_outlined, filled: Icons.visibility),
  'lock': AppIcon(outlined: Icons.lock_outlined, filled: Icons.lock),
  'key': AppIcon(outlined: Icons.key_outlined, filled: Icons.key),
  'flag': AppIcon(outlined: Icons.flag_outlined, filled: Icons.flag),
  'label': AppIcon(outlined: Icons.label_outlined, filled: Icons.label),
  'push_pin': AppIcon(outlined: Icons.push_pin_outlined, filled: Icons.push_pin),
  'thumb_up': AppIcon(outlined: Icons.thumb_up_outlined, filled: Icons.thumb_up),
  'celebration': AppIcon(outlined: Icons.celebration_outlined, filled: Icons.celebration),
  'workspace_premium': AppIcon(outlined: Icons.workspace_premium_outlined, filled: Icons.workspace_premium),
  'savings': AppIcon(outlined: Icons.savings_outlined, filled: Icons.savings),
  'bolt': AppIcon(outlined: Icons.bolt_outlined, filled: Icons.bolt),
  'menu': AppIcon(outlined: Icons.menu_outlined, filled: Icons.menu),
  'arrow_back': AppIcon(outlined: Icons.arrow_back_outlined, filled: Icons.arrow_back),
  'arrow_forward': AppIcon(outlined: Icons.arrow_forward_outlined, filled: Icons.arrow_forward),
  'arrow_upward': AppIcon(outlined: Icons.arrow_upward_outlined, filled: Icons.arrow_upward),
  'arrow_downward': AppIcon(outlined: Icons.arrow_downward_outlined, filled: Icons.arrow_downward),
  'chevron_left': AppIcon(outlined: Icons.chevron_left_outlined, filled: Icons.chevron_left),
  'chevron_right': AppIcon(outlined: Icons.chevron_right_outlined, filled: Icons.chevron_right),
  'expand_more': AppIcon(outlined: Icons.expand_more_outlined, filled: Icons.expand_more),
  'expand_less': AppIcon(outlined: Icons.expand_less_outlined, filled: Icons.expand_less),
  'more_horiz': AppIcon(outlined: Icons.more_horiz_outlined, filled: Icons.more_horiz),
  'more_vert': AppIcon(outlined: Icons.more_vert_outlined, filled: Icons.more_vert),
  'close': AppIcon(outlined: Icons.close_outlined, filled: Icons.close),
  'refresh': AppIcon(outlined: Icons.refresh_outlined, filled: Icons.refresh),
  'open_in_new': AppIcon(outlined: Icons.open_in_new_outlined, filled: Icons.open_in_new),
  'swap_horiz': AppIcon(outlined: Icons.swap_horiz_outlined, filled: Icons.swap_horiz),
  'double_arrow': AppIcon(outlined: Icons.double_arrow_outlined, filled: Icons.double_arrow),
  'unfold_more': AppIcon(outlined: Icons.unfold_more_outlined, filled: Icons.unfold_more),
  'login': AppIcon(outlined: Icons.login_outlined, filled: Icons.login),
  'logout': AppIcon(outlined: Icons.logout_outlined, filled: Icons.logout),
  'schedule': AppIcon(outlined: Icons.schedule_outlined, filled: Icons.schedule),
  'calendar_today': AppIcon(outlined: Icons.calendar_today_outlined, filled: Icons.calendar_today),
  'alarm': AppIcon(outlined: Icons.alarm_outlined, filled: Icons.alarm),
  'timer': AppIcon(outlined: Icons.timer_outlined, filled: Icons.timer),
  'hourglass_empty': AppIcon(outlined: Icons.hourglass_empty_outlined, filled: Icons.hourglass_empty),
  'event': AppIcon(outlined: Icons.event_outlined, filled: Icons.event),
  'event_note': AppIcon(outlined: Icons.event_note_outlined, filled: Icons.event_note),
  'update': AppIcon(outlined: Icons.update_outlined, filled: Icons.update),
  'watch_later': AppIcon(outlined: Icons.watch_later_outlined, filled: Icons.watch_later),
  'history': AppIcon(outlined: Icons.history_outlined, filled: Icons.history),
  'today': AppIcon(outlined: Icons.today_outlined, filled: Icons.today),
  'date_range': AppIcon(outlined: Icons.date_range_outlined, filled: Icons.date_range),
  'timelapse': AppIcon(outlined: Icons.timelapse_outlined, filled: Icons.timelapse),
  'pending': AppIcon(outlined: Icons.pending_outlined, filled: Icons.pending),
  'alarm_on': AppIcon(outlined: Icons.alarm_on_outlined, filled: Icons.alarm_on),
  'event_available': AppIcon(outlined: Icons.event_available_outlined, filled: Icons.event_available),
  'account_tree': AppIcon(outlined: Icons.account_tree_outlined, filled: Icons.account_tree),
  'psychology': AppIcon(outlined: Icons.psychology_outlined, filled: Icons.psychology),
  'school': AppIcon(outlined: Icons.school_outlined, filled: Icons.school),
  'menu_book': AppIcon(outlined: Icons.menu_book_outlined, filled: Icons.menu_book),
  'lightbulb': AppIcon(outlined: Icons.lightbulb_outlined, filled: Icons.lightbulb),
  'science': AppIcon(outlined: Icons.science_outlined, filled: Icons.science),
  'history_edu': AppIcon(outlined: Icons.history_edu_outlined, filled: Icons.history_edu),
  'auto_stories': AppIcon(outlined: Icons.auto_stories_outlined, filled: Icons.auto_stories),
  'rule': AppIcon(outlined: Icons.rule_outlined, filled: Icons.rule),
  'functions': AppIcon(outlined: Icons.functions_outlined, filled: Icons.functions),
  'calculate': AppIcon(outlined: Icons.calculate_outlined, filled: Icons.calculate),
  'translate': AppIcon(outlined: Icons.translate_outlined, filled: Icons.translate),
  'spellcheck': AppIcon(outlined: Icons.spellcheck_outlined, filled: Icons.spellcheck),
  'library_add': AppIcon(outlined: Icons.library_add_outlined, filled: Icons.library_add),
  'emoji_objects': AppIcon(outlined: Icons.emoji_objects_outlined, filled: Icons.emoji_objects),
  'insights': AppIcon(outlined: Icons.insights_outlined, filled: Icons.insights),
  'schema': AppIcon(outlined: Icons.schema_outlined, filled: Icons.schema),
  'polyline': AppIcon(outlined: Icons.polyline_outlined, filled: Icons.polyline),
  'folder': AppIcon(outlined: Icons.folder_outlined, filled: Icons.folder),
  'description': AppIcon(outlined: Icons.description_outlined, filled: Icons.description),
  'library_books': AppIcon(outlined: Icons.library_books_outlined, filled: Icons.library_books),
  'inventory_2': AppIcon(outlined: Icons.inventory_2_outlined, filled: Icons.inventory_2),
  'archive': AppIcon(outlined: Icons.archive_outlined, filled: Icons.archive),
  'book': AppIcon(outlined: Icons.book_outlined, filled: Icons.book),
  'article': AppIcon(outlined: Icons.article_outlined, filled: Icons.article),
  'note': AppIcon(outlined: Icons.note_outlined, filled: Icons.note),
  'sticky_note_2': AppIcon(outlined: Icons.sticky_note_2_outlined, filled: Icons.sticky_note_2),
  'attachment': AppIcon(outlined: Icons.attachment_outlined, filled: Icons.attachment),
  'link': AppIcon(outlined: Icons.link_outlined, filled: Icons.link),
  'folder_open': AppIcon(outlined: Icons.folder_open_outlined, filled: Icons.folder_open),
  'receipt_long': AppIcon(outlined: Icons.receipt_long_outlined, filled: Icons.receipt_long),
  'category': AppIcon(outlined: Icons.category_outlined, filled: Icons.category),
  'layers': AppIcon(outlined: Icons.layers_outlined, filled: Icons.layers),
  'workspaces': AppIcon(outlined: Icons.workspaces_outlined, filled: Icons.workspaces),
  'snippet_folder': AppIcon(outlined: Icons.snippet_folder_outlined, filled: Icons.snippet_folder),
  'topic': AppIcon(outlined: Icons.topic_outlined, filled: Icons.topic),
  'play_arrow': AppIcon(outlined: Icons.play_arrow_outlined, filled: Icons.play_arrow),
  'pause': AppIcon(outlined: Icons.pause_outlined, filled: Icons.pause),
  'stop': AppIcon(outlined: Icons.stop_outlined, filled: Icons.stop),
  'image': AppIcon(outlined: Icons.image_outlined, filled: Icons.image),
  'videocam': AppIcon(outlined: Icons.videocam_outlined, filled: Icons.videocam),
  'mic': AppIcon(outlined: Icons.mic_outlined, filled: Icons.mic),
  'volume_up': AppIcon(outlined: Icons.volume_up_outlined, filled: Icons.volume_up),
  'headset': AppIcon(outlined: Icons.headset_outlined, filled: Icons.headset),
  'photo_camera': AppIcon(outlined: Icons.photo_camera_outlined, filled: Icons.photo_camera),
  'music_note': AppIcon(outlined: Icons.music_note_outlined, filled: Icons.music_note),
  'movie': AppIcon(outlined: Icons.movie_outlined, filled: Icons.movie),
  'slideshow': AppIcon(outlined: Icons.slideshow_outlined, filled: Icons.slideshow),
  'graphic_eq': AppIcon(outlined: Icons.graphic_eq_outlined, filled: Icons.graphic_eq),
  'album': AppIcon(outlined: Icons.album_outlined, filled: Icons.album),
  'camera_alt': AppIcon(outlined: Icons.camera_alt_outlined, filled: Icons.camera_alt),
  'screenshot': AppIcon(outlined: Icons.screenshot_outlined, filled: Icons.screenshot),
  'podcasts': AppIcon(outlined: Icons.podcasts_outlined, filled: Icons.podcasts),
  'radio': AppIcon(outlined: Icons.radio_outlined, filled: Icons.radio),
  'person': AppIcon(outlined: Icons.person_outlined, filled: Icons.person),
  'group': AppIcon(outlined: Icons.group_outlined, filled: Icons.group),
  'face': AppIcon(outlined: Icons.face_outlined, filled: Icons.face),
  'badge': AppIcon(outlined: Icons.badge_outlined, filled: Icons.badge),
  'diversity_3': AppIcon(outlined: Icons.diversity_3_outlined, filled: Icons.diversity_3),
  'support_agent': AppIcon(outlined: Icons.support_agent_outlined, filled: Icons.support_agent),
  'manage_accounts': AppIcon(outlined: Icons.manage_accounts_outlined, filled: Icons.manage_accounts),
  'supervisor_account': AppIcon(outlined: Icons.supervisor_account_outlined, filled: Icons.supervisor_account),
  'assignment_ind': AppIcon(outlined: Icons.assignment_ind_outlined, filled: Icons.assignment_ind),
  'contact_page': AppIcon(outlined: Icons.contact_page_outlined, filled: Icons.contact_page),
  'fingerprint': AppIcon(outlined: Icons.fingerprint_outlined, filled: Icons.fingerprint),
  'accessibility_new': AppIcon(outlined: Icons.accessibility_new_outlined, filled: Icons.accessibility_new),
  'self_improvement': AppIcon(outlined: Icons.self_improvement_outlined, filled: Icons.self_improvement),
  'record_voice_over': AppIcon(outlined: Icons.record_voice_over_outlined, filled: Icons.record_voice_over),
  'smart_toy': AppIcon(outlined: Icons.smart_toy_outlined, filled: Icons.smart_toy),
  'auto_awesome': AppIcon(outlined: Icons.auto_awesome_outlined, filled: Icons.auto_awesome),
  'memory': AppIcon(outlined: Icons.memory_outlined, filled: Icons.memory),
  'hub': AppIcon(outlined: Icons.hub_outlined, filled: Icons.hub),
  'model_training': AppIcon(outlined: Icons.model_training_outlined, filled: Icons.model_training),
  'rocket_launch': AppIcon(outlined: Icons.rocket_launch_outlined, filled: Icons.rocket_launch),
  'tips_and_updates': AppIcon(outlined: Icons.tips_and_updates_outlined, filled: Icons.tips_and_updates),
  'online_prediction': AppIcon(outlined: Icons.online_prediction_outlined, filled: Icons.online_prediction),
  'blur_on': AppIcon(outlined: Icons.blur_on_outlined, filled: Icons.blur_on),
  'psychology_alt': AppIcon(outlined: Icons.psychology_alt_outlined, filled: Icons.psychology_alt),
  'assistant': AppIcon(outlined: Icons.assistant_outlined, filled: Icons.assistant),
  'tune': AppIcon(outlined: Icons.tune_outlined, filled: Icons.tune),
  'palette': AppIcon(outlined: Icons.palette_outlined, filled: Icons.palette),
  'dashboard': AppIcon(outlined: Icons.dashboard_outlined, filled: Icons.dashboard),
  'grid_view': AppIcon(outlined: Icons.grid_view_outlined, filled: Icons.grid_view),
  'view_list': AppIcon(outlined: Icons.view_list_outlined, filled: Icons.view_list),
  'filter_list': AppIcon(outlined: Icons.filter_list_outlined, filled: Icons.filter_list),
  'view_module': AppIcon(outlined: Icons.view_module_outlined, filled: Icons.view_module),
  'widgets': AppIcon(outlined: Icons.widgets_outlined, filled: Icons.widgets),
  'apps': AppIcon(outlined: Icons.apps_outlined, filled: Icons.apps),
  'format_size': AppIcon(outlined: Icons.format_size_outlined, filled: Icons.format_size),
  'text_fields': AppIcon(outlined: Icons.text_fields_outlined, filled: Icons.text_fields),
  'color_lens': AppIcon(outlined: Icons.color_lens_outlined, filled: Icons.color_lens),
  'gradient': AppIcon(outlined: Icons.gradient_outlined, filled: Icons.gradient),
  'animation': AppIcon(outlined: Icons.animation_outlined, filled: Icons.animation),
  'dark_mode': AppIcon(outlined: Icons.dark_mode_outlined, filled: Icons.dark_mode),
  'light_mode': AppIcon(outlined: Icons.light_mode_outlined, filled: Icons.light_mode),
  'straighten': AppIcon(outlined: Icons.straighten_outlined, filled: Icons.straighten),
  'aspect_ratio': AppIcon(outlined: Icons.aspect_ratio_outlined, filled: Icons.aspect_ratio),
  'settings': AppIcon(outlined: Icons.settings_outlined, filled: Icons.settings),
  };

  /// True when [name] is a name this build can render.
  static bool isKnown(String? name) => name != null && catalog.containsKey(name);

  /// The name [slot] actually renders: the configured one when the catalog knows
  /// it, otherwise the slot's factory default. Never throws for a name - only for
  /// a slot that is not one of [slots], which is a programming error.
  static String effectiveName(String slot, Map<String, String> icons) {
    final configured = icons[slot];
    if (isKnown(configured)) {
      return configured!;
    }
    final fallback = slotDefaults[slot];
    if (fallback == null) {
      throw ArgumentError.value(
        slot,
        'slot',
        'unknown slot (expected one of ${slots.join(', ')})',
      );
    }
    return fallback;
  }

  /// The pair for [slot] under [icons].
  static AppIcon iconFor(String slot, Map<String, String> icons) =>
      catalog[effectiveName(slot, icons)]!;

  /// The [IconData] for [slot]: outlined when not selected, filled when selected.
  static IconData iconData(
    String slot,
    Map<String, String> icons, {
    required bool filled,
  }) {
    final icon = iconFor(slot, icons);
    return filled ? icon.filled : icon.outlined;
  }

  /// Every catalog name, in category order.
  static List<String> get names =>
      <String>[for (final group in categories.values) ...group];

  /// Names containing [query] (case-insensitive); an empty query returns all.
  static List<String> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return names;
    }
    return <String>[for (final name in names) if (name.contains(needle)) name];
  }

  /// The category [name] belongs to, or null when it is not in the catalog.
  static IconCategory? categoryOf(String name) {
    for (final entry in categories.entries) {
      if (entry.value.contains(name)) {
        return entry.key;
      }
    }
    return null;
  }
}