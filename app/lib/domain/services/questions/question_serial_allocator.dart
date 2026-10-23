/// 题目编号分配：决定下一道题拿到的 `serial_no`。
///
/// 为什么需要这个纯函数：`docs/QUESTION_BANK_DESIGN.md` §11.1（第 246-248 行）
/// 的「未做（诚实清单）」写明「发出即永久保留」尚未做到——旧实现在事务里取
/// `MAX(serial_no) + 1`，删掉最大号那道题之后，这个号会被下一道题接手，编号就
/// 不再「一个编号固定对应一道题」。持久化计数器（数据库里的高水位）留待后续
/// schema 落地；本函数先把分配规则本身做成可测的纯逻辑：
///
/// - `highestExisting`：现存题目的最大号（旧实现唯一的输入）；
/// - `lastIssued`：历史最大发放号（高水位，来自持久计数器；没有就是 null）。
///
/// 分配规则：两个候选都先过合法性检查（`>= 1`），取合法值里的最大者 M；没有
/// 合法候选时返回 1；否则返回 M + 1。这样即使最大号那题被删了，高水位仍能让
/// 新题不接手已经发出过的号。
///
/// 上限 [kMaxAllocatableQuestionSerial]：题号检索（`question_number_query.dart`
/// 的 `kMaxQuestionNumberQueryDigits` = 9 位）超过 9 位就解析不了，所以 M 达到
/// 上限时返回上限饱和，而不是回绕成负数。
///
/// 纯函数：不读 IO、不依赖时间/随机数，同一输入永远同一输出，永不抛异常；
/// 返回值恒 `>= 1`。上限饱和是唯一可能出现「返回值小于合法候选」的情况（候选
/// 本身就超过上限时，饱和值也小于候选），这是有意的取舍。
library;

/// 分配器允许发出的最大题号（与 `question_number_query.dart` 的
/// `kMaxQuestionNumberQueryDigits` = 9 位检索上限对齐）。
const int kMaxAllocatableQuestionSerial = 999999999;

/// 计算下一道题应分配的题号。
///
/// [highestExisting] 是现存题目的最大号，[lastIssued] 是历史最大已发放号
/// （数据库高水位，可为 null）。两者取合法值（`>= 1`）的最大者 M，返回
/// `M + 1`；都不合法时返回 1。M 达到 [kMaxAllocatableQuestionSerial] 时返回
/// 该上限（饱和，不回绕）。
///
/// 永不抛异常：null、0、负数、极大值都按上面的规则处理。
int allocateQuestionSerial({int? highestExisting, int? lastIssued}) {
  var maxCandidate = 0;
  if (highestExisting != null &&
      highestExisting >= 1 &&
      highestExisting > maxCandidate) {
    maxCandidate = highestExisting;
  }
  if (lastIssued != null && lastIssued >= 1 && lastIssued > maxCandidate) {
    maxCandidate = lastIssued;
  }
  if (maxCandidate == 0) {
    return 1;
  }
  if (maxCandidate >= kMaxAllocatableQuestionSerial) {
    return kMaxAllocatableQuestionSerial;
  }
  return maxCandidate + 1;
}
