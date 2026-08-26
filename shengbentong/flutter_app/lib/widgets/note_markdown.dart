/// NoteMarkdownView — 笔记 Markdown 渲染管线（v2.2/T-123）。
///
/// 全部通过 markdown_widget 公开配置接口定制（不改其源码）：
/// - 代码高亮：PreConfig.theme 挂 flutter_highlight 的 vs/vs2015 主题
///   （VSCode 浅色/深色同源配色，192 语言含 C）
/// - 数学公式：自定义 InlineSyntax 注册 latex 标签，经 flutter_math_fork
///   渲染 KaTeX（上游官方 example latex.dart 扩展模式），解析失败红字显示不静默
/// - 笔记图片：ImgConfig.builder 把 `noteimg://<name>` 映射到本地文件离线渲染
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/vs.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';

const _latexTag = 'latex';
const _noteimgScheme = 'noteimg://';

/// 行内/块级公式语法：$...$ 与 $$...$$（非贪婪，防跨段吞并）
class _LatexSyntax extends m.InlineSyntax {
  _LatexSyntax() : super(r'(\$\$[\s\S]+?\$\$)|(\$.+?\$)');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final matchValue = match.input.substring(match.start, match.end);
    var content = '';
    var isInline = true;
    if (matchValue.startsWith(r'$$') &&
        matchValue.endsWith(r'$$') &&
        matchValue.length > 4) {
      content = matchValue.substring(2, matchValue.length - 2);
      isInline = false;
    } else if (matchValue.startsWith(r'$') &&
        matchValue.endsWith(r'$') &&
        matchValue.length > 2) {
      content = matchValue.substring(1, matchValue.length - 1);
    }
    final el = m.Element.text(_latexTag, matchValue)
      ..attributes['content'] = content
      ..attributes['isInline'] = '$isInline';
    parser.addNode(el);
    return true;
  }
}

/// 公式节点：KaTeX 渲染；块级居中带边距；解析失败红字原文（不静默吞错）
class _LatexNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  _LatexNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] != 'false';
    final style = parentStyle ?? config.p.textStyle;
    if (content.isEmpty) return TextSpan(style: style, text: textContent);
    final latex = Math.tex(
      content,
      mathStyle: MathStyle.text,
      textStyle: style,
      textScaleFactor: 1,
      onErrorFallback: (error) =>
          Text(content, style: style.copyWith(color: Colors.red)),
    );
    return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: isInline
            ? latex
            : Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: latex)));
  }
}

/// 笔记图片：noteimg:// → 本地文件；http(s) 网络图兜底；其余/失败占位
Widget noteImageWidget(String url, Map<String, String> imageMap) {
  Widget placeholder(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 4),
          Flexible(child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12))),
        ],
      );

  if (url.startsWith(_noteimgScheme)) {
    final name = url.substring(_noteimgScheme.length);
    final path = imageMap[name];
    if (path == null || path.isEmpty) {
      return placeholder(Icons.image_not_supported, '缺图 $name');
    }
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                placeholder(Icons.broken_image, '损坏 $name')));
  }
  if (url.startsWith('http')) {
    return Image.network(url,
        errorBuilder: (_, _, _) => placeholder(Icons.link_off, url));
  }
  return placeholder(Icons.image_not_supported, url);
}

/// 笔记正文渲染视图。imageMap 由调用方经 resolveNoteImageMap 预解析。
class NoteMarkdownView extends StatelessWidget {
  final String contentMd;
  final Map<String, String> imageMap;

  const NoteMarkdownView({super.key,
      required this.contentMd,
      this.imageMap = const {}});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MarkdownBlock(
      data: contentMd,
      generator: MarkdownGenerator(inlineSyntaxList: [_LatexSyntax()],
          generators: [
            SpanNodeGeneratorWithTag(
                tag: _latexTag,
                generator: (e, config, visitor) =>
                    _LatexNode(e.attributes, e.textContent, config)),
          ]),
      config: MarkdownConfig(configs: [
        PreConfig(
            theme: dark ? vs2015Theme : vsTheme,
            textStyle: const TextStyle(fontSize: 13.5,
                fontFamily: 'monospace', height: 1.45)),
        ImgConfig(builder: (url, attrs) => noteImageWidget(url, imageMap)),
      ]),
    );
  }
}
