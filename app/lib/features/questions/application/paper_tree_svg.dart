// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;

// 把题单思维树 JSON 渲染成无颜色、按形状分类的 SVG。
// 不依赖 Canvas，直接写文件，Markdown 用 <img src="trees/xxx.svg" style="zoom:33%;" /> 引用。

const String _stroke = '#263238';
const String _font = 'Microsoft YaHei, PingFang SC, sans-serif';
const double _labelSize = 13;
const double _noteSize = 11;
const double _pad = 12;

class PaperTreeSvg {
  static String render(Map<String, Object?> spec) {
    final root = _Node.parse(spec['root']);
    final title = (spec['title'] as String?)?.trim() ?? '';
    _measure(root);
    final rootH = _subtreeHeight(root);
    final top = title.isEmpty ? 20.0 : 60.0;
    _layout(root, 18, top + (rootH - root.h) / 2);
    var maxX = 0.0;
    var maxY = 0.0;
    void ext(_Node n) {
      maxX = math.max(maxX, n.x + n.w);
      maxY = math.max(maxY, n.y + n.h);
      for (final c in n.children) {
        ext(c);
      }
    }

    ext(root);
    final titleW = title.isEmpty ? 0.0 : _textWidth(title, 16) + 40;
    final width = math.max(maxX + 20, titleW).ceilToDouble();
    final height = (maxY + 22).ceilToDouble();
    final out = <String>[
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<svg xmlns="http://www.w3.org/2000/svg" width="' +
          width.toInt().toString() +
          '" height="' +
          height.toInt().toString() +
          '" viewBox="0 0 ' +
          width.toInt().toString() +
          ' ' +
          height.toInt().toString() +
          '">',
      '<rect width="100%" height="100%" fill="#ffffff"/>',
    ];
    if (title.isNotEmpty) {
      out.add(
          '<text x="20" y="32" font-size="16" font-weight="bold" fill="#111" font-family="' +
              _font +
              '">' +
              _esc(_plain(title)) +
              '</text>');
    }
    void edges(_Node n) {
      for (final c in n.children) {
        final x1 = n.x + n.w;
        final y1 = n.y + n.h / 2;
        final x2 = c.x;
        final y2 = c.y + c.h / 2;
        final gutter = x1 + 12;
        final dash = c.status == 'wrong' ? ' stroke-dasharray="6 4"' : '';
        out.add('<path d="M' +
            _n(x1) +
            ' ' +
            _n(y1) +
            ' H' +
            _n(gutter) +
            ' V' +
            _n(y2) +
            ' H' +
            _n(x2) +
            '" fill="none" stroke="' +
            _stroke +
            '" stroke-width="1.3" opacity="0.75"' +
            dash +
            '/>');
        edges(c);
      }
    }

    void nodes(_Node n) {
      out.add(_shape(n));
      out.add(_text(n));
      for (final c in n.children) {
        nodes(c);
      }
    }

    edges(root);
    nodes(root);
    out.add('</svg>');
    return out.join('\n');
  }

