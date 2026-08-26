/// T-126a 块切分器测试：无损往返是生命线不变量
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/services/note_block_parser.dart';

String join(List<MdBlock> blocks) => blocks.map((b) => b.source).join();

void main() {
  group('无损往返（生命线不变量）', () {
    test('普通多块文档', () {
      const md = '# 标题\n\n段落一\n段落二续行\n\n```c\nint a;\n```\n\n- 列表1\n- 列表2\n';
      expect(join(splitBlocks(md)), md);
    });

    test('文末无换行符', () {
      const md = '# T\n\npara';
      expect(join(splitBlocks(md)), md);
    });

    test('纯空行文档 / 空串 / 仅空白行', () {
      expect(join(splitBlocks('')), '');
      expect(join(splitBlocks('\n\n\n')), '\n\n\n');
      expect(join(splitBlocks('  \n\t\n')), '  \n\t\n');
    });

    test('未闭合围栏兜底到文尾', () {
      const md = '前文\n\n```c\nint a;\nint b;';
      expect(join(splitBlocks(md)), md);
    });

    test('未闭合 \$\$ 块兜底到文尾', () {
      const md = '\$\$\nx^2';
      expect(join(splitBlocks(md)), md);
    });

    test('围栏内 # 与 \$\$ 不误切', () {
      const md = '```md\n# 不是标题\n\$\$\n不是公式\n\$\$\n```\n后文';
      final blocks = splitBlocks(md);
      expect(join(blocks), md);
      expect(blocks.where((b) => b.type == MdBlockType.heading), isEmpty);
    });

    test('CRLF 归一化', () {
      expect(normalizeLineBreaks('a\r\nb\rc'), 'a\nb\nc');
    });
  });

  group('块类型识别', () {
    test('标题/段落/围栏/数学块/列表/引用/分割线', () {
      const md = '# H1\n\npara\n\n```c\nx\n```\n\n\$\$\ny\n\$\$\n\n- a\n- b\n\n> 引用\n\n---\n';
      final types = splitBlocks(md).map((b) => b.type).toList();
      expect(types, [
        MdBlockType.heading,
        MdBlockType.paragraph,
        MdBlockType.fencedCode,
        MdBlockType.mathBlock,
        MdBlockType.list,
        MdBlockType.quote,
        MdBlockType.hr,
      ]);
    });

    test('段落被列表行打断 → 列表另起块', () {
      final blocks = splitBlocks('文字行\n- 列表项\n');
      expect(blocks.map((b) => b.type),
          [MdBlockType.paragraph, MdBlockType.list]);
    });

    test('#tag 无空格不是标题', () {
      expect(splitBlocks('#tag 文字').single.type, MdBlockType.paragraph);
    });

    test('多级标题与列表任务项', () {
      final blocks = splitBlocks('### 三级\n\n- [ ] 任务\n1. 有序\n');
      expect(blocks[0].type, MdBlockType.heading);
      expect(blocks[1].type, MdBlockType.list);
      expect(blocks[1].source, contains('- [ ] 任务'));
      expect(blocks[1].source, contains('1. 有序'));
    });

    test('块尾空行归属前一块（拼接无损的机制）', () {
      final blocks = splitBlocks('A\n\n\nB\n');
      expect(blocks[0].source, 'A\n\n\n');
      expect(blocks[1].source, 'B\n');
    });
  });
}
