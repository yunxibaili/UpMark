/// 知识点阅读页（Markdown渲染）—— 纯UI，零IO。
/// 知识点内容与题目列表由调用方（ChapterScreen）从DB加载后传入，
/// 与 QuizScreen 同架构，可在 flutter test 中纯内存测试。
library;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/quiz_logic.dart';
import 'quiz_screen.dart';

class KnowledgeScreen extends StatelessWidget {
  final String title;
  final String? knowledgeMd;
  final List<Question> questions;
  final Set<int> initialFavorites;
  final void Function(Question q, UserAnswer ua)? onAnswered;
  final Future<bool> Function(int questionId)? onToggleFavorite;

  const KnowledgeScreen(
      {super.key,
      required this.title,
      this.knowledgeMd,
      this.questions = const [],
      this.initialFavorites = const {},
      this.onAnswered,
      this.onToggleFavorite});

  void _startQuiz(BuildContext context) {
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => QuizScreen(
            title: title,
            questions: questions,
            initialFavorites: initialFavorites,
            onAnswered: onAnswered,
            onToggleFavorite: onToggleFavorite)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('知识点 · $title',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      bottomNavigationBar: SafeArea(child:
          Padding(padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: brandBlue,
                  minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.edit),
              label: Text(questions.isEmpty ? '本章无练习题' : '学完本章，开始练习',
                  style: const TextStyle(fontSize: 16)),
              onPressed:
                  questions.isEmpty ? null : () => _startQuiz(context)))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: MarkdownBlock(data: knowledgeMd ?? '暂无知识点内容')),
    );
  }
}
