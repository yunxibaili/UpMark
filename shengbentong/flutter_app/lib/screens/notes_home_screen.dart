/// NotesHomeScreen — 全局笔记列表（v2.2/T-124/T-125）。
///
/// 多篇自由笔记：新建/编辑/长按删除，按更新时间倒序。
/// AppBar 菜单提供「备份到PC」与「从PC恢复」（notes_backup_service）。
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/note_image_store.dart';
import '../services/notes_backup_service.dart';
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
        actions: [
          PopupMenuButton<String>(
              tooltip: '备份',
              icon: const Icon(Icons.cloud_sync),
              onSelected: (v) {
                if (v == 'push') _backupToPc();
                if (v == 'pull') _restoreFromPc();
              },
              itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'push',
                        child: ListTile(leading: Icon(Icons.cloud_upload),
                            title: Text('备份到PC'))),
                    PopupMenuItem(
                        value: 'pull',
                        child: ListTile(leading: Icon(Icons.cloud_download),
                            title: Text('从PC恢复'))),
                  ]),
        ],
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      itemCount: _notes.length,
                      separatorBuilder: (_, _) => Divider(
                          height: 1,
                          thickness: 0.6,
                          indent: 52,
                          color: Colors.grey.shade300),
                      itemBuilder: (_, i) {
                        final n = _notes[i];
                        return InkWell(
                            key: Key('note_item_${n.id}'),
                            onTap: () => _openEditor(initial: n),
                            onLongPress: () => _deleteNote(n),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                          padding: const EdgeInsets.only(
                                              top: 2, right: 12),
                                          child: Icon(
                                              n.questionId == null
                                                  ? Icons.sticky_note_2_outlined
                                                  : Icons.quiz_outlined,
                                              size: 20,
                                              color: brandBlue
                                                  .withValues(alpha: .75))),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                n.title.isEmpty
                                                    ? '（无标题）'
                                                    : n.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 15.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            Text(_firstLine(n.contentMd),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors
                                                        .grey.shade600)),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              if (n.questionId != null)
                                                Padding(
                                                    padding: const EdgeInsets
                                                        .only(right: 8),
                                                    child: Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 6,
                                                            vertical: 1),
                                                        decoration: BoxDecoration(
                                                            color: brandBlue
                                                                .withValues(
                                                                    alpha: .1),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6)),
                                                        child: const Text(
                                                            '题目笔记',
                                                            style: TextStyle(
                                                                fontSize: 10.5,
                                                                color:
                                                                    brandBlue)))),
                                              Text(_fmtTime(n.updatedAt),
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .grey.shade500)),
                                            ]),
                                          ])),
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

  // ------------------------------------------------- 备份/恢复（T-125）

  Future<void> _backupToPc() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (db, dir) = await _env();
      final api = await createApiFromPrefs();
      final r = await pushBackup(api: api, db: db, databasesDir: dir);
      await _load();
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: okGreen,
          content: Text('已备份 ${r.pushed} 篇到PC'
              '${r.imagesUploaded > 0 ? '（补传${r.imagesUploaded}图）' : ''}'
              '${r.skippedImages.isNotEmpty ? '，缺本地图${r.skippedImages.length}张' : ''}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('${e.message}——备份需连接PC'),
          backgroundColor: badRed));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('备份失败：$e'), backgroundColor: badRed));
    }
  }

  Future<void> _restoreFromPc() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
            title: const Text('从PC恢复笔记？'),
            content: const Text('本地笔记将被PC端备份整体覆盖'
                '（含笔记图片重新下载）。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('恢复')),
            ]));
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (db, dir) = await _env();
      final api = await createApiFromPrefs();
      final r =
          await pullRestore(api: api, db: db, databasesDir: dir);
      await _load();
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: okGreen,
          content: Text('已恢复 ${r.restored} 篇'
              '（图片${r.imagesDownloaded}张'
              '${r.failedImages.isNotEmpty ? '，失败${r.failedImages.length}' : ''}）')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('${e.message}——恢复需连接PC'), backgroundColor: badRed));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('恢复失败：$e'), backgroundColor: badRed));
    }
  }

  static String _fmtTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
