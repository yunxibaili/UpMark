/// 章节列表：顺序展示、题量徽标、知识点标记；练习/知识点双入口
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import 'knowledge_screen.dart';
import 'quiz_screen.dart';

class ChapterScreen extends StatefulWidget {
  final Subject subject;
  const ChapterScreen({super.key, required this.subject});

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _Row {
  final Chapter chapter;
  final int questionCount;
  final bool hasKnowledge;
  _Row({required this.chapter, required this.questionCount, required this.hasKnowledge});
}

class _ChapterScreenState extends State<ChapterScreen> {
  late Future<List<_Row>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Row>> _load() async {
    final db = await DbService.open();
    final chapters = await db.chaptersOf(widget.subject.id);
    return [
      for (final c in chapters)
        _Row(
            chapter: c,
            questionCount: await db.questionCountOf(c.id),
            hasKnowledge: (c.knowledgeMd ?? '').isNotEmpty),
    ];
  }

  Future<void> _openQuiz(Chapter c) async {
    final db = await DbService.open();
    final rows = await db.rawQuestionsOf(c.id);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => QuizScreen(title: c.title,
            questions: rows.map(Question.fromRow).toList())));
  }

  Future<void> _openKnowledge(Chapter c) async {
    final db = await DbService.open();
    final md = await db.knowledgeOf(c.id);
    final rows = await db.rawQuestionsOf(c.id);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        KnowledgeScreen(title: c.title, knowledgeMd: md,
            questions: rows.map(Question.fromRow).toList())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.subject.name,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      body: FutureBuilder<List<_Row>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return const Center(child: Text('暂无内容',
                  style: TextStyle(color: Colors.grey)));
            }
            return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: brandBlue.withValues(alpha: .12),
                          child: Text('${i + 1}',
                              style: TextStyle(color: brandBlue,
                                  fontWeight: FontWeight.bold))),
                      title: Text(r.chapter.title),
                      subtitle: Row(children: [
                        Icon(Icons.quiz, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('${r.questionCount} 题', style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (r.hasKnowledge)
                          IconButton(tooltip: '知识点',
                              onPressed: () => _openKnowledge(r.chapter),
                              icon: Icon(Icons.menu_book, color: brandBlue)),
                        FilledButton.tonal(
                            onPressed: () => _openQuiz(r.chapter),
                            style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact),
                            child: const Text('练习')),
                      ]),
                    ),
                  );
                });
          }),
    );
  }
}
