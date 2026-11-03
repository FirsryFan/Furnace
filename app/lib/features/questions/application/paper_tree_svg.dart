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
    _measure(root, 0);
    var y = title.isEmpty ? 24.0 : 64.0;
    final all = <_Node>[];
    void place(_Node n, int depth) {
      n.x = 20 + depth * 30;
      n.y = y;
      y += n.h + 18;
      all.add(n);
      for (final c in n.children) {
        place(c, depth + 1);
      }
    }

    place(root, 0);
    var maxX = 0.0;
    for (final n in all) {
      maxX = math.max(maxX, n.x + n.w);
    }
    final width = (maxX + 24).ceilToDouble();
    final height = (y + 18).ceilToDouble();
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
          '<text x="20" y="32" font-size="17" font-weight="bold" fill="#111" font-family="' +
              _font +
              '">' +
              _esc(_plain(title)) +
              '</text>');
    }
    // 纵向树：从父节点底部引到子节点左侧；缩进本身就是层级。
    void edges(_Node n) {
      for (final c in n.children) {
        final px = n.x + n.w / 2;
        final py = n.y + n.h;
        final cy = c.y + c.h / 2;
        final cx = c.x;
        final dash = c.status == 'wrong' ? ' stroke-dasharray="6 4"' : '';
        out.add('<path d="M' +
            _n(px) +
            ' ' +
            _n(py) +
            ' V' +
            _n(cy) +
            ' H' +
            _n(cx) +
            '" fill="none" stroke="' +
            _stroke +
            '" stroke-width="1.3" opacity="0.72"' +
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

  static String _text(_Node n) {
    final out = <String>[];
    final center = n.status == 'diamond' || n.status == 'answer';
    final tx = center ? n.x + n.w / 2 : n.x + _pad;
    final anchor = center ? ' text-anchor="middle"' : '';
    var ty = n.y + 18;
    for (final line in n.labelLines) {
      out.add('<text x="' +
          _n(tx) +
          '" y="' +
          _n(ty) +
          '" font-size="13" font-weight="600" fill="#111"' +
          anchor +
          ' font-family="' +
          _font +
          '">' +
          _esc(line) +
          '</text>');
      ty += 17;
    }
    ty += 2;
    for (final line in n.noteLines) {
      out.add('<text x="' +
          _n(tx) +
          '" y="' +
          _n(ty) +
          '" font-size="11" fill="#37474f"' +
          anchor +
          ' font-family="' +
          _font +
          '">' +
          _esc(line) +
          '</text>');
      ty += 14;
    }
    return out.join();
  }

  static void _measure(_Node n, int depth) {
    final maxText = math.max(180.0, 500.0 - depth * 30.0);
    n.labelLines = _wrap(_plain(n.label), _labelSize, maxText);
    n.noteLines = n.note == null
        ? <String>[]
        : _wrap(_plain(n.note!), _noteSize, maxText);
    var w = 0.0;
    for (final line in n.labelLines) {
      w = math.max(w, _textWidth(line, _labelSize));
    }
    for (final line in n.noteLines) {
      w = math.max(w, _textWidth(line, _noteSize));
    }
    n.w = math.min(maxText, w) + _pad * 2;
    n.h = n.labelLines.length * 17 +
        (n.noteLines.isEmpty ? 0 : n.noteLines.length * 14 + 6) +
        16;
    if (n.status == 'diamond') {
      n.w = math.max(n.w, 160);
      n.h = math.max(n.h + 8, 58);
    } else if (n.status == 'answer' || n.status == 'check') {
      n.h += 4;
    }
    for (final c in n.children) {
      _measure(c, depth + 1);
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
