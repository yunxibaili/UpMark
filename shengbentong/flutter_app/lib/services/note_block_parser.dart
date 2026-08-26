/// NoteBlockParser — Live Preview 块切分器（v1.2/T-126a）。
///
/// 把 Markdown 正文按块切分：光标所在块显示源码可编辑，其余块实时渲染
/// （Obsidian Live Preview 的块级简化版，Typora 同款粒度）。
///
/// 铁律：**无损往返** —— `splitBlocks(md)` 各块 source 直接拼接必须等于
/// 原文（空行归属前一块尾部），这是编辑器写回不丢内容的生命线。
/// 输入约定为 LF 换行（编辑器入口先做 CRLF 归一化）。
library;

enum MdBlockType { paragraph, heading, fencedCode, mathBlock, list, quote, hr, blank }

class MdBlock {
  final MdBlockType type;
  final String source;

  const MdBlock(this.type, this.source);

  @override
  String toString() => 'MdBlock($type, ${source.length}ch)';
}

final _fenceOpenRe = RegExp(r'^ {0,3}(```|~~~)');
final _mathOpenRe = RegExp(r'^\s*\$\$\s*$');
final _headingRe = RegExp(r'^ {0,3}#{1,6}(\s|$)');
final _hrRe = RegExp(r'^ {0,3}([-*_])\s*(\1\s*){2,}$');
final _quoteRe = RegExp(r'^ {0,3}>');
final _listRe = RegExp(r'^ {0,3}([-*+]|\d{1,9}[.)])(\s|$)');

bool _isBlank(String line) => line.trim().isEmpty;

/// 把 Markdown 文本切分为块列表。空串返回空列表。
List<MdBlock> splitBlocks(String md) {
  if (md.isEmpty) return [];
  final blocks = <MdBlock>[];
  final lines = md.split('\n');
  // split('\n') 在文末换行时会产生幻影空行，剔除
  if (md.endsWith('\n') && lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  var i = 0;

  MdBlockType classify(String line) {
    if (_fenceOpenRe.hasMatch(line)) return MdBlockType.fencedCode;
    if (_mathOpenRe.hasMatch(line)) return MdBlockType.mathBlock;
    if (_headingRe.hasMatch(line)) return MdBlockType.heading;
    if (_hrRe.hasMatch(line)) return MdBlockType.hr;
    if (_quoteRe.hasMatch(line)) return MdBlockType.quote;
    if (_listRe.hasMatch(line)) return MdBlockType.list;
    return MdBlockType.paragraph;
  }

  String consumeTrailingBlanks() {
    // 块尾空行归属本块（保持拼接无损）；返回空串表示无
    var blanks = '';
    while (i < lines.length && _isBlank(lines[i])) {
      blanks += '${lines[i]}\n';
      i++;
    }
    return blanks;
  }

  void push(MdBlockType type, List<String> body) {
    var source = body.join('\n');
    if (source.isNotEmpty || body.isNotEmpty) source += '\n';
    source += consumeTrailingBlanks();
    blocks.add(MdBlock(type, source));
  }

  while (i < lines.length) {
    final line = lines[i];

    // 文首空行：独立 blank 块（拼接无损）
    if (_isBlank(line)) {
      final blanks = <String>[];
      while (i < lines.length && _isBlank(lines[i])) {
        blanks.add(lines[i]);
        i++;
      }
      blocks.add(MdBlock(MdBlockType.blank, '${blanks.join('\n')}\n'));
      continue;
    }

    final type = classify(line);

    switch (type) {
      case MdBlockType.fencedCode:
        // 围栏：从开行到同标记闭行；未闭合兜底到文尾
        final marker = _fenceOpenRe.firstMatch(line)!.group(1)!;
        final body = <String>[line];
        i++;
        while (i < lines.length) {
          body.add(lines[i]);
          final closed = lines[i].trim().startsWith(marker) &&
              lines[i].trim().length >= 3;
          i++;
          if (closed && body.length > 1) break;
        }
        push(type, body);

      case MdBlockType.mathBlock:
        // $$ 独立块：开 $$ 到闭 $$；未闭合兜底到文尾
        final body = <String>[line];
        i++;
        while (i < lines.length) {
          body.add(lines[i]);
          final closed = _mathOpenRe.hasMatch(lines[i]);
          i++;
          if (closed && body.length > 1) break;
        }
        push(type, body);

      case MdBlockType.heading:
      case MdBlockType.hr:
        i++; // 先消费标题/分割线行本身
        push(type, [line]); // push 内再吃块尾空行

      case MdBlockType.quote:
        final body = <String>[];
        while (i < lines.length && _quoteRe.hasMatch(lines[i])) {
          body.add(lines[i]);
          i++;
        }
        push(type, body);

      case MdBlockType.list:
        final body = <String>[];
        while (i < lines.length &&
            _listRe.hasMatch(lines[i]) &&
            !_isBlank(lines[i])) {
          body.add(lines[i]);
          i++;
        }
        push(type, body);

      case MdBlockType.paragraph:
        final body = <String>[];
        while (i < lines.length) {
          final l = lines[i];
          if (_isBlank(l)) break;
          final t = classify(l);
          // 段落被结构行打断 → 结构行另起块
          if (t != MdBlockType.paragraph) break;
          body.add(l);
          i++;
        }
        push(type, body);

      case MdBlockType.blank:
        break; // 不可达：blank 已在循环头处理
    }
  }

  // 无损修正：原文末尾无换行时，最后一个块不得补 \n
  if (blocks.isNotEmpty && md.isNotEmpty && !md.endsWith('\n')) {
    final last = blocks.removeLast();
    final fixed = last.source.endsWith('\n')
        ? last.source.substring(0, last.source.length - 1)
        : last.source;
    blocks.add(MdBlock(last.type, fixed));
  }
  return blocks;
}

/// 编辑器入口的换行归一化（CRLF → LF），保存时即以 LF 落库
String normalizeLineBreaks(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
