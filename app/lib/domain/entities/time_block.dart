/// Time block domain entity used by the scheduling engine.
library;

class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.available = true,
    this.energy,
    this.suitableFor,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool available;
  final String? energy;

  /// e.g. `memorize`, `deep_work`, `review`.
  final String? suitableFor;

  Duration get duration => end.difference(start);
}
