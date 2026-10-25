/// 用户自我描述（persona）的纯逻辑层：归一化、存储值、长度上限、AI 提示块、预览。
///
/// 功能背景：用户希望「自己描述自己」——这段文字保存在本地、显示在认知模型页，
/// 并在 AI 对话时并入系统提示，让模型知道用户是谁、怎么和他说话。
/// 本文件只做纯函数：不依赖 Flutter、drift、数据库与 UI，方便单测与复用。
///
/// 为什么保留原文、不截断：
///
/// * 归一化只处理「粘贴进来的换行符与行尾空白」这类没有语义的差异，
///   不改写用户用词——persona 是用户的自述，任何改写都可能改变它的意思；
/// * [userPersonaForStorage] 不截断：静默截断会让用户在不知情的情况下丢字。
///   超长只由 [userPersonaTooLong] 如实报告，由调用方在 UI 层提示用户自己删改；
/// * 唯一允许改写的地方是 [userPersonaPreview]——那是给页面看的摘要，
///   折叠空白并加省略号，**不用于存储、也不拼进 AI 提示**。
library;

/// persona 的长度上限（按 [String.length]，即 UTF-16 code unit 计数）。
///
/// 8000 是「够写一段很长的自我介绍」与「不要塞满整条系统提示」之间的折中。
/// 中文常用字基本都是 1 个 code unit；emoji 等星形平面字符算 2 个。
const int kUserPersonaMaxChars = 8000;

/// AI 系统提示里 persona 块的固定引导行。
///
/// 用固定文案而不是让用户写：模型需要知道「这一段是背景，不是指令」，
/// 并且明确不要复述、不要迎合；用户改 persona 内容时这句不会漂移。
const String _promptLeadLine = '用户对自己的描述（作为背景来理解用户；不要复述这段话，也不要因为提到就刻意迎合）：';

/// 把用户粘贴的 persona 原文归一化：统一换行、去掉每行行尾空白、整体去首尾空白。
///
/// 只做「空白差异」层面的归一化，不改写用户用词：
///
/// * CRLF 与单独的 CR 统一成 LF（Windows 复制、富文本编辑器粘贴常见）；
/// * 每行行尾的空格、制表符、全角空格（U+3000）、不换行空格（U+00A0）去掉；
/// * 行首缩进与行内空白原样保留（用户可能故意用缩进或空行分段）；
/// * 结果整体 trim 后只剩空白时返回空串。
String normalizeUserPersona(String raw) {
  if (raw.isEmpty) return '';
  final unified = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = unified.split('\n');
  final stripped = <String>[];
  for (final line in lines) {
    stripped.add(_stripLineTrailingWhitespace(line));
  }
  return stripped.join('\n').trim();
}

/// 写入本地存储用的值：归一化后为空返回 null（数据库里存 NULL 表示「没写」），
/// 否则返回归一化文本——**不截断**（见文件头说明）。
String? userPersonaForStorage(String raw) {
  final normalized = normalizeUserPersona(raw);
  return normalized.isEmpty ? null : normalized;
}

/// 这段 persona 是否有实际内容（null、空串、全空白都算没有）。
bool userPersonaIsPresent(String? raw) {
  if (raw == null) return false;
  return normalizeUserPersona(raw).isNotEmpty;
}

/// 归一化后是否超过 [kUserPersonaMaxChars]。
///
/// 按归一化后的长度算：行尾空白与 CRLF 里多出来的字符不计入，
/// 与用户实际能看到的字数一致。
bool userPersonaTooLong(String raw) =>
    normalizeUserPersona(raw).length > kUserPersonaMaxChars;

/// 拼进 AI 系统提示的 persona 块：没有内容时返回空串（提示字节保持不变）。
///
/// 有内容时第一行是固定引导行，第二行起是归一化后的用户文本，结尾不带换行。
String userPersonaPromptBlock(String? raw) {
  if (raw == null) return '';
  final normalized = normalizeUserPersona(raw);
  if (normalized.isEmpty) return '';
  return '$_promptLeadLine\n$normalized';
}

/// 页面展示用的单行预览：折叠所有空白、超长截断并加省略号。
///
/// * 返回长度最多 [maxChars]（省略号算在内），按 UTF-16 code unit 截断，
///   因此理论上可能切开 emoji 的代理对——预览可接受，存储与 AI 提示都不走这里；
/// * [maxChars] 必须是正数（<= 0 先 assert；release 下按 1 兜底）。
String userPersonaPreview(String? raw, {int maxChars = 120}) {
  assert(maxChars > 0, 'maxChars 必须大于 0');
  final limit = maxChars < 1 ? 1 : maxChars;
  if (raw == null) return '';
  final normalized = normalizeUserPersona(raw);
  if (normalized.isEmpty) return '';
  final collapsed = _collapseWhitespace(normalized);
  if (collapsed.length <= limit) return collapsed;
  if (limit == 1) return '…';
  return '${collapsed.substring(0, limit - 1)}…';
}

/// 行尾空白包括半角空格、制表符、垂直制表符、换页符、不换行空格、全角空格。
bool _isTrailingLineWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0B ||
    codeUnit == 0x0C ||
    codeUnit == 0xA0 ||
    codeUnit == 0x3000;

String _stripLineTrailingWhitespace(String line) {
  var end = line.length;
  while (end > 0 && _isTrailingLineWhitespace(line.codeUnitAt(end - 1))) {
    end--;
  }
  return end == line.length ? line : line.substring(0, end);
}

/// Unicode 空白（大致对齐 ECMAScript 的 \s，另外覆盖全角空格）。
bool _isCollapsibleWhitespace(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0B ||
    rune == 0x0C ||
    rune == 0x0D ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000 ||
    rune == 0xFEFF;

String _collapseWhitespace(String text) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in text.runes) {
    if (_isCollapsibleWhitespace(rune)) {
      if (buffer.isNotEmpty) pendingSpace = true;
      continue;
    }
    if (pendingSpace) {
      buffer.write(' ');
      pendingSpace = false;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
