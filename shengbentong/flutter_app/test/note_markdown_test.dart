/// T-123 笔记渲染管线测试：代码高亮 / KaTeX 公式 / noteimg 本地图与缺图占位
///
/// 注意：凡涉及真实文件 IO（Image.file 解码）的用例必须整体包在
/// tester.runAsync 中——testWidgets 假异步环境里真实 IO 会死锁。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shengbentong/widgets/note_markdown.dart';

/// 合法的 1x1 PNG（保证测试中图片流正常关闭、进程可退出）
final _validPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Widget host(String md, {Map<String, String> map = const {}}) => MaterialApp(
    home: Scaffold(
        body: SingleChildScrollView(
            child: NoteMarkdownView(contentMd: md, imageMap: map))));

void main() {
  testWidgets('代码围栏按语言高亮渲染', (tester) async {
    await tester.pumpWidget(host('```c\nint main() {}\n```\n'));
    await tester.pumpAndSettle();
    expect(find.textContaining('int main'), findsOneWidget);
  });

  testWidgets('行内与块级公式经 KaTeX 渲染', (tester) async {
    final md = '质能方程 \$E=mc^2\$ 很有名。\n\n\$\$\n\\\\frac{1}{2}\n\$\$\n';
    await tester.pumpWidget(host(md));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('非法 LaTeX 红字回退原文，不抛异常不静默吞掉', (tester) async {
    const bad = r'$\frac{未闭合$';
    await tester.pumpWidget(host(bad));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('noteImageWidget 纯逻辑四分支（不触发解码）', () {
    expect(noteImageWidget('noteimg://gone.png', const {}), isA<Row>());
    expect(noteImageWidget('noteimg://ok.png', {'ok.png': 'x.png'}),
        isA<ClipRRect>());
    expect(noteImageWidget('http://x/y.png', const {}), isA<Image>());
    expect(noteImageWidget('weird://x', const {}), isA<Row>());
  });

  testWidgets('noteimg 集成：有图渲染本地文件，缺图显示占位', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('note_md_test');
      final img = File('${dir.path}/ok.png');
      await img.writeAsBytes(_validPng);
      await tester.pumpWidget(host(
          '![](noteimg://ok.png)\n\n![](noteimg://gone.png)',
          map: {'ok.png': img.path}));
      // 给真实解码留时间，再推进帧
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
      expect(find.textContaining('gone.png'), findsOneWidget);
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await dir.delete(recursive: true);
      }
    });
  });
}
