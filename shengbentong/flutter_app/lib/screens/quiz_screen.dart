/// 刷题页 —— 纯UI+状态管理，零IO。
/// 题目列表由调用方（ChapterScreen）从DB加载后传入。
/// 这使本页面可在flutter test中用纯内存数据直接测试，无需任何mock。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/quiz_logic.dart';
import '../widgets/rich_text.dart';

class QuizScreen extends StatefulWidget {
  final String title;
  final List<Question> questions;

  /// 初始收藏集合（由调用方从DB查出注入）
  final Set<int> initialFavorites;

  /// 答题回调：调用方负责写 local_progress+sync_queue（本页零IO）
  final void Function(Question q, UserAnswer ua)? onAnswered;

  /// 收藏切换回调：返回切换后的新状态
  final Future<bool> Function(int questionId)? onToggleFavorite;

  /// T-124: 打开当前题目的笔记（null=不显示入口；调用方负责编辑器与落库）
  final Future<void> Function(int questionId)? onOpenNote;

  const QuizScreen(
      {super.key,
      required this.title,
      required this.questions,
      this.initialFavorites = const {},
      this.onAnswered,
      this.onToggleFavorite,
      this.onOpenNote});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<Question> _questions;
  late final Set<int> _favorites;
  final Map<int, UserAnswer> _answers = {};
  final Set<String> _picked = {};
  final TextEditingController _blankCtrl = TextEditingController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _questions = widget.questions;
    _favorites = Set.of(widget.initialFavorites);
  }

  @override
  void dispose() {
    _blankCtrl.dispose();
    super.dispose();
  }

  Question get _q => _questions[_index];
  UserAnswer? get _answerOfQ => _answers[_q.id];
  bool get _isAnswered => _answers.containsKey(_q.id);
  bool get _isFav => _favorites.contains(_q.id);

  void _answer(Object? pick) {
    if (_isAnswered) return;
    final ua = QuizLogic.evaluate(_q, pick);
    setState(() => _answers[_q.id] = ua);
    widget.onAnswered?.call(_q, ua);
  }

  Future<void> _toggleFavorite() async {
    final target = !_isFav;
    setState(() =>
        target ? _favorites.add(_q.id) : _favorites.remove(_q.id));
    final confirmed = await widget.onToggleFavorite?.call(_q.id) ?? target;
    if (mounted && confirmed != _isFav) {
      setState(() =>
          confirmed ? _favorites.add(_q.id) : _favorites.remove(_q.id));
    }
  }

  void _next() => setState(() { _index++; _picked.clear(); _blankCtrl.clear(); });
  void _prev() => setState(() { _index--; _picked.clear(); _blankCtrl.clear(); });

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) return _empty(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title}  ${_index + 1}/${_questions.length}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: brandBlue, foregroundColor: Colors.white,
          actions: [
            if (widget.onOpenNote != null)
              IconButton(
                  tooltip: '本题笔记',
                  onPressed: () => widget.onOpenNote?.call(_q.id),
                  icon: const Icon(Icons.edit_note)),
            IconButton(
                tooltip: _isFav ? '取消收藏' : '收藏本题',
                onPressed: _toggleFavorite,
                icon: Icon(_isFav ? Icons.bookmark : Icons.bookmark_border)),
          ]),
      body: Column(children: [
        LinearProgressIndicator(value: (_index + 1) / _questions.length,
            backgroundColor: Colors.grey.shade200, color: brandBlue),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          _questionCard(),
          const SizedBox(height: 12),
          ..._resultAndExplanation(),
        ])),
        _navBar(),
      ]),
    );
  }

  Widget _empty(BuildContext c) => Scaffold(appBar: AppBar(),
      body: Center(child: Text('本章暂无题目', style: TextStyle(color: Colors.grey))));

  Widget _questionCard() {
    final material = _q.material ?? '';
    return Card(elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_typeChip(), const SizedBox(width: 8)]),
          if (material.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: brandBlue.withValues(alpha: .15))),
              child: SingleChildScrollView(
                  child: Text(material,
                      style: TextStyle(fontSize: 14.5, height: 1.6,
                          color: Colors.grey.shade800)))),
            const SizedBox(height: 12),
          ],
          if ((_q.image ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(width: double.infinity, color: const Color(0xFFFAFBFC),
                    padding: const EdgeInsets.all(8),
                    child: Image.file(File(_q.image!),
                        fit: BoxFit.contain, height: 230,
                        errorBuilder: (_, _, _) =>
                            const SizedBox.shrink()))),
          ],
          const SizedBox(height: 6),
          if (_q.stem.isEmpty)
            Text('（完形填空 第${_q.number}空）',
                style: const TextStyle(fontSize: 16, height: 1.5))
          else
            richText(_q.stem,
                style: const TextStyle(fontSize: 16, height: 1.5)),
        ])));
  }

  Widget _typeChip() {
    final label = switch (_q.type) {
      QuestionType.singleChoice => '单选',
      QuestionType.multipleChoice => '多选',
      QuestionType.judgment => '判断',
      QuestionType.fillBlank => '填空',
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: brandBlue.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(fontSize: 12, color: brandBlue)));
  }

  List<Widget> _resultAndExplanation() {
    final ua = _answerOfQ;
    if (ua == null) return _inputs();

    return [
      Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: ua.isCorrect ? okGreen : badRed, width: 1.5)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ua.isCorrect ? Icons.check_circle : Icons.cancel,
                  color: ua.isCorrect ? okGreen : badRed, size: 22),
              const SizedBox(width: 8),
              Text(ua.isCorrect ? '回答正确' : '回答错误',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                      color: ua.isCorrect ? okGreen : badRed)),
              const Spacer(),
              Text('你的作答：${ua.display}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ]),
            if (_q.type == QuestionType.singleChoice ||
                _q.type == QuestionType.multipleChoice) ...[
              const SizedBox(height: 6),
              Text('正确答案：${_q.answer}', style: const TextStyle(fontSize: 13)),
            ],
            if (_q.type == QuestionType.fillBlank && _q.accepts != null &&
                _q.accepts!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('参考答案：${_q.accepts!.map((b) => b.join('/')).join(' ｜ ')}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ]))),
      Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('【讲解】', style: TextStyle(fontWeight: FontWeight.bold, color: brandBlue)),
            const SizedBox(height: 6),
            if (_q.explanation.isEmpty)
              const Text('（本题暂无解析）',
                  style: TextStyle(fontSize: 14.5, height: 1.55))
            else
              richText(_q.explanation,
                  style: const TextStyle(fontSize: 14.5, height: 1.55)),
          ]))),
    ];
  }

  List<Widget> _inputs() => switch (_q.type) {
      QuestionType.judgment => [
          Row(children: [
            Expanded(child: _judgeBtn(true, Icons.thumb_up, '正确')),
            const SizedBox(width: 12),
            Expanded(child: _judgeBtn(false, Icons.thumb_down, '错误')),
          ])],
      QuestionType.fillBlank => [
          TextField(controller: _blankCtrl, maxLines: 1,
              decoration: InputDecoration(border: const OutlineInputBorder(),
                  hintText: _q.accepts != null && _q.accepts!.length > 1
                      ? '多个空用｜分隔' : '输入答案',
                  suffixIcon: IconButton(icon: const Icon(Icons.send, color: brandBlue),
                      onPressed: () => _answer(_blankCtrl.text.trim())))),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => _answer(_blankCtrl.text.trim()),
                  style: FilledButton.styleFrom(backgroundColor: brandBlue),
                  child: const Text('提交'))),
        ],
      QuestionType.multipleChoice => [
          for (var i = 0; i < _q.options.length; i++)
            _optionTile(String.fromCharCode(65 + i), _q.options[i]),
          const SizedBox(height: 4),
          FilledButton(
              key: const Key('btn_confirm_multi'),
              onPressed: _picked.isEmpty ? null : () => _answer(_picked.toList()),
              style: FilledButton.styleFrom(backgroundColor: brandBlue,
                  minimumSize: const Size.fromHeight(48)),
              child: Text(_picked.isEmpty ? '请选择答案（可多选）' : '确认作答(${_picked.length})')),
        ],
      _ => [for (var i = 0; i < _q.options.length; i++)
             _optionTile(String.fromCharCode(65 + i), _q.options[i])],
    };

  Widget _optionTile(String letter, String content) {
    final isMulti = _q.type == QuestionType.multipleChoice;
    final picked = isMulti && _picked.contains(letter);
    return Padding(padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (_isAnswered) return;
          if (isMulti) {
            setState(() => picked ? _picked.remove(letter) : _picked.add(letter));
          } else {
            _answer(letter);
          }
        },
        child: Container(width: double.infinity, padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              border: Border.all(color: picked ? brandBlue : Colors.grey.shade300, width: 1.4),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            CircleAvatar(radius: 13,
                backgroundColor: picked ? brandBlue : brandBlue.withValues(alpha: .15),
                child: Text(letter, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.bold, color: picked ? Colors.white : brandBlue))),
            const SizedBox(width: 12),
            Expanded(child: richText(content, style: const TextStyle(fontSize: 15))),
            if (picked) const Icon(Icons.check_circle, color: brandBlue, size: 20),
          ]))));
  }

  Widget _judgeBtn(bool value, IconData icon, String label) {
    return FilledButton.tonalIcon(
        onPressed: () => _answer(value),
        style: FilledButton.styleFrom(backgroundColor: Colors.white,
            foregroundColor: brandBlue,
            side: const BorderSide(color: brandBlue, width: 1.3),
            padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: Icon(icon), label: Text(label, style: const TextStyle(fontSize: 16)));
  }

  Widget _navBar() {
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(children: [
        OutlinedButton(key: const Key('btn_prev'),
            onPressed: _index == 0 ? null : _prev, child: const Text('上一题')),
        const Spacer(),
        FilledButton(key: const Key('btn_next'),
            onPressed: _index == _questions.length - 1 ? null : _next,
            style: FilledButton.styleFrom(backgroundColor: brandBlue),
            child: const Text('下一题')),
      ])));
  }
}
