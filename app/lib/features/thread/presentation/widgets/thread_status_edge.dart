import 'package:flutter/material.dart';

import '../../../../data/database/database.dart';

/// Lifecycle status of one Thread event, expressed as the colour of the
/// coloured edge on its bar (user feedback item 4).
///
/// Semantics fixed by the user:
///   green  = completed
///   blue   = waiting (the expected moment has not arrived yet)
///   yellow = the expected moment has passed
///   red    = the deadline has passed
///
/// Deadline beats expected time: an event past its deadline is red even if its
/// expected moment is also in the past.
enum ThreadStatus {
  completed,
  waiting,
  expectedPassed,
  deadlinePassed;

  Color get color => switch (this) {
        ThreadStatus.completed => const Color(0xFF2E7D32), // green 800
        ThreadStatus.waiting => const Color(0xFF1565C0), // blue 800
        ThreadStatus.expectedPassed => const Color(0xFFF9A825), // yellow 800
        ThreadStatus.deadlinePassed => const Color(0xFFC62828), // red 800
      };

  /// Resolves the status of [task] relative to [now].
  static ThreadStatus of(Task task, DateTime now) {
    if (task.status == 'done' || task.completedAt != null) {
      return ThreadStatus.completed;
    }
    final dueAt = task.dueAt;
    if (dueAt != null && dueAt <= now.millisecondsSinceEpoch) {
      return ThreadStatus.deadlinePassed;
    }
    final expectedAt = task.expectedAt;
    if (expectedAt != null && expectedAt <= now.millisecondsSinceEpoch) {
      return ThreadStatus.expectedPassed;
    }
    return ThreadStatus.waiting;
  }
}

/// The coloured left edge of an event bar.
class ThreadStatusEdge extends StatelessWidget {
  const ThreadStatusEdge({
    super.key,
    required this.status,
    this.width = 5,
    this.height = 44,
  });

  final ThreadStatus status;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
