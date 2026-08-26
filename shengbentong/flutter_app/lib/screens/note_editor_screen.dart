/// NoteEditorScreen — 笔记编辑器（v1.2/T-126 Live Preview 重构）。
///
/// Obsidian 式块级所见即所得：光标所在块显示源码，其余实时渲染。
/// AppBar 👁/✏️ 切全文档预览；工具栏贴键盘（撤销重做最前，Obsidian 默认位）；
/// 内联大标题；直调 DbService/note_image_store 持久化。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/note_image_store.dart';
import '../services/note_live_editor_controller.dart';
import '../widgets/note_live_editor.dart';
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

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final NoteLiveEditorController _live = NoteLiveEditorController(
      initialText: widget.initial?.contentMd ?? '');
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initial?.title ?? '');
  late final String _noteId = widget.initial?.id ?? newNoteHexId();
  Map<String, String> _imageMap = const {};
  bool _previewing = false;
  bool _dirty = false;
  bool _deleted = false;

  bool get _isQuestionNote =>
      (widget.initial?.questionId ?? widget.questionId) != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() => _dirty = true);
    _live.addListener(() => _dirty = true);
    _loadImageMap();
  }

  Future<void> _loadImageMap() async {
    final map = await resolveNoteImageMap(
        widget.databasesDir, widget.initial?.contentMd ?? '');
    if (!mounted || map.isEmpty) return;
    setState(() => _imageMap = map);
  }

  @override
  void dispose() {
    _live.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  int? get _boundQuestionId => widget.initial?.questionId ?? widget.questionId;

  // ------------------------------------------------------------ 工具栏动作

  /// 工具栏动作前保证有编辑块：无则进入最后一个块
  void _ensureEditing() {
    if (_previewing) setState(() => _previewing = false);
    if (!_live.isEditing) {
      _live.beginEdit(_live.blocks.length - 1);
    }
  }

  void _wrap(String prefix, String suffix, {String placeholder = ''}) {
    _ensureEditing();
    _live.wrapSelection(prefix, suffix, placeholder: placeholder);
  }

  void _insert(String snippet) {
    _ensureEditing();
    _live.insertSnippet(snippet);
  }

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
      setState(() => _imageMap[name] =
          '${noteImagesDirPath(widget.databasesDir)}'
          '${Platform.pathSeparator}$name');
      _insert('![](noteimg://$name)\n');
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

  void _togglePreview() {
    if (_live.isEditing) _live.commit();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _previewing = !_previewing);
  }

  // ------------------------------------------------------------ 保存与删除

  Future<bool> _save({bool silent = false}) async {
    if (_live.isEditing) _live.commit();
    final content = _live.text;
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
          actions: [
            IconButton(
                key: const Key('btn_toggle_preview'),
                tooltip: _previewing ? '编辑' : '预览',
                onPressed: _togglePreview,
                icon: Icon(_previewing ? Icons.edit_outlined
                    : Icons.visibility_outlined)),
            IconButton(
                key: const Key('btn_save'),
                tooltip: '保存',
                onPressed: () => _save(),
                icon: const Icon(Icons.check)),
            if (widget.initial != null)
              IconButton(
                  key: const Key('btn_delete'),
                  tooltip: '删除',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: Column(children: [
          Expanded(
              child: _previewing ? _buildFullPreview() : _buildLivePane()),
          if (!_previewing) _buildKeyboardToolbar(),
        ]),
      ),
    );
  }

  Widget _buildLivePane() => Column(children: [
        if (!_isQuestionNote)
          TextField(
              key: const Key('field_note_title'),
              controller: _titleCtrl,
              style: const TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700, height: 1.3),
              decoration: const InputDecoration(
                  hintText: '笔记标题',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.fromLTRB(14, 10, 14, 4))),
        Expanded(child: NoteLiveEditor(
            controller: _live, imageMap: _imageMap)),
      ]);

  Widget _buildFullPreview() => Container(
      key: const Key('pane_preview'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _live.text.trim().isEmpty
          ? Center(child: Text('暂无内容',
              style: TextStyle(color: Colors.grey.shade500)))
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  if (!_isQuestionNote && _titleCtrl.text.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(_titleCtrl.text,
                            style: const TextStyle(fontSize: 22,
                                fontWeight: FontWeight.w700))),
                  NoteMarkdownView(
                      contentMd: _live.text, imageMap: _imageMap),
                ])));

  /// 键盘上方工具栏（Obsidian 式）：随键盘滑入滑出，撤销重做最前。
  /// ListenableBuilder 保证撤销/重做可用态随 controller 实时刷新
  Widget _buildKeyboardToolbar() {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
            key: const Key('keyboard_toolbar'),
            width: double.infinity,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                    top: BorderSide(
                        color: Colors.grey.shade300, width: 0.6))),
            child: ListenableBuilder(
                listenable: _live,
                builder: (context, _) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: [
                  IconButton(
                      key: const Key('btn_undo'),
                      tooltip: '撤销',
                      onPressed:
                          _live.canUndo ? () => _live.undo() : null,
                      icon: const Icon(Icons.undo, size: 20)),
                  IconButton(
                      key: const Key('btn_redo'),
                      tooltip: '重做',
                      onPressed:
                          _live.canRedo ? () => _live.redo() : null,
                      icon: const Icon(Icons.redo, size: 20)),
                  const SizedBox(width: 2),
                  _toolBtn(key: 'btn_bold', icon: Icons.format_bold,
                      tip: '加粗',
                      onTap: () => _wrap('**', '**', placeholder: '重点')),
                  _toolBtn(key: 'btn_inline_code', icon: Icons.code,
                      tip: '行内代码',
                      onTap: () => _wrap('`', '`', placeholder: 'code')),
                  _toolBtn(key: 'btn_fence', icon: Icons.data_object,
                      tip: '代码块',
                      onTap: () => _insert('```c\n\n```')),
                  _toolBtn(key: 'btn_math',
                      iconWidget: const Text(r'$',
                          style: TextStyle(fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      tip: '行内公式',
                      onTap: () => _wrap(r'$', r'$', placeholder: 'x^2')),
                  _toolBtn(key: 'btn_math_block',
                      iconWidget: const Text(r'$$',
                          style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      tip: '公式块',
                      onTap: () =>
                          _insert('\n\$\$\n\\frac{1}{2}\n\$\$\n')),
                  _toolBtn(key: 'btn_image', icon: Icons.image,
                      tip: '插图', onTap: _pickAndInsertImage),
                  const SizedBox(width: 2),
                  IconButton(
                      key: const Key('btn_hide_keyboard'),
                      tooltip: '收起键盘',
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      icon: const Icon(Icons.keyboard_hide, size: 20)),
                ]),
              ),
            ),
          ),
        );
  }

  Widget _toolBtn({required String key, IconData? icon, Widget? iconWidget,
      required String tip, required VoidCallback onTap}) =>
      IconButton(
          key: Key(key),
          tooltip: tip,
          onPressed: onTap,
          icon: iconWidget ?? Icon(icon, size: 20));
}
