/// 题库列表排序：纯函数，把读表结果 [QuestionLibraryEntry] 按用户选的顺序排好。
///
/// 为什么单独一个文件：题库页（`question_library_page.dart`）与后续可能的 AI
/// 工具都要按同一套规则排题库；排序规则写一次、单测钉死，页面只负责把
/// [QuestionLibrarySort] 传给读表/筛选之后的结果。
///
/// 三条规则：
/// - [QuestionLibrarySort.newest]：入参原样顺序（读表本身是「最新在前」），
///   只包一层新列表；
/// - [QuestionLibrarySort.serial]：题号升序，未编号排最后，同号按 questionId
///   升序兜底（确定）；
/// - [QuestionLibrarySort.wrongFirst]：答错次数降序，同次数保持入参原顺序
///   （显式稳定排序——`List.sort` 本身不保证稳定）。
///
/// 三种都返回 `List.unmodifiable` 的新列表，绝不原地改入参。纯 Dart：不读 IO、
/// 不依赖时间/随机数，同一输入永远同一输出。
library;

import 'question_library_reader.dart';

/// 题库列表可选的排序方式。
enum QuestionLibrarySort {
  /// 最新在前：读表顺序原样返回（不再重排）。
  newest,

  /// 题号升序；未编号（serialNo 为 null）排最后，同号按 questionId 升序。
  serial,

  /// 错题优先：答错次数降序，同次数保持入参原顺序。
  wrongFirst,
}

/// 排序偏好的持久化 code（schema v34 的
/// `local_settings.question_library_sort_mode`）。
///
/// 库里只存 code、不存中文标签：改文案不会让已存值变成读不懂的字符串，换语言
/// 之后读回来的还是同一个档位。code 一经发出就不再改（改了等于把老安装的选择
/// 变成"未知值"）。
String questionLibrarySortCode(QuestionLibrarySort sort) {
  return switch (sort) {
    QuestionLibrarySort.newest => 'newest',
    QuestionLibrarySort.serial => 'serial',
    QuestionLibrarySort.wrongFirst => 'wrong_first',
  };
}

/// 把库里存的 code 读回 [QuestionLibrarySort]。
///
/// NULL / 空串 / 未知 code 一律回落出厂档位 [QuestionLibrarySort.newest]：
/// "用户没选过"与"存的是未来版本才认识的档位"都该得到同一套行为（按最新排），
/// 而不是报错或换一个用户没选的排序。
QuestionLibrarySort questionLibrarySortFromStorage(String? code) {
  return switch (code?.trim()) {
    'serial' => QuestionLibrarySort.serial,
    'wrong_first' => QuestionLibrarySort.wrongFirst,
    _ => QuestionLibrarySort.newest,
  };
}

/// 按 [sort] 排序 [entries]，返回不可变的新列表。
///
/// 空表返回空列表；[entries] 本身不会被修改。
List<QuestionLibraryEntry> sortQuestionLibraryEntries(
  List<QuestionLibraryEntry> entries,
  QuestionLibrarySort sort,
) {
  return switch (sort) {
    QuestionLibrarySort.newest =>
      List<QuestionLibraryEntry>.unmodifiable(entries),
    QuestionLibrarySort.serial => _stableSorted(entries, _compareSerial),
    QuestionLibrarySort.wrongFirst =>
      _stableSorted(entries, _compareWrongFirst),
  };
}

/// 用带原始下标的装饰排序实现稳定排序：比较相等时按入参下标升序。
List<QuestionLibraryEntry> _stableSorted(
  List<QuestionLibraryEntry> entries,
  int Function(QuestionLibraryEntry a, QuestionLibraryEntry b) compare,
) {
  final List<int> indices = List<int>.generate(entries.length, (int i) => i);
  indices.sort((int a, int b) {
    final int byValue = compare(entries[a], entries[b]);
    return byValue != 0 ? byValue : a.compareTo(b);
  });
  final List<QuestionLibraryEntry> sorted = <QuestionLibraryEntry>[
    for (final int index in indices) entries[index],
  ];
  return List<QuestionLibraryEntry>.unmodifiable(sorted);
}

/// 题号升序；null 排最后；同号按 questionId 升序兜底。
int _compareSerial(QuestionLibraryEntry a, QuestionLibraryEntry b) {
  final int? aSerial = a.serialNo;
  final int? bSerial = b.serialNo;
  if (aSerial == null && bSerial == null) {
    return a.questionId.compareTo(b.questionId);
  }
  if (aSerial == null) {
    return 1;
  }
  if (bSerial == null) {
    return -1;
  }
  final int bySerial = aSerial.compareTo(bSerial);
  if (bySerial != 0) {
    return bySerial;
  }
  return a.questionId.compareTo(b.questionId);
}

/// 答错次数降序。
int _compareWrongFirst(QuestionLibraryEntry a, QuestionLibraryEntry b) {
  return b.wrongAttemptCount.compareTo(a.wrongAttemptCount);
}
