/// 设置页 A4 预览的默认文档。
///
/// 这份文档**只在内存里**：代码模式可以改它，但改完不落盘，下次进入设置页
/// 仍然显示这一份。它覆盖了统一渲染器需要展示的全部语法：标题、中英文字体、
/// 行内/块级 LaTeX、表格、任务列表、引用、代码块、分隔线。
library;

const String defaultMarkdownDocument = r'''# Markdown 预览

这一段用来看**中英文混排**与行内公式：设 $x^2-5x+6=0$，则 $x_1=2,\ x_2=3$。

> 引用块：所有 Markdown 入口（AI 消息、题目、闪存卡、这里、PDF）共用一套
> 渲染器与同一份主题。

## 中英文字体

English text uses the Latin font; 中文使用中文字体。`inline code` 用等宽字体。

### 任务与列表

- [x] 统一渲染入口
- [ ] 调整 PDF 页边距
  1. 纸张
  2. 页眉页脚
- 分栏预览与导出

### 表格

| 项目 | 纸张 | 深色 |
| --- | --- | --- |
| 背景 | 白色 | 深灰 |
| 正文 | 黑字 | 浅灰 |
| 公式 | 可排版 | 可排版 |

### 公式块

$$
\int_0^1 x^2\,\mathrm{d}x = \frac{1}{3}
$$

### 代码块

```dart
void main() {
  final markdown = MarkdownRenderer(markdown: text);
  print(markdown);
}
```

---

右下角页脚与页码跟随「主题设置 → Markdown」里的设置。
''';
