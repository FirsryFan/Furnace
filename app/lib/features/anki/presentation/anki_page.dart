import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/srs/sm2_scheduler.dart';
import 'anki_manage_page.dart';

class _ReviewItem {
  const _ReviewItem({required this.state, required this.template});

  final CardState state;
  final CardTemplate template;
}

/// Anki module: spaced-repetition review session.
class AnkiPage extends ConsumerStatefulWidget {
  const AnkiPage({super.key});

  @override
  ConsumerState<AnkiPage> createState() => _AnkiPageState();
}

class _AnkiPageState extends ConsumerState<AnkiPage> {
  List<_ReviewItem> _items = [];
  bool _loading = true;
  bool _showAnswer = false;
  String? _submittedAnswer;
  bool? _isCorrect;
  String? _currentTemplateId;
  List<String> _mcqOptions = [];
  final TextEditingController _fillController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchDueItems();
  }

  @override
  void dispose() {
    _fillController.dispose();
    super.dispose();
  }

  Future<void> _loadDueItems() async {
    setState(() {
      _loading = true;
      _items = [];
      _showAnswer = false;
      _submittedAnswer = null;
      _isCorrect = null;
      _currentTemplateId = null;
      _mcqOptions = [];
    });
    await _fetchDueItems();
  }

  Future<void> _fetchDueItems() async {
    final repository = ref.read(ankiRepositoryProvider);
    final states = await repository.getDueCardStates(
      DateTime.now().millisecondsSinceEpoch,
    );
    final items = <_ReviewItem>[];
    for (final state in states) {
      // v2: the owning template id is derived from the presentation unit key
      // when present (preset cards); cloze/essay units arrive in R3/R5 and
      // have no preset template.
      final unit = state.unitKey;
      final templateId = state.cardTemplateId ??
          (unit != null && unit.startsWith('preset:')
              ? unit.substring('preset:'.length)
              : null);
      if (templateId == null) {
        continue;
      }
      final template = await repository.getCardTemplateById(templateId);
      if (template != null) {
        items.add(_ReviewItem(state: state, template: template));
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navAnki),
        actions: [
          IconButton(
            tooltip: l10n.ankiManage,
            icon: const Icon(Icons.manage_search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnkiManagePage()),
            ),
          ),
          IconButton(
            tooltip: l10n.ankiStartReview,
            icon: const Icon(Icons.refresh),
            onPressed: _loadDueItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyReview(l10n: l10n)
              : _buildReview(context, l10n),
    );
  }

  Widget _buildReview(BuildContext context, AppLocalizations l10n) {
    final item = _items.first;
    final template = item.template;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  template.question,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (template.type == 'mcq')
                  ..._buildMcqOptions(context, l10n, template),
                if (template.type == 'fill_blank' && !_showAnswer)
                  TextField(
                    controller: _fillController,
                    decoration: InputDecoration(
                      labelText: l10n.commonContent,
                      suffixIcon: IconButton(
                        onPressed: () => _submitFillBlank(template),
                        icon: const Icon(Icons.check),
                      ),
                    ),
                  ),
                if (_showAnswer) ...[
                  const Divider(height: 32),
                  if (_submittedAnswer != null) ...[
                    Text('${l10n.ankiYourAnswer}: $_submittedAnswer'),
                    Text(
                      _isCorrect == true ? l10n.ankiCorrect : l10n.ankiWrong,
                      style: TextStyle(
                        color: _isCorrect == true ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    template.answer,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 24),
                if (!_showAnswer)
                  FilledButton(
                    onPressed: _revealAnswer,
                    child: Text(l10n.ankiShowAnswer),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RatingButton(
                        label: l10n.ankiForgot,
                        color: Colors.red,
                        onPressed: () => _rate(SrsRating.forgot),
                      ),
                      _RatingButton(
                        label: l10n.ankiFuzzy,
                        color: Colors.orange,
                        onPressed: () => _rate(SrsRating.fuzzy),
                      ),
                      _RatingButton(
                        label: l10n.ankiRemembered,
                        color: Colors.green,
                        onPressed: () => _rate(SrsRating.remembered),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMcqOptions(
    BuildContext context,
    AppLocalizations l10n,
    CardTemplate template,
  ) {
    if (_currentTemplateId != template.id) {
      final options = template.options == null
          ? const <String>[]
          : template.options!.split('\u0001');
      _mcqOptions = List.of(options)..shuffle();
      _currentTemplateId = template.id;
    }
    return [
      for (final option in _mcqOptions)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _submittedAnswer = option;
                _isCorrect = option == template.answer;
                _showAnswer = true;
              });
            },
            child: Text(option),
          ),
        ),
    ];
  }

  void _submitFillBlank(CardTemplate template) {
    final submitted = _fillController.text.trim();
    setState(() {
      _submittedAnswer = submitted;
      _isCorrect = _normalize(submitted) == _normalize(template.answer);
      _showAnswer = true;
    });
  }

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、；：""（）]'), '');
  }

  void _revealAnswer() {
    setState(() => _showAnswer = true);
  }

  Future<void> _rate(SrsRating rating) async {
    final item = _items.first;
    await ref.read(ankiServiceProvider).reviewCard(
          cardTemplateId: item.template.id,
          rating: rating,
          now: DateTime.now(),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _items.removeAt(0);
      _showAnswer = false;
      _submittedAnswer = null;
      _isCorrect = null;
      _currentTemplateId = null;
      _mcqOptions = [];
      _fillController.clear();
    });
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration_outlined, size: 64),
          const SizedBox(height: 16),
          Text(l10n.ankiNoDueCards),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: color.withOpacity(0.15)),
      child: Text(label),
    );
  }
}
