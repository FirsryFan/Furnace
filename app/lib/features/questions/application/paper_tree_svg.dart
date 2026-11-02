// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;

// 把题单思维树 JSON 渲染成无颜色、按形状分类的 SVG。
// 不依赖 Canvas，直接写文件，Markdown 用 <img src="trees/xxx.svg" style="zoom:33%;" /> 引用。

const String _stroke = '#263238';
const String _font = 'Microsoft YaHei, PingFang SC, sans-serif';
const double _labelSize = 13;
const double _noteSize = 11;
const double _pad = 12;
const double _vgap = 34;
const double _hgap = 22;

class PaperTreeSvg {
  static String render(Map<String, Object?> spec) {
    final root = _Node.parse(spec['root']);
    final title = (spec['title'] as String?)?.trim() ?? '';
    _measure(root);
    final levels = <double>[];
    _levels(root, 0, levels);
    final levelY = <double>[72];
    for (var d = 1; d < levels.length; d++) {
      levelY.add(levelY[d - 1] + levels[d - 1] + _vgap);
    }
    _layout(root, 20, 0, levelY);
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
    final width = math.max(maxX + 22, titleW).ceilToDouble();
    final height = (maxY + 26).ceilToDouble();
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
          '<text x="20" y="34" font-size="16" font-weight="bold" fill="#111" font-family="' +
              _font +
              '">' +
              _esc(title) +
              '</text>');
    }
    void edges(_Node n) {
      for (final c in n.children) {
        final dash = c.status == 'wrong' ? ' stroke-dasharray="6 4"' : '';
        final x1 = n.x + n.w / 2;
        final y1 = n.y + n.h;
        final x2 = c.x + c.w / 2;
        final y2 = c.y;
        final midY = (y1 + y2) / 2;
        out.add('<path d="M' +
            _n(x1) +
            ' ' +
            _n(y1) +
            ' C' +
            _n(x1) +
            ' ' +
            _n(midY) +
            ' ' +
            _n(x2) +
            ' ' +
            _n(midY) +
            ' ' +
            _n(x2) +
            ' ' +
            _n(y2) +
            '" fill="none" stroke="' +
            _stroke +
            '" stroke-width="1.4" opacity="0.75"' +
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
    if (n.status == 'diamond') {
      final cx = _n(n.x + n.w / 2);
      final labelY = _n(n.y + (n.note == null ? 36 : 30));
      out.add('<text x="' +
          cx +
          '" y="' +
          labelY +
          '" font-size="13" font-weight="600" fill="#111" text-anchor="middle" font-family="' +
          _font +
          '">' +
          _esc(n.label) +
          '</text>');
      if (n.note != null) {
        out.add('<text x="' +
            cx +
            '" y="' +
            _n(n.y + 50) +
            '" font-size="11" fill="#37474f" text-anchor="middle" font-family="' +
            _font +
            '">' +
            _esc(n.note!) +
            '</text>');
      }
      return out.join();
    }
    final tx = _n(n.x + _pad);
    out.add('<text x="' +
        tx +
        '" y="' +
        _n(n.y + 20) +
        '" font-size="13" font-weight="600" fill="#111" font-family="' +
        _font +
        '">' +
        _esc(n.label) +
        '</text>');
    if (n.note != null) {
      out.add('<text x="' +
          tx +
          '" y="' +
          _n(n.y + 37) +
          '" font-size="11" fill="#37474f" font-family="' +
          _font +
          '">' +
          _esc(n.note!) +
          '</text>');
    }
    return out.join();
  }

  static void _measure(_Node n) {
    n.w = math.max(_textWidth(n.label, _labelSize),
            n.note == null ? 0 : _textWidth(n.note!, _noteSize)) +
        _pad * 2;
    n.h = n.note == null ? 32 : 46;
    if (n.status == 'diamond') {
      n.w = math.max(n.w * 1.18, _textWidth(n.label, _labelSize) + 90);
      n.h = n.note == null ? 58 : 74;
    } else if (n.status == 'check') {
      n.w += 14;
      n.h += 4;
    }
    for (final c in n.children) {
      _measure(c);
    }
  }

  static double _subtreeWidth(_Node n) {
    if (n.children.isEmpty) {
      return n.w;
    }
    var total = 0.0;
    for (final c in n.children) {
      total += _subtreeWidth(c);
    }
    total += _hgap * (n.children.length - 1);
    return math.max(n.w, total);
  }

  static void _levels(_Node n, int depth, List<double> levels) {
    if (levels.length <= depth) {
      levels.add(0);
    }
    levels[depth] = math.max(levels[depth], n.h);
    for (final c in n.children) {
      _levels(c, depth + 1, levels);
    }
  }

  static void _layout(_Node n, double left, int depth, List<double> levelY) {
    final sw = _subtreeWidth(n);
    n.x = left + sw / 2 - n.w / 2;
    n.y = levelY[depth];
    if (n.children.isEmpty) {
      return;
    }
    var total = 0.0;
    for (final c in n.children) {
      total += _subtreeWidth(c);
    }
    total += _hgap * (n.children.length - 1);
    var x = left + (sw - total) / 2;
    for (final c in n.children) {
      _layout(c, x, depth + 1, levelY);
      x += _subtreeWidth(c) + _hgap;
    }
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
