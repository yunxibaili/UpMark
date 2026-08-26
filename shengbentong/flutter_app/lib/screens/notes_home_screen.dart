/// NotesHomeScreen — 全局笔记列表（v2.2/T-124）。
///
/// 多篇自由笔记：新建/编辑/长按删除，按更新时间倒序。
/// 直调 DbService 与 note_image_store（与 SubjectScreen 同风格）；
/// 备份到PC / 从PC恢复 的动作由 T-125 的 notes_backup_service 接入本页。
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/note_image_store.dart';
import 'note_editor_screen.dart';

class NotesHomeScreen extends StatefulWidget {
  /// 测试注入钩子；生产路径传 null 由内部 open()
  final DbService? db;
  final String? databasesDir;

  const NotesHomeScreen({super.key, this.db, this.databasesDir});

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  List<Note> _notes = [];
  bool _loading = true;

  Future<(DbService, String)> _env() async {
    final db = widget.db ?? await DbService.open();
    final dir = widget.databasesDir ?? await getDefaultDatabasesDirectory();
    return (db, dir);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (db, _) = await _env();
    final notes = await db.allNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _openEditor({Note? initial}) async {
    final (db, dir) = await _env();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => NoteEditorScreen(db: db,
            databasesDir: dir, initial: initial)));
    _load();
  }

  Future<void> _deleteNote(Note n) async {
    final (db, dir) = await _env();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
            title: const Text('删除这条笔记？'),
            content: const Text('删除后将在下次同步时从PC备份中一并移除。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: badRed),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除')),
            ]));
    if (confirmed != true || !mounted) return;
    try {
      await db.softDeleteNote(n.id);
      // 清理本地不再被任何存活笔记引用的图片
      final refs = <String>{};
      for (final live in await db.allNotes()) {
        refs.addAll(extractNoteImgRefs(live.contentMd));
      }
      await cleanupOrphanNoteImages(dir, refs);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('删除失败：$e'), backgroundColor: badRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('我的笔记',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          heroTag: 'fab_add_note',
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('新建')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 10),
                    Text('还没有笔记，点右下角新建一篇',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _notes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final n = _notes[i];
                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                              key: Key('note_item_${n.id}'),
                              onTap: () => _openEditor(initial: n),
                              onLongPress: () => _deleteNote(n),
                              leading: Icon(
                                  n.questionId == null
                                      ? Icons.sticky_note_2_outlined
                                      : Icons.quiz_outlined,
                                  color: brandBlue),
                              title: Text(
                                  n.title.isEmpty ? '（无标题）' : n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_firstLine(n.contentMd),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.grey.shade600)),
                                    const SizedBox(height: 2),
                                    Row(children: [
                                      if (n.questionId != null)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                right: 8),
                                            child: Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                    color: brandBlue
                                                        .withValues(
                                                            alpha: .12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                                child: const Text('题目笔记',
                                                    style: TextStyle(
                                                        fontSize: 10.5,
                                                        color: brandBlue)))),
                                      Text(_fmtTime(n.updatedAt),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500)),
                                    ]),
                                  ])));
                      })),
    );
  }

  static String _firstLine(String md) {
    final line = md
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line
        .replaceAll(RegExp(r'^[#>*\-\s]+'), '')
        .replaceAll('**', '')
        .replaceAll('`', '');
  }

  static String _fmtTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
