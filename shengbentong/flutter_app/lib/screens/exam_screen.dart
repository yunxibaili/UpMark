/// 模拟考试 —— 限时组卷作答，交卷后统一判分（T-106 标准版）。
/// 纯UI+回调：题目由调用方抽取传入，交卷经 onSubmit 交回调用方落库。
/// 考试语义：不即时判分、无收藏；超时自动交卷；未作答按错误计分但不入错题本。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/quiz_logic.dart';
import '../widgets/rich_text.dart';

/// 一次交卷的完整作答：qid -> pick（'A' / ['A','B'] / bool / 填空字符串）
typedef ExamPicks = Map<int, Object?>;

class ExamScreen extends StatefulWidget {
  final String title;
  final List<Question> questions;
  final int durationMinutes;
  final void Function(ExamPicks picks) onSubmit;

  const ExamScreen(
      {super.key,
      required this.title,
      required this.questions,
      required this.durationMinutes,
      required this.onSubmit});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late int _remaining;
  Timer? _timer;
  final Map<int, Object?> _picks = {};
  final Set<String> _multi = {};
  int _index = 0;
  bool _submitted = false;
  final TextEditingController _blankCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _submit(auto: true);
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blankCtrl.dispose();
    super.dispose();
  }

  Question get _q => widget.questions[_index];
  bool get _answered => _picks.containsKey(_q.id);

  void _submit({bool auto = false}) {
    if (_submitted) return;
    _submitted = true;
    _timer?.cancel();
    final unanswered = widget.questions.length - _picks.length;
    if (!auto && unanswered > 0) {
      showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
              title: const Text('确认交卷？'),
              content: Text('还有 $unanswered 题未作答，交卷后未作答按错误计分。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('继续作答')),
                FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _finish();
                    },
                    child: const Text('确认交卷')),
              ]));
      return;
    }
    _finish();
  }

  void _finish() {
    widget.onSubmit(Map.of(_picks));
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ExamResultScreen(
            title: widget.title,
            questions: widget.questions,
            picks: Map.of(_picks))));
  }

  String get _clock =>
      '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}';

  void _pickOption(String letter) {
    final q = _q;
    setState(() {
      if (q.type == QuestionType.multipleChoice) {
        _multi.contains(letter) ? _multi.remove(letter) : _multi.add(letter);
      } else {
        _picks[q.id] = letter;
        _next();
      }
    });
  }

  void _next() {
    _blankCtrl.clear();
    if (_index < widget.questions.length - 1) setState(() => _index++);
  }

  void _prev() {
    _blankCtrl.clear();
    if (_index > 0) setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _remaining < 60;
    return PopScope(
        canPop: false,
        child: Scaffold(
            appBar: AppBar(
                leading: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '交卷后退出',
                    onPressed: () => _submit()),
                title: Text('$_clock  第${_index + 1}/${widget.questions.length}题',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: urgent ? Colors.orangeAccent : Colors.white)),
                backgroundColor: brandBlue,
                foregroundColor: urgent ? Colors.orangeAccent : Colors.white,
                actions: [
                  IconButton(
                      tooltip: '答题卡',
                      onPressed: _showCard,
                      icon: const Icon(Icons.grid_view)),
                  TextButton(
                      onPressed: () => _submit(),
                      child: const Text('交卷',
                          style: TextStyle(color: Colors.white))),
                ]),
            body: Column(children: [
              LinearProgressIndicator(
                  value: (_index + 1) / widget.questions.length,
                  backgroundColor: Colors.grey.shade200,
                  color: brandBlue),
              Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
                _questionCard(),
                const SizedBox(height: 12),
                ..._inputs(),
              ])),
              _navBar(),
            ])));
  }

  Widget _questionCard() {
    final q = _q;
    return Card(
        elevation: 1.5,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: brandBlue.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(
                        switch (q.type) {
                          QuestionType.singleChoice => '单选',
                          QuestionType.multipleChoice => '多选',
                          QuestionType.judgment => '判断',
                          QuestionType.fillBlank => '填空',
                        },
                        style: const TextStyle(
                            fontSize: 12, color: brandBlue))),
                const SizedBox(width: 8),
                if (_answered)
                  const Text('已作答',
                      style: TextStyle(fontSize: 12, color: Colors.green)),
              ]),
              const SizedBox(height: 10),
              richText(q.stem, style: const TextStyle(fontSize: 16, height: 1.5)),
            ])));
  }

  List<Widget> _inputs() => switch (_q.type) {
        QuestionType.judgment => [
            Row(children: [
              Expanded(child: _judgeBtn(true, '正确')),
              const SizedBox(width: 12),
              Expanded(child: _judgeBtn(false, '错误')),
            ])
          ],
        QuestionType.fillBlank => [
            TextField(
                controller: _blankCtrl,
                maxLines: 1,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '输入答案',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.send, color: brandBlue),
                        onPressed: _saveBlank))),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: _saveBlank,
                    style: FilledButton.styleFrom(backgroundColor: brandBlue),
                    child: const Text('记答案'))),
          ],
        QuestionType.multipleChoice => [
            for (var i = 0; i < _q.options.length; i++)
              _optionTile(String.fromCharCode(65 + i), _q.options[i]),
            const SizedBox(height: 4),
            FilledButton(
                onPressed: _multi.isEmpty
                    ? null
                    : () {
                        setState(() => _picks[_q.id] = ([..._multi]..sort()).join());
                        _next();
                      },
                style: FilledButton.styleFrom(
                    backgroundColor: brandBlue,
                    minimumSize: const Size.fromHeight(48)),
                child: Text(_multi.isEmpty
                    ? '请选择答案（可多选）'
                    : '确认本题（${[..._multi].join()}）')),
          ],
        _ => [
            for (var i = 0; i < _q.options.length; i++)
              _optionTile(String.fromCharCode(65 + i), _q.options[i])
          ],
      };

  void _saveBlank() {
    final v = _blankCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() => _picks[_q.id] = v);
    _next();
  }

  Widget _optionTile(String letter, String content) {
    final picked = _q.type == QuestionType.multipleChoice
        ? _multi.contains(letter)
        : _picks[_q.id] == letter;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _pickOption(letter),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    border: Border.all(
                        color: picked ? brandBlue : Colors.grey.shade300,
                        width: 1.4),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  CircleAvatar(
                      radius: 13,
                      backgroundColor: picked
                          ? brandBlue
                          : brandBlue.withValues(alpha: .15),
                      child: Text(letter,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: picked ? Colors.white : brandBlue))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: richText(content,
                          style: const TextStyle(fontSize: 15))),
                ]))));
  }

  Widget _judgeBtn(bool value, String label) {
    final picked = _picks[_q.id] == value;
    return FilledButton.tonalIcon(
        onPressed: () => setState(() => _picks[_q.id] = value),
        style: FilledButton.styleFrom(
            backgroundColor: picked ? brandBlue : Colors.white,
            foregroundColor: picked ? Colors.white : brandBlue,
            side: const BorderSide(color: brandBlue, width: 1.3),
            padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: Icon(value ? Icons.thumb_up : Icons.thumb_down),
        label: Text(label, style: const TextStyle(fontSize: 16)));
  }

  Widget _navBar() {
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(children: [
              OutlinedButton(
                  onPressed: _index == 0 ? null : _prev,
                  child: const Text('上一题')),
              const Spacer(),
              OutlinedButton(
                  onPressed: _showCard, child: const Text('答题卡')),
              const SizedBox(width: 10),
              FilledButton(
                  onPressed: _index == widget.questions.length - 1
                      ? () => _submit()
                      : _next,
                  style: FilledButton.styleFrom(backgroundColor: brandBlue),
                  child: Text(_index == widget.questions.length - 1
                      ? '交卷'
                      : '下一题')),
            ])));
  }

  void _showCard() {
    showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('答题卡',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8, childAspectRatio: 1),
                      itemCount: widget.questions.length,
                      itemBuilder: (_, i) {
                        final q = widget.questions[i];
                        final answered = _picks.containsKey(q.id);
                        return Padding(
                            padding: const EdgeInsets.all(4),
                            child: InkWell(
                                onTap: () {
                                  setState(() => _index = i);
                                  Navigator.pop(context);
                                },
                                child: CircleAvatar(
                                    backgroundColor: answered
                                        ? brandBlue
                                        : Colors.grey.shade200,
                                    child: Text('${i + 1}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: answered
                                                ? Colors.white
                                                : Colors.black54)))));
                      }),
                ]))));
  }
}

