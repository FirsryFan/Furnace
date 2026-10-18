/// 题目编号：**跨学科一个序列**的人可读号码（SCP 式，v24 / 轮次一百二十一）。
///
/// 用户口径（m 会话）："给每个题目一个独有的编号，就像 SCP 对异常有编号一样……
/// 我建议搞成一个整体的吧"——所以编号不分学科、全局连续，学科只体现在题目字段里。
///
/// 编号是**给人看的**：短、稳、能背、能抄在错题本上。它不是主键（主键仍是
/// `questions.id`），也不参与去重；跨设备 append 导入时两边的号可能撞（数据库
/// 没有唯一约束，见 `docs/QUESTION_BANK_DESIGN.md` 的未做清单），这是刻意接受的
/// 代价：append 导入宁可有两个"TR-00007"，也不要为了唯一性丢题。
library;

/// 显示时的最少位数，不足左边补 0：`1` → `TR-00001`。
///
/// 五位够用很久（十万道题）；超过五位不截断，`100000` → `TR-100000`，
/// 编号始终是"原来的数字"，不会因为位数变化换一个号。
const int kQuestionSerialMinDigits = 5;

/// 编号前缀。`TR` = THREADRIPPER（这个产品的内部代号）。
const String kQuestionSerialPrefix = 'TR';

/// 还没有编号时界面上显示的占位；不是 0 号，也不参与排序。
const String kUnnumberedQuestionLabel = 'TR-未编号';

/// 把号码格式化成 `TR-00001`。号码从 1 开始，0 / 负数当场报错。
String formatQuestionSerial(int serialNo) {
  if (serialNo < 1) {
    throw ArgumentError.value(serialNo, 'serialNo', '题目编号从 1 开始');
  }
  return '$kQuestionSerialPrefix-${serialNo.toString().padLeft(kQuestionSerialMinDigits, '0')}';
}

/// 界面上显示用的编号：有号给 `TR-00001`，没号给 [kUnnumberedQuestionLabel]。
String questionSerialLabel(int? serialNo) {
  final serial = serialNo;
  if (serial == null || serial < 1) {
    return kUnnumberedQuestionLabel;
  }
  return formatQuestionSerial(serial);
}

/// 下一个号：现有最大号 + 1；一条编号都没有时从 1 开始。
///
/// 传入 `null` 或 0 / 负数都当作"还没有号"。删题不回收号码——号码一旦给出去就
/// 是那道题的，回收会让旧笔记里的号指到另一道题上。
int nextQuestionSerial(int? highestSerialNo) {
  final highest = highestSerialNo;
  if (highest == null || highest < 1) {
    return 1;
  }
  return highest + 1;
}

/// 从显示形式里读回号码：`TR-00042` / `tr-42` / `00042` / `42` 都认。
///
/// 不是编号（空串、别的前缀、0、负数、带多余字符）返回 null。以后做"按编号搜题"
/// 时用这个，不在界面层再写一遍正则。
int? tryParseQuestionSerial(String text) {
  var value = text.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.length >= kQuestionSerialPrefix.length + 1 &&
      value
          .substring(0, kQuestionSerialPrefix.length)
          .toUpperCase() ==
          kQuestionSerialPrefix) {
    value = value.substring(kQuestionSerialPrefix.length);
    // 认 `TR-00042` 与 `TR00042` 两种写法。
    if (value.startsWith('-')) {
      value = value.substring(1);
    }
  }
  if (value.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(value)) {
    return null;
  }
  final serial = int.tryParse(value);
  if (serial == null || serial < 1) {
    return null;
  }
  return serial;
}
