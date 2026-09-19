import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'calendar_page.dart';
import 'time_board_page.dart';

/// The Time module (blueprint 3).
///
/// Calendar first, because "what does my day actually look like" is the
/// question this module answers; the block list stays available for bulk
/// editing and the legacy "today's schedule" summary.
class TimePage extends ConsumerStatefulWidget {
  const TimePage({super.key});

  @override
  ConsumerState<TimePage> createState() => _TimePageState();
}

class _TimePageState extends ConsumerState<TimePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          CalendarPage(),
          TimeBoardPage(embedded: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l10n.calendarDay,
          ),
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: l10n.timeTodaySchedule,
          ),
        ],
      ),
    );
  }
}
