/// 把「渲染成一句话的挖空题」按既有下标切开，供练习界面就地呈现（纯函数）。
///
/// 输入口径来自 `ReviewService._clozeItem`
/// （app/lib/features/anki/application/review_service.dart:655-657）：
/// `question = content.substring(0, start) + '______' + content.substring(start + length)`，
/// 也就是 `ReviewItem.question` 里本来就带着一串下划线；`slotStart` 是
/// `ReviewItem.slotStart`，`slotLength` 是空掉的那段原文长度。
///
/// 这里**不重新找空**（不猜、不搜关键词），只按调用方给的下标切开；
/// 对不上就返回 `null`，让调用方回退到旧的整句渲染。
library;

/// 一句挖空题的「空格前 / 空格 / 空格后」三段。
class ClozeLayout {
  const ClozeLayout(
      {required this.prefix, required this.blank, required this.suffix});

  /// 空格之前的原文。
  final String prefix;

  /// 题面里那串下划线本身（宽度按实际下划线数量，不写死 6）。
  final String blank;

  /// 空格之后的原文。
  final String suffix;

  /// 空格宽度（下划线字符数），界面用它决定输入框/占位宽度。
  int get blankWidth => blank.length;

  /// 未作答时的题面（与 `question` 逐字符相等）。
  String get masked => '$prefix$blank$suffix';

  /// 已揭示时的整句：把答案填回原来的位置。
  String reveal(String answer) => '$prefix$answer$suffix';

  /// 在 [question] 的 [slotStart] 处切出三段；切不动就返回 `null`。
  ///
  /// 与 `review_service.dart` 的 `_renderBlank` 保持同一口径：**至少 3 个下划线**才算空。
  static ClozeLayout? of({required String question, int? slotStart}) {
    if (slotStart == null) return null;
    if (slotStart < 0 || slotStart >= question.length) return null;

    final match = _blankPattern.matchAsPrefix(question, slotStart);
    if (match == null) return null;

    return ClozeLayout(
      prefix: question.substring(0, slotStart),
      blank: question.substring(slotStart, match.end),
      suffix: question.substring(match.end),
    );
  }

  /// 与 `_renderBlank` 同口径：3 个及以上连续下划线。
  static final RegExp _blankPattern = RegExp(r'_{3,}');
}
