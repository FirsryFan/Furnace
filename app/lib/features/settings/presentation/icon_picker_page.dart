/// The built-in icon picker (APPEARANCE_DESIGN decision D1).
///
/// Why a picker at all: the theme stores an icon **name** (`"tags": "star"`), and
/// expecting a user to type Material names correctly is not a feature. This page
/// shows the built-in catalog grouped by category with a search box, so choosing
/// an icon is clicking, not spelling.
///
/// Offline on purpose: the catalog is compiled in (`core/theme/app_icons.dart`),
/// so there is no icon pack to download, no cache to manage, and no network call
/// anywhere in this file - which is also why Android needs nothing special here.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../l10n/app_localizations.dart';

/// One slot's icon, chosen from the catalog.
///
/// The result travels back through `Navigator.pop` as a **catalog base name**.
/// [restoreDefault] is a sentinel rather than `null`: `null` is what a cancelled
/// route returns, and "the user backed out" must not be read as "reset the slot".
class IconPickerPage extends StatefulWidget {
  const IconPickerPage({super.key, required this.slot, this.current});

  /// The slot being edited, used for the title.
  final String slot;

  /// The base name currently in effect for that slot (highlighted in the grid).
  final String? current;

  /// Returned when the user asks for the slot's factory icon again.
  static const String restoreDefault = '';

  @override
  State<IconPickerPage> createState() => _IconPickerPageState();
}

class _IconPickerPageState extends State<IconPickerPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final matches = AppIcons.search(_search.text).toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.iconPickerTitle} · ${slotLabel(l10n, widget.slot)}'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: Text(l10n.iconPickerRestoreDefault),
            onPressed: () =>
                Navigator.of(context).pop(IconPickerPage.restoreDefault),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              autofocus: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.iconPickerSearch,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(child: Text(l10n.iconPickerEmpty))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    children: [
                      for (final entry in AppIcons.categories.entries)
                        if (entry.value.any(matches.contains))
                          _CategoryBlock(
                            label: iconCategoryLabel(l10n, entry.key),
                            names: [
                              for (final name in entry.value)
                                if (matches.contains(name)) name,
                            ],
                            selected: widget.current,
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.label,
    required this.names,
    required this.selected,
  });

  final String label;
  final List<String> names;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
          child: Text(label, style: theme.textTheme.titleSmall),
        ),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final name in names)
              _IconCell(
                name: name,
                isSelected: name == selected,
                onPick: () => Navigator.of(context).pop(name),
              ),
          ],
        ),
      ],
    );
  }
}

/// One tappable icon. The name is the tooltip *and* the semantics label, so the
/// grid is usable both by a mouse and by a screen reader.
class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.name,
    required this.isSelected,
    required this.onPick,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = AppIcons.catalog[name]?.outlined ?? Icons.help_outline;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          label: name,
          button: true,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? scheme.primary : Theme.of(context).dividerColor,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Icon(icon, color: isSelected ? scheme.primary : null),
          ),
        ),
      ),
    );
  }
}

/// The label of a slot. Shares the navigation labels on purpose: the slot *is*
/// the navigation place, and two strings for one place would drift apart.
///
/// Unknown slots fall back to their raw id - a picker row for a slot this build
/// does not know is still better than a crash.
String slotLabel(AppLocalizations l10n, String slot) => switch (slot) {
      'tags' => l10n.navTags,
      'thread' => l10n.navThread,
      'time' => l10n.navTime,
      'knowledge' => l10n.navAnki,
      'packages' => l10n.navPackages,
      'ai' => l10n.navAi,
      'settings' => l10n.navSettings,
      _ => slot,
    };

/// The display name of a catalog category.
///
/// Exhaustive on purpose: adding an `IconCategory` stops compiling here instead of
/// shipping a grid with an untranslated header.
String iconCategoryLabel(AppLocalizations l10n, IconCategory category) =>
    switch (category) {
      IconCategory.common => l10n.iconCategoryCommon,
      IconCategory.navigation => l10n.iconCategoryNavigation,
      IconCategory.time => l10n.iconCategoryTime,
      IconCategory.knowledge => l10n.iconCategoryKnowledge,
      IconCategory.objects => l10n.iconCategoryObjects,
      IconCategory.media => l10n.iconCategoryMedia,
      IconCategory.people => l10n.iconCategoryPeople,
      IconCategory.ai => l10n.iconCategoryAi,
      IconCategory.ui => l10n.iconCategoryUi,
    };
