/// NoteEditorScreen — 笔记编辑器（v2.2/T-123）。
///
/// MD 源码编辑/预览双 Tab + 工具栏（加粗/行内代码/围栏/$公式$/$$块$/插图）。
/// 直调 DbService 与 note_image_store 持久化（与 SubjectScreen 同风格）；
/// 图片选择经 [pickImage] 注入便于测试（默认 ImagePicker 相册/拍照）。
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/note_image_store.dart';
import '../widgets/note_markdown.dart';

class NoteEditorScreen extends StatefulWidget {
  final DbService db;
  final String databasesDir;

  /// 非 null = 编辑既有笔记；null = 新建（id 自动生成）
  final Note? initial;

  /// 题目笔记绑定（新建题目笔记时传入）
  final int? questionId;

  /// 保存/删除成功后通知调用方刷新列表
  final VoidCallback? onChanged;

  /// 图片选择注入点：返回选中图片的本地路径；null=取消。测试传假实现。
  final Future<String?> Function(ImageSource source)? pickImage;

  const NoteEditorScreen({super.key,
      required this.db,
      required this.databasesDir,
      this.initial,
      this.questionId,
      this.onChanged,
      this.pickImage});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  late final TextEditingController _mdCtrl =
      TextEditingController(text: widget.initial?.contentMd ?? '');
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initial?.title ?? '');
  late final String _noteId = widget.initial?.id ?? newNoteHexId();
  bool get _isQuestionNote =>
      (widget.initial?.questionId ?? widget.questionId) != null;
  bool _dirty = false;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _mdCtrl.addListener(() => _dirty = true);
    _titleCtrl.addListener(() => _dirty = true);
  }

  @override
  void dispose() {
    _tab.dispose();
    _mdCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  int? get _boundQuestionId => widget.initial?.questionId ?? widget.questionId;

  // ---------------------------------------------------------- 文本插入工具

  void _insertAtCursor(String snippet) {
    final sel = _mdCtrl.selection;
    final text = _mdCtrl.text;
    final base = sel.isValid ? sel.start : text.length;
    final extent = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(base, extent, snippet);
    _mdCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: base + snippet.length));
    setState(() => _dirty = true);
  }

  void _wrapSelection(String prefix, String suffix,
      {String placeholder = ''}) {
    final sel = _mdCtrl.selection;
    final text = _mdCtrl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final inner = start == end ? placeholder : text.substring(start, end);
    final next = text.replaceRange(start, end, '$prefix$inner$suffix');
    _mdCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
            offset: start + prefix.length + inner.length));
    setState(() => _dirty = true);
  }

  // ---------------------------------------------------------------- 插图

  Future<void> _pickAndInsertImage() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
                children: [
              ListTile(leading: const Icon(Icons.photo_library),
                  title: const Text('从相册选择'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery)),
              ListTile(leading: const Icon(Icons.camera_alt),
                  title: const Text('拍照'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
            ])));
    if (source == null || !mounted) return;
    try {
      final picker = widget.pickImage ?? _defaultPickImage;
      final path = await picker(source);
      if (path == null || !mounted) return;
      final name = await importNoteImage(widget.databasesDir, path);
      _insertAtCursor('![](noteimg://$name)\n');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插图失败：$e'), backgroundColor: badRed));
    }
  }

  static Future<String?> _defaultPickImage(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return x?.path;
  }

  // ------------------------------------------------------------ 保存与删除

  /// 返回是否实际落库（全空新笔记不落库）
  Future<bool> _save({bool silent = false}) async {
    final content = _mdCtrl.text;
    final title = _titleCtrl.text.trim();
    if (widget.initial == null && content.trim().isEmpty && title.isEmpty) {
      return false;
    }
    try {
      await widget.db.saveNote(
          id: _noteId,
          title: title,
          contentMd: content,
          questionId: _boundQuestionId);
      _dirty = false;
      await _gcLocalImages();
      widget.onChanged?.call();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存'),
                backgroundColor: okGreen, duration: Duration(seconds: 1)));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败：$e'), backgroundColor: badRed));
      }
      return false;
    }
  }

  /// 清理本地无任何存活笔记引用的图片文件
  Future<void> _gcLocalImages() async {
    final refs = <String>{};
    for (final n in await widget.db.allNotes()) {
      refs.addAll(extractNoteImgRefs(n.contentMd));
    }
    await cleanupOrphanNoteImages(widget.databasesDir, refs);
  }

  Future<void> _delete() async {
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
      await widget.db.softDeleteNote(_noteId);
      _deleted = true;
      await _gcLocalImages();
      widget.onChanged?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e'), backgroundColor: badRed));
      }
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_deleted && _dirty) {
          _save(silent: true); // 返回时静默自动保存
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          title: Text(_isQuestionNote ? '题目笔记' : '我的笔记',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
              controller: _tab,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: '编辑', icon: Icon(Icons.edit, size: 18)),
                Tab(text: '预览', icon: Icon(Icons.visibility, size: 18)),
              ]),
          actions: [
            if (widget.initial != null)
              IconButton(icon: const Icon(Icons.delete_outline),
                  tooltip: '删除',
                  onPressed: _delete),
            IconButton(icon: const Icon(Icons.check),
                tooltip: '保存',
                onPressed: () => _save()),
          ],
        ),
        body: Column(children: [
          if (!_isQuestionNote)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: TextField(
                key: const Key('field_note_title'),
                controller: _titleCtrl,
                decoration: const InputDecoration(
                    hintText: '笔记标题',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
          _buildToolbar(),
          Expanded(child: TabBarView(controller: _tab, children: [
            _buildEditPane(),
            _buildPreviewPane(),
          ])),
        ]),
      ),
    );
  }

  Widget _buildToolbar() => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only()),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            IconButton(key: const Key('btn_bold'),
                icon: const Icon(Icons.format_bold), tooltip: '加粗',
                onPressed: () => _wrapSelection('**', '**', placeholder: '重点')),
            IconButton(key: const Key('btn_inline_code'),
                icon: const Icon(Icons.code), tooltip: '行内代码',
                onPressed: () => _wrapSelection('`', '`', placeholder: 'code')),
            IconButton(key: const Key('btn_fence'),
                icon: const Icon(Icons.data_object), tooltip: '代码块',
                onPressed: () => _insertAtCursor('```c\n\n```')),
            IconButton(key: const Key('btn_math'),
                icon: const Text(r'$',
                    style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold)), tooltip: '行内公式',
                onPressed: () => _wrapSelection(r'$', r'$', placeholder: 'x^2')),
            IconButton(key: const Key('btn_math_block'),
                icon: const Text(r'$$',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.bold)), tooltip: '公式块',
                onPressed: () => _insertAtCursor('\n\$\$\n\\frac{1}{2}\n\$\$\n')),
            IconButton(key: const Key('btn_image'),
                icon: const Icon(Icons.image), tooltip: '插图',
                onPressed: _pickAndInsertImage),
          ])));

  Widget _buildEditPane() => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_isQuestionNote)
          Padding(padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.link, size: 14,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('本笔记绑定当前题目，保存后自动备份到PC',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
        Expanded(child: TextField(
            key: const Key('field_note_md'),
            controller: _mdCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5,
                height: 1.5),
            decoration: const InputDecoration(
                hintText: 'Markdown 笔记…\n\n支持 **加粗**、`行内代码`、代码块、'
                    r'$x^2$ 公式、插图',
                border: InputBorder.none))),
      ]));

  Widget _buildPreviewPane() {
    final md = _mdCtrl.text;
    return Container(
        key: const Key('pane_preview'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: md.trim().isEmpty
            ? Center(child: Text('暂无内容',
                style: TextStyle(color: Colors.grey.shade500)))
            : SingleChildScrollView(
                child: FutureBuilder<Map<String, String>>(
                    future:
                        resolveNoteImageMap(widget.databasesDir, md),
                    builder: (context, snap) {
                      return NoteMarkdownView(
                          contentMd: md, imageMap: snap.data ?? const {});
                    })));
  }
}
