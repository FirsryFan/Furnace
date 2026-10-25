/// 新卡插入节奏：每多少张复习卡后面插一张新卡。
///
/// 用户反馈（2026-10-25）：闪存卡重复出现频率高、难以推进新卡片。
/// 新卡按固定节奏均匀插进复习序列（而不是全部堆在队尾），让同一轮复习里
/// 既有到期复习卡、也有新卡持续进入。
const int kNewCardEveryReviews = 5;

/// 把新卡均匀插进复习卡序列（纯函数，不改入参，返回新的可增长 List）。
///
/// 语义：
///
/// * [every] 小于 1 时按 1 处理（每张复习卡后都试着插一张新卡）；
/// * 按 [reviews] 原顺序逐个放入；每放满 [every] 张且还有新卡，就在后面插一张；
/// * [reviews] 放完后，剩余新卡按原顺序接在末尾，一张都不丢；
/// * [reviews] 为空返回 [newCards] 的副本；[newCards] 为空返回 [reviews] 的副本；
///   两者都空返回空表。
///
/// 例：reviews = r1..r10、newCards = n1..n3、every = 5
/// → `[r1, r2, r3, r4, r5, n1, r6, r7, r8, r9, r10, n2, n3]`。
///
/// 本函数只负责排顺序，不关心卡片内容与到期时间；泛型是为了测试可以用
/// `int` / `String` 直接验节奏，调用方传真正的复习条目类型即可。
List<T> paceNewCards<T>({
  required List<T> reviews,
  required List<T> newCards,
  int every = kNewCardEveryReviews,
}) {
  final pace = every < 1 ? 1 : every;
  final paced = <T>[];
  var nextNew = 0;
  for (var i = 0; i < reviews.length; i++) {
    paced.add(reviews[i]);
    if ((i + 1) % pace == 0 && nextNew < newCards.length) {
      paced.add(newCards[nextNew]);
      nextNew++;
    }
  }
  while (nextNew < newCards.length) {
    paced.add(newCards[nextNew]);
    nextNew++;
  }
  return paced;
}
