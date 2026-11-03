import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/application/paper_tree_svg.dart';

void main() {
  test('渲染形状、无颜色、按 status 区分', () {
    final spec = <String, Object?>{
      'title': '题1 思维树',
      'root': <String, Object?>{
        'label': '审题',
        'note': '问什么',
        'status': 'step',
        'children': <Object?>[
          <String, Object?>{
            'label': '定原文',
            'note': '引原句',
            'status': 'evidence',
            'children': <Object?>[
              <String, Object?>{
                'label': '判断',
                'note': '依据',
                'status': 'decision',
                'children': <Object?>[
                  <String, Object?>{
                    'label': '结论',
                    'note': '答案',
                    'status': 'answer',
                    'children': <Object?>[]
                  },
                  <String, Object?>{
                    'label': '弯路',
                    'note': '错因',
                    'status': 'wrong',
                    'children': <Object?>[]
                  },
                  <String, Object?>{
                    'label': '修正',
                    'note': '直路',
                    'status': 'fix',
                    'children': <Object?>[]
                  },
                  <String, Object?>{
                    'label': '检查',
                    'note': '回代',
                    'status': 'check',
                    'children': <Object?>[]
                  },
                ],
              },
            ],
          },
        ],
      },
    };
    final svg = PaperTreeSvg.render(spec);
    expect(svg, contains('<svg'));
    expect(svg, contains('polygon')); // 菱形 / 平行四边形 / 六边形
    expect(svg, contains('stroke-dasharray')); // 弯路
    expect(svg, contains('fill="#ffffff"'));
    expect(svg, isNot(contains('#e8f5e9'))); // 不再用绿色填充
    expect(svg, contains('题1 思维树'));
  });

  test('宽树改为纵向可读布局，并把 LaTeX 转成普通文字', () {
    final children = <Object?>[
      for (var i = 0; i < 8; i++)
        <String, Object?>{
          'label': '分支' + i.toString(),
          'note': r'$W=\frac{1}{2}mv^2+fx$',
          'status': 'step',
          'children': <Object?>[],
        }
    ];
    final svg = PaperTreeSvg.render(<String, Object?>{
      'title': '宽树',
      'root': <String, Object?>{
        'label': '根节点',
        'note': '',
        'status': 'step',
        'children': children,
      },
    });
    final size = RegExp(r'width="(\d+)" height="(\d+)"').firstMatch(svg)!;
    final w = int.parse(size.group(1)!);
    final h = int.parse(size.group(2)!);
    expect(w / h, lessThan(2.2), reason: '宽高比应接近正常图片');
    expect(svg, isNot(contains(r'\frac')));
    expect(svg, isNot(contains(r'$')));
  });

  test('XML 转义 & < >', () {
    final svg = PaperTreeSvg.render(<String, Object?>{
      'title': 'A & B',
      'root': <String, Object?>{
        'label': '<判断>',
        'note': 'a & b',
        'status': 'step',
        'children': <Object?>[]
      },
    });
    expect(svg, contains('A &amp; B'));
    expect(svg, contains('&lt;判断&gt;'));
    expect(svg, contains('a &amp; b'));
  });
}
