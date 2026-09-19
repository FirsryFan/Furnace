import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/time_template_repository.dart';
import '../../../domain/services/scheduling/time_window_engine.dart';
import '../../../l10n/app_localizations.dart';
import 'widgets/calendar_support.dart';

final calendarBlocksProvider = FutureProvider<List<TimeBlock>>((ref) {
  return ref.watch(timeBlockRepositoryProvider).getTimeBlocks();
});

final timeViewSettingsProvider = FutureProvider<TimeViewSetting>((ref) {
  return ref.watch(timeViewRepositoryProvider).ensure();
});

final timeTemplatesProvider = FutureProvider<List<TimeTemplate>>((ref) {
  return ref.watch(timeTemplateRepositoryProvider).getTemplates();
});

enum CalendarView { day, week, month, timeline }

/// The Time module's calendar (spec 1.2.2 + user feedback item 3).
///
/// Views: day / week / month / multi-year timeline.
/// - ISO week numbers, continuous across the timeline, on the left of the
///   week grid and of every month row.
/// - Right-click (desktop) or long-press (touch) opens the same context menu
///   on a day cell and on a week row.
/// - Month cells carry the real blocks; a detail panel below does the editing,
///   so cells stay readable while still supporting add / edit / delete.
/// - Blocks are translucent coloured cards; overlaps are allowed on purpose.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  CalendarView _view = CalendarView.day;
  DateTime _anchor = DateTime.now();

  /// Row size of the day/week grids. Defaults to 30 minutes, not a whole hour:
  /// an hour-only grid hides every half-hour boundary (user: "不要默认按小时来分").
  int _minutesPerRow = 30;
  DateTime? _selectedDay;

  static const double _rowBaseHeight = 44;

  double get _rowHeight => _rowBaseHeight * (60 / _minutesPerRow);

  DateTime get _dayStart => DateTime(_anchor.year, _anchor.month, _anchor.day);

  @override
  void initState() {
    super.initState();
    _selectedDay = _dayStart;
    _restorePreferences();
  }

  /// Minutes-per-row is a stored preference, not session-only state.
  Future<void> _restorePreferences() async {
    final settings = await ref.read(timeViewRepositoryProvider).ensure();
    if (!mounted) {
      return;
    }
    setState(() => _minutesPerRow = settings.minutesPerRow);
  }

  Future<void> _setMinutesPerRow(int value) async {
    setState(() => _minutesPerRow = value);
    // `chosen: true` records that this was a deliberate pick, so later
    // default changes never override it.
    await ref
        .read(timeViewRepositoryProvider)
        .update(minutesPerRow: value, chosen: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocksAsync = ref.watch(calendarBlocksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navTime),
        actions: [
          IconButton(
            tooltip: l10n.calendarToday,
            icon: const Icon(Icons.today),
            onPressed: () => setState(() {
              _anchor = DateTime.now();
              _selectedDay = _dayStart;
            }),
          ),
          if (_view != CalendarView.timeline)
            PopupMenuButton<int>(
              tooltip: l10n.calendarZoom,
              icon: const Icon(Icons.height),
              onSelected: _setMinutesPerRow,
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: 15,
                  checked: _minutesPerRow == 15,
                  child: Text(l10n.calendarZoom15),
                ),
                CheckedPopupMenuItem(
                  value: 30,
                  checked: _minutesPerRow == 30,
                  child: Text(l10n.calendarZoom30),
                ),
                CheckedPopupMenuItem(
                  value: 60,
                  checked: _minutesPerRow == 60,
                  child: Text(l10n.calendarZoom60),
                ),
              ],
            ),
          IconButton(
            tooltip: l10n.timeTemplates,
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () => showTemplatesSheet(context, ref, anchor: _anchor),
          ),
        ],
      ),
      body: Column(
        children: [
          _NavigationBar(
            title: _title(l10n),
            onPrev: () => setState(() => _anchor = _shift(-1)),
            onNext: () => setState(() => _anchor = _shift(1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<CalendarView>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: CalendarView.day,
                  icon: const Icon(Icons.view_day_outlined),
                  label: Text(l10n.calendarDay),
                ),
                ButtonSegment(
                  value: CalendarView.week,
                  icon: const Icon(Icons.view_week_outlined),
                  label: Text(l10n.calendarWeek),
                ),
                ButtonSegment(
                  value: CalendarView.month,
                  icon: const Icon(Icons.calendar_view_month),
                  label: Text(l10n.calendarMonth),
                ),
                ButtonSegment(
                  value: CalendarView.timeline,
                  icon: const Icon(Icons.timeline),
                  label: Text(l10n.calendarTimeline),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: blocksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('$error')),
              data: (blocks) => switch (_view) {
                CalendarView.day => _DayGrid(
                    day: _dayStart,
                    blocks: blocks,
                    rowHeight: _rowHeight,
                    minutesPerRow: _minutesPerRow,
                    onEmptyTap: _createAt,
                    onBlockTap: _editBlock,
                  ),
                CalendarView.week => _WeekGrid(
                    anchor: _anchor,
                    blocks: blocks,
                    rowHeight: _rowHeight,
                    minutesPerRow: _minutesPerRow,
                    onBlockTap: _editBlock,
                    onWeekMenu: _showWeekMenu,
                    onDayMenu: _showDayMenu,
                  ),
                CalendarView.month => _MonthView(
                    anchor: _anchor,
                    blocks: blocks,
                    selectedDay: _selectedDay ?? _dayStart,
                    onSelectDay: (day) => setState(() => _selectedDay = day),
                    onOpenDay: (day) => setState(() {
                      _anchor = day;
                      _selectedDay = day;
                      _view = CalendarView.day;
                    }),
                    onOpenWeek: (day) => setState(() {
                      _anchor = day;
                      _view = CalendarView.week;
                    }),
                    onDayMenu: _showDayMenu,
                    onEmptyTap: _createAt,
                    onBlockTap: _editBlock,
                  ),
                CalendarView.timeline => _TimelineView(
                    blocks: blocks,
                    anchor: _anchor,
                    onBlockTap: _editBlock,
                    onSelectDay: (day) => setState(() => _selectedDay = day),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- navigation ----------------------------------------------------------

  DateTime _shift(int direction) {
    switch (_view) {
      case CalendarView.day:
        return _anchor.add(Duration(days: direction));
      case CalendarView.week:
        return _anchor.add(Duration(days: 7 * direction));
      case CalendarView.month:
        return DateTime(_anchor.year, _anchor.month + direction, 1);
      case CalendarView.timeline:
        return DateTime(_anchor.year + direction, _anchor.month, 1);
    }
  }

  String _title(AppLocalizations l10n) {
    switch (_view) {
      case CalendarView.day:
        return '${_anchor.year}-${_two(_anchor.month)}-${_two(_anchor.day)}'
            '   ${IsoWeek.label(_anchor)}';
      case CalendarView.week:
        final start = IsoWeek.weekStart(_anchor);
        final end = start.add(const Duration(days: 6));
        return '${IsoWeek.label(start)}   ${_two(start.month)}/${_two(start.day)}'
            ' - ${_two(end.month)}/${_two(end.day)}';
      case CalendarView.month:
        return '${_anchor.year}-${_two(_anchor.month)}';
      case CalendarView.timeline:
        return '${_anchor.year}';
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  // --- context menus -------------------------------------------------------

  /// Right-click / long-press on a day cell.
  Future<void> _showDayMenu(DateTime day) async {
    final l10n = AppLocalizations.of(context);
    final choice = await _contextMenu(
      <_MenuItem>[
        _MenuItem('new', Icons.add, l10n.calendarAddBlock),
        _MenuItem('template', Icons.dashboard_customize_outlined,
            l10n.timeApplyTemplate),
        _MenuItem('day', Icons.view_day_outlined, l10n.calendarOpenDay),
        _MenuItem('week', Icons.view_week_outlined, l10n.calendarOpenWeek),
      ],
      title: '${day.year}-${_two(day.month)}-${_two(day.day)}  '
          '${IsoWeek.label(day)}',
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case 'new':
        await _createAt(day.add(const Duration(hours: 8)));
      case 'template':
        await showTemplatesSheet(context, ref, anchor: day, days: [day]);
      case 'day':
        setState(() {
          _anchor = day;
          _selectedDay = day;
          _view = CalendarView.day;
        });
      case 'week':
        setState(() {
          _anchor = day;
          _view = CalendarView.week;
        });
    }
  }

  /// Right-click / long-press on a week row: selects the whole week and offers
  /// the week-level actions.
  Future<void> _showWeekMenu(DateTime weekStart) async {
    final l10n = AppLocalizations.of(context);
    final days = IsoWeek.weekDays(weekStart);
    final choice = await _contextMenu(
      <_MenuItem>[
        _MenuItem('open', Icons.view_week_outlined, l10n.calendarOpenWeek),
        _MenuItem('template-day', Icons.wb_sunny_outlined,
            l10n.timeApplyDayTemplate),
        _MenuItem('template-week', Icons.date_range_outlined,
            l10n.timeApplyWeekTemplate),
        _MenuItem('new', Icons.add, l10n.calendarAddBlock),
      ],
      title: '${l10n.calendarWeek} ${IsoWeek.label(weekStart)}',
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case 'open':
        setState(() {
          _anchor = weekStart;
          _view = CalendarView.week;
        });
      case 'template-day':
        await showTemplatesSheet(context, ref,
            anchor: weekStart, days: [weekStart], kind: 'day');
      case 'template-week':
        await showTemplatesSheet(context, ref,
            anchor: weekStart, days: days, kind: 'week');
      case 'new':
        await _createAt(weekStart.add(const Duration(hours: 8)));
    }
  }

  Future<String?> _contextMenu(
    List<_MenuItem> items, {
    required String title,
  }) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? const Size(400, 400);
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width * 0.25,
        size.height * 0.3,
        size.width * 0.25,
        size.height * 0.3,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(title, style: Theme.of(context).textTheme.labelMedium),
        ),
        const PopupMenuDivider(),
        for (final item in items)
          PopupMenuItem<String>(
            value: item.value,
            child: Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: 10),
                Text(item.label),
              ],
            ),
          ),
      ],
    );
  }

  // --- block operations ----------------------------------------------------

  Future<void> _createAt(DateTime moment) async {
    final l10n = AppLocalizations.of(context);
    final title = TextEditingController();
    var start = moment;
    var end = moment.add(const Duration(hours: 1));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(l10n.calendarAddBlock),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(context).pop(true),
                  decoration: InputDecoration(labelText: l10n.commonTitle),
                ),
                const SizedBox(height: 8),
                _MomentRow(
                  label: l10n.commonStart,
                  moment: start,
                  onChanged: (value) => setLocal(() => start = value),
                ),
                _MomentRow(
                  label: l10n.commonEnd,
                  moment: end,
                  onChanged: (value) => setLocal(() => end = value),
                ),
                const SizedBox(height: 8),
                Text(l10n.timeArbitraryRangeHint,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: l10n.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IconButton.filled(
              tooltip: l10n.commonSave,
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (saved != true || title.text.trim().isEmpty) {
      return;
    }
    await ref.read(timeBlockRepositoryProvider).createTimeBlock(
          title: title.text.trim(),
          startAt: start.millisecondsSinceEpoch,
          endAt: end.millisecondsSinceEpoch,
        );
    ref.invalidate(calendarBlocksProvider);
  }

  Future<void> _editBlock(TimeBlock block) async {
    final l10n = AppLocalizations.of(context);
    final title = TextEditingController(text: block.title);
    var start = DateTime.fromMillisecondsSinceEpoch(block.startAt);
    var end = DateTime.fromMillisecondsSinceEpoch(block.endAt);
    var available = block.available;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.event_note,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.commonEdit)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => Navigator.of(context).pop(true),
                  decoration: InputDecoration(labelText: l10n.commonTitle),
                ),
                const SizedBox(height: 8),
                _MomentRow(
                  label: l10n.commonStart,
                  moment: start,
                  onChanged: (value) => setLocal(() => start = value),
                ),
                _MomentRow(
                  label: l10n.commonEnd,
                  moment: end,
                  onChanged: (value) => setLocal(() => end = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: available,
                  title: Text(l10n.timeAvailable),
                  subtitle: Text(l10n.timeBusyHint),
                  onChanged: (value) => setLocal(() => available = value),
                ),
                Text(l10n.timeArbitraryRangeHint,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(timeBlockRepositoryProvider)
                    .deleteTimeBlock(block.id);
                if (context.mounted) {
                  Navigator.of(context).pop(false);
                }
              },
            ),
            IconButton(
              tooltip: l10n.commonCancel,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IconButton.filled(
              tooltip: l10n.commonSave,
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref.read(timeBlockRepositoryProvider).updateTimeBlock(
            block.id,
            title: title.text.trim(),
            startAt: start.millisecondsSinceEpoch,
            endAt: end.millisecondsSinceEpoch,
            available: available,
          );
    }
    ref.invalidate(calendarBlocksProvider);
  }
}

