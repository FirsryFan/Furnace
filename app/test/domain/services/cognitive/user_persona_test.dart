import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/user_persona.dart';

/// persona 纯逻辑测试：归一化 / 存储值 / 长度上限 / AI 提示块 / 预览。
///
/// 固定引导行在这里用字面量重复一遍，作用是**钉住契约**：
/// 将来有人改 `_promptLeadLine` 时，这个测试必须显式跟着改，
/// 而不是让 AI 系统提示在无声中变化。
const String kLeadLine = '用户对自己的描述（作为背景来理解用户；不要复述这段话，也不要因为提到就刻意迎合）：';

void main() {
  group('normalizeUserPersona：只做空白归一化', () {
    test('单行去首尾空白', () {
      expect(normalizeUserPersona('  你好  '), '你好');
    });

    test('空串 / 全空白 / 单空格都归一为空串', () {
      expect(normalizeUserPersona(''), '');
      expect(normalizeUserPersona('   '), '');
      expect(normalizeUserPersona(' '), '');
      expect(normalizeUserPersona('\n\n'), '');
      expect(normalizeUserPersona('\r\n\r\n'), '');
      expect(normalizeUserPersona('\t'), '');
    });

    test('CRLF 统一为 LF', () {
      expect(normalizeUserPersona('第一行\r\n第二行'), '第一行\n第二行');
    });

    test('单独的 CR 也统一为 LF', () {
      expect(normalizeUserPersona('第一行\r第二行'), '第一行\n第二行');
    });

    test('CRLF、LF、CR 混用都能统一', () {
      expect(normalizeUserPersona('a\r\nb\nc\rd'), 'a\nb\nc\nd');
    });

    test('逐行去掉行尾空格与制表符', () {
      expect(normalizeUserPersona('第一行  \n第二行\t\n'), '第一行\n第二行');
    });

    test('行尾全角空格与不换行空格也去掉', () {
      expect(normalizeUserPersona('结尾\u3000\u00a0'), '结尾');
    });

    test('多行中文保留中间空行与行首缩进', () {
      expect(
        normalizeUserPersona('第一段\n\n  缩进的第二段'),
        '第一段\n\n  缩进的第二段',
      );
    });

    test('行内空白不改写（只处理行尾与首尾）', () {
      expect(normalizeUserPersona('  我  喜欢   数学  '), '我  喜欢   数学');
    });
  });

  group('userPersonaForStorage：空存 null、超长不截断', () {
    test('空 / 全空白 → null', () {
      expect(userPersonaForStorage(''), isNull);
      expect(userPersonaForStorage('   \r\n  '), isNull);
    });

    test('普通文本 → 归一化后的文本', () {
      expect(
        userPersonaForStorage('  我是高中生。\r\n喜欢数学。  '),
        '我是高中生。\n喜欢数学。',
      );
    });

    test('超过上限也不截断（由调用方按 tooLong 提示用户）', () {
      final long = 'a' * (kUserPersonaMaxChars + 1);
      final stored = userPersonaForStorage(long);
      expect(stored, isNotNull);
      expect(stored!.length, kUserPersonaMaxChars + 1);
    });
  });

  group('userPersonaIsPresent', () {
    test('null、空串、全空白都算没有内容', () {
      expect(userPersonaIsPresent(null), isFalse);
      expect(userPersonaIsPresent(''), isFalse);
      expect(userPersonaIsPresent(' \n\t '), isFalse);
    });

    test('有一个非空白字符就算有内容', () {
      expect(userPersonaIsPresent('我'), isTrue);
      expect(userPersonaIsPresent(' 我 '), isTrue);
    });
  });

  group('userPersonaTooLong：按归一化后的长度判定', () {
    test('正好 8000 不算超长', () {
      expect(kUserPersonaMaxChars, 8000);
      expect(userPersonaTooLong('a' * 8000), isFalse);
    });

    test('8001 算超长', () {
      expect(userPersonaTooLong('a' * 8001), isTrue);
    });

    test('行尾空白不计入长度（归一化后正好 8000 不算超长）', () {
      expect(userPersonaTooLong('a' * 8000 + '      '), isFalse);
    });

    test('CRLF 不额外占长度（4000 + CRLF + 4000 归一化后 8001 算超长）', () {
      expect(userPersonaTooLong('${'a' * 4000}\r\n${'a' * 4000}'), isTrue);
    });
  });

  group('userPersonaPromptBlock：空→空串，非空→固定引导行 + 原文', () {
    test('null / 空串 / 全空白 → 空串（AI 提示字节不变）', () {
      expect(userPersonaPromptBlock(null), '');
      expect(userPersonaPromptBlock(''), '');
      expect(userPersonaPromptBlock('   \r\n '), '');
    });

    test('非空时第一行是固定引导行、第二行起是归一化文本、结尾无换行', () {
      final block = userPersonaPromptBlock('我是高二学生。\n喜欢数学。');
      expect(block, '$kLeadLine\n我是高二学生。\n喜欢数学。');
      expect(block.startsWith('$kLeadLine\n'), isTrue);
      expect(block.endsWith('\n'), isFalse);
    });

    test('先归一化再拼：CRLF 与行尾空白不会进提示', () {
      expect(
        userPersonaPromptBlock('  我是一名学生。  \r\n\r\n  喜欢物理。\t'),
        '$kLeadLine\n我是一名学生。\n\n  喜欢物理。',
      );
    });
  });

  group('userPersonaPreview：折叠空白 + 截断加省略号', () {
    test('null / 空串 / 全空白 → 空串', () {
      expect(userPersonaPreview(null), '');
      expect(userPersonaPreview(''), '');
      expect(userPersonaPreview('  \r\n\t '), '');
    });

    test('折叠所有空白为单个空格', () {
      expect(userPersonaPreview('我  喜欢\n\n数学\t和   物理'), '我 喜欢 数学 和 物理');
    });

    test('短文本不加省略号', () {
      expect(userPersonaPreview('我是高中生。'), '我是高中生。');
      expect(userPersonaPreview('我是高中生。').endsWith('…'), isFalse);
    });

    test('正好等于上限时不加省略号', () {
      final text = 'a' * 120;
      expect(userPersonaPreview(text), text);
    });

    test('超过上限：截到 120 个 code unit（省略号算在内）', () {
      final text = '字' * 200;
      final preview = userPersonaPreview(text);
      expect(preview.length, 120);
      expect(preview.endsWith('…'), isTrue);
      expect(preview, '${'字' * 119}…');
    });

    test('自定义 maxChars 生效（默认 120 没有写死）', () {
      final preview = userPersonaPreview('a' * 10, maxChars: 5);
      expect(preview, 'aaaa…');
      expect(preview.length, 5);
    });

    test('maxChars=1：超长时只剩省略号，恰好 1 个字符时原样', () {
      expect(userPersonaPreview('abc', maxChars: 1), '…');
      expect(userPersonaPreview('a', maxChars: 1), 'a');
    });

    test('maxChars <= 0 触发 assert', () {
      expect(
          () => userPersonaPreview('abc', maxChars: 0), throwsAssertionError);
      expect(
          () => userPersonaPreview('abc', maxChars: -5), throwsAssertionError);
    });
  });
}
