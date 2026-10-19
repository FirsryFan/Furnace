/// 题目编号检索：把搜索框里的输入解析成「想查哪个题号」。
///
/// 题号是 v24 起跨学科一个序列的人可读编号（`TR-00001`，见
/// `question_number.dart`）。搜索框要能把同一道题的各种写法归一到同一个号：
///
/// | 输入 | serialNo | normalizedLabel | hasPrefix |
/// | --- | --- | --- | --- |
/// | `TR-00001` / `tr-1` / `TR1` | 1 | `TR-00001` | true |
/// | `#7` / `＃７` | 7 | `TR-00007` | true |
/// | `12` / ` 12 ` / `１２` | 12 | `TR-00012` | false |
///
/// 判定规则（宁可返回 null，也不猜）：
/// - 先 trim 前后空白（含全角空格 U+3000）；
/// - 前缀只认 `TR`（大小写不敏感）与 `#`（也认全角 `＃`）；`TR` 后允许一个
///   半角或全角连字符，也允许没有连字符；`#` 后直接接数字；
/// - 其余字符必须全是半角或全角数字；数字之间/后缀夹任何其它字符都拒绝；
/// - 数字位数（含前导零）上限 [kMaxQuestionNumberQueryDigits] 位，超过直接
///   拒绝，不做截断；`0`、前导 `+/-`、负数一律拒绝；
/// - 题号从 1 开始，`0` / `00` / `TR-0` 都算无效。
///
/// 纯函数：不读 IO、不依赖时间/随机数，同一输入永远同一输出；失败返回 null，
/// **不抛异常**。[QuestionNumberQuery.normalizedLabel] 用 [formatQuestionSerial]
/// 生成（至少补到 [kQuestionSerialMinDigits] 位；超过 5 位不截断）。
library;

import 'question_number.dart';

/// 题号检索接受的最多数字位数（含前导零）。
///
/// 现有编号 5 位够用很久，但登记到 100000 以上也合法；这里给检索留到 9 位
/// （最大 999,999,999），再长就拒绝而不是静默截断。上限按输入的数字字符数算，
/// 所以 `TR-000000001`（9 位、值为 1）接受，`0000000001`（10 位）拒绝。
const int kMaxQuestionNumberQueryDigits = 9;

/// 一条解析成功的题号检索。
///
/// 不可变值对象；[serialNo] 是被问的题号，[normalizedLabel] 是规范写法，
/// [hasPrefix] 表示用户写没写 `TR` / `#`，[raw] 是 trim 后的原始输入（回显用，
/// 不参与相等性）。相等性只按 [serialNo]：`TR-00001`、`TR-1`、`1` 问的是同一道题。
///
/// 一般只用 [parseQuestionNumberQuery] 构造；直接调用构造函数时调用方要保证
/// `serialNo >= 1` 且 `normalizedLabel` 与之一致。
class QuestionNumberQuery {
  const QuestionNumberQuery({
    required this.serialNo,
    required this.normalizedLabel,
    required this.hasPrefix,
    required this.raw,
  });

  /// 题号（>= 1）。
  final int serialNo;

  /// 规范显示：`TR-00001`。
  final String normalizedLabel;

  /// 输入是否带 `TR` 或 `#` 前缀。
  final bool hasPrefix;

  /// trim 后的原始输入（回显/日志用，不参与相等性）。
  final String raw;

  @override
  bool operator ==(Object other) =>
      other is QuestionNumberQuery && other.serialNo == serialNo;

  @override
  int get hashCode => serialNo.hashCode;

  @override
  String toString() =>
      'QuestionNumberQuery($normalizedLabel, raw: $raw, hasPrefix: $hasPrefix)';
}

/// 解析一条题号检索；不是题号返回 null（不抛异常）。
///
/// 接受的写法见 library doc；`raw` 可以为空/纯空白/任意脏字符串，失败都只返回 null。
QuestionNumberQuery? parseQuestionNumberQuery(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  var rest = trimmed;
  var hasPrefix = false;
  if (rest.toUpperCase().startsWith(kQuestionSerialPrefix)) {
    rest = rest.substring(kQuestionSerialPrefix.length);
    hasPrefix = true;
    if (rest.startsWith('-') || rest.startsWith('－')) {
      rest = rest.substring(1);
    }
  } else if (rest.startsWith('#') || rest.startsWith('＃')) {
    rest = rest.substring(1);
    hasPrefix = true;
  }
  if (rest.isEmpty) return null;

  final StringBuffer digits = StringBuffer();
  for (final int rune in rest.runes) {
    final int? digit = _asciiDigitOf(rune);
    if (digit == null) return null;
    digits.write(digit);
  }
  final String text = digits.toString();
  if (text.length > kMaxQuestionNumberQueryDigits) return null;
  final int? serial = int.tryParse(text);
  if (serial == null || serial < 1) return null;

  return QuestionNumberQuery(
    serialNo: serial,
    normalizedLabel: formatQuestionSerial(serial),
    hasPrefix: hasPrefix,
    raw: trimmed,
  );
}

/// 搜索框分流：输入能完整解析成题号才是 true，其余都当关键词处理。
bool isQuestionNumberQuery(String raw) => parseQuestionNumberQuery(raw) != null;

/// 题号是否命中查询；[serialNo] 为 null（还没编号的题）永远不命中。
bool matchQuestionSerial(int? serialNo, QuestionNumberQuery query) =>
    serialNo != null && serialNo == query.serialNo;

/// 半角/全角数字转 0–9；其它字符返回 null。
int? _asciiDigitOf(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
  if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFF10;
  return null;
}
