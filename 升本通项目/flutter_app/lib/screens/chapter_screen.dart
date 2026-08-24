/// 章节列表：顺序展示、题量徽标、知识点标记；点击预留T-104刷题入口
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';

class ChapterScreen extends StatefulWidget {
  final Subject subject;
  const ChapterScreen({super.key, required this.subject});

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
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
    final rows = <_Row>[];
    for (final c in chapters) {
      final count = await db.questionCountOf(c.id);
      final hasKn = (c.knowledgeMd ?? '').isNotEmpty;
      rows.add(_Row(
          chapter: c,
          questionCount: count,
          hasKnowledge: hasKn && c.knowledgeMd!.contains('##')));
    }
    return rows;
  }

  void _onTap(_Row row) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '「${row.chapter.title}」学习/刷题功能将在 T-104 开放（本章 ${row.questionCount} 题）'),
        backgroundColor: brandBlue));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.subject.name,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue,
          foregroundColor: Colors.white),
      body: FutureBuilder<List<_Row>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data ?? const [];
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)),
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: brandBlue.withValues(alpha: .12),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: brandBlue,
                                  fontWeight: FontWeight.bold))),
                      title: Text(r.chapter.title),
                      subtitle: Row(children: [
                        Icon(Icons.quiz,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('${r.questionCount} 题',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                        if (r.hasKnowledge) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.menu_book,
                              size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text('知识点',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                        ],
                      ]),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => _onTap(r),
                    ),
                  );
                });
          }),
    );
  }
}

class _Row {
  final Chapter chapter;
  final int questionCount;
  final bool hasKnowledge;
  _Row({required this.chapter, required this.questionCount, required this.hasKnowledge});
}