class _MenuItem {
  const _MenuItem(this.value, this.icon, this.label);

  final String value;
  final IconData icon;
  final String label;
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.title,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.calendarPrev,
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          IconButton(
            tooltip: l10n.calendarNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Start/end picker for an arbitrary moment (no snapping to whole hours).
class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.label,
    required this.moment,
    required this.onChanged,
  });

  final String label;
  final DateTime moment;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final two = (int value) => value.toString().padLeft(2, '0');
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        TextButton.icon(
          icon: const Icon(Icons.schedule, size: 16),
          label: Text('${two(moment.hour)}:${two(moment.minute)}'),
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(moment),
            );
            if (picked != null) {
              onChanged(DateTime(moment.year, moment.month, moment.day,
                  picked.hour, picked.minute));
            }
          },
        ),
        const Spacer(),
        IconButton(
          tooltip: l10n.timeMinusFiveMinutes,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () =>
              onChanged(moment.subtract(const Duration(minutes: 5))),
        ),
        IconButton(
          tooltip: l10n.timePlusFiveMinutes,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 16),
          onPressed: () => onChanged(moment.add(const Duration(minutes: 5))),
        ),
      ],
    );
  }
}

// ============================================================================
// Occurrence expansion
// ============================================================================

typedef Occurrence = ({TimeBlock block, DateTime start, DateTime end});

