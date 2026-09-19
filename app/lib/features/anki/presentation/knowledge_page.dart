import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'anki_manage_page.dart';
import 'knowledge_insight_page.dart';
import 'review_page.dart';

/// The Knowledge module (blueprint 4; user annotation 19).
///
/// Two tabs, because the practice screen must stay free of management
/// clutter: 复习 (flow) and 管理 (knowledge points / templates). "Today's
/// review" is a separate screen reached from the app bar.
class KnowledgePage extends ConsumerStatefulWidget {
  const KnowledgePage({super.key});

  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? l10n.navAnki : l10n.ankiManage),
        actions: [
          IconButton(
            tooltip: l10n.knowledgeInsight,
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const KnowledgeInsightPage(),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          ReviewPage(),
          AnkiManagePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.psychology_outlined),
            selectedIcon: const Icon(Icons.psychology),
            label: l10n.knowledgeReviewTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_books_outlined),
            selectedIcon: const Icon(Icons.library_books),
            label: l10n.ankiManage,
          ),
        ],
      ),
    );
  }
}
