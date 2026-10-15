import 'package:flutter/material.dart';

import '../../../../domain/services/scheduling/schedule_conflict.dart';
import '../../../../l10n/app_localizations.dart';

/// 用户在冲突弹窗里选了什么。
///
/// * [before] / [after]：按顺延候选挪动；
/// * [keep]：就要这个时刻，不改；
/// * 弹窗被点掉（返回 null）：**放弃这次选择**，保持原来的截止时间。
enum ScheduleConflictChoice { before, after, keep }

/// Q23 的冲突警告：把「这段撞上了哪个日程块」讲清楚，并给出两个顺延动作。
///
/// 弹窗只负责**出示**候选时刻，不自己算——`before` / `after` 由调用方用
/// [ScheduleConflict.freeMomentBefore] / [ScheduleConflict.freeMomentAfter]
/// 算好；为 null 表示那个方向找不到空闲时刻（顺延搜索有跳转上限，不硬造一个
/// 时刻），此时该动作禁用并说明原因（也不把动作藏起来让用户以为没这个选项）。
class ScheduleConflictDialog extends StatelessWidget {
  const ScheduleConflictDialog({
    super.key,
    required this.blockTitle,
    required this.blockStart,
    required this.blockEnd,
    required this.before,
    required this.after,
  });

  /// 撞上的日程块标题（原样显示）。
  final String blockTitle;

  /// 撞上的那一段真实起止。
  final DateTime blockStart;
  final DateTime blockEnd;

  /// 「移到这块之前」的候选时刻；null = 这个方向没有空位。
  final DateTime? before;

  /// 「移到这块之后」的候选时刻；null = 这个方向没有空位。
  final DateTime? after;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noFreeSlot = before == null || after == null;
    return AlertDialog(
      title: Text(l10n.tasksDueAtConflictTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tasksDueAtConflictBody(
              blockTitle,
              '${_format(blockStart)} → ${_format(blockEnd)}',
            ),
          ),
          if (noFreeSlot) ...[
            const SizedBox(height: 8),
            Text(
              l10n.tasksDueAtConflictNoFreeMoment,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: before == null
              ? null
              : () => Navigator.pop(context, ScheduleConflictChoice.before),
          child: Text(
            l10n.tasksDueAtConflictMoveBefore(
              before == null
                  ? l10n.tasksDueAtConflictNoFreeMoment
                  : _format(before!),
            ),
          ),
        ),
        TextButton(
          onPressed: after == null
              ? null
              : () => Navigator.pop(context, ScheduleConflictChoice.after),
          child: Text(
            l10n.tasksDueAtConflictMoveAfter(
              after == null
                  ? l10n.tasksDueAtConflictNoFreeMoment
                  : _format(after!),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ScheduleConflictChoice.keep),
          child: Text(l10n.tasksDueAtConflictKeep),
        ),
      ],
    );
  }

  String _format(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 弹出冲突警告；返回值见 [ScheduleConflictChoice]，被点掉时是 null。
Future<ScheduleConflictChoice?> showScheduleConflictWarning({
  required BuildContext context,
  required ScheduleConflictHit hit,
  required DateTime? before,
  required DateTime? after,
}) {
  return showDialog<ScheduleConflictChoice>(
    context: context,
    builder: (context) => ScheduleConflictDialog(
      blockTitle: hit.block.title,
      blockStart: hit.busy.start,
      blockEnd: hit.busy.end,
      before: before,
      after: after,
    ),
  );
}