/// Expands [blocks] into concrete occurrences overlapping [from, to), clipped
/// to that window so multi-day blocks render correctly inside one day column.
List<Occurrence> _occurrences(
  List<TimeBlock> blocks,
  DateTime from,
  DateTime to,
) {
  final result = <Occurrence>[];
  for (final block in blocks) {
    final schedule = ScheduleBlock(
      id: block.id,
      title: block.title,
      startAt: DateTime.fromMillisecondsSinceEpoch(block.startAt),
      endAt: DateTime.fromMillisecondsSinceEpoch(block.endAt),
      available: block.available,
      repeatRule: block.repeatRule,
    );
    for (final interval in TimeWindowEngine.expand(
        block: schedule, windowStart: from, windowEnd: to)) {
      result.add((block: block, start: interval.start, end: interval.end));
    }
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

// ============================================================================
// Day grid
// ============================================================================

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.day,
    required this.blocks,
    required this.rowHeight,
    required this.minutesPerRow,
    required this.onEmptyTap,
    required this.onBlockTap,
  });

  final DateTime day;
  final List<TimeBlock> blocks;
  final double rowHeight;
  final int minutesPerRow;
  final ValueChanged<DateTime> onEmptyTap;
  final ValueChanged<TimeBlock> onBlockTap;

  /// The single-day timeline keeps a readable width instead of stretching
  /// across a wide desktop window, and never collapses below a usable width
  /// (user: "日视图要有宽度").
  static const double _maxWidth = 760;
  static const double _minWidth = 340;

  @override
  Widget build(BuildContext context) {
    final rows = (24 * 60) ~/ minutesPerRow;
    final occurrences =
        _occurrences(blocks, day, day.add(const Duration(days: 1)));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(_minWidth, _maxWidth);
        final needsHorizontalScroll = constraints.maxWidth < _minWidth;

        final grid = SizedBox(
          width: width,
          height: rows * rowHeight,
          child: Stack(
            children: [
              Column(
                children: [
                  for (var row = 0; row < rows; row++)
                    _HourRow(
                      label: rowLabel(row, minutesPerRow),
                      height: rowHeight,
                      majorTick: isMajorTick(row, minutesPerRow),
                      onTap: () => onEmptyTap(
                        day.add(Duration(minutes: row * minutesPerRow)),
                      ),
                    ),
                ],
              ),
              for (final occurrence in occurrences)
                _BlockOverlay(
                  block: occurrence.block,
                  start: occurrence.start,
                  end: occurrence.end,
                  day: day,
                  rowHeight: rowHeight,
                  minutesPerRow: minutesPerRow,
                  left: 52,
                  right: 10,
                  onTap: () => onBlockTap(occurrence.block),
                ),
            ],
          ),
        );

        final centered = Center(child: grid);
        final body = needsHorizontalScroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              )
            : centered;

        return SingleChildScrollView(child: body);
      },
    );
  }
}