  static String _shape(_Node n) {
    final x = _n(n.x);
    if (n.status == 'diamond') {
      return '<rect x="' +
          x +
          '" y="' +
          _n(n.y) +
          '" width="' +
          _n(n.w) +
          '" height="' +
          _n(n.h) +
          '" rx="3" fill="#ffffff" stroke="#263238" stroke-width="1.7"/>';
    }
    final y = _n(n.y);
    final w = _n(n.w);
    final h = _n(n.h);
    const base = 'fill="#ffffff" stroke="#263238"';
    switch (n.status) {
      case 'diamond':
        final cx = _n(n.x + n.w / 2);
        final cy = _n(n.y + n.h / 2);
        return '<polygon points="' +
            cx +
            ',' +
            y +
            ' ' +
            _n(n.x + n.w) +
            ',' +
            cy +
            ' ' +
            cx +
            ',' +
            _n(n.y + n.h) +
            ' ' +
            x +
            ',' +
            cy +
            '" ' +
            base +
            ' stroke-width="1.7"/>';
      case 'evidence':
        return '<polygon points="' +
            _n(n.x + 16) +
            ',' +
            y +
            ' ' +
            _n(n.x + n.w) +
            ',' +
            y +
            ' ' +
            _n(n.x + n.w - 16) +
            ',' +
            _n(n.y + n.h) +
            ' ' +
            x +
            ',' +
            _n(n.y + n.h) +
            '" ' +
            base +
            ' stroke-width="1.7"/>';
      case 'answer':
        return '<rect x="' +
            x +
            '" y="' +
            y +
            '" width="' +
            w +
            '" height="' +
            h +
            '" rx="' +
            _n(n.h / 2) +
            '" ' +
            base +
            ' stroke-width="2.4"/>';
      case 'wrong':
        return '<rect x="' +
            x +
            '" y="' +
            y +
            '" width="' +
            w +
            '" height="' +
            h +
            '" rx="3" ' +
            base +
            ' stroke-width="1.5" stroke-dasharray="6 4"/>';
      case 'fix':
        return '<rect x="' +
            x +
            '" y="' +
            y +
            '" width="' +
            w +
            '" height="' +
            h +
            '" rx="3" ' +
            base +
            ' stroke-width="1.6"/>' +
            '<rect x="' +
            _n(n.x + 3.5) +
            '" y="' +
            _n(n.y + 3.5) +
            '" width="' +
            _n(n.w - 7) +
            '" height="' +
            _n(n.h - 7) +
            '" rx="2" fill="none" stroke="#263238" stroke-width="1"/>';
      case 'check':
        return '<polygon points="' +
            _n(n.x + 12) +
            ',' +
            y +
            ' ' +
            _n(n.x + n.w - 12) +
            ',' +
            y +
            ' ' +
            _n(n.x + n.w) +
            ',' +
            _n(n.y + n.h / 2) +
            ' ' +
            _n(n.x + n.w - 12) +
            ',' +
            _n(n.y + n.h) +
            ' ' +
            _n(n.x + 12) +
            ',' +
            _n(n.y + n.h) +
            ' ' +
            x +
            ',' +
            _n(n.y + n.h / 2) +
            '" ' +
            base +
            ' stroke-width="1.7"/>';
      default:
        return '<rect x="' +
            x +
            '" y="' +
            y +
            '" width="' +
            w +
            '" height="' +
            h +
            '" rx="3" ' +
            base +
            ' stroke-width="1.7"/>';
    }
  }

  static String _kindLabel(String status) {
    switch (status) {
      case 'evidence':
        return '依据';
      case 'decision':
      case 'diamond':
        return '判断';
      case 'answer':
        return '结论';
      case 'wrong':
        return '弯路';
      case 'fix':
        return '修正';
      case 'check':
        return '检查';
      default:
        return '步骤';
    }
  }

  static String _text(_Node n) {
    final out = <String>[];
    final tx = n.x + _pad;
    // 右上角节点类型：不放图例，每个框自己说明。
    out.add('<text x="' +
        _n(n.x + n.w - 8) +
        '" y="' +
        _n(n.y + 15) +
        '" font-size="11" fill="#111" text-anchor="end" font-family="' +
        _font +
        '">' +
        _kindLabel(n.status) +
        '</text>');
    var ty = n.y + 31;
    for (final line in n.labelLines) {
      out.add('<text x="' +
          _n(tx) +
          '" y="' +
          _n(ty) +
          '" font-size="14" font-weight="600" fill="#111" font-family="' +
          _font +
          '">' +
          _esc(line) +
          '</text>');
      ty += 18;
    }
    ty += 2;
    for (final line in n.noteLines) {
      out.add('<text x="' +
          _n(tx) +
          '" y="' +
          _n(ty) +
          '" font-size="13" fill="#111" font-family="' +
          _font +
          '">' +
          _esc(line) +
          '</text>');
      ty += 16;
    }
    return out.join();
  }

  static void _measure(_Node n) {
    const maxText = 158.0;
    n.labelLines = _wrap(_plain(n.label), 14, maxText);
    n.noteLines =
        n.note == null ? <String>[] : _wrap(_plain(n.note!), 13, maxText);
    n.w = 190;
    n.h = 34 +
        n.labelLines.length * 18 +
        (n.noteLines.isEmpty ? 0 : n.noteLines.length * 16 + 8) +
        12;
    for (final c in n.children) {
      _measure(c);
    }
  }

  static double _subtreeHeight(_Node n) {
    if (n.children.isEmpty) {
      return n.h;
    }
    var total = 0.0;
    for (final c in n.children) {
      total += _subtreeHeight(c);
    }
    total += 14 * (n.children.length - 1);
    return math.max(n.h, total);
  }

  static void _layout(_Node n, double x, double y) {
    n.x = x;
    n.y = y + (_subtreeHeight(n) - n.h) / 2;
    var cy = y;
    for (final c in n.children) {
      _layout(c, x + n.w + 34, cy);
      cy += _subtreeHeight(c) + 14;
    }
  }

