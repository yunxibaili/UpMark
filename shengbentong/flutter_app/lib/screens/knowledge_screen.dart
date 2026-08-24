/// 知识点阅读页（Markdown渲染）+ "学完本章开始练习"入口
library;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../main.dart';
import 'quiz_screen.dart';

class KnowledgeScreen extends StatelessWidget {
  final int chapterId;
  final String title;
  final String? knowledgeMd;

  const KnowledgeScreen(
      {super.key,
      required this.chapterId,
      required this.title,
      required this.knowledgeMd});

  @override
  Widget build(BuildContext context) {
    final md = (knowledgeMd ?? '').trim().isEmpty
        ? '本章暂无知识点内容，可直接进入练习。'
        : knowledgeMd!;
    return Scaffold(
      appBar: AppBar(
          title: Text('知识点 · $title',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue,
          foregroundColor: Colors.white),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: brandBlue,
                minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.edit),
            label: const Text('学完本章，开始练习',
                style: TextStyle(fontSize: 16)),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) =>
                    QuizScreen(chapterId: chapterId, title: title))),
          ),
        ),
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarkdownBlock(data: md)),
    );
  }
}