/// Row label for a sub-hour grid.
///
/// With a 30- or 15-minute row the grid no longer starts a new row on every
/// whole hour, so the label shows the actual time, and only the whole hour is
/// emphasised (user: "不要默认按小时来分").
String? rowLabel(int row, int minutesPerRow) {
  final minutes = row * minutesPerRow;
  final two = (int value) => value.toString().padLeft(2, '0');
  return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
}

/// True when the row starts a whole hour, which draws the stronger divider.
bool isMajorTick(int row, int minutesPerRow) =>
    (row * minutesPerRow) % 60 == 0;

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.label,
    required this.height,
    required this.onTap,
    this.majorTick = true,
  });

  final String? label;
  final double height;
  final VoidCallback onTap;

  /// Whole hours draw a stronger divider, sub-hour rows a faint one.
  final bool majorTick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.dividerColor
                  .withValues(alpha: majorTick ? 0.4 : 0.16),
            ),
          ),
        ),
        child: label == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Text(
                  label!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: majorTick
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

// ============================================================================
// Week grid: week-number column + right-click on the row / a day
// ============================================================================

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.anchor,
    required this.blocks,
    required this.rowHeight,
    required this.minutesPerRow,
    required this.onBlockTap,
    required this.onWeekMenu,
    required this.onDayMenu,
  });

  final DateTime anchor;
  final List<TimeBlock> blocks;
  final double rowHeight;
  final int minutesPerRow;
  final ValueChanged<TimeBlock> onBlockTap;
  final ValueChanged<DateTime> onWeekMenu;
  final ValueChanged<DateTime> onDayMenu;

  /// Seven day columns stay legible down to this width; below it the grid
  /// scrolls horizontally instead of squashing into unreadable slivers.
  static const double _minWidth = 560;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = IsoWeek.weekDays(anchor);
    final weekStart = days.first;
    final rows = (24 * 60) ~/ minutesPerRow;

    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = SizedBox(
          width: constraints.maxWidth < _minWidth ? _minWidth : null,
          child: _buildGrid(context, l10n, theme, days, weekStart, rows),
        );
        if (constraints.maxWidth >= _minWidth) {
          return grid;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: grid,
        );
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    List<DateTime> days,
    DateTime weekStart,
    int rows,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          GestureDetector(
            onSecondaryTap: () => onWeekMenu(weekStart),
            onLongPress: () => onWeekMenu(weekStart),
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: Text(
                        'W${IsoWeek.number(weekStart)}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  for (final day in days)
                    Expanded(
                      child: GestureDetector(
                        onSecondaryTap: () => onDayMenu(day),
                        onLongPress: () => onDayMenu(day),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: Text(
                              '${weekdayLabel(l10n, day.weekday)}\n${day.day}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: rows * rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      for (var row = 0; row < rows; row++)
                        SizedBox(
                          height: rowHeight,
                          child: isMajorTick(row, minutesPerRow)
                              ? Text(
                                  rowLabel(row, minutesPerRow) ?? '',
                                  style: theme.textTheme.labelSmall,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                for (final day in days)
                  Expanded(
                    child: GestureDetector(
                      onSecondaryTap: () => onDayMenu(day),
                      onLongPress: () => onDayMenu(day),
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              for (var row = 0; row < rows; row++)
                                Container(
                                  height: rowHeight,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: theme.dividerColor.withValues(
                                          alpha: isMajorTick(
                                                  row, minutesPerRow)
                                              ? 0.4
                                              : 0.16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          for (final occurrence in _occurrences(blocks, day,
                              day.add(const Duration(days: 1))))
                            _BlockOverlay(
                              block: occurrence.block,
                              start: occurrence.start,
                              end: occurrence.end,
                              day: day,
                              rowHeight: rowHeight,
                              minutesPerRow: minutesPerRow,
                              left: 0,
                              right: 2,
                              onTap: () => onBlockTap(occurrence.block),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Month view: cells hold the blocks, the panel below does the editing
// ============================================================================

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.anchor,
    required this.blocks,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onOpenWeek,
    required this.onDayMenu,
    required this.onEmptyTap,
    required this.onBlockTap,
  });

  final DateTime anchor;
  final List<TimeBlock> blocks;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<DateTime> onOpenWeek;
  final ValueChanged<DateTime> onDayMenu;
  final ValueChanged<DateTime> onEmptyTap;
  final ValueChanged<TimeBlock> onBlockTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final first = DateTime(anchor.year, anchor.month, 1);
    final last = DateTime(anchor.year, anchor.month + 1, 0);
    final gridStart = IsoWeek.weekStart(first);
    final weeks = <List<DateTime>>[];
    var cursor = gridStart;
    while (!cursor.isAfter(last)) {
      weeks.add([for (var i = 0; i < 7; i++) cursor.add(Duration(days: i))]);
      cursor = cursor.add(const Duration(days: 7));
    }

    final selected =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final selectedOccurrences = _occurrences(
        blocks, selected, selected.add(const Duration(days: 1)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const SizedBox(width: 48),
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: Center(
                    child: Text(weekdayLabel(l10n, weekday),
                        style: theme.textTheme.bodySmall),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 26 * weeks.length.toDouble(),
          child: ListView(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final week in weeks)
                _MonthWeekRow(
                  week: week,
                  month: anchor.month,
                  blocks: blocks,
                  selected: selected,
                  onSelectDay: onSelectDay,
                  onOpenDay: onOpenDay,
                  onOpenWeek: onOpenWeek,
                  onDayMenu: onDayMenu,
                  onBlockTap: onBlockTap,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _DayDetailPanel(
            day: selected,
            occurrences: selectedOccurrences,
            onAdd: () => onEmptyTap(selected.add(const Duration(hours: 8))),
            onOpenDay: () => onOpenDay(selected),
            onOpenWeek: () => onOpenWeek(selected),
            onEdit: onBlockTap,
          ),
        ),
      ],
    );
  }
}

class _MonthWeekRow extends StatelessWidget {
  const _MonthWeekRow({
    required this.week,
    required this.month,
    required this.blocks,
    required this.selected,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onOpenWeek,
    required this.onDayMenu,
    required this.onBlockTap,
  });

  final List<DateTime> week;
  final int month;
  final List<TimeBlock> blocks;
  final DateTime selected;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<DateTime> onOpenWeek;
  final ValueChanged<DateTime> onDayMenu;
  final ValueChanged<TimeBlock> onBlockTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          GestureDetector(
            onSecondaryTap: () => onOpenWeek(week.first),
            onLongPress: () => onOpenWeek(week.first),
            child: SizedBox(
              width: 48,
              child: Center(
                child: Text(
                  'W${IsoWeek.number(week.first)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          for (final day in week)
            Expanded(
              child: _MonthCell(
                day: day,
                inMonth: day.month == month,
                isSelected: day.year == selected.year &&
                    day.month == selected.month &&
                    day.day == selected.day,
                blocks: blocks,
                onSelect: () => onSelectDay(day),
                onOpen: () => onOpenDay(day),
                onMenu: () => onDayMenu(day),
                onBlockTap: onBlockTap,
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.blocks,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
    required this.onBlockTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isSelected;
  final List<TimeBlock> blocks;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final ValueChanged<TimeBlock> onBlockTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occurrences =
        _occurrences(blocks, day, day.add(const Duration(days: 1)));
    if (!inMonth) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
      );
    }

    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onOpen,
      onSecondaryTap: onMenu,
      onLongPress: onMenu,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: 0.35),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            Text('${day.day}', style: theme.textTheme.labelSmall),
            const SizedBox(width: 2),
            // Translucent coloured cards; the count badge keeps the cell
            // readable when a day is packed.
            Expanded(
              child: Row(
                children: [
                  for (final occurrence in occurrences.take(3))
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onBlockTap(occurrence.block),
                        child: Container(
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: BoxDecoration(
                            color: BlockPalette.fill(
                              BlockPalette.colorFor(
                                  BlockPalette.slotForId(occurrence.block.id)),
                              busy: !occurrence.block.available,
                            ),
                            border: Border.all(
                              color: BlockPalette.border(
                                BlockPalette.colorFor(BlockPalette.slotForId(
                                    occurrence.block.id)),
                                busy: !occurrence.block.available,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  if (occurrences.length > 3)
                    Text('+${occurrences.length - 3}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month view's detail panel for the selected day: month cells stay
/// compact, every day-level operation lives here.
class _DayDetailPanel extends ConsumerWidget {
  const _DayDetailPanel({
    required this.day,
    required this.occurrences,
    required this.onAdd,
    required this.onOpenDay,
    required this.onOpenWeek,
    required this.onEdit,
  });

  final DateTime day;
  final List<Occurrence> occurrences;
  final VoidCallback onAdd;
  final VoidCallback onOpenDay;
  final VoidCallback onOpenWeek;
  final ValueChanged<TimeBlock> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final two = (int value) => value.toString().padLeft(2, '0');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
          child: Row(
            children: [
              Icon(Icons.event, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${day.year}-${two(day.month)}-${two(day.day)}   '
                  '${IsoWeek.label(day)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l10n.calendarAddBlock,
                icon: const Icon(Icons.add),
                onPressed: onAdd,
              ),
              IconButton(
                tooltip: l10n.calendarOpenDay,
                icon: const Icon(Icons.view_day_outlined),
                onPressed: onOpenDay,
              ),
              IconButton(
                tooltip: l10n.calendarOpenWeek,
                icon: const Icon(Icons.view_week_outlined),
                onPressed: onOpenWeek,
              ),
            ],
          ),
        ),
        Expanded(
          child: occurrences.isEmpty
              ? Center(child: Text(l10n.calendarDayEmpty))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final occurrence in occurrences)
                      _OccurrenceRow(
                        occurrence: occurrence,
                        onTap: () => onEdit(occurrence.block),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({required this.occurrence, required this.onTap});

  final Occurrence occurrence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final base = BlockPalette.colorFor(
        BlockPalette.slotForId(occurrence.block.id));
    final busy = !occurrence.block.available;
    final two = (int value) => value.toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 30,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(occurrence.block.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${two(occurrence.start.hour)}:${two(occurrence.start.minute)}'
                    ' - ${two(occurrence.end.hour)}:${two(occurrence.end.minute)}'
                    '${busy ? '' : '  ·  ${l10n.timeAvailable}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.commonEdit,
              icon: const Icon(Icons.tune, size: 18),
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Multi-year timeline
// ============================================================================

class _TimelineView extends ConsumerWidget {
  const _TimelineView({
    required this.blocks,
    required this.anchor,
    required this.onBlockTap,
    required this.onSelectDay,
  });

  final List<TimeBlock> blocks;
  final DateTime anchor;
  final ValueChanged<TimeBlock> onBlockTap;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(timeViewSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('$error')),
      data: (settings) {
        final span = settings.timelineSpanDays;
        final pxPerDay = settings.timelinePxPerDay;
        final collapsed = settings.timelineCollapsed;
        final start = DateTime(anchor.year, 1, 1);
        final end = start.add(Duration(days: span));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.timelineZoomOut,
                    icon: const Icon(Icons.zoom_out),
                    onPressed: pxPerDay <= 1
                        ? null
                        : () => ref
                            .read(timeViewRepositoryProvider)
                            .update(timelinePxPerDay: pxPerDay / 1.5),
                  ),
                  IconButton(
                    tooltip: l10n.timelineZoomIn,
                    icon: const Icon(Icons.zoom_in),
                    onPressed: pxPerDay >= 40
                        ? null
                        : () => ref
                            .read(timeViewRepositoryProvider)
                            .update(timelinePxPerDay: pxPerDay * 1.5),
                  ),
                  Expanded(
                    child: Slider(
                      value: span.clamp(30, 3650).toDouble(),
                      min: 30,
                      max: 3650,
                      divisions: 362,
                      label: l10n.timelineSpanDays(span),
                      onChanged: (value) => ref
                          .read(timeViewRepositoryProvider)
                          .update(timelineSpanDays: value.round()),
                    ),
                  ),
                  Text(l10n.timelineSpanDays(span),
                      style: Theme.of(context).textTheme.bodySmall),
                  IconButton(
                    tooltip:
                        collapsed ? l10n.timelineUnfold : l10n.timelineFold,
                    icon: Icon(
                        collapsed ? Icons.unfold_more : Icons.unfold_less),
                    onPressed: () => ref
                        .read(timeViewRepositoryProvider)
                        .update(timelineCollapsed: !collapsed),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = (constraints.maxWidth - 56)
                      .clamp(100.0, double.infinity);
                  // Unfolded: one strip scrolling horizontally.
                  // Folded: the same days wrapped into bands scrolling
                  // vertically (user feedback 3).
                  final perRow = collapsed
                      ? (available / pxPerDay).floor().clamp(7, 100000)
                      : span;
                  final rows = (span / perRow).ceil();

                  return SingleChildScrollView(
                    scrollDirection:
                        collapsed ? Axis.vertical : Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var row = 0; row < rows; row++)
                          _TimelineRow(
                            rowStart: start.add(Duration(days: row * perRow)),
                            days: perRow,
                            pxPerDay: pxPerDay,
                            blocks: blocks,
                            rangeEnd: end,
                            onBlockTap: onBlockTap,
                            onSelectDay: onSelectDay,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.rowStart,
    required this.days,
    required this.pxPerDay,
    required this.blocks,
    required this.rangeEnd,
    required this.onBlockTap,
    required this.onSelectDay,
  });

  final DateTime rowStart;
  final int days;
  final double pxPerDay;
  final List<TimeBlock> blocks;
  final DateTime rangeEnd;
  final ValueChanged<TimeBlock> onBlockTap;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowEnd = rowStart.add(Duration(days: days));
    final clippedEnd = rowEnd.isAfter(rangeEnd) ? rangeEnd : rowEnd;
    final occurrences = _occurrences(blocks, rowStart, clippedEnd);
    const rowHeight = 40.0;

    return SizedBox(
      height: rowHeight + 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Text(
                '${rowStart.year}-${rowStart.month.toString().padLeft(2, '0')}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          SizedBox(
            width: days * pxPerDay,
            height: rowHeight + 16,
            child: Stack(
              children: [
                for (var i = 0; i < days; i++)
                  Positioned(
                    left: i * pxPerDay,
                    top: 0,
                    bottom: 0,
                    width: pxPerDay,
                    child: GestureDetector(
                      onTap: () =>
                          onSelectDay(rowStart.add(Duration(days: i))),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: rowStart.add(Duration(days: i)).day == 1
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.6)
                                  : theme.dividerColor.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final occurrence in occurrences)
                  Positioned(
                    left: occurrence.start.difference(rowStart).inMinutes /
                        1440 *
                        pxPerDay,
                    top: 14,
                    height: rowHeight - 18,
                    width: ((occurrence.end.difference(occurrence.start).inMinutes /
                                1440) *
                            pxPerDay)
                        .clamp(2.0, days * pxPerDay),
                    child: GestureDetector(
                      onTap: () => onBlockTap(occurrence.block),
                      child: Container(
                        decoration: BoxDecoration(
                          color: BlockPalette.fill(
                            BlockPalette.colorFor(
                                BlockPalette.slotForId(occurrence.block.id)),
                            busy: !occurrence.block.available,
                          ),
                          border: Border.all(
                            color: BlockPalette.border(
                              BlockPalette.colorFor(
                                  BlockPalette.slotForId(occurrence.block.id)),
                              busy: !occurrence.block.available,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Block overlay (day + week grids) - translucent coloured card
// ============================================================================

class _BlockOverlay extends StatelessWidget {
  const _BlockOverlay({
    required this.block,
    required this.start,
    required this.end,
    required this.day,
    required this.rowHeight,
    required this.minutesPerRow,
    required this.left,
    required this.right,
    required this.onTap,
  });

  final TimeBlock block;
  final DateTime start;
  final DateTime end;
  final DateTime day;
  final double rowHeight;
  final int minutesPerRow;
  final double left;
  final double right;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pixelsPerMinute = rowHeight / minutesPerRow;
    final top = start.difference(day).inMinutes * pixelsPerMinute;
    final height =
        (end.difference(start).inMinutes * pixelsPerMinute).clamp(16.0, 4000.0);
    final busy = !block.available;
    final base = BlockPalette.colorFor(BlockPalette.slotForId(block.id));

    return Positioned(
      top: top,
      left: left,
      right: right,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          decoration: BoxDecoration(
            color: BlockPalette.fill(base, busy: busy),
            border: Border.all(
              color: BlockPalette.border(base, busy: busy),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            block.title,
            maxLines: height > 34 ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Templates
// ============================================================================

/// Opens the template sheet: apply an existing day/week template to [days], or
/// save the current day/week as a new template (user feedback 3).
Future<void> showTemplatesSheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime anchor,
  List<DateTime>? days,
  String? kind,
}) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(timeTemplateRepositoryProvider);
  final templates = await repo.getTemplates(kind: kind);
  if (!context.mounted) {
    return;
  }
  final targetDays = days ?? IsoWeek.weekDays(anchor);
  final effectiveKind = kind ?? 'week';

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.timeTemplates,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                // Quick scope switch: a week template paints the whole week,
                // a day template paints one day (user feedback 3).
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'day', label: Text(l10n.calendarDay)),
                    ButtonSegment(
                        value: 'week', label: Text(l10n.calendarWeek)),
                  ],
                  selected: {effectiveKind},
                  onSelectionChanged: (selection) {
                    Navigator.of(context).pop();
                    showTemplatesSheet(
                      context,
                      ref,
                      anchor: anchor,
                      days: selection.first == 'week'
                          ? IsoWeek.weekDays(anchor)
                          : [anchor],
                      kind: selection.first,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.timeNoTemplates, textAlign: TextAlign.center),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final template in templates)
                    ListTile(
                      leading: const Icon(Icons.event_available),
                      title: Text(template.name),
                      subtitle: Text(
                        l10n.timeTemplateBlockCount(
                            repo.blocksOf(template).length),
                      ),
                      trailing: IconButton(
                        tooltip: l10n.timeDeleteTemplate,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await repo.delete(template.id);
                          ref.invalidate(timeTemplatesProvider);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      onTap: () async {
                        final created = await repo.applyToDays(
                          template: template,
                          days: targetDays,
                        );
                        ref.invalidate(calendarBlocksProvider);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.timeTemplateApplied(created)),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          const Divider(height: 16),
          // Saving the current day/week as a template closes the loop: lay it
          // out once, reuse it on every future week.
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(l10n.timeSaveTemplate),
            onTap: () async {
              final name = await _askTemplateName(context, l10n);
              if (name == null || name.isEmpty) {
                return;
              }
              final saved = await _captureTemplate(
                ref: ref,
                name: name,
                kind: effectiveKind,
                days: targetDays,
              );
              ref.invalidate(timeTemplatesProvider);
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.timeTemplateApplied(saved))),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Builds a template from whatever blocks already sit on [days].
Future<int> _captureTemplate({
  required WidgetRef ref,
  required String name,
  required String kind,
  required List<DateTime> days,
}) async {
  final blocks = await ref.read(timeBlockRepositoryProvider).getTimeBlocks();
  final inRange = <TimeBlock>[];
  for (final block in blocks) {
    final start = DateTime.fromMillisecondsSinceEpoch(block.startAt);
    final day = DateTime(start.year, start.month, start.day);
    if (days.any((d) =>
        d.year == day.year && d.month == day.month && d.day == day.day)) {
      inRange.add(block);
    }
  }
  final templateBlocks = <TemplateBlock>[
    for (final block in inRange)
      TemplateBlock(
        title: block.title,
        startMinutes: DateTime.fromMillisecondsSinceEpoch(block.startAt).hour *
                60 +
            DateTime.fromMillisecondsSinceEpoch(block.startAt).minute,
        endMinutes: DateTime.fromMillisecondsSinceEpoch(block.endAt).hour * 60 +
            DateTime.fromMillisecondsSinceEpoch(block.endAt).minute,
        available: block.available,
        repeatRule: block.repeatRule,
        dows: kind == 'week'
            ? [DateTime.fromMillisecondsSinceEpoch(block.startAt).weekday]
            : const [],
        colorSlot: BlockPalette.slotForId(block.id),
      ),
  ];
  await ref.read(timeTemplateRepositoryProvider).save(
        name: name,
        kind: kind,
        blocks: templateBlocks,
      );
  return templateBlocks.length;
}

Future<String?> _askTemplateName(
  BuildContext context,
  AppLocalizations l10n,
) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.timeSaveTemplate),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
        decoration: InputDecoration(labelText: l10n.commonName),
      ),
      actions: [
        IconButton(
          tooltip: l10n.commonCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        IconButton.filled(
          tooltip: l10n.commonSave,
          icon: const Icon(Icons.check),
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    ),
  );
}

/// Short weekday label (1 = Monday .. 7 = Sunday).
String weekdayLabel(AppLocalizations l10n, int weekday) {
  switch (weekday) {
    case 1:
      return l10n.calendarWeekday1;
    case 2:
      return l10n.calendarWeekday2;
    case 3:
      return l10n.calendarWeekday3;
    case 4:
      return l10n.calendarWeekday4;
    case 5:
      return l10n.calendarWeekday5;
    case 6:
      return l10n.calendarWeekday6;
    default:
      return l10n.calendarWeekday7;
  }
}
