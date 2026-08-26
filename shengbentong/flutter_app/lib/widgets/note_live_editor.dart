/// NoteLiveEditor — Obsidian 式块级 Live Preview 编辑区（v1.2/T-126b）。
///
/// 光标所在块 = 可编辑源码 TextField（全文档唯一），其余块经现有
/// NoteMarkdownView 管线实时渲染（KaTeX/VSCode 高亮/noteimg 全生效）。
/// 点击渲染块切入编辑；块尾回车新建段落块；失焦自动写回。
/// IME 安全：编辑中的块不因打字重建，仅块切换时更新 TextField 内容。
library;

import 'package:flutter/material.dart';

import '../services/note_block_parser.dart';
import '../services/note_live_editor_controller.dart';
import 'note_markdown.dart';

class NoteLiveEditor extends StatefulWidget {
  final NoteLiveEditorController controller;
  final Map<String, String> imageMap;

  const NoteLiveEditor({super.key, required this.controller,
      this.imageMap = const {}});

  @override
  State<NoteLiveEditor> createState() => _NoteLiveEditorState();
}

class _NoteLiveEditorState extends State<NoteLiveEditor> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _blockCtrl = TextEditingController();
  final FocusNode _editFocus = FocusNode();
  int _lastEditingIndex = -2;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
    _editFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _editFocus.removeListener(_onFocusChange);
    _scroll.dispose();
    _blockCtrl.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  /// 失焦 = 退出编辑态，写回当前块
  void _onFocusChange() {
    if (!_editFocus.hasFocus && widget.controller.isEditing) {
      widget.controller.commit();
    }
  }

  /// 控制器状态 → TextField 同步：块身份变化全量同步；
  /// 同块内由工具栏/撤销引起的值变化也同步（打字场景两者恒等，为无操作）
  void _syncFromController() {
    if (widget.controller.editingIndex != _lastEditingIndex) {
      _lastEditingIndex = widget.controller.editingIndex;
      if (_blockCtrl.text != widget.controller.blockValue.text) {
        _blockCtrl.text = widget.controller.blockValue.text;
      }
      _blockCtrl.selection = widget.controller.blockValue.selection;
      if (widget.controller.isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_editFocus.hasFocus) _editFocus.requestFocus();
        });
      }
      setState(() {});
    } else if (widget.controller.isEditing &&
        _blockCtrl.text != widget.controller.blockValue.text) {
      _blockCtrl.text = widget.controller.blockValue.text;
      _blockCtrl.selection = widget.controller.blockValue.selection;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final blocks = widget.controller.blocks;
          // 末位恒为"虚拟尾块"：文末新段落入口（Obsidian 内容下方点击续写）
          return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: blocks.length + 1,
              itemBuilder: (context, i) {
                if (i == blocks.length) return _buildVirtualTail(i);
                final block = blocks[i];
                final editing = i == widget.controller.editingIndex;
                if (editing) return _buildEditingField();
                return _buildRenderedBlock(i, block);
              });
        });
  }

  Widget _buildVirtualTail(int index) {
    final editing = widget.controller.editingIndex == index;
    if (editing) return _buildEditingField();
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.beginEditVirtual(),
        child: Container(
            key: const Key('live_block_tail'),
            width: double.infinity,
            height: 56,
            alignment: Alignment.centerLeft,
            child: Text('点此继续输入…',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400))));
  }

  Widget _buildEditingField() {
    final isEmpty = _blockCtrl.text.isEmpty;
    return Container(
        key: const Key('live_editing_block'),
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isEmpty)
            // 空块退格键盘无法感知：提供 × 删除（合并到上一块）
            IconButton(
                key: const Key('btn_delete_empty_block'),
                visualDensity: VisualDensity.compact,
                tooltip: '删除本块',
                onPressed: () => widget.controller.deleteEmptyEditingBlock(),
                icon: Icon(Icons.close,
                    size: 16, color: Theme.of(context).colorScheme.error)),
          Expanded(
              child: TextField(
                  controller: _blockCtrl,
                  focusNode: _editFocus,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace',
                      fontSize: 14.5, height: 1.6),
                  decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: isEmpty ? '输入内容，回车分段…' : null,
                      isDense: true),
                  onChanged: (text) =>
                      widget.controller.updateBlockValue(TextEditingValue(
                          text: text,
                          selection: _blockCtrl.selection)))),
        ]));
  }

  Widget _buildRenderedBlock(int index, MdBlock block) {
    if (block.type == MdBlockType.blank) {
      return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.controller.beginEdit(index),
          child: const SizedBox(height: 14, width: double.infinity));
    }
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller.beginEdit(index),
        child: Container(
            key: Key('live_block_$index'),
            constraints: const BoxConstraints(minHeight: 28),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            // 透明装饰使容器自身可命中：空段落渲染高度为0时点击仍落在容器内
            decoration: const BoxDecoration(color: Color(0x00000000)),
            child: NoteMarkdownView(
                contentMd: block.source,
                imageMap: widget.imageMap,
                selectable: false)));
  }
}
