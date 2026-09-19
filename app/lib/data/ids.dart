import 'package:uuid/uuid.dart';

/// Single source of truth for local record ids.
///
/// Why this exists: every repository used to build ids as
/// `'$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'`.
/// Two inserts inside the same microsecond therefore produced the SAME id,
/// which surfaced as real `UNIQUE constraint failed` errors - reproduced in
/// tests for `time_blocks` and `diffusion_logs` (a demo seed inserts several
/// rows back to back). Ids must never be derived from a clock alone.
///
/// The human-readable prefix is kept because it makes raw database rows and
/// error messages far easier to read; uniqueness comes from a random v4 UUID.
abstract final class Ids {
  static const Uuid _uuid = Uuid();

  /// A new id like `task-3f2a...`.
  static String next(String prefix) => '$prefix-${_uuid.v4()}';

  /// A new id without a prefix.
  static String uuid() => _uuid.v4();
}
