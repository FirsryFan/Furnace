import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/features/anki/application/deck_progress.dart';

const CardGroupPlan _plan = CardGroupPlan(
  id: 'group-1',
  tagId: 'tag-1',
  tagPath: '数学',
  newCardsPerDay: 10,
  reviewCardsPerDay: 20,
);

ReviewGroupLoad _load({
  int alreadyDoneToday = 0,
  int newDoneToday = 0,
  int reviewDoneToday = 0,
  int newRemaining = 0,
  int? remainingReviews = 0,
  List<String> memberPaths = const <String>['数学'],
}) {
  return ReviewGroupLoad(
    plan: _plan,
    memberPaths: memberPaths,
    alreadyDoneToday: alreadyDoneToday,
    newDoneToday: newDoneToday,
    reviewDoneToday: reviewDoneToday,
    newRemaining: newRemaining,
    remainingReviews: remainingReviews,
  );
}

void main() {
  group('有上限的正常卡组', () {
    test('新卡与复习都未完成时给出目标与比例', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 4,
          newRemaining: 6,
          reviewDoneToday: 6,
          remainingReviews: 14,
        ),
      );
      expect(progress.newDone, 4);
      expect(progress.newTarget, 10);
      expect(progress.reviewDone, 6);
      expect(progress.reviewTarget, 20);
      expect(progress.newComplete, isFalse);
      expect(progress.reviewComplete, isFalse);
      expect(progress.isComplete, isFalse);
      expect(progress.fraction, closeTo(10 / 30, 1e-9));
    });

    test('新卡完成但复习未完成时整体仍未完成', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 10,
          newRemaining: 0,
          reviewDoneToday: 2,
          remainingReviews: 5,
        ),
      );
      expect(progress.newTarget, 10);
      expect(progress.newComplete, isTrue);
      expect(progress.reviewTarget, 7);
      expect(progress.reviewComplete, isFalse);
      expect(progress.isComplete, isFalse);
      expect(progress.fraction, closeTo(12 / 17, 1e-9));
    });

    test('复习完成但新卡未完成时整体仍未完成', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 2,
          newRemaining: 5,
          reviewDoneToday: 10,
          remainingReviews: 0,
        ),
      );
      expect(progress.newComplete, isFalse);
      expect(progress.reviewComplete, isTrue);
      expect(progress.isComplete, isFalse);
    });

    test('新卡与复习目标都达成时整体完成且比例为 1', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 10,
          newRemaining: 0,
          reviewDoneToday: 20,
          remainingReviews: 0,
        ),
      );
      expect(progress.newTarget, 10);
      expect(progress.reviewTarget, 20);
      expect(progress.newComplete, isTrue);
      expect(progress.reviewComplete, isTrue);
      expect(progress.isComplete, isTrue);
      expect(progress.fraction, 1.0);
    });

    test('新卡目标为 0 但有上限复习时按复习算比例', () {
      final progress = deckProgressFor(
        _load(
          newRemaining: 0,
          reviewDoneToday: 4,
          remainingReviews: 6,
        ),
      );
      expect(progress.newTarget, 0);
      expect(progress.newComplete, isTrue);
      expect(progress.reviewTarget, 10);
      expect(progress.reviewComplete, isFalse);
      expect(progress.fraction, 0.4);
    });

    test('什么都没做时比例为 0', () {
      final progress = deckProgressFor(
        _load(newRemaining: 10, remainingReviews: 5),
      );
      expect(progress.newDone, 0);
      expect(progress.reviewDone, 0);
      expect(progress.fraction, 0.0);
    });
  });

  group('复习不限的卡组', () {
    test('复习目标为 null 且永不算完成', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 10,
          newRemaining: 0,
          reviewDoneToday: 100,
          remainingReviews: null,
        ),
      );
      expect(progress.reviewTarget, isNull);
      expect(progress.reviewComplete, isFalse);
      expect(progress.newComplete, isTrue);
      expect(progress.isComplete, isFalse);
      expect(progress.fraction, 1.0);
    });

    test('复习不限且新卡目标为 0 时分母为 0，比例为 null', () {
      final progress = deckProgressFor(
        _load(newRemaining: 0, remainingReviews: null),
      );
      expect(progress.newTarget, 0);
      expect(progress.reviewTarget, isNull);
      expect(progress.newComplete, isTrue);
      expect(progress.reviewComplete, isFalse);
      expect(progress.isComplete, isFalse);
      expect(progress.fraction, isNull);
    });

    test('复习不限时进度分母只算新卡目标', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 3,
          newRemaining: 7,
          reviewDoneToday: 999,
          remainingReviews: null,
        ),
      );
      expect(progress.reviewTarget, isNull);
      expect(progress.fraction, 1.0);
    });
  });

  group('边界与不变量外输入', () {
    test('新卡与复习都归零（分母 0）时比例为 null 且整体完成', () {
      final progress = deckProgressFor(
        _load(newRemaining: 0, remainingReviews: 0),
      );
      expect(progress.fraction, isNull);
      expect(progress.isComplete, isTrue);
    });

    test('负数剩余额度时比例仍夹在 0..1', () {
      final progress = deckProgressFor(
        _load(
          newDoneToday: 6,
          newRemaining: -2,
          reviewDoneToday: 4,
          remainingReviews: -1,
        ),
      );
      expect(progress.newTarget, 4);
      expect(progress.reviewTarget, 3);
      expect(progress.fraction, 1.0);
      expect(progress.isComplete, isFalse);
    });

    test('alreadyDoneToday 与 memberPaths 不参与进度换算', () {
      final left = deckProgressFor(
        _load(
          newDoneToday: 4,
          newRemaining: 6,
          reviewDoneToday: 6,
          remainingReviews: 14,
          memberPaths: const <String>['数学'],
        ),
      );
      final right = deckProgressFor(
        _load(
          newDoneToday: 4,
          newRemaining: 6,
          reviewDoneToday: 6,
          remainingReviews: 14,
          alreadyDoneToday: 20,
          memberPaths: const <String>['数学', '数学/函数'],
        ),
      );
      expect(left.newDone, right.newDone);
      expect(left.newTarget, right.newTarget);
      expect(left.reviewDone, right.reviewDone);
      expect(left.reviewTarget, right.reviewTarget);
      expect(left.isComplete, right.isComplete);
      expect(left.fraction, right.fraction);
    });

    test('纯函数：同一输入重复调用结果一致', () {
      final input = _load(
        newDoneToday: 4,
        newRemaining: 6,
        reviewDoneToday: 6,
        remainingReviews: 14,
      );
      final first = deckProgressFor(input);
      final second = deckProgressFor(input);
      expect(first.fraction, second.fraction);
      expect(first.newTarget, second.newTarget);
      expect(first.reviewTarget, second.reviewTarget);
      expect(first.isComplete, second.isComplete);
    });

    test('DeckProgress 可以用 const 构造', () {
      const progress = DeckProgress(
        newDone: 1,
        newTarget: 2,
        reviewDone: 3,
        reviewTarget: null,
        newComplete: false,
        reviewComplete: false,
        isComplete: false,
        fraction: null,
      );
      expect(progress.newDone, 1);
      expect(progress.reviewTarget, isNull);
      expect(progress.fraction, isNull);
    });
  });
}
