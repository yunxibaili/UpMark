/// 刷题页：四题型作答 → 即时判分（绿/红）→ 讲解展开 → 上/下题导航 → 进度落库
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/db_service.dart';
import '../services/quiz_logic.dart';

class QuizScreen extends StatefulWidget {
  final int chapterId;
  final String title;
  const QuizScreen({super.key, required this.chapterId, required this.title});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  DbService? _db;
  final List<Question> _questions = [];
  final Map<int, UserAnswer> _answers = {};   // qid -> 用户作答
  final Set<String> _picked = {};             // 多选题已勾选字母
  int _index = 0;
  bool _loading = true;

  final _blankCtrl = TextEditingController();

  Question get _q => _questions[_index];
  UserAnswer? get _answerOfQ => _answers[_q.id];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 复用最近打开的实例（测试种子连接），避免同路径句柄被关闭的边界情况
    final db = DbService.lastOpened ?? await DbService.open();
    _db = db;
    final rows = await db.rawQuestionsOf(widget.chapterId);
    final progress = await db.progressMapOf(rows.map((r) => r['id'] as int).toList());
    for (final row in rows) {
      final q = Question.fromRow(row);
      _questions.add(q);
      final p = progress[q.id];
      if (p != null) {
        final correct = (p['is_correct'] as int? ?? 0) == 1;
        // 已答过的题恢复为已答状态（显示上次对错；答案不回填，鼓励重做）
        _answers[q.id] = UserAnswer(display: correct ? '✓' : '✗', isCorrect: correct);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _emptyBody() => Scaffold(
      appBar: _appBar(),
      body: const Center(
          child: Text('本章暂无题目',
              style: TextStyle(color: Colors.grey))));

  void _answer(Object? pick) {
    if (_answerOfQ != null) return;                 // 已答锁定
    final ua = QuizLogic.evaluate(_q, pick);
    setState(() => _answers[_q.id] = ua);
    _db?.saveProgress(questionId: _q.id, isCorrect: ua.isCorrect);
  }

  void _submitBlank() => _answer(_blankCtrl.text.trim());

  @override
  void dispose() {
    _blankCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: _appBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_questions.isEmpty) return _emptyBody();
    return Scaffold(
      appBar: _appBar(),
      body: Column(children: [
        LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            backgroundColor: Colors.grey.shade200, color: brandBlue),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          _buildQuestionCard(),
          const SizedBox(height: 12),
          ..._buildResultAndExplanation(),
        ])),
        _buildNavBar(),
      ]),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
      title: Text('${widget.title}  ${_index + 1}/${_questions.length}'),
      backgroundColor: brandBlue, foregroundColor: Colors.white);

  Widget _buildQuestionCard() {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _typeChip(),
            const SizedBox(width: 8),
            if ((_q.material ?? '').isNotEmpty)
              const Tooltip(message: '本题含材料', child:
                  Icon(Icons.article_outlined, size: 18, color: brandBlue)),
          ]),
          if ((_q.material ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FC),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_q.material!,
                  style: const TextStyle(fontSize: 13.5, height: 1.5)),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Text(_q.stem.isEmpty ? '（完形填空：为材料中第${_q.number}空选择最佳答案）'
                  : _q.stem,
              style: const TextStyle(fontSize: 16, height: 1.5)),
        ]),
      ),
    );
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

  List<Widget> _buildResultAndExplanation() {
    final ua = _answerOfQ;
    if (ua == null) return _buildInputs();

    final correctLetter = switch (_q.type) {
      QuestionType.judgment => null,
      QuestionType.fillBlank => null,
      _ => _q.answer,
    };

    return [
      Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: ua.isCorrect ? okGreen : badRed, width: 1.5)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(ua.isCorrect ? Icons.check_circle : Icons.cancel,
                  color: ua.isCorrect ? okGreen : badRed),
              const SizedBox(width: 8),
              Text(ua.isCorrect ? '回答正确' : '回答错误',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 16, color: ua.isCorrect ? okGreen : badRed)),
              if (_q.type == QuestionType.multipleChoice && _answerOfQ == null && _picked.isNotEmpty) 
          FilledButton(onPressed: () => _answer(_picked.toList()),
              style: FilledButton.styleFrom(backgroundColor: brandBlue),
              child: Text('确认作答()')) else
          FilledButton(key: const Key('btn_next'), onPressed: _index == _questions.length - 1 ? null :
              () => setState(() { _index++; _blankCtrl.clear(); _picked.clear(); }),
              style: FilledButton.styleFrom(backgroundColor: brandBlue),
              child: const Text('下一题')),
              Text('你的作答：${ua.display}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ]),
            if (_q.type == QuestionType.multipleChoice ||
                _q.type == QuestionType.singleChoice) ...[
              const SizedBox(height: 6),
              Text('正确答案：${correctLetter!}',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (_q.type == QuestionType.fillBlank &&
                _q.accepts != null && _q.accepts!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('参考答案：${_q.accepts!.map((b) => b.join('/')).join(' ｜ ')}',
                  style: const TextStyle(fontSize: 13)),
            ],
          ]))),
      Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('【讲解】', style: TextStyle(fontWeight: FontWeight.bold,
                color: brandBlue)),
            const SizedBox(height: 6),
            Text(_q.explanation.isEmpty ? '（本题暂无解析）' : _q.explanation,
                style: const TextStyle(fontSize: 14.5, height: 1.55)),
          ]))),
    ];
  }

  List<Widget> _buildInputs() {
    return switch (_q.type) {
      QuestionType.judgment => [
          Row(children: [
            Expanded(child: _judgeButton(true, Icons.thumb_up, '正确')),
            const SizedBox(width: 12),
            Expanded(child: _judgeButton(false, Icons.thumb_down, '错误')),
          ]),
        ],
      QuestionType.fillBlank => [
          TextField(controller: _blankCtrl,
              maxLines: 1,
              decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: _q.accepts != null && _q.accepts!.length > 1
                      ? '多个空用｜分隔'
                      : '输入答案',
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: brandBlue),
                      onPressed: _submitBlank))),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _submitBlank,
                  style: FilledButton.styleFrom(backgroundColor: brandBlue),
                  child: const Text('提交'))),
        ],
      _ => [for (var i = 0; i < _q.options.length; i++)
             _optionTile(String.fromCharCode(65 + i), _q.options[i])],
    };
  }

  Widget _optionTile(String letter, String content) {
    final isMulti = _q.type == QuestionType.multipleChoice;
    final picked = isMulti && _picked.contains(letter);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(borderRadius: BorderRadius.circular(9),
        onTap: () {
          if (_answerOfQ != null) return;
          if (isMulti) {
            setState(() => picked ? _picked.remove(letter)
                                  : _picked.add(letter));
          } else {
            _answer(letter);
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              border: Border.all(
                  color: picked ? brandBlue : Colors.grey.shade300, width: 1.4),
              borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            CircleAvatar(radius: 13,
                backgroundColor: picked ? brandBlue : brandBlue.withValues(alpha: .15),
                child: Text(letter, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: picked ? Colors.white : brandBlue))),
            const SizedBox(width: 12),
            Expanded(child: Text(content, style: const TextStyle(fontSize: 15))),
            if (picked) const Icon(Icons.check_circle, color: brandBlue, size: 20),
          ]))));
  }

  Widget _judgeButton(bool value, IconData icon, String label) {
    return FilledButton.tonalIcon(
        key: value ? const Key('btn_judge_true') : const Key('btn_judge_false'),
        onPressed: () => _answer(value),
        style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: brandBlue,
            side: const BorderSide(color: brandBlue, width: 1.3),
            padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: Icon(icon), label: Text(label, style: const TextStyle(fontSize: 16)));
  }

  Widget _buildNavBar() {
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Row(children: [
        OutlinedButton(key: const Key('btn_prev'), onPressed: _index == 0 ? null : () => setState(() { _index--; _blankCtrl.clear(); }),
            child: const Text('上一题')),
        if (_q.type == QuestionType.multipleChoice && _answerOfQ == null && _picked.isNotEmpty) 
          FilledButton(onPressed: () => _answer(_picked.toList()),
              style: FilledButton.styleFrom(backgroundColor: brandBlue),
              child: Text('确认作答()')) else
          FilledButton(key: const Key('btn_next'), onPressed: _index == _questions.length - 1 ? null :
              () => setState(() { _index++; _blankCtrl.clear(); _picked.clear(); }),
              style: FilledButton.styleFrom(backgroundColor: brandBlue),
              child: const Text('下一题')),
        FilledButton(key: const Key('btn_next'), onPressed: _index == _questions.length - 1 ? null :
            () => setState(() { _index++; _blankCtrl.clear(); _picked.clear(); }),
            style: FilledButton.styleFrom(backgroundColor: brandBlue),
            child: const Text('下一题')),
      ])));
  }
}
