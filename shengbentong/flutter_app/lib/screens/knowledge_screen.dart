/// 知识点阅读页（Markdown渲染）+ "学完本章开始练习"入口
library;

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import 'quiz_screen.dart';

class KnowledgeScreen extends StatefulWidget {
  final int chapterId;
  final String title;

  const KnowledgeScreen(
      {super.key, required this.chapterId, required this.title});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  String? _knowledgeMd;
  bool _loading = true;
  List<Question> _questions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DbService.open();
    _knowledgeMd = await db.knowledgeOf(widget.chapterId);
    final rows = await db.rawQuestionsOf(widget.chapterId);
    _questions = rows.map(Question.fromRow).toList();
    if (mounted) setState(() => _loading = false);
  }

  void _startQuiz() {
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => QuizScreen(title: widget.title,
            questions: _questions)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('知识点 · ${widget.title}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      bottomNavigationBar: SafeArea(child:
          Padding(padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: brandBlue,
                  minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.edit),
              label: Text(_questions.isEmpty ? '本章无练习题' : '学完本章，开始练习',
                  style: const TextStyle(fontSize: 16)),
              onPressed: _questions.isEmpty ? null : _startQuiz))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(padding: const EdgeInsets.all(16),
              child: MarkdownBlock(data: _knowledgeMd ?? '暂无知识点内容')),
    );
  }
}
