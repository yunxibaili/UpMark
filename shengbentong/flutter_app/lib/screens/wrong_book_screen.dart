/// 错题本 —— 答错的题自动进入（saveProgress: in_wrong_book=1），
/// 重练答对自动移出；也可手动移除。纯列表+重练入口。
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/db_service.dart';
import 'quiz_screen.dart';

class WrongBookScreen extends StatefulWidget {
  const WrongBookScreen({super.key});

  @override
  State<WrongBookScreen> createState() => _WrongBookScreenState();
}

class _WrongBookScreenState extends State<WrongBookScreen> {
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
    final entries = await db.wrongBookEntries();
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

  void _remove(int qid) async {
    final db = await DbService.open();
    await db.removeFromWrongBook(qid);
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从错题本移除'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _practiceAll() async {
    if (_practicing) return;
    setState(() => _practicing = true);
    try {
      final db = await DbService.open();
      final ids = await db.wrongQuestionIds();
      final questions = await db.questionsByIds(ids);
      if (questions.isEmpty) return;
      final favs = await _favIds(db, ids);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => QuizScreen(
              title: '错题重练',
              questions: questions,
              initialFavorites: favs,
              onAnswered: (q, ua) =>
                  db.saveProgress(questionId: q.id, isCorrect: ua.isCorrect),
              onToggleFavorite: (qid) async {
                await db.setFavorite(qid, true);
                return true;
              }))).then((_) => _reload());
    } finally {
      if (mounted) setState(() => _practicing = false);
    }
  }

  Future<Set<int>> _favIds(DbService db, List<int> ids) async {
    final progress = await db.progressMapOf(ids);
    return {
      for (final e in progress.entries)
        if ((e.value['in_favorites'] as int? ?? 0) == 1) e.key,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('错题本${_entries.isEmpty ? "" : " (${_entries.length})"}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white),
      bottomNavigationBar: _entries.isEmpty
          ? null
          : SafeArea(child: Padding(padding: const EdgeInsets.all(14),
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: brandBlue,
                      minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.fitness_center),
                  label: Text(_practicing ? '加载中…' : '错题重练（答对自动移出）',
                      style: const TextStyle(fontSize: 16)),
                  onPressed: _practicing ? null : _practiceAll))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        size: 64, color: Colors.amber.shade400),
                    const SizedBox(height: 8),
                    Text('太棒了，暂无错题！',
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
                              backgroundColor: badRed.withValues(alpha: .12),
                              child: Text(_typeLabel(e['type']),
                                  style: const TextStyle(fontSize: 11,
                                      color: badRed))),
                          title: Text(stem.isEmpty ? '（完形填空空）' : stem,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${e['subject']} · ${_fmtTime(e['answered_at'])}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                          trailing: IconButton(
                              tooltip: '移出错题本',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => _remove(e['qid'] as int)),
                        ),
                      );
                    },
                  )),
    );
  }

  String _fmtTime(Object? iso) {
    if (iso is! String || iso.length < 16) return '';
    return iso.substring(0, 16).replaceAll('T', ' ');
  }
}
