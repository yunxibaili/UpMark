/// NoteLiveEditorController — Live Preview 编辑器核心逻辑（v1.2/T-126b）。
///
/// 源码字符串是唯一事实源；块切分只用于呈现。
/// - 光标所在块（editingIndex）= 可编辑 TextEditingValue，打字过程**不重切分**（中文 IME 安全）
/// - 切换块/收起编辑时才写回并重切分，此时压入撤销快照
/// - **虚拟尾块**：editingIndex == blocks.length 表示"文末新段落"——
///   尾随空块在无损切分下不可表示（尾随空行恒并入前块），故仅在提交时
///   才落为 `\n\n` 分隔（Obsidian/Typora 同款语义）
/// - 纯逻辑无渲染依赖，可直接单测
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'note_block_parser.dart';

class NoteLiveEditorController extends ChangeNotifier {
  String _text;
  List<MdBlock> _blocks;
  int _editingIndex; // -1=无；0..len-1=实块；len=虚拟尾块
  TextEditingValue _blockValue;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  final VoidCallback? _onTextChanged;

  NoteLiveEditorController({required String initialText, this._onTextChanged})
      : _text = normalizeLineBreaks(initialText),
        _blocks = splitBlocks(normalizeLineBreaks(initialText)),
        _editingIndex = -1,
        _blockValue = TextEditingValue.empty {
    // 空文档保证至少一个可编辑空段落块
    if (_blocks.isEmpty) _blocks = [const MdBlock(MdBlockType.paragraph, '')];
  }

  bool get _isVirtual => _editingIndex == _blocks.length;

  /// 合成当前文档文本（编辑中的块用实时值写回）
  String get text {
    if (_editingIndex < 0) return _text;
    if (_isVirtual) {
      final v = _blockValue.text;
      return v.isEmpty ? _text : '$_text\n\n$v';
    }
    final blocks = List<MdBlock>.of(_blocks);
    blocks[_editingIndex] = MdBlock(blocks[_editingIndex].type, _blockValue.text);
    return blocks.map((b) => b.source).join();
  }

  List<MdBlock> get blocks => _blocks;
  int get editingIndex => _editingIndex;
  TextEditingValue get blockValue => _blockValue;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isEditing => _editingIndex >= 0;

  /// 进入某实块的编辑态（点击渲染块时调用）
  void beginEdit(int index) {
    assert(index >= 0 && index < _blocks.length);
    if (_editingIndex == index) return;
    commit(silent: true); // 切块前写回上一块
    _editingIndex = index;
    _blockValue = TextEditingValue(
        text: _blocks[index].source,
        selection: TextSelection.collapsed(
            offset: _blocks[index].source.length));
    notifyListeners();
  }

  /// 进入文末虚拟尾块（点击内容下方空白处）
  void beginEditVirtual() {
    if (_isVirtual) return;
    commit(silent: true);
    _editingIndex = _blocks.length;
    _blockValue = TextEditingValue.empty;
    notifyListeners();
  }

  /// 编辑块打字中：只更新块值，绝不重切分（IME 组合输入安全）。
  /// 例外：非围栏/数学块的**末尾回车** → 转入新段落（Typora 行为）
  void updateBlockValue(TextEditingValue value) {
    if (_editingIndex < 0) return;
    _blockValue = value;
    final enterAtEnd = value.text.endsWith('\n') &&
        value.selection.isCollapsed &&
        value.selection.baseOffset == value.text.length;
    if (enterAtEnd && !_editingFencedOrMath) {
      enterNewParagraphAfterCurrent();
      return;
    }
    notifyListeners();
    _onTextChanged?.call();
  }

  bool get _editingFencedOrMath =>
      !_isVirtual &&
      (_blocks[_editingIndex].type == MdBlockType.fencedCode ||
          _blocks[_editingIndex].type == MdBlockType.mathBlock);

