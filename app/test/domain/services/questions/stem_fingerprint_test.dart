import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/question_repository.dart';

void main() {
  group('题干指纹：重题判断的底层键', () {
    test('空白、标点、大小写归一后相同', () {
      const a = '已知函数 f(x)=x^2 + 1，求 f(1)。';
      const b = ' 已知函数 f(x)=x^2+1 求 f(1) ';
      expect(stemFingerprint(a), stemFingerprint(b));
    });

    test('换数字、换问法不应假装同一题', () {
      expect(stemFingerprint('已知函数 f(x)=x^2+1，求 f(1)。'),
          isNot(stemFingerprint('已知函数 f(x)=x^3+1，求 f(1)。')));
      expect(
          stemFingerprint('求 a 的取值范围。'), isNot(stemFingerprint('求 b 的取值范围。')));
    });

    test('空串与纯空白归一为同一空指纹，调用方应视为无指纹', () {
      expect(stemFingerprint(''), stemFingerprint('   \n\t '));
    });
  });
}
