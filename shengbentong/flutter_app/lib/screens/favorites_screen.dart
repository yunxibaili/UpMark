/// 收藏夹 —— 刷题页书签图标收藏；支持移除与重练。
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/db_service.dart';
import 'quiz_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, Object?>> _entries = [];
  bool _loading = true;
  bool _practicing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final db = await DbService.open();
    final entries = await db.favoriteEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _typeLabel(Object? t) => switch (t) {
        'single_choice' => '单选',
        'multiple_choice' => '多选',
        'judgment' => '判断',
        'fill_blank' => '填空',
        _ => '题',
      };

  Future<void> _unfavorite(int qid) async {
    final db = await DbService.open();
    await db.setFavorite(qid, false);
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _practiceAll() async {
    if (_practicing) return;
    setState(() => _practicing = true);
    try {
      final db = await DbService.open();
      final ids = await db.favoriteQuestionIds();
      final questions = await db.questionsByIds(ids);
      if (questions.isEmpty || !mounted) return;
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => QuizScreen(
              title: '收藏练习',
              questions: questions,
              initialFavorites: Set<int>.of(ids),
              onAnswered: (q, ua) =>
                  db.saveProgress(questionId: q.id, isCorrect: ua.isCorrect),
              onToggleFavorite: (qid) async {
                await db.setFavorite(qid, false);
                return false;
              }))).then((_) => _reload());
    } finally {
      if (mounted) setState(() => _practicing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('收藏夹${_entries.isEmpty ? "" : " (${_entries.length})"}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      bottomNavigationBar: _entries.isEmpty
          ? null
          : SafeArea(child: Padding(padding: const EdgeInsets.all(14),
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: brandBlue,
                      minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_practicing ? '加载中…' : '练习全部收藏',
                      style: const TextStyle(fontSize: 16)),
                  onPressed: _practicing ? null : _practiceAll))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_border,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text('刷题时点击右上角书签即可收藏',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ]))
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final stem = (e['stem'] as String? ?? '')
                          .replaceAll('\n', ' ');
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        child: ListTile(
                          leading: CircleAvatar(
                              backgroundColor: brandBlue.withValues(alpha: .12),
                              child: Text(_typeLabel(e['type']),
                                  style: const TextStyle(fontSize: 11,
                                      color: brandBlue))),
                          title: Text(stem.isEmpty ? '（完形填空空）' : stem,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(e['subject'] as String? ?? '',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                          trailing: IconButton(
                              tooltip: '取消收藏',
                              icon:
                                  const Icon(Icons.bookmark, color: brandBlue),
                              onPressed: () => _unfavorite(e['qid'] as int)),
                        ),
                      );
                    },
                  )),
    );
  }
}