  static List<String> _wrap(String text, double size, double maxWidth) {
    if (text.trim().isEmpty) {
      return <String>[''];
    }
    final lines = <String>[];
    var current = '';
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final next = current + ch;
      if (_textWidth(next, size) > maxWidth && current.isNotEmpty) {
        lines.add(current);
        current = ch;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines.isEmpty ? <String>[''] : lines;
  }

  static String _plain(String raw) {
    var s = raw.replaceAll(r'\$', '');
    s = s.replaceAll(r'$', '');
    final frac = RegExp(r'\\d?frac\{([^{}]*)\}\{([^{}]*)\}');
    s = s.replaceAllMapped(
        frac, (m) => (m.group(1) ?? '') + '/' + (m.group(2) ?? ''));
    s = s.replaceAllMapped(
        RegExp(r'\\sqrt\{([^{}]*)\}'), (m) => '√(' + (m.group(1) ?? '') + ')');
    s = s.replaceAllMapped(
        RegExp(r'\\text\{([^{}]*)\}'), (m) => m.group(1) ?? '');
    const greek = {
      r'\\alpha': 'α',
      r'\\beta': 'β',
      r'\\gamma': 'γ',
      r'\\delta': 'δ',
      r'\\Delta': 'Δ',
      r'\\theta': 'θ',
      r'\\lambda': 'λ',
      r'\\mu': 'μ',
      r'\\pi': 'π',
      r'\\rho': 'ρ',
      r'\\sigma': 'σ',
      r'\\phi': 'φ',
      r'\\omega': 'ω',
      r'\\Omega': 'Ω',
    };
    greek.forEach((k, v) => s = s.replaceAll(k, v));
    const symbols = {
      r'\\propto': '∝',
      r'\\times': '×',
      r'\\cdot': '·',
      r'\\pm': '±',
      r'\\le': '≤',
      r'\\leq': '≤',
      r'\\ge': '≥',
      r'\\geq': '≥',
      r'\\ne': '≠',
      r'\\neq': '≠',
      r'\\rightarrow': '→',
      r'\\to': '→',
      r'\\Rightarrow': '⇒',
      r'\\infty': '∞',
      r'\\circ': '°',
      r'\\sin': 'sin',
      r'\\cos': 'cos',
      r'\\tan': 'tan',
      r'\\log': 'log',
      r'\\ln': 'ln',
      r'\\max': 'max',
      r'\\min': 'min',
    };
    symbols.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAllMapped(RegExp(r'\^\{?([0-9])\}?'), (m) {
      const sup = {
        '0': '⁰',
        '1': '¹',
        '2': '²',
        '3': '³',
        '4': '⁴',
        '5': '⁵',
        '6': '⁶',
        '7': '⁷',
        '8': '⁸',
        '9': '⁹'
      };
      return sup[m.group(1)] ?? m.group(1)!;
    });
    s = s.replaceAllMapped(RegExp(r'\_\{?([0-9])\}?'), (m) {
      const sub = {
        '0': '₀',
        '1': '₁',
        '2': '₂',
        '3': '₃',
        '4': '₄',
        '5': '₅',
        '6': '₆',
        '7': '₇',
        '8': '₈',
        '9': '₉'
      };
      return sub[m.group(1)] ?? m.group(1)!;
    });
    s = s.replaceAll('{', '').replaceAll('}', '').replaceAll(r'\\', '');
    return s.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');
  }

  static double _textWidth(String s, double size) {
    var w = 0.0;
    for (final r in s.runes) {
      final wide = r >= 0x2e80 && r <= 0x9fff ||
          r >= 0xff00 && r <= 0xffef ||
          r >= 0x3000 && r <= 0x303f;
      w += wide ? size : size * 0.56;
    }
    return w;
  }

  static String _n(double v) => v.toStringAsFixed(1);

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class _Node {
  _Node(
      {required this.label,
      this.note,
      required this.status,
      required this.children});

  final String label;
  final String? note;
  final String status;
  final List<_Node> children;
  double x = 0;
  double y = 0;
  double w = 0;
  double h = 0;
  List<String> labelLines = <String>[];
  List<String> noteLines = <String>[];

  static _Node parse(Object? raw) {
    final map =
        (raw is Map) ? raw.cast<String, Object?>() : <String, Object?>{};
    final label = (map['label'] as String?)?.trim();
    final note = (map['note'] as String?)?.trim();
    final status = (map['status'] as String?)?.trim() ?? 'step';
    final children = <_Node>[];
    final rawChildren = map['children'];
    if (rawChildren is List) {
      for (final child in rawChildren) {
        children.add(_Node.parse(child));
      }
    }
    return _Node(
      label: label == null || label.isEmpty ? '（步骤）' : label,
      note: note == null || note.isEmpty ? null : note,
      status: _norm(status),
      children: children,
    );
  }

  static String _norm(String s) {
    if (s == 'decision') {
      return 'diamond';
    }
    const allowed = {
      'step',
      'evidence',
      'diamond',
      'answer',
      'wrong',
      'fix',
      'check'
    };
    return allowed.contains(s) ? s : 'step';
  }
}
