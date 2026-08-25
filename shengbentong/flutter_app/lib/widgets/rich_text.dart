/// 轻量富文本渲染 —— 零新增依赖（T-111 D方案阶段一）。
/// 识别：行内公式 $...$（等宽斜体+主色）、行内代码 `...`（等宽+灰底）、
/// 围栏代码块 ```...```（灰底等宽容器）。其余原样文本，LaTeX不做数学排版
/// （可读优先；若将来需要精美公式再评估 flutter_math_fork，见任务清单阶段二）。
library;

import 'package:flutter/material.dart';

import '../main.dart';

final _inlineRe = RegExp(r'(\$[^$\n]+\$|`[^`\n]+`)');
final _fence = RegExp(r'^\s{0,3}```');

/// 把含公式/代码标记的文本渲染为富文本Widget
Widget richText(String text, {TextStyle? style}) {
  if (text.isEmpty) return const SizedBox.shrink();
  final lines = text.split('\n');
  final widgets = <Widget>[];
  final buf = <String>[];
  var i = 0;

  void flushBuf() {
    if (buf.isEmpty) return;
    widgets.add(Text.rich(TextSpan(
        style: style, children: _inlineSpans(buf.join('\n'), style))));
    buf.clear();
  }

  while (i < lines.length) {
    if (_fence.hasMatch(lines[i])) {
      flushBuf();
      final code = <String>[];
      i++;
      while (i < lines.length && !_fence.hasMatch(lines[i])) {
        code.add(lines[i]);
        i++;
      }
      i++; // 跳过闭合围栏（缺失则已到文本尾）
      widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(6)),
          child: Text(code.join('\n'),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13, height: 1.45))));
    } else {
      buf.add(lines[i]);
      i++;
    }
  }
  flushBuf();
  return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets);
}

List<InlineSpan> _inlineSpans(String text, TextStyle? style) {
  final base = style ?? const TextStyle();
  final spans = <InlineSpan>[];
  var start = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > start) spans.add(TextSpan(text: text.substring(start, m.start)));
    final tok = m.group(0)!;
    if (tok.startsWith(r'$')) {
      spans.add(TextSpan(
          text: tok,
          style: base.copyWith(
              fontFamily: 'monospace',
              fontStyle: FontStyle.italic,
              color: brandBlue)));
    } else {
      spans.add(TextSpan(
          text: tok,
          style: base.copyWith(
              fontFamily: 'monospace',
              background: Paint()..color = const Color(0xFFEDEDED))));
    }
    start = m.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  if (spans.isEmpty) spans.add(TextSpan(text: text));
  return spans;
}