/// 考试结果页：得分总览 + 逐题回顾（含讲解）
class ExamResultScreen extends StatelessWidget {
  final String title;
  final List<Question> questions;
  final ExamPicks picks;

  const ExamResultScreen(
      {super.key,
      required this.title,
      required this.questions,
      required this.picks});

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final q in questions)
        picks.containsKey(q.id)
            ? QuizLogic.evaluate(q, picks[q.id])
            : const UserAnswer(display: '未作答', isCorrect: false)
    ];
    final correct = results.where((r) => r.isCorrect).length;
    final pct = questions.isEmpty ? 0.0 : correct / questions.length * 100;
    return Scaffold(
        appBar: AppBar(
            title: Text('$title · 成绩',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: brandBlue, foregroundColor: Colors.white),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Text('${pct.toStringAsFixed(1)}分',
                        style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: pct >= 60 ? okGreen : badRed)),
                    const SizedBox(height: 6),
                    Text('共 ${questions.length} 题 · 答对 $correct · 答错 ${questions.length - correct}',
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    const Text('错题已记入错题本，进度可在「我的统计」上传PC',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ]))),
          const SizedBox(height: 8),
          for (var i = 0; i < questions.length; i++) _review(i, results[i]),
        ]));
  }

  Widget _review(int i, UserAnswer r) {
    final q = questions[i];
    final answerText = switch (q.type) {
      QuestionType.fillBlank =>
        (q.accepts != null && q.accepts!.isNotEmpty)
            ? q.accepts!.map((b) => b.join('/')).join(' ｜ ')
            : q.answer,
      _ => q.answer,
    };
    return Card(
        elevation: 1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Icon(r.isCorrect ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: r.isCorrect ? okGreen : badRed),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('第${i + 1}题  你的作答：${r.display}',
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 6),
              richText('正确答案：$answerText',
                  style: const TextStyle(fontSize: 13)),
              if (q.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                richText(q.explanation,
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ])));
  }
}