  /// 块尾回车 → 新段落：
  /// 实块：剥掉回车写回（其余块原样），转入虚拟尾块；
  /// 虚拟块已有内容：以 `\n\n` 分隔落为新段，继续保持虚拟尾块
  void enterNewParagraphAfterCurrent() {
    if (_editingIndex < 0) return;
    if (_isVirtual) {
      var v = _blockValue.text;
      if (v.isEmpty) return; // 空虚拟块回车忽略
      if (v.endsWith('\n')) v = v.substring(0, v.length - 1);
      final next = '$_text\n\n$v';
      _undoStack.add(_text);
      _redoStack.clear();
      _text = next;
      _blocks = splitBlocks(next);
      _editingIndex = _blocks.length;
      _blockValue = TextEditingValue.empty;
      notifyListeners();
      _onTextChanged?.call();
      return;
    }
    final ei = _editingIndex;
    var src = _blockValue.text;
    if (src.endsWith('\n')) src = src.substring(0, src.length - 1);
    final blocks = List<MdBlock>.of(_blocks);
    blocks[ei] = MdBlock(blocks[ei].type, src);
    final next = blocks.map((b) => b.source).join();
    _undoStack.add(_text);
    _redoStack.clear();
    _text = next;
    _blocks = splitBlocks(next);
    _editingIndex = _blocks.length; // 转入虚拟尾块
    _blockValue = TextEditingValue.empty;
    notifyListeners();
    _onTextChanged?.call();
  }

  /// 写回当前块并退出编辑态；文本有变化时压撤销快照。
  /// 虚拟尾块为空时直接退出（不产生尾随空行）
  void commit({bool silent = false}) {
    if (_editingIndex < 0) return;
    if (_isVirtual) {
      final v = _blockValue.text;
      if (v.isEmpty) {
        _editingIndex = -1;
        _blockValue = TextEditingValue.empty;
        notifyListeners();
        return;
      }
      final next = '$_text\n\n$v';
      _undoStack.add(_text);
      _redoStack.clear();
      _applyText(next);
      return;
    }
    final blocks = List<MdBlock>.of(_blocks);
    blocks[_editingIndex] = MdBlock(blocks[_editingIndex].type, _blockValue.text);
    _apply(blocks, pushUndo: true);
  }

  /// 删除空编辑块（块首 × 按钮），聚焦合并到上一块
  void deleteEmptyEditingBlock() {
    if (_editingIndex < 0) return;
    if (_blockValue.text.isNotEmpty) return;
    if (_isVirtual) {
      _editingIndex = -1;
      _blockValue = TextEditingValue.empty;
      notifyListeners();
      return;
    }
    final blocks = List<MdBlock>.of(_blocks);
    blocks.removeAt(_editingIndex);
    if (blocks.isEmpty) blocks.add(const MdBlock(MdBlockType.paragraph, ''));
    _apply(blocks, pushUndo: true);
    final target = _editingIndex > 0 ? _editingIndex - 1 : -1;
    _editingIndex = -1;
    _blockValue = TextEditingValue.empty;
    if (target >= 0) beginEdit(target);
    notifyListeners();
  }

  /// 在编辑块光标处插入片段（工具栏）
  void insertSnippet(String snippet) {
    if (_editingIndex < 0) return;
    final sel = _blockValue.selection;
    final base = sel.isValid ? sel.start : _blockValue.text.length;
    final extent = sel.isValid ? sel.end : _blockValue.text.length;
    final text = _blockValue.text.replaceRange(base, extent, snippet);
    _blockValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: base + snippet.length));
    notifyListeners();
    _onTextChanged?.call();
  }

  /// 包裹选区（加粗/行内代码/行内公式）
  void wrapSelection(String prefix, String suffix,
      {String placeholder = ''}) {
    if (_editingIndex < 0) return;
    final sel = _blockValue.selection;
    final text = _blockValue.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final inner = start == end ? placeholder : text.substring(start, end);
    final next = text.replaceRange(start, end, '$prefix$inner$suffix');
    _blockValue = TextEditingValue(
        text: next,
        selection:
            TextSelection.collapsed(offset: start + prefix.length + inner.length));
    notifyListeners();
    _onTextChanged?.call();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_text);
    _applyText(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_text);
    _applyText(_redoStack.removeLast());
  }

  void _apply(List<MdBlock> blocks, {required bool pushUndo}) {
    final next = blocks.map((b) => b.source).join();
    if (pushUndo && next != _text) {
      _undoStack.add(_text);
      _redoStack.clear();
    }
    _applyText(next);
  }

  void _applyText(String next) {
    _text = next;
    _blocks = splitBlocks(next);
    if (_blocks.isEmpty) _blocks = [const MdBlock(MdBlockType.paragraph, '')];
    _editingIndex = -1;
    _blockValue = TextEditingValue.empty;
    notifyListeners();
    _onTextChanged?.call();
  }
}
